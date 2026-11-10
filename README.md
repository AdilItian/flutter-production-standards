# flutter-production-standards

A Claude Code / Agent Skill that makes an AI behave like a senior Flutter architect: it asks before assuming, plans before scaffolding, builds the design system before screens, and refuses to deliver work that fails its own review gate.

## Install

```bash
# project-level
cp -r flutter-production-standards .claude/skills/
# or user-level
cp -r flutter-production-standards ~/.claude/skills/
chmod +x flutter-production-standards/scripts/*.sh
```

Then ask for any Flutter work ("create a food-delivery app", "add a cart feature", "build this Figma screen", "review my project").

## Publish and use

```bash
# publish (once)
cd flutter-production-standards && git init && git add . && git commit -m "Flutter production standards skill"
gh repo create flutter-production-standards --public --source=. --push

# install: Skills.sh (confirm the command on skills.sh)
npx skills add <you>/flutter-production-standards
# or manually
git clone https://github.com/<you>/flutter-production-standards ~/.claude/skills/flutter-production-standards
```

Restart Claude Code, then just ask for Flutter work; the skill triggers from its description.
On a new app the skill copies `audit.sh` and `new_feature.sh` into the project's `scripts/`. To audit any project without that:
`~/.claude/skills/flutter-production-standards/scripts/audit.sh <project_root>`

CI step (GitHub Actions example), after `flutter analyze`:
```yaml
- run: scripts/audit.sh
```

## Layout

```
flutter-production-standards/
├── SKILL.md                          # workflow + routing (kept short, loaded every time)
├── references/                       # loaded only when the current step needs them
│   ├── architecture.md               ├── state-management.md
│   ├── folder-structure.md           ├── data-models.md
│   ├── ui-guidelines.md              ├── error-handling.md
│   ├── theming-and-constants.md      ├── code-standards.md
│   ├── routing.md                    ├── performance.md
│   ├── localization.md               ├── testing.md
│   ├── networking.md                 ├── accessibility.md
│   ├── security.md                   └── code-review-checklist.md
├── templates/
│   ├── requirements-questionnaire.md # every discovery question, options, defaults
│   ├── adr-template.md               # decision record + ADR-0001 foundations table
│   ├── design-analysis.md            # design → tokens → components, before any screen
│   └── analysis_options.yaml
└── scripts/
    ├── audit.sh                      # enforces the rules mechanically (grep-based)
    └── new_feature.sh                # feature skeleton
```

## Design decisions (what is different from the original brief, and why)

| Brief | This skill | Reason |
|---|---|---|
| Ask all questions up front | Three rounds, each question with a recommended default; "defaults" accepted and recorded as `delegated` | 15+ questions at once get shallow answers. "Never assume" is honored because every default is explicit and recorded |
| Clean Architecture on every feature | Entities + repo interfaces always; use cases only when they hold logic | Pass-through use cases add files and no behavior |
| DTO → Entity → Model → Mapper | DTO → Entity (+ optional UI model); mappers are functions | A fourth type with no distinct reason to change is ceremony |
| `AppColors` used by widgets | Widgets use theme roles; `AppColors` is raw palette for theme builders | Raw palette references break dark mode and rebranding |
| `AppStrings` class | gen-l10n + ARB | Plurals, locale formatting, translator workflow, compile-time keys |
| `AppRoutes`/`AppPages` | go_router typed routes, feature-owned (GetX variant included) | Deep links, web, guards, type safety |
| "Recommend GetX/Riverpod/Bloc" | Riverpod default; Bloc for strict event flows; GetX supported with rules and a stated risk | Honest trade-offs rather than neutrality |
| Checklist the AI reads | Checklist + `audit.sh` + lints, with a bounded fix loop | Prose rules are forgotten; tooling is not |
| Share common widgets early | Rule of two for feature code; design-system atoms exempt | Premature sharing fits one use case badly |
| Two exception/failure hierarchies | One sealed `AppFailure` + `Result` | They mirror each other 1:1 in practice |
| Many tiers of structure | Tier S/M/L chosen in discovery | A monorepo for a solo app costs more than it returns |

## Known limits

- `audit.sh` is regex-based: it catches common violations, will miss some and can false-positive. Use `// audit:ignore <reason>` sparingly. It complements lints and review; it does not replace them.
- Code samples target current stable Flutter/Dart 3. Package APIs and theme class names change between versions: the skill tells the AI to check pub.dev and the project's Flutter version rather than trusting memory.
- Package names mentioned (go_router, riverpod, dio, freezed, etc.) are defaults, not mandates; existing project choices win.
