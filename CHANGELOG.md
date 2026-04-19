# Changelog

## 0.2.0 - 2026-04-19
- Add Shortcut-backed reminder tag search and tag mutation
- Ship stable Shortcut assets for `remindctl - Search By Tag` and `remindctl - Mutate Tags`
- Add live Shortcut contract tests and end-to-end tag workflow coverage

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
