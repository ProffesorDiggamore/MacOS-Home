# Home Widgets

Apple-style widgets for your Mac desktop. They're lightweight, you can customize them, and they update live.

Home Widgets is a native Mac app (Swift + SwiftUI, no Electron) that pins widgets to your desktop, behind your windows like the widgets in macOS Sonoma and later. Unlike Apple's widgets, these update every second, launch apps, show your CPU/GPU, Claude Code sessions, GitHub and Cairn notes, and come in shapes Apple doesn't offer.

<p align="center"><img src="Resources/AppIcon.png" width="128" alt="Home Widgets icon"></p>

## Install

You need macOS 14 Sonoma or newer, plus Apple's free developer tools. Open **Terminal** and paste these lines one at a time:

```bash
xcode-select --install
```

If a window pops up, click **Install** and wait for it to finish. If it says the tools are already installed, that's fine. Then:

```bash
git clone -b claude/sweet-bell-9o7yth https://github.com/ProffesorDiggamore/MacOS-Home.git
cd MacOS-Home
make install
```

**Home Widgets** lands in your Applications folder and opens. It has a Dock icon like a normal app: click it any time to bring back the window.

### Update to the latest version

```bash
cd ~/MacOS-Home && git pull && make install
```

### Start fresh (delete and re-download)

```bash
cd ~ && rm -rf ~/MacOS-Home && git clone -b claude/sweet-bell-9o7yth https://github.com/ProffesorDiggamore/MacOS-Home.git && cd MacOS-Home && make install
```

Your widgets and settings are kept either way. They live in `~/Library/Application Support/HomeWidgets`.

| Command | What it does |
| --- | --- |
| `make install` | Build, copy to Applications, and open |
| `make update` | `git pull` + `make install` |
| `make run` | Build into `./build` and open without installing |
| `make uninstall` | Remove the app from Applications |

## Widgets (66)

| Category | Widgets |
| --- | --- |
| **Time & Date** | Clock · Analog Clock · World Clock · Calendar · Countdown · Year Progress · Flip Clock · Word Clock · Binary Clock · Stopwatch · Sun |
| **System** | System Stats · CPU · GPU · Memory · Storage · Network · Battery · Top Processes · About This Mac · Disk Activity · Wi-Fi · Volume · Clipboard History |
| **Productivity** | Claude Code · App Shortcuts · Quick Actions (+ your Shortcuts) · Reminders · Focus Timer · Sticky Note · Folder · Weather · To-Do List · Habits · Quick Links · Calculator · Counter |
| **Accounts & Web** | GitHub · Contributions · **Cairn Notes** · Mail · News Feed (any RSS) · Hacker News · Stocks · Crypto · Currency · Sports Scores · Website Monitor · Service Status |
| **Photos, Text & Media** | Now Playing · Photo · Sticker · Text · Verse of the Day (KJV) · Moon Phase |
| **Fun & Aesthetic** | Claude Crab · Lava Lamp · Aquarium · Digital Rain · Night Sky · Game of Life · Bouncing Text · Mood Gradient · Color Palette · Dice & Coin · Pixel Plant |

### Sizes

| Size | Shape | Good for |
| --- | --- | --- |
| Small | 1×1 | most widgets |
| Medium | 2×1 | lists, graphs |
| Large | 2×2 | dashboards |
| **Tall** | 1×2 | portrait photos, notes, to-dos |
| **Wide** | 4×1 | banners: app docks, stocks, news |
| **Extra Large** | 4×2 | big photos, aquarium, night sky |
| **Portrait** | 2×3 | tall photos, Cairn's today page |

Right-click any widget › **Size** to change it.

### Your own images
- **Sticker**: any image floating on your desktop with no box around it. PNGs with transparent backgrounds look best. Drag an image onto it, or paste one.
- **Photo**: drag photos onto it to build an album (click to go to the next one), or point it at a folder. Frames: Edge to Edge, Polaroid (with a caption), or Framed.
- **Any widget** can have a background photo, with sliders to darken and blur it so text stays readable: right-click › Edit Widget › Background Photo.

Images you add are copied into the app's own storage, so they keep working even if you delete the originals.

### Claude Code
- **Session list**: 🟠 working, 🟢 your turn, ⚪ ended. Click a live one to jump to its terminal, or an ended one to resume it.
- **Just the Crab** (Edit Widget › Show): the pixel crab from the Claude Code logo. It works when Claude is working, bounces when it's your turn, and naps when everything's idle.
- **Claude Crab** widget: a desktop pet that wanders around. Click it to make it jump.

### Accounts
Open **Settings › Accounts**:
- **GitHub**: click *Create a Token on GitHub* (it pre-selects the right permissions), paste it, and click *Connect*. This powers the GitHub and Contributions widgets.
- **Cairn**: paste the token you already use in Cairn (Contents read & write on your Cairn repo), or reuse the GitHub token. The Cairn widget shows recent notes with their icons and today's daily note, and quick capture adds bullets or to-dos to `Daily/YYYY-MM-DD.md`, which Cairn picks up on its next sync. Put your Cairn web address in the widget's settings and clicking a note opens it in Cairn.
- **Mail**: works with any account added to Apple's Mail app (Gmail, iCloud, Outlook). No token needed.

Tokens are stored in your Mac's Keychain. Because the app is signed locally, macOS may ask for your password once after each update so the new version can read them.

## Using it
- **Dock icon** opens the Home Widgets window: Widget Gallery, My Widgets, Accounts, Appearance, General.
- **Drag** a widget anywhere. It snaps into line with nearby widgets and screen edges.
- **Right-click** a widget to resize it, restyle it, edit it, or remove it.
- **Appearance**: Frosted Glass, Liquid Glass (macOS 26), Solid, Tinted or Clear; light/dark; accent color; font; opacity.
- **General**: widgets on the desktop or floating above windows, lock positions, open at login, Dock/menu bar icons, refresh rate, °F/°C.

## Permissions
macOS asks the first time a widget needs something. Calendar and Reminders ask for those; Weather and Sun ask for Location (or type a city instead); Now Playing, Mail, Dark Mode and Empty Trash ask for Automation; Folder asks for Files & Folders.

## How it stays lightweight
- Native AppKit windows + SwiftUI. No web views, no background daemons.
- Each data source only runs while a widget that uses it is on screen.
- Animated widgets **pause automatically when covered by windows**.
- CPU/GPU/memory/disk come straight from the kernel and IOKit, with no shell commands.

## Credits
Weather by [Open-Meteo](https://open-meteo.com) · Stocks via Yahoo Finance · Currency via [Frankfurter](https://frankfurter.app) (ECB) · Sports via ESPN · Scripture from the King James Version (public domain).
