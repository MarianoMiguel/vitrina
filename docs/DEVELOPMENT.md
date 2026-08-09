# Development

## Build

```sh
./scripts/build-app.sh
open dist/Vitrina.app
```

The build creates an ignored local signing identity under `.local-codesign/` so macOS Accessibility and Screen Recording permissions stay stable across rebuilds. If System Settings shows the app as enabled while it still asks for permissions, reset stale TCC entries:

```sh
./scripts/trust-local-signing-certificate.sh
./scripts/reset-permissions.sh
./scripts/build-app.sh
```

## Debug logs

The app writes verbose diagnostics to `~/Library/Logs/Vitrina/debug.log`.

## Developer mode

Test target, diagnostics export, virtual display info, and log-path UI are hidden from end users. Enable them with:

```sh
defaults write com.marianomiguel.vitrina developerMode -bool true
```

and relaunch the app.

## Gotcha: launch with `open`, never the raw binary

Always launch the app with `open dist/Vitrina.app` (or Finder). Launching `Contents/MacOS/vitrina` directly from a terminal makes macOS 26 attribute the menu bar item to the *terminal* in ControlCenter's `trackedApplications` registry (`~/Library/Group Containers/group.com.apple.controlcenter/`). If the terminal's own menu bar icon is set to hidden, every item attributed to it is silently blocked — the status item registers successfully but gets parked off-screen, and the app's own "Show in Menu Bar" toggle cannot fix it.

Vitrina detects this parked state at launch and points users at System Settings > Menu Bar; repairing a poisoned attribution requires editing that registry (Full Disk Access) or unhiding the terminal's icon.

## Diagnostic environment variables

- `VITRINA_SKIP_VDISPLAY=1` — start without creating the virtual display.
- `VITRINA_SKIP_TARGETWINDOW=1` — create the display but no target window.
