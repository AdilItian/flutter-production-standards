# Project Identity: Application IDs and Names

Read when: creating a new app (always, during foundation), or when the baseline scan reports identifier findings on an existing app.

The application ID is the app's permanent identity in the stores, in push and sign-in services, and in deep links. Get it right before the first build; after publishing it effectively cannot change.

## Rules per platform

| Platform | Where it lives | Valid format | Notes |
|---|---|---|---|
| **Android** `applicationId` | `android/app/build.gradle(.kts)` | Dot-separated segments, **at least two**, each starts with a letter, only letters, digits, underscores. No reserved Java keywords as a segment. | **Permanent after the first Play Store upload.** Separate from `namespace` (the code package), which can differ. |
| **iOS** bundle identifier | `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`, one per build configuration; extensions get their own) | Letters, digits, **hyphens**, dots; at least two segments. **No underscores.** Case-insensitive. | Tied to provisioning profiles, push, Sign in with Apple, associated domains, keychain groups. |
| **macOS** | `macos/Runner/Configs/AppInfo.xcconfig` | Same as iOS | |
| **Linux** | `linux/CMakeLists.txt` (`APPLICATION_ID`) | Reverse-DNS, at least two segments (GApplication rules) | |
| **Windows** | No store-style id in a default project | Microsoft Store builds use MSIX package identity and publisher | Not auto-validated. Ask if the user publishes there. |
| **Web** | None | Manifest `name`, `short_name`, `start_url` | Not an identifier; check them for correctness. |
| **Dart package** `name:` | `pubspec.yaml` | `lowercase_with_underscores`, not a reserved word | Internal; not the store id. |

### The portable subset (recommended default)

Android allows underscores and iOS allows hyphens, but neither accepts the other's extras. Use the **portable subset**: lowercase letters and digits only, dot-separated, every segment starting with a letter.

```
^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$        e.g.  com.acme.shopapp
```
Then the **same string** works on Android, iOS, macOS and Linux, and Firebase/OAuth/deep-link configuration can be copy-pasted across platforms.

## How to choose (new apps)

1. **Ask for the organization domain** in discovery Round 1: "What reverse-DNS prefix should the app ids use? Use a domain you own, e.g. `com.acme`."
2. **Derive the default** with `scripts/check_ids.sh --suggest <org> "<App Name>"` (e.g. `com.acme` + "Shop App" → `com.acme.shopapp`). Show it for confirmation, once, for all platforms together.
3. **No domain?**
   - Individual developer on GitHub: `io.github.<username>.<appname>` is a common convention (confirm the username is theirs).
   - Never use `com.example.*`, `com.company.*`, `org.example.*`, or `com.flutter.*`. These are template values; the stores and services may reject them, and they collide with other people's apps.
4. **Set it for every platform in the project** (via `flutter create --org <org> --project-name <pkg> .` for a new project, or edit the platform files), then run `scripts/check_ids.sh`.
5. Record the ids in ADR-0001.

## Flavors and environments

| Flavor | Android `applicationIdSuffix` | iOS bundle id | Display name |
|---|---|---|---|
| production | none | `com.acme.shopapp` | `Shop App` |
| staging | `.staging` | `com.acme.shopapp.staging` | `Shop App (Stg)` |
| development | `.dev` | `com.acme.shopapp.dev` | `Shop App (Dev)` |

Different ids let all flavors be installed side by side and keep push tokens, deep links and OAuth redirects separate. Each flavor needs its own Firebase app (or an equivalent per-environment registration) with a matching package name / bundle id.

## What must match the id

- `google-services.json` `package_name` and `GoogleService-Info.plist` `BUNDLE_ID` (the scan checks these).
- OAuth redirect URIs / custom URL schemes, Sign in with Apple and Google sign-in client ids.
- Universal Links (`apple-app-site-association` app ids, `assetlinks.json` package and certificate hash).
- Push (APNs key team and bundle id, FCM sender).
- Keychain access groups, app groups, extension ids (must be prefixed by the main bundle id).
- Store listings and signing configuration.

## Display names

User-visible app name is localized (`CFBundleDisplayName` in `InfoPlist.strings`, Android `app_name` in `values-xx/strings.xml`) and kept short (≈ 12 characters shows untruncated on most home screens). It is not the id.

## Existing apps: how to handle findings

- **Never change an id of an app that is published or distributed** (Play Store, App Store, TestFlight, enterprise). Report it as a finding with the consequence, and let the user decide. A changed id is a new app: users, reviews, push tokens and sign-in links do not carry over.
- If the app is **not yet published**, a placeholder id (`com.example.*`) is a **Blocker** to fix before the first store upload: propose the new id, list the files to change (build.gradle, pbxproj, xcconfig, CMake, Firebase files, URL schemes, associated domains, Kotlin/Java package directory if the namespace changes), get approval, then change everything together and re-run the check.
- Mismatched ids across platforms are a **Major** finding when they are accidental, and a note when intentional (document why).
- Find out whether the app is published by asking. Never infer it.

## Checks (what `scripts/check_ids.sh` does)

Valid format per platform; placeholder detection; Java keywords in the Android id; Android vs iOS/macOS consistency (case-insensitive); Dart package name; Firebase config match. It does not call any store or service and cannot know whether an id is already taken. Mention that limit in the report.
