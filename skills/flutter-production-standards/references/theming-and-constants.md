# Theming and Constants

Read when: creating or changing colors, text styles, spacing, radii, elevations, durations, sizes, icons, assets, themes, environment config, API constants or storage keys.

**Rule:** there are no magic values. If a literal appears in `features/`, `shared/`, or `app/`, it is a bug. Literals are allowed only inside `design_system/tokens`, `design_system/theme`, `core/constants`, and tests.

## Two layers: raw tokens, then semantic roles

**Decision:** widgets read **semantic roles** (`colorScheme.primary`, `context.appColors.success`, `textTheme.titleMedium`), never raw palette entries (`AppColors.blue500`).
**Why:** a raw palette reference is a hardcoded color with a nicer name. It cannot adapt to dark mode, high contrast, or rebranding. Semantic roles can.
**Trade-off:** one more mapping step, in exactly one place (`app_theme.dart`).

Raw palette (`AppColors`) is used only by the theme builders. Mark it `abstract final class` with a doc comment "theme builders only".

## Tokens

```dart
// design_system/tokens/app_colors.dart: raw palette, theme builders only
abstract final class AppColors {
  static const Color brand = Color(0xFF3B5BDB);
  static const Color success = Color(0xFF2F9E44);
  static const Color warning = Color(0xFFF08C00);
  static const Color error = Color(0xFFE03131);
  // ...neutrals
}

// design_system/tokens/app_spacing.dart
abstract final class AppSpacing {
  static const double xxs = 2, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32, xxxl = 48;

  static const EdgeInsets screen = EdgeInsets.all(lg);
  static const EdgeInsets card = EdgeInsets.all(lg);

  // Spacers: const, so they cost nothing at runtime
  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
  static const SizedBox gapXl = SizedBox(width: xl, height: xl);
}

// design_system/tokens/app_radius.dart
abstract final class AppRadius {
  static const double sm = 4, md = 8, lg = 12, xl = 16, pill = 999;
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
}

// design_system/tokens/app_sizes.dart: component dimensions
abstract final class AppSizes {
  static const double iconSm = 18, iconMd = 24, iconLg = 32;
  static const double buttonHeightSm = 36, buttonHeightMd = 48, buttonHeightLg = 56;
  static const double minTapTarget = 48;
  static const double strokeThin = 2;
  static const double maxContentWidth = 640;
  static const double avatarSm = 32, avatarMd = 48, avatarLg = 96;
}

// design_system/tokens/app_durations.dart
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration debounce = Duration(milliseconds: 350);
  static const Duration snackbar = Duration(seconds: 4);
}

// design_system/tokens/app_elevation.dart
abstract final class AppElevation { static const double none = 0, low = 1, medium = 3, high = 6; }

// design_system/tokens/app_breakpoints.dart
abstract final class AppBreakpoints { static const double medium = 600, expanded = 840; }
```

`abstract final class` (Dart 3) cannot be instantiated or extended, which is exactly what a constants holder should be.

### Typography

```dart
// design_system/tokens/app_typography.dart
abstract final class AppTypography {
  static const String fontFamily = 'Inter'; // declared in pubspec fonts, or via google_fonts with bundled files

  static TextTheme textTheme(Brightness b) => const TextTheme(
        displayLarge: TextStyle(fontSize: 57, height: 1.12, fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(fontSize: 28, height: 1.29, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 22, height: 1.27, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, height: 1.43),
        labelLarge: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600),
      ).apply(fontFamily: fontFamily);
}
```
Use Material 3 role names (not `h1`, `bigText`) so components and Flutter widgets agree. Add a brand-specific extension only if the design needs a role Material lacks.
**Fonts:** bundle font files; do not fetch fonts at runtime in production (offline failure, privacy, flash of fallback). If a language needs other glyphs, add a fallback list (`fontFamilyFallback`).

## Theme building

```dart
// design_system/theme/app_theme.dart
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: b);
    // For strict brand colors, replace fromSeed with an explicit ColorScheme(...) per brightness.
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      textTheme: AppTypography.textTheme(b),
      extensions: [b == Brightness.light ? AppColorsExtension.light : AppColorsExtension.dark],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: AppTypography.textTheme(b).labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      ),
      cardTheme: CardThemeData(elevation: AppElevation.low, shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius)),
      // appBarTheme, dialogTheme, bottomSheetTheme, snackBarTheme, chipTheme, listTileTheme,
      // navigationBarTheme, dividerTheme, switchTheme, checkboxTheme, tabBarTheme, tooltipTheme...
    );
  }
}
```
Class names for theme data have changed across Flutter versions (e.g. `CardTheme` vs `CardThemeData`). Check the project's Flutter version and use what its analyzer accepts.

**Component themes to define up front:** filled/outlined/text/icon buttons, input decoration, card, app bar, dialog, bottom sheet, snackbar, chip, list tile, navigation bar/rail, divider, switch/checkbox/radio, tab bar, tooltip, progress indicator, page transitions. Components inherit from these; they do not restyle.

### Semantic colors beyond `ColorScheme`

Success, warning, info and similar roles are not in `ColorScheme`. Use a `ThemeExtension` so they get light/dark values and lerp during theme animation:

```dart
@immutable
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  const AppColorsExtension({
    required this.success, required this.onSuccess,
    required this.warning, required this.onWarning,
  });

  final Color success, onSuccess, warning, onWarning;

  static const light = AppColorsExtension(
    success: AppColors.success, onSuccess: Color(0xFFFFFFFF),
    warning: AppColors.warning, onWarning: Color(0xFF000000),
  );
  static const dark = AppColorsExtension(
    success: Color(0xFF69DB7C), onSuccess: Color(0xFF00210B),
    warning: Color(0xFFFFC078), onWarning: Color(0xFF2B1700),
  );

  @override
  AppColorsExtension copyWith({Color? success, Color? onSuccess, Color? warning, Color? onWarning}) =>
      AppColorsExtension(
        success: success ?? this.success, onSuccess: onSuccess ?? this.onSuccess,
        warning: warning ?? this.warning, onWarning: onWarning ?? this.onWarning,
      );

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
    );
  }
}

// design_system/theme/theme_context_x.dart
extension ThemeContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => theme.colorScheme;
  TextTheme get text => theme.textTheme;
  AppColorsExtension get appColors => theme.extension<AppColorsExtension>()!;
}
```

Usage in a widget: `context.colors.primary`, `context.text.titleMedium`, `context.appColors.success`.

### Theme mode

`themeMode` is user state (system / light / dark), persisted in key-value storage, exposed by a small `ThemeModeController`. Default `ThemeMode.system`. If the user chose light-only/dark-only in discovery, still build both themes if there is no cost; ship only the chosen one.

Verify dark mode contrast with the same 4.5:1 text and 3:1 UI component thresholds (`accessibility.md`). Dark mode is not an inverted light mode: avoid pure `#000` on `#FFF` extremes, use tonal surfaces.

## Assets

```dart
// design_system/tokens/app_assets.dart
abstract final class AppAssets {
  static const String _images = 'assets/images';
  static const String _icons = 'assets/icons';
  static const String logo = '$_images/logo.png';
  static const String onboardingWelcome = '$_images/onboarding_welcome.webp';
  static const String iconGoogle = '$_icons/google.svg';
}
```
- Never write an asset path anywhere else. `audit.sh` flags `'assets/…'` outside this file.
- **Prefer generation** when the project allows it: `flutter_gen` (or equivalent) generates typed accessors and fails the build on missing files. Then `AppAssets` is replaced by the generated class and `lib/gen/` is excluded from audits.
- Naming: `snake_case`, purpose-first (`empty_orders.svg`), no spaces, no `final_v2`.
- Formats: SVG (via `flutter_svg`/`vector_graphics`) for icons and flat art, WebP for photos, Lottie/Rive only when motion earns its weight. Provide 1x/2x/3x only for raster images that need it.
- Declare folders (not individual files) in `pubspec.yaml`.

## Icons

`AppIcons` maps *meaning* to icon: `AppIcons.search`, `AppIcons.back`, `AppIcons.delete`. Features say what they mean, and the icon set can change in one file.
```dart
abstract final class AppIcons {
  static const IconData search = Icons.search_rounded;
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
}
```
Directional icons (back/forward/chevron) must mirror in RTL: use `Icons.arrow_back` (auto-mirrors with `matchTextDirection`) or wrap in `Directionality`-aware widget.

## Strings

User-facing text is **not** in a constants class. It lives in ARB files (`localization.md`). A constants file may hold *non-user-facing* strings only (storage keys, header names, event names), and those live in the module that owns them.

```dart
// core/constants/storage_keys.dart
abstract final class StorageKeys {
  static const String accessToken = 'auth.access_token';  // secure store
  static const String themeMode = 'settings.theme_mode';  // key-value
  static const String onboardingDone = 'flags.onboarding_done';
}
```

## Environment and API constants

```dart
// core/config/env.dart
enum Flavor { development, staging, production }

abstract final class Env {
  static late final Flavor flavor;
  // Build-time values from --dart-define-from-file=env/<flavor>.json
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static bool get isProduction => flavor == Flavor.production;
}

// core/constants/api_constants.dart
abstract final class ApiConstants {
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const int defaultPageSize = 20;
  // Paths: relative, versioned in one place
  static const String products = '/v1/products';
  static String productById(String id) => '/v1/products/$id';
}
```
Validate required `Env` values at startup and fail loudly with a clear message (`assert` is not enough in release; throw a `StateError` in `bootstrap` if `apiBaseUrl` is empty).
**Security:** `--dart-define` values are compiled into the binary and are extractable. They are configuration, not secrets. See `security.md`.

Other constants belong to their owner, not a global junk file: pagination limits near networking, validation lengths near validators (`AppLimits`), animation values in `AppDurations`.
