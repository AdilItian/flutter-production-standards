---
name: flutter-review
description: Slash command. Review the current Flutter changes against the flutter-production-standards checklist (architecture, magic values, localization, states, tests, security) and report findings.
argument-hint: "[git range | path | fix]"
disable-model-invocation: true
---

# /flutter-review

Standards folder: `${CLAUDE_SKILL_DIR}/../flutter-production-standards`
If that folder does not exist, stop and tell the user to install it: `npx skills add AdilItian/flutter-production-standards` (select all skills).

Scope or mode: `$ARGUMENTS` (empty means the uncommitted changes plus the last commit if the tree is clean; a git range or path narrows it; `fix` also fixes what is found).

Do this:
1. Determine the changed files (`git diff`, `git diff <range>`, or the given path). If there is no git history, review the given path or `lib/`.
2. Read the standards `references/code-review-checklist.md` and run its **Procedure**: format, analyze, tests, `scripts/audit.sh`. State clearly what could not be run.
3. Walk sections A to K against the changed files and their immediate neighbors (look for duplicates of new widgets and logic).
4. Report findings by severity (Blocker, Major, Minor) with `file:line`, why it matters, and the fix. Use the report format at the end of the checklist. Do not claim a check passed unless you ran it.
5. Report only by default. In `fix` mode, fix Blockers and Majors, re-run, and stop after 3 rounds.
