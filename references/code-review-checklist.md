# Code Review Checklist (the delivery gate)

Read at the end of **every** task. You are the reviewer now, and you are strict with your own work. Do not present results that fail an item; fix first.

## Procedure

1. **Run the machines first** (they are cheaper and more reliable than eyes):
   ```bash
   dart format --set-exit-if-changed .
   flutter analyze --fatal-infos
   flutter test
   scripts/audit.sh
   ```
   If a tool cannot run in this environment, say so explicitly in the report; do not claim it passed.
2. **Walk the checklist below** against the files you changed *and* their immediate neighbors (a new widget may duplicate an old one).
3. **Fix every failure.** Refactor, then re-run step 1. Maximum 3 loops; if something still fails (needs a user decision, external dependency, missing credential), list it under "Open items" with the reason.
4. **Report** per the format at the bottom.

Severity: **Blocker** = must fix before delivery. **Major** = fix unless the user explicitly defers. **Minor** = fix if cheap, otherwise list.

## A. Architecture and separation of concerns (Blocker)

- [ ] Dependency direction respected: presentation → domain ← data; domain is pure Dart
- [ ] No business logic in widgets (no parsing, branching on status codes, price math, validation rules)
- [ ] No HTTP, SQL, Firebase, or storage calls in widgets or state holders
- [ ] Chain intact: UI → state holder → repository → datasource → client
- [ ] Repositories return `Result<T>`; datasources throw typed `AppFailure`; no raw `DioException`/`FirebaseException` above data
- [ ] No cross-feature imports of `data`/`presentation` internals; barrel only
- [ ] Wiring only in `<feature>_providers.dart` / `app/di`; no service locator calls in widgets
- [ ] No pass-through use cases; no unused abstractions; no empty ritual folders
- [ ] Each class has one reason to change
- [ ] Decisions with trade-offs recorded in an ADR if they deviate from defaults

## B. Models and mapping (Blocker)

- [ ] No `Map<String, dynamic>`/`dynamic` outside DTO parsing
- [ ] DTOs stay in `data`; entities are pure and immutable; mappers are pure and tested
- [ ] Unknown enum values and nulls handled; money not `double`; dates are `DateTime`

## C. UI and design system (Blocker/Major)

- [ ] **No duplicate widgets**: searched the repo; every repeated chunk is a component
- [ ] New components live in the right place (`design_system` vs `shared` vs feature) with variants as enums and all states
- [ ] Screen composed from components; `build` short; no `_buildX()` widget helper methods
- [ ] Loading, content, empty, error (and offline) states all rendered
- [ ] Side effects not triggered from `build`

## D. No magic values (Blocker)

- [ ] No literal colors, font sizes, spacing, radii, durations, sizes in features/shared/app
- [ ] Widgets use theme roles (`colorScheme`, `textTheme`, theme extension), not raw `AppColors` palette
- [ ] Asset paths only via `AppAssets`/generated; icons via `AppIcons` or theme
- [ ] Route paths/names only via typed routes or `AppRoutes`; no hardcoded navigation strings
- [ ] API paths, timeouts, storage keys, env values from constants/`Env`
- [ ] Nothing hardcoded that varies by flavor

## E. Localization and theming (Blocker)

- [ ] No hardcoded user-facing strings (labels, hints, tooltips, semantics, errors, notifications)
- [ ] ARB keys added for **every** supported locale with descriptions; placeholders/plurals via ICU
- [ ] Dates/numbers/currency formatted by locale
- [ ] Works in light **and** dark; contrast verified
- [ ] RTL-safe layout (Directional variants) if any RTL locale is supported

## F. Errors, logging, state (Major)

- [ ] Every failure path produces a typed failure and a localized, actionable message
- [ ] No empty `catch`; no swallowed errors; no `print`
- [ ] Retry only where safe; cancel/debounce for search
- [ ] State immutable, sealed or `AsyncValue`; no booleans-soup; no `BuildContext` in state
- [ ] Streams, timers, controllers, subscriptions disposed
- [ ] Rebuild scope minimal (`select`/`BlocSelector`/small `Obx`); `const` used

## G. Performance (Major)

- [ ] Lists use builders with keys; no `shrinkWrap` on big lists
- [ ] Images sized/cached; no heavy work in `build`; heavy parsing off the main isolate
- [ ] Pagination implemented for unbounded lists; caches bounded and cleared on sign-out

## H. Accessibility (Major)

- [ ] Labels on icon-only controls, ≥ 48 dp targets, headings, reading order
- [ ] 200% text scale and no clipped text; reduced motion respected
- [ ] State changes announced

## I. Security (Blocker for sensitive features)

- [ ] No secrets in code/assets/logs; tokens only in secure storage; wiped on sign-out
- [ ] External input validated; no PII to analytics/logs
- [ ] See `security.md` checklist when the feature touches auth, payments, or personal data

## J. Code quality and consistency (Minor/Major)

- [ ] Naming follows `code-standards.md` (files, classes by role, booleans, callbacks)
- [ ] Files ≤ ~300 lines, methods ≤ ~40, no deep nesting
- [ ] Package imports; ordered; no unused imports/code; no commented-out code
- [ ] No duplicated logic (extracted to a function/extension at the right layer)
- [ ] Dartdoc on public core/design_system APIs; comments explain why
- [ ] No new dependency without a reason; versions verified, not invented

## K. Tests (Major)

- [ ] Mappers, repositories, state holders, and new components have tests
- [ ] Tests mirror `lib/` paths; fakes over deep mocks; no sleeps
- [ ] New strings/locales covered by the ARB parity test
- [ ] Bug fixes include a regression test

## Report format (final message)

```
Built: <1-3 lines>
Decisions: <Decision / Why / Trade-off, only the non-obvious ones>
Reused components: <list>   Created: <list>
Verified: format ✓  analyze ✓  tests ✓ (N)  audit ✓   [or: ✗ <what and why>]
Not verified: <e.g. physical iOS device, TalkBack pass, golden on CI platform>
Open items / needs your call: <list or "none">
Translations needing review: <keys + locales, or "none">
```
Never write "all checks passed" unless you ran them. If you did not run something, say that.
