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

`remindctl - Search Reminders By Tag with JSON Output`

Install steps:
- Open [Support/Shortcuts/remindctl - Search Reminders By Tag with JSON Output.shortcut](/Users/vk/work/openclaw/remindctl/Support/Shortcuts/remindctl%20-%20Search%20Reminders%20By%20Tag%20with%20JSON%20Output.shortcut) in Finder, or drag it into the Shortcuts app.
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
remindctl edit 1 --title "New title" --due 2026-01-04
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
