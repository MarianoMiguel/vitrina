# Dynamic Share Target

Working-name macOS utility for a Niri-like screen sharing workflow.

The app creates a stable share target named `Dynamic Share Target`, then lets you switch what appears there with global hotkeys:

- `Control+Option+W`: share the focused window
- `Control+Option+M`: share the monitor containing the focused window
- `Control+Option+C`: clear to a black frame

## Build

```sh
./scripts/build-app.sh
```

The generated app bundle is printed at the end, usually:

```text
dist/Dynamic Share Target.app
```

The build creates an ignored local signing identity under `.local-codesign/`.
This keeps macOS Accessibility and Screen Recording permissions stable across rebuilds.

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

This is an MVP/personal utility. It uses ScreenCaptureKit for capture and a small Objective-C shim around macOS virtual display classes, similar to the approach used by DeskPad.

## Debug logs

The app writes verbose diagnostics to:

```text
~/Library/Logs/DynamicShareTarget/debug.log
```

Use the menu bar item `Copy Log Path` after a crash/relaunch to grab the exact path.
