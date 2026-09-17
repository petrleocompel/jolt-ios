# Prompt for Claude Design — Jolt design system and redesign

> Paste everything below the line into Claude Design, in the existing project
> (`Jolt Replica.dc.html` is the Phase 1 replica, and a local copy lives in
> `docs/design/`). Attach the screenshots from
> `fastlane/design_screenshots/dark/en-US/` and `…/light/en-US/`.
>
> Regenerate the screenshots with `bundle exec fastlane design_screenshots`.
> `bundle exec fastlane design_compare` also renders the replica and writes
> `fastlane/design_screenshots/compare.html`, with the app and the design side
> by side. Remaining differences are listed in `docs/design-missing-parts.md`.
>
> Filenames are prefixed by area:
>
> | Prefix | Area |
> |---|---|
> | `00` | First run |
> | `01`–`09` | Remote, device and firing states, developer tools |
> | `10`–`17` | Alarms, ringing alarm and challenges |
> | `20`–`29` | Friends |
> | `30`–`37` | Quick poke, poke trigger and composer states |
> | `40`–`47` | Settings |
> | `52` | Pairing |

---

## Role and goal

You are a senior product designer for iOS. **Jolt** is an iOS app I'm building (SwiftUI, iOS 17+, iPhone first, iPad supported). We work in three phases, and you stop after each one so I can give feedback:

1. **Replica. Done.** It's in this project as `Jolt Replica.dc.html`, and the app now matches it. The screenshots attached are the current app.
2. **Design system / design language. Next.** Derive a coherent system from what exists and formalize it: principles, tokens, components, patterns and voice. The open audit items below are the problems it has to solve.
3. **Redesign.** Apply the system to the key screens in iterations and propose UX improvements. Always show before and after, and explain why.

Every output must be implementable in SwiftUI. Prefer native iOS components (List, Form, NavigationStack, sheet, TabView, SF Symbols) and only go custom where it adds real value. Respect Dynamic Type, Dark Mode, VoiceOver and a 44 pt minimum touch target. **Design light and dark on purpose:** the app supports both, and only Remote is always dark.

## What Jolt is

Jolt is an independent iOS client for **Pavlok** wearables: wristbands that deliver a **Zap** (a mild electric shock), a **Vibe** (vibration) or a **Beep** (sound). People use them to break habits and to wake up. Jolt isn't affiliated with Pavlok Inc. and must not look like Pavlok's official branding.

Three pillars:

- **Remote:** fire a stimulus on your own wristband over Bluetooth.
- **Alarms:** wake-up alarms with a stimulus and a "wake-up guarantee" challenge.
- **Friends:** a social layer where friends can "poke" you (send a stimulus to your band remotely), within limits you allow.

**The wearable is optional.** Friends, pokes, phone alarms and settings all work without one. Only firing at your own wrist needs a device.

Tone: playful but trustworthy. It's literally about electric shocks, so **safety, consent and control** must be visible. The user always needs to know what will fire, at what intensity, and on whose wrist.

## Domain model a designer needs

- **Stimulus:** Zap / Vibe / Beep.
  - Intensity is 0–100 % (relative, not volts); repetitions are 1–5×.
  - Remote defaults: Zap 20 %, Vibe 60 %, Beep 60 %.
  - **High intensity is above 60 %:** it shows a HIGH badge, and in Hold mode needs a second hold in a "HIGH INTENSITY" sheet.
- **Firing mode** (per stimulus, set in Settings → Firing):
  - Tap: fires immediately.
  - Hold: hold for 0.85 s while a ring or bar fills; letting go early cancels.
  - Confirm: a centred alert, "Fire Zap? — Zap at 20% on pavlok-3", with Cancel / Fire.
- **Device:** Pavlok 2, Pavlok 3, Shock Clock Max.
  - The card reads one of five states:
    - *connected*
    - *no device* (never paired)
    - *not connected* (paired but out of range, switched off, or Bluetooth off)
    - *connecting*
    - *failed* (with the Bluetooth reason)
  - Paired devices are remembered by name and reconnect automatically; **Try again** reconnects now.
  - Battery %, model and firmware come from the device.
  - The hardware buttons (Top/Middle/Bottom, short and long press) can be reassigned.
- **Pairing:**
  - Pick one family, scan, and tap a found device. Rows show its signal strength, e.g. "Pavlok 3 · −54 dBm".
  - It's always a sheet with **Not now**, opened from the first-run screen, the Remote card, Settings → Device and Device detail.
  - A failed connection shows "Couldn't connect to pavlok-3. Move closer and try again."
- **Friends:**
  - Adding: by @handle, invite code, or QR code. Requests are Accept/Ignore; outgoing ones show as Pending.
  - **Permissions are two-way and asymmetric.** "What they let me send" (max intensity + cooldown per stimulus) and "what I let them send". Presets: Full / Trusted (≤60 %, 15 s) / Cautious (≤20 %, 2 min) / Off.
  - Do Not Disturb for incoming pokes.
- **Three ways to poke:**
  1. The **composer** on a friend's detail: pick the stimulus, intensity up to their cap, and repetitions.
     - While sending, the button becomes "Sending…".
     - A failure replaces the button with a card: "COULDN'T REACH THE SERVER" or "POKE NOT SENT", with Retry / Dismiss.
  2. **Quick poke:** a preset friend + stimulus as a card on Remote; one tap sends it, and ⋯ opens the full composer. If that friend has gone, the composer shows a "FRIEND NOT FOUND" card.
  3. **Poke trigger:** a physical button on the wearable sends a poke to the chosen friend.
- **Poke status:** pending / fired / device not connected / not allowed / muted.
- **Alarms:**
  - Time, repeat days, stimulus, label.
  - **Device alarm:** stored in the wearable; fires even when the phone is off.
  - **Phone alarm:** one local notification, which Focus can silence.
  - Dismiss challenge: none / math puzzle (three answer choices) / 10 jumping jacks (counted by the **phone's** motion sensor) / scan a **saved** QR code. You scan and save the code in the alarm editor; older alarms without one accept any code.
  - **Ringing screen** (for a phone alarm, when its notification arrives or is tapped): the time, label, "Dismiss — <challenge>" and **Snooze 9 min** (re-schedules once). Challenges can be switched: math ↔ jacks ↔ QR (QR only if a code is saved).
- **Accounts:**
  - The Jolt account (email + password, handle, display name) lives on a Jolt server; the URL is configurable for self-hosting.
  - A Pavlok account can optionally be signed in separately (Pavlok friends, device log).
- **Poke feedback:** profiles Off / Minimal / Standard / Rich (banner, button flash, haptic, "Sent" label).

## Information architecture (current)

- **Launch:** black splash with a green bolt "J" logo, "Jolt Remote", "Your Pavlok, on your terms."
- **First run** (only until you pair or skip): "Find your Pavlok", "Pair now to fire from your phone, or carry on without one — alarms, friends and pokes work either way.", then **Pair a device** (opens the pairing sheet) and **Continue without a device**.
- **Tab bar**, always available: Remote (`bolt.fill`) · Alarms (`alarm.fill`) · Friends (`person.2.fill`) · Settings (`gearshape.fill`).
- **Ringing alarm:** full screen, always dark, above everything.

### Remote (custom, always dark, scoped to this tab)

- **Dashboard of cards on #0A0A0A:**
  1. **Device card:**
     - **Connected:** status dot + CONNECTED, device name, family, large battery number with a bar, "More info ›".
     - **No device:** "NO DEVICE · Not connected", "Alarms, friends and pokes still work. Firing needs a paired Pavlok.", then a green **Pair a device** button.
     - **Not connected / connecting / failed:**
       - Status line in orange, cyan or red respectively, with the reason.
       - The device name as the title and one line of explanation.
       - **Try again** (green) and **Pair a different device** (grey).
  2. **Stimulus rows:** one each for Zap, Vibe and Beep.
     - Each row has the icon, name, a large "20 %", "tap / hold / confirm to fire", and a HIGH badge.
     - On the right is a 64 pt fire ring in green.
     - Tapping the left side opens the intensity + repetitions editor (a sheet).
     - With no device the rows are dimmed to 40 %. Tapping fire shows the error banner "No device connected. Pair one to fire."
  3. **Quick poke** (violet): friend avatar, name, chips "Vibe · 30 %", a bar "Tap to poke Alice", and ⋯ for the full composer. It's only shown once configured in Settings.
  4. **Next alarm:** time, "in 7h 12m", "Zap 40 % · Scan a QR code".
  5. **Recent activity:** "Alice buzzed you · 30 min".
  6. Dashed "Customize home screen" button → sheet: reorder with arrows, remove, a gallery of widgets to add.
- **Device detail:**
  - Hero card: 84 pt icon, name, and "CONNECTED · 82%".
  - Device info rows.
  - **Pair a different device**, **GATT inspector & diagnostics**, **Protocol lab**, **Bluetooth log**, **Button configuration**.
  - A red-bordered **Disconnect** button.
- **Developer tools** (still visible to everyone; see audit 4):
  - **Diagnostics:** device info; the GATT table with Read all values and Copy GATT dump; stimulus characteristic remapping; and a Live events section (Listen toggle, captured events, Protocol lab and Bluetooth log links).
  - **Protocol lab:** characteristic, hex payload, write with/without response, Send payload, and a "Last exchange" log. It has a reading state and a read-failed card with Retry.
  - **Bluetooth log:** monospaced lines, Copy log, Clear log. It keeps the last 500 lines of the current launch.

### Alarms (stock iOS List/Form)

- **List:** time, label, a toggle. Empty state "No alarms".
- **Editor (sheet):**
  - Wheel time picker, Mon–Sun buttons, and a Device/Phone segment.
  - Stimulus picker + intensity stepper, and a label.
  - Dismiss challenge; for QR, "Scan code to save" / "Code saved · Rescan".
- **Ringing:** "ALARM · ZAP 40%", the huge time, label, a bolt ring, one honest line about what happens, **Dismiss — <challenge>**, **Snooze 9 min**.
- **Challenges** (each has an eyebrow + title):
  - **Math:** a problem card with three answer buttons and links to switch challenge.
  - **Jumping jacks:** a "3 / 10" counter with a progress bar and Switch challenge.
  - **QR:** a camera preview with a dashed guide, a wrong-code error and Switch challenge.

### Friends

- **Signed out:** header "Connect with friends", segmented Log In / Sign Up, fields.
- **List:** sections Requests (Accept/Ignore), Friends ("@alice · can send: Zap, Vibe, Beep"), Pending, and a "Poke activity" link. Toolbar: profile, add friend.
- **Add friend (sheet):** handle, invite code, QR scanner, "Your code" with a QR code.
- **Friend detail:**
  - **Poke composer:**
    - Stimulus chips (violet when selected).
    - A large intensity number and a slider up to the friend's cap, labelled "Alice's cap: 30 %".
    - Repetitions stepper and a violet "Tap to poke Alice" bar.
    - Sending and error states as described above.
  - Links: "Permissions you've granted Alice" (presets + per-stimulus Allow toggle, max intensity and cooldown sliders with editable numbers) and a destructive Remove friend.
- **Activity:** "You zapped Bob" / "Alice buzzed you", a relative time, and a status icon.
- **Profile:** initials avatar, stats, QR invite, share/copy handle, linked Pavlok account, Log out.

### Settings (stock List, follows system appearance)

- **Device:**
  - Connected: `Connected · pavlok-3`, Disconnect, Forget device, Pair a different device ›.
  - No device: `Device · None paired`, Pair device ›.
  - Paired but not connected: `Device · Not connected` with an orange icon.
- **Pokes & Firing:** DND toggle, Poke from your Pavlok, Quick poke, Firing (per-stimulus mode + explanation), Poke feedback.
- **Notifications:** diagnostics plus sending a test push, with "Arrived in 1.2 s".
- **Account:** Pavlok account, Server (URL, Test connection, Save and switch; https only).
- **About.**
- **Quick poke:** enable toggle, friend picker, stimulus, intensity slider (step 5), repetitions, status.
- **Poke trigger:** enable toggle, friend, stimulus, intensity, button choice or "learn a gesture" (raw hex), a device event log, status Listening/Armed.

## Current visual language (from code)

| Token | Value | Use |
|---|---|---|
| Accent / brand | `#00E676` electric green | device, local fire, primary actions, logo |
| Violet | `#8F7BFF`, text on it `#C9BEFF` | social layer: pokes, quick poke, composer |
| Amber | `#FFB020` | HIGH / high intensity warning |
| Remote background | `#0A0A0A` | dark dashboard |
| Link states | orange (not connected), cyan (connecting), red (failed), grey (no device) | device card status line |
| Stimulus tint | Zap orange, Vibe indigo, Beep teal | only on some sliders and headers |

- **Numerals:** SF Rounded semibold (a stand-in for Space Grotesk). Sizes 16/17/19/22/24/26/30/32/36/50.
- **Eyebrow labels:** caption2 semibold, uppercase, tracking 1.2.
- **Cards:** radius 22, padding 18, gap 14, screen margin 16. Subtle vertical gradient (tint 10 % → 1.5 %), 1 pt border (tint ~33 %, neutral white 13 %).
- **Other radii:** 18 status cards and Disconnect, 17 hold bar, 16 banner, 14 chips/tiles, 8 small chips, 5 badge. Primary actions are capsules (50–54 pt tall).
- **White opacities on dark:** used ad hoc (0.85 … 0.10) with no named tokens.
- **Hold bar:** 56 pt, fills left to right with 22 % white, flashes on send, label turns into "Sent" or "Sending…".
- **Fire ring:** 64 pt, 3 pt progress arc from 12 o'clock.
- **Symbols:** Zap `bolt.fill`, Vibe `waveform`, Beep `speaker.wave.2.fill`; presets use `shield.*`; pokes use `hand.tap`.
- **InlineBanner** (transient feedback):
  - A rounded card pinned to the **bottom** safe area, above the tab bar or the sheet edge.
  - Tinted and bordered: red for errors, green for success. There's a × to dismiss; success clears itself after 3 s.
  - Kept at the bottom on purpose: it never shifts content under a finger about to fire, and it stays visible inside sheets.
- **StatusCard:** a tinted card that *replaces* a control until acknowledged: an eyebrow (e.g. "COULDN'T REACH THE SERVER"), a message, and capsule actions (Retry / Dismiss / Close). Used in the poke composer, quick poke and Protocol lab.
- **Haptics:** only success after a poke.
- **Logo:** a green bolt shaped like a "J" in a gray ring, on white or black.

## UX/UI audit — status

Resolved during Phase 1 (don't re-solve, but do fold into the system):

- ~~**1. No device, no app.**~~ Every tab works without a device. Remote, Settings and Device detail show clear device states and offer pairing.
- ~~**3. Broken light mode.**~~ Remote's dark appearance no longer leaks to the whole window; other tabs follow the system. *Still open:* design light mode deliberately, and decide whether Remote should stay always dark.
- **2. Onboarding states:** partly done.
  - Done: first run is a two-button offer, pairing has scanning / found / failed, and the device card shows the Bluetooth reason (off, denied, not found).
  - Open: a dedicated Bluetooth-off/denied screen with a Settings deep link, and an empty state for "nothing found" after a timeout.
- **7. Feedback:** partly done. The banner and StatusCard are unified. Open: validation text in forms is still ad hoc red/orange text, and some flows still use alerts.
- **14. Alarms:** partly done.
  - Done: snooze, saved QR code, switchable challenges, math as choices.
  - Open:
    - The row doesn't show repeat days, stimulus or challenge.
    - A new alarm defaults to Phone.
    - Intensity is a stepper without %; time is always 24 h.
    - No camera-denied state for QR.
- **15. Firing modes:** explained in Settings. Open: widget descriptions in Customize still say "Hold to fire" in every mode.

Open, for the design system and redesign to solve:

4. **Developer tools mixed into the product** (GATT, Protocol lab, raw hex, "Armed/Listening", "See docs/RE-FINDINGS.md"). Propose where to hide them (an Advanced / Developer mode) and how to phrase them.
5. **Six different intensity controls:** slider step 1 / step 5 / continuous up to a cap / stepper without % / slider + editable number / number only. The system needs one intensity component with variants (own device, capped by a friend, high-intensity warning).
6. **Inconsistent repetitions copy:** "×3", "3×", "Repetitions: 3", "Repeat: 3×".
8. **Destructive actions without confirmation:** Remove friend, Forget device, Disconnect.
9. **Ambiguous permission copy.** "can send: Zap, Vibe" in the friends list means what *I* may send *them*. The two directions of permissions need to be visually unmistakable.
10. **Quick poke and poke trigger offer 0–100 % of any stimulus** even though the friend allows less; the server rejects it later. The UI should respect the caps.
11. **Dashboard widgets vanish silently** when unconfigured or empty (Quick poke before setup, Next alarm with no alarms, Recent activity with no pokes), yet Customize shows them as "on the home screen". They need empty/setup states.
12. **Symbol collisions and inconsistent colors.** `bolt.fill` means the Remote tab, Zap, Quick poke and the pairing logo. `waveform` means both Vibe and Poke feedback. Stimulus colors (orange/indigo/teal) are barely used, and fire rings are always green.
13. **Link text vs. screen title mismatches:** "Poke activity" → "Activity", "Customize home screen" → "Customize home", "Log In" vs "Sign in" vs "Log out", "Jolt Remote" vs "Jolt".
16. **Activity:** status icons have no legend; there's no filter or link from the Remote card.
17. **Long, technical section footers** (Poke trigger, Button config, Pavlok, Notifications, Diagnostics).
18. **Unpolished details:**
    - Recent activity shows the time as "31 min, 32 sec".
    - The floating tab bar covers the ends of long section footers and the dashed "Customize" button on Remote.
    - A DEBUG row "Simulate incoming poke" appears in friend detail (debug builds only).
19. **Haptics are almost unused** for an app built around physical feedback: none on hold progress, fire, or error.
20. **The ringing eyebrow "ALARM · ZAP 40%"** suggests the phone fires the stimulus. For a phone alarm it doesn't; it's just the alarm's setting.

## What I want from you now

**Phase 2 — Design system "Jolt"** (a separate file in this project, next to the replica)
- **Principles:** 3–5 short statements, e.g. "Consent is visible", "Every fire is intentional".
- **Tokens:**
  - Color (semantic): brand/device, social, danger/high-intensity, success, the device link states, surface levels, and text on dark and light.
  - A white/black opacity scale as named tokens.
  - Type: text styles + numerals, Dynamic Type.
  - Spacing scale, radii, elevation/borders.
  - Motion: durations, curves.
  - Haptics.
- **Stimulus identity:** color, symbol and verb (zapped / buzzed / beeped) for Zap/Vibe/Beep, consistent across the app.
- **Components**, each with states (default / pressed / disabled / loading / error) and light + dark:
  - card (device in all five link states / stimulus / social / neutral)
  - fire control (tap / hold / confirm + high intensity + no device)
  - intensity control (own device / capped / read-only)
  - repetitions control
  - stimulus chip / picker
  - friend row + avatar
  - permission row + preset
  - poke status badge
  - alarm row
  - feedback banner (bottom; success / error / info)
  - status card (error / warning / info, with actions)
  - empty state
  - setup / configure prompt
  - destructive confirmation
  - section footer
  - challenge screen scaffold (eyebrow, title, body, primary + switch)
- **Patterns:** device offline and reconnecting, onboarding states (including Bluetooth off/denied), feedback after a fire, error handling, destructive actions, where developer tools live.
- **Voice & copy:** a terminology glossary (poke vs zap, sign in/out, repetitions), capitalization, error message tone.
- Everything as SwiftUI-ready specs: token names, values, the matching SF Symbol, and any native component to use.

**Phase 3 — Redesign** (priority order)
1. Remote dashboard + fire control + intensity (including the no-device and offline states).
2. Friend detail / poke composer + permissions.
3. Alarms list + editor + ringing and challenges.
4. Settings (restructure, hide developer tools).
5. First run and pairing (Bluetooth off/denied, nothing found).

For each: before/after, a list of changes with the reasoning, and the impact on the component library.

Constraints: native iOS feel (not a web look), dark mode and light mode are both first-class, don't copy Pavlok branding, keep electric green `#00E676` as the brand color. Violet as the "social" color is open for discussion: suggest whether to keep it. Keep the feedback banner at the bottom unless you have a better answer to the layout-shift and sheet-visibility problems.
