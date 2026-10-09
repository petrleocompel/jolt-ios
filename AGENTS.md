# Agent notes

## Remotes and mobile builds

- GitHub is the public repository; pull requests go there.
- If you are petrleocompel's agent: `origin` in this clone is his private GitLab, which builds and ships the iOS app, and `github` is the public repository. Push every `main` commit to both (`git push origin main && git push github main`), and push to `github` only `main` and release tags.
- Everyone else: mobile builds run on a private pipeline; GitHub Actions cover checks, the website and releases.

## Project

- `project.yml` is the XcodeGen source of truth; run `xcodegen --spec project.yml` after editing it and commit the regenerated `Jolt.xcodeproj`.
- Checks: `swiftlint --strict`, then the `xcodebuild test` command in `README.md` (Development).
- Never commit credentials, server hosts or signing material. Server URLs and test accounts come from build settings and environment variables (see `README.md`).
