# Project instructions

This is a Flutter app built and maintained with the **flutter-production-standards** skill.

For ANY Flutter work in this repository (new feature, screen, bug fix, refactor, review), load and follow that skill first, even when the request sounds small. A request to "keep it simple" changes the scope, not the process: still read the decision record, reuse the design system, and finish with the review gate.

Where things are:
- Decisions: `docs/decisions/` (read before asking the user anything the record already answers)
- Gap report (if any): `docs/skill-audit/`
- Rules audit: `scripts/audit.sh` (run before reporting work as done)
- App ids: `scripts/check_ids.sh`
- New feature skeleton: `scripts/new_feature.sh <name>`

Slash commands: `/flutter-new-feature`, `/flutter-design-to-ui`, `/flutter-audit`, `/flutter-review`, `/flutter-ids`, `/flutter-baseline`, `/flutter-help`.

Non-negotiables in one line each: layers point inward; no business logic or HTTP in widgets; components before screens; no magic values or hardcoded strings or route strings; offline-first by default; `AppToast` for feedback, `AppLoader` for loading; `Result<T>` from repositories; run format, analyze, tests and `scripts/audit.sh` before saying done.
