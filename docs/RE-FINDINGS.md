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

Legacy Pavlok 2/3 — **decompiled ground truth**, cross-checked against a real
Pavlok 3 (fw 6.10.0, model `Pavlok-S`).

### UUIDs (from `ble_uuids_constants.dart`)

Services use a vendor base, written in the Dart source with a stray dash
(`156E-1000-A300-…`), which is why a UUID-shaped regex over the string table
misses them. **The service names do not follow the numbering**: `156E5000` is
the application service, `156E0000` the diagnostic one.

| Service | Constant | Characteristics |
|---|---|---|
| `156E0000` | `kPavlokService` | `0001` battery diagnostic, `0008` diagnostic command |
| `156E1000` | `kConfigServiceUuid` | `1001` vibration, `1002` beep, `1003` zap, `1005` time, `1006` hand-detect, `1008` DAQ control |
| `156E2000` | `kNotificationServiceUuid` | `2002` events, `2009` notification files, `200A` alarm loaded |
| `156E5000` | `kApplicationServiceUuid` | `5001` control, `5002` download, `5003` alarm notify |
| `156E6000` | `kFirmwareServiceUuid` | `6002` |
| `156E7000` | `kSetupServiceUuid` | `7001` |

**Zap is `1003`, not `1001`.** The order is vibration, beep, zap.

### Stimulus wire format (from `ble_manager.dart`)

`performZap` / `performMotor` / `performPiezo` and `updateZap` /
`updateMotor` / `updatePiezo` write to the **same** characteristic. They
differ only by a constant added to byte 0:

    perform* → + 0x80   (fire now)
    update*  → + 0x40   (store as device default)

| Output | Char | Payload |
|---|---|---|
| zap | `1003` | `[count｜flag, level]` |
| vibration | `1001` | `[count｜flag, 0x0C, level, onInterval, offInterval]` |
| beep | `1002` | `[count｜flag, 0x0C, level, onInterval, offInterval]` |

The `0x0C` at index 1 is a literal in `performMotor`. The interval bytes come
from `MotorConfig.encodedOnInterval` / `encodedOffInterval`, which derive them
from millisecond fields.

Live device readback confirms every field:

    1001  01 0C 23 16 16    vibration, level 0x23 = 35
    1002  01 0C 64 16 16    beep,      level 0x64 = 100
    1003  01 19             zap,       level 0x19 = 25

**This is why earlier writes did nothing.** Byte 0 was copied back from the
device as `0x01`, with neither `0x80` nor `0x40` set — the device was told to
neither fire nor store, so it acknowledged the write and ignored it.

### Operation → characteristic map (from `ble_manager.dart`)

Every legacy operation, with the characteristic it actually writes:

| Operation | Service | Characteristic |
|---|---|---|
| `performZap` / `updateZap` | config `156E1000` | `1003` |
| `performMotor` / `updateMotor` | config | `1001` |
| `performPiezo` / `updatePiezo` | config | `1002` |
| `writeCurrentTimeToDevice` | config | `1005` time |
| `readHandDetectData` / `writeHandDetectData` | config | `1006` hand-detect |
| `writeAlarmBytesToDevice` | application `156E5000` | `5002` download |
| `writeReadAlarmCommand`, `turnOffDeviceAlarm`, `snoozeDeviceAlarm` | application | `5001` control |
| `listenToAlarmNotifier`, `getAlarmState` | application | `5003` alarm notify |
| `setButtonAction`, `getDeviceButtonActions`, `saveTimerToDevice` | **setup `156E7000`** | `7001` |
| `writeReadUserLogCommand`, `writeReadDiagnosticLogCommand` | notification `156E2000` | — |

Two of these contradict earlier guesses: button config lives in the *setup*
service, not the application one, and alarm slot bytes go to the download
characteristic (`5002`) while alarm *commands* go to the control point
(`5001`).

Payloads for alarms and button config are still unrecovered — `setButtonAction`
builds a variable-length list whose shape depends on the action type.

### Shock Clock Max

The Shock Clock Max code in the Android app is a much larger protocol than the
legacy one (~20k lines), and there is no SCMax hardware to verify against.

ESF is MessagePack-shaped. The decoder in `esf_parser.dart` dispatches on tag
ranges `0x7f/0x80`, `0x9f/0xa0`, `0xbf/0xc0`, `0xdf/0xe0`, `0xef/0xf0`,
`0xf7/0xf8`, `0xfc`, `0xfd`, `0xfe`, and the type parsers give:

| Type | Tag |
|---|---|
| positive fixint | `0x00`–`0x7f` inline |
| int (wider) | `0x80`, `0x90` prefixes |
| fixstr | `0xa0` \| len, len < `0x20` |
| array | `0xf4` |
| null | `0xfe` |

Timeout labels visible in `scmax_device_manager.dart` name the message set:
"Battery Report Timeout", "Time Report Timeout", "Hand Detect Dump Timeout",
"User Logs Timeout".

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
