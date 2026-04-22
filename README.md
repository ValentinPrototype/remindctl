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
- Installed Apple Shortcut helpers for tag search, tag mutation, and hierarchy mutation

## Shortcut Setup And Doctor
Shortcut-backed features depend on three Apple Shortcut helpers installed in the Shortcuts app with these exact names:

- `remindctl - Search By Tag`
- `remindctl - Mutate Tags`
- `remindctl - Mutate Hierarchy`

Install steps:
- From the repo, run `remindctl shortcuts install` to open the bundled `.shortcut` files, or open the files in [Support/Shortcuts](/Users/vk/work/openclaw/remindctl/Support/Shortcuts) manually.
- Click `Add Shortcut` when macOS asks to import it.
- Do not rename the shortcuts after import.
- Delete numbered duplicate copies such as `remindctl - Mutate Tags 1`; `remindctl` invokes the exact canonical names above.

Check local Shortcut hygiene and plan safe updates with:

```bash
remindctl doctor shortcuts
remindctl doctor shortcuts --json
remindctl shortcuts update --dry-run
```

`remindctl shortcuts install` and `remindctl shortcuts update` intentionally refuse to open the bundled assets when
canonical helpers or numbered copies are already installed. Delete the listed helpers in Shortcuts.app first, then rerun
the command. This avoids macOS importing replacements as `... 1` duplicates. Use `--open-anyway` only when you
intentionally want duplicate imports.

First runs may trigger macOS Shortcuts and Reminders permission prompts. Run the doctor command and one interactive
live command before relying on automation so permission dialogs can be approved. Search helpers use a `60s` timeout;
tag and hierarchy mutation helpers use `120s` timeouts. Hierarchy mutation can still take roughly `10-40s` because it
goes through Shortcuts, Reminders, and iCloud state.

## Tag Search Setup
Tag search is powered by `remindctl - Search By Tag`.

Once installed, tag search works like this:

```bash
remindctl show --tag active-project
remindctl show --tag active-project --tag area-work
remindctl show completed --tag active-project
```

If the shortcut is missing or renamed, `remindctl` fails with a setup error explaining that
the helper shortcut is required for `--tag` searches.

## Tag Mutation Setup
True tag mutation is powered by `remindctl - Mutate Tags`.

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
True sub-reminder mutation is powered by `remindctl - Mutate Hierarchy`.

Command usage:

```bash
remindctl project create "Ship v1" --area work --step "Draft release notes"
remindctl project add-step 2 "Email supplier" --kind next-action --context messenger --energy low
remindctl project attach 4 --to 2
remindctl project show 2 --all
remindctl sync --gtd
remindctl project health --area work
remindctl review weekly
```

The helper contract is documented in
[Support/Shortcuts/HIERARCHY_MUTATION_SHORTCUT.md](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/HIERARCHY_MUTATION_SHORTCUT.md).
Tags are still handled by `remindctl - Mutate Tags`; the hierarchy helper only creates or attaches true subtasks.
Project step commands call the hierarchy helper's `create_child` operation, then apply tags and native metadata.
`project show` reads the live hierarchy through `remindctl - Search By Tag` by default. Use `--mirror` to query
an existing mirror database instead.
`sync --gtd` refreshes the local GTD mirror using native Reminders plus the installed `remindctl - Search By Tag`
helper. It populates active-project, next-action, waiting-on, and hierarchy data for review-style reads.
`project health` reads the mirror by default. Use `project health --sync` to refresh first. It reports active
projects with no open children, no next-action child, unclassified children, missing area tags, or unresolved child
details.
`review weekly` reads the same mirror and returns a compact weekly review snapshot with project health, next
actions, waiting-ons, overdue actionables, and stale/vague candidates.

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
remindctl sync --gtd
remindctl project health --area work
remindctl project health --sync --area work
remindctl review weekly --sync
remindctl complete 1 2 3
remindctl delete 4A83 --force
remindctl status                # permission status
remindctl authorize             # request permissions
remindctl doctor shortcuts      # validate Shortcut helper installation
remindctl shortcuts update      # safely open replacement Shortcut assets after old copies are deleted
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
