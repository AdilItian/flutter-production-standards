# Accessibility

Read when: building **any** screen or component (always), and when reviewing. Target comes from discovery (default WCAG 2.2 AA). Accessible-by-construction components make most of this free for feature code.

## Screen readers (TalkBack, VoiceOver)

- Use standard widgets (they ship correct semantics). Custom tappables: `Semantics(button: true, label: …, onTap: …)` or build on `InkWell` + `Semantics`.
- Every icon-only control has a label: `IconButton(tooltip: context.l10n.commonClose, …)` (tooltip doubles as semantics label). Labels come from l10n, never hardcoded.
- Decorative images/icons: `excludeFromSemantics: true` / `ExcludeSemantics`. Informative images: `semanticLabel`.
- Group related info into one focusable unit: `MergeSemantics` (e.g. product tile: "Mug, 12 dollars, in stock").
- State must be announced: `selected`, `checked`, `toggled`, `enabled`, `expanded`, `liveRegion` for dynamic changes (errors, loading finished, toasts). `SemanticsService.announce(…)` for events with no widget.
- Headings: `Semantics(header: true)` so users can navigate by heading.
- Reading order follows visual order; use `SemanticsSortKey`/`OrdinalSortKey` only when the layout order differs.
- Modals trap focus and announce themselves; closing returns focus to the trigger.
- Loading: announce start/finish; don't leave an unlabeled spinner.
- Custom painters/charts need a textual alternative (summary label or data table).
- Don't rely on color, shape, or position alone to convey meaning (error = icon + text + color).

## Touch targets and input

- Minimum 48×48 dp (Material), 44×44 pt (iOS HIG): `AppSizes.minTapTarget`. Small visuals get padding (`InkResponse`, `IconButton` default constraints), not smaller hit areas.
- Spacing between adjacent targets ≥ 8 dp.
- Support keyboard/switch/d-pad navigation: logical `FocusTraversalGroup`, visible focus indicators (don't disable theme focus highlights), `Shortcuts/Actions` for desktop/web, Enter/Space activation.
- Forms: `autofillHints`, `keyboardType`, `textInputAction`, visible labels (not placeholder-only), errors tied to the field, clear on-screen instructions.
- Gestures need an alternative: swipe-to-delete also has a button/menu action. Avoid time limits; if unavoidable, allow extension.
- Do not rely on hover or long-press as the only path.

## Text and scaling

- Never disable or clamp system text scaling below 200% unless the design provably breaks, and then clamp to a documented max (e.g. `TextScaler.clamp(maxScaleFactor: 2.0)`), never to 1.0.
- Layouts must survive 200% scale: no fixed heights on text containers (use `ConstrainedBox(minHeight)`), `Flexible`/`Expanded` text, wrap/ellipsis with a way to read the full text, scrollable screens.
- Use theme text roles (relative sizes); don't hardcode `fontSize`.
- Minimum body size ≈ 14 sp; line height ≥ 1.4 for paragraphs.
- Support bold-text and high-contrast OS settings (`MediaQuery.boldTextOf`, `highContrastOf`) where feasible.
- Test German/Finnish-length strings and Arabic/Hebrew (RTL).

## Color and contrast

- Text: 4.5:1 (3:1 for large text ≥ 18.66 px bold / 24 px regular). UI components and meaningful graphics: 3:1 against adjacent colors. Verify in **both** light and dark themes (`textContrastGuideline` in widget tests, or a contrast checker for tokens in the design analysis).
- Don't communicate by color alone; add icon/text/pattern.
- Respect `MediaQuery.platformBrightness` via `ThemeMode.system`.

## Motion

- Honor reduce-motion: `MediaQuery.disableAnimationsOf(context)` → shorten or skip non-essential animation, no parallax/auto-play carousels by default.
- No flashing > 3 times/second.
- Auto-updating content can be paused.

## Responsive and adaptive layout

- Layouts respond to width classes (compact < 600, medium 600-839, expanded ≥ 840), orientation, foldables (`DisplayFeature`), and window resizing on desktop/web/iPad/Android large screens.
- Respect safe areas, system insets, keyboard (`resizeToAvoidBottomInset`, scrollable forms, `MediaQuery.viewInsets`).
- Support landscape unless the product forbids it; don't lock orientation as a shortcut.
- Content max width on large screens for readable line length (~60-80 chars).
- Navigation adapts (bar → rail → drawer).

## Internationalization overlap

RTL mirroring, locale-aware numbers/dates, and localized semantics labels are accessibility, too. See `localization.md`.

## Testing accessibility

```dart
testWidgets('PrimaryButton meets a11y guidelines', (tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpApp(PrimaryButton(label: 'Pay', onPressed: () {}));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
});
```
Plus manual passes before release: TalkBack and VoiceOver on the main flows, 200% font size, bold text, dark mode, RTL, keyboard-only (web/desktop), and one reduced-motion run. Automated checks catch roughly the mechanical half; the manual pass catches confusing flows.

## Done criteria for any screen

- [ ] All interactive elements labeled and ≥ 48 dp
- [ ] Reading order sensible; headings marked
- [ ] Works at 200% text and in RTL without overflow or clipped text
- [ ] Contrast verified in both themes
- [ ] State changes announced; no color-only meaning
- [ ] Reduced motion respected
