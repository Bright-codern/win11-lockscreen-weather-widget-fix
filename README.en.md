# Fix: Windows 11 lock screen Weather widget — "Add" button greyed out

[中文说明](README.md) · English

> **TL;DR** — On Windows 11 **25H2 / 26H2**, the **Weather** widget's *Add* button on
> **Settings → Personalization → Lock screen → Widgets** is greyed out even though Weather is
> **not** on the lock screen. The stale "already pinned" record lives in
> `Microsoft.WidgetsPlatformRuntime` → **`Settings\settings.dat` → `LockState`** — *not* in
> `LocalState`. That is why every "reset the Widgets data / rename LocalState" guide on the
> internet fails. This repo clears that record.

---

## Symptoms

On Windows 11 **25H2 / 26H2**, in
**Settings → Personalization → Lock screen → Widgets → Add widget**:

- ✅ Some widgets (e.g. *Sports*, *Tips*) can be added normally
- ❌ **Weather's "Add widget" button is greyed out** and cannot be clicked
- ❌ No weather card is visible on the actual lock screen
- ✅ The weather widget on the taskbar and in the Widgets board (`Win + W`) works fine
- Location services are on, region/language are correct, the taskbar Widgets toggle is on

---

## Root cause

### 1. What a greyed-out button actually means

Microsoft's own documentation does **not** state why the button is greyed out.
Its [Customize the lock screen in Windows](https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-lock-screen-in-windows)
article only mentions the size restriction ("currently, only widgets that support the small size
can be added to the lock screen"), which cannot explain this bug — Weather is the lock screen's
default card and therefore certainly supports the small size.

The "greyed out = already added" rule comes from the elevenforum lock screen widgets tutorial:

> **If the `+ Add widget` button is grayed out, then the widget has already been added.**

> 📌 **Source note:** that sentence is **not** Microsoft's own wording. Both the Chinese and
> English Microsoft support articles were re-checked on 2026-10-16 and neither contains the
> "greyed out / already added" statement. It is community experience — but it matches the
> observed behaviour exactly (see the A/B reasoning and the exclusion of the size explanation in
> `docs/INVESTIGATION.md`, section 3).

So a greyed-out *Weather* button means **Windows believes Weather is already on the lock screen** —
while in reality the lock screen shows nothing. The recorded state and the rendered state disagree.

### 2. Where the state actually lives (the key finding)

Under `%LOCALAPPDATA%\Packages\Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe\` there are
**two independent ApplicationData containers**:

```
Settings\settings.dat   <-- holds RoamingState / LockState      ★ lock screen widget state
LocalState\             <-- holds WidgetSessions / FeedSessions (per-widget instance data)
```

A hex dump of `settings.dat` confirms it contains these key names:

```
RoamingState
LockState          <-- lock screen widget pin records
```

By contrast, `MicrosoftWindows.Client.WebExperience`'s `settings.dat` holds the
**Widgets board (`Win + W`)** pins instead:

```
WIDGET_PINS_CONTAINER
WIDGET_PINS_MIGRATED_CONTAINER
RichCalendarSD,medium,rail,1|SportsMatch,medium,rail,2|WeatherSummary,medium,rail,0
```

> **This is why every existing guide fails.**
> They all reset `LocalState` (even the usual "`-HardReset`" just renames `LocalState`),
> **but `LockState` lives in `Settings\settings.dat`, which is untouched by a `LocalState` reset.**

### 3. A red herring

These registry values under `HKCU\Software\Microsoft\Windows\CurrentVersion\Lock Screen`
look extremely suspicious:

```
HasLockCanvasRemovedPreplacedWidgets                       = 1
HasLockCanvasWithRecommendationsMigratedFromLockCanvasV1   = 1
```

("Pre-placed widgets were removed from the lock canvas!")

**They are not the cause.** Verified experimentally: delete them → reboot → the migration runs
again → **they come right back** — and the problem is still fixed. They are a normal by-product of
the migration logic. Clearing them alone changes nothing.

### 4. Supporting evidence: ghost widget instances

At failure time, the number of instance files per widget in `WidgetSessions` correlated perfectly
with whether that widget could be added:

| Widget | Instance files | Addable? |
|---|---|---|
| Weather | **2** ⚠️ | ❌ greyed out |
| Watchlist (Finance) | **2** ⚠️ | ❌ greyed out |
| Daily Discovery | **2** ⚠️ | ❌ greyed out |
| Today's Moment | **2** ⚠️ | ❌ greyed out |
| Sports | **1** | ✅ addable |
| Tips | **0** | ✅ addable |

Every widget with more than one instance file was un-addable. The extra file appears to be a
**ghost instance** that makes the widget catalogue believe the widget is already present.
After the fix, Weather is back to **1** instance file like every other widget.

---

## The fix

1. Stop all Widgets processes (release file locks)
2. **Move away** `WidgetsPlatformRuntime\Settings\settings.dat` ← clears `LockState` (**key step**)
3. **Move away** `WidgetsPlatformRuntime\LocalState` ← clears `WidgetSessions`
4. Clear the stale migration flags in the lock screen registry key
5. Set `LockScreenWidgetsSystemCurationEnabled = 1` and `LockScreenWidgetsEnabled = 1` so Windows can re-place Weather automatically
6. Delete the empty `FeedManager` subkey (Windows recreates it)
7. **Restart** the PC (use **Restart**, *not* Shutdown → power on)

### Why this works

Once `LockState` is gone, the "pre-place widgets" pass no longer treats Weather as a duplicate,
so Weather is placed back onto the lock screen canvas — and the catalogue button stops being
greyed out.

---

## Usage

**Requirements:** Windows 11 25H2 / 26H2 · **no administrator rights needed** · PowerShell 5.1+

### 1. Diagnose first (read-only, changes nothing)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1 -Diagnose
```

Prints your OS version, Web Experience Pack version, all lock screen registry values, whether
`settings.dat` / `LocalState` exist, and per-widget instance counts.

**Decision rule:** if `Settings\settings.dat` exists → this fix applies to you.

### 2. Apply the fix

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1
```

Everything is backed up automatically to
`%USERPROFILE%\lockscreen-widget-backup\<timestamp>\` (`settings.dat` + `LocalState` + `LockScreen.reg`).

### 3. Restart

> ⚠️ Choose **Restart**. Do **not** use Shutdown → power on — Windows Fast Startup skips part of
> the initialization.

### 4. Verify

| What you see | Verdict |
|---|---|
| A weather card appears at the bottom of the lock screen | ✅ Fixed (Windows re-placed it) |
| Weather is in the "Your widgets" list, button still grey | ✅ **Also fixed** — greyed out means "already added" |
| Weather still absent, button still grey | ❌ Not fixed — please open an issue with your `-Diagnose` output |

### Roll back

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-LockScreenWeatherWidget.ps1 -Restore
```

---

## What does NOT work (don't waste your time)

All of the following **were tried and failed**. The "clear the registry migration flags only"
entry was reproduced locally (v1); every other entry comes from the reporter's own attempts in the
[Microsoft Q&A thread](https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray)
(see `docs/INVESTIGATION.md`, sections 2 and 4):

| Attempt | Result |
|---|---|
| Settings → Privacy & security → Location: off → reboot → on | ❌ |
| Remove Weather from the Widgets board, then add it back | ❌ |
| Reset the Windows Web Experience Pack (Advanced options → Reset) | ❌ |
| **Rename the WebExperience `LocalState` folder** | ❌ ← most commonly recommended, but wrong target |
| Clean boot (msconfig, disable all non-Microsoft services) | ❌ |
| `sfc /scannow` | ❌ |
| In-place upgrade / repair install of Windows (keep files & apps) | ❌ |
| Check the `Disable Widgets On Lock Screen` group policy | Already *Not Configured* |
| Clear only the lock screen registry migration flags | ❌ **useless on its own — must be combined with clearing `LockState`** |

After **13 days** of back-and-forth, Microsoft Support's final recommendation was:

> "As a workaround, you may consider creating a new Windows user profile and migrating your data to it."

**This repo exists so you don't have to do that.**

---

## Tested environment

| Item | Value |
|---|---|
| OS | Windows 11 **26H2**, build **26300.9711** (GA) |
| Windows Feature Experience Pack | `1000.26100.372.0` |
| Windows Web Experience Pack | `526.21100.40.0` |
| Widgets Platform Runtime | `1.6.19.0` |
| Microsoft.StartExperiencesApp | `1.398.2.0` |
| Region / language | China / zh-CN |
| Account type | Microsoft account (MSA) |

The same symptom has been reported on Windows 11 **25H2 (`26200.x`)** and **persisted after
upgrading to 26H2** — see
[Microsoft Q&A #6021021](https://learn.microsoft.com/en-us/answers/questions/6021021/weather-lock-screen-widget-add-button-remains-gray).

---

## Repository layout

```
.
├── README.md                                  ← 中文说明 (Chinese)
├── README.en.md                               ← you are here
├── HANDOVER.md                                ← handover / handoff notes (Chinese)
├── LICENSE                                    ← MIT
├── scripts/
│   └── Fix-LockScreenWeatherWidget.ps1        ← -Diagnose | (default) fix | -Restore
└── docs/
    └── INVESTIGATION.md                       ← full investigation log + raw evidence (Chinese)
```

---

## Disclaimer

- This is a community workaround, **not an official Microsoft fix**.
- The script **moves** widget data files and **modifies** lock screen registry values under `HKCU`.
  It backs everything up and ships a `-Restore` switch, but please review it before running.
- Side effect: widgets on the Widgets board (`Win + W`) may need to reload or be re-pinned once.

## License

MIT
