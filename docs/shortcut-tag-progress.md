# Apple Reminders Tag Search via Shortcuts

## Goal

Add shortcut-backed tag search to `remindctl` with a stable JSON query contract, while keeping the public CLI small for now.

## Current State

- The shipped helper shortcut name is `remindctl: Search Reminders By Tag with JSON Output`.
- The shortcut now accepts JSON on stdin and writes JSON results to a caller-provided output file.
- `remindctl` currently only needs tag search, but the query contract is being shaped for richer AND-combined filters later.

## Proven Transport

Working invocation:

```bash
printf '{ "tags": ["active-project"] }' \
  | shortcuts run "remindctl: Search Reminders By Tag with JSON Output" \
      --output-path output.txt
```

Working output:

- the shortcut writes JSON to `output.txt`
- the current payload includes `success`, `count`, `request`, and `data`

Implementation hint:

- keep output on a workspace-local file via `--output-path`
- do not use `/tmp` for `remindctl`

## Input Contract V1

`remindctl` should send a versioned JSON object on stdin:

```json
{
  "schemaVersion": 1,
  "filters": {
    "tagsAll": ["active-project", "area-work"],
    "isCompleted": true,
    "isFlagged": true,
    "priority": "high",
    "hasSubtasks": true,
    "date": [
      {
        "field": "createdAt",
        "op": "before",
        "value": "2026-03-17T00:00:00Z"
      }
    ]
  }
}
```

Semantics:

- top-level filters are AND-combined
- `tagsAll` means the reminder must contain every listed tag
- `date` is an AND-combined predicate array
- ranges are represented by multiple predicates on the same field
- `value` is always ISO 8601

## Transitional Compatibility

The currently installed shortcut still expects top-level `tags`.

This payload works with the current shortcut and preserves the planned contract:

```json
{
  "schemaVersion": 1,
  "filters": {
    "tagsAll": ["active-project"]
  },
  "tags": ["active-project"]
}
```

Implementation hint:

- `remindctl` should encode the versioned contract
- for now, also mirror `filters.tagsAll` into top-level `tags`
- remove the compatibility mirror later once the shortcut is updated to read `filters.tagsAll`

## Output Contract

The output contract remains unchanged for this step.

Current payload shape:

```json
{
  "success": true,
  "count": 40,
  "request": "active-project",
  "data": [
    {
      "id": "optional-string",
      "list": "Work",
      "title": "Build Main Agent",
      "notes": "",
      "isCompleted": false,
      "completedAt": "",
      "priority": "High",
      "dueAt": "",
      "tags": "active-project\nopenclaw",
      "subTasks": "",
      "parent": "",
      "url": "",
      "hasSubtasks": false,
      "location": "",
      "whenMessagingPerson": "",
      "isFlagged": true,
      "hasAlarms": false,
      "createdAt": "2026-03-17T10:00:00Z",
      "udpatedAt": "2026-03-17T11:00:00Z"
    }
  ]
}
```

Implementation hint:

- keep tolerating `udpatedAt` until the shortcut fixes the typo
- keep decoding newline-delimited `tags` and `subTasks`

## Public CLI Scope For Now

Implement only:

```bash
remindctl show --tag active-project
remindctl show --tag active-project --tag area-work
remindctl show completed --tag active-project
```

Rules:

- `--tag` is repeatable
- repeated tags are AND-combined
- if any tags are present and no explicit filter is given, default to `all`
- non-tag `show` behavior stays unchanged

## Future Filters To Add Later

Planned but not yet implemented:

- `isCompleted`
- `isFlagged`
- `priority`
- `hasSubtasks`
- `date` predicates over:
  - `createdAt`
  - `completedAt`
  - `dueAt`
  - `updatedAt`

Examples the schema should support later:

- reminders with tag `tag1`
- reminders completed yesterday
- reminders due within the next week
- open reminders with tags `tag1` and `tag2`

## Practical Advice

- Prefer direct `/usr/bin/shortcuts` execution over AppleScript for the JSON stdin path.
- Keep using workspace-local output files.
- Validate and normalize tags before launching the shortcut.
- Treat the query schema as internal but stable enough to version now.
