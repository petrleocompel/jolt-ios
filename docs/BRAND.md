# Jolt brand assets

Visual identity for the Jolt iOS app (independent Pavlok companion by Peelco).

## Concept

The mark combines two ideas:

1. **Electric bolt badge (A)** — a bold lightning bolt echoing the in-app `bolt.circle.fill` motif used on onboarding and device discovery.
2. **“J” monogram (C)** — the bolt stroke forms the letter **J** for **Jolt**, readable at small icon sizes.

The design is intentionally distinct from official Pavlok branding (Jolt is not affiliated with or endorsed by Pavlok Inc.).

## Color palette

| Role | Name | Hex | sRGB components | Usage |
|------|------|-----|-----------------|-------|
| Primary accent | Electric green | `#00E676` | R 0.000, G 0.902, B 0.463 | App icon symbol, launch logo, `AccentColor` |
| Light background | White | `#FFFFFF` | R 1.000, G 1.000, B 1.000 | App icon (light), launch screen (light) |
| Dark background | Black | `#000000` | R 0.000, G 0.000, B 0.000 | App icon (dark), launch screen (dark) |
| Ring (light) | Light gray | `#E8E8E8` | — | Subtle circle badge on light app icon |
| Ring (dark) | Dark gray | `#2A2A2A` | — | Subtle circle badge on dark app icon |

## App icon

**Location:** `Resources/Assets.xcassets/AppIcon.appiconset/`

| File | Appearance | Description |
|------|------------|-------------|
| `AppIcon.png` | Default (light) | Green J-bolt with gray circle ring on white, 1024×1024 |
| `AppIcon-Dark.png` | Dark | Same symbol on black, 1024×1024 |

Configured in `Contents.json` with a `luminosity` / `dark` appearance variant. Referenced by Xcode via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in `project.yml`.

## Launch screen (splash)

**Configuration:** `Resources/Info.plist` → `UILaunchScreen`

| Asset | Location | Description |
|-------|----------|-------------|
| `LaunchBackground` | `Resources/Assets.xcassets/LaunchBackground.colorset/` | White (light) / black (dark) full-screen background |
| `LaunchLogo` | `Resources/Assets.xcassets/LaunchLogo.imageset/` | Centered green J-bolt with circle ring on transparent PNG (540×540 @3x) |

The launch screen follows system appearance: white backdrop in light mode, black in dark mode, with the same green mark centered on both.

## In-app accent

**Location:** `Resources/Assets.xcassets/AccentColor.colorset/`

SwiftUI `.tint` and `.accentColor` resolve to electric green (`#00E676`), matching the icon and launch logo.

## Regenerating the Xcode project

Asset catalog paths live under `Resources/`, which XcodeGen includes automatically. After editing assets or `Info.plist`:

```bash
xcodegen --spec project.yml
```

## Source session notes

Decisions from the initial icon design session:

- **Concept:** A + C (bolt badge + J monogram), not Pavlok-branded.
- **Colors:** Electric green symbol; white or black background by system theme.
- **Style:** Recommended treatment — circle badge around the bolt (matches onboarding SF Symbol), flat vector, high contrast, no text on icon.
