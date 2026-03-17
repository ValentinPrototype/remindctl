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
remindctl add "Plan trip" --start tomorrow --location "SFO" --url https://example.com --tag travel --tag family
remindctl edit 1 --title "New title" --due 2026-01-04
remindctl edit 1 --tag urgent --location "Desk" --clear-url
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
Accepted by `--due`, `--start`, and filters:
- `today`, `tomorrow`, `yesterday`
- `YYYY-MM-DD`
- `YYYY-MM-DD HH:mm`
- ISO 8601 (`2026-01-03T12:34:56Z`)

## Tags and metadata
- Use `--tag` (repeatable) when adding or editing reminders.
- Tags are persisted as hashtags in reminder title/notes (EventKit has no dedicated tag field).
- Reminder output now includes tags plus available EventKit metadata such as start date, URL, location, alarms, and recurrence flags.

## Permissions
Run `remindctl authorize` to trigger the system prompt. If access is denied, enable
Terminal (or remindctl) in System Settings → Privacy & Security → Reminders.
If running over SSH, grant access on the Mac that runs the command.
