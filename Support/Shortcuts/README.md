# Shortcut Assets

This directory is the permanent repo home for Shortcut assets, GTD contract docs, and fixture payloads.

## Purpose

Use this directory for two different kinds of Shortcut artifacts:
- shipped transport/reference Shortcuts that `remindctl` can run today
- fixed, versioned GTD acquisition contracts implemented by the Shortcut team in parallel

The current shipped helpers are:
- `remindctl - Search By Tag.shortcut`
- `remindctl - Mutate Tags.shortcut`
- `remindctl - Mutate Hierarchy.shortcut`

The tag mutation helper contract is documented in:
- [TAG_MUTATION_SHORTCUT.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/TAG_MUTATION_SHORTCUT.md)

The hierarchy mutation helper contract is documented in:
- [HIERARCHY_MUTATION_SHORTCUT.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/HIERARCHY_MUTATION_SHORTCUT.md)

The GTD contract catalog is documented in:
- [REQUIRED_SHORTCUTS.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/REQUIRED_SHORTCUTS.md)

Fixture payloads live in:
- `fixtures/`

## Ownership Boundary

- Native/EventKit team owns reminder mutation, footer normalization, and native evidence capture.
- Shortcut integration may be used for true tag mutation when EventKit cannot express the operation directly.
- Shortcut integration may be used for true hierarchy mutation when EventKit cannot express the operation directly.
- Shortcut team owns read-only Shortcut implementations that satisfy the documented contract IDs.
- Mirror/query team owns footer parsing, canonicalization, unresolved-row handling, and query confidence.

The Shortcut team does not own canonicalization.

## Naming Rules

- Core logic refers to contract IDs, not human Shortcut names.
- A single adapter layer maps contract IDs to deployed Shortcut names.
- Shipped Shortcut names must stay stable once published.
- Installed transport helpers must use the exact canonical names: `remindctl - Search By Tag`, `remindctl - Mutate Tags`, and `remindctl - Mutate Hierarchy`.
- Numbered duplicate copies such as `remindctl - Mutate Tags 1` should be deleted after import. The CLI invokes exact names, so duplicate copies are not used, but they make manual edits and exports ambiguous.

## Local Doctor

Use the CLI doctor before live Shortcut work:

```bash
remindctl doctor shortcuts
remindctl doctor shortcuts --json
remindctl shortcuts update --dry-run
```

The doctor verifies that canonical helper names are installed and reports numbered duplicate copies. It does not mutate Reminders.

Use the assisted installer from the repo root:

```bash
remindctl shortcuts install
remindctl shortcuts update
```

The install/update command opens bundled `.shortcut` assets only when doing so should not create numbered duplicate imports. If canonical helpers or duplicate copies already exist, it blocks and prints the exact Shortcuts to delete first. macOS does not provide a reliable public CLI command for replacing or deleting installed Shortcuts, so the deletion step remains manual in Shortcuts.app.

First live runs may still pause on macOS Shortcuts or Reminders permission dialogs. Run setup checks interactively once before using project automation or scheduled jobs.

Expected live helper timing:
- Tag/search helpers are usually fast, with a `60s` search timeout.
- Tag mutation has a `120s` timeout.
- Hierarchy mutation has a `120s` timeout and may take roughly `10-40s` because it writes true Reminders subtasks through Shortcuts/iCloud.

## Notes And Canonical Identity

Shortcut payloads must preserve raw `notes` exactly enough for the core parser to extract:
- `notes_body`
- `canonical_managed_id`
- `footer_state`

Shortcut implementations must not generate or interpret the canonical footer semantically.

## Fixture Rules

Each required contract must have:
- one golden `ok` fixture
- one `error` fixture

Fixture names use the contract ID as the base filename, for example:
- `shortcut.active_projects.v1.ok.json`
- `shortcut.active_projects.v1.error.json`

## Current Asset Policy

The helper Shortcut is copied here as the canonical repo location.
A compatibility copy may still exist elsewhere in the repository while documentation transitions.

## Testing Note

Repo tests that exercise installed Shortcuts are opt-in. Use:
- `REMINDCTL_RUN_LIVE_SHORTCUT_TESTS=1 swift test`
- `REMINDCTL_RUN_LIVE_SHORTCUT_TESTS=1 REMINDCTL_RUN_REMINDER_E2E_TESTS=1 swift test`
- `REMINDCTL_RUN_LIVE_HIERARCHY_TESTS=1 swift test --filter ShortcutHierarchyMutationLiveTests`
- `REMINDCTL_RUN_PROJECT_E2E_TESTS=1 swift test --filter ProjectCommandLiveE2ETests`

Default `swift test` validates repo-side adapters and assets, but does not invoke the installed Shortcuts app helpers.
