# Requirements Questionnaire

Ask in three rounds. Skip any question the repo already answers (say what you inferred). Mark the recommended option in the question. "Changes" tells you what the answer drives so you can explain why you asked.

Format to the user, per round:

> **Round 2 of 3: Technology.** Reply with letters, or say "defaults" to accept the ones marked ★.

---

## Round 1: Shape

| # | Question | Options | Changes |
|---|---|---|---|
| 1 | App name, and your organization's reverse-DNS prefix (a domain you own, e.g. `com.acme`)? I derive one application id for Android/iOS/macOS/Linux from it and show it for confirmation. | free text. No domain: `io.github.<username>` ★. Never `com.example` | Project name, ids on every platform, flavors suffixes, Firebase/OAuth/deep-link config (`project-identity.md`) |
| 2 | What does the app do, and who uses it? List the 3-5 core user flows. | free text | Feature list, build order, tier |
| 3 | Target platforms? | a) iOS+Android ★ b) +Web c) +Desktop d) single platform | Plugins allowed, responsive scope, secure-storage choice |
| 4 | Flutter/Dart version? | Detected: `flutter --version`. Confirm or pin. | Language features, package compatibility |
| 5 | Team size and expected app size? | a) solo / <10 screens b) 2-6 devs / 10-50 screens ★ c) multiple teams / 50+ | **Tier S / M / L** |

## Round 2: Technology

| # | Question | Options | Changes |
|---|---|---|---|
| 6 | State management? | a) Riverpod ★ b) Bloc/Cubit c) GetX d) other (name it) | State folder shape, DI, test style |
| 6b | Navigation? | a) GetX navigation: `AppRoutes` + `AppPages` + `GetPage` ★ b) go_router (typed routes) | Routes folder, deep-link handling, guards (`routing.md`). Keep `get` for navigation only unless GetX state was chosen |
| 7 | Backend? | a) REST ★ b) GraphQL c) Firebase d) Supabase e) none (local only) | Network layer, datasource types, auth |
| 8 | Authentication? | a) none b) email+password c) social (which?) d) phone/OTP e) SSO/OIDC f) biometric unlock (in addition) | Auth feature, route guards, token storage |
| 9 | Offline behavior? **Offline-first is the default** (the app works when the backend is down). | a) offline-first: cache-first reads, local-first writes, sync ★ b) read cache only c) online only (record why) | Local DB, sync/outbox, conflict policy, `resilience.md` |
| 10 | Local database? | a) drift (SQL) ★ b) isar/objectbox c) none (only if Q9 = c) | Persistence layer, migrations. *Required unless Q9 = c.* |

## Round 3: Product and operations

| # | Question | Options | Changes |
|---|---|---|---|
| 11 | **What languages should this app support?** Any right-to-left (Arabic, Hebrew, Urdu, Persian)? | list of locale codes; default locale | ARB files, RTL-safe layout rules, fonts |
| 12 | Theme? | a) light+dark+system ★ b) light only c) dark only d) brand-specific scheme (provide colors) | Theme files, token set, component tests |
| 13 | Push notifications? | a) none b) FCM c) APNs/other | Permissions flow, deep-link routing, service abstraction |
| 14 | Analytics? | a) none b) Firebase Analytics c) Mixpanel/Amplitude/PostHog d) other | `AnalyticsService` abstraction, event naming, consent |
| 15 | Crash reporting? | a) Crashlytics b) Sentry ★ (if not Firebase) c) none | Global error hooks, symbol upload in CI |
| 16 | Environments / flavors? | a) dev+staging+prod ★ b) dev+prod c) single | Entrypoints, env files, app ids per flavor |
| 17 | CI/CD? | a) GitHub Actions b) GitLab CI c) Codemagic/Bitrise d) Fastlane only e) none | Pipeline files, signing, store delivery |
| 18 | Design source? | a) Figma b) screenshots c) none (design for me) d) existing design system | Token extraction, design-analysis step |
| 19 | Accessibility target? | a) WCAG AA ★ b) AAA for key flows c) basic | Contrast checks, text scaling tests |
| 20 | Compliance/sensitivity? | a) none b) personal data (GDPR/CCPA) c) payments d) health/finance | Cert pinning, consent screens, logging redaction, storage rules |

## Follow-ups (ask only when the earlier answer triggers them)

| # | Asked when | Question | Options | Changes |
|---|---|---|---|---|
| 21 | Q7 is REST/GraphQL | Does the backend publish rate limits (requests per second/minute, `Retry-After`)? | a) yes (give numbers) b) no / unknown ★ | `RequestGate` constants |
| 22 | Q9 = a (offline-first) | For each synced entity: how fresh must data be, and who wins on conflict? One grouped question. | defaults ★ (`SyncPolicy.standard`: 5 min stale-after, 15 min foreground pull, server wins; presets in `resilience.md`) or per-entity values; conflict: server wins / client wins / last write wins / merge / ask user | `SyncPolicy` per entity, conflict policy in the ADR |
| 23 | Q9 = a (offline-first) | Should sync run in the background when the app is closed? | a) foreground only ★ b) background (WorkManager / BGTaskScheduler, timing not guaranteed) | Platform setup, battery impact |

## Conflict checks (run before writing the ADR)

- Q9 = offline-first and Q10 = none → ask which database (one is required).
- Q3 includes Web and Q8 uses biometric → biometrics unsupported on web; confirm fallback.
- Q7 = Firebase and Q8 = SSO/OIDC → confirm Firebase Auth supports the provider or use custom tokens.
- Q11 includes RTL and Q12 = brand-specific → confirm the brand font has Arabic/Hebrew glyphs.
- Q20 = payments/health/finance → recommend certificate pinning, FLAG_SECURE on sensitive screens, no analytics PII; ask for confirmation.

## Output

Write all answers (and which were `delegated`) to `docs/decisions/0001-project-foundations.md` from `templates/adr-template.md`.
