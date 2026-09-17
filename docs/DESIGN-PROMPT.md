# Prompt for Claude Design — Jolt replica + design system

> Paste everything below the line into Claude Design and attach the
> screenshots from `fastlane/design_screenshots/dark/en-US/` (41 screens) plus
> `light/en-US/…-50-Onboarding.png` and `…-51-Onboarding-Scanning.png`.
> The rest of the `light/` set is visually identical to `dark/`: once the tabs
> appear the whole app switches to dark (see audit item 3).
> Regenerate with `bundle exec fastlane design_screenshots`.
> Filenames are prefixed by area: `0x` Remote, `1x` Alarms, `2x` Friends,
> `3x` quick poke / trigger + Remote with quick poke, `4x` Settings,
> `5x` Onboarding.

---

## Role and goal

You are a senior product designer for iOS. I'm attaching screenshots of **Jolt**, an iOS app I'm building (SwiftUI, iOS 17+, iPhone first, iPad supported). Work in three phases and **stop after each one** so I can give feedback before you continue:

1. **Replica.** Rebuild the current app faithfully as an interactive, clickable prototype: every screen, the same layout, copy, data and states. Don't improve anything yet. Where a screenshot and this description disagree, the screenshot wins; list those differences.
2. **Design system / design language.** Derive a coherent system from what exists and formalize it: principles, tokens, components, patterns, and voice. Use the audit below as the problems the system must solve.
3. **Redesign.** Apply the system to the key screens in iterations and propose UX improvements. Always show before/after and explain why.

The goal is to improve UX and UI step by step, so every output must be implementable in SwiftUI. Prefer native iOS components (List, Form, NavigationStack, sheet, TabView, SF Symbols) and only build custom where it adds real value. Respect Dynamic Type, Dark Mode, VoiceOver and a 44 pt minimum touch target.

## What Jolt is

Jolt is an independent iOS client for **Pavlok** wearables: wristbands that deliver a **Zap** (a mild electric shock), a **Vibe** (vibration) or a **Beep** (sound). People use them to break habits and to wake up. Jolt isn't affiliated with Pavlok Inc. and must not look like Pavlok's official branding.

Three pillars:

- **Remote:** fire a stimulus on your own wristband over Bluetooth.
- **Alarms:** wake-up alarms with a stimulus and a "wake-up guarantee" challenge.
- **Friends:** a social layer where friends can "poke" you (send a stimulus to your band remotely), within limits you allow.

Tone: playful but trustworthy. It's literally about electric shocks, so **safety, consent and control** must be visible. The user always needs to know what will fire, at what intensity, and on whose wrist.

## Domain model a designer needs

- **Stimulus:** Zap / Vibe / Beep. Intensity 0–100 % (relative, not volts), repetitions 1–5×. Remote defaults: Zap 20 %, Vibe 60 %, Beep 60 %. **High intensity is above 60 %**: it shows a HIGH badge and in Hold mode requires a second confirmation.
- **Firing mode** (per stimulus, in Settings):
  - Tap: fires immediately.
  - Hold: hold for 0.85 s while a ring or bar fills; letting go early cancels.
  - Confirm dialog.
- **Device:** Pavlok 2, Pavlok 3, Shock Clock Max. States: disconnected / scanning / connecting / connected / failed. Battery %, model, firmware. Hardware buttons (Top/Middle/Bottom, short and long press) can be reassigned.
- **Friends:**
  - Adding: by @handle, invite code, or QR code. Requests are Accept/Ignore; outgoing ones show as Pending.
  - **Permissions are two-way and asymmetric.** "What they let me send" (max intensity + cooldown per stimulus) and "what I let them send". Presets: Full / Trusted (≤60 %, 15 s) / Cautious (≤20 %, 2 min) / Off.
  - Do Not Disturb for incoming pokes.
- **Three ways to poke:**
  1. The **composer** on a friend's detail: pick the stimulus, intensity up to their cap, repetitions.
  2. **Quick poke:** a preset friend + stimulus as a card on Remote; one tap sends it.
  3. **Poke trigger:** a physical button on the wearable sends a poke to the chosen friend.
- **Poke status:** pending / fired / device not connected / not allowed / muted.
- **Alarms:**
  - Time, repeat days, stimulus, label.
  - **Device alarm:** stored in the wearable; fires even when the phone is off.
  - **Phone alarm:** a notification that Focus can silence.
  - Dismiss challenge: none / math puzzle / 10 jumping jacks (accelerometer) / scan any QR code.
- **Accounts:**
  - The Jolt account (email + password, handle, display name) lives on a Jolt server; the URL is configurable for self-hosting.
  - A Pavlok account can optionally be signed in separately (Pavlok friends, device log).
- **Poke feedback:** profiles Off / Minimal / Standard / Rich (banner, button flash, haptic, "Sent" label).

## Information architecture (current)

- **Launch:** black splash with a green bolt "J" logo, "Jolt Remote", "Your Pavlok, on your terms."
- **Gating:** without a connected device, the only screens are **Onboarding** ("Find your Pavlok", family filter Pavlok 2 / 3 / Shock Clock Max, Start scanning, list of found devices) and **Reconnecting**. Tabs appear only once connected. This is a known UX problem.
- **Tab bar:** Remote (`bolt.fill`) · Alarms (`alarm.fill`) · Friends (`person.2.fill`) · Settings (`gearshape.fill`).

### Remote (custom, always dark)

- **Dashboard of cards on #0A0A0A:**
  1. **Device hero:** status dot + CONNECTED, device name, family, large battery number with a bar, "More info ›".
  2. **Stimulus rows:** one each for Zap, Vibe and Beep. Each row has the icon, name, a large number "20 %", "tap to fire" / "hold to fire", and a HIGH badge. On the right is a 64 pt fire ring in green. Tapping the left side opens the intensity + repetitions editor (a system Form sheet, light in light mode).
  3. **Quick poke** (violet): friend avatar, name, chips "Vibe · 30 %", "×2", a bar "Tap to poke Alice", and ⋯ for the full composer.
  4. **Next alarm:** time, "in 7h 12m", "Zap 40 % · Scan a QR code".
  5. **Recent activity:** "Alice buzzed you · 30 min".
  6. Dashed "Customize home screen" button → sheet: reorder with arrows, remove, a gallery of widgets to add.
- **High-intensity confirmation:** black half sheet, amber "HIGH INTENSITY", a green hold bar.
- **Device detail:** device info, Disconnect, links to Diagnostics (GATT table, remap characteristics), Protocol lab (writes raw bytes), Bluetooth log, Button configuration. These are developer tools currently visible to regular users.

### Alarms (stock iOS List/Form)

- **List:** time, label, a toggle. Empty state "No alarms".
- **Editor (sheet):** wheel time picker, Mon–Sun buttons, Device/Phone segment, stimulus picker + intensity stepper, dismiss challenge, label.
- **Active alarm (full screen):** time + Dismiss, or a challenge screen (math, QR camera, a jumping-jacks ring with a counter).

### Friends

- **Signed out:** header "Connect with friends", segmented Log In / Sign Up, fields.
- **List:** sections Requests (Accept/Ignore), Friends ("@alice · can send: Zap, Vibe, Beep"), Pending, and a "Poke activity" link. Toolbar: profile, add friend.
- **Add friend (sheet):** handle, invite code, QR scanner, "Your code" with a QR code.
- **Friend detail:**
  - **Poke composer:** stimulus chips (violet when selected), a large intensity number, a slider up to the friend's cap, "Alice's cap: 30 %", repetitions stepper, a violet "Tap to poke Alice" bar.
  - Links: "Permissions you've granted Alice" (presets + per-stimulus Allow toggle, max intensity and cooldown sliders with editable numbers) and a destructive Remove friend.
- **Activity:** "You zapped Bob" / "Alice buzzed you", a relative time, and a status icon.
- **Profile:** initials avatar, stats, QR invite, share/copy handle, linked Pavlok account, Log out.

### Settings (stock List)

- **Device:** Connected, Disconnect, Forget device.
- **Pokes & Firing:** DND toggle, Poke from your Pavlok, Quick poke, Firing, Poke feedback.
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
| Stimulus tint | Zap orange, Vibe indigo, Beep teal | only on some sliders and headers |

- **Numerals:** SF Rounded semibold (a stand-in for Space Grotesk). Sizes 16/17/19/22/24/30/32/36/50.
- **Eyebrow labels:** caption2 semibold, uppercase, tracking 1.2.
- **Cards:** radius 22, padding 18, gap 14, screen margin 16. Subtle vertical gradient (tint 10 % → 1.5 %), 1 pt border (tint ~33 %, neutral white 13 %).
- **Other radii:** 17 hold bar, 14 chips/tiles, 8 small chips, 5 badge.
- **White opacities on dark:** used ad hoc (0.85 … 0.12) with no named tokens.
- **Hold bar:** 56 pt, fills left to right with 22 % white, flashes on send, label turns into "Sent".
- **Fire ring:** 64 pt, 3 pt progress arc from 12 o'clock.
- **Symbols:** Zap `bolt.fill`, Vibe `waveform`, Beep `speaker.wave.2.fill`; presets use `shield.*`; pokes use `hand.tap`.
- **InlineBanner:** a capsule on material at the bottom; errors red, success gray.
- **Haptics:** only success after a poke.
- **Logo:** a green bolt shaped like a "J" in a gray ring, on white or black.

## UX/UI audit — problems the design system and redesign must solve

1. **No device, no app.** Friends, Alarms and Settings are unreachable without a connected wristband, and Disconnect throws the user back to onboarding. Propose a navigation that works without hardware, with clear "device offline" states.
2. **Onboarding is missing states:** Bluetooth off or denied, nothing found, timeout. The family filter has no explanation.
3. **Two visual worlds + broken light mode.** Remote is custom and forced dark; everything else is stock iOS List/Form. The forced dark on Remote leaks to the whole window, so once connected the **entire app is dark even when the system is in light mode**; only onboarding is light. Design both appearances deliberately and say whether Remote should stay always-dark.
4. **Developer tools mixed into the product** (Protocol lab, GATT, raw hex, "Armed/Listening", "See docs/RE-FINDINGS.md"). Propose where to hide them (an Advanced / Developer mode) and how to phrase them.
5. **Six different intensity controls:** slider step 1 / step 5 / continuous up to a cap / stepper without % / slider + editable number / number only. The system needs one intensity component with variants (own device, capped by a friend, high-intensity warning).
6. **Inconsistent repetitions copy:** "×3", "3×", "Repetitions: 3", "Repeat: 3×".
7. **Five kinds of errors:** banner, red text, alert, orange validation, confirm dialog. Success is gray in some places and green in others. Define a single feedback pattern (banner / inline / blocking).
8. **Destructive actions without confirmation:** Remove friend, Forget device, Disconnect. Some errors are swallowed silently.
9. **Ambiguous permission copy.** "can send: Zap, Vibe" in the friends list means what *I* may send *them*. The two directions of permissions need to be visually unmistakable.
10. **Quick poke and poke trigger offer 0–100 % of any stimulus** even though the friend allows less; the server rejects it later. The UI should respect the caps.
11. **Dashboard widgets vanish silently** when unconfigured or empty, yet Customize shows them as "on the home screen". They need empty/setup states.
12. **Symbol collisions and inconsistent colors.** `bolt.fill` means the Remote tab, Zap and Quick poke. `waveform` means both Vibe and Poke feedback. Stimulus colors (orange/indigo/teal) are barely used, and fire rings are always green.
13. **Link text vs. screen title mismatches:** "Poke activity" → "Activity", "Customize home screen" → "Customize home", "Log In" vs "Sign in" vs "Log out", "Jolt Remote" vs "Jolt".
14. **Alarms:**
    - The row doesn't show repeat days, stimulus or challenge.
    - A new alarm defaults to Phone while the copy recommends Device.
    - Intensity is a stepper without %; time is always 24 h.
    - Challenges show no alarm context and have no snooze; the QR challenge has no state for camera denied.
15. **Firing modes (Tap/Hold/Confirm) have no explanation** in settings, and widget hints say "Hold to fire" even in Tap mode.
16. **Activity:** status icons have no legend; there's no filter or link from the Remote card.
17. **Long, technical section footers** (Poke trigger, Button config, Pavlok, Notifications).
18. **Unpolished details from the screenshots:**
    - Recent activity shows the time as "31 min, 32 sec".
    - The floating tab bar covers the ends of long section footers and the dashed "Customize" button on Remote.
    - Onboarding has a large empty area and the family chips don't read as a filter.
    - A DEBUG row "Simulate incoming poke" appears in friend detail.
19. **Haptics are almost unused** for an app built around physical feedback: none on hold progress, fire, or error.

## What I want from you

**Phase 1 — Replica**
- An interactive prototype of every screen from the screenshots, in light and dark. The Remote tab stays dark as it is today.
- Clickable flows: tabs, Remote → editor / customize / device detail, Alarms → edit, Friends → sign up → list → detail → permissions, Settings → subpages, onboarding.
- Real content from the screenshots: device `pavlok-3`, 82 %; friends Alice, Bob, Charlie (request), Dana (pending); alarms 07:00 "Wake up" and 14:30 "Stand up".

**Phase 2 — Design system "Jolt"**
- **Principles:** 3–5 short statements, e.g. "Consent is visible", "Every fire is intentional".
- **Tokens:** color (semantic: brand/device, social, danger/high-intensity, success, surface levels, text on dark and light), a white/black opacity scale as named tokens, type (text styles + numerals, Dynamic Type), spacing scale, radii, elevation/borders, motion (durations, curves), haptics.
- **Stimulus identity:** color, symbol and verb (zapped / buzzed / beeped) for Zap/Vibe/Beep, consistent across the app.
- **Components**, each with states (default / pressed / disabled / loading / error) and light + dark:
  - card (device / stimulus / social / neutral)
  - fire control (tap / hold / confirm + high intensity)
  - intensity control (own device / capped / read-only)
  - repetitions control
  - stimulus chip / picker
  - friend row + avatar
  - permission row + preset
  - poke status badge
  - alarm row
  - feedback banner (success / error / info)
  - empty state
  - setup / configure prompt
  - destructive confirmation
  - section footer
- **Patterns:** device offline, onboarding states, feedback after a fire, error handling, destructive actions, where developer tools live.
- **Voice & copy:** a terminology glossary (poke vs zap, sign in/out, repetitions), capitalization, error message tone.
- Everything as SwiftUI-ready specs: token names, values, the matching SF Symbol, and any native component to use.

**Phase 3 — Redesign** (priority order)
1. Navigation and state without a device + onboarding.
2. Remote dashboard + fire control + intensity.
3. Friend detail / poke composer + permissions.
4. Alarms list + editor + active alarm.
5. Settings (restructure, hide dev tools).

For each: before/after, a list of changes with the reasoning, and the impact on the component library.

Constraints: native iOS feel (not a web look), dark mode is first-class, don't copy Pavlok branding, keep electric green `#00E676` as the brand color. Violet as the "social" color is open for discussion: suggest whether to keep it.
