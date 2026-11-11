#!/usr/bin/env bash
# Flutter production-standards audit.
#   Usage:  audit.sh [project_root]        (default: current dir)
#   Env:    MAX_LINES=300                  max lines per hand-written file
# Suppress one line with a trailing comment:  // audit:ignore <reason>
# Exit 1 if any [ERROR] is found. [WARN] never fails the run.
# These are heuristics: a clean run does not replace the review checklist.
# Known limit: only whole-line // comments are skipped; a match in a trailing comment is reported.
set -u
cd "${1:-.}" || exit 2
[ -d lib ] || { echo "no lib/ directory here"; exit 2; }

MAX_LINES="${MAX_LINES:-300}"
errors=0
warns=0
NEVER='a^' # matches nothing

# check LEVEL TITLE REGEX EXCLUDE_REGEX PATH...
check() {
  local level="$1" title="$2" regex="$3" exclude="$4"
  shift 4
  local out
  out=$(grep -rnE --include='*.dart' -e "$regex" "$@" 2>/dev/null |
    grep -vE '\.(g|freezed)\.dart:|^lib/(gen|l10n)/' |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' |
    grep -v 'audit:ignore' |
    grep -vE "${exclude:-$NEVER}")
  if [ -n "$out" ]; then
    echo "[$level] $title"
    echo "$out" | sed 's/^/    /'
    echo
    if [ "$level" = ERROR ]; then
      errors=$((errors + $(echo "$out" | wc -l)))
    else
      warns=$((warns + $(echo "$out" | wc -l)))
    fi
  fi
}

UI='lib/features lib/shared lib/app'
PRES='lib/features/*/presentation lib/shared'

# --- Magic values ---------------------------------------------------------
check ERROR "Hardcoded color. Use Theme/ColorScheme/AppColorsExtension" \
  'Color\(0x|Color\.from(ARGB|RGBO)|Colors\.[a-zA-Z]' 'Colors\.transparent' $UI
check ERROR "Raw numeric spacing/radius. Use AppSpacing/AppRadius" \
  '(EdgeInsets(Directional)?\.[A-Za-z]+|SizedBox(\.[a-z]+)?|(Border)?Radius\.circular)\(([^)]*[ (,:])?[0-9]' '' $UI
check ERROR "Raw fontSize / ad-hoc TextStyle. Use text theme roles" \
  'fontSize:[[:space:]]*[0-9]|TextStyle\(' '' $UI
check ERROR "Raw Duration. Use AppDurations" \
  'Duration\((milliseconds|seconds|minutes):[[:space:]]*[0-9]' '' $UI
check ERROR "Raw asset path. Use AppAssets (or generated assets)" \
  "['\"]assets/" 'app_assets\.dart' lib

check ERROR "Direct network image call. Use AppNetworkImage (cached, skeleton, failure state)" \
  '(Image\.network|(^|[^A-Za-z_])(Cached)?NetworkImage(Provider)?)\(' '^lib/design_system/' lib

# --- Shared building blocks -----------------------------------------------
check ERROR "Raw spinner. Use AppLoader (branded, delayed, accessible)" \
  'CircularProgressIndicator\(' '^lib/design_system/' lib
check ERROR "Raw SnackBar/toast. Use AppToast (black, text only)" \
  'SnackBar\(|showSnackBar\(|Get\.(snackbar|showSnackbar)\(|Fluttertoast|BotToast' '^lib/design_system/' lib
check ERROR "Date/number formatting outside core/utils. Use context.fmt (AppDateFormatter/AppNumberFormatter)" \
  '(DateFormat|NumberFormat)(\.|\()' '^lib/core/utils/' lib
check WARN "DateTime.now() outside core. Inject Clock so time is testable" \
  'DateTime\.now\(\)' '^lib/core/' lib

# --- Localization ---------------------------------------------------------
check ERROR "Hardcoded user-facing string. Use context.l10n" \
  "(Text|SelectableText)\(([[:space:]]*const)?[[:space:]]*['\"]|(labelText|hintText|helperText|errorText|tooltip|semanticLabel|semanticsLabel|title|label):[[:space:]]*(const[[:space:]]+)?(Text\()?['\"]" '' $UI

# --- Routing --------------------------------------------------------------
check ERROR "Hardcoded route string. Use AppRoutes via AppNavigation" \
  "(context\.(go|push|pushReplacement|replace)|Navigator\.(of\(context\)\.)?(pushNamed|pushReplacementNamed|popAndPushNamed)|Get\.(to|toNamed|off|offNamed|offAllNamed|offNamedUntil))(<[A-Za-z?<>, ]*>)?\(([[:space:]]*)['\"]" '' lib
check ERROR "Navigation call outside AppNavigation. Add a helper to app_navigation.dart" \
  'Get\.(toNamed|offNamed|offAllNamed|offNamedUntil)(<[A-Za-z?<>, ]*>)?\(' '^lib/app/routes/' lib

# --- Layering -------------------------------------------------------------
check ERROR "HTTP/DB package imported in presentation or domain" \
  "import 'package:(dio|http|retrofit|drift|sqflite|cloud_firestore|firebase_[a-z_]+)/" '' \
  lib/features/*/presentation lib/features/*/domain lib/shared
check ERROR "Presentation imports a data layer file" \
  "import '[^']*/data/" '' lib/features/*/presentation lib/shared
check ERROR "Domain imports Flutter UI, data, or presentation" \
  "import 'package:flutter/(material|widgets|cupertino|services|rendering)\.dart'|import '[^']*/(data|presentation)/" '' \
  lib/features/*/domain
check ERROR "Service locator / repository resolved inside a widget" \
  "Get\.find|GetIt\.(I|instance)|ref\.(read|watch)\([a-zA-Z]*([Rr]epository|[Dd]ata[Ss]ource|[Aa]pi[Cc]lient)[A-Za-z]*Provider" '' \
  lib/features/*/presentation/screens lib/features/*/presentation/widgets lib/shared
check ERROR "Map<String, dynamic> outside data layer" \
  'Map<String,[[:space:]]*dynamic>' '' lib/features/*/presentation lib/features/*/domain lib/shared
# Cross-feature internals: importing file's feature (path segment 3) must equal the imported feature
cross=$(grep -rnE --include='*.dart' "import '[^']*/features/[a-z_]+/(data|domain|presentation)/" lib/features 2>/dev/null |
  grep -vE '\.(g|freezed)\.dart:' | grep -v 'audit:ignore' |
  awk -F: '{ split($1, p, "/"); line = $0; sub(/^[^:]*:[0-9]+:/, "", line);
             if (match(line, /features\/[a-z_]+\//)) { imp = substr(line, RSTART + 9, RLENGTH - 10); if (imp != p[3]) print } }')
if [ -n "$cross" ]; then
  echo "[ERROR] Feature imports another feature's internals. Import its barrel instead"
  echo "$cross" | sed 's/^/    /'
  echo
  errors=$((errors + $(echo "$cross" | wc -l)))
fi

# --- Hygiene --------------------------------------------------------------
check ERROR "print/debugPrint. Use the Logger abstraction" \
  '(^|[^A-Za-z_.])(print|debugPrint)\(' 'lib/core/logging' lib
check WARN "Physical left/right (breaks RTL). Use Directional variants" \
  'EdgeInsets\.(only|fromLTRB)\(([^)]*)(left|right)|Alignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)|Positioned\(([^)]*)(left|right):' '' $UI
check WARN "Widget-returning helper method. Extract a widget class" \
  '^[[:space:]]+Widget _build[A-Za-z]*\(' '' $UI

# --- File size ------------------------------------------------------------
big=$(find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -path 'lib/gen/*' ! -path 'lib/l10n/*' \
  -exec wc -l {} + | grep -v ' total$' | awk -v m="$MAX_LINES" '$1 > m {print $1 " lines  " $2}')
if [ -n "$big" ]; then
  echo "[WARN] Files over $MAX_LINES lines. Split by responsibility"
  echo "$big" | sed 's/^/    /'
  echo
  warns=$((warns + $(echo "$big" | wc -l)))
fi

echo "audit: $errors error(s), $warns warning(s)"
[ "$errors" -eq 0 ]
