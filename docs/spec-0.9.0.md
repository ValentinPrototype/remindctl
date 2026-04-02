# spec-0.9.0

**Document Type:** Software Design Description (SDD)  
**Version:** 0.9.0  
**Status:** Draft  
**Project:** `remindctl-gtd`  
**Owners:** Valentin / Prometheus / David  
**Primary Audience:** Native/EventKit team, Shortcut team, mirror/query team, David-layer team

---

## 1. Introduction

### 1.1 Purpose

This document defines the software design for `remindctl-gtd`, a hard fork of the current `remindctl` repository for GTD-oriented Apple Reminders retrieval, normalization, and query support.

The purpose of this SDD is to:
- describe the target system structure
- define subsystem boundaries and responsibilities
- specify cross-team interfaces
- lock identity, confidence, and validation behavior
- remove design ambiguity before implementation proceeds in parallel

### 1.2 Scope

This document covers v1 design for:
- native Apple Reminders acquisition through EventKit
- Shortcut-based semantic acquisition for GTD-specific reminder slices
- local mirror/query storage and canonicalization
- David-facing query outputs for productivity review workflows

This document does not cover:
- a private Reminders database integration
- long-range analytics and scoreboards
- write automation beyond the current generic CLI scope
- implementation detail below the level needed for parallel subsystem work

### 1.3 Definitions, Acronyms, and Abbreviations

- **David**: the productivity specialist consumer of normalized query views
- **GTD**: Getting Things Done style productivity semantics
- **SDD**: Software Design Description
- **EventKit**: Apple's public reminders/calendar framework on macOS
- **Mirror**: the local normalized store used by `remindctl-gtd`
- **Canonical row**: a mirror record whose identity has been deterministically established
- **Unresolved Shortcut row**: a Shortcut-acquired row that contains useful semantics but cannot be promoted to a canonical row because identity proof is missing
- **Contract ID**: the stable machine name used by core logic to refer to a Shortcut acquisition contract
- **Validation gate**: an explicit proof checkpoint that must pass before a capability is assumed in production logic

### 1.4 References

This SDD is based on:
- [docs/spec-0.1.0.md](/Users/vk/work/openclaw/remindctl/docs/spec-0.1.0.md)
- [docs/user-stories-0.0.1.md](/Users/vk/work/openclaw/remindctl/docs/user-stories-0.0.1.md)
- current repository implementation in [Sources/RemindCore/EventKitStore.swift](/Users/vk/work/openclaw/remindctl/Sources/RemindCore/EventKitStore.swift)
- current repository reminder model in [Sources/RemindCore/Models.swift](/Users/vk/work/openclaw/remindctl/Sources/RemindCore/Models.swift)
- verified local EventKit headers from the macOS SDK available in this environment

### 1.5 Document Overview

The document is organized as follows:
- Section 2 describes the current system baseline and the target product shape.
- Section 3 defines design constraints and locked assumptions.
- Section 4 defines the architectural decomposition.
- Section 5 defines data design, including canonical identity.
- Section 6 defines interface design, including the Shortcut contract catalog.
- Section 7 defines runtime behavior, validation gates, and confidence handling.
- Section 8 traces requirements to implementation classes and dependencies.
- Section 9 defines verification and acceptance criteria.
- Section 10 records risks and rationale.

---

## 2. System Overview

### 2.1 Current Repository Baseline

The current repository is a generic Apple Reminders CLI built on EventKit.

The current implementation supports:
- reminders permission handling
- list enumeration
- list create, rename, and delete
- reminder create, update, complete, and delete
- reminder retrieval with date-oriented filters such as `today`, `tomorrow`, `week`, `overdue`, `upcoming`, `completed`, and `all`
- JSON, plain-text, standard, and quiet output formats

The current implementation does not support:
- Shortcut integration
- a local mirror or SQLite
- tag extraction
- parent/child reminder extraction
- GTD-specific semantic retrieval
- confidence and freshness reporting
- canonical identity beyond the local CRUD CLI use of `calendarItemIdentifier`

### 2.2 Current Public Reminder Model

The current public reminder model is `ReminderItem`.

Current fields:
- `id`
- `title`
- `notes`
- `isCompleted`
- `completionDate`
- `priority`
- `dueDate`
- `listID`
- `listName`

Current JSON output is simply the serialized `ReminderItem` payload.
It is not a stable GTD schema and is not sufficient as the mirror canonical form for `remindctl-gtd`.

### 2.3 Target Product Shape

`remindctl-gtd` is not just a prettier wrapper around Reminders.
It is a productivity-oriented retrieval and query system whose primary consumer is David.

The target product must support:
- retrieval of semantic sets such as active projects, next actions, and waiting-ons
- normalized local state for repeated queries and correlation
- productivity diagnostics such as stale work, weak project structure, and missing next actions
- explicit confidence reporting when the acquisition surface is weak or incomplete

### 2.4 Stakeholders and Parallel Teams

The design assumes parallel implementation across these lanes:
- native/EventKit team
- Shortcut team
- mirror/query team
- David-layer team

The design must therefore specify:
- strict ownership boundaries
- strict contract boundaries
- strict rules for what may and may not be inferred

---

## 3. Design Constraints and Assumptions

### 3.1 Locked Product Decisions

The following decisions are normative:
- `remindctl-gtd` is a hard fork from the current generic CLI direction.
- Mirror-state is phase-one core.
- True GTD semantics must come from public acquisition evidence.
- No semantic fallback from title or notes is allowed when true tags or hierarchy are missing.
- No private Reminders database access is allowed.
- No generic highly-parameterized Shortcut query engine is allowed in v1.
- Business logic must refer to Shortcut contract IDs, never human Shortcut names.
- Canonical identity must never be established by fuzzy matching on title, notes, due date, list, or tag text.

### 3.2 Platform Constraints

The design is constrained by public Apple surfaces:
- EventKit is the native acquisition API.
- the `shortcuts` command-line tool is the execution path for deployed Shortcuts
- the product must tolerate the possibility that some useful Reminders app features are not fully exposed through EventKit or Shortcut payloads

### 3.3 Design Assumptions

The design assumes:
- macOS-local execution
- Apple Reminders as the execution-state source of truth
- Obsidian productivity notes as the workflow-definition source of truth
- the Shortcut team can implement fixed read-only contracts in parallel
- the mirror/query team can build against fixture payloads before live Shortcuts exist

### 3.4 Explicit Non-Goals

This design does not permit:
- direct reads from the private Reminders app database
- note-body hashtag fallback for GTD semantics
- title-only or note-only fallback for hierarchy
- silent degradation from missing semantics to guessed semantics
- business logic that depends on deployed Shortcut names

---

## 4. Architectural Design

### 4.1 Architectural Context

The system is decomposed into four major subsystems:
- Native acquisition subsystem
- Shortcut acquisition subsystem
- Mirror/query subsystem
- David consumption subsystem

### 4.2 Subsystem Decomposition

#### 4.2.1 Native Acquisition Subsystem

Responsibilities:
- permissions
- public EventKit retrieval
- public EventKit mutation where applicable
- authoritative native identifier capture
- provider and calendar metadata capture
- native field reliability validation

Native acquisition does not own:
- GTD semantics
- Shortcut contract execution
- canonical promotion policy beyond emitting authoritative native evidence
- David judgment logic

#### 4.2.2 Shortcut Acquisition Subsystem

Responsibilities:
- fixed-purpose semantic retrieval contracts
- fixed-purpose hierarchy retrieval contract
- deterministic JSON output
- explicit success, empty, and failure signaling
- fixture payloads for contract consumers

Shortcut acquisition does not own:
- canonical identity joins
- mirror schema
- productivity diagnostics
- deployed Shortcut name lookup outside the adapter boundary

#### 4.2.3 Mirror/Query Subsystem

Responsibilities:
- normalized storage
- canonical identity promotion
- unresolved Shortcut row retention
- provenance, freshness, and confidence metadata
- derived query views for David
- the adapter layer that maps contract IDs to deployed Shortcut names

Mirror/query does not own:
- raw EventKit retrieval mechanics
- Shortcut UI implementation
- end-user productivity judgment

#### 4.2.4 David Consumption Subsystem

Responsibilities:
- interpretation of normalized query views
- stale, vague, missing-next-action, and delegation reasoning
- review-oriented outputs that include confidence

David does not own:
- raw acquisition
- raw Shortcut payload parsing
- canonical identity
- semantic fallback when tags or hierarchy are missing

### 4.3 Boundary Rules

The following boundary rules are normative:
- retrieval belongs to native/EventKit or Shortcut acquisition
- normalization belongs to mirror/query
- productivity judgment belongs to David
- no subsystem may silently infer missing identity, tags, or hierarchy

### 4.4 High-Level Runtime Flow

#### 4.4.1 Native Sync Flow

1. Native acquisition requests Reminders access.
2. Native acquisition fetches public EventKit fields and provider scope.
3. Native rows are written to the mirror.
4. Mirror/query evaluates canonical identity from native identifiers.

#### 4.4.2 Shortcut Ingest Flow

1. Mirror/query requests a contract by contract ID.
2. Adapter resolves the deployed Shortcut name.
3. The contract is executed through `shortcuts run`.
4. Output is schema-validated.
5. Rows are written either as canonical enrichments or unresolved Shortcut rows depending on identity evidence.

#### 4.4.3 David Query Flow

1. David requests a normalized query view.
2. Mirror/query resolves the query from canonical and unresolved rows as permitted by policy.
3. Mirror/query attaches confidence, freshness, and acquisition provenance.
4. David applies interpretation logic only to the normalized result.

---

## 5. Data Design

### 5.1 Native Capability Baseline

Based on the current repository and verified local EventKit headers, the public native capability surface is as follows:

| Capability | Public EventKit status | Current repo status | Design classification |
|---|---|---|---|
| List enumeration | supported | implemented | native-supported |
| List create, rename, delete | supported | implemented | native-supported |
| Fetch reminders in calendars | supported | implemented | native-supported |
| Fetch incomplete reminders by due-date range | supported | not wired in repo | native-supported after native lane work |
| Fetch completed reminders by completion-date range | supported | not wired in repo | native-supported after native lane work |
| `calendarItemIdentifier` | supported | implemented | local lookup handle only |
| `calendarItemExternalIdentifier` | supported | not exposed in repo | preferred canonical identity when validated |
| `creationDate` | supported | not exposed in repo | native acquisition field |
| `lastModifiedDate` | supported | not exposed in repo | native acquisition field, gated |
| `URL` | supported | not exposed in repo | native acquisition field |
| `EKSource.sourceIdentifier` | supported | not exposed in repo | required provider scope field |
| Title, notes, due date, completion date, priority | supported | implemented | native acquisition fields |
| True reminder tags | unproven for this product | not implemented | do not assume; use gate |
| Parent/child reminder structure | unproven for this product | not implemented | do not assume; use gate |
| Flagged state | not present in verified public headers used here | not implemented | unsupported for v1 |

### 5.2 Canonical Identity Model

#### 5.2.1 Identity Fields

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

For native EventKit sources:
- `source_scope_id` must be derived from `EKSource.sourceIdentifier`

#### 5.2.2 Identity Status Values

Allowed values:
- `canonical_external`
- `local_only_unstable`
- `shortcut_unresolved`
- `collision_unresolved`

#### 5.2.3 Canonicalization Rules

Rule 1:
If `native_external_identifier` is present and validated for the provider, the preferred canonical key is:

`external::<source_scope_id>::<native_external_identifier>`

Rule 2:
If no validated external identifier exists but `native_calendar_item_identifier` exists, the row may be stored with:

`local::<source_scope_id>::<native_calendar_item_identifier>`

and `identity_status = local_only_unstable`

Rule 3:
If a Shortcut row carries a native identifier and matches exactly one native row in the current sync, the Shortcut row may be promoted onto that canonical record.

Rule 4:
If a Shortcut row does not carry a deterministic native join handle, it must be stored as:
- `identity_status = shortcut_unresolved`
- `canonical_id = null`

Rule 5:
If two or more live native rows share the same `(source_scope_id, native_external_identifier)`, the mirror must not auto-merge them.
Those rows must be marked `collision_unresolved`.

Rule 6:
The system must never use fuzzy matching by:
- title
- notes
- due date
- list title
- priority
- tag text

for canonical identity.

### 5.3 Mirror Logical Data Sets

The mirror must contain the equivalent of these logical data sets:
- `native_reminders`
- `shortcut_contract_runs`
- `shortcut_items`
- `canonical_reminders`
- `unresolved_shortcut_items`
- `reminder_relationships`
- `sync_runs`
- `local_annotations`

Table names are not fixed by this document.
Responsibilities are fixed.

### 5.4 Canonical Reminder Core

The canonical reminder model must include at minimum:
- canonical identity fields
- native identity fields
- title
- notes
- list identity and list title
- completion state and completion date
- priority
- due timestamp
- created timestamp
- updated timestamp
- URL if available
- provenance to the producing source and sync run

### 5.5 Query Result Metadata

Every David-facing query result must carry:
- `confidence`
- `freshness`
- `acquisition_sources`
- `identity_status`

Allowed confidence values:
- `high`
- `medium`
- `low`

---

## 6. Interface Design

### 6.1 Native Acquisition Interface

#### 6.1.1 Required Native Output Fields

The native lane must expose:
- `calendarItemIdentifier`
- `calendarItemExternalIdentifier`
- `creationDate`
- `lastModifiedDate`
- `URL`
- `EKSource.sourceIdentifier`
- `calendarIdentifier`
- list title
- title
- notes
- priority
- due date
- completion state
- completion date

#### 6.1.2 Native Query Boundary

The native lane may answer:
- list-oriented retrieval
- date-oriented retrieval
- completion-oriented retrieval
- wording heuristics that do not depend on GTD tags or hierarchy
- freshness questions based on native sync evidence

The native lane may not claim:
- true `active-project`, `next-action`, or `waiting-on` semantics
- parent/child project structure
- tag intersections
- untagged child diagnostics
- project-missing-next-action diagnostics

unless a public supported path is proven and promoted through the validation gates in Section 7.

### 6.2 Shortcut Contract Interface

Shortcut acquisition is a public API boundary for a separate team.

#### 6.2.1 Global Contract Rules

Every Shortcut contract must be:
- fixed-purpose
- versioned
- read-only
- non-interactive
- deterministic
- JSON-only
- runnable via `shortcuts run`

Every contract must:
- take no runtime parameters in v1
- never require GUI interaction after installation
- never return plain text or rich text as the primary data format
- never use zero items as an implicit failure signal

Core business logic must reference:
- `contract_id`

Core business logic must not reference:
- deployed Shortcut names

#### 6.2.2 Adapter Mapping

The mirror/query subsystem owns the only mapping from contract IDs to deployed Shortcut names:

| Contract ID | Deployed Shortcut Name |
|---|---|
| `shortcut.active_projects.v1` | `OC GTD: Active Projects` |
| `shortcut.next_actions.v1` | `OC GTD: Next Actions` |
| `shortcut.waiting_ons.v1` | `OC GTD: Waiting-Ons` |
| `shortcut.productivity_hierarchy.v1` | `OC GTD: Productivity Hierarchy` |
| `shortcut.productivity_recently_updated.v1` | `OC GTD: Productivity Recently Updated` |

Parallel implementation rule:
- the Shortcut team may implement against the contract catalog without waiting for mirror/query work
- the mirror/query team must implement against contract fixtures without waiting for live Shortcuts
- compatibility is measured by contract IDs, schemas, and fixture payloads only

#### 6.2.3 Invocation Interface

Each contract is invoked as:

```bash
shortcuts run "<deployed-shortcut-name>" --output-path "$OUT" --output-type public.json
```

Rules:
- no input payload in v1
- output must be a single JSON document
- all timestamps must be UTC ISO 8601 strings

#### 6.2.4 Common Contract Envelope

Every contract must emit:

| Field | Type | Rule |
|---|---|---|
| `contract_id` | string | must match the requested contract |
| `contract_version` | string | must be `"v1"` |
| `generated_at` | string | required UTC ISO 8601 timestamp |
| `status` | enum | `ok`, `empty`, or `error` |
| `items` | array | required; empty only for `empty` or `error` |
| `warnings` | array | required |
| `errors` | array | required |

`status` semantics:
- `ok`: execution succeeded and returned one or more items
- `empty`: execution succeeded and returned zero items
- `error`: execution failed and returned zero items

#### 6.2.5 Warning and Error Object Interface

Warnings and errors must use:

| Field | Type | Rule |
|---|---|---|
| `code` | string | stable machine-readable code |
| `message` | string | human-readable explanation |
| `retryable` | boolean | required for errors; optional for warnings |

#### 6.2.6 Common Item Interface

Every item in every required contract must include:

| Field | Type | Nullable | Rule |
|---|---|---|---|
| `source_item_id` | string | no | Shortcut-local identifier only |
| `native_calendar_item_identifier` | string | yes | current-run native join handle if exposed |
| `native_external_identifier` | string | yes | preferred cross-run join handle if exposed |
| `title` | string | no | reminder title |
| `notes` | string | yes | reminder notes |
| `list_title` | string | no | human-visible list title |
| `is_completed` | boolean | no | true completion state |
| `priority` | enum | no | `none`, `low`, `medium`, `high` |
| `due_at` | string | yes | UTC ISO 8601 or null |
| `created_at` | string | yes | UTC ISO 8601 or null |
| `updated_at` | string | yes | UTC ISO 8601 or null |
| `url` | string | yes | reminder URL if publicly available |
| `matched_semantics` | array | no | normalized semantic labels |
| `observed_tags` | array | yes | normalized true tag values only |

Additional interface rules:
- `matched_semantics` must use lowercase normalized values without `#`
- `observed_tags` must represent true tag evidence only
- the Shortcut must not infer tags from titles or notes
- item order must be deterministic
- default deterministic order is `list_title`, `due_at` nulls last, `title`, `source_item_id`

#### 6.2.7 Contract Catalog

##### `shortcut.active_projects.v1`

Purpose:
- return incomplete reminders that truly match `active-project`

Required semantics:
- every item must contain `active-project` in `matched_semantics`
- completed reminders must not be emitted

Required fixtures:
- `fixtures/shortcut.active_projects.v1.ok.json`
- `fixtures/shortcut.active_projects.v1.empty.json`
- `fixtures/shortcut.active_projects.v1.error.json`

##### `shortcut.next_actions.v1`

Purpose:
- return incomplete reminders that truly match `next-action`

Required semantics:
- every item must contain `next-action` in `matched_semantics`
- completed reminders must not be emitted

Required fixtures:
- `fixtures/shortcut.next_actions.v1.ok.json`
- `fixtures/shortcut.next_actions.v1.empty.json`
- `fixtures/shortcut.next_actions.v1.error.json`

##### `shortcut.waiting_ons.v1`

Purpose:
- return incomplete reminders that truly match `waiting-on`

Required semantics:
- every item must contain `waiting-on` in `matched_semantics`
- completed reminders must not be emitted

Required fixtures:
- `fixtures/shortcut.waiting_ons.v1.ok.json`
- `fixtures/shortcut.waiting_ons.v1.empty.json`
- `fixtures/shortcut.waiting_ons.v1.error.json`

##### `shortcut.productivity_hierarchy.v1`

Purpose:
- return hierarchy evidence for productivity-scope reminders
- return enough child membership to support project-hygiene diagnostics

This contract must additionally include:

| Field | Type | Nullable | Rule |
|---|---|---|---|
| `parent_source_item_id` | string | yes | parent within the payload |
| `child_source_item_ids` | array | no | direct children within the payload |

Additional rules:
- completed parents may be included when required to express inconsistent states
- untagged children may be included when needed for project diagnostics
- the payload must be sufficient to reconstruct parent/child edges without inference

Required fixtures:
- `fixtures/shortcut.productivity_hierarchy.v1.ok.json`
- `fixtures/shortcut.productivity_hierarchy.v1.empty.json`
- `fixtures/shortcut.productivity_hierarchy.v1.error.json`

##### `shortcut.productivity_recently_updated.v1`

Purpose:
- provide a public Shortcut path for reliable productivity-scope update timestamps

Activation rule:
- required only if native `lastModifiedDate` fails validation or the semantic contracts cannot reliably provide `updated_at`

Required fixtures if activated:
- `fixtures/shortcut.productivity_recently_updated.v1.ok.json`
- `fixtures/shortcut.productivity_recently_updated.v1.empty.json`
- `fixtures/shortcut.productivity_recently_updated.v1.error.json`

### 6.3 Mirror/Query Internal Interface

The mirror/query subsystem must expose internal interfaces for:
- native row ingestion
- Shortcut contract run ingestion
- contract schema validation
- canonical promotion
- unresolved row retention
- normalized query views

Required mirror/query behaviors:
- ingest every successful native row
- ingest every successful Shortcut row
- promote only deterministically joinable rows
- preserve unresolved Shortcut rows instead of dropping them
- attach provenance, freshness, and identity status to query outputs

### 6.4 David-Facing Query Interface

The David-facing query interface must consume normalized views only.

David-facing outputs must not:
- parse raw Shortcut payloads
- perform canonical joins
- infer tags from note text
- infer hierarchy from title structure

David-facing outputs must:
- include confidence
- include freshness
- include acquisition provenance
- degrade explicitly when identity or acquisition is incomplete

---

## 7. Behavioral Design

### 7.1 Validation Gates

Each gate in this section is mandatory.
The implementation may not silently assume a pass.

| Gate ID | Gate | Proof Required | Pass Effect | Fail Effect |
|---|---|---|---|---|
| `G1` | Tag visibility gate | prove a public supported path returns true reminder tag membership; note-body hashtags do not count | tag-based stories may ship | all tag-based stories remain blocked pending validation |
| `G2` | Hierarchy visibility gate | prove a public supported path returns parent/child relationships with sufficient fidelity | hierarchy-based stories may ship | all hierarchy stories remain blocked pending validation |
| `G3` | Shortcut identifier gate | prove Shortcut payloads can carry deterministic native identifiers for EventKit joins | Shortcut rows may be promoted to canonical rows | only single-contract low-confidence retrieval is allowed; joins remain blocked |
| `G4` | External-ID reliability gate | validate `calendarItemExternalIdentifier` on the real provider mix, including collision behavior | external identifier becomes the preferred canonical identity | fallback to provider-scoped local IDs only |
| `G5` | Last-modified reliability gate | validate `lastModifiedDate` mutation coverage for this product's required edits | native incremental sync and updated-at diagnostics may use native timestamps | native updated-at logic is disabled and the conditional recent-updated contract may become required |

### 7.2 Gate Consequence Behavior

#### If `G1` fails

Blocked:
- all tag-based semantic retrieval
- tag intersections
- tag absence diagnostics
- any project-health view that depends on semantic tags

#### If `G2` fails

Blocked:
- parent/child retrieval
- missing-next-action child diagnostics
- no-subtask and untagged-subtask diagnostics
- hierarchy-aware project-health views

#### If `G3` fails

Allowed:
- single-contract semantic retrieval from unresolved Shortcut rows with low confidence

Blocked:
- joins between Shortcut contracts
- joins between Shortcut data and native data
- canonical project-hygiene diagnostics

#### If `G4` fails

Allowed:
- full syncs
- provider-scoped local usage

Downgraded or blocked:
- high-confidence cross-run merge assumptions for affected providers

#### If `G5` fails

Disallowed:
- native updated-at stale logic
- native timestamp-driven incremental sync

Required:
- either rely on created-at-only logic where acceptable
- or activate `shortcut.productivity_recently_updated.v1`

### 7.3 Confidence and Failure Behavior

Confidence policy is normative:
- unresolved single-contract semantic retrieval must return `low` confidence
- multi-source or multi-contract views must not silently omit unresolved rows and pretend completeness
- when a requested derived view requires joins that are not available, the system must return low confidence or explicit unsupported status instead of a false clean result

### 7.4 Query Class Behavior

The implementation shall use these design classes:
- `native-supported`
- `native+mirror`
- `shortcut-required`
- `blocked pending validation`

These classes are used for requirements traceability in Section 8.

---

## 8. Requirements Traceability

### 8.1 V1 Story Mapping

This section maps v1 core stories 1-50 from `user-stories-0.0.1` to design classes.

Stories 51-90 remain outside v1 scope.

| Stories | Capability | Class | Required Path | Blocked If |
|---|---|---|---|---|
| 1 | Active projects retrieval | `shortcut-required` | `shortcut.active_projects.v1` | `G1` fails |
| 2 | Next actions retrieval | `shortcut-required` | `shortcut.next_actions.v1` | `G1` fails |
| 3-4 | Waiting-ons retrieval and follow-up age views | `shortcut-required` | `shortcut.waiting_ons.v1` with timestamps | `G1` fails |
| 5 | Active projects stale-by-age retrieval | `shortcut-required` | `shortcut.active_projects.v1` with `updated_at` | `G1` fails |
| 6-9 | Date/list filtered next-action views | `shortcut-required` | `shortcut.next_actions.v1` | `G1` fails |
| 10 | Multi-tag intersections | `blocked pending validation` | canonical joins across semantic sets | `G1` or `G3` fails |
| 11 | Parent-child retrieval | `shortcut-required` | `shortcut.productivity_hierarchy.v1` | `G2` fails |
| 12-17 | Project structure diagnostics | `blocked pending validation` | hierarchy plus canonical semantic correlation | `G2` or `G3` fails |
| 18 | Old vague tasks by age and wording | `native+mirror` | native timestamps, title, notes | native timestamp wiring missing |
| 19 | Active projects older than 14 days with no next-action child | `blocked pending validation` | semantic plus hierarchy join | `G1`, `G2`, or `G3` fails |
| 20-21 | Waiting-on and next-action hygiene checks from their own semantic slices | `shortcut-required` | single semantic contract plus notes/title heuristics | `G1` fails |
| 22 | Active projects with no recent child updates | `blocked pending validation` | hierarchy plus child updated-at evidence | `G2`, `G3`, or `G5` fails |
| 23 | Project-shaped reminders missing `active-project` tag | `blocked pending validation` | full inventory plus tag-absence proof | `G1` fails |
| 24 | `active-project` items that look like single actions | `shortcut-required` | `shortcut.active_projects.v1` plus wording heuristics | `G1` fails |
| 25 | Old incomplete reminders with empty notes | `native+mirror` | native timestamps and notes | native timestamp wiring missing |
| 26-27 | Weekly review joins across active projects, next actions, waiting-ons, and child structure | `blocked pending validation` | canonical multi-source correlation | `G1`, `G2`, or `G3` fails |
| 28-30 | Grouped planning views from a single semantic slice | `shortcut-required` | corresponding single semantic contract | `G1` fails |
| 31 | Project-health grouping | `blocked pending validation` | hierarchy plus canonical semantic joins | `G1`, `G2`, or `G3` fails |
| 32 | Delegation candidate detection | `blocked pending validation` | broad canonical candidate set not provided by one fixed contract | `G3` fails or broader acquisition is added |
| 33 | Ingest specialized Shortcut results into mirror | `shortcut-required` | contract catalog and mirror ingestion | contract catalog not implemented |
| 34-36 | Store normalized data, sync metadata, and run full sync | `native+mirror` | native lane plus mirror | mirror not implemented |
| 37-38 | Incremental sync by trusted changes | `blocked pending validation` | validated identity and timestamp behavior | `G4` or `G5` fails |
| 39-40 | Local annotations, source confidence, freshness | `native+mirror` | mirror metadata | mirror not implemented |
| 41-42 | Explicit confidence and zero-results-versus-failure handling | `native+mirror` | query layer with source-aware statuses | mirror/query not implemented |
| 43 | Reject malformed or partial Shortcut payloads | `shortcut-required` | contract schema validation | contract schema not enforced |
| 44-45 | Record acquisition path and expose stale or failed sync runs | `native+mirror` | provenance and sync-run storage | mirror not implemented |
| 46-47 | Separate retrieval from diagnostics and define stable JSON schemas | `native+mirror` | mirror/query contracts | mirror/query not implemented |
| 48 | Specialized narrow Shortcut contracts | `shortcut-required` | the catalog in Section 6 | Shortcut team diverges from catalog |
| 49 | Explicit productivity query-family documentation | `native+mirror` | this SDD plus query-layer docs | n/a |
| 50 | Active projects with no subtasks or with subtasks without tags | `blocked pending validation` | hierarchy plus tag plus canonical joins | `G1`, `G2`, or `G3` fails |

### 8.2 Cross-Team Deliverables

#### Native/EventKit team deliverables

- expose the missing public EventKit fields listed in Section 6.1
- validate timestamp and identity behavior
- provide authoritative provider scope

#### Shortcut team deliverables

- implement the contract catalog in Section 6.2
- produce schema-valid JSON
- provide `ok`, `empty`, and `error` behavior
- provide fixtures for each implemented contract
- remain independent of mirror internal implementation details

#### Mirror/query team deliverables

- implement adapter mapping from contract IDs to deployed Shortcut names
- implement schema validation
- store unresolved rows
- implement canonical promotion rules
- implement fixture-first ingestion before live Shortcuts exist

#### David-layer team deliverables

- consume normalized query views only
- implement interpretation logic only after normalization
- avoid raw payload parsing and semantic fallback

---

## 9. Verification and Acceptance

### 9.1 Native Verification

Before implementation is considered correct, verify:
- native capability claims in this SDD match the actual EventKit headers and live behavior
- `creationDate`, `lastModifiedDate`, and `calendarItemExternalIdentifier` are wired into native acquisition
- provider scope is captured through `EKSource.sourceIdentifier`

### 9.2 Contract Acceptance Checks

Every required contract must pass:
- schema-valid output
- deterministic ordering
- explicit `ok`, `empty`, and `error` behavior
- timestamp normalization to UTC ISO 8601
- required keys always present, including nullable keys
- fixture payloads for `ok`, `empty`, and `error`

### 9.3 Integration Validation Scenarios

The combined system must explicitly test:
- whether a Shortcut item can be promoted when both native IDs are present
- what happens when a Shortcut succeeds but emits no native identifiers
- what happens when hierarchy data exists without canonical IDs
- what confidence is returned when a single semantic contract succeeded but canonicalization failed
- what confidence is returned when a join-based view is requested but unresolved rows prevent correlation
- whether `lastModifiedDate` changes after title, notes, due-date, completion, tag, and hierarchy-relevant edits

### 9.4 Acceptance Criteria for This SDD

This document is implementation-ready only if:
- each v1 story group has a design classification
- all required Shortcut contracts are named and scoped
- canonical identity rules are explicit
- validation-gate failure behavior is explicit
- unresolved Shortcut rows have defined storage and query behavior
- no major cross-team interface decision is left open

---

## 10. Risks and Rationale

### 10.1 Risk Register

| Risk | Severity | Consequence | Required Mitigation |
|---|---|---|---|
| `calendarItemIdentifier` changes after full sync | high | broken joins and stale references | never treat it as the preferred canonical identity |
| `calendarItemExternalIdentifier` duplicates or provider caveats | high | accidental over-merge | provider-scoped canonical keys and collision handling |
| public native path does not expose true tags | high | semantic retrieval blocked | fixed Shortcut contracts |
| public native path does not expose hierarchy | high | project diagnostics blocked | fixed hierarchy contract or keep views blocked |
| Shortcut payloads omit native identifiers | high | no canonical promotion | low-confidence source-only retrieval; block joins |
| `lastModifiedDate` is unreliable | medium | broken incremental sync and stale logic | gate `G5` and activate conditional update contract if needed |
| Shortcut team and core team drift on payload shape | high | integration failure | contract catalog plus fixtures |
| zero-result sets are confused with failures | high | false clean-system conclusions | explicit `empty` versus `error` statuses |
| pressure to infer tags from titles or notes | high | false GTD semantics | explicitly prohibited |

### 10.2 Key Design Rationale

The major design choices are intentional:
- The mirror is phase-one core because confidence, provenance, and unresolved-row handling are first-order product requirements.
- Fixed Shortcut contracts are preferred to a generic query engine because a separate team must build them in parallel and the core system must integrate against stable interfaces.
- Canonical identity is separated from Shortcut-local identity because the current evidence does not justify assuming Shortcut IDs are native IDs.
- Fallback from title or notes is prohibited because the product's core value is trustworthy productivity semantics, not best-effort guesses.

---

## Appendix A. Shortcut Fixture Examples

### A.1 Minimal `ok` Example

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

### A.2 Minimal `error` Example

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

## Appendix B. Changelog

### 0.9.0

- restructured the prior implementation-bridge draft into a software design description
- preserved the locked product decisions from the earlier draft
- formalized subsystem decomposition and ownership boundaries
- formalized the canonical identity model
- formalized the Shortcut contract interface for parallel team delivery
- formalized validation gates, traceability, and acceptance criteria
