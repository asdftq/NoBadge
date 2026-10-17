# NoBadge

Hide supported Dock badges while macOS Focus is on. Bring your previous badge settings back when it ends.

**[Get the signed Mac app — $2.99 once](https://www.asdftq.com/nobadge/?utm_source=github&utm_medium=readme&utm_campaign=nobadge_source)** · [Setup and compatibility](https://www.asdftq.com/nobadge/support.html)

The website version is a ready-to-install, signed and notarized download with in-app updates. One purchase covers up to 3 Macs. If you prefer to build it yourself, the source is MIT licensed and the source build needs no purchase key.

[![Illustrative Dock comparison with example badge counts](https://www.asdftq.com/nobadge/assets/dock-social.png)](https://www.asdftq.com/nobadge/)

## What it does

- Follow any Focus, or only the modes you choose.
- Hide supported badges in the Dock and app switcher.
- Hide the separate System Settings Dock badge on macOS 27, with the same exceptions and restoration.
- Keep badges visible for individual apps.
- Show badges for 15 minutes without switching Focus off.
- Restore the badge settings NoBadge changed when Focus ends.

## Before you run it

**Compatibility:** Apple Silicon on macOS **26.5.1 or later in macOS 26, and macOS 27**. NoBadge selects the adapter for your OS family and checks the settings format before changing badges. Stable minor and patch updates within these families do not need a new build-number approval. macOS 28 and later, beta builds, Intel Macs and older macOS versions need a compatible release.

Directly verified builds: macOS 26.5.1 (25F80), 26.6 (25G72) and 27.0.1 (26A434). A supported family is not a claim that every build has been tested. If Apple changes the settings format, NoBadge pauses changes and keeps recovery information.

NoBadge requires **Full Disk Access** because it reads private macOS Focus settings and changes notification preferences. This is a broad permission. The app does not read messages or documents, and badge/Focus processing stays on your Mac. Some apps draw their own badges and may not respond.

Quit any running NoBadge copy before using another build. Use **Restore & Quit** before removing or replacing it. If it is force-quit, reopen it to restore pending settings.

## Badge support

| Badge path | macOS 26.5.1+ within 26 | macOS 27 |
| --- | --- | --- |
| Registered notification badges | Supported | Supported |
| System Settings Dock attention badge | Not supported | Supported since 0.1.40 |
| Other custom app-drawn badges | Not guaranteed | Not guaranteed |

System Settings uses a separate, journaled adapter. It follows Focus, Show badges, app exceptions and safe exit/update restoration. It preserves current external attention entries; it does not resolve the underlying system requests or hide notices inside System Settings. Supported adapters are declared per OS family. Unknown settings formats pause changes rather than reporting a successful hide.

## Build from source

You need a Mac with a current Xcode installation and Python 3.

```sh
git clone https://github.com/asdftq/NoBadge.git
cd NoBadge
./scripts/build-source.sh
```

The app is written to:

```text
build/SourceData/Build/Products/Release/NoBadge.app
```

The script generates the Xcode project with `NOBADGE_SOURCE_BUILD` and signs locally with an ad hoc signature. It does not need our signing certificate, notarization credentials, or a purchase key. After building, you can also open `NoBadge.xcodeproj` in Xcode.

Source builds do not read purchase credentials or check the commercial update feed. To update, pull the latest source and build again. For the signed, notarized download and in-app updates, use **[the website](https://www.asdftq.com/nobadge/)**.

## Development

The app uses SwiftUI/AppKit. Badge transactions, restoration journals, Focus decoding and compatibility policy live in the local `NoBadgeCore` Swift package.

```sh
swift test --package-path Packages/NoBadgeCore
```

Tests use temporary fixtures. Do not experiment with writes to your real notification database or publish Focus files, recovery journals, license keys, or private diagnostics in issues.

## License and credits

[MIT](LICENSE)

Inspired by [FocusNoBadges](https://github.com/FuzzDOT/FocusNoBadges) and [FocusPlsNoBadges](https://github.com/aydenp/FocusPlsNoBadges). No upstream source or artwork was imported. Sparkle retains its own license; see [third-party notices](Docs/third-party-notices.md).
