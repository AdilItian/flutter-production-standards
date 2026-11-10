# Existing Project: Baseline Audit and Gap Report

Read when: the working directory already contains a Flutter project and this is the first time the skill is used on it (no report in `docs/skill-audit/`), or the user asks for a review, health check or adoption plan.

**Purpose:** find out how far the project is from the standards, write that down in a file the team keeps, tell the user, and let them choose what to fix. The audit **changes no source code.**

## Principles

1. **Existing conventions win.** Judge the project against its *own* choices first (if it uses Bloc, don't flag "not Riverpod"). Flag a choice only when it is risky (e.g. an unmaintained package, secrets in the repo).
2. **Evidence, not opinion.** Every finding cites files and lines (or script output) and says why it matters.
3. **Don't rewrite working code.** Recommend incremental migration (strangler pattern): new code follows the standards, old code moves feature by feature when touched.
4. **Never change app ids, signing, or release configuration** during the audit.
5. **Say what you did not check** (e.g. runtime behavior, store state, backend).

## Procedure

1. **Run the scanners** (project copy of the scripts, or the skill's copy with the project root as the argument):
   ```bash
   scripts/scan_project.sh . > /tmp/facts.md     # stack, structure, signals, security settings, ids, audit.sh summary
   dart format --set-exit-if-changed . ; flutter analyze ; flutter test --coverage    # record results; note if they cannot run
   ```
   Write temporary output to the scratchpad or `build/`, not into the project tree.
2. **Read selectively**: `pubspec.yaml`, `analysis_options.yaml`, `main*.dart`, router, one representative feature end to end, the theme, one repository and one screen. Enough to judge structure, not every file.
3. **Ask at most two questions**, only if they change the report: *Is the app published or distributed (so ids cannot change)?* and *What matters most now: stabilize, scale the team, or ship a feature?* Default if unanswered: treat the app as published, stabilize first.
4. **Classify findings** using the rubric below, and compile the report from `templates/gap-report.md` into `docs/skill-audit/gap-report-YYYY-MM-DD.md`.
5. **Notify the user** (format below) and wait for their choice before changing code.
6. Proceed with the original task only after the user answers, unless the task is independent of every Blocker (then say so and continue).

## Areas to assess

Each area produces findings; skip an area only if truly not applicable.

| Area | Look for |
|---|---|
| **Identity** | `check_ids.sh` results: placeholders, invalid formats, mismatches, Firebase mismatch, pubspec name |
| **Architecture** | Layering violations, business logic in widgets, HTTP in UI, cross-feature imports, god classes, folder organization vs `folder-structure.md` |
| **State management** | Mixed systems, controllers that only forward calls, state in `build`, missing disposal, `setState` abuse |
| **Data and models** | `Map<String, dynamic>` in UI, no DTO/entity split, `double` money, unhandled nulls/enums |
| **Networking and errors** | Multiple HTTP clients, no error mapping, swallowed exceptions, no timeouts, no retry/refresh strategy, `print` logging |
| **Offline and sync** | Whether offline was a requirement; cache without TTL; writes lost offline |
| **UI and design system** | Duplicate widgets, magic values, no tokens/theme, no dark theme, widget helper methods, giant `build` methods |
| **Routing** | Hardcoded route strings, `Navigator` 1.0 only, no guards, no deep links (if needed) |
| **Localization** | Hardcoded strings, no l10n, RTL-unsafe layout (if RTL needed) |
| **Accessibility** | No semantics, small targets, fixed text sizes, color-only meaning |
| **Performance** | `ListView` without builder, `shrinkWrap` lists, full-size images, work in `build`, no pagination |
| **Security** | Secrets in source or assets, tokens in `shared_preferences`, cleartext traffic, `allowBackup`, tracked keystores/env files, unvetted WebViews |
| **Testing and CI** | Test count and coverage, no CI, no analyzer gate, no flavors |
| **Dependencies** | Discontinued or very outdated packages, duplicates (two HTTP clients), unused packages. Verify on pub.dev; never guess |
| **Docs and decisions** | No README, no ADRs, no setup instructions |

## Severity rubric

| Severity | Meaning | Examples |
|---|---|---|
| **Blocker** | Security hole, data loss, store rejection risk, or something that makes safe change impossible | Committed keystore or secrets, tokens in plain storage, placeholder app id on an unpublished app, no error handling around payments |
| **Major** | Will cause bugs or slow the team soon | Business logic in widgets, two state systems, no tests on core flows, hardcoded strings with a localization requirement, no CI |
| **Minor** | Quality and consistency | Naming, file size, missing `const`, lints off |
| **Note** | Observation or intentional deviation | Different architecture choice that works |

Effort: **S** (under an hour), **M** (a day or less), **L** (several days or a migration).

## Migration plan shape (in the report)

1. **Phase 0, safety net (S–M):** analyzer and format gates, `audit.sh` in CI, secrets removal, critical tests around the flows you will touch.
2. **Phase 1, foundations (M):** tokens + theme, l10n setup, error/`Result` types, API client cleanup. New code uses them; old code is untouched.
3. **Phase 2, feature by feature (L):** migrate one feature at a time, ordered by risk and change frequency, each with tests before and after.
4. **Phase 3, polish:** accessibility, performance, offline, docs.

Name the first concrete step and its expected diff size so the user can say "go".

## Notifying the user

After writing the file, send a short message:

```
Baseline audit finished. Report: docs/skill-audit/gap-report-2026-11-10.md
Readiness: <Needs work | Mostly aligned | Aligned>
Findings: <n> Blocker · <n> Major · <n> Minor
Top issues:
  1. <one line, with severity>   2. ...   (max 5)
App ids: <valid and consistent | N issues, see report>
Not checked: <list>
Decision needed: <at most 2 questions>
Suggested first step: <phase and action>
I have not changed any code.
```
Do not paste the whole report into chat. If you also changed anything (e.g. created `docs/skill-audit/`), say what.

## Re-running

If a report already exists, read it first. Update statuses (open / fixed / accepted) instead of starting over, and add a dated section for new findings. A user-accepted deviation is recorded as `accepted` with the reason, and is not re-raised.
