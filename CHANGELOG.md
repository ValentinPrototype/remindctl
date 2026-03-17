# Changelog

## Unreleased
- Add reminder tags support via `--tag` (stored as hashtags in notes/title)
- Add metadata fields to reminders: start date, location, URL, created/modified timestamps, alarms, recurrence
- Extend `add` and `edit` with metadata options (`--start`, `--location`, `--url`, clear flags)

## 0.1.1 - 2026-01-11
- Fix Swift 6 strict concurrency crash when fetching reminders

## 0.1.0 - 2026-01-03
- Reminders CLI with Commander-based command router
- Show reminders with filters (today/tomorrow/week/overdue/upcoming/completed/all/date)
- Manage lists (list, create, rename, delete)
- Add, edit, complete, and delete reminders
- Authorization status and permission prompt command
- JSON and plain output modes for scripting
- Flexible date parsing (relative, ISO 8601, and common formats)
- GitHub Actions CI with lint, tests, and coverage gate
