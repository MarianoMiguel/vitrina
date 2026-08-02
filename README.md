<h1 align="center">Vitrina</h1>

<p align="center"><b>A dynamic screen sharing target for macOS.</b></p>

<p align="center">
<a href="https://github.com/MarianoMiguel/vitrina/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
<a href="https://github.com/MarianoMiguel/vitrina/actions/workflows/ci.yml"><img src="https://github.com/MarianoMiguel/vitrina/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/MarianoMiguel/vitrina/releases"><img src="https://img.shields.io/github/v/release/MarianoMiguel/vitrina?include_prereleases" alt="Release"></a>
</p>

<p align="center">
<a href="#install">Install</a> · <a href="#features">Features</a> · <a href="#how-it-works">How it works</a> · <a href="docs/DEVELOPMENT.md">Development</a> · <a href="docs/RELEASING.md">Releasing</a>
</p>

<!-- screenshot: menu bar open over a shared window, coming soon -->

## About

Share one stable virtual display in Zoom, Meet, or any meeting app — then switch what appears on it instantly, from the menu bar or with global hotkeys. No more fumbling with your meeting app's share picker mid-call, and no more "let me re-share my screen."

Vitrina creates a virtual display that meeting apps see as an ordinary screen. You share it once; Vitrina decides what shows up there:

| Shortcut | Action |
| --- | --- |
| `⌃⌥W` | Share the focused window |
| `⌃⌥M` | Share the monitor containing the focused window |
| `⌃⌥F` | Follow Focus — the share tracks whatever window is active |
| `⌃⌥C` | Clear to your wallpaper (or a custom backdrop) |

All shortcuts are re-recordable in Settings. The menu bar also has explicit pickers listing every shareable window (with app icons, front-to-back) and every display by name.

The idea comes from [niri](https://github.com/niri-wm/niri)'s dynamic cast target, translated to macOS.

## Features

- **Instant target switching** — window, monitor, or follow-focus, without touching the meeting app.
- **Privacy filters** — Vitrina composites the shared frame itself, so it controls exactly what participants see:
  - Hide all notifications while sharing (default on).
  - Hide the menu bar (default on) — the focused app's name and your status icons stay private.
  - Block list: apps that never appear in a monitor share, even when on screen.
  - Allow-list mode: block everything except apps you pick; sharing an unlisted window offers to add it, optionally automatically.
- **Precise cursor** — window shares show the pointer only while it's actually over the shared window.
- **HiDPI output** — the virtual display runs at 2x and physically resizes to match the source's aspect ratio, so portrait windows aren't letterboxed into 16:9 and Retina text stays crisp (up to 3840×2160).
- **Custom backdrop** — between shares, participants see your wallpaper or an image of your choice.
- **Stage Manager aware** — macOS only delivers frames for on-stage windows, so when Stage Manager is on, Vitrina switches window sharing to Follow Focus automatically instead of letting the share freeze.

## Install

Homebrew:

```sh
brew install marianomiguel/tap/vitrina
```

Or build from source:

```sh
git clone https://github.com/MarianoMiguel/vitrina.git
cd vitrina
./scripts/build-app.sh
open dist/Vitrina.app
```

macOS will ask for two permissions: **Accessibility** (to resolve the focused window) and **Screen Recording** (so ScreenCaptureKit can capture the chosen source).

## How it works

Vitrina creates a virtual display through a small Objective-C shim over macOS's private `CGVirtualDisplay` API, renders ScreenCaptureKit captures onto it, and lets meeting apps treat that display as an ordinary screen. Selective visibility (block/allow lists, notification and menu bar hiding) works because ScreenCaptureKit composites frames from individual window layers rather than screenshotting the framebuffer.

Because of the private API, Vitrina is distributed outside the Mac App Store.

Updates ship through GitHub releases: the app checks the published appcast manually today, with a Sparkle-based auto-updater planned.

## Acknowledgments

- [niri](https://github.com/niri-wm/niri) — the scrollable-tiling Wayland compositor whose dynamic cast target inspired Vitrina.
- [DeskPad](https://github.com/Stengo/DeskPad) (MIT) — pioneered the virtual-monitor-for-screen-sharing approach on macOS. Vitrina's `VirtualDisplayShim` adapts the private `CGVirtualDisplay` API declarations carried by DeskPad.
- [Khaos Tian](https://github.com/KhaosT) — originally reverse-engineered the `CGVirtualDisplay` private API declarations (VirtualDisplayExp, 2021) that DeskPad and Vitrina build on.

## License

[MIT](LICENSE). Created by [Mariano Miguel](https://github.com/MarianoMiguel).
