# 排查全过程与原始证据

本文记录从"现象"到"根因"的完整推理链，以及每一步的原始数据。
保留这些是为了让方案**可证伪**，而不是"某个人说这样能好"。

---

## 1. 初始现象

用户报告：**Win11 锁屏小组件里加不了天气**。

设置 → 个性化 → 锁屏界面 → 小组件 → 添加小组件，目录中有 9 项：

```
Microsoft.Clipchamp        今日精彩瞬间        休闲游戏
关注列表                   天气                必应上的热点
提示                       每日发现            比赛项目
```

其中只有 **比赛项目** 和 **提示** 可以添加，「天气」等按钮为灰色。

---

## 2. 第一轮：排除常见原因

| 检查项 | 结果 | 结论 |
|---|---|---|
| 组策略 `HKLM/HKCU\SOFTWARE\Policies\Microsoft\Dsh` | 不存在 | 没被策略禁用 |
| `PolicyManager\...\NewsAndInterests` | 不存在 | 没被 MDM 禁用 |
| 任务栏小组件 `TaskbarDa` | `1` | 开着 |
| 锁屏小组件 `LockScreenWidgetsEnabled` | `1` | 开着 |
| 位置服务（HKLM + HKCU ConsentStore\location） | `Allow` / `Allow` | 开着 |
| 域 / Azure AD 加入状态 | 全部 `NO` | 无企业策略 |
| 网络到 `widgets.microsoft.com` / `msn.cn` | 可达 | 不是网络问题 |
| 微软账户登录 | 是（微软账户 / MSA） | 已登录 MSA |

**结论**：不是策略、不是网络、不是设置开关的问题。

---

## 3. 第二轮：找出灰色按钮的确切含义

微软官方文档（[在 Windows 中自定义锁屏界面](https://support.microsoft.com/zh-cn/windows/experience/personalization/customize-the-lock-screen-in-windows)）中的关键句：

> 若要添加更多小组件，请选择列表下方的 **"添加小组件"**。
> …… 目前，只有**支持小尺寸**的小组件才能添加到锁屏界面。

以及 elevenforum 教程中的补充：

> **If the `+ Add widget` button is grayed out, then the widget has already been added.**

即灰色按钮有两种可能：

| 原因 | 是否适用 |
|---|---|
| A. 该小组件**已经添加过** | ✅ 高度可疑（天气是锁屏默认小组件，必然支持小尺寸） |
| B. 该小组件**不支持小尺寸** | ❌ 天气是锁屏的默认卡片，一定支持 |

**判定：原因 A —— 系统认为天气"已经添加过了"。**

---

## 4. 第三轮：找到同类报告（确定这是已知问题）

Microsoft Q&A：[**Weather lock-screen widget Add button remains grayed out in Windows 11 26H2**](https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray)（2026-09-30 提出）

提问者的环境和本案例高度一致：

- Windows 11 **26H2**
- 症状**在 25H2 就存在，升级到 26H2 依旧**
- Web Experience Pack **526.21100.40.0**（与本案例完全相同）
- 位置服务已开启
- `Win+W` 小组件板里的天气**正常**
- 其他小组件可添加，只有天气不行

微软支持给出的方案与该用户的实测结果：

| # | 建议的方案 | 结果 |
|---|---|---|
| 1 | 关位置服务 → 重启 → 打开 | ❌ |
| 2 | 小组件板里移除天气再加回 | ❌ |
| 3 | Microsoft Store 更新 Web Experience Pack | ❌（已是最新） |
| 4 | 重置 Web Experience Pack（高级选项 → 重置） | ❌ |
| 5 | 结束进程 + 打开 `%LOCALAPPDATA%\Packages`（步骤缺失，无操作） | ❌ |
| 6 | 重命名 `WebExperience\LocalState` → `LocalState.old` | ❌ |
| 7 | 干净启动（msconfig 禁用全部非微软服务） | ❌ |
| 8 | `sfc /scannow` | ❌（无损坏） |
| 9 | 就地升级重装系统（保留个人文件和应用） | ❌ |
| 10 | 最终建议：新建用户配置文件并迁移数据 | 理论可行但代价极大 |

**关键线索**：

> 该用户创建了一个**本地测试账户**，在其中**天气直接就在锁屏上**，无需添加。

说明：问题**跟着用户配置文件走**，同一台机器的其他账户正常。

---

## 5. 第四轮：定位状态真正的存储位置

### 5.1 先看注册表（失败路径）

`HKCU\Software\Microsoft\Windows\CurrentVersion\Lock Screen` 的初始值：

```
LockAppAumId                                                = Microsoft.LockApp_cw5n1h2txyewy!WindowsDefaultLockScreen
FirstLockAfterOSInstall                                     = 26100.ge_release.240331-1435
IsNewUserOrFirstLockSinceUpgradeFromWin10OrLower            = 0
LockInstanceType                                            = 3
TileMigrated                                                = 3
AutoSelectWidgetsOnLockScreen                               = 1
SlideshowEnabled                                            = 0
HasLockCanvasWithRecommendationsMigratedFromDetailedStatus  = 1
MigratedFromDetailedStatus                                  = 1
LockScreenWidgetsSystemCurationEnabled                      = 0
HasMigratedDetailedStatus                                   = 1
LockScreenWidgetsEnabled                                    = 1
PreplacedWidgetsAttempted                                   = 1
HasLockCanvasRemovedPreplacedWidgets                        = 1
```

子键：

```
HKCU\...\Lock Screen\FeedManager\Feeds      (存在但无值)
HKCU\...\Lock Screen\FeedManager\Selected   (存在但无值)
```

看起来 `HasLockCanvasRemovedPreplacedWidgets = 1` 非常像病因
（"预置的小组件被移除了！"）。

### 5.2 第一次尝试（v1）：只清注册表 → **无效**

方案：删除 `HasLockCanvasRemovedPreplacedWidgets`、`PreplacedWidgetsAttempted`、
`HasLockCanvasWithRecommendationsMigratedFromDetailedStatus`、`AutoSelectWidgetsOnLockScreen`、
`TileMigrated`，删除空的 `FeedManager`，置 `LockScreenWidgetsSystemCurationEnabled = 1`，重启。

重启后的注册表：

```
HasLockCanvasWithRecommendationsMigratedFromLockCanvasV1  = 1     ← 换了个名字出现
HasLockCanvasRemovedPreplacedWidgets                      = 1     ← 又回来了
```

**结论**：系统确实重新跑了一遍迁移，但**又执行了一次"移除预置小组件"**。
删除这些标记只是在触发一轮重放，**并不能改变结果**。

用户反馈：**症状依旧**。

### 5.3 换个方向：检查包数据容器

列出三个相关包的 ApplicationData：

```
%LOCALAPPDATA%\Packages\Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe\
    Settings\settings.dat       (8192 B)      ← 之前从未被关注
    LocalState\
        WidgetSessions\
            ...MicrosoftStartWeatherWidgets\15a13dfb-a1c6-42ad-bc02-e825848ed137.dat  (16413 B)
            ...MicrosoftStartWeatherWidgets\9b5ae83a-036e-4f8b-9c6d-01053b68a9ef.dat  ( 4201 B)
            ...MicrosoftStartSportsWidgets\5cc86e37-91df-436b-898e-a3d1c550492b.dat  (11722 B)
            ...MicrosoftStartFinanceWidgets\... (2 个)
            ...MicrosoftStartDailyDiscoveryWidgets\... (2 个)
            ...MicrosoftStartTodaysMomentWidgets\... (2 个)
            ...MicrosoftStartTrendingSearchWidgets\... (1 个)
        FeedSessions\
            ...MicrosoftStartFeed
            ...Global.WidgetBoard!!BaselineFeedProvider
```

### 5.3.1 实例文件数对照（重要旁证）

把**故障时**各小组件的 WidgetSession 实例文件数整理出来，与"目录里能否添加"对照：

| 小组件 | 实例文件数 | 目录里能否添加 |
|---|---|---|
| 天气 Weather | **2** ⚠️ | ❌ 灰色 |
| 关注列表 Finance | **2** ⚠️ | ❌ 灰色 |
| 每日发现 DailyDiscovery | **2** ⚠️ | ❌ 灰色 |
| 今日精彩瞬间 TodaysMoment | **2** ⚠️ | ❌ 灰色 |
| 比赛项目 Sports | **1** | ✅ 可添加 |
| 提示 Tips | **0** | ✅ 可添加 |

**高度相关**：实例文件数 > 1 的全部不能添加；"比赛项目"是 1 个、"提示"是 0 个，都能加。

推测：每个实例文件对应一个已固定的 Widget 实例。锁屏小组件目录在判断
"这个小组件能不能加"时，会因为存在**多余的幽灵实例**而认为"已经添加过了"，
于是把按钮置灰，但画布上并不渲染它。

修复后，天气的实例文件数变回 **1**（与其他小组件一致）。

### 5.4 十六进制 dump `settings.dat` → **找到 LockState**

对 `Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe\Settings\settings.dat`
按 UTF-16LE 提取字符串，得到（字节序颠倒显示，交换后即真实键名）：

```
RoamingState
LockState
```

对比 `MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy\Settings\settings.dat`
（先结束 WidgetBoard / WidgetService 进程释放占用再读取）：

```
WIDGET_PINS_CONTAINER
WIDGET_PINS_MIGRATED_CONTAINER
DashboardMigration
WidgetInstanceCache
WidgetLayout_ThreeColumns
IsFullView
Pinned
RoamingState
LocalState
{15a13dfb-a1c6-42ad-bc02-e825848ed137}
{3b1ff704-fdeb-4d79-a7e9-9870a49f7479}
{4b0a022d-60f4-486b-ac33-abf7fa6e2aae}
{5cc86e37-91df-436b-898e-a3d1c550492b}
{7a71abf7-ab40-48b8-99b2-b46a8b98d09d}
{7c39b3b0-7475-4b06-975b-0c2df4b396d8}
RichCalendarSD,medium,rail,1|SportsMatch,medium,rail,2|WeatherSummary,medium,rail,0
```

**关键发现**：

- 锁屏状态 → `WidgetsPlatformRuntime` → `Settings\settings.dat` → **`LockState`**
- 小组件板状态 → `WebExperience` → `Settings\settings.dat` → `WIDGET_PINS_CONTAINER`
  （`rail` 布局串里能直接看到 `WeatherSummary` 挂在板上）

### 5.5 为什么之前所有人都修不好

```
❌ 网上所有方案（以及本仓库的 v1）重置的：
     WebExperience\LocalState            ← 小组件板的数据
     HKCU\...\Lock Screen 注册表         ← 只是迁移标记

✅ 真正需要清的：
     WidgetsPlatformRuntime\Settings\settings.dat  →  LockState    ★
     WidgetsPlatformRuntime\LocalState             →  WidgetSessions
```

`Settings\settings.dat` 和 `LocalState\` 是 ApplicationData 中**两个互相独立的容器**。
重命名 `LocalState` **完全不会**影响 `Settings\settings.dat`。

那位微软 Q&A 用户折腾 13 天无果、甚至就地重装了系统，根源就在于此。

---

## 6. 第二次尝试（v2）：清 `LockState` → **成功**

执行内容：

1. 结束 `WidgetBoard` / `WidgetService` 进程
2. 备份 `settings.dat`、`LocalState`、`LockScreen.reg`
3. 移走 `WidgetsPlatformRuntime\Settings\settings.dat`
4. 移走 `WidgetsPlatformRuntime\LocalState`
5. 删除 6 个迁移标记；置 `LockScreenWidgetsSystemCurationEnabled = 1`、`LockScreenWidgetsEnabled = 1`
6. 重启

**结果：修复成功** —— 锁屏上天气回来了。

### 重启后的状态（用于对照）

```powershell
# 注册表：两个标记又长回来了，但问题已修复 → 证明它们是红鲱鱼
HasLockCanvasRemovedPreplacedWidgets                     : 1
HasLockCanvasWithRecommendationsMigratedFromLockCanvasV1 : 1
LockScreenWidgetsSystemCurationEnabled                   : 1   # 保持为 1
LockScreenWidgetsEnabled                                 : 1

# settings.dat 没有被重建（陈旧 LockState 已永久清除）
Settings\settings.dat  : False

# WidgetSessions 用全新 GUID 重建（旧实例数据已作废）
...MicrosoftStartWeatherWidgets\a4e84bd5-2011-4189-938c-37ec5b010bb3.dat
...MicrosoftStartWeatherWidgets\e7697bd1-d41e-452d-aa18-bcbb408353b6.dat
```

---

## 7. 结论与不确定性

### 已确认

- 灰按钮 = 系统认为该小组件**已添加**（微软官方定义）
- 锁屏小组件状态保存在 `Microsoft.WidgetsPlatformRuntime\Settings\settings.dat` 的 `LockState`
- 重置 `LocalState`（无论是 WebExperience 的还是 WidgetsPlatformRuntime 的）**都不足以**修复
- `HasLockCanvasRemovedPreplacedWidgets` 等注册表标记是**正常副产物**，不是病因

### 尚不确定

- **无法百分百确定**是"清 `settings.dat`"还是"清 `LocalState`"（或两者的组合、或"连续两轮重启"）
  起了决定性作用。v2 是一次性做完这几步的。
- 但这不影响可用性：v1（只清注册表）失败、v2（额外清这两个容器）成功，
  差异点明确，且 v2 可重复执行、可回滚。

### 如果 v2 对你无效

请提 Issue，附上 `-Diagnose` 的完整输出，至少包含：

- Windows 版本 / build
- Web Experience Pack 版本
- `HKCU\...\Lock Screen` 全部值
- `Settings\settings.dat` 是否存在

---

## 8. 参考链接

- [Microsoft 支持 — 在 Windows 中自定义锁屏界面](https://support.microsoft.com/zh-cn/windows/experience/personalization/customize-the-lock-screen-in-windows)
- [Microsoft Q&A #6021021 — Weather lock-screen widget Add button remains grayed out in Windows 11 26H2](https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray)
- [Windows IT Pro Blog — Configuring "weather and more" on the lock screen](https://techcommunity.microsoft.com/blog/windows-itpro-blog/configuring-weather-and-more-on-the-lock-screen-in-windows/4101024)
- [Windows Latest — Microsoft turned Windows 11's lock screen into MSN hell, now it's undoing most of it](https://www.windowslatest.com/2026/09/17/microsoft-turned-windows-11s-lock-screen-into-msn-hell-now-its-undoing-most-of-it)
- [elevenforum — Add and Remove Widgets on Lock Screen in Windows 11](https://www.elevenforum.com/t/add-and-remove-widgets-on-lock-screen-in-windows-11.33141)
