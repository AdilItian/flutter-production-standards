# flutter-production-standards

A Claude Code / Agent Skill that makes an AI behave like a senior Flutter architect: it asks before assuming, plans before scaffolding, builds the design system before screens, and refuses to deliver work that fails its own review gate.

## Install

```bash
# Skills.sh CLI (works with Claude Code, Cursor, Codex, Copilot, Gemini CLI and others).
# Choose ALL skills when prompted: the slash commands need the main skill next to them.
npx skills add AdilItian/flutter-production-standards

# or manually, for Claude Code
git clone https://github.com/AdilItian/flutter-production-standards /tmp/fps
mkdir -p ~/.claude/skills && cp -R /tmp/fps/skills/* ~/.claude/skills/
chmod +x ~/.claude/skills/flutter-production-standards/scripts/*.sh
```

Restart Claude Code after installing.

## Slash commands

Type `/` in Claude Code to see them. `/flutter-help` prints this table.

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

The commands are only started by you (they never trigger on their own). The main skill still triggers automatically when you ask for Flutter work in plain language. Slash commands are a Claude Code feature; in other agents the same skills load by name or description.

## Use

On a new app the skill copies `audit.sh`, `check_ids.sh` and `new_feature.sh` into the project's `scripts/`. To audit any project without that:
`~/.claude/skills/flutter-production-standards/scripts/audit.sh <project_root>`

CI step (GitHub Actions example), after `flutter analyze`:
```yaml
- run: scripts/audit.sh
```

## Layout

```
skills/                               # the repo publishes several skills
├── flutter-production-standards/     # the main skill
│   ├── SKILL.md                      # workflow + routing (kept short, loaded every time)
│   ├── references/                   # loaded only when the current step needs them
│   │   ├── architecture.md           ├── state-management.md
│   │   ├── folder-structure.md       ├── data-models.md
│   │   ├── ui-guidelines.md          ├── error-handling.md
│   │   ├── theming-and-constants.md  ├── code-standards.md
│   │   ├── routing.md                ├── performance.md
│   │   ├── localization.md           ├── testing.md
│   │   ├── networking.md             ├── accessibility.md
│   │   ├── security.md               ├── forms-and-feedback.md
│   │   ├── project-identity.md       ├── existing-project-audit.md
│   │   └── code-review-checklist.md
│   ├── templates/
│   │   ├── requirements-questionnaire.md  # every discovery question, options, defaults
│   │   ├── adr-template.md                # decision record + ADR-0001 foundations table
│   │   ├── design-analysis.md             # design to tokens to components, before any screen
│   │   ├── gap-report.md                  # baseline audit report for existing projects
│   │   └── analysis_options.yaml
│   └── scripts/
│       ├── audit.sh                  # enforces the rules mechanically (grep-based)
│       ├── check_ids.sh              # validates app ids on every platform; --suggest derives a default
│       ├── scan_project.sh           # read-only facts about an existing project
│       └── new_feature.sh            # feature skeleton
├── flutter-new-app/        flutter-new-feature/     flutter-design-to-ui/
├── flutter-baseline/       flutter-audit/           flutter-review/
└── flutter-ids/            flutter-help/            # thin slash-command skills (one SKILL.md each)
```

Why a `skills/` folder: the Skills.sh installer lets a `SKILL.md` at the repo root hide every skill below it. Publishing the main skill plus its commands from one repo therefore requires them all to live under `skills/`.

## Design decisions (what is different from the original brief, and why)

| Brief | This skill | Reason |
|---|---|---|
| Ask all questions up front | Three rounds, each question with a recommended default; "defaults" accepted and recorded as `delegated` | 15+ questions at once get shallow answers. "Never assume" is honored because every default is explicit and recorded |
| Clean Architecture on every feature | Entities + repo interfaces always; use cases only when they hold logic | Pass-through use cases add files and no behavior |
| DTO → Entity → Model → Mapper | DTO → Entity (+ optional UI model); mappers are functions | A fourth type with no distinct reason to change is ceremony |
| `AppColors` used by widgets | Widgets use theme roles; `AppColors` is raw palette for theme builders | Raw palette references break dark mode and rebranding |
| `AppStrings` class | gen-l10n + ARB | Plurals, locale formatting, translator workflow, compile-time keys |
| `AppRoutes`/`AppPages` | Kept, as asked: GetX navigation (`GetMaterialApp`, `GetPage`) with central `AppRoutes`, `AppPages` and an `AppNavigation` helper (go_router as the alternative) | Single obvious place for routes. Compensates for string routes with builders, an audit rule against string literals, and an auth middleware |
| "Recommend GetX/Riverpod/Bloc" | Riverpod default; Bloc for strict event flows; GetX supported with rules and a stated risk | Honest trade-offs rather than neutrality |
| Checklist the AI reads | Checklist + `audit.sh` + lints, with a bounded fix loop | Prose rules are forgotten; tooling is not |
| Share common widgets early | Rule of two for feature code; design-system atoms exempt | Premature sharing fits one use case badly |
| Two exception/failure hierarchies | One sealed `AppFailure` + `Result` | They mirror each other 1:1 in practice |
| Many tiers of structure | Tier S/M/L chosen in discovery | A monorepo for a solo app costs more than it returns |

## What the skill enforces for common app behavior

| Practice | Where |
|---|---|
| Consistent loading, success and error feedback | `forms-and-feedback.md`, `error-handling.md`, `ui-guidelines.md` |
| Form validation | `forms-and-feedback.md` |
| No internet, retries, request throttling | `networking.md`, `error-handling.md` |
| Offline-first, sync and conflict handling | `networking.md` |
| One controller only when needed | `state-management.md` |
| Valid, consistent app ids on every platform, with a default suggestion | `project-identity.md`, `scripts/check_ids.sh` |
| Existing project: gap analysis written to `docs/skill-audit/` and the user notified | `existing-project-audit.md`, `templates/gap-report.md` |

## Known limits

- `audit.sh` is regex-based: it catches common violations, will miss some and can false-positive. Use `// audit:ignore <reason>` sparingly. It complements lints and review; it does not replace them.
- Code samples target current stable Flutter/Dart 3. Package APIs and theme class names change between versions: the skill tells the AI to check pub.dev and the project's Flutter version rather than trusting memory.
- Package names mentioned (go_router, riverpod, dio, freezed, etc.) are defaults, not mandates; existing project choices win.
