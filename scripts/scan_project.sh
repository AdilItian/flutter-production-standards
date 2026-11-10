#!/usr/bin/env bash
# Collect objective facts about an existing Flutter project as Markdown on stdout.
#   scan_project.sh [project_root] > facts.md
# Read-only. The AI interprets these facts into the gap report; this script judges nothing.
set -u
cd "${1:-.}" || exit 2
[ -f pubspec.yaml ] || { echo "no pubspec.yaml here"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"

count() { grep -rE --include='*.dart' -e "$1" "${2:-lib}" 2>/dev/null | grep -vE '\.(g|freezed)\.dart:' | wc -l | tr -d ' '; }
dep() { grep -qE "^[[:space:]]+$1:" pubspec.yaml && echo "yes" || echo "no"; }

echo "# Project facts"
echo
echo "## Toolchain"
fv=$(flutter --version 2>/dev/null | head -1)
echo "- Flutter: ${fv:-flutter not available in this environment}"
echo "- SDK constraint: $(grep -E '^[[:space:]]+sdk:' pubspec.yaml | head -1 | sed 's/^ *//')"
echo "- Dart package: $(sed -n 's/^name:[[:space:]]*//p' pubspec.yaml | head -1)"
echo "- Platforms present: $(for p in android ios web macos linux windows; do [ -d $p ] && printf '%s ' $p; done)"
echo
echo "## Stack detected from pubspec.yaml"
echo "| Concern | Package | Present |"
echo "|---|---|---|"
for p in flutter_riverpod riverpod_annotation flutter_bloc bloc get provider mobx; do echo "| state | $p | $(dep $p) |"; done
for p in go_router auto_route beamer; do echo "| routing | $p | $(dep $p) |"; done
for p in dio http retrofit chopper graphql_flutter; do echo "| network | $p | $(dep $p) |"; done
for p in freezed json_serializable equatable dart_mappable; do echo "| models | $p | $(dep $p) |"; done
for p in drift sqflite isar hive objectbox shared_preferences flutter_secure_storage; do echo "| storage | $p | $(dep $p) |"; done
for p in get_it injectable; do echo "| di | $p | $(dep $p) |"; done
for p in firebase_core firebase_crashlytics sentry_flutter firebase_analytics; do echo "| services | $p | $(dep $p) |"; done
for p in flutter_localizations intl easy_localization; do echo "| l10n | $p | $(dep $p) |"; done
for p in mocktail mockito bloc_test integration_test golden_toolkit alchemist; do echo "| testing | $p | $(dep $p) |"; done
echo
echo "## Structure"
echo "- Top-level folders in lib/: $(ls -d lib/*/ 2>/dev/null | sed 's#lib/##; s#/##' | tr '\n' ' ')"
echo "- Dart files in lib/: $(find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' | wc -l | tr -d ' ')"
echo "- features/ folder: $([ -d lib/features ] && echo yes || echo no); core/: $([ -d lib/core ] && echo yes || echo no); design_system|theme: $([ -d lib/design_system ] || [ -d lib/theme ] && echo yes || echo no)"
echo "- Five largest files:"
find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + | grep -v ' total$' | sort -rn | head -5 | sed 's/^ */    /'
echo
echo "## Code signals (counts in lib/)"
echo "- setState calls: $(count 'setState\(')"
echo "- ThemeData usages: $(count 'ThemeData\('); darkTheme set: $(count 'darkTheme:')"
echo "- Semantics widgets / tooltips: $(count 'Semantics\(') / $(count 'tooltip:')"
echo "- ListView( without builder: $(count 'ListView\(') ; shrinkWrap: true: $(count 'shrinkWrap:[[:space:]]*true')"
echo "- Navigator.push* calls: $(count 'Navigator\.(of\(context\)\.)?push'); context.go/push: $(count 'context\.(go|push)\(')"
echo "- http:// URLs: $(count "['\"]http://")"
echo "- print( calls: $(count '(^|[^A-Za-z_.])print\(')"
echo "- Possible hardcoded secrets: $(count "([Aa][Pp][Ii][_-]?[Kk]ey|[Ss]ecret|[Tt]oken|[Pp]assword)[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9_./+-]{16,}['\"]")"
echo
echo "## Localization"
if [ -f l10n.yaml ]; then echo "- l10n.yaml: present"; else echo "- l10n.yaml: absent"; fi
echo "- ARB files: $(find . -name '*.arb' -not -path './build/*' 2>/dev/null | tr '\n' ' ')"
echo
echo "## Tests and CI"
echo "- Test files in test/: $(find test -name '*_test.dart' 2>/dev/null | wc -l | tr -d ' '); integration_test/: $([ -d integration_test ] && echo yes || echo no)"
echo "- CI config: $(ls .github/workflows/*.y*ml .gitlab-ci.yml codemagic.yaml bitrise.yml fastlane/Fastfile 2>/dev/null | tr '\n' ' ')"
echo "- Flavor entrypoints: $(ls lib/main_*.dart 2>/dev/null | tr '\n' ' ')"
echo "- analysis_options.yaml: $(grep -E '^include:' analysis_options.yaml 2>/dev/null || echo 'absent or no include')"
echo "- .env or secrets as Flutter assets: $(grep -E '^[[:space:]]+-[[:space:]]+\.env|assets/.*env' pubspec.yaml | tr '\n' ' ')"
echo
echo "## Platform security settings"
echo "- Android usesCleartextTraffic: $(grep -rhoE 'usesCleartextTraffic="[a-z]+"' android/app/src 2>/dev/null | sort -u | tr '\n' ' ')"
echo "- Android allowBackup: $(grep -rhoE 'allowBackup="[a-z]+"' android/app/src 2>/dev/null | sort -u | tr '\n' ' ')"
echo "- iOS NSAllowsArbitraryLoads: $(grep -A1 'NSAllowsArbitraryLoads' ios/Runner/Info.plist 2>/dev/null | grep -oE '<(true|false)/>' | tr '\n' ' ')"
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "- Tracked sensitive files: $(git ls-files | grep -E '\.(jks|keystore|p12|p8|mobileprovision)$|key\.properties$|(^|/)\.env($|\.)|google-services\.json$|GoogleService-Info\.plist$' | tr '\n' ' ')"
fi
echo
echo "## Application identifiers (check_ids.sh)"
echo '```'
"$HERE/check_ids.sh" . 2>&1
echo '```'
echo
echo "## Rule audit (audit.sh, first 80 lines)"
echo '```'
"$HERE/audit.sh" . 2>&1 | head -80
echo '```'
