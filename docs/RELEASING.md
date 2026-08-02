# Releasing Vitrina

One command cuts a release end to end:

```sh
scripts/release.sh 0.1.0
```

That performs, in order:

1. **Preflight** — clean working tree, on `main`, `gh` authenticated.
2. **Version stamp** — writes `CFBundleShortVersionString` (the semver you passed) and `CFBundleVersion` (a UTC timestamp) into `Resources/Info.plist`.
3. **Build** — `CONFIGURATION=release scripts/build-app.sh` → `dist/Vitrina.app`.
4. **Sign** — if `RELEASE_SIGN_IDENTITY` is set, re-signs with your Developer ID certificate (hardened runtime + secure timestamp). Otherwise the bundle keeps the local dev signature and the script warns: fine for testing, but Gatekeeper will warn users who download it.
5. **Notarize** — if `NOTARY_PROFILE` is set, submits to Apple with `notarytool`, waits, and staples the ticket.
6. **Package** — `dist/Vitrina-<version>.zip` plus `dist/appcast.json` (the feed the in-app update check reads via `releases/latest/download/appcast.json`).
7. **Publish** — commits the version bump, tags `v<version>`, pushes, and creates the GitHub release with both artifacts and generated notes.
8. **Homebrew** — `scripts/update-tap.sh` writes `Casks/vitrina.rb` in `MarianoMiguel/homebrew-tap` with the new version and sha256, making `brew install marianomiguel/tap/vitrina` serve the release.

Use `--dry-run` to build, zip, and print the sha256 without tagging or publishing (the version stamp is reverted):

```sh
scripts/release.sh 0.1.0 --dry-run
```

## Distribution-grade signing

Until these are configured, releases are functional but Gatekeeper-unfriendly. With an Apple Developer Program membership:

```sh
# once: store notary credentials in the keychain
xcrun notarytool store-credentials vitrina-notary \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

# then release with:
RELEASE_SIGN_IDENTITY="Developer ID Application: Mariano Miguel (TEAMID)" \
NOTARY_PROFILE=vitrina-notary \
scripts/release.sh 0.1.0
```

## CI

`.github/workflows/ci.yml` builds every push and pull request on a macOS runner — the badge in the README reflects it. Releases are cut locally by design: signing identities stay on your machine instead of in repository secrets. If that trade-off changes, the release script is the single source of truth to port into a workflow.
