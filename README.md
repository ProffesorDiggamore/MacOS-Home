# Home Widgets

Apple-style widgets for your Mac desktop. They're lightweight, you can customize them, and they update live.

Home Widgets is a small native app (Swift + SwiftUI, no Electron) that lives in your menu bar and pins widgets to your desktop, behind your windows like the widgets in macOS Sonoma and later. Unlike the built-in widgets, these update every second, can launch apps, and can show things Apple's widgets can't, like CPU/GPU usage and your Claude Code sessions.

<p align="center"><img src="Resources/AppIcon.png" width="128" alt="Home Widgets icon"></p>

## Download

**[⬇ Download Home Widgets for Mac](https://github.com/ProffesorDiggamore/MacOS-Home/releases/latest/download/Home-Widgets.zip)** · macOS 14 Sonoma or later · Apple Silicon and Intel

1. Unzip it and drag **Home Widgets** into **Applications**.
2. Open it. The first time, macOS says it can't verify the developer — click **Done**.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. You only do this once.

The app isn't notarized by Apple, which is why macOS asks. All versions are on the [Releases page](https://github.com/ProffesorDiggamore/MacOS-Home/releases).

## Widgets (27)

| Time & Date | System | Productivity | Media & Inspiration |
| --- | --- | --- | --- |
| Clock | System Stats (CPU/GPU/RAM/Disk rings) | **Claude Code sessions** | Now Playing (Music & Spotify) |
| Analog Clock | CPU (history + per-core) | **App Shortcuts** | Photo / slideshow |
| World Clock | GPU | Quick Actions + your Shortcuts | Verse of the Day (KJV) |
| Calendar (+ events) | Memory (pressure, swap) | Reminders (check them off) | Moon Phase |
| Countdown | Storage | Focus Timer (Pomodoro) | |
| Year Progress | Network (live up/down) | Sticky Note | |
| | Battery (health, cycles, watts) | Folder / Recent Downloads | |
| | Top Processes | Weather (Open-Meteo, no API key) | |
| | About This Mac | | |

Most widgets come in **Small**, **Medium** and **Large**, using the same proportions as Apple's widgets.

### Claude Code widget
Reads `~/.claude/projects` and checks for running `claude` processes. For each session it shows:
- 🟠 **Working**: Claude is thinking or running tools
- 🟢 **Your turn**: Claude finished and is waiting for you
- ⚪ **Ended**: with how long ago it was active

Click a live session to jump to the terminal it's running in (Terminal, iTerm, VS Code…). Click an ended one to **resume it** (`claude --resume`) in a new Terminal window. The Large size also shows today's token usage.

## Install

You need macOS 14 Sonoma or newer, plus Apple's free developer tools. Open **Terminal** and run:

```bash
xcode-select --install          # only needed once; skip if you already have Xcode
git clone https://github.com/ProffesorDiggamore/MacOS-Home.git
cd MacOS-Home
make install
```

`make install` builds the app, copies **Home Widgets.app** to `/Applications`, and opens it. A default set of widgets appears on your desktop, and the Widget Gallery opens so you can add more.

Other commands:

| Command | What it does |
| --- | --- |
| `make run` | Build into `./build` and launch without installing |
| `make build` | Just compile (quick check) |
| `make uninstall` | Remove the app from `/Applications` |
| `make clean` | Delete build files |

> **Prefer a download?** Every push builds the app on GitHub Actions. Open the **Actions** tab, pick the latest run, and download the `HomeWidgets-macos-15` artifact. The app isn't notarized, so the first time you open it, right-click it and choose **Open**.

## Using it

- **Menu bar icon** (the 2×2 grid): add widgets, open the gallery, hide/lock widgets, arrange them, quit.
- **Drag** a widget anywhere. It snaps into line with nearby widgets and screen edges.
- **Right-click** a widget to change its size or style, edit its options, or remove it.
- **Settings › Appearance**: Frosted Glass, Liquid Glass (macOS 26), Solid, Tinted or Clear; light/dark; accent color; font; opacity.
- **Settings › General**: keep widgets on the desktop or floating above windows, lock positions, open at login, refresh rate, °F/°C.
- Drag apps from Finder onto the **App Shortcuts** widget to add them.

## Permissions

macOS asks the first time a widget needs something:

| Widget | Permission |
| --- | --- |
| Calendar, Reminders | Calendars / Reminders |
| Weather (current location) | Location (or type a city instead) |
| Now Playing, Quick Actions › Dark Mode / Empty Trash | Automation (Music, Spotify, System Events, Finder) |
| Folder (Downloads) | Files & Folders |

Because the app is signed locally (ad-hoc), macOS may ask again after you rebuild it. That's normal.

## How it stays lightweight

- Native AppKit windows + SwiftUI. No web views, no background daemons.
- Each data source (CPU, GPU, network, Claude, weather…) **only runs while a widget that uses it is visible**.
- CPU/GPU/memory come straight from the kernel (`host_processor_info`, IOKit `IOAccelerator`, `host_statistics64`), with no shell commands.
- Clocks update with SwiftUI `TimelineView`, so they redraw once a second (or once a minute) instead of animating constantly.

## Project layout

```
Sources/HomeWidgets/
  App/        menu bar, desktop panels, drag & snap
  Model/      widget list, per-widget settings, appearance settings
  Monitors/   CPU, GPU, memory, storage, network, battery, processes, Claude Code
  Services/   weather, calendar/reminders, now playing, folders, system info
  UI/         widget chrome (glass/solid/tinted), rings, sparklines…
  Widgets/    one file per family of widgets
  Settings/   gallery, editor, appearance & general settings
```

Adding a widget: add a case to `WidgetKind`, write a SwiftUI view that takes a `WidgetModel`, and add it to the switch in `UI/WidgetView.swift` (plus optional settings in `Settings/WidgetOptions.swift`).

## Credits

Weather data by [Open-Meteo](https://open-meteo.com). Scripture quotations are from the King James Version (public domain).
