---
name: flutter-audit
description: Slash command. Run the flutter-production-standards rule audit (magic values, hardcoded strings, layer violations, file sizes) plus analyzer, and report the violations.
argument-hint: "[fix]"
disable-model-invocation: true
---

# /flutter-audit

Standards folder: `${CLAUDE_SKILL_DIR}/../flutter-production-standards`
If that folder does not exist, stop and tell the user to install it: `npx skills add AdilItian/flutter-production-standards` (select all skills).

Mode: `$ARGUMENTS` (empty means report only; `fix` means fix violations).

Do this:
1. Run `bash <standards>/scripts/audit.sh .` (or the project's `scripts/audit.sh`). Also run `dart format --set-exit-if-changed .` and `flutter analyze` if Flutter is available; if not, say so.
2. Group the findings by rule and summarize counts. Explain each rule class in one line and show the worst offenders.
3. **Report only** by default. Change nothing.
4. In `fix` mode: fix the violations by refactoring (extract tokens, components and ARB strings; do not just add `// audit:ignore`), re-run, and stop after 3 rounds. List anything left and why.
5. The audit is heuristic. Say that a clean run does not replace `/flutter-review`.
