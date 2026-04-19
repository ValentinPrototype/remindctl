# Tag Mutation Shortcut Contract

The helper Shortcut used by `remindctl` for true Apple Reminders tag mutation must be installed in
the Shortcuts app with this exact name:

`remindctl - Mutate Tags`

## Purpose

- keep EventKit as the primary reminder mutation path
- use Shortcuts only for true Reminders tag changes
- target reminders by the managed footer ID embedded in reminder notes

## Input Contract

`remindctl` sends JSON on stdin:

```json
{
  "schema_version": 1,
  "managed_id": "550e8400-e29b-41d4-a716-446655440000",
  "operation": "set",
  "tags": ["active-project", "area-work"]
}
```

Allowed `operation` values:

- `set`
- `add`
- `remove`
- `clear`

Rules:

- `set` replaces the full tag set with the requested tags
- `tags` is required for `set`, `add`, and `remove`
- `tags` is omitted for `clear`
- the Shortcut must resolve the reminder from the `[remindctl-gtd:v1 id=...]` footer in notes
- the Shortcut must fail when zero or multiple reminders match the requested managed ID
- optional response fields may be omitted entirely when not available

## Output Contract

The Shortcut writes JSON to the caller-provided output path:

```json
{
  "success": true,
  "operation": "set",
  "managed_id": "550e8400-e29b-41d4-a716-446655440000",
  "resolved_reminder_count": 1,
  "applied_tags": ["active-project", "area-work"],
  "error_message": null
}
```

Rules:

- always emit valid JSON
- always include `success`
- on failure, set `success = false` and populate `error_message`
- `resolved_reminder_count` should be `1` for success
- if included, `managed_id` and `operation` should echo the request values

## Notes

- This helper is separate from the read-only tag-search Shortcut.
- `remindctl` treats tag mutation as best-effort after native create/edit succeeds.
- Default `swift test` does not execute installed Shortcuts helpers; live shortcut suites are opt-in via
  `REMINDCTL_RUN_LIVE_SHORTCUT_TESTS=1` and `REMINDCTL_RUN_REMINDER_E2E_TESTS=1`.
