# Routing

Read when: adding or changing navigation, deep links, route guards, tabs/shells, or any `Get.toNamed` / navigation call.

## Decision

**Default: GetX navigation** (the `get` package: `GetMaterialApp`, `GetPage`, `GetMiddleware`, named routes), organized in two central files:

- `app/routes/app_routes.dart`: `AppRoutes`, every route name and path in one place.
- `app/routes/app_pages.dart`: `AppPages`, the list of `GetPage`s (page builder, transition, middleware, binding).

**Why:** one obvious place for every route, string-free navigation in screens, middleware for guards, route-scoped bindings when GetX state is used, and no extra routing concepts to learn.
**Trade-offs, stated once:** GetX uses the Navigator 1.0 style, so routes are strings, not compile-time-typed objects. Deep links work by route name and path, with less type safety and a weaker nested-navigation story than `go_router`. The skill compensates with `AppRoutes` builder functions, an `AppNavigation` helper layer, and an `audit.sh` rule against string literals in navigation calls. Keep GetX for navigation only if the project uses Riverpod or Bloc for state; mixing is fine because routing and state are different concerns, but `Bindings` are only used when the project also uses GetX state.
**`go_router`** stays a valid alternative (see the last section) when the project already uses it or the user chooses it in discovery.

## Files

```
lib/app/routes/
  app_routes.dart        # route names/paths + builders for parameterized paths
  app_pages.dart         # AppPages.pages: List<GetPage>
  app_navigation.dart    # AppNavigation: the only place that calls Get.toNamed/offNamed/offAllNamed
  middlewares/
    auth_middleware.dart
```
Tier L (packages): each feature package exports its own `List<GetPage>`, and `AppPages` spreads them: `...authPages, ...homePages`. Tier S/M keep one list.

### AppRoutes

```dart
// app/routes/app_routes.dart
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String home = '/';
  static const String search = '/search';
  static const String notFound = '/not-found';

  // Parameterized routes: a pattern for AppPages and a builder for callers
  static const String titleDetailPattern = '/title/:id';
  static String titleDetail(String id) => '/title/${Uri.encodeComponent(id)}';

  // Parameter names, so screens never use raw 'id' strings
  static const String paramId = 'id';
}
```
Rules: constants only; one pattern constant plus one builder per parameterized route; `Uri.encodeComponent` on values; no logic.

### AppPages

```dart
// app/routes/app_pages.dart
abstract final class AppPages {
  static final List<GetPage<dynamic>> pages = [
    GetPage(name: AppRoutes.splash, page: SplashScreen.new),
    GetPage(name: AppRoutes.login, page: LoginScreen.new),
    GetPage(
      name: AppRoutes.home,
      page: HomeScreen.new,
      middlewares: [AuthMiddleware(appContainer)], // see Guards
      binding: HomeBinding(), // only if the project uses GetX state
    ),
    GetPage(
      name: AppRoutes.titleDetailPattern,
      page: () => TitleDetailScreen(id: Get.parameters[AppRoutes.paramId]!),
      transition: Transition.rightToLeft,
    ),
  ];

  static final GetPage<dynamic> notFound =
      GetPage(name: AppRoutes.notFound, page: NotFoundScreen.new);
}
```
Screens come from feature barrels (`features/title_detail/title_detail.dart`), never from a feature's `presentation/` internals. Validate parameters (`Get.parameters[...]` is a `String?`): parse to the expected type and show the not-found state on failure.

### App widget

```dart
GetMaterialApp(
  initialRoute: AppRoutes.splash,
  getPages: AppPages.pages,
  unknownRoute: AppPages.notFound,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: themeMode,
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  defaultTransition: Transition.fade, // define once; pick per brand/platform
  transitionDuration: AppDurations.normal,
  routingCallback: analyticsRouteObserver.onRoute, // screen tracking
);
```
Wrap with `ProviderScope`/`UncontrolledProviderScope` (Riverpod) or the Bloc providers above it, as the project requires. Check the `get` package's current API on pub.dev; parameter names have changed between versions.

### AppNavigation: no string navigation anywhere else

```dart
// app/routes/app_navigation.dart
abstract final class AppNavigation {
  static Future<T?>? toTitleDetail<T>(String id) => Get.toNamed<T>(AppRoutes.titleDetail(id));
  static Future<T?>? toSearch<T>() => Get.toNamed<T>(AppRoutes.search);
  static void toHomeClearingStack() => Get.offAllNamed<void>(AppRoutes.home);
  static void toLoginClearingStack() => Get.offAllNamed<void>(AppRoutes.login);
  static void back<T>([T? result]) => Get.back<T>(result: result);
}
```
Widgets call `AppNavigation.toTitleDetail(id)`. Raw `Get.toNamed('/…')` in a widget is rejected by `audit.sh`. Pass **ids**, never objects, through routes; the destination loads its own data. Use `arguments` only for non-essential hints and handle `null`.

## Guards

```dart
// app/routes/middlewares/auth_middleware.dart
class AuthMiddleware extends GetMiddleware {
  AuthMiddleware(this._session);
  final AuthSession _session; // small interface in shared/, implemented by the auth feature

  @override
  int? get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    switch (_session.status) {
      case AuthStatus.signedIn:
        return null;
      case AuthStatus.unknown:
        return const RouteSettings(name: AppRoutes.splash);
      case AuthStatus.signedOut:
        _session.rememberDestination(route); // go back here after login
        return const RouteSettings(name: AppRoutes.login);
    }
  }
}
```
- **One place decides** who may enter which route. Screens never check "am I logged in?" and navigate away.
- `redirect` is synchronous: resolve async state (reading the token) in bootstrap or on the splash screen, then navigate.
- The guard depends on a small interface (`AuthSession`) so it works with Riverpod (read from the root `ProviderContainer`), Bloc, or GetX state.
- React to later changes (sign-out, expired refresh token) by calling `AppNavigation.toLoginClearingStack()` from one listener in the app shell, not from random widgets.
- After login, go to `rememberedDestination` if present, else home.

## Deep links and notifications

- Flutter passes the incoming URL to the app as a route name, so every deep-linkable path must have a `GetPage` pattern in `AppPages` (including parameters).
- Android App Links and iOS Universal Links are preferred over custom schemes (verifiable). For web, enable the path URL strategy (`usePathUrlStrategy()`).
- A push or local-notification payload carries a **route intent** (`type`, `id`), mapped to `AppRoutes` builders in one `NotificationRouter`. Never put raw paths in payloads.
- Treat links as untrusted input: validate ids and enums, require the guard for private routes, confirm destructive actions. See `security.md`.
- Test: cold start from a link, warm start, link while signed out (after login, continue to the target), unknown path (not-found screen).

## Tabs and shells

Navigator 1.0 has no built-in shell route. Use one `MainShellScreen` holding the bottom navigation or rail and an `IndexedStack` (keeps each tab's state and scroll position), with the tab's content as ordinary widgets. Detail screens open above the shell with `AppNavigation`. If tabs need their own back stacks, use nested navigators (`Get.nestedKey`) and document the exception, or choose `go_router`.

## Back behavior and transitions

- Define `defaultTransition` and its duration once in the app widget; override per `GetPage` only with a reason.
- Don't intercept back with `WillPopScope`. Use `PopScope` with `canPop` only for unsaved-changes confirmation.
- Modal flows (checkout, onboarding) get their own start route and finish with `offAllNamed` or a defined return route so back is predictable.
- Dialogs, sheets and snackbars use the design-system helpers (`ui-guidelines.md`), not `Get.dialog` / `Get.snackbar` in features.

## Testing routes

- Unit-test the middleware with a fake `AuthSession` for each status.
- Test that `AppRoutes` builders produce the expected paths (including encoding) and that every pattern in `AppRoutes` has a `GetPage`: a test that walks `AppPages.pages` catches a missing route.
- Widget-test navigation with `GetMaterialApp(getPages: AppPages.pages)` and fakes.
- One integration test per deep-link type.

## Alternative: go_router (when already in the project or chosen)

Use `go_router` with typed routes (`go_router_builder`). Keep the same ideas: path constants in one `AppPaths` class, one `redirect` that owns auth gating, ids only in parameters, `StatefulShellRoute.indexedStack` for tab apps, a single `GoRouter` instance driven by `refreshListenable`, and `const HomeRoute().go(context)` style navigation. The `audit.sh` rule against string literals applies to `context.go('/…')` as well. Everything else in this skill (layering, feature barrels, tests) is unchanged.
