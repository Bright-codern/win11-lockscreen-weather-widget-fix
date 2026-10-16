# 交接文档 · Windows 11 锁屏天气小组件修复

| 项目 | 内容 |
|---|---|
| **项目名** | `win11-lockscreen-weather-widget-fix` |
| **交接日期** | 2026-10-16 |
| **文档版本** | v1.0 |
| **当前状态** | ✅ 修复方案已验证有效；仓库内容已完成；**未推送到 GitHub** |
| **接手需知** | 见 [第 4 节 技术核心](#4-技术核心接手必读)，这是全篇最重要的一节 |

---

## 1. 项目概述

### 1.1 起因

Windows 11 用户（本机）遇到问题：

> **设置 → 个性化 → 锁屏界面 → 小组件 → 添加小组件** 里，
> 「天气」的「添加小组件」按钮是**灰色不可点**，锁屏界面上也看不到天气。
> 同一目录下「比赛项目」「提示」等却可以正常添加。

### 1.2 一句话价值

这是 Windows 11 25H2/26H2 的一个**真实存在的系统缺陷**。微软官方问答帖（#6021021，2026-09-30 提问）
在提问者逐项尝试了官方给的方案后仍未解决，2026-10-09 官方给出的变通建议是
"新建一个 Windows 用户配置文件并把数据迁移过去"。
本项目找到了**真正的状态存储位置**，用一条脚本即可修复，**无需重建账户**。

### 1.3 为什么值得开源

- 网上所有"重置小组件 / 重命名 LocalState"的方案**全部无效**，但没有一篇说明为什么
- 微软官方问答帖（#6021021）至今未解决，提问者已按官方建议逐项尝试，全部无效
- 问题跨版本存在（25H2 → 26H2 依旧），短期内不会自行消失
- 搜索量大、竞争者为零，属于**高价值长尾内容**

---

## 2. 当前状态与完成度

| 阶段 | 内容 | 状态 |
|---|---|---|
| 问题定位 | 找到根因（`LockState` 而非 `LocalState`） | ✅ 完成 |
| 方案验证 | 在本机实测修复成功 | ✅ 完成 |
| 脚本编写 | `Fix-LockScreenWeatherWidget.ps1`（三模式） | ✅ 完成，已通过语法检查与实跑 |
| 中文 README | `README.md` | ✅ 完成 |
| 英文 README | `README.en.md` | ✅ 完成 |
| 排查记录 | `docs/INVESTIGATION.md` | ✅ 完成 |
| 交接文档 | `HANDOVER.md`（本文） | ✅ 完成 |
| **推送到 GitHub** | 建仓 + push | ⬜ **未做，需接手方完成** |
| 打 Release | `v1.0.0` tag | ⬜ 未做 |
| 社区运营 | Issue 回复、扩散 | ⬜ 未做 |

> ⚠️ **接手第一件事**：本机**没有安装 Git**。推送前需要先安装
> <https://git-scm.com/download/win>（或用 GitHub Desktop），
> 然后按 [第 10.4 节](#104-推送到-github) 的命令推送。

---

## 3. 交付物清单

仓库根目录：`%USERPROFILE%\Documents\默认项目\lockscreen-weather-widget-fix\`

| 文件 | 体积 | 说明 | 面向读者 |
|---|---|---|---|
| `README.md` | ~9 KB | 中文主文档：症状 / 根因 / 方案 / 用法 / 无效方案清单 | 最终用户 |
| `README.en.md` | ~10 KB | 英文版，便于国际用户搜索到 | 最终用户 |
| `docs/INVESTIGATION.md` | ~14 KB | **完整排查链 + 原始证据**，可证伪 | 技术接手方 |
| `HANDOVER.md` | 本文 | 交接说明 | 接手方 |
| `scripts/Fix-LockScreenWeatherWidget.ps1` | ~14 KB | 主脚本，三模式 | 最终用户 |
| `LICENSE` | 1 KB | MIT | — |
| `.gitignore` | 0.2 KB | — | — |

### 3.1 脚本的三种模式

```powershell
# 只读诊断（不改任何东西）—— 建议所有 Issue 都先要这个输出
.\scripts\Fix-LockScreenWeatherWidget.ps1 -Diagnose

# 执行修复（默认行为，无需 -Fix 也可以，参数集默认值即 Fix）
.\scripts\Fix-LockScreenWeatherWidget.ps1

# 从最近一次备份回滚
.\scripts\Fix-LockScreenWeatherWidget.ps1 -Restore
```

**技术约束（改动时请遵守）**：

- **不需要管理员权限** —— 全部操作限定在 `HKCU` 与当前用户的包数据目录。不要引入需要提权的操作。
- **文件必须是 `UTF-8 with BOM`** —— PowerShell 5.1 读 UTF-8 无 BOM 的中文会乱码并导致**语法错误**。
  如果你用编辑器重存过脚本，务必确认 BOM 还在，否则重跑：
  ```powershell
  $p = '.\scripts\Fix-LockScreenWeatherWidget.ps1'
  $b = [IO.File]::ReadAllBytes($p)
  if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
      [IO.File]::WriteAllBytes($p, [byte[]](0xEF,0xBB,0xBF) + $b)
      '已补 BOM'
  }
  ```
- **参数集**：`Fix`（默认）/ `Diagnose` / `Restore`，靠 `$PSCmdlet.ParameterSetName` 分发。

---

## 4. 技术核心（接手必读）

### 4.1 问题本质

灰色按钮**不是**"禁用"，而是微软定义的"**该小组件已经添加过了**"
（出处：微软支持文档《在 Windows 中自定义锁屏界面》）。

也就是说：**Windows 认为天气已经在锁屏上了，但锁屏上实际没有。**
记录状态 ≠ 渲染状态 —— 这就是整个 bug。

### 4.2 状态存在哪（全篇最关键的一句）

```
%LOCALAPPDATA%\Packages\Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe\
├── Settings\settings.dat   ← ★ LockState / RoamingState 在这里（锁屏小组件状态）
└── LocalState\             ← WidgetSessions / FeedSessions（小组件实例数据）

%LOCALAPPDATA%\Packages\MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy\
└── Settings\settings.dat   ← WIDGET_PINS_CONTAINER（小组件板 Win+W 的固定项）
```

**`Settings\settings.dat` 与 `LocalState\` 是 ApplicationData 里两个互相独立的容器。**
重置（重命名/删除）`LocalState` **完全不会**影响 `Settings\settings.dat`。

### 4.3 为什么网上所有方案都无效

| 网上流传的方案 | 实际动的东西 | 为什么无效 |
|---|---|---|
| 重置 Windows Web Experience Pack | `LocalState` | 清的是版块数据，不是锁屏状态 |
| 重命名 `WebExperience\LocalState` | `LocalState` | 同上；且找错了包 |
| 在小组件板里删掉天气再加回 | 版块固定项 | 版块 ≠ 锁屏 |
| 关闭/打开位置服务 | 无关 | — |
| 干净启动 / sfc / 就地重装 | 无关 | 状态在用户数据里，重装系统文件不影响 |
| 新建用户配置文件 | 换了一套全新状态 | **有效，但代价极大** ← 微软给的最终建议 |

**根因一句话**：所有方案都绕开了 `WidgetsPlatformRuntime\Settings\settings.dat`。

### 4.4 修复做了什么

1. 结束 `WidgetBoard` / `WidgetService` 进程（释放文件占用）
2. **移走** `WidgetsPlatformRuntime\Settings\settings.dat` ← 清 `LockState`（**决定性一步**）
3. **移走** `WidgetsPlatformRuntime\LocalState` ← 清 `WidgetSessions`（含幽灵实例）
4. 删除锁屏注册表的 6 个迁移标记
5. 置 `LockScreenWidgetsSystemCurationEnabled = 1`、`LockScreenWidgetsEnabled = 1`（允许系统重新预置天气）
6. 删除 `Lock Screen` 下空的 `FeedManager` 子键（由系统重新生成）
7. **重启**（必须选「重启」，不要「关机」再开机）

### 4.5 一个必须知道的红鲱鱼

`HKCU\Software\Microsoft\Windows\CurrentVersion\Lock Screen` 下的：

```
HasLockCanvasRemovedPreplacedWidgets                       = 1
HasLockCanvasWithRecommendationsMigratedFromLockCanvasV1   = 1
```

**它们不是病因**。实测：删掉 → 重启 → 系统重跑迁移 → **它们又长回来了**，
但问题**已经修复**。

👉 **接手方千万不要在 README 或回复里把它们说成根因**，否则会误导别人。
修复后这两个值**依然是 1**，这是正常的。

### 4.6 旁证：幽灵实例

故障时 `WidgetSessions` 各小组件的实例文件数 vs 可添加性：

| 小组件 | 实例数 | 可添加 |
|---|---|---|
| 天气 / 关注列表 / 每日发现 / 今日精彩瞬间 | **2** ⚠️ | ❌ |
| 比赛项目 | 1 | ✅ |
| 提示 | 0 | ✅ |

**实例数 > 1 的全部加不了**，相关性完美。
修复后天气变回 1 个。

> 注：此表是**故障现场**的快照。修复后重新统计时，
> 部分小组件（如关注列表、每日发现）可能已经不在 `WidgetSessions` 里了 —— 这是正常的。

---

## 5. 尚未完成 / 待办（TODO）

### 5.1 必做

- [ ] **装 Git 并推送到 GitHub**（见 [10.4](#104-推送到-github)）
- [ ] 确认仓库描述与 Topics（建议值见 [10.5](#105-建议的仓库信息)）
- [ ] 打 `v1.0.0` tag 并写 Release Notes
- [ ] 在微软 Q&A 帖 [#6021021](https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray)
      下回复本方案（**这是最快的曝光渠道**，帖子里有 3 个人标记了同样问题）

### 5.2 可选增强

- [ ] 英文版 `INVESTIGATION.md`（`docs/INVESTIGATION.en.md`）
- [ ] GitHub Actions：用 `PSScriptAnalyzer` 做静态检查 + 语法检查（防止 BOM 丢失）
- [ ] 把失败的 v1 方案（只清注册表）留档到 `scripts/archive/`，作为反例
- [ ] 支持 `-BackupRoot` 自定义路径（**已实现**，参数已存在）
- [ ] 增加"修复后自动校验"步骤：
      重启后跑 `-Diagnose`，检查 `WidgetSessions` 里各组件实例数是否都为 1

### 5.3 明确不做的

- ❌ 不申请管理员权限
- ❌ 不修改系统文件、不重装系统
- ❌ 不动 `WebExperience` 的 `LocalState`（已验证无效，且会丢失版块个性化）

---

## 6. 不确定性与风险（务必如实告知用户）

### 6.1 技术上的不确定性

**无法 100% 确定**是以下哪一项起到了决定性作用：

- (a) 清 `settings.dat`（`LockState`）
- (b) 清 `LocalState`（`WidgetSessions`）
- (c) 两者组合
- (d) 连续两轮重启的累积效应

因为 v2 是一次性做完这几步的。但**这不影响可用性**：

- v1（只清注册表）→ **失败**
- v2（v1 + 清这两个容器）→ **成功**

差异点明确，且 v2 可重复执行、可回滚。
**如果要对外表述，请用"实测组合生效"，不要断言单一原因。**

### 6.2 使用风险

| 风险 | 程度 | 缓解 |
|---|---|---|
| 小组件板（`Win+W`）个性化丢失 | 低 | 脚本只清 `WidgetsPlatformRuntime`，理论上不动版块固定项；但用户可能仍需重新加载小组件 |
| 注册表误改 | 低 | 全自动备份到 `%USERPROFILE%\lockscreen-widget-backup\`，`-Restore` 可回滚 |
| 微软后续版本改了存储结构 | 中 | 见 [第 7 节](#7-维护指南)，需按 `-Diagnose` 输出重新定位 |
| 在其他 Windows 版本上误用 | 中 | README 已限定 25H2/26H2；脚本 `-Diagnose` 会让用户先确认 `settings.dat` 存在 |

### 6.3 合规与免责

- 本项目**非微软官方修复**，README 已含免责声明
- 仓库内容已检查：**无个人隐私信息**（无邮箱、无用户名；路径统一用 `%LOCALAPPDATA%` / `%USERPROFILE%` 占位）
  - 2026-10-16 复查发现 `docs/INVESTIGATION.md` 第 2 节曾写入真实微软账户邮箱，已改为匿名表述
- 唯一涉及个人环境的是「复现环境」表格里的"账户类型：微软账户（MSA）"
  —— 这条对读者有诊断价值，**如需更保守可删除**

---

## 7. 维护指南

### 7.1 收到 Issue 时的标准动作

1. 让用户跑 `-Diagnose` 并把**完整输出**贴上来
2. 看三件事：
   - Windows 版本 / build 是否在 25H2–26H2 范围
   - `Settings\settings.dat` **是否存在**
     - 存在 → 适用本方案，让用户跑修复
     - 不存在 → 已被清过，或结构变了，需进一步排查
   - `WidgetSessions` 里**天气的实例数**是否 > 1
3. 若修复无效，问清楚：
   - 有没有**选「重启」**而不是「关机再开机」
   - 跑脚本前有没有**结束所有 Widgets 进程**（文件被占用会导致 `settings.dat` 移不走）
   - `settings.dat` 是否**真的被移走了**

### 7.2 微软改了结构怎么办

症状可能是脚本找不到 `settings.dat`，或移动后问题不解决。排查方法：

```powershell
# 1. 看包数据目录有没有新文件/新容器
Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe" -Recurse -Depth 2 |
    Select-Object FullName, Length, LastWriteTime
```

```powershell
# 2. 直接在所有候选 settings.dat 里找 LockState（先结束 Widgets 进程释放占用）
$pkgs = 'Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe',
        'MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy',
        'Microsoft.StartExperiencesApp_8wekyb3d8bbwe'
foreach ($p in $pkgs) {
    $src = "$env:LOCALAPPDATA\Packages\$p\Settings\settings.dat"
    if (-not (Test-Path $src)) { "$p : 无 settings.dat"; continue }
    $dst = "$env:TEMP\$p-settings.dat"
    $fs = [IO.File]::Open($src,'Open','Read','ReadWrite')
    $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $fs.Close()
    [IO.File]::WriteAllBytes($dst, $ms.ToArray()); $ms.Close()
    $b = [IO.File]::ReadAllBytes($dst)
    "--- $p ---"
    # 注意：键名在文件里是字节序颠倒的，直接按 Unicode 读会乱码，
    # 把每个 UTF-16 字符的两个字节交换回来即可得到真实键名
    $sw = [byte[]]::new($b.Length)
    for ($i=0; $i -lt $b.Length-1; $i+=2) { $sw[$i]=$b[$i+1]; $sw[$i+1]=$b[$i] }
    ([regex]::Matches([Text.Encoding]::Unicode.GetString($sw),'[\x20-\x7E]{4,}') |
        ForEach-Object { $_.Value } | Sort-Object -Unique) -join ', '
}
```

找到 `LockState` 落在哪个包里，就清哪个包的 `Settings\settings.dat`。

### 7.3 关键概念备忘

| 概念 | 含义 |
|---|---|
| `LockState` | **锁屏**小组件的固定记录。病因所在 |
| `WIDGET_PINS_CONTAINER` | **版块（Win+W）**的固定记录 |
| `WidgetSessions` | 每个小组件实例的会话/缓存数据，一个 `.dat` 一个实例 |
| `HasLockCanvasRemovedPreplacedWidgets` | 迁移副产物，**非病因** |
| `LockScreenWidgetsSystemCurationEnabled` | 是否允许系统自动策展锁屏小组件；置 1 有助于天气自动回归 |

---

## 8. 验证与测试方法

### 8.1 复现原问题（用于验证方案有效性）

需要一台**未修复**的 25H2/26H2 机器，且锁屏天气处于"卡死"状态。
可用 `-Diagnose` 判断：`Settings\settings.dat` 存在 + 目录里天气按钮为灰。

### 8.2 验证修复有效

```powershell
# 修复 + 重启后
.\scripts\Fix-LockScreenWeatherWidget.ps1 -Diagnose
```

期望看到：

- `Settings\settings.dat` : **不存在**
- `WidgetSessions` 里每个小组件实例数 = **1**
- 锁屏上出现天气卡片（`Win + L` 验证）

### 8.3 验证回滚有效

```powershell
.\scripts\Fix-LockScreenWeatherWidget.ps1 -Restore
# 重启后 settings.dat 应重新出现，且值回到修复前
```

### 8.4 脚本改动的回归检查清单

每次改脚本后必跑：

```powershell
$p = '.\scripts\Fix-LockScreenWeatherWidget.ps1'
# 1) BOM 检查
$b = [IO.File]::ReadAllBytes($p)
"BOM: " + ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
# 2) 语法检查
$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $p), [ref]$null, [ref]$e)
"语法错误数: " + $e.Count
# 3) 参数集
(Get-Command $p).ParameterSets.Name
# 4) 实跑诊断模式（只读，安全）
powershell -ExecutionPolicy Bypass -File $p -Diagnose
```

---

## 9. 关键路径速查

| 名称 | 路径 |
|---|---|
| 仓库根目录 | `%USERPROFILE%\Documents\默认项目\lockscreen-weather-widget-fix\` |
| 主脚本 | `.\scripts\Fix-LockScreenWeatherWidget.ps1` |
| 用户侧备份目录 | `%USERPROFILE%\lockscreen-widget-backup\<时间戳>\` |
| 被清理的包数据 | `%LOCALAPPDATA%\Packages\Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe\{Settings\settings.dat, LocalState\}` |
| 被修改的注册表 | `HKCU\Software\Microsoft\Windows\CurrentVersion\Lock Screen` |

---

## 10. 操作手册

### 10.1 诊断

```powershell
cd "$env:USERPROFILE\Documents\默认项目\lockscreen-weather-widget-fix"
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1 -Diagnose
```

### 10.2 修复

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1
# 然后必须「重启」
```

### 10.3 回滚

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1 -Restore
```

### 10.4 推送到 GitHub

> 前置：先安装 Git <https://git-scm.com/download/win>（本机目前**没有**）

```powershell
cd "$env:USERPROFILE\Documents\默认项目\lockscreen-weather-widget-fix"

git init
git add .
git commit -m "fix: Windows 11 锁屏天气小组件无法添加（添加按钮灰色不可点）"
git branch -M main

# 先在 GitHub 上建一个空仓库（不要勾选 README/.gitignore/License）
git remote add origin https://github.com/<用户名>/<仓库名>.git
git push -u origin main

# 打 tag
git tag -a v1.0.0 -m "v1.0.0 首个可用版本"
git push origin v1.0.0
```

### 10.5 建议的仓库信息

| 项目 | 建议 |
|---|---|
| 仓库名 | `win11-lockscreen-weather-widget-fix` |
| 描述（英文，利于搜索） | Fix Windows 11 lock screen weather widget: greyed-out "Add widget" button (25H2/26H2). Resets the stale `LockState` in WidgetsPlatformRuntime — which every "reset LocalState" guide misses. |
| Topics | `windows-11` `bug-fix` `powershell` `widgets` `lock-screen` `windows-11-25h2` `windows-11-26h2` |
| Release | `v1.0.0`，附上 README 的「已确认无效的方案」表格 |

### 10.6 建议的曝光渠道

1. **微软 Q&A #6021021** —— 在帖子里回复方案（最高优先级，精准命中）
2. elevenforum 的 `Cannot Add Lock Screen Weather Widget Windows 11 25H2` 帖
3. Reddit：`r/Windows11`、`r/WindowsHelp`
4. 中文社区：V2EX、NGA、B站/知乎（可选）
5. 微软 Feedback Hub 提交反馈，附本仓库链接

---

## 11. 参考资料

| 资料 | 链接 |
|---|---|
| 微软支持 · 在 Windows 中自定义锁屏界面（"灰色=已添加"的出处） | <https://support.microsoft.com/zh-cn/windows/experience/personalization/customize-the-lock-screen-in-windows> |
| **微软 Q&A #6021021**（完全同症状，13 天未解决） | <https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray> |
| Windows IT Pro Blog · Configuring "weather and more" on the lock screen | <https://techcommunity.microsoft.com/blog/windows-itpro-blog/configuring-weather-and-more-on-the-lock-screen-in-windows/4101024> |
| Windows Latest · 微软简化锁屏小组件 | <https://www.windowslatest.com/2026/09/17/microsoft-turned-windows-11s-lock-screen-into-msn-hell-now-its-undoing-most-of-it> |
| elevenforum · Add and Remove Widgets on Lock Screen | <https://www.elevenforum.com/t/add-and-remove-widgets-on-lock-screen-in-windows-11.33141> |

---

## 12. 交接确认清单

接手方请逐项确认：

- [ ] 已通读 [第 4 节 技术核心](#4-技术核心接手必读)
- [ ] 已理解 `Settings\settings.dat` 与 `LocalState` 是**两个独立容器**
- [ ] 已知道 `HasLockCanvasRemovedPreplacedWidgets` 是**红鲱鱼**，不可对外说成根因
- [ ] 已知道脚本**必须保持 UTF-8 with BOM**
- [ ] 已能在本机独立跑通 `-Diagnose` / 修复 / `-Restore`
- [ ] 已知悉 [第 6 节](#6-不确定性与风险务必如实告知用户) 的不确定性与风险
- [ ] 已知悉推送前需要先安装 Git
- [ ] 已确认仓库中无个人隐私信息

---

**文档结束** · 如需补充请直接修改本文件并更新顶部的「文档版本」与「交接日期」
