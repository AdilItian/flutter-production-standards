---
name: flutter-ids
description: Slash command. Check application ids (Android applicationId, iOS/macOS bundle id, Linux id) for validity and consistency, or suggest a default id from an organization domain.
argument-hint: "[suggest <org.domain> \"App Name\"]"
disable-model-invocation: true
---

# /flutter-ids

Standards folder: `${CLAUDE_SKILL_DIR}/../flutter-production-standards`
If that folder does not exist, stop and tell the user to install it: `npx skills add AdilItian/flutter-production-standards` (select all skills).

Arguments: `$ARGUMENTS`

Do this:
1. Read the standards `references/project-identity.md`.
2. If the arguments start with `suggest`, run `bash <standards>/scripts/check_ids.sh --suggest <org> "<App Name>"`, show the id, and explain that the same string is used on every platform (flavor suffixes `.dev` and `.staging` are added on top). Ask no other question.
3. Otherwise run `bash <standards>/scripts/check_ids.sh .` and explain each finding in plain language: placeholder ids, invalid formats, Android vs iOS mismatches, Firebase mismatches.
4. **Do not edit anything.** Ask whether the app is already published or distributed. If yes, ids are frozen: explain the consequences of changing them and offer nothing destructive. If no, propose the new id and the list of files that would change, and apply only after the user confirms.
5. The check cannot know whether an id is already taken in a store. Say so.
