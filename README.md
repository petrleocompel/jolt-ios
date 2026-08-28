# Jolt

Control Pavlok wearables and wake up to them — an independent iOS client.

Peelco iOS app — XcodeGen + Fastlane.

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
| Team | `REDACTED` |
| Scheme | `Jolt` |

## Fastlane

```bash
bundle exec fastlane generate_project
bundle exec fastlane dev              # lint + test + debug IPA
bundle exec fastlane beta             # Release IPA → TestFlight
bundle exec fastlane internal         # ad-hoc IPA (if enabled)
bundle exec fastlane appstore         # upload binary, no auto-submit (if enabled)
bundle exec fastlane screenshots      # capture + flatten (if enabled)
bundle exec fastlane store_assets     # screenshots + metadata upload (if enabled)
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
