# Architecture

Read when: choosing a tier, deciding whether a feature needs a domain layer or use cases, wiring dependencies, or justifying a structure to the user.

## The model: feature-first, three layers per feature

```
                 ┌───────────────────────────────┐
                 │         presentation          │  screens, widgets, state holders
                 └───────────────┬───────────────┘
                                 │ depends on
                 ┌───────────────▼───────────────┐
                 │            domain             │  entities, repository interfaces,
                 │       (pure Dart, no I/O)     │  use cases (only when earned)
                 └───────────────▲───────────────┘
                                 │ implements
                 ┌───────────────┴───────────────┐
                 │             data              │  DTOs, mappers, datasources,
                 └───────────────────────────────┘  repository implementations
```

**Decision:** organize by feature first, layer second (`features/cart/{data,domain,presentation}`), not layer first (`data/`, `domain/`, `presentation/` at the root).
**Why:** a feature change touches one folder; features can be deleted or extracted into packages whole; teams own features without merge conflicts; the dependency rules are checkable per folder.
**Trade-off:** shared code needs an explicit home (`core`, `design_system`, `shared`) and a promotion rule (folder-structure.md).

### Dependency rules (enforced by `scripts/audit.sh` and lints)

1. `presentation` imports `domain` and `design_system`/`core`. Never `data`.
2. `domain` imports only Dart core and `core/error` types. No Flutter UI, no packages that do I/O.
3. `data` imports `domain` and `core`. Never `presentation`.
4. `core` and `design_system` import no feature. `shared` imports no single feature.
5. A feature imports another feature **only through its barrel file** (`features/auth/auth.dart`), and only for domain types (e.g. `CurrentUser`) or routes. Never its `data` or `presentation` internals.
6. Wiring (datasource → repository) lives in `<feature>/<feature>_providers.dart` at the feature root, or in `app/di` for global services. That file is the only place allowed to see both `data` and `domain`.

**Why layers point inward:** the stable thing (business rules) must not depend on the volatile things (HTTP client, JSON shape, widget library). Swapping REST for GraphQL, or Dio for `http`, should touch only `data`.

## Choose a tier (decide in discovery, record in the ADR)

| | Tier S: small | **Tier M: default** | Tier L: multi-team |
|---|---|---|---|
| Fits | Solo, prototype, <10 screens, short life | 2-6 devs, 10-50 screens, long life | Multiple teams, 50+ screens, white-label |
| Layout | single package, feature folders | single package, feature folders | Melos/pub-workspace monorepo: `core`, `design_system`, one package per feature or feature group, thin `app` |
| Domain layer | entities + repo interface only where >1 data source or real rules; otherwise repository class directly | entities + repo interfaces always; use cases when earned | same, plus feature packages expose only barrels |
| Boundaries enforced by | audit script + lints | audit script + lints + code review | package dependencies (compiler-enforced) |

**Why not always Tier L:** a monorepo costs real friction (versioning, CI, tooling) that a 3-person team never recoups. **Why not always Tier S:** "temporary" prototypes become products; Tier S still uses the same folders so growing to M is a rename, not a rewrite.

## Domain layer: what is mandatory and what must earn its place

**Always (Tier M):**
- **Entities**: immutable, pure Dart, no JSON. The language of the business.
- **Repository interfaces**: `abstract interface class ProductRepository`. Cheap, and they give you test fakes and a clean seam.

**Use cases only when at least one is true:**
- the operation coordinates two or more repositories;
- it contains a business rule (pricing, validation, eligibility, ordering);
- it is reused by two or more state holders.

**Anti-pattern:** `GetProductsUseCase` that just calls `repository.getProducts()`. It adds a file, a test, a provider, and zero behavior. State holders may call repositories directly when there is no logic to put in between.
**Trade-off:** this deviates from textbook Clean Architecture. The upside is roughly a third fewer files per simple feature with no loss of testability, because the repository interface is already the seam.

## Data flow (one direction, one type per layer)

```
UI event ──► State holder ──► (Use case) ──► Repository (interface in domain)
                                                    │ implemented in data
                                                    ▼
                                               Datasource ──► ApiClient / DB
                                                    │
                                 DTO ◄──────────────┘  raw JSON parsed here only
                                  │ mapper
                                  ▼
                               Entity ──► Result<Entity> ──► state ──► widget
```

- Datasources return/accept **DTOs**. Repositories map DTO ↔ Entity and wrap in `Result`.
- State holders expose immutable state built from entities. See `data-models.md`.

## Dependency injection

| State management | DI | Rule |
|---|---|---|
| Riverpod | Providers are the DI container. | Providers wire everything. Never also add `get_it`. |
| Bloc | `get_it` (+ `injectable` optional) or `RepositoryProvider`. | Register in one `app/di/` module. Blocs receive dependencies via constructor. |
| GetX | `Bindings`. | Bindings per route. Widgets never call `Get.find` for repositories. |

**Universal rules:** constructor injection; no static singletons for anything with state or I/O; a service locator is only ever called from the composition root, never from widgets, domain, or repositories; every external dependency (clock, connectivity, analytics, storage) sits behind an interface so tests can fake it.

## Cross-cutting services

Analytics, crash reporting, push, logging, connectivity, secure storage: define an **interface in `core/services`**, one implementation per vendor. Feature code depends on `AnalyticsService`, not `FirebaseAnalytics`.
**Why:** vendor swap or removal touches one file; tests need no Firebase; privacy gating (consent) has one choke point.

## Concurrency and lifecycle

- Long-lived streams are owned by state holders and cancelled in dispose/`ref.onDispose`/`close`.
- Heavy parsing (> ~50 KB JSON, image processing, crypto) runs with `Isolate.run`. See `performance.md`.
- Never use `BuildContext` after an `await` without a `mounted` check; better, keep context out of state holders and emit one-shot UI events instead.

## Recording decisions

Every non-default choice gets an ADR in `docs/decisions/` (`templates/adr-template.md`). Short is fine. The goal is that the next engineer (or AI session) can see *why* without archaeology.
