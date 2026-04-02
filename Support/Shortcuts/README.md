# Shortcut Assets

This directory is the permanent repo home for Shortcut assets, GTD contract docs, and fixture payloads.

## Purpose

Use this directory for two different kinds of Shortcut artifacts:
- shipped transport/reference Shortcuts that `remindctl` can run today
- fixed, versioned GTD acquisition contracts implemented by the Shortcut team in parallel

The current shipped helper is:
- `remindctl - Search Reminders By Tag with JSON Output.shortcut`

The GTD contract catalog is documented in:
- [REQUIRED_SHORTCUTS.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/REQUIRED_SHORTCUTS.md)

Fixture payloads live in:
- `fixtures/`

## Ownership Boundary

- Native/EventKit team owns reminder mutation, footer normalization, and native evidence capture.
- Shortcut team owns read-only Shortcut implementations that satisfy the documented contract IDs.
- Mirror/query team owns footer parsing, canonicalization, unresolved-row handling, and query confidence.

The Shortcut team does not own canonicalization.

## Naming Rules

- Core logic refers to contract IDs, not human Shortcut names.
- A single adapter layer maps contract IDs to deployed Shortcut names.
- Shipped Shortcut names must stay stable once published.

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
