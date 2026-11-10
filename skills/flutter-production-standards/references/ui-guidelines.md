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
