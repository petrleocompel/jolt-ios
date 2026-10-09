# Security policy

## Reporting a vulnerability

Please report security issues privately, not in public issues or pull requests:

- **Preferred:** [GitHub private vulnerability reporting](https://github.com/petrleocompel/jolt-ios/security/advisories/new)
  (Security tab → Report a vulnerability).
- **Email:** [petrleocompel@gmail.com](mailto:petrleocompel@gmail.com).

Include what you found, how to reproduce it, and the app version or commit.
You'll get an acknowledgement within a week; fixes ship in the next TestFlight
and App Store build, and the advisory is published once a fixed build is out.

## Scope

This repository is the iOS app: local storage of tokens and settings, the
Bluetooth link to the wearable, and how the app talks to a Jolt Server.
Issues in the server itself belong to
[petrleocompel/jolt-server](https://github.com/petrleocompel/jolt-server).
Issues in Pavlok's own devices, firmware or API should go to Pavlok Inc.

Only the latest release and `main` receive security fixes.
