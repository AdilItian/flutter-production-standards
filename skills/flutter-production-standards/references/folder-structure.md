# Folder Structure

Read when: creating any file or folder, deciding where something lives, or promoting code to shared.

## Canonical tree (Tier M)

Trim what the app does not need; never invent new top-level folders without an ADR.

```
my_app/
├── lib/
│   ├── main_development.dart        # flavor entrypoints: set Flavor, call bootstrap()
│   ├── main_staging.dart
│   ├── main_production.dart
│   ├── bootstrap.dart               # init: bindings, env, error hooks, DI scope, runApp
│   │
│   ├── app/                         # the shell. Knows about every feature.
│   │   ├── app.dart                 # MaterialApp.router, theme, l10n, router
│   │   ├── router/
│   │   │   ├── app_router.dart      # composes feature routes, redirect/guards
│   │   │   └── app_paths.dart       # path/name constants for shell-level routes
│   │   └── di/                      # global providers/registrations (services, clients)
│   │
│   ├── core/                        # non-UI infrastructure. Imports no feature.
│   │   ├── config/                  # env.dart, flavor.dart
│   │   ├── constants/               # api_constants.dart, storage_keys.dart, app_limits.dart
│   │   ├── error/                   # app_failure.dart, result.dart, error_mapper.dart
│   │   ├── logging/                 # app_logger.dart
│   │   ├── network/                 # api_client.dart, interceptors/, connectivity
│   │   ├── storage/                 # secure_store.dart, key_value_store.dart, database/
│   │   ├── services/                # analytics_service.dart, crash_service.dart, push_service.dart
│   │   └── utils/                   # extensions/, formatters/, validators/, debouncer.dart
│   │
│   ├── design_system/               # UI primitives. Knows no feature, no business term.
│   │   ├── tokens/                  # app_colors, app_typography, app_spacing, app_radius,
│   │   │                            # app_sizes, app_elevation, app_durations, app_icons, app_assets
│   │   ├── theme/                   # app_theme.dart, light/dark schemes, component_themes/,
│   │   │                            # theme_extensions/, theme_context_x.dart
│   │   └── components/
│   │       ├── buttons/             # primary_button, secondary_button, app_icon_button
│   │       ├── inputs/              # app_text_field, app_dropdown, search_field
│   │       ├── display/             # app_card, profile_avatar, app_badge, app_list_tile
│   │       ├── feedback/            # loading_view, empty_state, error_view, app_snackbar
│   │       ├── navigation/          # app_app_bar, app_bottom_nav
│   │       └── overlays/            # app_dialog, app_bottom_sheet
│   │
│   ├── l10n/
│   │   ├── arb/                     # app_en.arb (template), app_<locale>.arb
│   │   └── l10n_context_x.dart      # context.l10n
│   │
│   ├── shared/                      # feature-agnostic but domain-aware. Rule of two (below).
│   │   ├── entities/                # types used by ≥2 features (Money, Pagination, Address)
│   │   ├── widgets/                 # composed widgets used by ≥2 features (UserTile)
│   │   └── providers/               # cross-feature state (current user, connectivity)
│   │
│   └── features/
│       └── <feature>/               # one folder per business capability, snake_case
│           ├── <feature>.dart       # barrel: the feature's PUBLIC API
│           ├── <feature>_providers.dart   # composition root of the feature
│           ├── data/
│           │   ├── datasources/     # <name>_remote_datasource.dart, <name>_local_datasource.dart
│           │   ├── dtos/            # <name>_dto.dart
│           │   ├── mappers/         # <name>_mapper.dart (extension methods)
│           │   └── repositories/    # <name>_repository_impl.dart
│           ├── domain/
│           │   ├── entities/        # <name>.dart
│           │   ├── repositories/    # <name>_repository.dart (interface)
│           │   └── usecases/        # only when earned (architecture.md)
│           └── presentation/
│               ├── screens/         # <name>_screen.dart (one route target each)
│               ├── widgets/         # feature-private widgets
│               ├── state/           # controllers / notifiers / blocs + state classes
│               └── routes/          # <feature>_routes.dart (feature-owned route declarations)
│
├── assets/
│   ├── images/   ├── icons/   ├── animations/   └── fonts/
├── test/                            # mirrors lib/ exactly (testing.md)
├── integration_test/
├── env/                             # dev.json, staging.json, prod.json (gitignored if secret-bearing)
├── docs/decisions/                  # ADRs
├── scripts/                         # audit.sh, new_feature.sh
├── l10n.yaml
├── analysis_options.yaml
└── pubspec.yaml
```

## Why each top-level folder exists (and where the lines are)

| Folder | Holds | Must not hold | Reason for the boundary |
|---|---|---|---|
| `app` | Shell: router composition, global DI, `MaterialApp` | Business logic, reusable widgets | It is the only place allowed to know all features |
| `core` | Infra with no UI: network, storage, logging, errors, service interfaces | Widgets, feature types | Reusable by any app; testable without Flutter UI |
| `design_system` | Tokens, theme, domain-free components | Business words (`Order`, `Cart`), repositories | Could ship as its own package; a button must not know what a product is |
| `l10n` | ARB + generated localizations | Hand-written user strings | One source of truth for text |
| `shared` | Things ≥2 features use that carry domain meaning | Anything used by only one feature | Prevents `shared` from becoming a junk drawer |
| `features` | One folder per capability | Cross-feature imports of internals | Isolation and deletability |

**Difference between `core`, `design_system`, `shared`:** `core` = no UI. `design_system` = UI without business meaning. `shared` = UI or types *with* business meaning that two or more features use.

## Promotion rule ("rule of two")

- Start code in the feature that needs it.
- On the **second** feature needing it, move it to `shared/` (or `design_system/` if it carries no business meaning) and update both callers in the same change.
- Exception: design-system atoms (buttons, fields, cards, states) are created in `design_system` immediately, because the design analysis already proves reuse.

**Why not share on the first guess:** premature sharing creates abstractions fitted to one use case; the second use shows the real shape.

## Feature internals: rules

- Screens are named `<thing>_screen.dart`; a screen is a route target. Other widgets in `widgets/`.
- One public class per file (private helpers and tightly coupled state classes excepted).
- `domain/usecases/` is absent until a use case earns its place.
- Features with no remote data omit `datasources/dtos` and say so; do not leave empty ritual folders (`.gitkeep` from `new_feature.sh` are removed on cleanup if unused).
- A feature barrel exports: domain entities others need, route classes, and public widgets (rare). Never exports `data/*` or `state/*`.

## Naming of folders and files

| Thing | Convention | Example |
|---|---|---|
| Folders, files | `snake_case` | `order_history/`, `order_summary_card.dart` |
| Feature folder | singular capability or noun group | `auth`, `cart`, `order_history` |
| Test file | source name + `_test` | `product_repository_impl_test.dart` |
| Generated | `.g.dart`, `.freezed.dart`, never edited, never reviewed, excluded from lints | |

Full naming rules: `code-standards.md`.

## Tier L variant

```
repo/
├── apps/my_app/                   # thin shell: main_*.dart, bootstrap, app/
├── packages/
│   ├── core/
│   ├── design_system/
│   ├── shared/
│   └── features/
│       ├── auth/                  # each a package with lib/auth.dart barrel only
│       └── cart/
└── melos.yaml
```
Same layers inside; package `pubspec.yaml` dependencies make rule 5 compiler-enforced (a feature cannot import another it does not declare).
