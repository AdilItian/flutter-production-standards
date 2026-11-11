# Error Handling and Logging

Read when: handling any failure, adding retry, writing user-facing error text, configuring global handlers, logging, or crash reporting.

## Principles

1. Errors are **typed values** across layer boundaries, not strings and not raw exceptions.
2. Handle an error at the lowest layer that can *do* something about it (retry, fallback to cache); translate at every boundary; present at the top.
3. Never swallow. Every `catch` either handles, rethrows as a typed failure, or logs with context. Empty `catch` blocks are rejected.
4. Users see friendly, localized, actionable messages. Developers see structured logs with the cause and stack trace.

## One hierarchy, one wrapper

**Decision:** a single sealed `AppFailure` hierarchy used both as the thing datasources `throw` and as the error inside `Result`. Many Clean Architecture guides use separate `Exception` (data) and `Failure` (domain) hierarchies; in practice they mirror each other 1:1 and double the boilerplate. One hierarchy in `core/error` is enough because it is pure Dart and not tied to any transport.

```dart
// core/error/app_failure.dart
sealed class AppFailure implements Exception {
  const AppFailure(this.cause, [this.stackTrace]);
  final Object? cause;
  final StackTrace? stackTrace;
}
final class OfflineFailure extends AppFailure { const OfflineFailure(super.cause, [super.stackTrace]); }
final class TimeoutFailure extends AppFailure { const TimeoutFailure(super.cause, [super.stackTrace]); }
final class UnauthorizedFailure extends AppFailure { const UnauthorizedFailure(super.cause, [super.stackTrace]); }
final class ForbiddenFailure extends AppFailure { const ForbiddenFailure(super.cause, [super.stackTrace]); }
final class NotFoundFailure extends AppFailure { const NotFoundFailure(super.cause, [super.stackTrace]); }
final class ConflictFailure extends AppFailure { const ConflictFailure(super.cause, [super.stackTrace]); }
final class RateLimitedFailure extends AppFailure {
  const RateLimitedFailure(super.cause, super.stackTrace, {this.retryAfter});
  final Duration? retryAfter;
}
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.cause, super.stackTrace, {this.fieldErrors = const {}});
  final Map<String, List<String>> fieldErrors;
}
final class ServerFailure extends AppFailure {
  const ServerFailure(super.cause, super.stackTrace, {this.statusCode});
  final int? statusCode;
}
/// Domain rule violated (e.g. insufficient funds). `code` is a feature-owned enum.
final class BusinessRuleFailure extends AppFailure {
  const BusinessRuleFailure(this.code, [Object? cause, StackTrace? stackTrace]) : super(cause, stackTrace);
  final Enum code;
}
final class ParsingFailure extends AppFailure { const ParsingFailure(super.cause, [super.stackTrace]); }
final class CancelledFailure extends AppFailure { const CancelledFailure(super.cause, [super.stackTrace]); }
final class UnknownFailure extends AppFailure { const UnknownFailure(super.cause, [super.stackTrace]); }
```
**Feature-specific failures:** a `sealed` class can only be extended in its own library, so features do not subclass `AppFailure`. They throw/return `BusinessRuleFailure(MyFeatureError.insufficientFunds)` with a feature-owned enum, and the feature's presentation maps that enum to an l10n message. This keeps the core switch exhaustive without core knowing feature vocabulary.

```dart
// core/error/result.dart
sealed class Result<T> { const Result(); }
final class Ok<T> extends Result<T> { const Ok(this.value); final T value; }
final class Err<T> extends Result<T> { const Err(this.failure); final AppFailure failure; }

extension ResultX<T> on Result<T> {
  R fold<R>({required R Function(T) ok, required R Function(AppFailure) err}) =>
      switch (this) { Ok(:final value) => ok(value), Err(:final failure) => err(failure) };
  T? get valueOrNull => switch (this) { Ok(:final value) => value, Err() => null };
}

// core/error/guard.dart
Future<Result<T>> guard<T>(Future<T> Function() body) async {
  try {
    return Ok(await body());
  } on AppFailure catch (f) {
    return Err(f);
  } catch (e, s) {
    // Unknown error: still a value, never an uncaught throw from a repository
    return Err(UnknownFailure(e, s));
  }
}
```

**Why `Result` at the repository and not exceptions all the way up:** the compiler forces callers to handle the failure branch; no forgotten `try/catch`; no accidental crash from an unexpected throw. Inside a datasource, plain `throw`/`await` keeps code straight-line, and `guard` converts at the boundary.

## Failure → user message (presentation only)

```dart
// presentation: one exhaustive mapping, localized
extension AppFailureL10n on AppFailure {
  String message(AppLocalizations l10n) => switch (this) {
        OfflineFailure() => l10n.errorOffline,
        TimeoutFailure() => l10n.errorTimeout,
        UnauthorizedFailure() => l10n.errorSessionExpired,
        ForbiddenFailure() => l10n.errorForbidden,
        NotFoundFailure() => l10n.errorNotFound,
        ConflictFailure() => l10n.errorConflict,
        RateLimitedFailure() => l10n.errorRateLimited,
        ValidationFailure() => l10n.errorValidation,
        ServerFailure() => l10n.errorServer,
        BusinessRuleFailure() => l10n.errorUnknown, // features override via their own code->message map
        ParsingFailure() || UnknownFailure() => l10n.errorUnknown,
        CancelledFailure() => '',
      };
  bool get isRetryable => this is OfflineFailure || this is TimeoutFailure || this is ServerFailure || this is RateLimitedFailure;
}
```
Messages say what happened and what to do ("You're offline. Check your connection and try again."), never expose status codes, stack traces, SQL or server text. `ErrorView(failure:, onRetry:)` shows the message and a Retry button only when `isRetryable`. Because the switch is exhaustive over a sealed type, adding a failure forces you to add its message.

Field-level `ValidationFailure.fieldErrors` map onto `AppTextField(errorText:)`.

## Global handlers (bootstrap)

```dart
Future<void> bootstrap(Widget Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();
  final crash = /* CrashService implementation for the flavor */;

  FlutterError.onError = (details) {          // framework errors (build, layout, paint)
    logger.e('flutter error', error: details.exception, stackTrace: details.stack);
    crash.recordFlutterError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {   // async errors outside the framework
    logger.e('uncaught', error: error, stackTrace: stack);
    crash.recordError(error, stack, fatal: true);
    return true;
  };
  ErrorWidget.builder = (details) => Env.isProduction ? const FriendlyCrashWidget() : ErrorWidget(details.exception);

  runApp(builder());
}
```
- No `runZonedGuarded` needed when `PlatformDispatcher.onError` is used on current Flutter; it must wrap `ensureInitialized` and `runApp` in the same zone if used.
- In production, replace the red error screen with a friendly widget; in debug keep it.
- Keep crash reporting disabled in debug and respect user consent where required.

## Logging

- Interface `AppLogger` in `core/logging` (`d`, `i`, `w`, `e`), backed by the `logger` package or similar. Features inject it.
- No `print`/`debugPrint` (lint + `audit.sh`).
- Levels: debug (dev only), info (lifecycle events), warning (recoverable, e.g. retry), error (failure with `error` + `stackTrace`).
- **Redact** tokens, passwords, emails, phone numbers, card data and any PII before logging. Log ids, not payloads.
- In release: warnings and errors go to the crash service as breadcrumbs/non-fatals; info stays out unless needed.
- Attach context: feature, operation, request id/correlation id if the backend sends one.

## Retry

| Where | Policy |
|---|---|
| Transport (interceptor) | Automatic, idempotent requests only, exponential backoff + jitter, max 3, honor `Retry-After` (`networking.md`) |
| UI | Manual "Retry" button for retryable failures; never auto-loop a user-visible failure |
| Background sync | Backoff with a ceiling, persisted attempt count, stop and surface after N failures |

Never retry on `ValidationFailure`, `Unauthorized` (after one refresh), `Forbidden`, `NotFound`.

## Error UX rules

- Inline/field errors for validation; non-blocking snackbar for background failures; full `ErrorView` when there is nothing to show; keep stale content visible, with the connectivity chip or a toast, when a refresh fails.
- Preserve user input on failure. Never clear a form because a submit failed.
- Destructive or financial operations: say clearly whether the action happened ("Payment was not completed. You have not been charged." only if true).
- Do not show errors for `CancelledFailure`.
- Announce errors to screen readers (`SemanticsService.announce` or `liveRegion`).

## Testing

Failure mapping tables, `guard` behavior, one test per `AppFailure` → message, `ErrorView` retry visibility, state holders emitting the right failure state, and a test that global handlers forward to the crash service fake.
