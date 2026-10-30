# Forex Market Hours

A beautiful, interactive macOS visualizer for forex trading sessions.
Market hours are computed locally — no account, no tracking. The only
network use is checking for app updates (Sparkle, about once a day or when
you choose "Check for Updates…").

![Forex Market Hours screenshot](docs/screenshot.png)

## Features

- **24-hour session map** — Sydney, Tokyo, Frankfurt, London and New York lanes with
  overlap bands, live NOW marker, true open/close times pinned to every bar, and
  inactive sessions greyed out
- **Scrub & play** — drag the timeline to preview any hour, or press Play to animate
  the market forward (15 market-minutes per second)
- **Timezone converter** — Local, UTC, Sydney, Tokyo, Frankfurt, London, New York
  (DST-aware)
- **Session cards** — live countdowns, progress, volatility meter, top pairs
  (incl. **XAU/USD** gold on London/New York); closed sessions grey out
- **Alerts** — distinct bells plus time-sensitive macOS banner popups on every
  session open/close, in live and play modes
- **Liquidity gauge, overlap strip** (incl. "Best to trade" London × New York),
  weekend-closed state
- **Interval timer tab** — a clock-aligned repeating beep at 1–60 minute
  intervals with a selectable macOS alert sound and start/pause/reset controls

## Install

Download `ForexMarketHours-<version>-macOS.dmg` from the
[Releases](https://github.com/Marvelxy/ForexMarketHours/releases) page,
open it and drag **Forex Market Hours** into **Applications**.
Runs on Apple Silicon and Intel (universal binary), macOS 14+.

> Unsigned developer build: on first launch, right-click the app → Open
> (or allow it in System Settings → Privacy & Security).

## Updates

The app updates itself via [Sparkle](https://sparkle-project.org/):

- **Check for Updates…** — in the app menu (Forex Market Hours →
  Check for Updates…), in Settings (⌘,), or via the About button in the app.
- Automatic checks run about once a day; toggle them in Settings.
- Releases are published on the
  [Releases](https://github.com/Marvelxy/ForexMarketHours/releases) page —
  each release ships the DMG plus the `appcast.xml` the updater reads.

Signing keys (already set up): the EdDSA keypair lives in the maintainer's
login keychain, the public key is in `Resources/Info.plist` (`SUPublicEDKey`),
and the private key is stored as the `SPARKLE_PRIVATE_KEY` repo secret for CI.
If the private key is ever lost, rotate it (see
[Sparkle docs](https://sparkle-project.org/documentation/#rotating-signing-keys))
and update both the plist and the secret — never commit the private key.

Every push to `main` (including merges) automatically cuts the next patch
release: CI stamps the version/build number, signs the update, and uploads the
DMG + appcast. To publish a specific version manually, push a tag such as
`git tag v1.4.0 && git push origin v1.4.0`.

> Production updates require a Developer ID signature + notarization; the
> local `make app` build uses an ad-hoc signature (fine for development).

## Build from source

Requires Xcode 16+ (Swift 6) on macOS.

```bash
make run-native   # fast dev loop: build for your Mac and launch
make app          # universal (arm64 + x86_64) .app bundle in ./build
make dmg          # drag-to-install DMG in ./dist  (VERSION=1.2.3 to tag it)
make install      # copy the bundle into /Applications
```

## Project layout

```
Package.swift                  # SwiftPM executable, macOS 14+
Sources/ForexMarketHours/
  ForexMarketHoursApp.swift    # @main app + window, Sparkle updater + Settings
  Updater.swift                # Sparkle wiring, Check-for-Updates views, AppInfo
  AboutView.swift              # About panel (author, version, update controls)
  MarketData.swift             # sessions, overlaps, UTC math, liquidity
  ContentView.swift            # timeline, cards, alerts, notifications
  TimerView.swift              # repeating interval timer + beep sounds
Scripts/
  build-app.sh                 # universal .app bundler + ad-hoc sign
  make-dmg.sh                  # drag-to-install DMG builder
  make-icon.swift              # generates AppIcon.icns (CoreGraphics, no assets needed)
Resources/Info.plist
.github/workflows/            # CI build + auto-release DMG pipeline
```

Session hours are anchored to each market's local time (e.g. London
08:00–17:00), so UTC offsets and daylight saving are handled automatically.
The trading week closes at New York's Friday close and reopens at Sydney's
Monday open.

## License

Copyright (C) 2026 Marvelous Akpotu (Marvelxy) — GNU General Public License v3.0 or later.
See [LICENSE](LICENSE). The DMG ships with a copy of the license.
