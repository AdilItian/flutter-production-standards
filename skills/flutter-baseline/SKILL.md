---
name: flutter-baseline
description: Slash command. Audit an existing Flutter project against flutter-production-standards, write a gap report to docs/skill-audit/, and summarize it for the user. Changes no source code.
disable-model-invocation: true
---

# /flutter-baseline

Standards folder: `${CLAUDE_SKILL_DIR}/../flutter-production-standards`
If that folder does not exist, stop and tell the user to install it: `npx skills add AdilItian/flutter-production-standards` (select all skills).

Arguments (ignored unless useful): `$ARGUMENTS`

Do this:
1. Require a `pubspec.yaml`. If none, suggest `/flutter-new-app`.
2. Read the standards `references/existing-project-audit.md` and follow its procedure exactly: `bash <standards>/scripts/scan_project.sh .`, analyzer and tests where possible, selective reading, at most two questions (is the app published; what matters most).
3. If a report already exists in `docs/skill-audit/`, update it instead of starting over.
4. Write `docs/skill-audit/gap-report-YYYY-MM-DD.md` from `templates/gap-report.md`.
5. Send the short notification in the format from the reference: file path, counts by severity, top 5 issues, ids status, decisions needed, suggested first step.
6. **Change no source code.** Never change app ids, signing or release settings.
