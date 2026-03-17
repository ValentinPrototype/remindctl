import Commander
import Foundation
import RemindCore

enum ShowCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "show",
      abstract: "Show reminders",
      discussion: "Filters: today, tomorrow, week, overdue, upcoming, completed, all, or a date string.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(
              label: "filter",
              help: "today|tomorrow|week|overdue|upcoming|completed|all|<date>",
              isOptional: true
            )
          ],
          options: [
            .make(
              label: "list",
              names: [.short("l"), .long("list")],
              help: "Limit to a specific list",
              parsing: .singleValue
            ),
            .make(
              label: "tag",
              names: [.long("tag")],
              help: "Search by tag via the bundled Shortcuts helper",
              parsing: .singleValue
            )
          ]
        )
      ),
      usageExamples: [
        "remindctl",
        "remindctl today",
        "remindctl show overdue",
        "remindctl show 2026-01-04",
        "remindctl show --list Work",
        "remindctl show --tag active-project",
        "remindctl show completed --tag active-project",
      ]
    ) { values, runtime in
      let listName = values.option("list")
      let tagName = values.option("tag")
      let filterToken = values.argument(0)

      let filter = try resolveFilter(filterToken: filterToken, tagName: tagName)

      if let tagName {
        let reminders = try ShortcutTagSearch.search(tag: tagName)
        let inScope = if let listName {
          reminders.filter { $0.listName == listName }
        } else {
          reminders
        }
        let filtered = ReminderFiltering.apply(inScope, filter: filter)
        OutputRenderer.printShortcutTagReminders(filtered, format: runtime.outputFormat)
        return
      }

      let store = RemindersStore()
      try await store.requestAccess()
      let reminders = try await store.reminders(in: listName)
      let filtered = ReminderFiltering.apply(reminders, filter: filter)
      OutputRenderer.printReminders(filtered, format: runtime.outputFormat)
    }
  }

  static func resolveFilter(filterToken: String?, tagName: String?) throws -> ReminderFilter {
    if let token = filterToken {
      guard let parsed = ReminderFiltering.parse(token) else {
        throw RemindCoreError.operationFailed("Unknown filter: \"\(token)\"")
      }
      return parsed
    }

    if tagName != nil {
      return .all
    }

    return .today
  }
}
