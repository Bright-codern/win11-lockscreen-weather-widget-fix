<#
.SYNOPSIS
    修复 Windows 11 锁屏「天气」小组件无法添加（"添加"按钮灰色不可点）的问题。

.DESCRIPTION
    【症状】
      设置 > 个性化 > 锁屏界面 > 小组件 > 「添加小组件」目录中，
      "天气"的添加按钮为灰色不可点，锁屏上也看不到天气。
      同一个目录里，部分小组件（如"比赛项目""提示"）却可以正常添加。

    【根因】
      锁屏小组件的"已固定 / 已添加"状态保存在
      Microsoft.WidgetsPlatformRuntime 包数据容器的
      Settings\settings.dat 的 LockState 键中。

      注意：它不在 LocalState 里！Settings\settings.dat 和 LocalState
      是 ApplicationData 里两个互相独立的数据容器，重置 LocalState
      不会清除 LockState —— 这正是网上大量"重置小组件无效"的原因。

      当 LockState 中的记录与实际锁屏画布不一致时，系统会认为
      天气"已经添加过了"，于是把目录里的添加按钮置灰，
      但锁屏上其实什么都没有。

    【本脚本做的事】
      1. 备份（settings.dat / LocalState / 注册表）
      2. 结束 Widgets 相关进程，释放文件占用
      3. 移走 WidgetsPlatformRuntime\Settings\settings.dat （含 LockState）
      4. 移走 WidgetsPlatformRuntime\LocalState            （含 WidgetSessions）
      5. 清除锁屏注册表中的陈旧迁移标记
      6. 置 LockScreenWidgetsSystemCurationEnabled = 1，让系统重新预置天气
      7. 提示重启（必须选「重启」，不要「关机」再开机）

.PARAMETER Diagnose
    只读模式：仅输出当前状态与诊断结论，不做任何修改。

.PARAMETER Restore
    从最近一次备份恢复全部改动。

.PARAMETER BackupRoot
    备份根目录。默认 %USERPROFILE%\lockscreen-widget-backup

.EXAMPLE
    # 先看看当前是什么情况（不改任何东西）
    .\Fix-LockScreenWeatherWidget.ps1 -Diagnose

.EXAMPLE
    # 执行修复
    .\Fix-LockScreenWeatherWidget.ps1

.EXAMPLE
    # 反悔
    .\Fix-LockScreenWeatherWidget.ps1 -Restore

.NOTES
    无需管理员权限（全部为 HKCU 与用户级包数据）。
    执行修复后必须重启电脑生效。
    本脚本按"原样"提供，请自行确认风险后再使用。
#>

[CmdletBinding(DefaultParameterSetName = 'Fix')]
param(
    [Parameter(ParameterSetName = 'Diagnose')]
    [switch]$Diagnose,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Fix')]
    [switch]$Fix,

    [string]$BackupRoot = (Join-Path $env:USERPROFILE 'lockscreen-widget-backup')
)

$ErrorActionPreference = 'Continue'
try { $OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ----------------------------------------------------------------- 常量
$PackageName   = 'Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe'
$PackageRoot   = Join-Path $env:LOCALAPPDATA "Packages\$PackageName"
$TargetSettings= Join-Path $PackageRoot 'Settings\settings.dat'
$TargetLocal   = Join-Path $PackageRoot 'LocalState'
$LockScreenKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen'
$Stamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir     = Join-Path $BackupRoot $Stamp

# 在迁移过程中会被反复重写的标记。删除它们只是为了让系统重新跑一次预置逻辑，
# 它们本身不是病因（修复后它们会自己再长回来，属正常现象）。
$StaleFlags = @(
    'HasLockCanvasRemovedPreplacedWidgets'
    'PreplacedWidgetsAttempted'
    'HasLockCanvasWithRecommendationsMigratedFromLockCanvasV1'
    'HasLockCanvasWithRecommendationsMigratedFromDetailedStatus'
    'AutoSelectWidgetsOnLockScreen'
    'TileMigrated'
)

# ----------------------------------------------------------------- 输出helper
function Write-Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Write-Warn2($t){ Write-Host "  [!]    $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "  [X]    $t" -ForegroundColor Red }
function Write-Info($t) { Write-Host "         $t" }

function Get-WidgetProcess {
    Get-Process -Name 'WidgetBoard','WidgetService','Widgets' -ErrorAction SilentlyContinue
}

function Stop-WidgetProcess {
    $procs = Get-WidgetProcess
    if (-not $procs) { Write-Info '没有正在运行的 Widgets 进程'; return $true }
    foreach ($p in $procs) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Write-Info "已结束 $($p.Name) (PID $($p.Id))" }
        catch { Write-Warn2 "结束 $($p.Name) 失败: $($_.Exception.Message)" }
    }
    Start-Sleep -Seconds 3
    return -not (Get-WidgetProcess)
}

# ----------------------------------------------------------------- 诊断
function Invoke-Diagnose {
    Write-Head '环境'
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Info "Windows : $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion)  (build $($os.BuildNumber).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR))"
    Write-Info "启动时间: $($os.LastBootUpTime)"
    $wep = Get-AppxPackage -Name MicrosoftWindows.Client.WebExperience -ErrorAction SilentlyContinue
    if ($wep) { Write-Info "Web Experience Pack: $($wep.Version)" } else { Write-Warn2 'Web Experience Pack 未安装' }

    Write-Head '锁屏小组件注册表'
    if (Test-Path $LockScreenKey) {
        (Get-ItemProperty $LockScreenKey).PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { Write-Info ("{0,-58} {1}" -f $_.Name, ($_.Value -join ',')) }
    } else { Write-Err "找不到 $LockScreenKey" }

    Write-Head 'WidgetsPlatformRuntime 包数据'
    Write-Info "包目录            : $PackageRoot"
    Write-Info "Settings\settings.dat : $(if (Test-Path $TargetSettings) { '存在  <-- LockState 在这里' } else { '不存在' })"
    Write-Info "LocalState            : $(if (Test-Path $TargetLocal) { '存在' } else { '不存在' })"

    $sess = Join-Path $TargetLocal 'WidgetSessions'
    if (Test-Path $sess) {
        Write-Info 'WidgetSessions 各小组件的实例文件数'
        Write-Info '  正常情况每个小组件 = 1 个实例；'
        Write-Info '  若「天气」多于 1 个而其他都是 1 个，即为幽灵实例特征'
        Write-Info '  （记录于故障现场：天气/关注列表/每日发现/今日精彩瞬间 各 2 个，'
        Write-Info '    比赛项目 1 个、提示 0 个 —— 恰好只有后两者可以添加。）'
        Get-ChildItem $sess -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $n = @(Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue).Count
            $mark = if ($n -gt 1 -and $_.Name -match 'Weather') { '  <-- 可疑' } else { '' }
            Write-Info ("  {0,-62} {1}{2}" -f $_.Name, $n, $mark)
        }
    }

    Write-Head '结论'
    $hasSettings = Test-Path $TargetSettings
    Write-Info "Settings\settings.dat 存在 : $hasSettings"
    if ($hasSettings) {
        Write-Info '=> 适用本修复方案。'
    } else {
        Write-Info '=> settings.dat 已被清除过。若天气仍加不上，可再跑一次修复或提 Issue。'
    }
    Write-Info '在"添加小组件"目录中，按钮为灰色 = 系统认为该小组件已添加（微软官方定义）。'
}

# ----------------------------------------------------------------- 备份
function New-Backup {
    Write-Head '备份'
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Info "备份目录: $BackupDir"

    if (Test-Path $TargetSettings) {
        try { Copy-Item $TargetSettings (Join-Path $BackupDir 'settings.dat') -Force -ErrorAction Stop
              Write-Ok 'settings.dat 已备份' }
        catch { Write-Warn2 "settings.dat 备份失败（可能被占用）: $($_.Exception.Message)" }
    }
    if (Test-Path $TargetLocal) {
        try { Copy-Item $TargetLocal (Join-Path $BackupDir 'LocalState') -Recurse -Force -ErrorAction Stop
              Write-Ok 'LocalState 已备份' }
        catch { Write-Warn2 "LocalState 备份失败: $($_.Exception.Message)" }
    }
    $reg = Join-Path $BackupDir 'LockScreen.reg'
    reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Lock Screen' "$reg" /y | Out-Null
    if (Test-Path $reg) { Write-Ok 'Lock Screen 注册表已备份' } else { Write-Warn2 '注册表备份失败' }
}

# ----------------------------------------------------------------- 修复
function Invoke-Fix {
    Write-Head '0. 环境'
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Info "Windows : $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion) (build $($os.BuildNumber))"
    $wep = Get-AppxPackage -Name MicrosoftWindows.Client.WebExperience -ErrorAction SilentlyContinue
    if ($wep) { Write-Info "Web Experience Pack: $($wep.Version)" }

    New-Backup

    Write-Head '1. 结束 Widgets 进程'
    [void](Stop-WidgetProcess)

    Write-Head '2. 清除 LockState（关键）'
    if (Test-Path $TargetSettings) {
        try {
            Move-Item $TargetSettings (Join-Path $BackupDir 'settings.dat.removed') -Force -ErrorAction Stop
            Write-Ok 'settings.dat 已移走 —— LockState（锁屏小组件状态）已清除'
        } catch {
            Write-Err "移动失败，文件仍被占用: $($_.Exception.Message)"
            Write-Info '请在任务管理器结束所有「小组件 / Widgets」进程后重跑本脚本。'
        }
    } else {
        Write-Info 'settings.dat 不存在（可能已清除过）'
    }

    Write-Head '3. 清除 WidgetSessions'
    if (Test-Path $TargetLocal) {
        try {
            Move-Item $TargetLocal (Join-Path $BackupDir 'LocalState.removed') -Force -ErrorAction Stop
            Write-Ok 'LocalState 已移走 —— WidgetSessions / FeedSessions 已清除'
        } catch {
            Write-Warn2 "移动失败: $($_.Exception.Message)"
        }
    } else {
        Write-Info 'LocalState 不存在'
    }

    Write-Head '4. 清除锁屏注册表陈旧标记'
    foreach ($name in $StaleFlags) {
        $v = (Get-ItemProperty $LockScreenKey -Name $name -ErrorAction SilentlyContinue).$name
        if ($null -ne $v) {
            Remove-ItemProperty -Path $LockScreenKey -Name $name -ErrorAction SilentlyContinue
            Write-Info "删除 $name (原值 $v)"
        } else {
            Write-Info "$name 不存在"
        }
    }
    Set-ItemProperty -Path $LockScreenKey -Name 'LockScreenWidgetsSystemCurationEnabled' -Value 1 -Type DWord
    Write-Ok 'LockScreenWidgetsSystemCurationEnabled = 1（允许系统重新预置天气）'
    Set-ItemProperty -Path $LockScreenKey -Name 'LockScreenWidgetsEnabled' -Value 1 -Type DWord
    Write-Ok 'LockScreenWidgetsEnabled = 1'

    $fm = Join-Path $LockScreenKey 'FeedManager'
    if (Test-Path $fm) {
        Remove-Item $fm -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok 'FeedManager 子键已删除（由系统重新生成）'
    }

    Write-Head '5. 修复后状态'
    (Get-ItemProperty $LockScreenKey).PSObject.Properties |
        Where-Object { $_.Name -notlike 'PS*' } |
        ForEach-Object { Write-Info ("{0,-58} {1}" -f $_.Name, ($_.Value -join ',')) }

    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Green
    Write-Host ' 下一步：必须重启电脑！' -ForegroundColor Yellow
    Write-Host '   请选「重启 / Restart」，不要「关机」再开机' -ForegroundColor Yellow
    Write-Host '   （快速启动会让虚拟化/小组件相关的初始化被跳过）' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ' 重启后验证：设置 > 个性化 > 锁屏界面 > 小组件' -ForegroundColor Yellow
    Write-Host '   若天气出现在列表里、且按钮仍是灰色 => 修复成功' -ForegroundColor Yellow
    Write-Host '   （灰色 = 已添加，这是正常状态）' -ForegroundColor Yellow
    Write-Host ('=' * 60) -ForegroundColor Green
    Write-Host " 备份: $BackupDir"
    Write-Host " 反悔: .\Fix-LockScreenWeatherWidget.ps1 -Restore"
}

# ----------------------------------------------------------------- 恢复
function Invoke-Restore {
    Write-Head '恢复模式'
    if (-not (Test-Path $BackupRoot)) { Write-Err "找不到备份根目录: $BackupRoot"; return }
    $latest = Get-ChildItem $BackupRoot -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { Write-Err '没有可用备份'; return }
    Write-Info "使用备份: $($latest.FullName)"

    [void](Stop-WidgetProcess)

    $bakSettings = Join-Path $latest.FullName 'settings.dat'
    if (Test-Path $bakSettings) {
        Remove-Item $TargetSettings -Force -ErrorAction SilentlyContinue
        Copy-Item $bakSettings $TargetSettings -Force
        Write-Ok 'settings.dat 已恢复'
    }
    $bakLocal = Join-Path $latest.FullName 'LocalState'
    if (Test-Path $bakLocal) {
        Remove-Item $TargetLocal -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item $bakLocal $TargetLocal -Recurse -Force
        Write-Ok 'LocalState 已恢复'
    }
    $bakReg = Join-Path $latest.FullName 'LockScreen.reg'
    if (Test-Path $bakReg) {
        reg.exe import "$bakReg" | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'Lock Screen 注册表已恢复' } else { Write-Warn2 '注册表恢复失败' }
    }
    Write-Host "`n请重启电脑生效。" -ForegroundColor Yellow
}

# ----------------------------------------------------------------- 分发
switch ($PSCmdlet.ParameterSetName) {
    'Diagnose' { Invoke-Diagnose }
    'Restore'  { Invoke-Restore }
    default    { Invoke-Fix }
}
