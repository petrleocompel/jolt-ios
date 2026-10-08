# Jolt

Control Pavlok wearables and wake up to them — an independent iOS client.

Peelco iOS app — XcodeGen + Fastlane.

## Server

Friends, permissions and pokes go through a [Jolt Server](https://github.com/petrleocompel/jolt-server).
The app ships pointing at `https://jolt.example.com/api/v1`, but the URL is a
setting — **Settings → Server** — so it can be aimed at a self-hosted instance
instead. The server repo's `docs/SELFHOSTING.md` covers running one.

Accounts are per-instance: switching servers signs you out, and friends and
poke history stay behind on the old one. The bearer token is kept in the
keychain, scoped to the server that issued it.

**Settings → Notifications** sends a test push through that server to this
phone — the same alert + silent pair a poke uses, but carrying no poke, so it
works with no friends, no permissions and (unless you ask it to fire) no
wearable connected. The phone acks it back, so "Arrived in 1.2s" means it
genuinely got there rather than that Apple accepted it. The same test lives on
the server's web dashboard under Devices.

Friends can also poke you from scripts, with API tokens minted on the
server's web dashboard (the app has no token UI). Whether a friend's scripts
may send you a given stimulus is a separate answer under **Friends → friend →
Permissions → Automated pokes**: Default, Allow or Block, where Default
follows the server's policy and says what that currently is. Presets and
slider edits never change it. Pokes a script sent are marked with a gearshape
in the activity log and on the dashboard. Against a server too old to know
about any of this, the setting is simply not shown.

`MockSocialBackend` still implements the same repository protocols
in-memory and is what snapshot/screenshot runs use, so the UI can be exercised
without a server.

### Test account

| Field | Value |
|-------|-------|
| Email | `tester@example.com` |
| Password | `REDACTED` |

## Requirements

- Xcode (iOS 17.0+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftlint`
- Ruby + Bundler
- Optional screenshots: ImageMagick (`brew install imagemagick`)

## Setup

```bash
xcodegen --spec project.yml
open Jolt.xcodeproj
bundle install
```

## Identity

| Field | Value |
|-------|-------|
| Bundle ID | `cz.peelco.jolt` |
| Team | `YCFL9S5UA8` |
| Scheme | `Jolt` |

## Fastlane

```bash
bundle exec fastlane generate_project
bundle exec fastlane dev              # lint + test + debug IPA
bundle exec fastlane beta             # Release IPA → TestFlight
bundle exec fastlane internal         # ad-hoc IPA (if enabled)
bundle exec fastlane appstore         # upload binary, no auto-submit (if enabled)
bundle exec fastlane screenshots      # capture + flatten (if enabled)
bundle exec fastlane design_compare   # app screens (light + dark) vs docs/design replica → fastlane/design_screenshots/compare.html
bundle exec fastlane store_assets     # screenshots + metadata upload (if enabled)
```

On CI, `store_assets` is wired as the manual `ios_store_assets` job in the
`publish` stage — it only unlocks once validate/build/distribute pass, and
never runs on its own. It needs ImageMagick on the runner and simulators
matching `fastlane/Snapfile` (overridable via `IPHONE_65_NAME` / `IPAD_13_NAME`).

```bash
```

Set `FASTLANE_RUN_XCODEGEN=1` to regenerate the project before build/screenshot lanes.

### App Store Connect API key

Prefer CI / env (never commit `.p8` or keys):

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_PATH` **or** `APP_STORE_CONNECT_KEY` (base64 PEM)

Local fallback: `fastlane/AuthKey_<KEY_ID>.p8` (gitignored) plus the key/issuer env vars.

Also: `APPLE_TEAM_ID`, `APP_IDENTIFIER`, optional `CHANGELOG`, `FASTLANE_APPLE_ID`.

## GitLab CI

macOS runners (`tags: [macos]`). Pipeline:

1. **validate** — `fastlane dev` on MRs and branches
2. **distribute** — on `main`: internal + TestFlight (if enabled)
3. **release** — manual on tag `vX.Y.Z` → App Store upload (if enabled)

CI sets `VERSION_CODE=$CI_PIPELINE_IID` for build numbers.

Configure protected CI variables for the ASC API key trio and team ID.

## URLs (App Store metadata)

- Marketing: https://petrleocompel.github.io/jolt-ios/
- Privacy: https://petrleocompel.github.io/jolt-ios/privacy/
- Support: https://petrleocompel.github.io/jolt-ios/support/

## Brand & assets

App icon, launch screen, and accent color are documented in [`docs/BRAND.md`](docs/BRAND.md).

| Element | Asset | Notes |
|---------|-------|-------|
| App icon | `Resources/Assets.xcassets/AppIcon.appiconset/` | Green J-bolt; light (white) and dark (black) variants |
| Launch screen | `LaunchBackground` + `LaunchLogo` in asset catalog | Configured via `UILaunchScreen` in `Info.plist` |
| Accent color | `Resources/Assets.xcassets/AccentColor.colorset/` | Electric green `#00E676` |

## Project layout

```
App/           # @main, root UI, AppEnvironment
Features/      # feature modules
Domain/        # non-UI logic
Resources/     # Info.plist, assets, localizations
docs/          # RE notes, brand guide (BRAND.md)
UITests/       # UI / screenshot tests
project.yml    # XcodeGen source of truth
fastlane/      # lanes, Snapfile, metadata
```

Regenerate after editing `project.yml`:

```bash
xcodegen --spec project.yml
```

## What this app is

An independent iOS client for Pavlok wearables (Pavlok 2, Pavlok 3, Shock Clock
Max). Not affiliated with or endorsed by Pavlok Inc. Reverse-engineering notes
from the Android app are in `docs/RE-FINDINGS.md`.

## Known gaps

- **Shock Clock Max wire protocol is unimplemented.** `BLE/SCMax/ESF` has a
  working LEB128/TLV codec (message *shape* recovered from the Android
  binary), but the actual opcode numbers and field layouts were compiled into
  machine code and could not be recovered by string analysis. `BLE/SCMax/ProtocolMap.swift`
  documents the values still needed and how to capture them (Android HCI
  snoop log while using the official app against a real device). Until then,
  Shock Clock Max connects and reads standard GATT (battery, device info) but
  cannot fire a stimulus.
- **Pavlok 2/3 legacy GATT** uses proprietary characteristics under the
  Bluetooth base UUID (`0x1001`–`0x7001` family). Implemented against the
  publicly known layout; unverified against real hardware.
- **Phone-side alarms cannot force a silenced iOS device to sound**, unlike
  Android. They're built on `UNNotificationRequest` (`Features/Alarms`).
  Reliable wake-the-phone behaviour would need Apple's Critical Alerts
  entitlement, which requires a written request to Apple and is out of scope
  for v1. Device alarms (stored on the wearable, fired by its own RTC) do not
  have this limitation and are the primary path.
