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
