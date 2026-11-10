# Security

Read when: storing tokens or personal data, configuring environments or secrets, adding auth, configuring release builds, or handling deep links, WebViews or payments. Raise the baseline when discovery says payments, health, finance or personal data.

**Threat model in one sentence:** the app binary and the device are in the attacker's hands; the only secrets that stay secret are those that never ship in the app.

## Secrets management

- **Anything compiled into the app is extractable**: API keys in Dart constants, `--dart-define` values, `.env` assets, `google-services.json` fields. Treat these as *configuration*, not secrets.
- Real secrets (third-party server keys, signing keys, DB credentials, payment secret keys) live on your **backend**. The app calls your backend, which calls the third party. If a vendor requires a client key, restrict it (package name + SHA-256 for Android, bundle id for iOS, referrer/IP/API restrictions, quotas) and monitor usage.
- Environment config: `--dart-define-from-file=env/<flavor>.json`, files documented via `env/example.json` and gitignored if they contain anything sensitive. Read via `String.fromEnvironment` in `Env`. Don't ship `.env` as a Flutter asset (`flutter_dotenv` assets are readable from the bundle).
- Never commit: keystores, `key.properties`, provisioning profiles, `.p8`/`.p12`, service-account JSON, real env files. Add to `.gitignore`; scan with `gitleaks`/GitHub secret scanning in CI. If one leaks: rotate, don't just delete.
- CI stores signing assets and tokens in the CI secret store, injected at build time.
- Validate required config at startup and fail loudly (`core-config`/`constants`).

## Token and credential handling

| Item | Storage | Notes |
|---|---|---|
| Access/refresh tokens, API credentials | `flutter_secure_storage` (Keychain / Android Keystore-backed) | Never `shared_preferences`, files, logs, or analytics |
| Non-sensitive prefs (theme, flags) | key-value store | |
| Sensitive local DB | encrypted DB (SQLCipher-backed drift/sqflite variants) with the key in secure storage | When regulations or threat model require at-rest encryption |
| In-memory | Hold tokens in the auth repository only; clear on sign-out | Don't put tokens in widget state or routes |

- Short-lived access tokens + rotating refresh tokens; refresh single-flight (`networking.md`). On refresh failure: sign out and clear everything.
- **Sign-out wipes**: secure storage, DB, caches, image cache, push token registration, analytics identity.
- Use OAuth2/OIDC with PKCE and the system browser (`flutter_appauth`/ASWebAuthenticationSession/Custom Tabs), not embedded WebViews for login.
- Biometrics (`local_auth`) is a *local gate* that unlocks a stored credential or token; it is not authentication to the server by itself. Handle enrollment changes and fallback.
- iOS Keychain persists across reinstall; decide deliberately whether to clear on first launch.
- Android: set `android:allowBackup="false"` or exclude secure/sensitive data via backup rules (`dataExtractionRules`); `flutter_secure_storage` data must not be restored to another device.

## Transport security

- HTTPS only. Android: `cleartextTrafficPermitted=false` in `network_security_config.xml` (allow cleartext for dev hosts in debug flavor only). iOS: do not add ATS exceptions.
- **Certificate pinning** only where the risk justifies the operational cost (finance, health, high-value accounts): pin the SPKI hash of the public key, include at least one **backup pin**, plan rotation and an emergency escape (remote-config kill switch or short-lived pin sets with graceful fallback), and test expiry scenarios. A bad pin bricks the app for users. Implement via Dio's `IOHttpClientAdapter` with `badCertificateCallback`/`validateCertificate`, a native config (Android network security config pins, iOS `NSPinnedDomains`), or a vetted package. Never ship `badCertificateCallback => true`.
- Pinning does not stop a rooted-device attacker with instrumentation; it raises the bar against network attackers.

## Backend is the security boundary

Client checks are UX. Authorization, price calculation, validation, rate-limits and entitlement checks happen server-side. For Firebase: enforce Security Rules per collection with tests, enable **App Check** (Play Integrity / App Attest) to reduce abuse, never rely on hiding UI.

## Data protection

- Collect the minimum; classify data (public / internal / personal / sensitive) in the ADR.
- Never log or send to analytics/crash tools: tokens, passwords, full emails, phone numbers, card numbers, health data, precise location (`error-handling.md` redaction). Use hashed/opaque user ids.
- Respect consent: analytics/crash/ads initialize only after consent where law requires (GDPR/ePrivacy/CCPA); make opt-out effective.
- Sensitive screens: block screenshots/task-switcher previews (`FLAG_SECURE` on Android; blur overlay on iOS app-inactive), clear clipboard use, obscure fields (`obscureText`, disable autocorrect/suggestions with `enableSuggestions: false`, `autocorrect: false`).
- Support account/data deletion if the store policies require it (both stores do for apps with account creation).
- Pay with platform payment sheets/SDK tokenization; never touch raw card data yourself.

## Input, links and WebViews

- Validate and bound all external input: deep-link params, notification payloads, intents, clipboard, files, QR codes. Parse to typed values; reject the rest.
- Prefer verified App Links / Universal Links; never act on a deep link that triggers destructive or privileged actions without re-auth/confirmation.
- WebViews: disable JavaScript unless needed, allow-list origins, no `addJavaScriptChannel` exposing sensitive handlers to untrusted content, disable file access, don't load arbitrary URLs.
- File handling: sanitize names/paths (no path traversal), cap sizes, scan types by content not extension.
- Use `Uri` parsing, not string concatenation, for URLs.

## Build and release hardening

- Release builds: `--obfuscate --split-debug-info=<dir>` (store symbols securely and upload to the crash tool). Obfuscation slows reverse-engineering; it does not protect secrets.
- Android: enable R8/ProGuard shrink, `minifyEnabled`, sign with a Play-managed or protected upload key; iOS: automatic signing via CI-managed certs.
- Strip debug features by flavor: no logging of bodies, no dev menus, no test endpoints in production.
- Optional root/jailbreak/emulator/debugger detection (Play Integrity API, App Attest, DeviceCheck) as a **risk signal sent to the backend**, not a hard client-side gate (trivially bypassed).
- Keep dependencies updated; run `flutter pub outdated` and a vulnerability scan (OSV/Dependabot) in CI; review new packages' maintainers and permissions; avoid abandoned plugins handling auth/crypto.
- Minimal platform permissions; request just-in-time with rationale; handle denial gracefully.
- Crypto: use platform primitives or well-reviewed packages (`cryptography`, `pointycastle`); never invent algorithms, never hardcode keys/IVs, use AEAD (AES-GCM/ChaCha20-Poly1305), random IVs.

## Security review checklist (run for sensitive features)

- [ ] No secret in source, assets, `--dart-define`, or logs
- [ ] Tokens only in secure storage; wiped on sign-out
- [ ] HTTPS enforced; pinning decision recorded (yes/no, why)
- [ ] Server-side authorization for every action
- [ ] External input validated; deep links safe
- [ ] No PII in analytics/crash/logs; consent honored
- [ ] Sensitive screens protected; backups configured
- [ ] Release build obfuscated; symbols stored; debug features off
- [ ] Dependencies scanned and minimal
