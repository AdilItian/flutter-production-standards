# Networking, Caching and Offline

Read when: adding any API call, Firebase/Supabase access, caching, offline behavior, pagination, uploads, or interceptors.

## The chain (strict)

```
UI (screen/widget)
   ↓ events
State holder (controller / notifier / bloc)
   ↓ calls
Repository (interface: domain · implementation: data)   → returns Result<Entity>
   ↓ calls
Datasource (remote / local)                              → returns/accepts DTOs, throws AppFailure
   ↓ calls
ApiClient (Dio wrapper) / DB / Firebase SDK              → raw I/O, interceptors
```

| Layer | Allowed | Forbidden |
|---|---|---|
| Widget | Read state, call state-holder methods | Any import of `dio`/`http`/Firebase, `try/catch` around I/O |
| State holder | Call repositories/use cases, map `Result` to state | HTTP, JSON, `DioException`, `BuildContext` |
| Repository | Orchestrate datasources (cache vs remote), map DTO↔Entity, `guard()` into `Result` | UI types, raw `Response` |
| Datasource | Build requests, parse DTOs, throw `AppFailure` | Business rules, caching policy |
| ApiClient | Base URL, headers, auth, retry, logging, error mapping | Endpoint-specific knowledge |

**Why this many layers:** each has exactly one reason to change (UI design / presentation logic / business+cache policy / endpoint shape / transport). Backend swap touches datasource; token strategy touches ApiClient; offline policy touches repository.

## ApiClient (Dio)

One configured client per backend, created in the DI layer, not a global singleton.

```dart
// core/network/api_client.dart
class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  Future<T> get<T>(String path, {Map<String, dynamic>? query, CancelToken? cancel, required T Function(Object? json) parse}) =>
      _send(() => _dio.get<Object?>(path, queryParameters: query, cancelToken: cancel), parse);

  Future<T> post<T>(String path, {Object? body, CancelToken? cancel, required T Function(Object? json) parse}) =>
      _send(() => _dio.post<Object?>(path, data: body, cancelToken: cancel), parse);

  Future<T> _send<T>(Future<Response<Object?>> Function() call, T Function(Object? json) parse) async {
    try {
      final res = await call();
      return parse(res.data);
    } on DioException catch (e) {
      throw mapDioException(e);
    } on AppFailure {
      rethrow;
    } catch (e, s) {
      throw ParsingFailure(e, s); // parse() blew up: malformed payload
    }
  }
}

Dio buildDio({required String baseUrl, required List<Interceptor> interceptors}) => Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: const {'Accept': 'application/json'},
      ),
    )..interceptors.addAll(interceptors);
```

`Object?` JSON enters the datasource's `parse` callback and becomes a DTO immediately. `Map<String, dynamic>` never travels beyond that.

### Error mapping (the only place `DioException` is understood)

```dart
AppFailure mapDioException(DioException e) {
  final status = e.response?.statusCode;
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => TimeoutFailure(e, e.stackTrace),
    DioExceptionType.connectionError => OfflineFailure(e, e.stackTrace),
    DioExceptionType.cancel => CancelledFailure(e, e.stackTrace),
    DioExceptionType.badResponse => switch (status) {
        401 => UnauthorizedFailure(e, e.stackTrace),
        403 => ForbiddenFailure(e, e.stackTrace),
        404 => NotFoundFailure(e, e.stackTrace),
        409 => ConflictFailure(e, e.stackTrace),
        422 || 400 => ValidationFailure(e, e.stackTrace, fieldErrors: _fieldErrors(e.response?.data)),
        429 => RateLimitedFailure(e, e.stackTrace, retryAfter: _retryAfter(e.response)),
        final int s when s >= 500 => ServerFailure(e, e.stackTrace, statusCode: s),
        _ => UnknownFailure(e, e.stackTrace),
      },
    _ => UnknownFailure(e, e.stackTrace),
  };
}
```
Failure classes and `Result` are defined in `error-handling.md`.

### Interceptors (order matters)

1. **Auth**: attaches the access token from secure storage.
2. **Refresh**: on 401, refresh once (single-flight: concurrent 401s await the same refresh future), retry the original request once; if refresh fails, emit a signed-out event (router redirect handles the rest). Never loop.
3. **Retry**: only idempotent methods (GET, PUT, DELETE, HEAD) or requests carrying an idempotency key; exponential backoff with jitter (e.g. 0.5s, 1s, 2s; max 3 attempts); retry on timeouts, connection errors, 502/503/504, and 429 honoring `Retry-After`. Never retry other 4xx.
4. **Logging**: debug builds only, headers/bodies **redacted** (Authorization, tokens, passwords, PII). In release, log method + path + status + duration at most.

Keep them as separate small classes in `core/network/interceptors/`.

### Request gate (client-side throttling and resilience)

The server enforces real rate limits; the gate keeps the app a good citizen and stops it from amplifying an outage. It wraps sends in `ApiClient`, before the retry interceptor, so retries also pass through it. Ask in discovery whether the backend publishes limits, and size the constants from them.

| Part | Behavior |
|---|---|
| Concurrency cap | At most `ApiConstants.maxConcurrentRequests` in flight; extra requests queue |
| Dedup | Identical in-flight **GET**s (method + URL + query) share one future |
| Host cooldown | After a `429`, new requests to that host wait until `Retry-After` (or `defaultCooldown`) has passed |
| Circuit breaker | After `breakerThreshold` consecutive 5xx or timeouts, fail fast with `ServerFailure` for `breakerWindow`, then let one request through |

```dart
// core/network/request_gate.dart  (sketch)
class RequestGate {
  RequestGate({required this.clock});
  final DateTime Function() clock; // injected so tests control time
  final Map<String, Future<Object?>> _inflight = {};
  final Map<String, DateTime> _cooldownUntil = {};
  final Map<String, DateTime> _openUntil = {};
  final Map<String, int> _failures = {};
  final Queue<Completer<void>> _queue = Queue();
  int _active = 0;

  Future<T> run<T>({required String host, String? dedupKey, required Future<T> Function() call}) async {
    final now = clock();
    final open = _openUntil[host];
    if (open != null && now.isBefore(open)) throw ServerFailure('circuit open', null);
    final cool = _cooldownUntil[host];
    if (cool != null && now.isBefore(cool)) await Future<void>.delayed(cool.difference(now));

    if (dedupKey != null && _inflight[dedupKey] case final Future<Object?> shared) return await shared as T;
    final future = _limited(call);
    if (dedupKey != null) _inflight[dedupKey] = future;
    try {
      final result = await future;
      _failures[host] = 0;
      return result;
    } on RateLimitedFailure catch (f) {
      _cooldownUntil[host] = clock().add(f.retryAfter ?? ApiConstants.defaultCooldown);
      rethrow;
    } on AppFailure catch (f) {
      if (f is ServerFailure || f is TimeoutFailure) {
        final n = _failures[host] = (_failures[host] ?? 0) + 1;
        if (n >= ApiConstants.breakerThreshold) _openUntil[host] = clock().add(ApiConstants.breakerWindow);
      }
      rethrow;
    } finally {
      if (dedupKey != null) _inflight.remove(dedupKey);
    }
  }

  Future<T> _limited<T>(Future<T> Function() call) async {
    if (_active >= ApiConstants.maxConcurrentRequests) {
      final waiter = Completer<void>();
      _queue.add(waiter);
      await waiter.future; // slot is handed over, _active unchanged
    } else {
      _active++;
    }
    try {
      return await call();
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeFirst().complete(); // hand the slot to the next waiter
      } else {
        _active--;
      }
    }
  }
}
```
Constants (`maxConcurrentRequests`, `defaultCooldown`, `breakerThreshold`, `breakerWindow`) live in `ApiConstants`. Tests: burst of requests respects the cap; dedup shares one call; a 429 pauses other requests to the host; the breaker opens, half-opens and closes.

## Datasource and repository

```dart
// data/datasources/product_remote_datasource.dart
class ProductRemoteDataSource {
  ProductRemoteDataSource(this._api);
  final ApiClient _api;

  Future<List<ProductDto>> fetchPage({required int page, required int size, CancelToken? cancel}) =>
      _api.get(
        ApiConstants.products,
        query: {'page': page, 'size': size},
        cancel: cancel,
        parse: (json) => (json! as List).map((e) => ProductDto.fromJson(e! as Map<String, dynamic>)).toList(),
      );
}

// domain/repositories/product_repository.dart
abstract interface class ProductRepository {
  Future<Result<Page<Product>>> getProducts({required int page});
}

// data/repositories/product_repository_impl.dart
class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._remote, this._local);
  final ProductRemoteDataSource _remote;
  final ProductLocalDataSource _local;

  @override
  Future<Result<Page<Product>>> getProducts({required int page}) => guard(() async {
        final dtos = await _remote.fetchPage(page: page, size: ApiConstants.defaultPageSize);
        await _local.cachePage(page, dtos);
        return Page(items: dtos.map((d) => d.toEntity()).toList(), hasMore: dtos.length == ApiConstants.defaultPageSize);
      });
}
```

## How many clients, repositories and datasources

- **One `ApiClient` per backend**, generic with no entity knowledge. A second one only for a second backend with different base URL or auth.
- **One repository per aggregate root**, not per class. `Order` and its `OrderItem`s share one `OrderRepository`; `Product` and `Category` are separate if they are fetched and changed independently.
- **One remote datasource per repository** (plus one local datasource when offline or caching is on). Datasources contain endpoint calls only; caching, mapping and policy live in the repository.
- No repository for an entity with no data access. Don't merge unrelated entities into one repository just to save files.
- **Generic `BaseRepository<T>` / `CrudDataSource<T>` are discouraged.** They fit uniform CRUD and hurt as soon as endpoints differ. Allow one only for a truly uniform CRUD API, recorded in an ADR.
- Naming: the per-entity data class is a **datasource**. "Service" is reserved for cross-cutting interfaces (analytics, crash, push, connectivity, sync).

## Cancellation

Search-as-you-type and screen exit must cancel in-flight work: pass a `CancelToken`, cancel it when the query changes or the state holder is disposed. Combine with a `AppDurations.debounce` debounce. Ignore stale responses in the state holder if cancellation is not possible.

## Pagination

- Pages are an entity (`Page<T>`: items, `hasMore`, cursor/next page), not `List` + loose ints.
- Prefer cursor pagination if the backend offers it (stable under inserts).
- State holder keeps `items`, `isLoadingMore`, `hasMore`, `error`; triggers `loadMore()` when the list is within ~3 items of the end; ignores calls while loading or when `!hasMore`.
- Pull-to-refresh resets to page 1 and replaces items; failure keeps old items and shows a non-blocking error.
- Deduplicate by id when appending.

## Caching strategies (decide per endpoint, record it)

| Strategy | Use for | Notes |
|---|---|---|
| Network only | Payments, anything that must be fresh | Fail loudly offline |
| Cache-first, refresh in background (stale-while-revalidate) | Feeds, catalogs, profiles | Emit cached then fresh via a `Stream` or two state updates |
| Network-first, cache fallback | Settings, reference data | Show "offline" indicator when serving fallback |
| HTTP caching (ETag / If-None-Match) | Large, rarely changing payloads | Let the backend drive it |
| Memory cache with TTL | Hot lookups within a session | Bounded size (LRU); cleared on sign-out |

Every cache has: a key, a TTL or invalidation trigger, a size bound, and is cleared on sign-out. Images use `cached_network_image` (disk cache with a max age/size), not the DB.

## Offline support (only if chosen in discovery)

| Level | Design |
|---|---|
| Read cache | Repository serves local on failure/offline; UI shows a "last updated" stamp and offline banner (connectivity from a `ConnectivityService` interface). |
| Offline writes | **Outbox pattern**: write goes to local DB with `pending` status and a client-generated id, an outbox worker replays in order with retry/backoff, reconciles server ids, and surfaces failures. Mutations carry idempotency keys. |
| Full sync | Add per-record `updatedAt`/version, a conflict policy per entity (last-write-wins, server-wins, merge, or ask the user), tombstones for deletes, and migration tests. Decide the conflict policy with the user; do not guess. |

**Single source of truth:** when offline is on, the UI observes the local DB (a `Stream`), and the network only refreshes the DB. This removes "which copy is right?" bugs.

Connectivity is a hint, not truth: a `connectionError` from a real request is authoritative. Do not block requests on a connectivity flag.

**No-internet UX (all offline levels):**
- A design-system `OfflineBanner` appears when `ConnectivityService` reports offline or a request fails with `OfflineFailure`; it is non-blocking and announces itself to screen readers.
- Screens that failed because of `OfflineFailure` show `ErrorView` with retry (or stale content plus the banner). When connectivity returns, they refresh automatically once (listen to the connectivity stream in the state holder), and sync runs if offline writes are on.
- Retry rules are in `error-handling.md`.

## Offline-first repository (when "full offline with sync" is chosen)

The repository changes shape: reads come from the local DB as a `Stream`, and writes return after the **local** write.

```dart
// domain/repositories/todo_repository.dart
abstract interface class TodoRepository {
  Stream<List<Todo>> watchAll();                 // from the local DB, always
  Future<Result<Todo>> add(NewTodo draft);       // completes after the LOCAL write
  Future<Result<void>> toggle(String id);
  Future<Result<void>> delete(String id);        // soft delete (tombstone) until synced
}

// data/repositories/todo_repository_impl.dart
class TodoRepositoryImpl implements TodoRepository {
  TodoRepositoryImpl(this._local, this._outbox, this._sync, this._newId);
  final TodoLocalDataSource _local;
  final Outbox _outbox;
  final SyncService _sync;
  final String Function() _newId; // client-generated ids (uuid), injected

  @override
  Stream<List<Todo>> watchAll() => _local.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<Todo>> add(NewTodo draft) => guard(() async {
        final id = _newId();
        final row = await _local.insertPending(draft.toRow(id));
        await _outbox.enqueue(entity: 'todo', entityId: id, op: OutboxOp.create, payload: draft.toDto(id).toJson());
        _sync.requestPush(); // fire-and-forget, debounced by the entity's policy
        return row.toEntity();
      });
  // local write + outbox enqueue happen in ONE database transaction
}
```
The local write and the outbox enqueue must be in a single transaction, or a crash between them loses the change.

### Local schema

- Every synced table has: `id` (client-generated), `sync_state` (`synced | pending | failed | conflict`), `updated_at`, `server_version` (or etag), `deleted_at` (tombstone).
- `outbox`: `id` (autoincrement, defines order), `entity`, `entity_id`, `op` (`create | update | delete`), `payload` (json), `idempotency_key` (unique), `status` (`pending | inflight | failed`), `attempts`, `last_error`, `created_at`, `next_attempt_at`.
- `sync_state_meta`: per entity `last_synced_at` and the server `cursor`.

### Sync engine

`SyncService` (an interface in `core/services`, implementation in `data/sync`) exposes `syncAll({force})`, `syncNow(entity)`, `requestPush()` and a `Stream<SyncStatus>`. It is single-flight (a mutex), so triggers never overlap.

**Triggers:** app start, connectivity regained, app resumed (`pullOnResume`), after a local write (`requestPush`, debounced), periodic while in the foreground, pull-to-refresh, and `syncNow`.

**Order: push, then pull.**

1. **Push** the outbox in `id` order. Coalesce redundant ops on the same record (create + update → create; anything + delete → delete). For each op: send with its idempotency key.
   - Success → remove from the outbox; write back server id/version; set the row `synced`.
   - Transient failure (offline, timeout, 5xx, 429) → `attempts++`, `next_attempt_at` = exponential backoff with jitter; stop after `maxRetries`, then mark `failed`.
   - Permanent failure (4xx other than 429) → mark the op and row `failed` with the reason, **skip later ops of the same record** (keep order per record) but continue with unrelated records.
2. **Pull** each entity whose policy says it is due (`staleAfter`, `pullInterval`, `force`): request changes since the stored cursor if the backend supports deltas, otherwise refetch. In one transaction:
   - Record has **no** pending/inflight local change → apply the server version (upsert, or delete for a tombstone).
   - Record **has** a pending local change → run that entity's conflict policy.
   - Save the new cursor only after the transaction commits.

**Conflict policies** (decided with the user per entity and recorded in the ADR; never guessed):

| Policy | Behavior | Fits |
|---|---|---|
| `serverWins` | Discard the local pending change | Reference data, admin-managed content |
| `clientWins` | Re-send the local change over the server version | Personal settings |
| `lastWriteWins` | Compare `updated_at` | Low-stakes data, with clock skew accepted |
| `merge` | Field-level merge through an entity-specific function | Documents, profiles |
| `askUser` | Mark `conflict`, surface both versions in the UI | High-value data |

### Per-entity sync policy

Developers configure sync per entity in one file, and every field has a default:

```dart
// core/constants/sync_defaults.dart
abstract final class SyncDefaults {
  static const Duration pullInterval = Duration(minutes: 15);
  static const Duration staleAfter = Duration(minutes: 5);
  static const Duration pushDebounce = Duration(seconds: 2);
  static const int maxRetries = 5;
}

// data/sync/sync_policies.dart
class SyncPolicy {
  const SyncPolicy({
    this.pullInterval = SyncDefaults.pullInterval, // periodic refresh while the app is open
    this.staleAfter = SyncDefaults.staleAfter,     // pull on read if older than this
    this.pushDebounce = SyncDefaults.pushDebounce, // batch quick successive writes
    this.pullOnResume = true,
    this.wifiOnly = false,
    this.maxRetries = SyncDefaults.maxRetries,
    this.conflict = ConflictPolicy.serverWins,
  });
  // fields omitted for brevity
}

const syncPolicies = <String, SyncPolicy>{
  'todo': SyncPolicy(conflict: ConflictPolicy.lastWriteWins),
  'catalog': SyncPolicy(pullInterval: Duration(hours: 6), wifiOnly: true),
  'settings': SyncPolicy(pushDebounce: Duration.zero, conflict: ConflictPolicy.clientWins),
};
```
The default numbers are starting points, not measured values. Confirm them with the user in discovery (one grouped question, only when sync is on) and record the result in the ADR. Periodic pulls run in the foreground only. Background sync uses WorkManager (Android) / BGTaskScheduler (iOS) with a longer minimum interval, because neither guarantees exact timing. Pull-to-refresh and `syncNow` bypass the interval. Retry backoff is separate from the interval.

### Status in the UI

`Stream<SyncStatus>`: `idle`, `syncing`, `pending(count)`, `failed(count)`, `offline`. The design system provides `SyncStatusChip`, and `failed` items open a screen where the user can retry or discard. Show "last synced" times on read-cache screens.

### Other rules

- Wipe all synced tables, the outbox and cursors on sign-out. Never carry one account's data to another.
- Database migrations are tested with real old-version fixtures; never drop a non-empty outbox in a migration.
- Tests: offline writes, outbox replay after restart, coalescing, each conflict policy, partial batch failure, crash between local write and push, migration with pending ops.

## Firebase / Supabase variants

The chain is identical. The SDK sits where `ApiClient` would: a `FirestoreClient`/`SupabaseClient` wrapper used only by datasources. Firestore documents map to DTOs (`fromFirestore`), then entities; do not leak `DocumentSnapshot`, `Timestamp` or `QuerySnapshot` above the datasource. Map `FirebaseException` codes to `AppFailure` in one function. Realtime listeners are `Stream<Result<...>>` or streams that throw `AppFailure`, cancelled on dispose. Security rules and indexes are part of the deliverable, versioned in the repo.

## GraphQL variant

Generate typed operations (`graphql_codegen`/`ferry`); the generated types are DTOs. Same mapping rules. Map `errors[]` extensions to `AppFailure` in the client wrapper.

## File uploads / downloads

Stream from disk (never `readAsBytes` for large files), report progress through a stream in the datasource, support cancel, and resume or retry where the backend allows. Validate type and size client-side for UX, never as a security control.

## Testing

- ApiClient: test error mapping with `http_mock_adapter` or a fake `HttpClientAdapter`.
- Datasource: feed JSON fixtures, assert DTOs and failures.
- Repository: fake datasources, assert `Result`, caching and mapping.
- Fixtures live in `test/fixtures/` as real captured payloads, including odd ones (nulls, unknown enum values, extra fields).
