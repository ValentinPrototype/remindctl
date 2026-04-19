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
            .make(label: "notes", names: [.short("n"), .long("notes")], help: "Set notes", parsing: .singleValue),
            .make(label: "setTag", names: [.long("set-tag")], help: "Replace the full tag set (repeatable)", parsing: .singleValue),
            .make(label: "addTag", names: [.long("add-tag")], help: "Add tag(s) incrementally (repeatable)", parsing: .singleValue),
            .make(label: "removeTag", names: [.long("remove-tag")], help: "Remove tag(s) incrementally (repeatable)", parsing: .singleValue),
            .make(
              label: "priority",
              names: [.short("p"), .long("priority")],
              help: "none|low|medium|high",
              parsing: .singleValue
            ),
          ],
          flags: [
            .make(label: "clearDue", names: [.long("clear-due")], help: "Clear due date"),
            .make(label: "clearTags", names: [.long("clear-tags")], help: "Remove all tags"),
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
        "remindctl edit 2 --set-tag active-project --set-tag area-work",
        "remindctl edit 2 --add-tag waiting-on --remove-tag next-action",
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
      let tagOperations = try CommandHelpers.parseEditTagOperations(
        setTags: values.optionValues("setTag"),
        addTags: values.optionValues("addTag"),
        removeTags: values.optionValues("removeTag"),
        clearTags: values.flag("clearTags")
      )

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

      let hasNativeChanges = title != nil || listName != nil || notes != nil || dueUpdate != nil || priority != nil || isCompleted != nil
      if hasNativeChanges == false && tagOperations.isEmpty {
        throw RemindCoreError.operationFailed("No changes specified")
      }

      let updatedReminder: ReminderItem
      if hasNativeChanges {
        let update = ReminderUpdate(
          title: title,
          notes: notes,
          dueDate: dueUpdate,
          priority: priority,
          listName: listName,
          isCompleted: isCompleted
        )

        updatedReminder = try await store.updateReminder(id: reminder.id, update: update)
      } else {
        updatedReminder = reminder
      }

      if tagOperations.isEmpty == false {
        let mutationTarget = try await store.mutationTarget(forReminderID: updatedReminder.id)
        do {
          try ShortcutTagMutation.apply(tagOperations, to: mutationTarget)
        } catch {
          let prefix = hasNativeChanges ? "Reminder updated, but tag mutation failed." : "Tag mutation failed."
          throw RemindCoreError.operationFailed("\(prefix) \(error.localizedDescription)")
        }
      }

      OutputRenderer.printReminder(updatedReminder, format: runtime.outputFormat)
    }
  }
}
