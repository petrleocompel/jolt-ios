# Design ↔ app: parts missing from the design

Source design: [`docs/design/Jolt Replica.dc.html`](design/Jolt%20Replica.dc.html)
(Claude Design, "Jolt · Phase 1 replica"). The replica only covers states that
showed up in the design-reference screenshots. The app keeps everything below
even though the design doesn't show it.

Compare them side by side with `bundle exec fastlane design_compare`, which
writes `fastlane/design_screenshots/compare.html`.

## Kept on purpose (decided against the design)

| Area | Design | App | Why |
|---|---|---|---|
| Pair device presentation | Full screen pushed onto the current tab, with the tab bar showing | Modal sheet with **Not now**, using the design's layout | Pairing is a self-contained task that ends when a device connects, so the sheet closes itself. You can't switch tabs while it's open, so a scan never keeps running in the background. The tab bar doesn't cover the scan button, and the sheet works the same from Remote, Settings and Device detail. |
| First run | None; the app opens on the tabs | "Find your Pavlok" offer with **Continue without a device**, styled like the design's Pair device page | The first run offers pairing up front and still lets you skip it. |
| Device detail → Disconnect | Green row with an icon | Red destructive button | Disconnect is a destructive action. |

## States the design doesn't show

- **Paired but unreachable device** (out of range, switched off, connecting,
  scanning, failed). The design only has *connected* and *no device*. The app
  reuses the "Not connected" card layout with a state-specific label and
  message ("NOT CONNECTED · Out of range or switched off", "CONNECTING ·
  Looking for your Pavlok", "FAILED · <reason>"), and the button reads
  **Pair a different device**.
- **Settings → Device while paired but not connected**: shows "Device · Not
  connected" and keeps Disconnect and Forget device.
- **Scanning with no results yet**: a "Scanning…" spinner.
- **Unselected device-family chips**: the design only draws them selected.
- **Pair device title when a device is already paired**: the sheet reads
  "Pair a different device".
- **High-intensity confirmation, and Hold / Confirm firing modes**: the design
  only shows Tap mode (no HIGH badge, hold ring or confirm dialog).
- **Active alarm and dismiss challenges**: math puzzle, jumping jacks, QR scan.
- **Quick-poke composer loading and error states**: "Couldn't reach the server"
  with Retry, and "Friend not found".
- **Error and success banners** (`InlineBanner`) on Remote, Friends and pairing.
- **Notification test result** ("Arrived in 1.2 s").

## Functionality the design leaves out

- **Diagnostics**: "Listen for device events", "Reset to defaults" for the
  stimulus characteristic mapping, and the Protocol lab and Bluetooth log links
  inside Diagnostics. The design shows Protocol lab and Bluetooth log on Device
  detail only. The app has them in both places, and the Device detail rows now
  open real screens; in the design they aren't clickable.
- **Protocol lab and Bluetooth log screens**: not in the design at all.
- **Device detail → Protocol lab** reads the GATT table first (spinner, then an
  error state if the read fails). Diagnostics passes the table it already has.
