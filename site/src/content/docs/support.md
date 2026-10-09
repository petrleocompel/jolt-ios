---
title: Support
description: Help with Jolt Remote, and how to get in touch.
---

## Get in touch

Found a bug or have an idea? Open an
[issue on GitHub](https://github.com/petrleocompel/jolt-ios/issues). For
anything you'd rather not post publicly, email
[petrleocompel@gmail.com](mailto:petrleocompel@gmail.com).

Include your device model (Pavlok 2, Pavlok 3 or Shock Clock Max), your iOS
version, and a short description of what happened. That's usually enough to
sort out most issues.

Security issues go through
[private vulnerability reporting](https://github.com/petrleocompel/jolt-ios/security/advisories/new)
instead; see the [security policy](https://github.com/petrleocompel/jolt-ios/blob/main/SECURITY.md).

## Common questions

### Jolt can't find my device

Make sure the device is charged and awake, that Bluetooth is on, and that you
granted Jolt the Bluetooth permission (iOS Settings → Jolt). If it was paired to
another app, disconnect it there first: a Pavlok can only hold one active
connection at a time.

### Do I need an account?

No. Controlling your own device (stimuli, alarms, button configuration) works
fully offline with no account. An account is only needed for the optional
friends and pokes feature.

### A friend's poke didn't fire

A poke can only fire while your phone can reach your device over Bluetooth and
Do Not Disturb is off. If your device was out of range or disconnected, the
notification still arrives, but the stimulus won't fire retroactively.
**Settings → Notifications** can send a test push to check delivery end to end.

### Which server does the app use?

Whichever you set under **Settings → Server**. Accounts are per server:
switching signs you out, and friends and poke history stay on the old one. To
run your own, see [Jolt Server](https://github.com/petrleocompel/jolt-server).

### Is this an official Pavlok app?

No. Jolt is an independent project and is not affiliated with or endorsed by
Pavlok Inc. It works with retail devices over their Bluetooth interface.

## Privacy

See the [privacy policy](/jolt-ios/privacy/) for exactly what the app stores and
what (if anything) leaves your device.
