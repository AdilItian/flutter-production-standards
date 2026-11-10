# Design Analysis (fill in BEFORE writing any screen)

Do this once per screen or flow handed to you. Keep it short; it is a working note, not a deliverable. Save as `docs/design/<screen>.md` only if the user wants a record.

## 1. Tokens found

| Kind | Values seen in the design | Maps to existing token? | New token needed |
|---|---|---|---|
| Colors | | | |
| Text styles (size/weight/line-height) | | | |
| Spacing values | | | |
| Radii | | | |
| Elevation / shadows | | | |
| Icon sizes | | | |
| Durations (if prototype shows motion) | | | |

Rule: snap near-values to the scale (15px → 16px). Only add a token if the value appears repeatedly and is intentional. Flag real inconsistencies to the user instead of encoding them.

## 2. Repeated patterns

List every UI chunk that appears 2 or more times, on this screen or others.

| Pattern | Occurrences | Existing component | Action |
|---|---|---|---|
| e.g. rounded list row with avatar + title + subtitle | 6 | none | create `AppListTile` |

## 3. Component inventory for this screen

| Component | Source (design_system / shared / feature-local / NEW) | Variants and states needed |
|---|---|---|
| | | |

Every NEW component needs: variants (enum), disabled, loading (if tappable/async), focus, error (if input), semantics label source, RTL behavior.

## 4. Screen states

- [ ] Loading (skeleton or spinner)
- [ ] Content
- [ ] Empty
- [ ] Error (with retry)
- [ ] Offline (if offline support chosen)
- [ ] Permission denied (if relevant)

## 5. Responsive notes

Which parts reflow at compact (<600), medium (600-839), expanded (≥840)? Anything scrollable that is fixed in the design?

## 6. Strings

Every visible string becomes an ARB key. List new keys, with plural/placeholder needs.

## 7. Build order

1. New tokens
2. New components (with widget tests / goldens)
3. Feature-local widgets
4. Screen composition
5. Strings, route, state wiring
