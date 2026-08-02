# Vitrina

**A dynamic screen sharing target for macOS.** Share one stable virtual display in Zoom, Meet, or any meeting app — then switch what appears on it instantly, from a menu bar app or with global hotkeys. Inspired by [niri](https://github.com/YaLTeR/niri)'s dynamic cast target.

Instead of fumbling with your meeting app's share picker mid-call, you share the `Vitrina` display once. After that:

- `Control+Option+W` — share the focused window
- `Control+Option+M` — share the monitor containing the focused window
- `Control+Option+F` — toggle Follow Focus: the share tracks whatever window is active
- `Control+Option+C` — clear to your wallpaper (or a custom backdrop)

All shortcuts are re-recordable in Settings. The menu bar also has explicit pickers: **Share Window** lists every shareable window (with app icons, front-to-back), **Share Monitor** lists every display by name.

## Privacy features

Because Vitrina composites the shared frame itself, it controls exactly what participants see:

- **Hide all notifications while sharing** (default on) — banners never reach the share.
- **Hide the menu bar** (default on) — the focused app's name and your status icons stay private.
- **Block list** — apps that never appear in a monitor share, even when on screen.
- **Allow list mode** — block everything except apps you pick; sharing an unlisted window offers to add it (optionally automatically).
- The cursor appears in window shares only while it's actually over the shared window.

## Quality

The virtual display runs in HiDPI (2x) and physically resizes to match the shared source's aspect ratio, so portrait windows aren't letterboxed into 16:9 and Retina text stays crisp (up to 3840×2160 output).

## Install

**Homebrew (coming soon):**

```sh
brew install marianomiguel/tap/vitrina
```

**Build from source:**

```sh
git clone https://github.com/MarianoMiguel/vitrina.git
cd vitrina
./scripts/build-app.sh
open dist/Vitrina.app
```

The build creates an ignored local signing identity under `.local-codesign/` so macOS Accessibility and Screen Recording permissions stay stable across rebuilds. If System Settings shows the app as enabled while it still asks for permissions, reset stale TCC entries:

```sh
./scripts/trust-local-signing-certificate.sh
./scripts/reset-permissions.sh
./scripts/build-app.sh
```

## Permissions

- **Accessibility** — to resolve the focused window.
- **Screen Recording** — so ScreenCaptureKit can capture the chosen source.

## How it works

Vitrina creates a virtual display through a small Objective-C shim over macOS's private `CGVirtualDisplay` API (the approach popularized by [DeskPad](https://github.com/Stengo/DeskPad)), renders ScreenCaptureKit captures onto it, and lets meeting apps treat that display as an ordinary screen. Because of the private API it is distributed outside the Mac App Store.

Stage Manager support is explicit rather than best-effort: macOS stops delivering frames for windows moved off the current stage, so only the active window can be shown reliably. When Stage Manager is on, the menu says so and window sharing degrades to Follow Focus.

## Updates

The app has a manual update check against the appcast published with each GitHub release. A Sparkle-based auto-updater with signed (EdDSA) appcasts is planned before the first tagged release.

## Development notes

Verbose logs: `~/Library/Logs/Vitrina/debug.log`. Test target, diagnostics export, and related UI hide behind a flag:

```sh
defaults write computer.interstellar.vitrina developerMode -bool true
```

**Always launch with `open dist/Vitrina.app`, never the raw binary.** Launching `Contents/MacOS/vitrina` from a terminal makes macOS 26 attribute the menu bar item to the *terminal* in ControlCenter's `trackedApplications` registry (`~/Library/Group Containers/group.com.apple.controlcenter/`). If the terminal's own menu bar icon is hidden, every item attributed to it is silently blocked — the item registers but gets parked off-screen, and the app's own "Show in Menu Bar" toggle can't fix it. Vitrina detects this parked state at launch and points at System Settings > Menu Bar; repairing a poisoned attribution requires editing that registry (Full Disk Access) or unhiding the terminal's icon.

## License

[MIT](LICENSE). Vitrina is free and open source, produced by Interstellar Computer, a DBA of Mariano Miguel, LLC.
