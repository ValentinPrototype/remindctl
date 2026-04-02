# Required Shortcuts

This file is the cross-team contract catalog for Shortcut-backed GTD acquisition.

## Rules

- The system references contract IDs, not human Shortcut names.
- Every contract is fixed-purpose, read-only, deterministic, and JSON-only.
- Every contract must report `ok`, `empty`, or `error`.
- Empty results are represented with `status = "empty"` and `items = []`.
- Failures are represented with `status = "error"` and explicit `errors`.
- `source_item_id` is always Shortcut-local and never a canonical join key.
- Raw `notes` must be included so the core parser can extract the canonical footer.

## Shared Envelope

Every contract must emit:
- `contract_id`
- `contract_version`
- `generated_at`
- `status`
- `items`
- `warnings`
- `errors`

Every reminder item must emit:
- `source_item_id`
- `native_calendar_item_identifier` nullable
- `native_external_identifier` nullable
- `title`
- `notes`
- `list_title`
- `is_completed`
- `priority`
- `due_at`
- `created_at`
- `updated_at`
- `url` nullable
- `matched_semantics`
- `observed_tags` nullable

Hierarchy items additionally emit:
- `parent_source_item_id`
- `child_source_item_ids`

## Contract Catalog

| Contract ID | Deployed Shortcut Name | Owner Team | Required | Why Native/EventKit Is Insufficient | Input Contract | Required Output Additions | Fixtures |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `shortcut.active_projects.v1` | `OC GTD: Active Projects` | Shortcut team | required | EventKit does not expose true tag membership for `active-project` | none | `matched_semantics` must include `active-project`; `observed_tags` should preserve available tag evidence | `shortcut.active_projects.v1.ok.json`, `shortcut.active_projects.v1.error.json` |
| `shortcut.next_actions.v1` | `OC GTD: Next Actions` | Shortcut team | required | EventKit does not expose true tag membership for `next-action` | none | `matched_semantics` must include `next-action` | `shortcut.next_actions.v1.ok.json`, `shortcut.next_actions.v1.error.json` |
| `shortcut.waiting_ons.v1` | `OC GTD: Waiting-Ons` | Shortcut team | required | EventKit does not expose true tag membership for `waiting-on` | none | `matched_semantics` must include `waiting-on` | `shortcut.waiting_ons.v1.ok.json`, `shortcut.waiting_ons.v1.error.json` |
| `shortcut.productivity_hierarchy.v1` | `OC GTD: Productivity Hierarchy` | Shortcut team | required | EventKit does not expose parent/child reminder structure in the required GTD form | none | `parent_source_item_id` and `child_source_item_ids` are mandatory | `shortcut.productivity_hierarchy.v1.ok.json`, `shortcut.productivity_hierarchy.v1.error.json` |
| `shortcut.productivity_recently_updated.v1` | `OC GTD: Productivity Recently Updated` | Shortcut team | conditional on `G5` failure | Native `lastModifiedDate` may not be reliable enough for stale-age reasoning on all providers | none | `updated_at` must be populated when available | `shortcut.productivity_recently_updated.v1.ok.json`, `shortcut.productivity_recently_updated.v1.error.json` |

## Current Shipped Transport Shortcut

The existing helper Shortcut:
- `remindctl - Search Reminders By Tag with JSON Output`

is a transport/reference Shortcut for current `show --tag` behavior. It is not the full GTD contract catalog and should not be used as the canonical identity model.
