#!/usr/bin/env bash
# Create the standard feature skeleton.   Usage: new_feature.sh <snake_case_name> [project_root]
# Use cases/ is intentionally not created: add it only when a use case holds real logic.
set -euo pipefail
name="${1:?usage: new_feature.sh <snake_case_name> [project_root]}"
cd "${2:-.}"
[[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "feature name must be snake_case"; exit 2; }
[ -d lib ] || { echo "run from a Flutter project root (no lib/)"; exit 2; }

base="lib/features/$name"
[ -e "$base" ] && { echo "$base already exists"; exit 1; }

for d in data/datasources data/dtos data/mappers data/repositories \
         domain/entities domain/repositories \
         presentation/screens presentation/widgets presentation/state; do
  mkdir -p "$base/$d"
  touch "$base/$d/.gitkeep"
done
mkdir -p "test/features/$name"/{data,domain,presentation}

# Public API barrel: other features may import ONLY this file.
cat > "$base/$name.dart" <<EOF
// Public API of the $name feature. Export only what other features may use.
EOF

# Composition root for the feature: wires data implementations to domain interfaces.
cat > "${base}/${name}_providers.dart" <<EOF
// Dependency wiring for the $name feature (datasource -> repository).
// Presentation imports repository *interfaces* from domain and providers from here.
EOF

echo "created $base"
