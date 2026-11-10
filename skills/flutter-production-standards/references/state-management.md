# State Management

Read when: creating any controller / notifier / bloc / GetX controller, or deciding which to use.

## Choosing

If the user has chosen one, use it. If they ask for a recommendation, apply this table and explain.

| Situation | Recommend | Why |
|---|---|---|
| New app, any size, team comfortable with modern Dart | **Riverpod** | Compile-time-safe DI + state in one tool, easy to test with overrides, scoped rebuilds with `select`, async is first class (`AsyncValue`), no `BuildContext` dependency |
| Large team that wants strict, auditable event → state flow; existing Bloc codebase; heavy event-driven domains (chat, streams) | **Bloc / Cubit** | Explicit events/transitions, great logging/replay, `bloc_test`. More boilerplate. Use Cubit for simple screens, Bloc when event transforms (debounce, restartable) matter |
| Small/simple app, solo, quick prototype | **Riverpod** still, or `ValueNotifier`/`ChangeNotifier` for 1-2 screens | Not worth adding a framework for trivial local state |
| Existing GetX project | **GetX, with the rules below** | Migrating is a separate decision; do not mix in a second system without an ADR |
| New project, user asks for GetX | Use it if insisted, but state the risks first | See below |

**Challenging the GetX choice (say this once, then respect the decision):** GetX bundles state, DI, routing, dialogs and utilities behind global `Get.*` calls. That makes widgets implicitly depend on global state, hides dependency flow (harder to enforce the layering this skill requires), makes tests need global setup/teardown, and has had long gaps in maintenance. It works, and many apps ship with it, but for a long-lived codebase Riverpod or Bloc give stronger guarantees.

**Never mix two global state systems** in one feature. Local widget state (`StatefulWidget` for animation controllers, text controllers, focus) is always fine and preferred for ephemeral UI state.

## What is state, and where does it live

| Kind | Example | Where |
|---|---|---|
| Ephemeral UI | focus, tab index, animation, text field controller | `StatefulWidget` / hooks |
| Screen state | loaded list, form values, selected filters, loading/error | Feature state holder |
| App/session state | current user, theme mode, locale, connectivity | `shared/providers` or `app/di`, provided globally |
| Server cache | fetched entities | Repository + (optional) local DB; state holder reads through it |

Derive, don't duplicate: `isEmpty`, totals, filtered lists are computed from state, not stored.

## Do I need a controller? (decide before creating one)

Go in order and stop at the first yes. A state holder (controller, notifier, Bloc/Cubit, GetX controller) is the ViewModel of a screen, and it must earn its place.

1. **State is visual and owned by one widget** (text field, tab index, animation, focus) → no controller; use a `StatefulWidget`.
2. **The data already lives in an existing state holder and this screen only reads it** (current user, theme, cart count) → reuse it; read with `select`.
3. **The screen is static or derived only from route parameters** → no controller.
4. **The screen loads data, submits actions, or holds state that must survive rebuilds** → create **one** controller for that screen.
5. **Two or more screens must share and change the same state** → one shared controller in `shared/providers`, not one per screen.

Limits:
- One controller per screen, not per widget. Split a screen into two only for unrelated concerns (e.g. a list plus an independent filter panel).
- Never two controllers holding the same data; they will disagree.
- A controller that only forwards a repository call and adds no state or logic is deleted; the widget reads the repository-backed provider directly. (Same test as use cases in `architecture.md`.)
- Record the answer for non-obvious screens in a one-line comment on the controller: why it exists.

## State shape

- Immutable. Equality by value (`freezed`, `equatable`, or hand-written with records).
- Model mutually exclusive situations with **sealed classes**, not a pile of booleans:

```dart
sealed class ProductListState { const ProductListState(); }
final class ProductListLoading extends ProductListState { const ProductListLoading(); }
final class ProductListLoaded extends ProductListState {
  const ProductListLoaded({required this.items, required this.hasMore, this.isLoadingMore = false, this.loadMoreFailure});
  final List<Product> items; final bool hasMore; final bool isLoadingMore; final AppFailure? loadMoreFailure;
}
final class ProductListFailed extends ProductListState { const ProductListFailed(this.failure); final AppFailure failure; }
```
The widget `switch`es exhaustively; the compiler forces every state to be rendered. With Riverpod, `AsyncValue<T>` already encodes loading/data/error; use it for simple cases and a sealed type when the screen has richer modes.
- State holds **entities and primitives**, never `BuildContext`, widgets, controllers, or DTOs.
- Failures stay typed (`AppFailure`); widgets translate them to text with l10n (`error-handling.md`).

## One-shot events (navigation, snackbars, dialogs)

Do not stuff "show a snackbar" into persistent state (it re-fires on rebuild/rotation). Options:
- Riverpod: `ref.listen(provider, (prev, next) {...})` in the widget, reacting to *transitions* (e.g. `next is Failed && prev is! Failed`), or a `StreamProvider` of events.
- Bloc: `BlocListener` (reacts to transitions) or a separate effects stream.
- GetX: `ever()`/worker in controller calling an injected `UiMessenger`, not `Get.snackbar` directly.

## Riverpod rules

- Use codegen (`riverpod_generator`) for new code; follow the project's existing style if it uses hand-written providers.
- Providers are declared in `<feature>_providers.dart` (wiring) and `presentation/state/` (state notifiers).
- Repositories and datasources: plain providers (`@riverpod X x(Ref ref) => X(ref.watch(dep))`), overridable in tests.
- Controllers: `AsyncNotifier`/`Notifier`. `build()` loads initial state. Methods mutate through `state = ...`; wrap actions in `AsyncValue.guard`.
- `ref.watch` in `build`, `ref.read` in callbacks, `ref.listen` for side effects. Never `ref.read` in `build` for reactive data.
- Reduce rebuilds with `select`: `ref.watch(p.select((s) => s.items.length))`.
- `autoDispose` by default (the generator's default); `keepAlive` deliberately and documented.
- Family parameters must have value equality.
- Don't call `ref` after dispose; check `ref.mounted` after awaits in long operations.

```dart
@riverpod
class ProductListController extends _$ProductListController {
  @override
  Future<List<Product>> build() => _fetch(page: 1);

  Future<List<Product>> _fetch({required int page}) async {
    final repo = ref.read(productRepositoryProvider);
    return switch (await repo.getProducts(page: page)) {
      Ok(:final value) => value.items,
      Err(:final failure) => throw failure,
    };
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _fetch(page: 1));
  }
}
```

## Bloc rules

- **Cubit** for straightforward state transitions; **Bloc** when event processing needs `transformer` (debounce, `restartable`, `droppable`).
- Events are past-tense or imperative facts, sealed (`ProductsRequested`, `ProductsRefreshed`). States sealed or single immutable class with a status enum.
- Blocs receive repositories by constructor; provide with `BlocProvider` at the route/feature boundary (create in `create:`, never in `build`).
- `emit` only inside handlers, check `isClosed` after awaits in long handlers (or use `emit.isDone`).
- Use `BlocSelector` / `buildWhen` to limit rebuilds; `BlocListener` for one-shot effects.
- Blocs never talk to each other directly; share via repositories/streams or lift the coordination to a parent.
- Test with `bloc_test` (`blocTest`), fake repositories.

## GetX rules (if chosen)

- Controllers extend `GetxController`, created by **Bindings** attached to routes (`Get.lazyPut`), never in widget `build`.
- Widgets obtain controllers via `GetView<T>` / `Get.find` **of the controller only**; repositories reach controllers by constructor injection in the Binding.
- Reactive fields: `Rx<T>`/`.obs`, exposed read-only (`RxList` private + getter returning `List`/`Obx`-friendly view); mutate through controller methods.
- Scope `Obx` as small as possible; never wrap a whole screen.
- Dispose workers/streams in `onClose`.
- UI feedback (snackbar/dialog) goes through the design-system helpers via an injected messenger/BuildContext-safe listener, not scattered `Get.snackbar`.
- Do not use `GetStorage` for secrets; routes through `AppRoutes`/`AppPages` (`routing.md`).
- Because there is no compile-time guard against `Get.find` in widgets, `audit.sh` and review must enforce layering.

## Rebuild discipline (all frameworks)

- Subscribe to the smallest slice that the widget renders.
- Put state consumers low in the tree; extract the subtree that changes into its own widget.
- Don't create state objects, futures or streams in `build`.
- Keep `const` constructors on everything that can have one.
See `performance.md`.

## Testing state holders

- Unit-test with fake repositories (hand-written fakes preferred over heavy mocking): initial state, success, each failure type, refresh, pagination edge cases, cancellation, disposal.
- Riverpod: `ProviderContainer(overrides: [...])`. Bloc: `blocTest`. GetX: `Get.put` in `setUp`, `Get.reset()` in `tearDown`.
- Assert **state transitions**, not implementation calls.
