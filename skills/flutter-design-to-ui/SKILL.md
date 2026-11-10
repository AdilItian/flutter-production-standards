---
name: flutter-design-to-ui
description: Slash command. Turn a design (image path, screenshot, or Figma link) into Flutter UI by analyzing it, creating reusable components first, then composing the screen.
argument-hint: "<design image path or link> [screen name]"
disable-model-invocation: true
---

# /flutter-design-to-ui

Standards folder: `${CLAUDE_SKILL_DIR}/../flutter-production-standards`
If that folder does not exist, stop and tell the user to install it: `npx skills add AdilItian/flutter-production-standards` (select all skills).

Design input: `$ARGUMENTS`
If it shows the literal text `$ARGUMENTS` or is empty, ask the user for the design (path, pasted image, or link) and the screen name.

Do this:
1. Read the standards `references/ui-guidelines.md`, `references/theming-and-constants.md`, `references/accessibility.md` and `templates/design-analysis.md`.
2. **Analyze before coding.** Fill in the design analysis: tokens, repeated patterns, component inventory (reuse vs new), screen states, responsive notes, strings. Show it to the user briefly.
3. Search the repo for existing components before creating any.
4. Add missing tokens, then missing components (with all states and variants), then compose the screen. Never build the screen first.
5. Cover loading, content, empty and error states (`references/forms-and-feedback.md`); localize every string; check RTL, dark theme and 200% text scale.
6. Report which components were reused and which were created. Finish with the review gate (`references/code-review-checklist.md`).
