# PeekPortal

PeekPortal is a macOS utility for a Niri-like screen sharing workflow.

The app creates a virtual display named `PeekPortal`, then lets you switch what appears there with global hotkeys. Defaults are:

- `Control+Option+W`: share the focused window
- `Control+Option+M`: share the monitor containing the focused window
- `Control+Option+C`: clear to a black frame

The virtual display is resized to match the selected window or monitor before
capture starts. This keeps non-16:9 windows from being stretched inside the
shared target, and single-window captures drop the macOS shadow padding.

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

Stage Manager support is best-effort. The app keeps its target panel from
hiding when deactivated and joins all spaces. Stronger Stage Manager flags are
avoided by default because they can make the target disappear from some meeting
apps' share pickers. macOS may still hide the original source window when Stage
Manager moves that app out of the current stage.

## Debug logs

The app writes verbose diagnostics to:

```text
~/Library/Logs/PeekPortal/debug.log
```

Use `Copy Diagnostics` for a support-safe bundle, or `Copy Log Path` when you
only need the raw log location.
