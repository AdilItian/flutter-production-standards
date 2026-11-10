---
name: flutter-new-feature
description: Slash command. Add a new feature slice (domain, data, state, presentation, route, strings, tests) to a Flutter project following flutter-production-standards.
argument-hint: "<feature_name> [short description]"
disable-model-invocation: true
---

# /flutter-new-feature

Standards folder: `${CLAUDE_SKILL_DIR}/../flutter-production-standards`
If that folder does not exist, stop and tell the user to install it: `npx skills add AdilItian/flutter-production-standards` (select all skills).

Feature request: `$ARGUMENTS`
If it shows the literal text `$ARGUMENTS`, or has no feature name, ask for a snake_case name and a one-line purpose.

Do this:
1. Require a `pubspec.yaml`. If none, suggest `/flutter-new-app`.
2. Read the standards `SKILL.md` and `docs/decisions/` (state management, backend, offline and locale choices are already decided there; do not re-ask them). If `docs/skill-audit/` has no report, mention `/flutter-baseline` in one line and continue.
3. Create the skeleton: `bash <standards>/scripts/new_feature.sh <feature_name> .` (or the project's `scripts/new_feature.sh` if it exists).
4. Build the slice per **Step 4**: domain, data, state (only if the "Do I need a controller?" order says so), presentation, feature-owned route, ARB strings in every locale, tests.
5. Reuse design-system components; create missing ones first (`references/ui-guidelines.md`).
6. Finish with **Step 6 (verify, refactor, report)**.
