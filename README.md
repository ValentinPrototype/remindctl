# remindctl

Forget the app, not the task ✅

Fast CLI for Apple Reminders on macOS.

## Install

### Homebrew (Home Pro)
```bash
brew install steipete/tap/remindctl
```

### From source
```bash
pnpm install
pnpm build
# binary at ./bin/remindctl
```

## Development
```bash
make remindctl ARGS="status"   # clean build + run
make check                     # lint + test + coverage gate
```

## Requirements
- macOS 14+ (Sonoma or later)
- Swift 6.2+
- Reminders permission (System Settings → Privacy & Security → Reminders)

## Tag Search Setup
Tag search is powered by an Apple Shortcut helper. The transport shortcut must be installed in the
Shortcuts app with this exact name:

`remindctl - Search By Tag`

Install steps:
- Open [Support/Shortcuts/remindctl - Search By Tag.shortcut](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/remindctl%20-%20Search%20By%20Tag.shortcut) in Finder, or drag it into the Shortcuts app.
- Click `Add Shortcut` when macOS asks to import it.
- Do not rename the shortcut after import.

Once installed, tag search works like this:

```bash
remindctl show --tag active-project
remindctl show --tag active-project --tag area-work
remindctl show completed --tag active-project
```

If the shortcut is missing or renamed, `remindctl` fails with a setup error explaining that
the helper shortcut is required for `--tag` searches.

## Tag Mutation Setup
True tag mutation is powered by a separate Apple Shortcut helper. The helper must be installed in the
Shortcuts app with this exact name:

`remindctl - Mutate Tags`

Command usage:

```bash
remindctl add "Ship v1" --tag active-project --tag area-work
remindctl edit 2 --set-tag active-project --set-tag area-work
remindctl edit 2 --add-tag waiting-on --remove-tag next-action
remindctl edit 2 --clear-tags
```

The helper contract is documented in
[Support/Shortcuts/TAG_MUTATION_SHORTCUT.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/TAG_MUTATION_SHORTCUT.md).
If the helper shortcut is missing or renamed, `remindctl` fails with a setup error when a tag mutation is requested.

Installed-shortcut coverage is opt-in during tests:

```bash
REMINDCTL_RUN_LIVE_SHORTCUT_TESTS=1 swift test
REMINDCTL_RUN_LIVE_SHORTCUT_TESTS=1 REMINDCTL_RUN_REMINDER_E2E_TESTS=1 swift test
```

Default `swift test` does not invoke the installed Shortcuts app helpers.

## Project Hierarchy Setup
True sub-reminder mutation is powered by a separate Apple Shortcut helper. The helper must be installed in the
Shortcuts app with this exact name:

`remindctl - Mutate Hierarchy`

Command usage:

```bash
remindctl project create "Ship v1" --area work --step "Draft release notes"
remindctl project add-step 2 "Email supplier" --kind next-action --context messenger --energy low
remindctl project attach 4 --to 2
remindctl project show 2 --all
```

The helper contract is documented in
[Support/Shortcuts/HIERARCHY_MUTATION_SHORTCUT.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/HIERARCHY_MUTATION_SHORTCUT.md).
Tags are still handled by `remindctl - Mutate Tags`; the hierarchy helper only creates or attaches true subtasks.

Live hierarchy Shortcut coverage is opt-in:

```bash
REMINDCTL_RUN_LIVE_HIERARCHY_TESTS=1 swift test --filter ShortcutHierarchyMutationLiveTests
REMINDCTL_RUN_PROJECT_E2E_TESTS=1 swift test --filter ProjectCommandLiveE2ETests
```

## GTD Shortcut Assets
The long-term GTD Shortcut contract catalog, fixtures, and shipped assets live under
[Support/Shortcuts](/Users/vk/work/openclaw/remindctl/Support/Shortcuts).

Use:
- [Support/Shortcuts/README.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/README.md) for install and ownership rules
- [Support/Shortcuts/REQUIRED_SHORTCUTS.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/REQUIRED_SHORTCUTS.md) for the cross-team contract list

## Usage
```bash
remindctl                      # show today (default)
remindctl today                 # show today
remindctl tomorrow              # show tomorrow
remindctl week                  # show this week
remindctl overdue               # overdue
remindctl upcoming              # upcoming
remindctl completed             # completed
remindctl all                   # all reminders
remindctl 2026-01-03            # specific date

remindctl list                  # lists
remindctl list Work             # show list
remindctl list Work --rename Office
remindctl list Work --delete
remindctl list Projects --create

remindctl add "Buy milk"
remindctl add --title "Call mom" --list Personal --due tomorrow
remindctl add "Ship v1" --tag active-project
remindctl edit 1 --title "New title" --due 2026-01-04
remindctl edit 2 --set-tag active-project --set-tag area-work
remindctl edit 2 --add-tag waiting-on --remove-tag next-action
remindctl edit 2 --clear-tags
remindctl project create "Ship v1" --area work --step "Draft release notes"
remindctl project add-step 2 "Email supplier" --kind next-action --context messenger --energy low
remindctl project attach 4 --to 2
remindctl project show 2 --all
remindctl complete 1 2 3
remindctl delete 4A83 --force
remindctl status                # permission status
remindctl authorize             # request permissions
```

## Output formats
- `--json` emits JSON arrays/objects.
- `--plain` emits tab-separated lines.
- `--quiet` emits counts only.

## Date formats
Accepted by `--due` and filters:
- `today`, `tomorrow`, `yesterday`
- `YYYY-MM-DD`
- `YYYY-MM-DD HH:mm`
- ISO 8601 (`2026-01-03T12:34:56Z`)

## Permissions
Run `remindctl authorize` to trigger the system prompt. If access is denied, enable
Terminal (or remindctl) in System Settings → Privacy & Security → Reminders.
If running over SSH, grant access on the Mac that runs the command.
