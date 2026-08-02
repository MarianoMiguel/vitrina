# PeekPortal

PeekPortal is a macOS utility for a Niri-like screen sharing workflow.

The app creates a virtual display named `PeekPortal`, then lets you switch what appears there with global hotkeys or from the menu bar. Default shortcuts are:

- `Control+Option+W`: share the focused window
- `Control+Option+M`: share the monitor containing the focused window
- `Control+Option+F`: toggle Follow Focus (the share target tracks the active window)
- `Control+Option+C`: clear to a black frame

The menu bar also has explicit pickers: `Share Window` lists every shareable
window (with app icons, front-to-back), and `Share Monitor` lists every
physical display by name. Both are populated live when the menu opens.

The virtual display runs in HiDPI (2x) mode and is resized to match the
selected window or monitor before capture starts. This keeps non-16:9 windows
from being stretched inside the shared target, keeps Retina text crisp, and
single-window captures drop the macOS shadow padding.

The menu bar icon shows the current status, the current target mode, primary
share actions with their active shortcuts, a test target, settings, diagnostics,
and quit. Settings has `General`, `Updates`, `About`, and `License` panes.
General includes permission shortcuts, Launch at Login, shortcut recording,
Reset All, a test target button, and diagnostics export.

## Build

```sh
./scripts/build-app.sh
```

The generated app bundle is printed at the end, usually:

```text
dist/PeekPortal.app
```

The build creates an ignored local signing identity under `.local-codesign/`.
This keeps macOS Accessibility and Screen Recording permissions stable across rebuilds.
The current bundle identifier is `computer.interstellar.peekportal`.

If System Settings shows the app as already enabled while the app still asks
for permissions, reset stale TCC entries and grant the `dist/` app again:

```sh
./scripts/trust-local-signing-certificate.sh
./scripts/reset-permissions.sh
./scripts/build-app.sh
```

## Permissions

macOS must grant:

- Accessibility, so the app can resolve the focused window.
- Screen Recording, so ScreenCaptureKit can capture the chosen source.

## Status

This is an MVP utility produced by Interstellar Computer, a DBA of Mariano Miguel, LLC. The public website will be `https://interstellar.computer`.

It uses ScreenCaptureKit for capture and a small Objective-C shim around macOS
virtual display classes, similar to the approach used by DeskPad.

Licensing is not active yet. Updates has a manual appcast check path that can be
replaced by Sparkle once the signed release channel is ready.

Stage Manager support is explicit rather than best-effort: macOS stops
delivering frames for windows that Stage Manager moves off the current stage,
so only the active window can be displayed reliably. When Stage Manager is on,
the menu says so and `Share Focused Window` degrades to Follow Focus, tracking
whatever window is active. The app also keeps its target panel from hiding when
deactivated and joins all spaces; stronger Stage Manager flags are avoided
because they can make the target disappear from some meeting apps' share
pickers.

## Developer mode

Test target, diagnostics, virtual display info, and log-path UI are hidden
from end users. Enable them with:

```sh
defaults write computer.interstellar.peekportal developerMode -bool true
```

and relaunch the app.

## Development gotcha: launch with `open`, never the raw binary

Always launch the app with `open dist/PeekPortal.app` (or Finder). Launching
`Contents/MacOS/peekportal` directly from a terminal makes macOS 26 attribute
the menu bar item to the *terminal* in ControlCenter's `trackedApplications`
registry (`~/Library/Group Containers/group.com.apple.controlcenter/`). If the
terminal's own menu bar icon is set to hidden, every item attributed to it is
silently blocked — the status item registers successfully but gets parked
off-screen, and the app's own "Show in Menu Bar" toggle cannot fix it. The app
detects this parked state at launch and points users at System Settings >
Menu Bar; repairing a poisoned attribution requires editing the registry
(Full Disk Access) or removing the terminal's hidden state.

## Debug logs

The app writes verbose diagnostics to:

```text
~/Library/Logs/PeekPortal/debug.log
```

Use `Copy Diagnostics` for a support-safe bundle, or `Copy Log Path` when you
only need the raw log location.
