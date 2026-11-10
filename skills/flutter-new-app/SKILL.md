---
name: flutter-new-app
description: Slash command. Start a new production-grade Flutter app with the flutter-production-standards workflow (discovery questions, plan, foundation).
argument-hint: "[app-name]"
disable-model-invocation: true
---

# /flutter-new-app

Standards folder: `${CLAUDE_SKILL_DIR}/../flutter-production-standards`
If that folder does not exist, stop and tell the user to install it: `npx skills add AdilItian/flutter-production-standards` (select all skills).

Requested app name (may be empty): `$ARGUMENTS`
If the line above shows the literal text `$ARGUMENTS`, the host did not substitute it; treat the name as unknown and ask.

Do this:
1. If a `pubspec.yaml` exists in the working directory, stop. This is an existing project: suggest `/flutter-baseline` first.
2. Read the standards `SKILL.md`, then run its **Step 1 (Discovery)** with `templates/requirements-questionnaire.md`: three rounds, recommended defaults, ask for the organization prefix and the languages. Record answers in `docs/decisions/0001-project-foundations.md`.
3. Present the **Step 2 plan** and wait for approval.
4. Build the **Step 3 foundation**, including application ids (`references/project-identity.md`, `scripts/check_ids.sh`).
5. Finish with **Step 6 (verify, refactor, report)**.
