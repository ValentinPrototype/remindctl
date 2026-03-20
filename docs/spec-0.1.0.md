# spec-0.1.0

**Version:** 0.1.0  
**Status:** Draft / build-oriented  
**Owner:** Valentin / Prometheus / David  
**Project:** `remindctl-gtd`  
**Scope:** Apple Reminders retrieval, normalization, mirror-state, and productivity-oriented query support for David

---

## 1. What this project is

`remindctl-gtd` is a **CLI and local query system for Apple Reminders**, specialized for GTD/productivity workflows.

Its purpose is to give **David** — the productivity specialist agent — a trustworthy productivity-oriented view of Apple Reminders.

This project exists because David needs more than simple reminder listing. He needs to support workflows like:
- reviewing active projects
- finding next actions
- flagging stale/vague tasks
- finding waiting-ons that need follow-up
- detecting projects with no next action
- identifying work that should be delegated to Prometheus rather than pushed through as "discipline"

So the build target is:

## Build target
Build a CLI/system that can retrieve, normalize, cache, and query Apple Reminders in a way that supports David’s productivity review workflows reliably.

This is **not** just a prettier generic Reminders wrapper.
It is a productivity-oriented system.

---

## 2. Why this exists

The standard Reminders surfaces are insufficient for David’s job because:
- productivity workflows depend on tags like `active-project`, `next-action`, and `waiting-on`
- some search capabilities appear to require Apple Shortcuts
- parent/child structure matters
- stale-task and missing-next-action diagnostics are derived views, not raw lists
- repeated live querying is awkward and expensive

Examples:
- to support **active-project review**, the system must reliably retrieve reminders tagged `active-project`
- to support **project hygiene**, it must inspect subtasks and child tags
- to support **stale-task review**, it must combine timestamps, tags, hierarchy, and actionability heuristics

---

## 3. Product boundary

This system has three layers:

### 3.1 Acquisition layer
Responsible for fetching Apple Reminders data from supported paths, including specialized Shortcuts where necessary.

### 3.2 Mirror/query layer
Responsible for storing normalized reminder state locally and exposing stable, machine-readable productivity queries.

### 3.3 David layer
Responsible for interpreting the data into productivity judgments, such as:
- stale task
- vague task
- project missing next action
- likely delegation candidate

### Rule
- retrieval belongs in acquisition
- normalized state belongs in the mirror/query layer
- productivity judgment belongs in David

---

## 4. Source-of-truth model

For David’s lane:
- **Apple Reminders** = current execution state
- **Obsidian productivity notes** = workflow-definition source of truth
- **local mirror DB** = normalized operational substrate
- **David** = interpretation + review layer

### Merge rule
1. Obsidian defines workflow semantics
2. Apple Reminders defines current execution state
3. The local mirror reflects a normalized copy of Reminders state
4. David interprets the mirror through the Obsidian definitions
5. If the mirror is stale or data quality is weak, David must lower confidence explicitly

---

## 5. Canonical productivity semantics

## 5.1 Project
A multi-step outcome that cannot be completed in one obvious action.

Signals:
- tagged `active-project`
- has meaningful subtasks
- project-shaped wording

For v1, `active-project` is the strongest signal.

## 5.2 Next action
The first visible, executable step that can actually be started.

Signals:
- tagged `next-action`
- executable wording
- not blocked on hidden clarification

## 5.3 Waiting-on
Work blocked on another person or external event.

Signal:
- tagged `waiting-on`

## 5.4 Actionable
A human can read the item and know what to do next without decomposing it.

## 5.5 Vague
The first executable step cannot be inferred from title + notes + context.

## 5.6 Stale
A diagnostic signal, not a raw field.
Derived from:
- age
- update recency
- due state
- hierarchy health
- actionability quality
- workflow role

---

## 6. v1 scope vs later scope

## 6.1 v1 core
v1 is specifically about making David operational as a productivity specialist.

v1 must support:
- active projects retrieval
- next actions retrieval
- waiting-ons retrieval
- hierarchy inspection
- projects with no next action
- active projects with no subtasks
- active projects with untagged subtasks
- stale/vague task detection
- compact review-oriented outputs
- confidence/failure handling
- mirror-state support only insofar as it helps the above

## 6.2 Explicitly later / out of scope for v1
Not core for 0.1.0:
- rich day/week/month/year scoreboards
- long-range execution analytics
- observability dashboards for the system itself
- deep product telemetry / architecture ROI reporting
- broad general-purpose Reminders automation

These may become v1.5 or v2, but they are not required to make David useful.

---

## 7. Acquisition strategy

## 7.1 Do not rely on one giant dynamic Shortcut
Apple Shortcuts are too graphical and awkward to scale as a universal dynamic query engine.

## 7.2 Preferred acquisition strategy
Use a **small suite of specialized shortcuts** and/or native retrieval paths for stable query families.

Examples:
- Search Active Projects
- Search Next Actions
- Search Waiting-Ons
- Search Today + Overdue Actionables
- Search Recently Updated Productivity Items

## 7.3 Shortcut design rule
Each shortcut should have a narrow, explicit contract.
Examples:
- fixed tag, no runtime parameters
- fixed tag + include/exclude completed
- fixed tag + simple date bucket

Do not turn Shortcuts into a hidden pseudo-programming platform if avoidable.

---

## 8. Mirror-state architecture

A local mirror DB is part of the design.

### Why
It enables:
- correlation across multiple specialized query families
- cheaper repeated productivity queries
- parent/child diagnostics
- tag coverage diagnostics
- derived views that are difficult in Shortcuts

### Example query that justifies the mirror
Show all active projects with no subtasks or with subtasks without tags.

This is much easier with a local database than with raw live Shortcut logic.

---

## 9. SQLite schema (v1-oriented)

## 9.1 `reminders`
Stores normalized reminder records.

Suggested fields:
- `id` (primary key)
- `title`
- `notes`
- `list_id`
- `list_name`
- `is_completed`
- `completed_at`
- `priority`
- `due_at`
- `created_at`
- `updated_at`
- `parent_id`
- `has_subtasks`
- `is_flagged`
- `source_path`
- `source_confidence`
- `last_seen_sync_id`
- `first_seen_at`
- `last_seen_at`

## 9.2 `tags`
- `id`
- `normalized_name`
- `display_name`

## 9.3 `reminder_tags`
- `reminder_id`
- `tag_id`

## 9.4 `relationships`
Optional if parent_id alone is insufficient.
- `parent_id`
- `child_id`
- `relation_type`

## 9.5 `sync_runs`
- `id`
- `started_at`
- `finished_at`
- `source_kind`
- `query_family`
- `status`
- `warning_count`
- `error_count`
- `notes`

## 9.6 `sync_state`
- `key`
- `value`

Examples:
- `last_full_sync_at`
- `last_incremental_sync_at`
- `updated_at_reliability`

## 9.7 `local_annotations`
Optional David-side metadata that should not pollute reminder notes.

Examples:
- `david_classification`
- `stale_reason`
- `review_confidence`
- `last_david_reviewed_at`

---

## 10. Annotation strategy

Default rule:
### prefer local shadow metadata in SQLite over writing metadata into reminder notes

Why:
- cleaner notes in Reminders
- less parsing fragility
- fewer sync conflicts
- clearer system boundary

Only use note-tail metadata if portability or human-visible semantics make it necessary.

---

## 11. Tag normalization rules

Canonical normalization for productivity tags:
- strip leading `#`
- lowercase
- trim whitespace
- compare normalized values only

Examples:
- `#active-project` == `active-project`
- `Active-Project` == `active-project`
- ` waiting-on ` == `waiting-on`

A note-body mention is **not** equivalent to a true Reminders tag unless explicitly modeled as fallback behavior.

---

## 12. Field reliability validation

Before depending on a field in production logic, validate it empirically.

### Must validate
- tag extraction completeness
- tag normalization behavior
- `updatedAt` behavior after:
  - title edits
  - notes edits
  - due-date edits
  - tag changes
  - child completion
  - parent completion
- parent/child fidelity
- deleted reminder handling

### Required outcome
Each key field must be classified as:
- trusted
- usable with caveats
- unsafe for automation logic

---

## 13. Sync model

## 13.1 Initial sync
Run a full sync to populate the mirror.

## 13.2 Incremental sync
If timestamps are reliable enough, incremental sync may use:
- `updatedAt`
- `createdAt`
- sync checkpoints

## 13.3 Freshness requirements
Every mirror-backed query should be able to report:
- freshness of the underlying sync
- whether source was full or incremental
- which acquisition path produced the data

## 13.4 Important gate
Do **not** make incremental sync central until `updatedAt` behavior is validated.

---

## 14. Failure and confidence model

David must never overstate certainty.

## 14.1 Confidence levels
### High confidence
- query succeeded
- required fields present
- mirror fresh enough
- relevant fields validated as trustworthy

### Medium confidence
- query succeeded
- some fields weak / partially missing
- answer still useful with caveats

### Low confidence
- source query failed
- mirror stale
- malformed/partial payload
- unexpected zero-result set
- critical fields unreliable for the question

## 14.2 Failure behavior
When data quality is weak, David should:
1. state confidence is low
2. avoid presenting the result as complete truth
3. retry only if a retry rule exists
4. fall back only if clearly labeled as fallback

---

## 15. v1 query families

## 15.1 Raw retrieval views
- Active Projects
- Next Actions
- Waiting-Ons
- Today / Overdue Actionables
- Recently Updated Productivity Items

## 15.2 Derived diagnostic views
- Stale Tasks
- Stale Projects
- Projects Missing Next Actions
- Active Projects With No Subtasks
- Active Projects With Untagged Subtasks
- Delegation Candidates

---

## 16. v1 query matrix

| David Question | Acquisition Need | Mirror Need | Derived by | Confidence Risks |
|---|---|---|---|---|
| What are the active projects? | active-project query | reminders + tags | mirror/query layer | tag extraction completeness |
| What are the next actions? | next-action query | reminders + tags | mirror/query layer | tag hygiene |
| Which waiting-ons need follow-up? | waiting-on query + timestamps | reminders + tags + timestamps | David | weak follow-up semantics |
| Which tasks are stale? | next-action/task candidate retrieval | timestamps + notes/title | David | unreliable updatedAt |
| Which projects are stale? | active-project retrieval | parent/child + timestamps + tags | David | fake project health from junk subtasks |
| Which projects lack next actions? | active-project retrieval | parent/child + child tags | David | weak next-action definition |
| Which active projects have no subtasks? | active-project retrieval | parent/child | mirror/query layer | hierarchy fidelity |
| Which active projects have untagged subtasks? | active-project retrieval | child-tag joins | mirror/query layer + David formatting | incomplete tag mapping |
| What should be delegated? | broad candidate set | normalized titles/notes/tags/lists | David | heuristic ambiguity |

---

## 17. v1 user-facing outcomes

A builder should assume David needs to produce structured outputs like:

### Example: active-project review
- active projects
- candidate next actions
- hygiene flags
- confidence note if data is partial

### Example: stale review
- stale tasks
- why they are stale
- smallest corrective action
- confidence caveat if timestamp reliability is weak

### Example: weekly review support
- active projects
- projects missing next actions
- waiting-ons needing follow-up
- overdue actionables

---

## 18. Explicit non-goals for 0.1.0

This version does **not** need:
- rich day/week/month/year dashboards
- deep execution analytics
- system telemetry dashboards
- broad generic reminders product scope
- direct reads from the private Reminders app DB
- full write automation

---

## 19. Explicit avoidance: private Reminders app DB

The private Reminders app database should **not** be the primary integration path.

Why:
- likely undocumented/private
- fragile across OS versions
- poor foundation for a durable product

Preferred acquisition paths remain:
- native access where viable
- shortcut-backed specialized queries where needed
- owned local mirror built by `remindctl-gtd`

---

## 20. Fork strategy

This project should be treated as **`remindctl-gtd`** when:
- mirror-state becomes a first-class feature
- specialized shortcut bundles are part of the product
- productivity-specific query families are first-class
- David is the primary customer/use case

That appears to be the current direction.

---

## 21. Recommended next implementation artifact

The next artifact should be an implementation plan / backlog with one row per query family and columns for:
- shortcut name
- acquisition path
- parameter contract
- normalized schema fields
- mirror tables touched
- derived logic
- confidence rule
- failure handling
- freshness requirement
- implementation priority

---

## 22. Changelog

### 0.1.0
- incorporated the user-story pass into a more build-oriented spec
- tightened scope around David’s v1 core job
- explicitly separated v1 core from later analytics/scoreboard ideas
- kept mirror-state architecture as part of the core direction
- clarified build target for an external builder with no prior context
- preserved the productivity-specific product boundary of `remindctl-gtd`
