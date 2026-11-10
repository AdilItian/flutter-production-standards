# Localization

Read when: adding any user-visible text, date, number, currency, plural, locale switch, or RTL support.

**Always ask in discovery:** "What languages should this app support? Any right-to-left?" Never ship English-only by default. If the answer is "English only", still use gen-l10n: adding a language later is then a translation task, not a refactor.

## Decision

**Use Flutter's official `gen-l10n` with ARB files**, not a hand-written `AppStrings` class or a third-party string registry.
**Why:** type-safe generated getters; ICU plurals/selects/placeholders; locale-aware date/number formatting; fallback and delegates handled by the framework; translator-friendly ARB format with descriptions; compile-time error for missing keys.
**Trade-off:** a codegen step (`flutter gen-l10n` runs automatically with `flutter pub get`/`run` when `generate: true`).

## Setup

`pubspec.yaml`:
```yaml
dependencies:
  flutter_localizations: { sdk: flutter }
  intl: any   # use the version flutter_localizations pins
flutter:
  generate: true
```

`l10n.yaml`:
```yaml
arb-dir: lib/l10n/arb
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/l10n/generated
nullable-getter: false
synthetic-package: false
untranslated-messages-file: build/l10n_untranslated.json
```
The template locale (default language) is the source of truth; every other ARB must contain the same keys. CI fails if `untranslated-messages-file` is non-empty for a locale marked as complete.

App wiring:
```dart
MaterialApp.router(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: ref.watch(localeControllerProvider), // null => follow device
  routerConfig: router,
);
```

Context extension (so call sites are short and the codebase has one idiom):
```dart
// l10n/l10n_context_x.dart
extension L10nContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```
Usage: `Text(context.l10n.cartEmptyTitle)`.

## ARB conventions

```json
{
  "@@locale": "en",
  "cartEmptyTitle": "Your cart is empty",
  "@cartEmptyTitle": { "description": "Title shown on the cart screen when there are no items." },

  "cartItemCount": "{count, plural, =0{No items} =1{1 item} other{{count} items}}",
  "@cartItemCount": { "placeholders": { "count": { "type": "int" } } },

  "orderPlacedOn": "Placed on {date}",
  "@orderPlacedOn": { "placeholders": { "date": { "type": "DateTime", "format": "yMMMd" } } },

  "errorOffline": "You're offline. Check your connection and try again."
}
```
- **Keys:** `camelCase`, prefixed by feature/area: `authLoginTitle`, `cartEmptyTitle`, `commonRetry`, `errorOffline`. Reusable words go under `common*`.
- **Every key has a `description`** when the context is not obvious (translators cannot see your UI).
- **Never concatenate** translated fragments (`"Hello " + name`). Use placeholders so translators can reorder.
- **Plurals and gender** use ICU `plural`/`select`. Never `count == 1 ? 'item' : 'items'`; many languages have more than two plural forms.
- **Dates, numbers, currency** use placeholders with `format`, or `DateFormat`/`NumberFormat` with `Localizations.localeOf(context)`. Never format with hand-built strings.
- **Error messages:** the domain emits typed failures; presentation maps them to ARB keys (`error-handling.md`). Server-sent messages are not shown to users unless the backend localizes them intentionally.
- **No text in images**; no emoji as the only carrier of meaning.

## Locale behavior

- Default: follow device locale, fall back to the template locale when unsupported.
- If the app offers an in-app language picker: persist the choice (key-value store), expose via a `LocaleController`, store `null` for "system".
- Resolve unsupported regional variants (`pt_BR` vs `pt_PT`) deliberately with `localeResolutionCallback` or supply both ARBs.
- Update the platform declarations: iOS `CFBundleLocalizations` in `Info.plist` and Android `resConfigs`/`localeConfig` so store listings and system per-app language settings show the right languages.
- App name, permission strings (`NSCameraUsageDescription` etc.) and notification channel names are also user-facing; localize them via `InfoPlist.strings` and Android `values-xx/strings.xml`.

## RTL (Arabic, Hebrew, Persian, Urdu)

If any RTL language is supported:
- Layout must be direction-agnostic: `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`, `BorderRadiusDirectional`, `start`/`end` not `left`/`right`. (`audit.sh` warns on physical left/right.)
- Mirror directional icons (back, forward, chevrons, progress); do not mirror logos, media controls, or numbers.
- Check fonts include the script and that line height suits it.
- Test every key screen in RTL with a pseudo-locale or `Directionality(textDirection: TextDirection.rtl)` goldens.

## Workflow when adding text

1. Add the key to the template ARB with description (and placeholders).
2. Add it to every other ARB, using a real translation if you can produce one reliably; otherwise copy the English text and list the key as **needing translation** in the final report. Never leave a locale missing a key.
3. Use `context.l10n.key`.
4. Run codegen (`flutter pub get`), analyzer, `audit.sh`.

## Testing

- Widget tests pump with `AppLocalizations.localizationsDelegates` and assert via `find.text(l10n.key)` (get `l10n` from a pumped context), not literal English.
- A test that loads every ARB and checks key parity and that placeholders match the template.
- Pseudo-localization (long strings, accents) golden to catch overflow.
- Long-language smoke test: German or Finnish at 200% text scale.
