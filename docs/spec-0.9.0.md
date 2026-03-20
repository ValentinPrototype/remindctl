# spec-0.9.0

**Version:** 0.9.0  
**Status:** Draft / implementation-bridge  
**Owner:** Valentin / Prometheus / David  
**Project:** `remindctl-gtd`  
**Scope:** Cross-team build spec for native acquisition, Shortcut acquisition, mirror/query, and David-facing GTD outputs

---

## 1. Purpose

`spec-0.9.0` is the build bridge between:
- the current `remindctl` repository state
- the draft product direction in `spec-0.1.0`
- the v1 core stories in `user-stories-0.0.1`

This document is intentionally implementation-oriented.
Its job is to remove ambiguity for four parallel lanes:
- native/EventKit team
- Shortcut team
- mirror/query team
- David layer team

This is a hard-fork spec for `remindctl-gtd`.
The current `remindctl` codebase remains a reference implementation for native Apple Reminders access, not the final GTD product shape.

---

## 2. Decision Summary

The following decisions are locked for v1:
- `remindctl-gtd` is a hard fork from the current generic CLI direction.
- mirror-state is phase-one core, not an optional later optimization.
- true GTD semantics must come from public acquisition evidence, not from title/notes fallback.
- no private Reminders database access is allowed.
- no giant dynamic Shortcut query engine is allowed.
- Shortcut acquisition is defined as a versioned contract API, not as an ad hoc automation layer.
- business logic must reference Shortcut contract IDs, never hard-coded Shortcut names.
- canonical joins must never use fuzzy matching on title, notes, due date, or list.

Two additional v1 behavior decisions are also locked:
- single-contract semantic retrieval may be surfaced from non-canonical Shortcut rows with **low confidence** if the contract succeeded but native identifier propagation is missing
- any multi-contract correlation, native-to-Shortcut join, or hierarchy-plus-tag diagnostic is **blocked pending validation** until canonical identifier proof exists

---

## 3. Current Repo Reality

## 3.1 What the repository ships today

The current repository is a generic Apple Reminders CLI built on EventKit.

It currently supports:
- Reminders permission flow
- list enumeration
- list create/rename/delete
- reminder create/update/complete/delete
- reminder fetch and local filtering by date-oriented views such as `today`, `tomorrow`, `week`, `overdue`, `upcoming`, `completed`, and `all`
- JSON, plain-text, standard, and quiet output formats

It does **not** currently ship:
- Shortcut integration
- mirror-state or SQLite
- GTD/productivity query families
- tag extraction
- parent/child reminder extraction
- stale/vague/project-hygiene diagnostics
- confidence/freshness reporting

## 3.2 Current reminder model

The current public reminder model in code is `ReminderItem`.
Its fields are:
- `id`
- `title`
- `notes`
- `isCompleted`
- `completionDate`
- `priority`
- `dueDate`
- `listID`
- `listName`

Current JSON output is simply the encoded `ReminderItem` payload.
It is not yet a stable GTD schema.

## 3.3 Current identifier behavior

Today the repo uses:
- `EKReminder.calendarItemIdentifier` as the reminder `id`
- numeric index or `calendarItemIdentifier` prefix resolution for CLI mutation commands

That behavior is suitable for a local CRUD CLI, but it is not sufficient as the canonical identity strategy for `remindctl-gtd`.

## 3.4 Current native gaps relative to GTD scope

The repo does not currently expose:
- `calendarItemExternalIdentifier`
- `creationDate`
- `lastModifiedDate`
- `URL`
- recurrence/alarm presence
- `EKSource.sourceIdentifier`

Those fields are part of public EventKit and must be added to the native acquisition lane.

The repo also has no existing public path for:
- true reminder tags
- reminder parent/child structure
- flagged state

---

## 4. System Boundaries And Ownership

## 4.1 Native/EventKit team

The native team owns:
- Reminders permission handling
- public EventKit reads and writes
- authoritative native reminder fields
- authoritative native identifiers
- source, calendar, and provider metadata
- validation of native timestamp and identity behavior

The native team does **not** own:
- GTD semantics such as `active-project`, `next-action`, or `waiting-on`
- Shortcut payload design
- cross-source canonicalization policy beyond emitting authoritative native evidence
- David judgment logic

## 4.2 Shortcut team

The Shortcut team owns:
- the fixed Shortcut contract catalog in this spec
- Shortcut implementation details inside the Shortcuts app
- contract fixture payloads
- contract-level failure behavior
- contract schema conformance

The Shortcut team does **not** own:
- mirror schema
- canonical identity joins
- GTD derived diagnostics
- business logic that chooses deployed Shortcut names

## 4.3 Mirror/query team

The mirror/query team owns:
- normalized storage
- canonical identity promotion
- unresolved Shortcut row storage
- provenance and confidence metadata
- query views consumed by David
- the adapter layer mapping contract IDs to deployed Shortcut names

The mirror/query team does **not** own:
- raw EventKit retrieval implementation details
- Shortcut UI implementation details
- David interpretation heuristics

## 4.4 David layer

The David layer owns:
- interpretation of normalized views
- stale/vague/delegation heuristics
- review-oriented outputs
- confidence-aware productivity guidance

The David layer does **not** own:
- raw acquisition
- mirror sync semantics
- parsing raw Shortcut payloads
- inferring tags or hierarchy from titles or notes when the acquisition layer did not prove them

## 4.5 Boundary rules

- retrieval belongs to native/EventKit or Shortcut acquisition
- normalization belongs to mirror/query
- productivity judgment belongs to David
- no layer may silently infer missing tags, hierarchy, or canonical identity

---

## 5. Native API Capability Boundary

## 5.1 Public native capability table

| Capability | Public EventKit status | Current repo status | v1 decision |
|---|---|---|---|
| List enumeration | supported | implemented | native-supported |
| List create/rename/delete | supported | implemented | native-supported |
| Fetch all reminders in calendars | supported | implemented | native-supported |
| Fetch incomplete reminders by due-date range | supported | not implemented in repo | native-supported after native lane wiring |
| Fetch completed reminders by completion-date range | supported | not implemented in repo | native-supported after native lane wiring |
| `calendarItemIdentifier` | supported | implemented | authoritative local lookup handle only |
| `calendarItemExternalIdentifier` | supported | not implemented in repo | preferred canonical identity when validated |
| `creationDate` | supported | not implemented in repo | native acquisition field |
| `lastModifiedDate` | supported | not implemented in repo | native acquisition field, gated for reliability |
| `notes` | supported | implemented | native acquisition field |
| `title` | supported | implemented | native acquisition field |
| `priority` | supported | implemented | native acquisition field |
| `dueDateComponents` / due date | supported | implemented | native acquisition field |
| `completionDate` / completed state | supported | implemented | native acquisition field |
| `URL` | supported | not implemented in repo | native acquisition field |
| recurrence/alarm presence | supported | not implemented in repo | optional native evidence field |
| `EKSource.sourceIdentifier` | supported | not implemented in repo | required for provider scoping |
| True reminder tags | unproven in EventKit for this product | not implemented | not assumed; use Shortcut gate |
| Parent/child reminder structure | unproven in EventKit for this product | not implemented | not assumed; use Shortcut gate |
| Flagged state | not present in verified public headers used here | not implemented | unsupported for v1 |

## 5.2 Native query boundary

The native lane is allowed to answer:
- list-oriented retrieval
- date-oriented retrieval
- completion-oriented retrieval
- title/notes-based heuristics that do not require GTD tags or hierarchy
- freshness and provenance questions based on native sync evidence

The native lane is **not** allowed to claim:
- true `active-project`, `next-action`, or `waiting-on` semantics
- parent/child project structure
- tag intersections
- untagged child diagnostics
- project-missing-next-action diagnostics

unless those capabilities are proven by a public supported path and explicitly promoted through the validation gates below.

## 5.3 Native API risks that must be carried into implementation

- `calendarItemIdentifier` is explicitly not sync-proof.
- `calendarItemExternalIdentifier` may duplicate in some server-side scenarios and has Exchange caveats.
- `lastModifiedDate` is public, but its mutation coverage is not yet proven for this product.
- current repo output is insufficient for mirror canonicalization until the native lane adds source/provider metadata and the missing native fields listed above.

---

## 6. Validation Gates

Each gate below is mandatory.
The implementation may not silently assume a pass.

| Gate ID | Gate | Proof required | Pass effect | Fail effect |
|---|---|---|---|---|
| `G1` | Tag visibility gate | Prove a public supported path returns true reminder tag membership for target reminders. Note-body hashtags do not count. | Tag-based query families may ship through Shortcut acquisition. | All tag-based stories remain blocked pending validation. |
| `G2` | Hierarchy visibility gate | Prove a public supported path returns parent/child reminder relationships with enough fidelity for productivity diagnostics. | Hierarchy-based query families may ship through Shortcut acquisition. | All hierarchy and project-structure stories remain blocked pending validation. |
| `G3` | Shortcut identifier gate | Prove Shortcut payloads can carry `native_calendar_item_identifier` and/or `native_external_identifier` that deterministically join to EventKit objects. | Shortcut rows may be promoted to canonical mirror rows when other identity rules pass. | Single-contract semantic retrieval may still be exposed as low-confidence source-only data; any multi-contract join remains blocked. |
| `G4` | External-ID reliability gate | Validate `calendarItemExternalIdentifier` on the actual provider mix in scope, including collision behavior and provider caveats. | External identifier becomes the preferred canonical identity when present. | Mirror falls back to provider-scoped local IDs only; cross-run reconciliation is low confidence for affected providers. |
| `G5` | Last-modified reliability gate | Validate whether `lastModifiedDate` changes after title edit, notes edit, due-date edit, completion toggle, tag change, and child/parent structure edits where applicable. | Timestamp-based incremental sync and updated-at diagnostics may use native timestamps. | Incremental sync by modified timestamp is disabled; `shortcut.productivity_recently_updated.v1` becomes required if updated-at semantics are still needed. |

## 6.1 Gate-specific consequences

### If `G1` fails

Blocked stories:
- 1-10 except purely native date/list filtering logic
- 12-14
- 19-24
- 26-32
- 50

### If `G2` fails

Blocked stories:
- 11-17
- 19
- 22
- 26-27
- 31
- 50

### If `G3` fails

Allowed with low confidence:
- simple retrieval views from a single successful Shortcut contract, such as "show active projects" or "show waiting-ons"

Blocked pending validation:
- tag intersections
- joins between Shortcut contracts
- joins between Shortcut data and native data
- project-hygiene and hierarchy diagnostics that require canonical correlation

### If `G4` fails

Allowed:
- local-session retrieval
- full syncs

Disallowed or downgraded:
- external-ID canonical promotion for affected providers
- high-confidence cross-run merge assumptions for affected providers

### If `G5` fails

Disallowed:
- native timestamp-driven incremental sync
- native updated-at stale detection

Required:
- either use `created_at`-based diagnostics only
- or add `shortcut.productivity_recently_updated.v1`

---

## 7. Canonical Identity Model

## 7.1 Identity fields that must exist in the mirror

Every acquired reminder row must preserve:
- `source_kind`
- `source_scope_id`
- `calendar_id`
- `source_query_family`
- `contract_id` nullable
- `source_item_id`
- `native_calendar_item_identifier` nullable
- `native_external_identifier` nullable
- `identity_status`
- `canonical_id` nullable

`source_scope_id` is the provider/account scope.
For native EventKit sources it must be derived from `EKSource.sourceIdentifier`.

## 7.2 Identity statuses

The mirror must use one of these statuses:
- `canonical_external`
- `local_only_unstable`
- `shortcut_unresolved`
- `collision_unresolved`

## 7.3 Canonicalization rules

Rule 1:
If `native_external_identifier` is present and `G4` passed for that provider, the preferred canonical key is:

`external::<source_scope_id>::<native_external_identifier>`

Rule 2:
If the native row does not have a validated external identifier, but it does have `native_calendar_item_identifier`, the row may be stored with:

`local::<source_scope_id>::<native_calendar_item_identifier>`

and `identity_status = local_only_unstable`

Rule 3:
If a Shortcut row carries a native identifier and matches exactly one native row in the current sync, the Shortcut row may be promoted onto the canonical record for that native row.

Rule 4:
If a Shortcut row does not carry a joinable native identifier, it must be stored with:
- `identity_status = shortcut_unresolved`
- `canonical_id = null`

and it may not be joined to:
- native rows
- rows from other Shortcut contracts
- prior runs of the same contract

unless and until `G3` later passes and a deterministic upgrade path exists.

Rule 5:
If two or more live native rows share the same `(source_scope_id, native_external_identifier)`, the mirror must not auto-merge them.
Those rows must be marked:
- `identity_status = collision_unresolved`

Rule 6:
The system must never use fuzzy matching by:
- title
- notes
- due date
- list title
- priority
- tag text

for canonical identity.

## 7.4 Consequence for query behavior

- single-contract retrieval can use `shortcut_unresolved` rows with low confidence
- any derived view requiring joins across contracts or across source kinds requires canonical rows and is blocked when only unresolved rows exist

---

## 8. Shortcut Contract Layer

Shortcut acquisition is a public contract boundary for a separate team.
It must be treated like an API.

## 8.1 Global contract rules

Every Shortcut contract must be:
- fixed-purpose
- versioned
- read-only
- non-interactive
- deterministic
- JSON-only
- runnable from `shortcuts run`

Every contract must:
- take no runtime parameters in v1
- never require GUI interaction after installation
- never return plain text or rich text as the primary data format
- never use "zero items" as an implicit failure signal

The GTD system must reference:
- `contract_id`

and must not reference:
- the human Shortcut name

## 8.2 Adapter rule

The mirror/query layer owns a single adapter mapping:

| Contract ID | Deployed Shortcut Name |
|---|---|
| `shortcut.active_projects.v1` | `OC GTD: Active Projects` |
| `shortcut.next_actions.v1` | `OC GTD: Next Actions` |
| `shortcut.waiting_ons.v1` | `OC GTD: Waiting-Ons` |
| `shortcut.productivity_hierarchy.v1` | `OC GTD: Productivity Hierarchy` |
| `shortcut.productivity_recently_updated.v1` | `OC GTD: Productivity Recently Updated` |

Only the adapter is allowed to know deployed names.
Business logic must use contract IDs only.

Parallel-work rule:
- the Shortcut team may implement against the contract catalog without waiting for the mirror/query team
- the mirror/query team must implement against fixture payloads without waiting for live Shortcuts
- contract compatibility is measured only by the catalog, schemas, and fixtures in this spec

## 8.3 Invocation rule

Each contract is invoked via:

```bash
shortcuts run "<deployed-shortcut-name>" --output-path "$OUT" --output-type public.json
```

Rules:
- no input payload in v1
- output must be a single JSON document
- timestamps must be normalized to UTC ISO 8601 strings

## 8.4 Common envelope

Every contract must emit this envelope:

| Field | Type | Rule |
|---|---|---|
| `contract_id` | string | must match the requested contract ID |
| `contract_version` | string | must be `"v1"` for this spec |
| `generated_at` | string | required UTC ISO 8601 timestamp |
| `status` | enum | `ok`, `empty`, or `error` |
| `items` | array | required; empty only when `status` is `empty` or `error` |
| `warnings` | array | required; may be empty |
| `errors` | array | required; must be empty unless `status` is `error` |

`status` semantics:
- `ok`: the contract succeeded and returned one or more items
- `empty`: the contract succeeded and returned zero items
- `error`: the contract failed and returned zero items

## 8.5 Warning and error objects

Warnings and errors must use this shape:

| Field | Type | Rule |
|---|---|---|
| `code` | string | stable machine-readable code |
| `message` | string | human-readable explanation |
| `retryable` | boolean | required for errors; optional for warnings |

## 8.6 Common item shape

Every item in every required contract must include these fields.
Fields may be null only where explicitly stated.

| Field | Type | Null? | Notes |
|---|---|---|---|
| `source_item_id` | string | no | Shortcut-local identifier for this item. Never treated as canonical outside the contract unless `G3` passes. |
| `native_calendar_item_identifier` | string | yes | Preferred current-run local native join handle if the Shortcut can expose it. |
| `native_external_identifier` | string | yes | Preferred cross-run native join handle if the Shortcut can expose it. |
| `title` | string | no | Reminder title. |
| `notes` | string | yes | Reminder notes. |
| `list_title` | string | no | Human-visible list title. |
| `is_completed` | boolean | no | Actual completion state. |
| `priority` | enum | no | `none`, `low`, `medium`, `high`. |
| `due_at` | string | yes | UTC ISO 8601 timestamp, or null. |
| `created_at` | string | yes | UTC ISO 8601 timestamp, or null. |
| `updated_at` | string | yes | UTC ISO 8601 timestamp, or null. |
| `url` | string | yes | Item URL if public acquisition exposes it. |
| `matched_semantics` | array | no | Normalized semantic labels such as `active-project`, `next-action`, `waiting-on`. |
| `observed_tags` | array | yes | Normalized true tag names if the Shortcut can expose them; otherwise null. |

Additional rules:
- `matched_semantics` must use normalized lowercase values without `#`
- `observed_tags` must reflect true tag evidence only
- the Shortcut must not synthesize tags from title or notes
- item order must be deterministic
- default deterministic order is: `list_title`, `due_at` nulls last, `title`, `source_item_id`

## 8.7 Required contracts

### 8.7.1 `shortcut.active_projects.v1`

Purpose:
- return incomplete reminders that truly match `active-project`

Owner:
- Shortcut team

Required semantics:
- all items must include `matched_semantics` containing `active-project`
- completed reminders must not be emitted

Fixture files that must ship:
- `fixtures/shortcut.active_projects.v1.ok.json`
- `fixtures/shortcut.active_projects.v1.empty.json`
- `fixtures/shortcut.active_projects.v1.error.json`

### 8.7.2 `shortcut.next_actions.v1`

Purpose:
- return incomplete reminders that truly match `next-action`

Owner:
- Shortcut team

Required semantics:
- all items must include `matched_semantics` containing `next-action`
- completed reminders must not be emitted

Fixture files that must ship:
- `fixtures/shortcut.next_actions.v1.ok.json`
- `fixtures/shortcut.next_actions.v1.empty.json`
- `fixtures/shortcut.next_actions.v1.error.json`

### 8.7.3 `shortcut.waiting_ons.v1`

Purpose:
- return incomplete reminders that truly match `waiting-on`

Owner:
- Shortcut team

Required semantics:
- all items must include `matched_semantics` containing `waiting-on`
- completed reminders must not be emitted

Fixture files that must ship:
- `fixtures/shortcut.waiting_ons.v1.ok.json`
- `fixtures/shortcut.waiting_ons.v1.empty.json`
- `fixtures/shortcut.waiting_ons.v1.error.json`

### 8.7.4 `shortcut.productivity_hierarchy.v1`

Purpose:
- return hierarchy evidence for productivity-scope reminders
- return enough child membership to support project-hygiene diagnostics

Owner:
- Shortcut team

This contract must emit the common item fields plus:

| Field | Type | Null? | Notes |
|---|---|---|---|
| `parent_source_item_id` | string | yes | Parent within this contract payload, if any. |
| `child_source_item_ids` | array | no | Direct children within this contract payload. |

Additional rules:
- this contract may include completed parents if they are required to represent an inconsistent parent/child state
- child items may be included even when they are not tagged productivity items
- the payload must be sufficient to reconstruct parent/child edges without inference

Fixture files that must ship:
- `fixtures/shortcut.productivity_hierarchy.v1.ok.json`
- `fixtures/shortcut.productivity_hierarchy.v1.empty.json`
- `fixtures/shortcut.productivity_hierarchy.v1.error.json`

### 8.7.5 `shortcut.productivity_recently_updated.v1`

Purpose:
- provide a public Shortcut path for reliable productivity-scope update timestamps

Owner:
- Shortcut team

This contract is conditional.
It becomes required only if:
- `G5` fails for native `lastModifiedDate`
- or the semantic contracts above cannot reliably carry `updated_at`

Fixture files that must ship if the contract is activated:
- `fixtures/shortcut.productivity_recently_updated.v1.ok.json`
- `fixtures/shortcut.productivity_recently_updated.v1.empty.json`
- `fixtures/shortcut.productivity_recently_updated.v1.error.json`

## 8.8 Fixture templates

Every required contract must ship fixture payloads shaped like the templates below.

Minimal `ok` example:

```json
{
  "contract_id": "shortcut.active_projects.v1",
  "contract_version": "v1",
  "generated_at": "2026-03-20T12:00:00Z",
  "status": "ok",
  "items": [
    {
      "source_item_id": "shortcut-item-001",
      "native_calendar_item_identifier": null,
      "native_external_identifier": null,
      "title": "Launch billing cleanup",
      "notes": null,
      "list_title": "Work",
      "is_completed": false,
      "priority": "medium",
      "due_at": null,
      "created_at": "2026-03-01T09:00:00Z",
      "updated_at": "2026-03-18T08:15:00Z",
      "url": null,
      "matched_semantics": ["active-project"],
      "observed_tags": ["active-project"]
    }
  ],
  "warnings": [],
  "errors": []
}
```

Minimal `error` example:

```json
{
  "contract_id": "shortcut.active_projects.v1",
  "contract_version": "v1",
  "generated_at": "2026-03-20T12:00:00Z",
  "status": "error",
  "items": [],
  "warnings": [],
  "errors": [
    {
      "code": "shortcut_runtime_failure",
      "message": "The Shortcut could not complete successfully.",
      "retryable": true
    }
  ]
}
```

---

## 9. Mirror And Query Contract

## 9.1 Mirror is mandatory in v1

The mirror is not optional because v1 needs:
- provenance
- confidence
- freshness
- canonical identity promotion
- unresolved Shortcut row handling
- repeatable query views for David

## 9.2 Mirror storage responsibilities

The mirror must store:
- native reminder snapshots
- Shortcut acquisition rows
- canonical reminder rows
- unresolved Shortcut rows
- relationship rows
- sync run metadata
- local annotations

## 9.3 Minimum conceptual datasets

The implementation must have the equivalent of these datasets:
- `native_reminders`
- `shortcut_contract_runs`
- `shortcut_items`
- `canonical_reminders`
- `unresolved_shortcut_items`
- `reminder_relationships`
- `sync_runs`
- `local_annotations`

This spec does not lock table names, but it does lock responsibilities.

## 9.4 Promotion rules

The mirror/query layer must:
- ingest every successful native row
- ingest every successful Shortcut row
- promote only deterministically joinable rows into canonical reminder records
- preserve unresolved rows instead of dropping them

## 9.5 Query result contract

Every David-facing query result must include:
- `confidence`
- `freshness`
- `acquisition_sources`
- `identity_status`

`confidence` levels:
- `high`
- `medium`
- `low`

Required behavior:
- single-contract retrieval from unresolved Shortcut rows must return `low` confidence
- multi-contract or multi-source views must not silently omit unresolved rows and pretend the result is complete
- if a derived view requires canonical joins and those joins are unavailable, the query must return explicit low confidence or unsupported status rather than a false clean result

---

## 10. V1 Support Matrix

This matrix covers:
- v1 core stories 1-50 from `user-stories-0.0.1`

Stories 51-90 remain later-scope work and are not required for v1 delivery.

| Stories | Capability | Class | Required path | Blocked if |
|---|---|---|---|---|
| 1 | Active projects retrieval | `shortcut-required` | `shortcut.active_projects.v1` | `G1` fails |
| 2 | Next actions retrieval | `shortcut-required` | `shortcut.next_actions.v1` | `G1` fails |
| 3-4 | Waiting-ons retrieval and follow-up age views | `shortcut-required` | `shortcut.waiting_ons.v1` with timestamps | `G1` fails |
| 5 | Active projects stale-by-age retrieval | `shortcut-required` | `shortcut.active_projects.v1` with `updated_at` | `G1` fails |
| 6-9 | Date/list filtered next-action views | `shortcut-required` | `shortcut.next_actions.v1` | `G1` fails |
| 10 | Multi-tag intersections and tag-derived set intersections | `blocked pending validation` | canonical join across semantic sets | `G1` or `G3` fails |
| 11 | Parent-child retrieval | `shortcut-required` | `shortcut.productivity_hierarchy.v1` | `G2` fails |
| 12-17 | Project structure diagnostics | `blocked pending validation` | hierarchy plus canonical semantic correlation | `G2` or `G3` fails |
| 18 | Old vague tasks by age and wording | `native+mirror` | native timestamps, title, notes | native timestamp wiring missing |
| 19 | Active projects older than 14 days with no next-action child | `blocked pending validation` | semantic plus hierarchy join | `G1`, `G2`, or `G3` fails |
| 20-21 | Waiting-on and next-action hygiene checks from their own semantic slices | `shortcut-required` | single semantic contract plus notes/title heuristics | `G1` fails |
| 22 | Active projects with no recent child-task updates | `blocked pending validation` | hierarchy plus child updated-at evidence | `G2`, `G3`, or `G5` fails |
| 23 | Project-shaped reminders missing `active-project` tag | `blocked pending validation` | full inventory plus tag-absence proof | `G1` fails |
| 24 | `active-project` items that look like single actions | `shortcut-required` | `shortcut.active_projects.v1` plus wording heuristics | `G1` fails |
| 25 | Old incomplete reminders with empty notes | `native+mirror` | native timestamps and notes | native timestamp wiring missing |
| 26-27 | Weekly review joins across active projects, next actions, waiting-ons, and child structure | `blocked pending validation` | canonical multi-source correlation | `G1`, `G2`, or `G3` fails |
| 28-30 | Grouped planning views from a single semantic slice | `shortcut-required` | corresponding single semantic contract | `G1` fails |
| 31 | Project-health grouping | `blocked pending validation` | hierarchy plus canonical semantic joins | `G1`, `G2`, or `G3` fails |
| 32 | Delegation candidate detection | `blocked pending validation` | broad canonical candidate set not provided by one fixed contract | `G3` fails or broader acquisition not added |
| 33 | Ingest specialized Shortcut results into mirror | `shortcut-required` | contract catalog and mirror ingestion | contract catalog not implemented |
| 34-36 | Store normalized data, sync metadata, and run full sync | `native+mirror` | native lane plus mirror | mirror not implemented |
| 37-38 | Incremental sync by trusted changes | `blocked pending validation` | validated identity and timestamp behavior | `G4` or `G5` fails |
| 39-40 | Local annotations, source confidence, freshness | `native+mirror` | mirror metadata | mirror not implemented |
| 41-42 | Explicit confidence and zero-results-vs-failure handling | `native+mirror` | query layer with source-aware statuses | mirror/query not implemented |
| 43 | Reject malformed or partial Shortcut payloads | `shortcut-required` | contract schema validation | contract schema not enforced |
| 44-45 | Record acquisition path and expose stale/failed sync runs | `native+mirror` | provenance and sync-run storage | mirror not implemented |
| 46-47 | Separate retrieval from diagnostics and define stable JSON schema | `native+mirror` | mirror/query contracts | mirror/query not implemented |
| 48 | Specialized narrow Shortcut contracts | `shortcut-required` | contract catalog in this spec | Shortcut team diverges from catalog |
| 49 | Explicit productivity query-family documentation | `native+mirror` | this spec plus query-layer docs | n/a |
| 50 | "Active projects with no subtasks or with subtasks without tags" | `blocked pending validation` | hierarchy plus tag plus canonical joins | `G1`, `G2`, or `G3` fails |

Later stories 51-90:
- remain out of v1 scope
- require snapshotting, analytics, cadence metrics, and trend storage beyond the scope locked in this document

---

## 11. Required Cross-Team Behaviors

## 11.1 Native team deliverables

The native lane must expose:
- `calendarItemIdentifier`
- `calendarItemExternalIdentifier`
- `creationDate`
- `lastModifiedDate`
- `URL`
- `EKSource.sourceIdentifier`
- `calendarIdentifier`
- list title
- completion state and completion date
- due date
- priority
- notes
- title

## 11.2 Shortcut team deliverables

The Shortcut team must deliver:
- the contract catalog in Section 8
- schema-valid JSON output
- `ok`, `empty`, and `error` behavior
- deterministic item ordering
- fixture payloads for every implemented contract
- no contract-level dependency on mirror implementation details

## 11.3 Mirror/query team deliverables

The mirror/query lane must deliver:
- adapter mapping contract IDs to deployed Shortcut names
- contract schema validation
- unresolved-row storage
- canonical promotion rules from Section 7
- confidence and freshness metadata on every query result
- fixture-first ingestion and validation so core work can proceed before live Shortcuts exist

## 11.4 David lane deliverables

The David lane must deliver:
- stale/vague/delegation logic only on normalized query views
- no raw Shortcut parsing
- no canonical join logic
- no semantic fallback for missing tags or hierarchy

---

## 12. Risk Register

| Risk | Severity | Consequence | Required mitigation |
|---|---|---|---|
| `calendarItemIdentifier` changes after full sync | high | broken joins and stale references | never use it as the preferred canonical identity |
| `calendarItemExternalIdentifier` duplicates or provider caveats | high | accidental over-merge | provider-scoped canonical keys and collision handling |
| Public native path does not expose true tags | high | semantic retrieval blocked | ship fixed Shortcut contracts |
| Public native path does not expose hierarchy | high | project-hygiene diagnostics blocked | ship hierarchy contract or keep views blocked |
| Shortcut payloads omit native identifiers | high | no canonical promotion | allow low-confidence source-only retrieval; block joins |
| `lastModifiedDate` is not reliable enough | medium | broken incremental sync and stale logic | gate `G5` and activate conditional recent-updated Shortcut if needed |
| Shortcut team and core team drift on payload shape | high | integration failure in parallel work | fixed contract catalog plus fixture payloads |
| Zero-result sets are confused with failures | high | false clean-system conclusions | explicit `status = empty` vs `status = error` |
| Temptation to infer tags from titles or notes | high | false GTD semantics | explicitly prohibited by this spec |

---

## 13. Test Plan And Acceptance Criteria

## 13.1 Native verification

Before implementation is considered correct, verify:
- native capability claims in this spec match the actual EventKit headers and live behavior
- `creationDate`, `lastModifiedDate`, and `calendarItemExternalIdentifier` are wired into the native acquisition model
- provider scope is captured via `EKSource.sourceIdentifier`

## 13.2 Contract acceptance checks

Every required contract must pass:
- schema-valid output
- deterministic item ordering
- explicit `ok`, `empty`, and `error` behavior
- timestamp normalization to UTC ISO 8601
- required keys always present, even when nullable
- fixture payloads present for `ok`, `empty`, and `error`

## 13.3 Validation scenarios

The combined system must explicitly test:
- can a Shortcut item be promoted to a canonical mirror row when both native IDs are present
- what happens when the Shortcut succeeds but emits no native identifiers
- what happens when hierarchy data exists without canonical IDs
- what confidence is returned when a single semantic contract succeeded but canonicalization failed
- what confidence is returned when a join-based view is requested but unresolved rows prevent correlation
- whether `lastModifiedDate` changes after title, notes, due-date, completion, tag, and hierarchy-relevant edits

## 13.4 Acceptance criteria for `spec-0.9.0`

This spec is considered implementation-ready only if:
- each v1 story group has a support classification
- all required Shortcut contracts are named and scoped
- canonical ID rules are explicit
- gate failure behavior is explicit
- unresolved Shortcut rows have defined storage and query behavior
- no major cross-team interface decision is left open

---

## 14. Non-Goals

This version does not allow:
- direct reads from the private Reminders database
- fuzzy canonical joins
- note-body hashtag fallback when true tag evidence is missing
- title-only or notes-only fallback for parent/child structure
- a generic parameterized Shortcut query engine
- David consuming raw Shortcut payloads directly
- business logic depending on deployed Shortcut names
- silent degradation from missing semantics to guessed semantics

---

## 15. Changelog

### 0.9.0
- converted the early product draft into an implementation-bridge spec
- grounded the design in the current repository state
- separated native, Shortcut, mirror/query, and David boundaries
- made mirror-state mandatory in phase one
- defined validation gates for tags, hierarchy, identifiers, external IDs, and timestamps
- locked canonical identity rules and prohibited fuzzy joins
- defined a fixed Shortcut contract catalog for parallel implementation
- mapped v1 core story groups to implementation classes and failure conditions
