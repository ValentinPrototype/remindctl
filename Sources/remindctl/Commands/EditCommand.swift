import Commander
import Foundation
import RemindCore

enum EditCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "edit",
      abstract: "Edit a reminder",
      discussion: "Use an index or ID prefix from the show output.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "id", help: "Index or ID prefix", isOptional: false)
          ],
          options: [
            .make(label: "title", names: [.short("t"), .long("title")], help: "New title", parsing: .singleValue),
            .make(label: "list", names: [.short("l"), .long("list")], help: "Move to list", parsing: .singleValue),
            .make(label: "due", names: [.short("d"), .long("due")], help: "Set due date", parsing: .singleValue),
            .make(label: "start", names: [.short("s"), .long("start")], help: "Set start date", parsing: .singleValue),
            .make(label: "notes", names: [.short("n"), .long("notes")], help: "Set notes", parsing: .singleValue),
            .make(label: "location", names: [.long("location")], help: "Set location", parsing: .singleValue),
            .make(label: "url", names: [.long("url")], help: "Set URL", parsing: .singleValue),
            .make(label: "tag", names: [.long("tag")], help: "Add tag (repeatable)", parsing: .singleValue),
            .make(
              label: "priority",
              names: [.short("p"), .long("priority")],
              help: "none|low|medium|high",
              parsing: .singleValue
            ),
          ],
          flags: [
            .make(label: "clearDue", names: [.long("clear-due")], help: "Clear due date"),
            .make(label: "clearStart", names: [.long("clear-start")], help: "Clear start date"),
            .make(label: "clearLocation", names: [.long("clear-location")], help: "Clear location"),
            .make(label: "clearURL", names: [.long("clear-url")], help: "Clear URL"),
            .make(label: "complete", names: [.long("complete")], help: "Mark completed"),
            .make(label: "incomplete", names: [.long("incomplete")], help: "Mark incomplete"),
          ]
        )
      ),
      usageExamples: [
        "remindctl edit 1 --title \"New title\"",
        "remindctl edit 4A83 --due tomorrow",
        "remindctl edit 2 --priority high --notes \"Call before noon\"",
        "remindctl edit 3 --clear-due",
        "remindctl edit 1 --tag work --url https://example.com",
      ]
    ) { values, runtime in
      guard let input = values.argument(0) else {
        throw ParsedValuesError.missingArgument("id")
      }

      let store = RemindersStore()
      try await store.requestAccess()
      let reminders = try await store.reminders(in: nil)
      let resolved = try IDResolver.resolve([input], from: reminders)
      guard let reminder = resolved.first else {
        throw RemindCoreError.reminderNotFound(input)
      }

      let title = values.option("title")
      let listName = values.option("list")
      let notes = values.option("notes")
      let tagValues = values.optionValues("tag")

      var dueUpdate: Date??
      if let dueValue = values.option("due") {
        dueUpdate = try CommandHelpers.parseDueDate(dueValue)
      }
      if values.flag("clearDue") {
        if dueUpdate != nil {
          throw RemindCoreError.operationFailed("Use either --due or --clear-due, not both")
        }
        dueUpdate = .some(nil)
      }

      var startDateUpdate: Date??
      if let startValue = values.option("start") {
        startDateUpdate = try CommandHelpers.parseDueDate(startValue)
      }
      if values.flag("clearStart") {
        if startDateUpdate != nil {
          throw RemindCoreError.operationFailed("Use either --start or --clear-start, not both")
        }
        startDateUpdate = .some(nil)
      }

      var locationUpdate: String??
      if let location = values.option("location") {
        locationUpdate = .some(location)
      }
      if values.flag("clearLocation") {
        if locationUpdate != nil {
          throw RemindCoreError.operationFailed("Use either --location or --clear-location, not both")
        }
        locationUpdate = .some(nil)
      }

      var urlUpdate: URL??
      if let urlValue = values.option("url") {
        urlUpdate = try CommandHelpers.parseURL(urlValue)
      }
      if values.flag("clearURL") {
        if urlUpdate != nil {
          throw RemindCoreError.operationFailed("Use either --url or --clear-url, not both")
        }
        urlUpdate = .some(nil)
      }

      let tags = try CommandHelpers.parseTags(tagValues)
      let tagsUpdate: [String]? = tags.isEmpty ? nil : tags

      var priority: ReminderPriority?
      if let priorityValue = values.option("priority") {
        priority = try CommandHelpers.parsePriority(priorityValue)
      }

      let completeFlag = values.flag("complete")
      let incompleteFlag = values.flag("incomplete")
      if completeFlag && incompleteFlag {
        throw RemindCoreError.operationFailed("Use either --complete or --incomplete, not both")
      }
      let isCompleted: Bool? = completeFlag ? true : (incompleteFlag ? false : nil)

      if title == nil
        && listName == nil
        && notes == nil
        && dueUpdate == nil
        && startDateUpdate == nil
        && locationUpdate == nil
        && urlUpdate == nil
        && tagsUpdate == nil
        && priority == nil
        && isCompleted == nil
      {
        throw RemindCoreError.operationFailed("No changes specified")
      }

      let update = ReminderUpdate(
        title: title,
        notes: notes,
        dueDate: dueUpdate,
        startDate: startDateUpdate,
        location: locationUpdate,
        url: urlUpdate,
        tags: tagsUpdate,
        priority: priority,
        listName: listName,
        isCompleted: isCompleted
      )

      let updated = try await store.updateReminder(id: reminder.id, update: update)
      OutputRenderer.printReminder(updated, format: runtime.outputFormat)
    }
  }
}
