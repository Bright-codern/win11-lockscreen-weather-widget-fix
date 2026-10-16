# 修复 Windows 11 锁屏「天气」小组件无法添加

[English](README.en.md) · 中文

> **TL;DR (English)** — On Windows 11 25H2/26H2, the Weather widget's **Add** button on
> *Settings → Personalization → Lock screen → Widgets* is greyed out even though the widget is
> **not** on the lock screen. The stale "already pinned" state lives in
> `Microsoft.WidgetsPlatformRuntime` → `Settings\settings.dat` → **`LockState`** — *not* in
> `LocalState`, which is why every "reset the Widgets data / LocalState" guide fails.
> This repo clears that state. [Jump to the fix ↓](#-使用方法)

---

## 📌 症状

Windows 11 **25H2 / 26H2**，在
**设置 → 个性化 → 锁屏界面 → 小组件 → 添加小组件** 目录中：

- ✅ 「比赛项目」「提示」等小组件可以正常添加
- ❌ **「天气」的「添加小组件」按钮是灰色，点不了**
- 锁屏界面上也**看不到**天气卡片
- `Win + W` 小组件板里的天气**是正常的**
- 位置服务已开启、地区/语言正确、任务栏小组件开关已打开

---

## 🔍 根因

### 1. 灰按钮的含义

关于这个按钮为什么变灰，**微软官方文档并没有直接写明**。
官方文档（[在 Windows 中自定义锁屏界面](https://support.microsoft.com/zh-cn/windows/experience/personalization/customize-the-lock-screen-in-windows)）
里只说到"目前，只有支持小尺寸的小组件才能添加到锁屏界面"这一条限制；
而天气是锁屏的默认卡片，必然支持小尺寸，所以官方文档解释不了本问题。

"灰 = 已添加"这个判定，来自 elevenforum 的锁屏小组件教程：

> **If the `+ Add widget` button is grayed out, then the widget has already been added.**

> 📌 **出处说明**：上面这句话**不是微软官方原文**。本仓库于 2026-10-16 复核了微软中英文支持文档，
> 两份中都**没有**"灰色 / 已添加"的表述。这条规则属于社区经验，
> 但它与故障现象完全吻合（判定过程与另一可能原因"不支持小尺寸"的排除，见 `docs/INVESTIGATION.md` 第 3 节）。

所以"天气"按钮变灰 = **系统认为天气已经在锁屏上了** —— 但锁屏上其实什么都没有。
这就是**状态与实际不一致**。

### 2. 状态存在哪里（关键）

`%LOCALAPPDATA%\Packages\Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe\` 下有两个**互相独立**的数据容器：

```
Settings\settings.dat   <-- 存 RoamingState / LockState    ★ 锁屏小组件状态在这里
LocalState\             <-- 存 WidgetSessions / FeedSessions（小组件实例数据）
```

用十六进制 dump 实测确认，`settings.dat` 里包含这些键名：

```
RoamingState
LockState          ← 锁屏小组件的固定记录
```

而 `MicrosoftWindows.Client.WebExperience` 的 `settings.dat` 里存的才是**小组件板（Win+W）**的固定项：

```
WIDGET_PINS_CONTAINER
WIDGET_PINS_MIGRATED_CONTAINER
RichCalendarSD,medium,rail,1|SportsMatch,medium,rail,2|WeatherSummary,medium,rail,0
```

> **这就是为什么网上所有方案都失败**：
> 大家重置的都是 `LocalState`（甚至 `-HardReset` 也只是把 `LocalState` 改名），
> **而 `LockState` 在 `Settings\settings.dat` 里，重置 `LocalState` 根本碰不到它。**

### 3. 一个会误导人的红鲱鱼

注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Lock Screen` 里的这两个值：

```
HasLockCanvasRemovedPreplacedWidgets                       = 1
HasLockCanvasWithRecommendationsMigratedFromLockCanvasV1   = 1
```

看起来非常像病因（"预置的小组件被移除了！"），**但它们不是**。

实测：清除它们 → 重启 → 系统重新跑一次迁移 → **它们又长回来了**，而且即使长回来，问题也已经修复了。
它们是迁移逻辑的正常副产物，**清不清都一样**。

### 4. 旁证：幽灵实例

故障时，`WidgetSessions` 下各小组件的实例文件数与该组件"能否添加"高度相关：

| 小组件 | 实例文件数 | 目录里能否添加 |
|---|---|---|
| 天气 Weather | **2** ⚠️ | ❌ 灰色 |
| 关注列表 Finance | **2** ⚠️ | ❌ 灰色 |
| 每日发现 DailyDiscovery | **2** ⚠️ | ❌ 灰色 |
| 今日精彩瞬间 TodaysMoment | **2** ⚠️ | ❌ 灰色 |
| 比赛项目 Sports | **1** | ✅ 可添加 |
| 提示 Tips | **0** | ✅ 可添加 |

即：**实例文件数 > 1 的全部加不了**。推测多出来的那个就是"幽灵实例"，
让目录误判为"已经添加过"。修复后天气的实例数变回 1。

---

## 🛠 解决方案

### 核心动作

1. 结束所有 Widgets 进程（释放文件占用）
2. **移走** `WidgetsPlatformRuntime\Settings\settings.dat` ← 清除 `LockState`（**关键**）
3. **移走** `WidgetsPlatformRuntime\LocalState` ← 清除 `WidgetSessions`
4. 清除锁屏注册表里的迁移标记
5. 置 `LockScreenWidgetsSystemCurationEnabled = 1`、`LockScreenWidgetsEnabled = 1`，让系统重新把天气预置回锁屏
6. 删除 `Lock Screen` 下空的 `FeedManager` 子键（由系统重新生成）
7. **重启电脑**（必须选「重启」，不要「关机」再开机）

### 为什么这样就行了

清掉 `LockState` 后，系统重新跑一遍"预置小组件"流程时，不会再把天气当成"重复项"剔除，
于是天气被正常放回锁屏画布；同时目录里的添加按钮也就不再被置灰。

---

## 🚀 使用方法

### 前置要求

- Windows 11 25H2 / 26H2（其他版本可先跑 `-Diagnose` 确认结构一致）
- **不需要管理员权限**（全部是 HKCU 与用户级包数据）
- PowerShell 5.1 及以上

### 1. 先诊断（只读，不改任何东西）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1 -Diagnose
```

会打印：系统版本、Web Experience Pack 版本、锁屏注册表全部值、
`settings.dat` / `LocalState` 是否存在、天气的 WidgetSession 实例。

**判断标准**：若 `Settings\settings.dat` 存在 → 适用本方案。

### 2. 执行修复

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1
```

脚本会自动备份到 `%USERPROFILE%\lockscreen-widget-backup\<时间戳>\`，
内容为 `settings.dat` + `LocalState` + `LockScreen.reg`。

### 3. 重启电脑

> ⚠️ **必须选「重启 / Restart」**，不要「关机」再开机。
> Windows 快速启动会跳过部分初始化流程。

### 4. 验证

| 看到什么 | 结论 |
|---|---|
| 锁屏底部出现天气卡片 | ✅ 修复成功（系统自动预置回来了） |
| 天气在「你的小组件」列表里，按钮仍是灰色 | ✅ **也算修复成功** —— 灰 = 已添加 |
| 列表里仍然没有天气、按钮仍然灰色 | ❌ 未生效，请提 Issue 并附上 `-Diagnose` 输出 |

### 反悔

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1 -Restore
```

---

## ❌ 已确认无效的方案（别浪费时间了）

以下方案**已实测无效**。除"只清注册表"一项为本机 v1 复现外，其余各项来自
[微软官方问答帖 #6021021](https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray)
中提问者的实测记录（对应关系见 `docs/INVESTIGATION.md` 第 2、4 节）：

| 方案 | 结果 |
|---|---|
| 设置 → 隐私和安全性 → 位置：关掉 → 重启 → 打开 | ❌ |
| 在 `Win+W` 小组件板里移除天气再加回来 | ❌ |
| 重置 Windows Web Experience Pack（高级选项 → 重置） | ❌ |
| **重命名 `WebExperience` 的 `LocalState` 文件夹** | ❌ ← 最常被推荐的方案，但清错了地方 |
| 干净启动（msconfig 禁用全部非微软服务） | ❌ |
| `sfc /scannow` | ❌ |
| 就地升级重装系统（保留个人文件和应用） | ❌ |
| 检查组策略 `Disable Widgets On Lock Screen` | 本来就是 Not Configured |
| 清除锁屏注册表的迁移标记（只做这一步） | ❌ **单独做无效，必须配合清 `LockState`** |

微软官方问答在折腾了 **13 天**后给出的最终建议是：
> "作为变通方法，你可以考虑新建一个 Windows 用户配置文件并把数据迁移过去。"

**本仓库的方案就是为了避免走到这一步。**

---

## 🧪 复现环境

| 项目 | 值 |
|---|---|
| Windows | 11 **26H2**，build **26300.9711** |
| 版本类型 | 正式版 |
| Windows 功能体验包 | `1000.26100.372.0` |
| Windows Web Experience Pack | `526.21100.40.0` |
| Widgets Platform Runtime | `1.6.19.0` |
| Microsoft.StartExperiencesApp | `1.398.2.0` |
| 区域 / 语言 | 中国 / zh-CN |
| 账户类型 | 微软账户（MSA） |

同症状也见于：
- Windows 11 25H2（`26200.x`），**升级到 26H2 后依然存在**
- [Microsoft Q&A #6021021 — *Weather lock-screen widget Add button remains grayed out in Windows 11 26H2*](https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray)

---

## 📂 仓库结构

```
.
├── README.md                                  ← 你在这里（中文）
├── README.en.md                               ← English version
├── HANDOVER.md                                ← 交接文档（技术细节 / 维护指南 / 待办）
├── LICENSE                                    ← MIT
├── scripts/
│   └── Fix-LockScreenWeatherWidget.ps1        ← 主脚本（-Diagnose / 默认修复 / -Restore）
└── docs/
    └── INVESTIGATION.md                       ← 完整排查过程与原始证据
```

---

## ⚠️ 免责声明

- 本方案为社区经验总结，**非微软官方修复**。
- 脚本会**移动**你的小组件相关数据文件并**修改** HKCU 下的锁屏注册表项。
  脚本已内置备份与 `-Restore`，但请自行确认风险后再使用。
- 副作用：小组件板（`Win+W`）上的小组件可能需要重新加载或重新固定一次。

## 📄 许可

MIT
