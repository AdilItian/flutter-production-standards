#!/usr/bin/env bash
# Validate application identifiers on every platform of a Flutter project.
#   check_ids.sh [project_root]                    inspect and validate (exit 1 on errors)
#   check_ids.sh --suggest <org.domain> "<App Name>"   print a portable default id
# Read-only: never edits files. Changing an id of a published app is a breaking change.
set -u

if [ "${1:-}" = "--suggest" ]; then
  org="${2:?usage: --suggest <reverse.domain> \"App Name\"}"
  name=$(printf '%s' "${3:?usage: --suggest <reverse.domain> \"App Name\"}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  [[ "$name" =~ ^[0-9] ]] && name="app$name"
  org=$(printf '%s' "$org" | tr '[:upper:]' '[:lower:]')
  echo "$org.$name"
  exit 0
fi

cd "${1:-.}" || exit 2
[ -f pubspec.yaml ] || { echo "no pubspec.yaml here"; exit 2; }

errors=0
warns=0
err() { echo "[ERROR] $*"; errors=$((errors + 1)); }
warn() { echo "[WARN]  $*"; warns=$((warns + 1)); }

JAVA_KW='abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while'
PLACEHOLDER='^(com|org|io|net)\.(example|company|yourcompany|your|test|sample|myapp|app)(\.|$)|^your\.company|^com\.flutter'

# check_id PLATFORM ID REGEX RULE_TEXT
check_id() {
  local plat="$1" id="$2" re="$3" rule="$4" seg
  case "$id" in *'$'*) echo "  $plat: $id (uses a build variable, not validated)"; return ;; esac
  echo "  $plat: $id"
  [[ "$id" =~ $re ]] || err "$plat id '$id' is invalid. $rule"
  if printf '%s' "$id" | grep -qiE "$PLACEHOLDER"; then
    err "$plat id '$id' is a placeholder or template value. Use a domain you own (reverse-DNS)"
  fi
  if ! [[ "$id" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]]; then
    warn "$plat id '$id' is outside the portable subset (lowercase letters and digits only). Valid, but harder to keep identical across platforms"
  fi
  if [ "$plat" = Android ]; then
    for seg in $(printf '%s' "$id" | tr '.' ' '); do
      for kw in $JAVA_KW; do [ "$seg" = "$kw" ] && err "Android id segment '$seg' is a reserved Java keyword"; done
    done
  fi
}

ANDROID_RE='^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$'
APPLE_RE='^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'
LINUX_RE='^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)+$'

echo "Application identifiers"
pkg=$(sed -n 's/^name:[[:space:]]*//p' pubspec.yaml | head -1 | tr -d '\r')
echo "  Dart package: $pkg"
[[ "$pkg" =~ ^[a-z][a-z0-9_]*$ ]] || err "pubspec name '$pkg' must be lowercase_with_underscores"
case "$pkg" in flutter_app|my_app|app|test|example|flutter_application_1) warn "pubspec name '$pkg' looks like a template default" ;; esac

# --- Android ---
and_id="" ; and_ns=""
gradle=$(ls android/app/build.gradle.kts android/app/build.gradle 2>/dev/null | head -1)
if [ -n "$gradle" ]; then
  and_id=$(grep -hE 'applicationId' "$gradle" | grep -vE '^\s*//' | head -1 | sed -E "s/.*applicationId[[:space:]]*=?[[:space:]]*[\"']([^\"']+)[\"'].*/\1/")
  and_ns=$(grep -hE '^\s*namespace' "$gradle" | head -1 | sed -E "s/.*namespace[[:space:]]*=?[[:space:]]*[\"']([^\"']+)[\"'].*/\1/")
  case "$and_id" in *applicationId*) and_id="" ;; esac # sed found no quoted value
  case "$and_ns" in *namespace*) and_ns="" ;; esac
  if [ -n "$and_id" ]; then
    check_id Android "$and_id" "$ANDROID_RE" "Segments are separated by dots (min 2), start with a letter, and contain only letters, digits and underscores"
  else
    warn "Android applicationId not found in $gradle (set through a variable or flavors?)"
  fi
  [ -n "$and_ns" ] && [ -n "$and_id" ] && [ "$and_ns" != "$and_id" ] && echo "  Android namespace: $and_ns (code package; may differ from applicationId, which is the store identity)"
  grep -qE 'productFlavors' "$gradle" && echo "  Android flavors: $(grep -oE 'applicationIdSuffix[[:space:]]*=?[[:space:]]*[\"'"'"'][^\"'"'"']+' "$gradle" | tr '\n' ' ')"
else
  echo "  Android: not present"
fi

# --- iOS ---
ios_ids=""
if [ -f ios/Runner.xcodeproj/project.pbxproj ]; then
  ios_ids=$(grep -hoE 'PRODUCT_BUNDLE_IDENTIFIER = [^;]+' ios/Runner.xcodeproj/project.pbxproj | sed 's/.*= //' | tr -d '"' | grep -vE 'RunnerTests$' | sort -u)
  for id in $ios_ids; do check_id iOS "$id" "$APPLE_RE" "Only letters, digits, hyphens and dots; at least two segments (underscores are not allowed on Apple platforms)"; done
  [ -z "$ios_ids" ] && warn "iOS bundle identifier not found in project.pbxproj"
else
  echo "  iOS: not present"
fi

# --- macOS ---
mac_id=""
if [ -f macos/Runner/Configs/AppInfo.xcconfig ]; then
  mac_id=$(grep -hE '^PRODUCT_BUNDLE_IDENTIFIER' macos/Runner/Configs/AppInfo.xcconfig | head -1 | sed 's/.*=[[:space:]]*//' | tr -d '\r')
  [ -n "$mac_id" ] && check_id macOS "$mac_id" "$APPLE_RE" "Only letters, digits, hyphens and dots; at least two segments"
fi

# --- Linux ---
lin_id=""
if [ -f linux/CMakeLists.txt ]; then
  lin_id=$(grep -hE 'APPLICATION_ID' linux/CMakeLists.txt | head -1 | sed -E 's/.*APPLICATION_ID[[:space:]]+"([^"]+)".*/\1/')
  [ -n "$lin_id" ] && check_id Linux "$lin_id" "$LINUX_RE" "Reverse-DNS with at least two segments (GApplication id rules)"
fi

[ -d windows ] && echo "  Windows: no store-style id in a default project (set MSIX identity if you publish to the Microsoft Store). Not validated"
[ -d web ] && echo "  Web: no application id (check manifest name and start_url). Not validated"

# --- Cross-platform consistency ---
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
if [ -n "$and_id" ] && [ -n "$ios_ids" ]; then
  found=0
  for id in $ios_ids; do [ "$(lc "$id")" = "$(lc "$and_id")" ] && found=1; done
  [ "$found" = 1 ] || warn "No iOS bundle id equals the Android applicationId '$and_id' (ignoring case). Ids should match, except flavor suffixes and Apple-only extensions"
fi
if [ -n "$and_id" ] && [ -n "$mac_id" ] && [ "$(lc "$mac_id")" != "$(lc "$and_id")" ]; then
  warn "macOS id '$mac_id' differs from Android '$and_id'"
fi

# --- Firebase / services config must match the ids ---
if [ -f android/app/google-services.json ] && [ -n "$and_id" ]; then
  gs=$(grep -oE '"package_name"[[:space:]]*:[[:space:]]*"[^"]+"' android/app/google-services.json | sed -E 's/.*"([^"]+)"$/\1/' | sort -u)
  echo "$gs" | grep -qx "$and_id" || warn "google-services.json package_name(s) [$(echo $gs)] do not include '$and_id'"
fi
if [ -f ios/Runner/GoogleService-Info.plist ] && [ -n "$ios_ids" ]; then
  gb=$(grep -A1 'BUNDLE_ID' ios/Runner/GoogleService-Info.plist | grep '<string>' | sed -E 's/.*<string>(.*)<\/string>.*/\1/' | head -1)
  echo "$ios_ids" | grep -qx "$gb" || warn "GoogleService-Info.plist BUNDLE_ID '$gb' is not among the iOS bundle ids"
fi

echo
echo "ids: $errors error(s), $warns warning(s)"
[ "$errors" -eq 0 ]
