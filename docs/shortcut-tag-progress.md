# Apple Reminders Tag Search via Shortcuts

## Goal

Add tag-based search to `remindctl` using Apple Shortcuts as the bridge, since Apple Reminders tags are not exposed as a first-class public API through EventKit or the Reminders AppleScript dictionary.

## Current State

- A dedicated shortcut exists: `VK: Search Reminders By Tag`.
- The shortcut currently:
  - receives text input
  - finds reminders where `Tags contains Shortcut Input`
  - filters `Is Not Completed`
  - stops and outputs the matched reminders
- The shortcut works interactively in the Shortcuts app.
- Programmatic execution also works, but only through the correct runner.

## Verified Learnings

### 1. Runner matters

Working:

```applescript
tell application "Shortcuts" to run shortcut "VK: Search Reminders By Tag" with input "active-project"
```

Not reliable for this shortcut:

```applescript
tell application "Shortcuts Events" to run shortcut "VK: Search Reminders By Tag" with input "active-project"
```

Observed behavior:

- `Shortcuts` returns a real result list.
- `Shortcuts Events` returned `missing value` for the same shortcut/input.

Implementation hint:

- For `remindctl`, prefer invoking the shortcut through `tell application "Shortcuts"` rather than `Shortcuts Events`.

### 2. Input format matters

Working input:

- `active-project`

Not working in the tested automation path:

- `#active-project`

Implementation hint:

- Normalize CLI input before passing it into the shortcut.
- Strip the leading `#` for the shortcut contract unless later testing proves both forms can be supported safely.

### 3. `shortcuts run --input-path` is not a text transport

Tested pattern:

```bash
shortcuts run "VK: Search Reminders By Tag" --input-path /tmp/tag.txt
```

Observed behavior:

- The shortcut showed `Unable to run`
- Error text: `The input of the shortcut could not be processed.`
- The shortcut also fell back to `Ask For Text` behavior in some runs

Interpretation:

- `--input-path` is not delivering plain text in the way this shortcut expects.
- It appears to hand the shortcut a file-like input item rather than raw text.

Implementation hint:

- Do not use `shortcuts run --input-path` for this shortcut in its current form.
- Prefer AppleScript with `tell application "Shortcuts" ... with input "active-project"`.

### 4. The shortcut does return the expected reminder set

Verified count for `active-project` through `tell application "Shortcuts"`:

- `40` reminders

### 5. Current output is not suitable for `remindctl` yet

When coerced from AppleScript, the returned reminder objects come back as temporary `.ics` file aliases in:

- `~/Library/Group Containers/group.com.apple.shortcuts/Temporary/com.apple.shortcuts/`

Example:

- `Take a family picture.ics`
- `OpenClaw: Build Main Agent.ics`
- `HGHI :: Intelligence: Email Archive.ics`

Interpretation:

- The shortcut is returning reminder objects, but the automation bridge exposes them as temporary exported calendar/reminder files.
- Titles can be approximated from filenames, but this is not pristine or stable enough for production use.

Implementation hint:

- The shortcut should eventually serialize its own output to a stable text/JSON payload instead of returning raw reminder objects.

### 6. Title fidelity is currently imperfect

Observed filename transformations include:

- `/` showing up as `:`
- Unicode normalization differences
- filename-safe adaptations from the temporary `.ics` export path

Implementation hint:

- Do not treat the current filename-based extraction as canonical reminder data.
- Use it only as proof that the shortcut can find the correct reminders.

## Suggested Contract For Later

### Input contract

- `remindctl` passes plain text tag name without leading `#`
- Example: `active-project`

### Output contract

- The shortcut should end by returning JSON text
- Avoid returning raw reminder objects

Suggested fields to preserve if available from Shortcut actions:

- reminder identifier
- title
- notes
- list name
- completed
- flagged
- priority
- creation date
- modification date
- due date
- start date
- tags
- parent reminder
- subtasks / child count

## Research Notes / Open Questions

### Next step 1

Research whether file input for the shortcut would be more prudent to prepare for a more flexible search that could include:

- open/closed state
- order attribute
- desc/asc
- sort by `createdAt`
- sort by `updatedAt`
- sort by `title`

Key question:

- Is there a robust file-based input contract the shortcut can intentionally decode, or is AppleScript text input still the safer path even for richer queries?

### Next step 2

Research what output format would give the most pristine/raw data, including:

- all available metadata
- preserved titles
- stable identifiers

Key question:

- Should the shortcut emit JSON text directly, or is there another export shape that preserves more Reminders metadata without lossy filename conversion?

### Next step 3

Research whether this shortcut can be saved, shipped, and installed by users so `remindctl` can depend on it.

Key questions:

- Can we export the shortcut in a way suitable for distribution?
- Can we version it?
- Can installation be documented as a one-time setup step?
- Can `remindctl` detect whether the shortcut is installed and guide the user if not?

## Practical Advice For The Next Session

- Start from the known-good invocation path:

```applescript
tell application "Shortcuts" to run shortcut "VK: Search Reminders By Tag" with input "active-project"
```

- Do not start by debugging `Shortcuts Events` again unless there is a specific reason.
- Do not start from CLI `--input-path` again unless the shortcut is redesigned to consume file input intentionally.
- The next real milestone is not “find reminders” anymore. That is proven.
- The next real milestone is “return structured, lossless reminder data that `remindctl` can parse reliably.”
