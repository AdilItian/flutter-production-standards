# Shared Utilities

Read when: you are about to format a date, number, currency or string, generate an id, read the current time, debounce input, add an extension, or write a helper function.

**Rule:** utilities live once, in `core/utils`, are tested, and are used by every feature. A feature never formats a date with its own pattern, never calls `DateTime.now()` directly, and never copies a helper. `audit.sh` flags `DateFormat(` / `NumberFormat(` outside `core/utils` and warns on `DateTime.now()` outside `core`.

## Shape

```
core/utils/
  date_time_formatter.dart      # AppDateFormatter
  number_formatter.dart         # AppNumberFormatter (number, compact, percent, currency, file size)
  string_utils.dart             # StringUtils (pure functions)
  validators.dart               # Validators (see forms-and-feedback.md)
  clock.dart                    # Clock abstraction
  id_generator.dart             # client-side unique ids
  debouncer.dart                # Debouncer, Throttler
  url_utils.dart                # safe URL parsing / building
  extensions/
    context_x.dart              # context.l10n, context.colors, context.text, context.fmt
    iterable_x.dart  string_x.dart  num_x.dart  datetime_x.dart
```
One topic per file. No `utils.dart`, `helpers.dart` or `common.dart` catch-alls.

### Pure versus injected

| Kind | How | Examples |
|---|---|---|
| **Pure** (same input, same output, no I/O) | Static functions in `abstract final class` | `StringUtils`, `Validators`, `UrlUtils` |
| **Locale-dependent** | Instance built with the current locale; reach it through `context.fmt` | `AppDateFormatter`, `AppNumberFormatter` |
| **Impure** (time, randomness, I/O) | Interface plus implementation, injected | `Clock`, `IdGenerator` |

**Why:** impure helpers called as statics make tests slow, flaky and order-dependent. Injecting `Clock` makes "5 minutes ago", token expiry, sync staleness and retry backoff testable with a fake.

## Dates and times

- Store and transmit **UTC**. Convert to local only for display.
- Patterns come from `intl` skeletons with the app locale, never hand-written patterns like `'dd/MM/yyyy'` (wrong order, separators and numerals in other locales).
- Relative times ("5 min ago") need plural-aware ARB strings, so the formatter takes `AppLocalizations`.

```dart
// core/utils/date_time_formatter.dart
class AppDateFormatter {
  const AppDateFormatter(this.locale, this._clock);
  final String locale;           // Localizations.localeOf(context).toLanguageTag()
  final Clock _clock;

  String date(DateTime d) => DateFormat.yMMMd(locale).format(d.toLocal());          // Nov 11, 2026
  String dateShort(DateTime d) => DateFormat.yMd(locale).format(d.toLocal());
  String time(DateTime d) => DateFormat.jm(locale).format(d.toLocal());             // 3:05 PM
  String dateTime(DateTime d) => DateFormat.yMMMd(locale).add_jm().format(d.toLocal());
  String weekday(DateTime d) => DateFormat.EEEE(locale).format(d.toLocal());
  String monthYear(DateTime d) => DateFormat.yMMMM(locale).format(d.toLocal());

  /// "Just now", "5 min ago", "Yesterday", then the date after a week. Strings are ARB keys.
  String relative(DateTime d, AppLocalizations l10n) {
    final diff = _clock.now().difference(d);
    if (diff.inSeconds < 45) return l10n.timeJustNow;
    if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays == 1) return l10n.timeYesterday;
    if (diff.inDays < 7) return l10n.timeDaysAgo(diff.inDays);
    return date(d);
  }

  String duration(Duration d) { // 1:05:09 or 5:09
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${d.inMinutes}:${two(s)}';
  }
}

// core/utils/clock.dart
abstract interface class Clock { DateTime now(); }
class SystemClock implements Clock { const SystemClock(); @override DateTime now() => DateTime.now().toUtc(); }
```
Access: `context.fmt.date(item.createdAt)`, where `fmt` is an extension on `BuildContext` that builds the formatters from the current locale (cache them per locale).

## Numbers, currency, sizes

```dart
class AppNumberFormatter {
  const AppNumberFormatter(this.locale);
  final String locale;
  String number(num n) => NumberFormat.decimalPattern(locale).format(n);
  String compact(num n) => NumberFormat.compact(locale: locale).format(n);                 // 1.2K
  String percent(double ratio) => NumberFormat.percentPattern(locale).format(ratio);
  String currency(Money m) => NumberFormat.simpleCurrency(locale: locale, name: m.currencyCode).format(m.amountMinor / m.minorUnitFactor);
  String fileSize(int bytes) { /* B, KB, MB, GB with one decimal, 1024 base or 1000 per decision */ }
}
```
Money is a type (integer minor units plus currency code), never a bare `double` (`data-models.md`). Decide in the ADR whether Arabic-locale screens show Arabic-Indic or Latin digits, then configure it once here.

## Strings

```dart
abstract final class StringUtils {
  static bool isBlank(String? s) => s == null || s.trim().isEmpty;
  static String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  static String titleCase(String s) => s.split(' ').map(capitalize).join(' ');
  static String truncate(String s, int max, {String ellipsis = '…'}) =>
      s.characters.length <= max ? s : s.characters.take(max).toString() + ellipsis;   // grapheme-safe
  static String initials(String name, {int max = 2}) =>
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(max).map((p) => p.characters.first.toUpperCase()).join();
  static String maskEmail(String e) { /* a***@example.com */ }
  static String maskPhone(String p) { /* ******1234 */ }
  static String slugify(String s) { /* lowercase, strip diacritics, dashes */ }
  static String normalizeForSearch(String s) { /* lowercase, trim, strip diacritics */ }
}
```
Rules: operate on graphemes (`characters`) not code units (emoji and Arabic combining marks); no display-language logic here (plurals and sentences are ARB messages); never build user-visible sentences by concatenation.

## Other shared helpers

- **`IdGenerator`** (`String newId()`): UUID v4/v7 for client-generated ids (offline creation). Inject; fake in tests.
- **`Debouncer` / `Throttler`**: take a `Duration` from `AppDurations`; always `dispose()` (cancel the timer) with the owner.
- **`UrlUtils`**: `tryParseHttps(String?)` returns `Uri?`, rejecting other schemes; `withQuery(...)` builds with `Uri`, not string concatenation.
- **Extensions**: small and obvious (`context.l10n`, `context.colors`, `context.text`, `Iterable.firstWhereOrNull`, `List.separatedBy`). No extension that hides I/O or business rules.
- **Env/Config**: `core/config` (`theming-and-constants.md`), not here.

## Rules

1. Search `core/utils` before writing any helper. Duplicates are a review finding.
2. A new utility needs: a doc comment with an example, a test with edge cases (empty, null, unicode, RTL, large values, DST changes for dates), and a topic file.
3. Feature-specific logic is not a utility. It belongs in the feature (rule of two before promoting).
4. Utilities never import a feature, `design_system` widgets or `presentation`. `context_x.dart` is the one place that touches `BuildContext`.
5. Utilities never throw for ordinary bad input (null, empty, unparsable): return a value or `null`, and document it.

## Testing

Table-driven tests per function. Date tests inject a fixed `Clock` and run across locales (`en`, `ar`, `de`), time zones and the DST boundary. String tests include emoji, combining marks, RTL text and empty strings.
