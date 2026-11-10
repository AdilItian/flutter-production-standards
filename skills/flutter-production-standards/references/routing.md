# Routing

Read when: adding or changing navigation, deep links, route guards, tabs/shells, or any `context.go/push`.

## Decision

**Default: `go_router` with typed routes (`go_router_builder`).** It is maintained by the Flutter team, supports deep links, web URLs, redirects, shell routes and nested navigation, and typed routes remove stringly-typed navigation entirely.
**Why not Navigator 1.0 named routes:** no deep-link/web story, string arguments, no guards.
**Why not `auto_route`/others:** viable, but a second routing vocabulary for no clear win; choose them only if the project already uses them.
**GetX** projects: use `AppRoutes` + `AppPages` (section below).

Never hardcode a path or name in a widget. `audit.sh` flags `context.go('/…')`, `Navigator.pushNamed('…')`, `Get.toNamed('…')`.

## Structure

```
app/router/
  app_router.dart     # builds GoRouter: composes feature routes, redirect, observers, error page
  app_paths.dart      # path constants for shell-level routes (splash, root)
features/<f>/presentation/routes/<f>_routes.dart   # feature-owned typed routes
```
**Why feature-owned routes:** deleting or extracting a feature removes its routes with it; `app_router.dart` only composes.

### Path constants

```dart
// app/router/app_paths.dart  (and per-feature path constants next to their routes)
abstract final class AppPaths {
  static const String splash = '/splash';
  static const String home = '/';
  static const String login = '/login';
  static const String products = '/products';
  static const String productDetail = ':productId'; // child of products
}
```

### Typed routes (a feature)

```dart
// features/products/presentation/routes/products_routes.dart
part 'products_routes.g.dart';

@TypedGoRoute<ProductsRoute>(
  path: AppPaths.products,
  routes: [TypedGoRoute<ProductDetailRoute>(path: AppPaths.productDetail)],
)
class ProductsRoute extends GoRouteData {
  const ProductsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) => const ProductListScreen();
}

class ProductDetailRoute extends GoRouteData {
  const ProductDetailRoute({required this.productId});
  final String productId;
  @override
  Widget build(BuildContext context, GoRouterState state) => ProductDetailScreen(productId: productId);
}
```
Navigate: `const ProductsRoute().go(context)`, `ProductDetailRoute(productId: id).push(context)`.
Pass **ids**, not objects, through routes (deep links, restoration and web refresh need serializable parameters); the destination loads its own data. Use `$extra` only for non-essential hints (e.g. a prefetched title) and always handle `null`.

### Composition and guards

```dart
// app/router/app_router.dart  (Riverpod shown)
@riverpod
GoRouter appRouter(Ref ref) {
  final auth = ref.watch(authStateListenableProvider); // a Listenable that notifies on auth change
  return GoRouter(
    initialLocation: AppPaths.splash,
    refreshListenable: auth,
    routes: [...$authRoutes, ...$homeRoutes, ...$productsRoutes],
    redirect: (context, state) {
      final status = auth.status;
      final loggingIn = state.matchedLocation == AppPaths.login;
      return switch (status) {
        AuthStatus.unknown => AppPaths.splash,
        AuthStatus.signedOut when !loggingIn => const LoginRoute().location,
        AuthStatus.signedIn when loggingIn || state.matchedLocation == AppPaths.splash => AppPaths.home,
        _ => null,
      };
    },
    errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
    observers: [ref.watch(analyticsRouteObserverProvider)],
  );
}
```
- **One redirect function** owns auth/onboarding/force-update gating. Individual screens never check "am I logged in" and push elsewhere.
- Preserve the intended destination on sign-in redirect (`?from=` encoded query) and return after login.
- Redirects are synchronous. Resolve async state (token read) in bootstrap or a splash state, then notify.
- Create the `GoRouter` once. Do not rebuild it on every state change (it resets navigation); drive changes through `refreshListenable`.

### Shell routes (tabs / persistent navigation)

Use `StatefulShellRoute.indexedStack` for bottom-nav/rail apps so each tab keeps its stack and scroll position. The shell widget is the adaptive navigation component from the design system.

### Navigation helpers

Keep helpers thin and typed; do not wrap go_router in a second abstraction.
```dart
extension NavX on BuildContext {
  void popOrGo(String fallback) => canPop() ? pop() : go(fallback);
}
```
Dialog/sheet/snackbar helpers are in `ui-guidelines.md`, not routing.

### Deep links and notifications

- Android App Links / iOS Universal Links over custom schemes where possible (verifiable, no hijack).
- A push notification payload carries a **route intent** (`type`, `id`), mapped to a typed route in one `NotificationRouter`. Never put raw paths in payloads.
- Validate every deep-link parameter (ids, enums). Treat links as untrusted input. See `security.md`.
- Test: cold start from link, warm start, link while signed out (after login, continue to target).

### Transitions and back behavior

- Define page transitions in the theme (`pageTransitionsTheme`), not per route.
- Android predictive back: do not intercept back with `WillPopScope`; use `PopScope` with `canPop` only for unsaved-changes confirmation.
- Modal flows (checkout, onboarding) get their own nested route tree so back is predictable.

## GetX variant (only if the user chose GetX)

```dart
abstract final class AppRoutes { static const String home = '/home'; static const String login = '/login'; }

abstract final class AppPages {
  static final List<GetPage<dynamic>> pages = [
    GetPage(name: AppRoutes.home, page: HomeScreen.new, binding: HomeBinding()),
    GetPage(name: AppRoutes.login, page: LoginScreen.new, binding: LoginBinding(),
        middlewares: [AuthMiddleware()]),
  ];
}
// Navigation helper: Get.toNamed(AppRoutes.home); arguments only as ids.
```
Bindings own controller creation (`Get.lazyPut`); guards are `GetMiddleware`s; screens never call `Get.find` for repositories.

## Testing routes

- Unit-test the redirect function with fake auth states (pure logic).
- Widget-test navigation with a `MockGoRouter` or by pumping `MaterialApp.router` with the real router and fakes.
- One integration test per deep link type.
