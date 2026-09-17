# Design ↔ app: where they still differ

Source design: [`docs/design/Jolt Replica.dc.html`](design/Jolt%20Replica.dc.html)
(Claude Design, "Jolt · Phase 1 replica", refreshed with the missing states).
Compare them side by side with `bundle exec fastlane design_compare`, which
writes `fastlane/design_screenshots/compare.html`.

The replica now covers almost every state in the app. This file lists what is
still different, and why.

## Decided against the design

| Area | Design | App | Why |
|---|---|---|---|
| Feedback banner position | Full-width bar pinned to the top | Bottom inset above the tab bar or sheet edge, with the design's look (tinted, bordered, ×) | A top bar pushes content down under a finger that may be about to tap Fire again. The design's own "Pairing — Connect failed" banner renders *behind* the pair sheet. The bottom inset never shifts layout and stays visible in sheets. |
| Alarm firing copy | "Firing every 30 seconds until the challenge is done." / "The alarm keeps firing while the challenge is open." | Says the alarm rang once and offers snooze | A phone alarm is a single local notification and nothing re-fires. The copy describes what really happens. |
| Jumping jacks footer | "Counted from the accelerometer in your Pavlok" | "Counted with your phone's motion sensor…" | The count comes from the phone's accelerometer (CoreMotion). |
| QR challenge title | "Scan the code in your bathroom" | "Scan your saved code" | The app doesn't know where the code is. |
| Firing footer | "Hold needs a half-second press… anything above 70% always asks, whatever the mode." | "Hold needs a press of just under a second… In Hold mode, anything above 60% asks for a second hold." | Matches `FireControl`: the hold lasts 0.85 s, the high-intensity threshold is 60%, and only Hold mode adds the second confirmation. |
| Protocol lab default target | Preselected `156E1001` | "Choose…" | A stray tap mustn't write raw bytes to what may be the zap output. |

## Prototype-only controls, not built

- **Count one jack** (jumping jacks) and **Simulate a scan** (QR): stand-ins for
  real sensor and camera input.
- **The index sidebar's state switches**: the app reaches those states for real,
  and the UI tests drive them with `-noDevice`, `-fakeDeviceLink
  offline|connecting|failed` and `-ringAlarm`.

## In the app, not in the design

- **Hold-mode high-intensity sheet**: the "HIGH INTENSITY" confirmation that
  needs a second hold for anything above 60%, and the HIGH badge on stimulus
  cards.
- **Old QR alarms without a saved code** still accept any QR code, and the
  footer says so. QR is only offered as a "switch challenge" target when the
  alarm has a saved code (or is already a QR alarm), so switching can't become
  an easy way out.
- **Captured device events**: a "Captured events (N)" row under Diagnostics →
  Listen for device events. Diagnostics used to be its only entry point.
- **Protocol lab extras**:
  - A byte-count and properties line under the payload.
  - A toolbar link to the Bluetooth log.
  - "Last exchange" only logs writes (no read lines like `180F/2A19 read`),
    and without-response writes say "no response expected" instead of a fake
    ACK.
- **Share buttons in toolbars** (GATT dump, Bluetooth log), next to the
  design's Copy rows.
- **Wrong QR code** shows an error; after 1.5 s the scanner restarts.
- **Scanning with no results yet** shows a "Scanning…" spinner, which is in
  the design. With the fake device in the UI tests a result arrives instantly,
  so the screenshot shows the found device instead.
- **Out-of-range device detail** is only reachable while connected (through
  "More info"). The design has a 04c state for it, which the app doesn't show.
- **Connecting/failed copy**: the failed message is the app's own ("The
  connection didn't go through. Move closer, then try again."), and the label
  carries the real reason from Bluetooth.

## Light mode (the design is dark-only)

- **Remote** stays dark in light mode. The dark appearance is scoped to the
  Remote tab, not the window, so other tabs follow the system. Sheets opened
  from Remote (stimulus editor, alarm editor, pairing, quick-poke composer)
  are dark too.
- **Known rough edge:** the Confirm-mode alert ("Fire Zap?") is drawn by the
  system in the *window's* appearance. In light mode it shows as a light
  alert over the dark Remote, with weaker contrast.

## Not captured by the UI tests yet

These exist in the app and the design renders them, but the screenshot run
doesn't reach them hermetically:

- **Protocol lab reading / read failed** (07a, 07b): the fake device always
  returns a GATT table.
- **Hold mode on the Remote** (09b).
- **Poke composer: sending and server error** (35a, 36): the mock backend
  answers instantly and never fails.
- **Pair device: connect failed** (52d) and the "Scanning…" spinner (52b).
