# Resilience: Offline-First by Default, Backend Up or Down

Read when: designing any feature that touches server data, the app startup, auth, sync, or when the backend is slow, failing or unreachable. Also read `networking.md` (mechanics: client, gate, outbox, sync engine) and `ui-guidelines.md` (the default views).

**The promise:** the app opens, shows useful content, accepts the user's work and never crashes or hangs, whether the backend is up, slow, flapping or completely down. Online is an optimization, not a requirement.

## Offline-first is the default

Unless the user opts out for a specific feature (recorded in the ADR), every feature that shows server data follows this:

| Concern | Default behavior |
|---|---|
| **Reads** | Cache-first. The UI observes the local DB (`Stream`). The network refreshes the DB in the background. Show the cached content immediately; update when fresh data arrives. |
| **Writes** (user-created or user-edited data) | Local first. Write to the local DB and the outbox in one transaction, show the change at once, mark it pending, sync later. |
| **Local database** | Required by default (drift unless the project chose another). `shared_preferences` is not a database. |
| **Freshness** | Each entity has a `SyncPolicy` with sensible defaults (below). |
| **Status** | Pending, failed and last-synced states are visible (`SyncStatusChip`, `ConnectivityChip`). |

**Online-only exceptions** (decide per feature, record in the ADR): first-time sign-in and sign-up, payments, anything whose result only the server can know (availability, live prices), search over data that was never cached, destructive operations the user must see confirmed. These show a clear "needs connection" state with retry; they never freeze or crash.

This replaces "offline support is optional". If the user truly wants an online-only app, record that decision; the resilience rules below (never crash, never hang, honest states) still apply.

## Default sync times

Starting points, not measured values. Present them in discovery, let the user override per entity, record the result. Presets live in code so a developer picks a class of data instead of inventing numbers:

| Preset | For | `staleAfter` (pull on read) | `pullInterval` (foreground) | `pullOnResume` | Notes |
|---|---|---|---|---|---|
| `SyncPolicy.live` | Feeds, inboxes, order status | 1 min | 5 min | yes | Use realtime (websocket/FCM) instead of polling if available |
| `SyncPolicy.standard` | Most user data and content lists | 5 min | 15 min | yes | **Default** when nothing is specified |
| `SyncPolicy.profile` | Profile, settings, preferences | 1 h | 1 h | yes | Writes push quickly (`pushDebounce` 0-2 s) |
| `SyncPolicy.reference` | Categories, catalogs, taxonomies | 24 h | 6 h | no | Wi-Fi only for large payloads |
| `SyncPolicy.staticContent` | Legal text, rarely changing config | 7 d | none | no | Refresh on app update or manual refresh |

Shared defaults for all presets: `pushDebounce` 2 s, `maxRetries` 5, exponential backoff with jitter (starting at 2 s, capped at about 5 min), conflict policy per entity (`serverWins` unless decided otherwise). Periodic pulls run in the foreground only; background sync is opt-in (WorkManager / BGTaskScheduler, timing not guaranteed). Pull-to-refresh and `syncNow(entity)` always bypass the interval. Conflict policies, the outbox and the engine are in `networking.md`.

```dart
// data/sync/sync_policies.dart
const syncPolicies = <String, SyncPolicy>{
  'titles': SyncPolicy.standard,
  'favorites': SyncPolicy.standard.copyWith(conflict: ConflictPolicy.merge),
  'profile': SyncPolicy.profile,
  'genres': SyncPolicy.reference,
};
```

## When the backend is down: required behavior

| Area | Required behavior |
|---|---|
| **Startup** | Never blocks on the network. The splash waits only for local init (secure storage, DB, env). Open on cached or last-known state. Remote config and feature flags: bundled defaults plus last cached values, fetched in the background with a short timeout. |
| **Session** | A token is valid or expired by its local expiry, not by calling the server. Network or 5xx failure during refresh is not a sign-out: keep the session, mark it "needs revalidation", retry later. Only an explicit rejection (`401`/`invalid_grant` on refresh) signs the user out. |
| **Reads** | Show cached data with the connectivity chip. If there is no cache (first run): `NoInternetView` or `ServerUnavailableView` with retry. Never a blank screen or an endless loader. |
| **Writes** | Accepted locally, queued, shown as pending. Toast: "Saved. Will sync when you're online." |
| **Navigation** | Every screen opens. Screens that need the server show an inline unavailable state with retry, not an exception. |
| **Timeouts** | Every request has connect, send and receive timeouts (`ApiConstants`). No infinite spinner: at about 8 s show "Still working…", at the timeout show the error state. |
| **Failure containment** | The circuit breaker (`RequestGate`) fails fast after repeated failures, so a dead backend doesn't make every screen wait for timeouts. |
| **Bad responses** | HTML error pages from proxies or CDNs, empty bodies and malformed JSON become `ServerFailure` / `ParsingFailure`, never an uncaught exception. Check the content type before parsing. |
| **Recovery** | When the backend returns: flush the outbox, refresh visible screens once, clear the chip. No toast storm, no duplicated sends (idempotency keys). |
| **UI** | Offline and service problems are shown with a small chip and one calm notice, never a blocking or layout-shifting UI (`ui-guidelines.md`, "Offline UI never blocks the app"). |
| **Honesty** | The UI never claims data is fresh or an action is confirmed when it is not. Show "last updated" and pending states. |

### BackendStatus

A small service in `core/services` that tells the UI what is wrong, so every screen reacts the same way:

```dart
enum BackendStatus { online, degraded, unreachable, offline }  // offline = no network at all

abstract interface class BackendStatusService {
  Stream<BackendStatus> get changes;
  BackendStatus get current;
}
```
Derived from `ConnectivityService` (device network) plus request outcomes (success, timeouts, 5xx, breaker state). While not `online`, a lightweight probe (cheapest endpoint, exponential backoff from 5 s up to 2 min) checks for recovery; it must not hammer a struggling server. The design system listens to it for `ConnectivityChip`; sync listens to it to pause and resume.

Failure mapping to views (`ErrorView` dispatches automatically):

| Failure | Shown when there is **no** usable cache | Shown when cache exists |
|---|---|---|
| `OfflineFailure` | `NoInternetView` with retry | Cached content + chip |
| `ServerFailure`, `TimeoutFailure`, breaker open | `ServerUnavailableView` ("We can't reach our servers") with retry | Cached content + chip |
| `UnauthorizedFailure` after refresh failed explicitly | Sign-in required view | Same |
| Others | `ErrorView` with retry if retryable | Toast, content stays |

## What must never depend on the backend being up

App launch, navigation between screens, reading previously loaded data, creating or editing user data, theme and language settings, onboarding, showing the sign-in screen, rendering any error or empty state, crash reporting init (queue and send later).

## Testing (required for offline-first projects)

A `FakeBackend` (or the mock server's chaos switches) supports these modes, and tests/integration tests assert behavior in each:

| Mode | Assert |
|---|---|
| Down (connection refused / DNS failure) | App launches; cached content visible; writes queue; chip and a one-time notice appear; no crash |
| Offline (device network off) | Same, plus `NoInternetView` on first-run screens |
| Slow (responses at 2× timeout) | Spinner then timeout state; no hang; UI stays responsive |
| 5xx / 503 with Retry-After | Breaker opens; cooldown respected; cached content stays |
| Flapping (alternates up/down) | No duplicate sends (idempotency), no toast storm, sync converges |
| Malformed 200 / HTML error page | `ParsingFailure`/`ServerFailure`, no crash |
| Expired token + backend down | User stays signed in; revalidates after recovery |
| Recovery | Outbox flushes in order; visible screens refresh once; chip clears |

Cold start with an empty cache and the backend down is a required test: it must show the right full-screen state with working retry.

## Checklist

- [ ] Every server-data feature is cache-first, with a `SyncPolicy` preset chosen
- [ ] Writes use the local DB plus outbox (or are listed as online-only exceptions in the ADR)
- [ ] Startup makes no blocking network call
- [ ] A network failure never signs the user out
- [ ] Chip, pending and failed states exist; no infinite loaders; timeouts set
- [ ] Backend-down tests pass, including cold start with an empty cache
