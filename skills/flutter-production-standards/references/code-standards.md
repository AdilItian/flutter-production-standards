# Code Standards

Read when: naming anything, deciding whether to split a file, configuring lints, or reviewing style.

Limits below are guardrails that trigger a *look*, not laws. Exceeding one requires a reason you can state in a sentence; `scripts/audit.sh` warns on file size.

## Naming

| Thing | Convention | Good | Bad |
|---|---|---|---|
| Files, folders, packages | `snake_case` | `order_summary_card.dart` | `OrderSummaryCard.dart` |
| Types (class, enum, typedef, extension) | `UpperCamelCase` | `OrderSummaryCard` | `orderSummaryCard` |
| Members, variables, params | `lowerCamelCase` | `totalPrice` | `total_price` |
| Constants | `lowerCamelCase` (Dart style), grouped in `abstract final class` | `AppSpacing.md` | `SPACING_MD` |
| Private | leading `_` | `_load()` | |
| Booleans | question form | `isLoading`, `hasMore`, `canSubmit` | `loading`, `flag` |
| Callbacks | `onX` (param), `handleX`/verb (impl) | `onPressed`, `submit()` | |
| Streams | noun, plural when many | `orderUpdates` | |
| Futures | verb phrase | `fetchOrders()`, `loadProfile()` | |

### Class naming by role

| Role | Pattern | Example |
|---|---|---|
| Screen (route target) | `<Thing>Screen` | `ProductDetailScreen` |
| Feature widget | `<Thing>` + kind, no "Widget" suffix | `ProductPriceTag`, `OrderTimeline` |
| Design-system component | role-based, prefixed `App` only when it would clash with Flutter | `PrimaryButton`, `AppTextField`, `AppCard`, `EmptyState` |
| State holder | Riverpod `<Thing>Controller`; Bloc `<Thing>Bloc`/`Cubit`; GetX `<Thing>Controller` | `CartController`, `AuthBloc` |
| State classes | `<Thing>State` (sealed subtypes `<Thing>Loaded`...) | `ProductListState` |
| Events (Bloc) | `<Thing><PastTenseVerb>` | `ProductsRequested` |
| Repository interface | `<Thing>Repository` | `AuthRepository` |
| Repository impl | `<Thing>RepositoryImpl` | `AuthRepositoryImpl` |
| Datasource | `<Thing>RemoteDataSource` / `LocalDataSource` | `ProductRemoteDataSource` |
| DTO | `<Thing>Dto` | `ProductDto` |
| Entity | plain noun | `Product` |
| Mapper | extension `<Thing>DtoMapper` | `ProductDtoMapper` |
| Use case | verb phrase + `UseCase` | `PlaceOrderUseCase` |
| Failure | `<Reason>Failure` | `OfflineFailure` |
| Routes | `<Thing>Route` (typed) | `ProductDetailRoute` |
| Token holders | `App<Kind>` | `AppColors`, `AppSpacing` |
| Services (interfaces) | `<Thing>Service` | `AnalyticsService` |
| Tests | `<unit>_test.dart`, group by class, test names read as sentences | `'returns Err(OfflineFailure) when the device is offline'` |

Names say what a thing *is* or *does* in business terms. No `Manager`, `Helper`, `Util`, `Common`, `Data`, `Info` dumping grounds; no abbreviations other than universally known (`id`, `url`, `dto`, `ui`).

## Size and complexity guardrails

| Unit | Guardrail | Action when exceeded |
|---|---|---|
| File | ≤ 300 lines (hand-written) | Split by responsibility; generated files exempt |
| Widget `build` | ≤ ~60 lines | Extract widget classes |
| Method | ≤ ~40 lines, one level of abstraction | Extract named private methods |
| Parameters | ≤ 6 | Group into a value object or params class |
| Nesting | ≤ 3 levels of `if/for` | Early returns, guard clauses, extract |
| Class | single reason to change | Split |
| Widget tree depth in one method | ≤ ~5 levels of nested constructors | Extract subtrees |

Cyclomatic complexity > ~10 in a method is a refactor candidate.

## Imports

- `always_use_package_imports`: no relative imports (they hide cross-layer reaching, e.g. `../../../data/…`).
- Order: `dart:` → `package:flutter` → third-party packages → own package, alphabetized (`directives_ordering`).
- Cross-feature imports only through the barrel (`architecture.md` rule 5).
- No `import '…' show`/`hide` gymnastics to dodge name clashes; rename the app class instead.

## Dart style

- Prefer `final`; `const` wherever possible; `late` only with a justification (DI fields set once).
- Null safety honestly: avoid `!` except right after a proven check; prefer pattern matching and `??`.
- Use Dart 3: sealed classes, `switch` expressions, records for lightweight tuples, `abstract interface class` for interfaces, `abstract final class` for constants holders.
- No `dynamic`. No `as` casts to paper over types (parse instead).
- Async: `await` or `unawaited(...)` explicitly (`unawaited_futures`); never fire-and-forget silently. Don't mark a method `async` if it never awaits.
- Collections: collection `if`/`for`, spread; avoid `.toList()` chains in `build`.
- Equality: value equality on state and entities.
- Comments explain *why*. Dartdoc (`///`) on public API of `core`, `design_system` and anything non-obvious. Delete commented-out code. `TODO(name): …` must reference an issue.
- Format with `dart format` (80 cols default, or project-configured); trailing commas on multi-line argument lists so the formatter lays out widget trees.

## Widgets

- `StatelessWidget` by default. `StatefulWidget` only for controllers/animations/focus.
- `super.key` on every widget. `const` constructors always when possible.
- Don't pass `BuildContext` into non-widget classes. Don't store it.
- No widget helper methods returning widgets (see `ui-guidelines.md`).
- Public widget parameters documented when non-obvious.

## Lint and static analysis

- `templates/analysis_options.yaml` (strict-casts/inference/raw-types, `very_good_analysis` base).
- Treat analyzer warnings as errors in CI (`flutter analyze --fatal-infos` or `--fatal-warnings`, per project).
- Suppress a lint only inline with a reason: `// ignore: rule, <reason>`. No file-level blanket ignores.
- Optional: `custom_lint`/`dart_code_linter` for import restrictions and unused code; check pub.dev for current maintenance before adopting.

## Git hygiene

- Conventional commits (`feat(cart): …`, `fix(auth): …`). One concern per commit.
- PRs small enough to review (< ~400 changed lines excluding generated).
- CI gates: format check, analyze, tests, `scripts/audit.sh`, build.
- Never commit secrets, `.env` with real values, keystores, `google-services.json` of prod where policy forbids.

## Dependencies

- Prefer the SDK and first-party (`flutter.dev`, `dart.dev`) packages. Add a dependency only when it removes real work and is maintained (recent releases, open-issue health, platform support, license).
- Check current versions and compatibility on pub.dev; never guess versions. Pin via caret ranges, commit `pubspec.lock` for apps.
- One package per concern (one HTTP client, one state solution, one router). Record deviations in an ADR.
- Wrap third-party SDKs behind your own interface when they are vendor-specific (analytics, crash, push).
