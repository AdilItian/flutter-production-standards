# Testing

Read when: writing tests, creating test folders/helpers, or wiring CI test jobs. Tests are written alongside the code in Step 4, not after.

## Strategy: spend effort where bugs live

| Layer | Test type | Priority | What to assert |
|---|---|---|---|
| `domain` entities / use cases | Unit | High (cheap, pure) | Rules, invariants, edge cases |
| `data` mappers | Unit, table-driven | High | Null/unknown/boundary mapping |
| `data` datasources | Unit with fake adapter + JSON fixtures | High | DTO parsing, error mapping |
| `data` repositories | Unit with fake datasources | High | `Result`, cache policy, offline fallback |
| State holders | Unit | High | State transitions: initial → loading → success/each failure, pagination, cancel, dispose |
| Design-system components | Widget (+ golden) | Medium-High | Variants, states, semantics, text scale, RTL |
| Screens | Widget | Medium | Four states render; key interactions call the state holder; strings localized |
| Router redirects / guards | Unit + widget | Medium | Auth/onboarding gating, deep link params |
| Critical user journeys | Integration (`integration_test`) | Targeted | Login, core purchase/create flow, restore state, deep link |

Test **behavior through public APIs**, not private methods or call counts. Prefer hand-written **fakes** (`FakeProductRepository`) over mock frameworks for repositories and services; they stay valid when interfaces grow and read like documentation. Use `mocktail` for narrow interaction checks (e.g. "analytics event sent once").

## Folder structure (mirrors `lib/` exactly)

```
test/
├── helpers/
│   ├── pump_app.dart              # wraps widget in MaterialApp, theme, l10n, router, ProviderScope
│   ├── fakes/                     # shared fakes (FakeAnalyticsService, FakeSecureStore…)
│   └── builders/                  # test data builders: aProduct({String? id, …})
├── fixtures/                      # captured JSON payloads (real shapes, odd cases)
│   └── products_page_1.json
├── core/
├── design_system/
│   └── components/
│       └── buttons/primary_button_test.dart
├── features/
│   └── products/
│       ├── data/{datasources,mappers,repositories}/
│       ├── domain/
│       └── presentation/{screens,widgets,state}/
└── goldens/                       # golden images (per platform if needed)
integration_test/
├── app_test.dart
└── flows/{login_flow_test.dart, checkout_flow_test.dart}
```
`scripts/new_feature.sh` creates `test/features/<name>/{data,domain,presentation}`.

## Helpers worth having from day one

```dart
// test/helpers/pump_app.dart
extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget child, {List<Override> overrides = const [], Locale locale = const Locale('en'),
      ThemeMode themeMode = ThemeMode.light, double textScale = 1.0, TextDirection? direction}) {
    return pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode: themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: direction ?? Directionality.of(context), child: c!),
        ),
        home: Scaffold(body: child),
      ),
    ));
  }
}
```
Adapt for Bloc (`MultiBlocProvider`/`RepositoryProvider`) or GetX (`Get.testMode`, `GetMaterialApp`).

Test data builders keep tests short and resilient to model changes:
```dart
Product aProduct({String id = 'p1', String name = 'Mug', Money? price}) => Product(id: id, name: name, price: price ?? Money.cents(1200), /* … */);
```

## What a good test file looks like

- `group('<Unit>')` → `group('<method/behavior>')` → `test('<sentence>')` using Arrange / Act / Assert.
- One logical assertion per test; test names state the condition and result.
- No sleeps; use `pump`, `pumpAndSettle` sparingly (never with infinite animations), fake timers / `fakeAsync`.
- No network, no real clocks, no real storage: inject `Clock`, `ConnectivityService`, `SecureStore` fakes.
- Deterministic data: no `DateTime.now()`/random without injection.

## Widget and golden tests

- Components: render every variant × state × (light, dark) × (LTR, RTL) × text scale (1.0, 2.0). Failing overflow throws in tests, which is the point.
- Semantics: `expect(tester.getSemantics(find.byType(PrimaryButton)), matchesSemantics(isButton: true, isEnabled: true, label: …))`; accessibility guidelines: `await expectLater(tester, meetsGuideline(androidTapTargetGuideline)); … iOSTapTargetGuideline; labeledTapTargetGuideline; textContrastGuideline`.
- Goldens: for design-system components and a few key screens only (they are expensive to maintain). Pin fonts (load bundled fonts in tests), render with a fixed size and DPR, run on one CI platform (or use a golden toolkit such as `alchemist`; check maintenance on pub.dev). Review golden diffs in PRs.
- Screens: assert loading/empty/error/content with fake state; assert tapping retry calls the state holder.

## Integration tests

- `integration_test` for a handful of journeys that cross layers with a **fake backend** (local mock server or overridden repositories) so they are stable. Real-backend smoke tests run separately, non-blocking.
- Cover: cold start → login → core flow; deep link while signed out; offline → online recovery if offline support chosen; locale switch.
- Keep them few and fast; they run on emulators in CI (Firebase Test Lab / device farm for release candidates).

## Coverage

Track, don't worship. Targets: domain/data/state ≥ 80-90% lines; design system ≥ 80%; screens as needed; generated and `main_*.dart` excluded. A PR that lowers coverage on logic code explains why. Coverage measures execution, not assertions: review for meaningful `expect`s.

```bash
flutter test --coverage
# exclude generated files via lcov --remove coverage/lcov.info '**/*.g.dart' '**/*.freezed.dart' 'lib/gen/*' 'lib/l10n/generated/*'
```

## CI test job (outline)

1. `flutter pub get` (cached)
2. `dart format --set-exit-if-changed .`
3. `flutter analyze --fatal-infos`
4. `scripts/audit.sh`
5. `flutter test --coverage` (+ upload)
6. Build smoke (`flutter build apk --debug` / `ios --no-codesign`)
7. Integration tests on nightly / release branches
8. Translation parity check (gen-l10n untranslated report)

## Offline, sync and throttling tests (when those features exist)

- Fake `ConnectivityService` and an injected clock; never sleep.
- Repository: a local write succeeds offline, appears in the `watchAll()` stream, and enqueues one outbox op in the same transaction.
- Sync: push-then-pull order; coalescing; transient failure backs off and retries; permanent failure marks `failed` and does not block unrelated records; each conflict policy; stop and resume after a simulated crash mid-sync; sign-out wipes everything.
- Policy: an entity without an override gets `SyncDefaults`; reading stale data triggers a pull.
- `RequestGate`: concurrency cap, GET dedup, host cooldown after a 429, breaker open/half-open/close.
- Forms and feedback: see `forms-and-feedback.md`.

## TDD for bugs

Reproduce the bug with a failing test at the lowest layer that exhibits it, then fix. Keep the test.
