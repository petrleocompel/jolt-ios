# Pavlok Android 2.5.17 — Reverse Engineering Findings

Source: Pavlok for Android 2.5.17 (package `com.pavlok3.core`, versionCode 927,
minSdk 26, targetSdk 36). Split APK bundle: base + 19 locale/abi splits.

Artifacts extracted under `re/` (gitignored): `re/base/assets/flutter_assets`,
`re/arm64/lib/arm64-v8a/libapp.so`, `re/libapp.strings.txt`, `re/dart_files.txt`.

## 1. Stack

**Flutter** app, Dart AOT (`libapp.so`, 23 MB). Release snapshot still contains
~4100 `package:...dart` source paths and all class/enum names, so the full module
graph is recoverable. Dart *logic* is not (native AArch64).

| Concern | Library |
|---|---|
| State | `flutter_bloc` / `bloc` (Cubits), `get_it`, `provider`, `flutter_hooks` |
| Nav | `auto_route` (~147 screens) |
| Models | `freezed` + `json_serializable` |
| HTTP | `dio` (+ `sentry_dio`) |
| Local | `hive_ce`, `sqflite`, `shared_preferences` |
| BLE | `flutter_blue_plus` + **3 first-party packages** (below) + `nordic_dfu` |
| Auth | `firebase_auth`, `google_sign_in`, `sign_in_with_apple`, `recaptcha_enterprise` |
| Backend svcs | Firebase (analytics, crashlytics, messaging, remote config, firestore) |
| Payments | `purchases_flutter` (RevenueCat) |
| Analytics | PostHog (`us.i.posthog.com`), Sentry, Smartlook, Firebase |
| Support | `intercom_flutter` |
| Health | `health` (Health Connect / HealthKit) |
| Phone triggers | `phone_state`, `readsms`, `flutter_contacts` |
| BG execution | `flutter_foreground_task`, `flutter_local_notifications`, `home_widget` |
| i18n | `easy_localization`, 6 locales (en, de, es, fr, ja, tr), 1948 keys |
| Design system | first-party `pavlok_ui` package (96 files) |

## 2. Backend

- REST base: `https://api.pavlok.com/api/v5`
- Log ingest: `https://api.logs.pavlok.com`
- Public API reference exists: <https://pavlok.readme.io>
- Firmware feed: `/firmwares/latest?mac_address=…`, binaries on S3 (Nordic DFU zips)
- Sentry DSN and PostHog host are embedded in the binary (client-side, not secrets
  we should reuse).

### Endpoint families seen in strings

`/users/login`, `/users/reset-password`, `/user/change-password`,
`/user/update-phone-number`, `/user/validate-otp`, `/user/settings/`,
`/social/auth-providers`, `/social/google`,
`/habits/habits/`, `/habits/user-habits/`, `/habits/habit-goals/`,
`/habits/habit-logs/`, `/habits/habit-records/all`,
`/alarms`, `/user-devices/`, `/phone-devices/`, `/device_logs/`, `/diagnostic_logs/`,
`/workflows/`, `/workflows/logs`,
`/challenges/`, `/challenges/global`, `/challenges/joined`,
`/friendships/*` (accept/cancel/reject/remove/get-friends/received-requests),
`/pokes/send/user/`, `/poke-permissions/`,
`/wallets/volts`, `/wallets/send-volts`, `/pv-store/products`, `/pv-store/redemption`,
`/badges/`, `/banners/`, `/notifications/`, `/entitlements/`,
`/measurements-logs/` (+ `/paginated`, `/key/heart_rate`),
`/sleep-dataset/` (+ `/bulk`), `/contents/categories/`,
`/ai-chat/threads/`, `/ai-chat/messages/`, `/ai-chat/feedbacks/`,
`/google-calendar/auth-url|status|disconnect`

## 3. Devices & BLE

Three first-party Dart packages:

| Package | Purpose |
|---|---|
| `pavlok_flutter_ble` (81 files) | Pavlok 2/3 + **Shock Clock Max (SCMax)**; alarms, timers, triggers, hand-detect, ANCS, diagnostic logs |
| `pavlok_flutter_ios_ble` | iOS-specific BLE bridge (present in pubspec, no Dart files in snapshot) |
| `pavlok_ring_ble` (42 files) | Pavlok Ring: HR, HRV, SpO2, sleep, steps, battery |

### GATT UUIDs found in `libapp.so`

Standard:
- `0000180A-…` Device Information — `2A24` model, `2A25` serial, `2A26` firmware rev,
  `2A27` hardware rev, `2A28` software rev, `2A29` manufacturer
- `0000180F-…` Battery — `2A19` level
- `00002902-…` CCCD

Shock Clock Max (`SCMaxControlPointsService`), Bluetooth-SIG-style v1 UUIDs:
- Service `66651000-39F4-11ED-92BD-832ABAC11AB4`
  - `66651001-…`, `66651002-…` (control-point write / notify pair)
- Service `66657000-39F4-11ED-92BD-832ABAC11AB4`
  - `66657001-…`

Legacy Pavlok 2/3 proprietary — **confirmed against a real Pavlok 3**
(fw 6.10.0, model `Pavlok-S`, advertised `Pavlok-3-E11D`).

Services use a vendor base; characteristics inside them are plain 16-bit:

| Service | Characteristics on device | Constant |
|---|---|---|
| `156E0000-A300-4FEA-897B-86F698D74461` | `0001`–`0008` | `kSetupServiceUuid` |
| `156E1000-…` | `1001`–`1008` | `kConfigServiceUuid` |
| `156E2000-…` | `2001`–`200A` | `kApplicationServiceUuid` |
| `156E4000-…` | `4001`, `4002` | *not referenced by the app* |
| `156E5000-…` | `5001`–`5003` | `kDiagnosticServiceUuid` |
| `156E6000-…` | `6002` | `kNotificationServiceUuid` |
| `156E7000-…` | `7001`, `7999` | `kFirmwareServiceUuid` |

The six vendor service UUIDs *are* in `libapp.so`, written with a stray dash
(`156E-1000-A300-4FEA-897B-86F698D74461`) — which is why a UUID-shaped regex
misses them. Grep for `156E`, not for a UUID pattern.

The sixteen 16-bit values in the binary are **characteristics**, not
services: `0x0001`, `0x0008`, `0x1001`, `0x1002`, `0x1003`, `0x1005`,
`0x1006`, `0x1008`, `0x2002`, `0x2009`, `0x200A`, `0x5001`, `0x5002`,
`0x5003`, `0x6002`, `0x7001`. (`flutter_blue_plus` renders 16-bit UUIDs
expanded against the Bluetooth base, which is why they appear as
`00001001-0000-1000-8000-00805f9b34fb` in the string table.) An earlier pass
read `0x1001` as the config *service* — it is a characteristic, and every
write failed at service lookup as a result.

Note `1004` and `1007` exist on the device but appear nowhere in the binary,
so the three stimulus outputs are among `1001 1002 1003 1005 1006 1008`.
Config-service properties as reported by the device: all `read|write`, except
`1003` which is `read|write|notify`.

#### Observed write behaviour (Pavlok 3, fw 6.10.0)

| Characteristic | 2-byte write | Result |
|---|---|---|
| `1001` | `01 14` | rejected — invalid attribute value length |
| `1002` | `01 3C` | rejected — invalid attribute value length |
| `1003` | `01 0A` | acknowledged, nothing audible |

`1001` and `1002` are therefore fixed-length and *not* two bytes. Every
config characteristic is readable, so the length and current contents can be
measured rather than guessed — `Diagnostics → Read all values` does this,
and `LegacyDeviceController` reads before every write to size its payload.

#### Fire vs. configure are different operations

The binary names both, separately:

- `performDeviceZap` / `PerformDeviceZapUsecase`, `performDeviceMotor`,
  `performDevicePiezo`, `performBeep`, `performStimulusBundle` — **fire**
- `updateDeviceZap` / `UpdateDeviceZapUsecase`, `updateMotor`, `updatePiezo`
  — **configure**, backed by `deviceZapConfig` / `deviceMotorConfig` /
  `devicePiezoConfig`

`1003` accepting a write while producing no output is what *configuring*
looks like. There is also `encodeTimerStimulusIntensityAndCount`, so
intensity and count are **packed into a combined value** somewhere in this
protocol rather than sent as two independent bytes — consistent with `1001`
and `1002` rejecting a 2-byte write.

Not found anywhere in the binary: `writeZap`, `writeStimulus`,
`writeVibration`. The full `write*` vocabulary is alarms, current time,
hand-detect config, ANCS config, and handshake/read commands — so firing does
not go through the same "write X to device" helpers the other features use.

#### Legacy constant names (`ble_uuids_constants.dart`)

The Dart snapshot's string table carries the *names* of every UUID constant,
recovered by grepping `re/libapp.strings.txt` for `init:k*Uuid`:

| Services | Characteristics |
|---|---|
| `kConfigServiceUuid` | `kZapCaracUuid`, `kVibrationCaracUuid`, `kBeepCaracUuid`, `kHandDetectCaracUuid`, `kTimeCaracUuid` |
| `kApplicationServiceUuid` | `kApplicationControlCharcUuid`, `kApplicationAlarmNotifyCharcUuid`, `kApplicationAlarmLoadedCharacUuid`, `kApplicationDownloadCharcUuid` |
| `kSetupServiceUuid` | `kSetupCharacUuid`, `kDaqControlCharacUuid` |
| `kDiagnosticServiceUuid` | `kDiagnosticCommandCharcUuid` |
| `kFirmwareServiceUuid` | `kFirmwareCharacUuid` |
| `kNotificationServiceUuid` | — |
| `kBatteryServiceUuid` (`180F`) | `kBatteryCracUuid` (`2A19`), `kBatteryDiagnosticCaracUuid` |
| `kDeviceInformationServiceUuid` (`180A`) | `cccdUuid` (`2902`) |

**The load-bearing conclusion: zap, vibe and beep are three separate
characteristics in `156E1000-…`, not one control point with a leading opcode
byte.**

Name→value assignment within the config service is still an inference: the
names are strings, the values they are initialised with are AOT machine code.
`BLE/Legacy/LegacyGATT.swift` carries the current best assignment
(`1001`/`1002`/`1003`); Diagnostics → "Read all values" dumps every readable
characteristic non-destructively, and Protocol lab sends arbitrary bytes, so
it is correctable against real hardware without a rebuild.

Stimulus payload fields come from the freezed `toString` fragments
`ZapConfig(count: `, `MotorConfig(count: `, `PiezoConfig(count: ` and the
shared separator `, level: ` — so each config is `(count, level)`. Byte order
between the two is not settled.

Advertised names: `Pavlok-1`, `pavlok-2`, `pavlok-3`, `Pavlok-RingL`,
`Pavlok-Smart-Ring`.

### SCMax wire protocol

Custom serialization the app calls **ESF** — see
`pavlok_flutter_ble/src/scmax/utils/esf_parser.dart` and
`esf_type_parsers/{esf_int,esf_bool,esf_string,esf_array,esf_list,esf_map,esf_null,esf_fix_bytes}.dart`,
plus `leb_128_parser.dart`. So: a **LEB128-varint, self-describing, CBOR/MessagePack-like
TLV format** over a control-point characteristic, with bulk/chunked transfer
(`SCMaxBulkMessageType`, `SCMaxBulkMessageStatus`, `SCMaxFileType`, `SCMaxLogSectorHeader`).

Known SCMax message models: handshake, MTU report, time report, battery report,
alarm data / alarm status / alarms dump / next alarm / alarm deleted,
triggers dump + trigger config, stopwatch status + opcode + stimulus config,
hand-detect status / profile data / read result, logs, file meta, tune config,
output model/type.

Stimulus primitives across all devices: **zap** (`zapConfig`), **vibe/motor**
(`motorConfig`), **beep/piezo** (`piezoConfig`), each with intensity + repetition;
`ButtonConfigModel` for physical-button actions; `HandDetectModel`;
`NextDstModel` for DST handling on-device.

> Not recovered: exact opcode numbers and byte layouts. Those live in AOT machine
> code. Getting them needs either (a) a BLE HCI snoop log from a real device, or
> (b) AArch64 disassembly of the ESF encoders. Plan for (a).

## 4. Feature modules (1488 Dart files under `package:pavlok/`)

| Module | Files | Module | Files |
|---|---|---|---|
| device | 286 | in_app_purchases | 46 |
| habits | 109 | badges | 38 |
| workflows | 87 | pavlok_store | 29 |
| friends | 84 | home | 29 |
| auth | 83 | notifications | 28 |
| settings | 65 | notification_centre | 28 |
| ring | 63 | active_alarm_manager | 25 |
| health_measurements | 63 | steps | 21 |
| challenges | 63 | health_records_integrations | 20 |
| alarms | 57 | stimulus_journal | 15 |
| ai_chat_bot | 56 | battery | 14 |
| sleep | 48 | + ~20 smaller | |

Smaller modules: banner, related_content, app_update_manager, remote_user_settings,
google_calendar, analytics, help, profile, menu, discover, app_widgets, app_reviews,
posthog, new_app_intro, integrations, health_data_sync, firebase_remote_config,
community, permission_handler.

### Screen inventory
147 `*Screen` classes, full list in `re/screens.txt`.

Rough grouping:
- **Auth/onboarding** (~20): OnBoarding, SignIn, SignUp, CreatePassword, ResetPassword,
  AddUserInfo, OnboardingDeviceType, OnboardingDeviceConnection, OnboardingSelectHabit,
  permission-request screens (BLE, location, notifications)
- **Device** (~30): ScanPavlokDevices, PairDevice, PairRing, DeviceStatus, DeviceInfo,
  DeviceDiagnostics, BatteryUsage, ConfigureDeviceButtons, DeviceHandDetect,
  ScMaxHandDetect, ScMaxStopwatch, DeviceTimerStopwatch, CheckFirmwareUpdate,
  InstallFirmwareUpdate, FirmwaresList, RingStatus, RingInfo, RingDiagnostics,
  StimulusListing, StimulusDetail, DeviceTourGuide, ZapIssue, DevicePairingIssues
- **Alarms** (~14): Alarms, AddStandardDeviceAlarm, AddStandardPhoneAlarm,
  EditStandardDeviceAlarm, AlarmDetails, PickStandardAlarmTime, DeviceAlarmTemplate,
  StandardAlarmWakeUpGuarantees, DeviceWakeupGuarantees, CustomizeDeviceWakeup,
  Stop{Regular,JJ,MathPuzzle,PuzzleGame,QRCode}Alarm, SolvePuzzleGame, ScanQRCode
- **Habits** (~12), **Challenges** (~6), **Friends/social** (~7),
  **Health/sleep/steps** (~18), **Badges** (~4), **Workflows** (~9 routes),
  **Store/subscriptions** (~7), **Settings** (~12), **AI coach/chat** (~4)

### Notable behaviours
- Alarms exist in two flavours: **device alarms** (stored on the wearable, survive
  phone-off) and **phone alarms**. "Wake-up guarantees" = dismissal challenges
  (jumping jacks, math puzzle, puzzle game, QR-code scan).
- **Workflows**: trigger→condition→action automation engine (time delay, Google
  Calendar, phone/SMS events, device events) with a template library and run logs.
- **ANCS** (`scmax_ancs_manager`): the wearable receives phone notifications.
- **Social**: friends, "pokes" (send a stimulus to a friend, gated by
  poke-permissions), challenges with team rankings, badges, a "Volts" virtual
  currency + redemption store.
- Foreground service keeps BLE alive; home-screen widgets via `home_widget`.

## 5. Legal note for the iOS rewrite

Independent reimplementation to interoperate with hardware the user owns is the
normal reading, but:
- Do **not** copy Pavlok's assets (images, sounds, videos, icons, fonts) or
  translation strings out of the APK — they are copyrighted. Write fresh copy.
- Do **not** reuse the embedded Sentry DSN / PostHog / Firebase project config.
- Whether to talk to `api.pavlok.com` depends on Pavlok's ToS; a device-only
  offline app avoids the question entirely.
