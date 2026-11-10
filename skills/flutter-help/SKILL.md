---
name: flutter-help
description: Slash command. List the flutter-production-standards commands and what each one does.
disable-model-invocation: true
---

# /flutter-help

Show this table to the user as is, then stop. Do not run tools.

| Command | Use it to |
|---|---|
| `/flutter-new-app [name]` | Start a new app: discovery questions, plan, foundation, app ids |
| `/flutter-new-feature <name> [purpose]` | Add a feature slice: domain, data, state, UI, route, strings, tests |
| `/flutter-design-to-ui <design> [screen]` | Build a screen from a design: analysis, components first, then the screen |
| `/flutter-baseline` | Audit an existing project and write a gap report to `docs/skill-audit/` |
| `/flutter-audit [fix]` | Run the rule audit (magic values, hardcoded strings, layering, file sizes) |
| `/flutter-review [range or path] [fix]` | Review changes against the full checklist |
| `/flutter-ids [suggest <org> "App Name"]` | Validate application ids on every platform, or suggest a default |
| `/flutter-production-standards` | Open-ended: apply the standards to whatever you ask |

The commands need the main skill installed next to them. If something reports a missing standards folder, run:
`npx skills add AdilItian/flutter-production-standards` and select all skills.

Note: plain `/name` commands are a Claude Code feature. In other agents (Cursor, Codex and others) the same skills load by name or description instead.
