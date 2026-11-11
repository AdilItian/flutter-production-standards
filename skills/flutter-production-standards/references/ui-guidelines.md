# UI Guidelines: Design System First

Read when: building any widget, component, or screen, or consuming a design (Figma, screenshot, mockup). Also read `accessibility.md` and `theming-and-constants.md`.

## The procedure (never skip, never reorder)

1. **Analyze** the design. Fill `templates/design-analysis.md`: tokens, repeated patterns, components, states.
2. **Map** every element to an existing component in `design_system/components` or `shared/widgets`. Search the repo before creating anything.
3. **Tokens first.** Add missing tokens (colors, text roles, spacing) to `design_system/tokens`; snap near-values (15 → 16) and flag genuine inconsistencies to the user.
4. **Components next.** Create missing components with the full contract below. Add a widget test (and golden if the project uses them).
5. **Compose the screen** from components. The screen file should read like an outline.
6. **State coverage**: loading, content, empty, error (+ offline where relevant).
7. **Report**: list components reused vs created.

**Why this order:** building the screen first bakes magic numbers and one-off styling into feature code, and copy-paste duplicates then diverge. Tokens and components first make the compliant path the lazy path.

## Component contract (every design-system component)

- Const constructor, named parameters, `required` for essentials.
- Variants as **enums** (`AppButtonSize`, `AppBadgeTone`), not booleans-soup (`isSmall`, `isRed`).
- Styling from tokens and theme only. Zero literals.
- States: enabled, disabled, **loading** (if async-triggering), focused, pressed, error (inputs). Minimum 48×48 dp hit target.
- `Semantics` label sourced from caller or l10n, never hardcoded.
- Direction-aware (`EdgeInsetsDirectional`, `AlignmentDirectional`, `TextDirection`).
- Text-scale safe: no fixed heights on text containers; use `minHeight` and padding.
- No business types in the signature. A button takes `String label`, not a `Product`.
- Callbacks, not state holders: components do not read providers/blocs. Feature widgets do.
- One component per file in the matching `components/<group>/` folder.

## Required baseline components

Create these during foundation (Step 3) so features never invent their own:

| Group | Components |
|---|---|
| Buttons | `PrimaryButton`, `SecondaryButton`, `AppTextButton`, `AppIconButton` |
| Inputs | `AppTextField` (label, hint, error, obscure toggle, prefix/suffix), `PasswordField`, `SearchField`, `AppDropdown`, `AppCheckbox`/`AppSwitch` as needed |
| Display | `AppCard`, `ProfileAvatar` (image/initials/placeholder), `AppBadge`, `AppListTile`, `AppDivider` |
| Media | `AppNetworkImage` (wraps `cached_network_image`, with skeleton, fade-in, failure-with-retry), `ImageFallback` |
| Feedback | `LoadingView`, `EmptyState`, `ErrorView` (with retry), `AppSnackbar` helper, `AppSkeleton` |
| Navigation | `AppAppBar`, bottom/rail navigation shell |
| Overlays | `showAppDialog`, `showAppBottomSheet`, confirm dialog |
| Layout | `AppScaffold` (safe area, padding, max content width), `AppGap` spacers, `ResponsiveBuilder` |

## Reference implementation: `PrimaryButton`

```dart
enum AppButtonSize { small, medium, large }

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.size = AppButtonSize.medium,
    this.expanded = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final AppButtonSize size;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final child = isLoading
        ? const SizedBox.square(
            dimension: AppSizes.iconSm,
            child: CircularProgressIndicator(strokeWidth: AppSizes.strokeThin),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: AppSizes.iconSm), AppSpacing.gapSm],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );

    final button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(minimumSize: Size(0, size.height)),
      child: child,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true, // announce the label, not the spinner internals
      child: expanded ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

extension on AppButtonSize {
  double get height => switch (this) {
        AppButtonSize.small => AppSizes.buttonHeightSm,
        AppButtonSize.medium => AppSizes.buttonHeightMd,
        AppButtonSize.large => AppSizes.buttonHeightLg,
      };
}
```

Colors, shape and text style come from `FilledButtonThemeData` in the theme, **not** from the widget. Restyling the app means editing the theme once.

## Network images: one component, never a raw call

**Rule:** every remote image is shown through `AppNetworkImage` (`design_system/components/media`), which wraps `cached_network_image`. Feature code never calls `Image.network`, `NetworkImage`, `CachedNetworkImage` or `CachedNetworkImageProvider` directly (`audit.sh` flags it). Avatars, cards, galleries and `CircleAvatar` backgrounds all go through it or through a component built on it (`ProfileAvatar`).

**Why:** `Image.network` has no disk cache, no sensible loading state and no failure state, so every screen reinvents them differently. One wrapper gives caching, decode-at-display-size, a consistent skeleton, a consistent failure state with retry, and semantics, and a package swap touches one file.

Contract:

| State | Behavior |
|---|---|
| **No url** (null or empty) | Neutral fallback with a generic icon. Not an error and no retry. |
| **Loading** | Skeleton the size of the final box (shimmer, static when reduced motion is on), never a spinner on a collapsed box. Reserve space with `aspectRatio` or a fixed size so the layout doesn't jump. |
| **Loaded** | Fade in over `AppDurations.fast`. Decode at display size (`memCacheWidth`/`memCacheHeight` from the layout constraints and device pixel ratio). |
| **Failed** | Tinted surface with a "broken image" icon. If the box is large enough, show a localized "Tap to retry" label; tapping evicts the cached entry and retries. Small boxes (under ~64 dp) show the icon only, still tappable. |
| **Semantics** | A localized label for informative images; `decorative: true` excludes decorative ones. The failed state announces "Image failed to load. Double tap to retry." from l10n. |

```dart
class AppNetworkImage extends StatefulWidget {
  const AppNetworkImage({
    required this.url,
    this.semanticLabel,
    this.decorative = false,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.httpHeaders,
    super.key,
  });

  final String? url;
  final String? semanticLabel; // from context.l10n; required in practice unless decorative
  final bool decorative;
  final double? aspectRatio;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final Map<String, String>? httpHeaders; // e.g. auth for protected images

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  int _attempt = 0; // changing the key forces a fresh load

  Future<void> _retry() async {
    await CachedNetworkImage.evictFromCache(widget.url!);
    if (mounted) setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    Widget child = (url == null || url.isEmpty)
        ? const ImageFallback.noImage()
        : LayoutBuilder(builder: (context, c) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            // Set only one dimension so the aspect ratio is kept.
            final cacheW = c.hasBoundedWidth ? (c.maxWidth * dpr).round() : null;
            final cacheH = cacheW == null && c.hasBoundedHeight ? (c.maxHeight * dpr).round() : null;
            return CachedNetworkImage(
              key: ValueKey('$url#$_attempt'),
              imageUrl: url,
              httpHeaders: widget.httpHeaders,
              fit: widget.fit,
              memCacheWidth: cacheW,
              memCacheHeight: cacheH,
              fadeInDuration: AppDurations.fast,
              fadeOutDuration: AppDurations.instant,
              placeholder: (_, __) => const AppSkeleton(),
              errorWidget: (_, __, ___) => ImageFallback.failed(onRetry: _retry),
            );
          });

    if (widget.aspectRatio != null) child = AspectRatio(aspectRatio: widget.aspectRatio!, child: child);
    child = ClipRRect(borderRadius: widget.borderRadius, child: child);
    return widget.decorative
        ? ExcludeSemantics(child: child)
        : Semantics(image: true, label: widget.semanticLabel, child: child);
  }
}
```
`ImageFallback` is a small component in the same folder: `.noImage()` shows a neutral icon; `.failed(onRetry:)` shows the broken-image icon on `colorScheme.surfaceContainerHighest`, an `InkWell` with at least a 48 dp tap area, and, when `constraints.maxWidth >= 64`, the localized retry label. Colors, icons (`AppIcons.imageBroken`, `AppIcons.imageEmpty`) and spacing come from tokens, as everywhere.

Notes and rules:
- Pass **sized** boxes. An unbounded image can't be decoded at display size and may load the full-resolution original.
- Ask the server for the right size and format (a width parameter, WebP). The decode size here reduces memory; it doesn't reduce download size.
- Disk cache limits: configure the cache manager once (`CacheManager` with `maxNrOfCacheObjects` and `stalePeriod`) in `core`, and clear it on sign-out when images are user-specific or private.
- `precacheImage` only for the next likely screen's hero image.
- On web the package relies on the browser cache. Check its current platform support on pub.dev before promising the same behavior there.
- Verify on pub.dev that `cached_network_image` is still maintained when starting a project. If it is not, keep the wrapper and swap the implementation inside it.
- Tests: no url shows the fallback; a failing loader shows the failed state, and tapping retry rebuilds with a new key; loading shows the skeleton at the final size; informative images expose a label and decorative ones don't. Use a fake `CacheManager` or an `HttpOverrides` stub so tests make no network calls.

## Reference implementation: state coverage wrapper

One widget makes the four-state rule cheap, so nobody skips it (Riverpod shown; adapt for Bloc with a `BlocBuilder` equivalent):

```dart
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.data,
    this.isEmpty,
    this.onRetry,
    this.empty,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final bool Function(T data)? isEmpty;
  final VoidCallback? onRetry;
  final Widget? empty;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(failure: e, onRetry: onRetry),
        data: (d) => (isEmpty?.call(d) ?? false) ? (empty ?? const EmptyState()) : data(d),
      );
}
```
Keep a version with `skipLoadingOnRefresh` so pull-to-refresh shows old data, not a spinner.

## Screen composition rules

- A screen is a thin composition: scaffold + sections. If `build` exceeds ~60 lines, extract section widgets.
- **Extract widget classes, not `_buildXxx()` methods.** Classes get their own element, can be `const`, rebuild independently, and are testable. (`audit.sh` warns on `Widget _build…`.)
- Screens read state via the state holder and call its methods. They contain no `try/catch`, no parsing, no `if (response.statusCode …)`, no navigation strings.
- Side effects (navigate, show snackbar) are triggered from listeners on one-shot events, never inside `build`.
- Lists use `ListView.builder`/slivers with stable keys. Forms use `AppTextField` plus a form state in the state holder, with validation functions from `core/utils/validators`, returning l10n keys or enums, not English strings.
- Use the theme's `TextTheme` roles (`titleLarge`, `bodyMedium`) through `context.text`. Do not construct `TextStyle(fontSize: …)`.

## Responsive layout

- Breakpoints (Material window size classes): compact < 600, medium 600-839, expanded ≥ 840. Defined once in `AppBreakpoints`.
- Use `LayoutBuilder`/`ResponsiveBuilder` for layout changes, `MediaQuery.sizeOf(context)` for size reads (not `MediaQuery.of`, which rebuilds on every metric change).
- Constrain content width on large screens (`AppScaffold` applies a max width token).
- Navigation adapts: bottom bar (compact) → rail (medium) → drawer or extended rail (expanded).
- Never design for one device size; test at 320 dp wide, 412 dp, 768 dp, 1280 dp, and at 200% text scale.

## Overlays

`showAppDialog` and `showAppBottomSheet` wrap `showDialog`/`showModalBottomSheet` with design-system shape, padding, safe areas, drag handle, scroll-controlled sheets and focus/semantics behavior. Feature code calls the helpers, never `showDialog` directly. Dialog buttons use design-system buttons; destructive confirmations label the action ("Delete order"), not "OK".

## Anti-patterns (reject on sight)

- Same `Container(decoration: BoxDecoration(...))` appearing twice → it is an `AppCard` variant.
- `Text('Submit')`, `Color(0xFF…)`, `SizedBox(height: 12)`, `Icon(Icons.x, size: 24)` in a feature.
- Component with a `bool` flag per visual variation.
- A "common" widget that imports a feature model.
- `Opacity`/`ClipRRect` stacks where a decoration or theme property does the job.
- Disabling a button with no visible reason or hint.
