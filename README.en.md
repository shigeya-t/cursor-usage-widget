# Cursor Usage Widget

[日本語](README.md)

A macOS menu bar app and WidgetKit widget that shows your AI plan and usage at a glance—so you do not have to keep opening the Cursor settings page.

The architecture matches [Subway Widget](https://github.com/shigeya-t/subway-widget):
**the host app fetches data; the widget extension only displays snapshots.**

<p align="center">
  <img src="docs/screenshots/widget-en.png" alt="Widget (English)" width="220" />
  &nbsp;
  <img src="docs/screenshots/menu-en.png" alt="Menu bar (English)" width="280" />
</p>

## Why this exists

Cursor’s dashboard has Plan & Usage, but there does not seem to be a clear
notification when remaining credits run low. It was easy to burn through the
included pool and drift deep into on-demand spend before noticing.

This app keeps plan quotas and on-demand balance visible in the menu bar and on
the desktop, without opening settings every time.

## Features

- Plan & Usage–style view (plan name, reset date, Cursor Models / Other Models, On-Demand)
- Menu bar stay-resident app (no Dock icon) plus small / medium / large widgets
- Explicit Japanese / English switch shared by the app and widgets
- Pause and refresh controls in both the app and the widget
- Save, replace, and delete a session cookie
- Provider-agnostic `UsageSnapshot` model (v1 ships Cursor only)

## Requirements

- macOS 14 or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Cursor.app login, or a `WorkosCursorSessionToken` cookie from the browser

## Build and install

```sh
brew install xcodegen
cp Config/Team.xcconfig.example Config/Team.xcconfig
./scripts/sync-team.sh
xcodegen generate
./scripts/test.sh
swift scripts/generate-app-icon.swift
./scripts/deploy-local.sh                 # installs to ~/Applications and build/
```

`deploy-local.sh` signs with your Development Team before installing.
Ad-hoc signing breaks App Intents and leaves widgets stuck on placeholders.
If you have multiple certificates, run
`DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/deploy-local.sh`.

After install, add **Cursor Usage** from Edit Widgets
(Japanese system language: **Cursor使用量**).
For everyday use, add it under System Settings → General → Login Items.

## Authentication (Cursor)

Personal Plan & Usage is not available through the official Admin API.
This app calls the same unofficial endpoint the dashboard uses:
`GET https://cursor.com/api/usage-summary`.

Session resolution order:

1. Manually saved `WorkosCursorSessionToken` in Keychain
2. Cursor.app `state.vscdb` (`cursorAuth/accessToken`)

To paste a cookie manually:

1. Open https://cursor.com/dashboard?tab=usage
2. DevTools → Application → Cookies → copy the **Value** of `WorkosCursorSessionToken`
3. Paste only the value into the menu bar field (the cookie name is shown as a fixed label)

Session cookies / JWTs are never logged. Only usage snapshots are shared with the widget.

## How refresh works

Widgets stay reasonably fresh only while the menu bar app is running.

- Fetching is centralized in the host app (the widget extension does not network)
- Default interval is 5 minutes; snapshots go through an App Group
- Pause stops automatic fetches; Refresh Now still works while paused

## Adding another AI provider

Implement `UsageProvider` and register it in `UsageProviderRegistry.all`.
The UI only renders `UsageSnapshot` (plan, percent meters, spend).

## Layout

```
project.yml                  XcodeGen project definition
Shared/                      models, Cursor fetch, L10n, App Intents
App/                         menu bar host app
WidgetExtension/             widget UI (no networking)
Tests/                       unit tests and JSON fixtures
docs/screenshots/            screenshots for the README
scripts/                     sync-team / test / deploy-local / icon generator
```

`Info.plist` and `*.entitlements` are generated from `project.yml` and are not committed.

Bundle ID is `jp.shigeya.AIUsageWidget`. When forking, also update:

- `bundleIdPrefix` / `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`
- `Notification.Name` and `groupSuffix` in `Shared/AppSettings.swift`
- Keychain service name in `Shared/CursorSession.swift`
- `BUNDLE_ID` in `scripts/_common.sh`

App Group: `$(DEVELOPMENT_TEAM).jp.shigeya.AIUsageWidget`.

## Notes

- `usage-summary` is unofficial and may change without notice
- Intended for personal, private use
- Do not contact Cursor support about issues with this app

## License

[MIT License](LICENSE)
