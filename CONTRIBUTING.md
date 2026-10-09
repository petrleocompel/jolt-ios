# Contributing to Jolt

Thanks for helping. Bug reports, protocol findings and pull requests are all
welcome.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on
  the approach.
- Server-side changes (friends, pokes, push delivery) belong in
  [petrleocompel/jolt-server](https://github.com/petrleocompel/jolt-server).
- Follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues
  privately as described in [SECURITY.md](SECURITY.md).

## Development setup

See [Build from source](README.md#build-from-source). In short:

```bash
brew install xcodegen swiftlint
xcodegen --spec project.yml
open Jolt.xcodeproj
```

Edit `project.yml`, not the generated Xcode project settings, and commit the
regenerated `Jolt.xcodeproj` with it.

## Pull requests

- Keep each PR to one change, with a commit message that says why.
- `swiftlint --strict` must pass, and so must the tests:
  ```bash
  xcodebuild test -project Jolt.xcodeproj -scheme Jolt \
    -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
  GitHub Actions runs the same checks on every PR.
- Add or update tests for behaviour changes. UI tests run against
  `MockSocialBackend` (`-snapshotMode`) and the fake device (`-fakeDevice`), so
  they need neither a server nor a wearable.
- Bluetooth protocol changes: say which device and firmware you verified
  against, and update `docs/RE-FINDINGS.md`.
- Don't commit Pavlok's assets, strings or decompiled code; write fresh
  implementations from documented behaviour.

Signed builds, TestFlight and App Store releases run on the maintainer's
private CI after a PR is merged.

## License

By contributing, you agree that your contributions are licensed under the
[Mozilla Public License 2.0](LICENSE), the same license as the project.
