# Data Models and Mapping

Read when: defining any model, parsing JSON, mapping between layers, or tempted to pass a `Map`.

## Decision: two core types and a mapper, not four

You proposed DTO → Entity → Model → Mapper. The mapper is a function, not a data type, and a separate "Model" in addition to Entity usually duplicates fields without adding information. Use:

```
DTO ──mapper──► Entity ──(optional)──► UI model
 data layer      domain layer          presentation layer
```

| Type | Lives in | Purpose | Rules |
|---|---|---|---|
| **DTO** | `data/dtos` | Mirrors the wire/DB format exactly (names, nulls, string dates, nested ids) | JSON-aware (`fromJson`/`toJson`). Never leaves `data`. Tolerant of the backend's quirks. |
| **Entity** | `domain/entities` | Business concept in business terms | Pure Dart, immutable, value equality, non-null where the business says required, real types (`DateTime`, `Money`, enums). No JSON annotations. |
| **UI model** *(only when needed)* | `presentation/state` | Pre-formatted/derived for display (`priceLabel`, `isLowStock`, grouped sections) | Add only when formatting logic is non-trivial or reused; otherwise format at the widget with `context.l10n` and entity getters. |
| **Mapper** | `data/mappers` | Pure functions DTO ↔ Entity | Extension methods, no I/O, unit-tested. |

**Why:** DTOs change when the backend does; entities change when the business does; UI models change when design does. Merging them couples all three. But a fourth type with no distinct reason to change is ceremony.
**Trade-off:** one extra class per concept versus using DTOs everywhere (simplest, but a backend rename then ripples through every widget). For throwaway prototypes only, skipping the Entity is acceptable if recorded.

## Rules

1. **No `Map<String, dynamic>` or `dynamic` outside the datasource's parse step.** Statically enforced by `strict-casts` + `avoid_dynamic_calls` + `audit.sh`.
2. Every JSON shape is parsed once, in a DTO `fromJson`.
3. Entities never import `json_annotation`, `dio`, or Flutter UI.
4. Mapping is explicit and total: every DTO field is either mapped or deliberately ignored (comment why).
5. Unknown enum values from the server must not crash: provide an `unknown` member or a default via `@JsonKey(unknownEnumValue: ...)`.
6. Parse dates into `DateTime` (UTC from the wire; convert to local only for display). Money as integer minor units or a `Money` type, **never `double`**.
7. Nullability reflects reality at each layer: DTO nullable per API contract, Entity non-null per business rule; the mapper decides the default or throws `ParsingFailure` when a required field is missing.
8. Collections in entities are unmodifiable views or treated as immutable.

## Tooling

- Default: `json_serializable` for DTOs, `freezed` for entities/states needing `copyWith`, unions and equality. Alternatives (`dart_mappable`, hand-written records/classes, `equatable`) are fine; match the project.
- For tiny apps, hand-written immutable classes avoid the codegen cost. Dart 3 records/patterns help for small value types.
- Generated files (`*.g.dart`, `*.freezed.dart`) are committed or regenerated in CI per the project's choice; the choice is written in the ADR. Never hand-edit them.

## Example

```dart
// data/dtos/product_dto.dart
@JsonSerializable(fieldRename: FieldRename.snake)
class ProductDto {
  const ProductDto({required this.id, required this.name, required this.priceCents, this.imageUrl, required this.status, required this.createdAt});
  factory ProductDto.fromJson(Map<String, dynamic> json) => _$ProductDtoFromJson(json);

  final String id;
  final String name;
  final int priceCents;
  final String? imageUrl;
  @JsonKey(unknownEnumValue: ProductStatusDto.unknown)
  final ProductStatusDto status;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => _$ProductDtoToJson(this);
}
enum ProductStatusDto { active, discontinued, unknown }

// domain/entities/product.dart
@immutable
class Product {
  const Product({required this.id, required this.name, required this.price, required this.imageUri, required this.isAvailable, required this.createdAt});
  final String id;
  final String name;
  final Money price;
  final Uri? imageUri;
  final bool isAvailable;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) => other is Product && other.id == id && other.name == name && other.price == price &&
      other.imageUri == imageUri && other.isAvailable == isAvailable && other.createdAt == createdAt;
  @override
  int get hashCode => Object.hash(id, name, price, imageUri, isAvailable, createdAt);
}

// data/mappers/product_mapper.dart
extension ProductDtoMapper on ProductDto {
  Product toEntity() => Product(
        id: id,
        name: name,
        price: Money.cents(priceCents),
        imageUri: imageUrl == null ? null : Uri.tryParse(imageUrl!),
        isAvailable: status == ProductStatusDto.active,
        createdAt: createdAt,
      );
}
extension ProductEntityMapper on Product {
  ProductDto toDto() => /* only if the app writes products back */ throw UnimplementedError();
}
```
(In a real project use `freezed` for `Product` to avoid the manual equality; shown by hand so the contract is visible. Do not leave the `toDto` stub: write the mapper you need or omit it.)

## Local DB models

drift/isar/objectbox rows are a second kind of DTO (storage DTO). Map them to entities exactly like network DTOs, in the local datasource/repository. Never let table classes reach the domain.

## Request models

Outgoing payloads follow the same flow in reverse: Entity or a domain "command/params" object → mapper → request DTO → `toJson`. Validation (required fields, ranges) happens in domain/presentation before the call; the server stays authoritative.

## Testing

- Mapper tests: table-driven (null fields, unknown enum, boundary dates, empty strings).
- DTO parsing tests against captured JSON fixtures.
- Entity tests only for real logic (getters, invariants).
