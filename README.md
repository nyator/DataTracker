# DataTracker

An iPhone app that alerts you when today's mobile data usage nears or passes a daily budget. It
reads the system's cellular byte counters directly. There is no VPN or Network Extension.

- **Today**: a progress ring of today's usage against the budget, which turns orange at the first
  alert and red at the second.
- **Bundle**: total used of the bundle, data left, days left, and a recommended daily amount from
  tomorrow on.
- **History**: a 14-day bar chart (Swift Charts). Days over budget are red.
- **Alerts**: local notifications at 80% and 100% of the day's budget (both configurable), each at
  most once per day.
- **Widget**: home screen (small and medium) and lock screen (circular and rectangular).
- **Budget**: by default, data left at the start of the day ÷ days left. With 217 GB over 90 days
  that starts at about 2.41 GB/day, then rises if you under-use and falls if you over-use. A fixed
  daily budget is also available.

## How usage is measured

`getifaddrs()` returns an `if_data` record for every network interface. The cellular interfaces
are named `pdp_ip0`, `pdp_ip1` and so on. Their `ifi_ibytes` (received) and `ifi_obytes` (sent)
fields are byte counters, but they make poor totals:

| Problem | How it's handled ([`Shared/CounterMath.swift`](Shared/CounterMath.swift)) |
|---|---|
| Counters are 32-bit and **wrap to 0 after 4 GiB** (about every 2 days at your budget) | Every reading is compared with the previous one. A drop from the upper half of the range (≥ 2 GiB) is a wrap, so the delta is `(2³² − previous) + current`. |
| Counters **reset to 0 on reboot** | Boot time (`kern.boottime`) and monotonic uptime are stored with each reading. If either shows a reboot, the delta is the current value (everything since boot). |
| Summing rx+tx first would hide a wrap | Each interface/direction counter is tracked separately. |
| Readings straddle midnight | The delta is split across days in proportion to time ([`DayMath.split`](Shared/DayMath.swift)). |

Only these deltas are added to the stored totals, which live in App Group `UserDefaults`
(`group.com.builtelo.DataTracker`). The raw counters are never used as a total. Each new day gets a
new entry in the per-day log, which is how midnight rollover works, and 120 days are kept.

Readings are taken on app launch, on every return to the foreground, once a minute while the app
is open, by background refresh (`BGAppRefreshTask`, roughly every 1–3 hours, as iOS allows), and
whenever the widget reloads. The app and widget share a file lock, so they never double-count.

**Known limits** (inherent to the counters, so they can't be coded away):

- If one counter moves 4 GiB or more between two readings, a whole wrap is invisible and lost.
  Opening the app now and then, and keeping the widget on the home screen, keeps gaps short.
- Usage between the last reading and a reboot is lost.
- On first launch the counters already hold data from before the app was installed. That isn't
  counted. Enter your real usage under **Settings → Correction** (check it with MTN, e.g. `*138#`).
- iOS decides when background refresh runs. If you force-quit the app from the app switcher, iOS
  stops running its background refreshes until you open it again.
- Counters include all cellular traffic, including tethering (Personal Hotspot). MTN's count can
  differ slightly. Use the correction field to re-sync from time to time.

## Project layout

```
project.yml                     XcodeGen spec (the .xcodeproj is generated, not committed)
Shared/                         Compiled into the app, widget and tests
  AppGroup.swift                  App Group / task / widget identifiers
  CellularCounters.swift          getifaddrs() + boot time readers
  CounterMath.swift               Wrap-around and reboot handling
  DayMath.swift                   Day keys, splitting usage across midnight
  Budget.swift                    Budget, days left, thresholds, formatting
  Models.swift                    BudgetSettings, TrackerState, UsageSnapshot
  TrackerEngine.swift             Pure state transitions (ingest, alerts, snapshot)
  UsageStore.swift                App Group persistence + cross-process lock
  UsageTracker.swift              Facade used by the app, background task and widget
  UsageRing.swift                 Progress ring view (app + widget)
DataTracker/                    App target
  DataTrackerApp.swift            App entry, AppDelegate (registers the BG task)
  BackgroundRefresh.swift         BGTaskScheduler registration, scheduling, handler
  Notifier.swift                  Local notifications
  DashboardModel.swift            View model
  Views/                          ContentView, DashboardView, HistoryChart, SettingsView
  Info.plist, DataTracker.entitlements, PrivacyInfo.xcprivacy, Assets.xcassets
DataTrackerWidget/              Widget extension
  DataTrackerWidget.swift         Timeline provider + views
  Info.plist, DataTrackerWidget.entitlements, PrivacyInfo.xcprivacy
DataTrackerTests/               Unit tests for wrap, reboot, rollover, budget and alerts
fastlane/                       Appfile, Fastfile (test + beta lanes)
.github/workflows/testflight.yml
```

### Capabilities and Info.plist

These are already set in the files above. Listed here for reference:

| What | Where |
|---|---|
| App Groups: `group.com.builtelo.DataTracker` | Both `.entitlements` files (also enable it on both App IDs in the developer portal; see step 1) |
| Background App Refresh: `UIBackgroundModes` = `fetch` | `DataTracker/Info.plist` |
| `BGTaskSchedulerPermittedIdentifiers` = `com.builtelo.DataTracker.refresh` | `DataTracker/Info.plist` |
| `ITSAppUsesNonExemptEncryption` = NO (skips the export-compliance question) | `DataTracker/Info.plist` |
| Widget extension point `com.apple.widgetkit-extension` | `DataTrackerWidget/Info.plist` |
| Privacy manifest: boot time (35F9.1), UserDefaults (CA92.1, 1C8F.1) | `PrivacyInfo.xcprivacy` in both targets |

Notifications need no capability. The app asks for permission on first launch.

## Setup

Your Mac (2017, Xcode 16) can build and test this project in the Simulator but can't install on
iOS 27, so builds for your phone go through GitHub Actions to TestFlight. The CI runner uses the
newest Xcode. The project file is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
on each machine, so nothing in the repo depends on a newer Xcode.

### 1. Apple Developer portal (one time)

At [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, IDs & Profiles** → **Identifiers**:

1. **+** → **App Groups** → Description `DataTracker`, Identifier `group.com.builtelo.DataTracker` → Register.
2. **+** → **App IDs** → **App** → Description `DataTracker`, Bundle ID (Explicit) `com.builtelo.DataTracker`.
   Under Capabilities, tick **App Groups** → Continue → Register. Then open the App ID, click
   **Configure** next to App Groups, select `group.com.builtelo.DataTracker`, and Save.
3. Repeat step 2 for the widget: Description `DataTracker Widget`, Bundle ID `com.builtelo.DataTracker.Widget`,
   App Groups → the same group.

Background App Refresh is not a portal capability. It's the `UIBackgroundModes` Info.plist entry.

### 2. App Store Connect app record (one time)

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**:
platform iOS, any unique name (e.g. "DataTracker Daily"; the home screen still shows
"DataTracker"), primary language, Bundle ID `com.builtelo.DataTracker`, SKU `datatracker`, User
Access: Full Access.

### 3. App Store Connect API key → 3 secrets

App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**.
Name it `GitHub CI` and give it the **App Manager** role. If profile creation later fails with a
permission error, use **Admin**. Then:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | The **Key ID** column, e.g. `ABC123DEF4` |
| `ASC_ISSUER_ID` | The **Issuer ID** shown above the key list (a UUID) |
| `ASC_KEY_P8_BASE64` | Download the `.p8` (**you can only download it once**), then `base64 -i AuthKey_ABC123DEF4.p8 \| pbcopy` and paste |

### 4. Apple Distribution certificate → 2 secrets

You can do this on your Mac in Terminal. It doesn't need Xcode:

```sh
mkdir ~/datatracker-signing && cd ~/datatracker-signing

# 1. Private key + certificate signing request
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr -subj "/emailAddress=you@example.com/CN=Your Name/C=GH"
#   (Apple replaces these fields with your team details; any values work.)
```

2. Developer portal → **Certificates** → **+** → **Apple Distribution** → upload `dist.csr` →
   download `distribution.cer` into the same folder.

```sh
# 3. Bundle key + certificate into a password-protected .p12
openssl x509 -inform DER -in distribution.cer -out dist.pem
openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12 -passout pass:CHOOSE_A_PASSWORD
#   If `openssl version` says "OpenSSL 3.x" (Homebrew), add -legacy after -export,
#   or macOS's keychain on the runner can't import it. The built-in LibreSSL needs nothing extra.

# 4. Copy for the secret
base64 -i dist.p12 | pbcopy
```

| Secret | Value |
|---|---|
| `DIST_CERT_P12_BASE64` | The base64 text you just copied |
| `DIST_CERT_PASSWORD` | `CHOOSE_A_PASSWORD` from step 3 |

Keep `dist.key` and `dist.p12` somewhere safe (a password manager), not in the repo. The
`.gitignore` blocks `*.p12`, `*.p8` and `*.cer` anyway. Your Team ID (`2TB72JR5D3`) is set in
`project.yml` and `fastlane/Appfile`. It isn't a secret.

### 5. Add the secrets to GitHub

Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**, once per
row above (5 secrets). With the GitHub CLI:

```sh
gh secret set ASC_KEY_ID --body "ABC123DEF4"
gh secret set ASC_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set ASC_KEY_P8_BASE64 < <(base64 -i AuthKey_ABC123DEF4.p8)
gh secret set DIST_CERT_P12_BASE64 < <(base64 -i dist.p12)
gh secret set DIST_CERT_PASSWORD --body "CHOOSE_A_PASSWORD"
```

### 6. Build

Push to `main`, or run **Actions → TestFlight → Run workflow**. The workflow:

1. Selects the newest stable Xcode on `macos-latest`.
2. Generates the project with XcodeGen.
3. Runs the unit tests (`fastlane test`).
4. Runs `fastlane beta`: imports the certificate into a temporary keychain, creates or downloads
   App Store profiles for the app and widget with the API key, sets the build number to the latest
   TestFlight build + 1, archives, and uploads.

Pull requests run the tests only. After an upload, Apple processes the build for 5–30 minutes.

### 7. Install on your iPhone

App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** to create a group →
add yourself. Install **TestFlight** from the App Store on your iPhone, sign in with the same
Apple ID, and install DataTracker. Each new build shows up there.

Then on the phone:

- Allow notifications when asked.
- Check **Settings → General → Background App Refresh** is on, both globally and for DataTracker.
- In DataTracker's **Settings**, set the bundle start date and enter **Used so far**.
- Long-press the home screen → **+** → DataTracker to add the widget.

## Local development (Xcode 16)

```sh
brew install xcodegen
xcodegen generate          # after cloning, and whenever you add/remove files
open DataTracker.xcodeproj
```

You can build, run in the iOS 18 Simulator, use SwiftUI previews, and run the tests (⌘U). The
Simulator has no `pdp_ip` interfaces, so the dashboard shows a "no cellular interface" notice and
zero usage. To see it with realistic numbers, add the launch argument `-demoData` (Product →
Scheme → Edit Scheme → Run → Arguments). This replaces the stored data with 13 days of history and
1.95 GB used today, and simulates 25 MB per reading, so the 80% alert fires right after launch.
Demo mode is compiled into Debug builds only, never TestFlight builds.

From the command line:

```sh
xcodebuild test -project DataTracker.xcodeproj -scheme DataTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

The project deliberately uses only APIs available on iOS 17 and Swift 5 language mode, so the same
code compiles with Xcode 16 locally and the newest Xcode in CI.

## Testing background refresh

**On your setup (TestFlight build):** open DataTracker → **Settings** → **Permissions** →
**Last background run** shows when iOS last ran the task and how many times it has run. Use the
phone normally for a day. Runs usually appear within a few hours, more often if you open the app
regularly, and rarely in Low Power Mode or overnight.

**With a debugger.** This needs an Xcode that supports the phone's iOS version, so a newer Mac.
BGTaskScheduler doesn't run in the Simulator.

1. Run the app on the device from Xcode.
2. Send it to the background (go to the home screen) so `schedule()` submits a request.
3. In Xcode press **Pause** (Debug → Pause), then at the `(lldb)` prompt:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.builtelo.DataTracker.refresh"]
   ```
4. Press **Continue**. The handler in `BackgroundRefresh.handle` runs immediately. Set a breakpoint
   there to step through it.
5. To test the expiration path, pause again during the task and run:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.builtelo.DataTracker.refresh"]
   ```

To check the alerts quickly, set a fixed daily budget of a few MB in Settings, use some data, and
reopen the app.

## Troubleshooting CI

- **"No profiles for 'com.builtelo.DataTracker.Widget'" / App Group errors**: the widget App ID
  isn't registered, or App Groups isn't enabled and configured on both App IDs (step 1).
- **Certificate import fails ("MAC verification failed")**: the `.p12` was made with OpenSSL 3
  without `-legacy`, or the password secret doesn't match.
- **"Could not find a valid code signing identity"**: the `.p12` doesn't hold the private key.
  Re-export it from `dist.key` + `dist.pem`.
- **403 / insufficient permissions when creating profiles**: give the API key the Admin role.
- **"No suitable application records were found"**: create the app in App Store Connect (step 2).
- Build logs are attached to each workflow run as the `logs` artifact.
