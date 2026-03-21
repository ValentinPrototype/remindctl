# spec-0.9.1

**Document Type:** Software Design Description (SDD) revision
**Version:** 0.9.1
**Status:** Draft
**Project:** `remindctl-gtd`
**Supersedes:** conflicting identity, join, and Shortcut asset-location sections in [docs/spec-0.9.0.md](/Users/vk/work/openclaw/remindctl/docs/spec-0.9.0.md)

---

## 1. Purpose

This document revises the `0.9.0` SDD after live validation against the current repository and actual Shortcut output.

The key observed fact is now explicit:
- native/EventKit returns a usable native reminder handle
- current Shortcut payload `id` is not the same identifier and must be treated as a Shortcut-local source key
- therefore native-to-Shortcut canonical joins cannot rely on current Shortcut `id`

This revision changes the canonical identity model, the `G3` validation gate, and the required Shortcut asset layout.

All support-status decisions from `0.9.0` remain in force unless this document states otherwise.

---

## 2. Observed Evidence

### 2.1 Native Reminder Evidence

The current native CLI can read reminder data that includes:
- `id`
- `title`
- `calendar`
- `creationDate`
- `notes`
- `priority`
- `dueDate`
- `lastModifiedDate`
- `isCompleted`
- `hasAlarms`
- `url`

The implementation also captures native evidence fields from EventKit:
- `calendarItemIdentifier`
- `calendarItemExternalIdentifier`

### 2.2 Shortcut Evidence

The current Shortcut transport can return:
- tag membership
- subtasks
- flagged state
- list name
- notes
- created and updated timestamps
- other semantic slices required for GTD queries

However, the current Shortcut payload `id` is a Shortcut-local/source identifier and is not usable as a canonical join key with EventKit.

### 2.3 Consequence

`spec-0.9.0` assumed that deterministic native identifier propagation through Shortcut payloads might become the primary join strategy.

That assumption is now rejected for v1.

The primary canonical identity for managed reminders is a note footer shared across native and Shortcut surfaces.

---

## 3. Revised Architecture Boundary

### 3.1 Native/EventKit Team

Responsibilities:
- read and write reminders through EventKit
- normalize managed note footers
- expose native evidence fields
- provide footer-stripped note bodies to user-facing CLI output

Native/EventKit does not own:
- GTD tag semantics
- parent/child interpretation
- canonical cross-source joins beyond emitting footer and evidence state

### 3.2 Shortcut Team

Responsibilities:
- produce fixed-purpose, read-only JSON contracts
- preserve raw `notes` exactly enough for footer parsing
- expose tag and hierarchy slices that EventKit does not provide directly

Shortcut contracts do not own:
- canonicalization
- footer generation
- footer interpretation
- business logic keyed to human Shortcut names

### 3.3 Mirror/Query Team

Responsibilities:
- parse note footers
- promote canonical rows only when footer evidence is valid
- retain unresolved Shortcut rows when footers are missing or invalid
- attach provenance, confidence, and freshness metadata to results

### 3.4 David Layer

Responsibilities:
- consume normalized query views
- reason over `confidence`, `identityStatus`, `warnings`, and `freshness`

David-layer logic must never parse raw Shortcut payloads or infer joins.

---

## 4. Canonical Identity Revision

### 4.1 Canonical Footer Format

The canonical footer format is normative and exact:

```text
[remindctl-gtd:v1 id=550e8400-e29b-41d4-a716-446655440000]
```

Rules:
- the footer is the last non-empty line in the note
- if there is human note text, exactly one blank line separates note body from footer
- UUID must be lowercase canonical text
- parsing is exact, never fuzzy
- malformed or duplicate footers are invalid

### 4.2 Note Storage Model

The system stores notes in two forms:
- `raw_notes`: the full stored note, including the footer when present
- `notes_body`: the human-visible note text, with the footer removed

User-facing note output must use `notes_body`, never `raw_notes`.

### 4.3 Managed Reminder Policy

All reminders seen by `remindctl-gtd` are managed reminders.

Sync behavior:
1. native acquisition reads reminders and parses footer state
2. reminders with missing footers get a generated UUID footer
3. reminders with malformed footers are rewritten into canonical form
4. the native read is repeated after write-back so mirror state reflects stored notes and timestamps
5. Shortcut acquisition runs after native footer normalization

Mutation behavior:
- `add` writes a footer at creation time
- `edit --notes` rewrites only the human note body and preserves or regenerates the footer
- non-note edits preserve the footer
- all future note mutations must round-trip through the footer parser/renderer

### 4.4 Canonical Identity and Evidence

Primary canonical ID format:

```text
managed::<uuid>
```

Identity rules:
- the parsed note-footer UUID is the primary canonical identity
- `native_calendar_item_identifier` and `native_external_identifier` are evidence fields only
- Shortcut `source_item_id` is always a Shortcut-local source key only
- native and Shortcut rows may join canonically only through the parsed footer UUID
- rows without a valid footer remain unresolved for cross-source joins

### 4.5 Identity States

The mirror uses these identity states:
- `canonical_managed`
- `shortcut_unresolved`
- `footer_invalid`
- `collision_unresolved`

`collision_unresolved` applies to secondary evidence conflicts only.
It does not override a valid managed UUID footer.

---

## 5. Validation Gate Revision

### 5.1 G3 Revision

`G3` is no longer an identifier-propagation gate.

`G3` is now the Shortcut note-footer gate:
- proof target: Shortcut payload `notes` preserve the canonical footer with enough fidelity for deterministic parsing

Pass effect:
- Shortcut rows with valid parsed footers may be promoted to canonical managed rows
- native-to-Shortcut joins may use the shared managed UUID

Fail effect:
- Shortcut rows remain unresolved even if they contain useful tags or hierarchy
- single-contract retrieval may still run with low confidence
- multi-contract and native-to-Shortcut joins remain blocked

### 5.2 G4 Revision

`G4` remains useful, but only as evidence quality:
- validates how much trust to place in `calendarItemExternalIdentifier`
- affects diagnostics and migration/debugging confidence
- does not define the primary canonical ID

### 5.3 G5 Revision

`G5` continues to gate stale-age logic based on native `lastModifiedDate`.

If `G5` fails, the system may require `shortcut.productivity_recently_updated.v1` as a fallback acquisition contract.

---

## 6. Shortcut Asset Layout and Contract Catalog

### 6.1 Repo Layout

The permanent home for Shortcut assets is:

- [Support/Shortcuts](/Users/vk/work/openclaw/remindctl/Support/Shortcuts)

Required contents:
- [Support/Shortcuts/README.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/README.md)
- [Support/Shortcuts/REQUIRED_SHORTCUTS.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/REQUIRED_SHORTCUTS.md)
- `Support/Shortcuts/fixtures/`
- versioned `.shortcut` assets when available

The existing shipped helper Shortcut remains a transport/reference asset. It is not the full GTD contract catalog.

### 6.2 Required Contracts

The required GTD contracts remain:
- `shortcut.active_projects.v1`
- `shortcut.next_actions.v1`
- `shortcut.waiting_ons.v1`
- `shortcut.productivity_hierarchy.v1`
- `shortcut.productivity_recently_updated.v1` only if `G5` fails

Each contract must define:
- contract ID
- deployed Shortcut name
- owner team
- why native/EventKit alone is insufficient
- invocation via `shortcuts run`
- JSON schema
- golden fixture payload
- failure fixture payload

### 6.3 Contract Rules

Normative rules:
- business logic refers to contract IDs, not human Shortcut names
- a single adapter layer maps contract IDs to deployed Shortcut names
- `source_item_id` remains Shortcut-local only
- Shortcut payloads must include raw `notes`
- the Shortcut team does not generate or interpret the footer semantically
- the core parser is solely responsible for footer parsing and canonicalization

---

## 7. Mirror and Query Effects

The mirror stores, at minimum:
- `canonical_managed_id`
- `raw_notes`
- `notes_body`
- `footer_state`
- native evidence identifiers
- Shortcut `source_item_id`
- provenance and acquisition-source metadata

Promotion rules:
- native rows with valid footers become canonical managed rows
- Shortcut rows may promote only when `G3` is passed and the parsed footer matches a canonical managed UUID
- otherwise Shortcut rows remain unresolved

User-facing effects:
- `show` and other human-facing outputs display `notes_body`
- mirror/query JSON may expose canonical metadata and footer validity
- note-based hygiene queries operate on `notes_body`, not raw footer content

---

## 8. Verification Requirements

The implementation must verify:
- valid footer parsing
- malformed footer detection
- duplicate footer detection
- deterministic footer rendering
- footer preservation across add, edit, complete, and sync normalization
- idempotent sync after footer backfill
- native and Shortcut row canonical joins via shared managed UUID
- unresolved behavior when Shortcut payloads lack a valid footer
- no user-facing note output leaks the managed footer

The Shortcut catalog must provide at least:
- one golden fixture per contract
- one failure fixture per contract

---

## 9. Current Implementation Alignment

The current implementation aligns with this revision in these ways:
- native sync normalizes managed footers before mirror ingestion
- native mutation paths preserve or create the footer
- mirror canonicalization uses managed footer UUIDs as the primary key
- Shortcut note parsing strips the footer for user-facing notes and extracts footer metadata for mirror logic
- `G3` is modeled as the Shortcut note-footer gate
- Support assets and required contracts are documented under `Support/Shortcuts`

Remaining support-status constraints from `0.9.0` remain unchanged:
- tag-only and hierarchy-only queries still require `G1` and `G2`
- broad project hygiene and multi-contract joins remain blocked until the required gates pass
- no fuzzy title/notes/list/date matching is permitted

---

## 10. Rationale

This revision prefers a managed note footer because it is the only currently verified identifier that can exist on both native and Shortcut surfaces without guessing.

This is a deliberate tradeoff:
- it writes managed metadata into reminder notes
- it avoids false joins and heuristic merges
- it allows the native team, mirror/query team, and Shortcut team to work in parallel against a deterministic contract

That tradeoff is accepted for v1.
