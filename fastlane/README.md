fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios generate_project

```sh
[bundle exec] fastlane ios generate_project
```

Regenerate Xcode project with XcodeGen

### ios lint

```sh
[bundle exec] fastlane ios lint
```

Run SwiftLint

### ios test_dev

```sh
[bundle exec] fastlane ios test_dev
```

Run tests on simulator

### ios build_dev

```sh
[bundle exec] fastlane ios build_dev
```

Build Debug development IPA

### ios dev

```sh
[bundle exec] fastlane ios dev
```

CI validation: lint + test + dev build

### ios build

```sh
[bundle exec] fastlane ios build
```

Build Release IPA for App Store / TestFlight

### ios build_internal

```sh
[bundle exec] fastlane ios build_internal
```

Build Release ad-hoc IPA for internal distribution

### ios internal

```sh
[bundle exec] fastlane ios internal
```

Internal distribution flow

### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Upload IPA to TestFlight

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build Release and upload to TestFlight

### ios testflight

```sh
[bundle exec] fastlane ios testflight
```

CI TestFlight lane (alias)

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture App Store screenshots, then flatten alpha

### ios design_screenshots

```sh
[bundle exec] fastlane ios design_screenshots
```

Capture every reachable screen in light + dark for design work

### ios design_reference

```sh
[bundle exec] fastlane ios design_reference
```

Render docs/design/Jolt Replica.dc.html per screen, next to the app's design_screenshots

### ios design_compare

```sh
[bundle exec] fastlane ios design_compare
```

Capture the app (design_screenshots), render the design, and build compare.html side by side

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots only to App Store Connect

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload text metadata from fastlane/metadata

### ios store_assets

```sh
[bundle exec] fastlane ios store_assets
```

Capture screenshots, flatten, upload screenshots + metadata

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
