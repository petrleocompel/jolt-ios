---
title: Privacy policy
description: What Jolt Remote stores, what leaves your device, and what never does.
lastUpdated: 2026-10-09
---

Jolt Remote ("Jolt", "the app") is an independent companion app for Pavlok
wearable devices, published by Petr Leo Compel (Peelco). It is not affiliated
with, endorsed by, or sponsored by Pavlok Inc. This policy explains what the app
does and does not collect.

**The short version:** controlling your own device happens entirely on your
iPhone or iPad and needs no account. The only data that leaves your device is
what you opt into when you use the friends feature or sign in to a third-party
account.

## Stays on your device

The following never leaves your phone. It is stored locally (and in your own
iCloud backup, if you have one enabled) and is not sent to us:

- Which Pavlok device you have paired, and its Bluetooth identifiers
- Your stimulus settings, button configuration and alarms
- Device status you read over Bluetooth: battery, firmware, connection state

## Permissions the app asks for

**Bluetooth.** Required to find, pair with and control your Pavlok device. Jolt
talks to the device directly; it does not send your device data anywhere.

**Notifications.** Used for on-device alarm alerts and, if you use the friends
feature, to deliver an incoming poke. You can decline or revoke this in iOS
Settings at any time.

**Camera.** Used only if you set up the "scan a QR code" wake-up guarantee for
an alarm. Camera frames are processed on-device to read the code and are never
stored or transmitted.

## Optional: the Jolt friends account

If you choose to create a Jolt account to add friends and trade pokes, the Jolt
Server you use stores only what that feature needs:

- Your email address, chosen handle and display name
- Your password, stored only as a salted hash, never in plain text
- Your friends, and the per-friend permissions and limits you set
- A record of pokes sent and received, and their delivery status
- An Apple Push Notification (APNs) token for each device you sign in on, so a
  poke can be delivered, or a push relay's token in its place (see below)

A poke push contains the sender's name and the stimulus to fire, so your device
can act on it immediately. Poke history is retained for a limited period (90
days by default) and pending friend requests expire automatically.

**Push relay.** A server without its own Apple credentials can deliver pokes
through a Jolt push relay. The app then registers with the relay directly: it
sends the relay this device's APNs token, the app's bundle ID, your server's ID
and, where the device supports it, an Apple App Attest statement that the
request comes from a genuine copy of the app. Your server receives the relay's
token instead of the APNs token, together with a key generated on your device.
Pokes are encrypted with that key before they leave the server, so the relay
sees which server sent a message, to which registration, whether it was a poke
or a test, its size and when it was sent, but not who sent it or what it
contains. Signing out revokes the registration and deletes the key.

The friends server is [open source](https://github.com/petrleocompel/jolt-server)
and the app can point at any instance (**Settings → Server**). When you use an
instance someone else runs, that data lives on their server and their privacy
policy applies.

## Optional: signing in to a Pavlok account

Jolt can optionally sign in to a first-party Pavlok account on your behalf so
you can poke your existing Pavlok friends. If you use this, your Pavlok email
and password are sent only to Pavlok's own API; we never receive or store them.
The session token Pavlok returns is kept in your device's Keychain and used only
to make requests you initiate.

## What we do not do

- No analytics, advertising, or third-party tracking SDKs
- No selling or sharing of personal data
- No collection of your location, contacts, or health data

## Children

Jolt is not directed at children under 13, and we do not knowingly collect data
from them.

## Your choices

You can delete your Jolt account at any time, which removes your profile,
friends, permissions and poke history from the server. Revoking notification or
Bluetooth permission in iOS Settings disables the corresponding features.
Deleting the app removes all locally stored data.

## Contact

Questions about this policy or your data? Email
[petrleocompel@gmail.com](mailto:petrleocompel@gmail.com) or see the
[support page](/jolt-ios/support/).

## Changes

If this policy changes materially, the "last updated" date on this page will
change and, where appropriate, the app will surface a notice. The full history
of this page is public in the
[repository](https://github.com/petrleocompel/jolt-ios/commits/main/site/src/content/docs/privacy.md).
