import Testing

@testable import RemindCore
@testable import remindctl

@MainActor
struct OutputFormattingTests {
  @Test("Legacy reminder standard lines are unchanged")
  func legacyStandardLines() {
    let reminders = [
      ReminderItem(
        id: "b-id",
        title: "Beta",
        notes: nil,
        isCompleted: true,
        completionDate: nil,
        priority: .high,
        dueDate: nil,
        listID: "inbox",
        listName: "Inbox"
      ),
      ReminderItem(
        id: "a-id",
        title: "Alpha",
        notes: nil,
        isCompleted: false,
        completionDate: nil,
        priority: .none,
        dueDate: nil,
        listID: "inbox",
        listName: "Inbox"
      ),
    ]

    let lines = OutputRenderer.renderReminderItemsStandard(reminders)

    #expect(
      lines == [
        "[1] [ ] Alpha [Inbox] — no due date",
        "[2] [x] Beta [Inbox] — no due date priority=high",
      ]
    )
  }

  @Test("Legacy reminder plain lines are unchanged")
  func legacyPlainLines() {
    let reminders = [
      ReminderItem(
        id: "b-id",
        title: "Beta",
        notes: nil,
        isCompleted: true,
        completionDate: nil,
        priority: .high,
        dueDate: nil,
        listID: "inbox",
        listName: "Inbox"
      ),
      ReminderItem(
        id: "a-id",
        title: "Alpha",
        notes: nil,
        isCompleted: false,
        completionDate: nil,
        priority: .none,
        dueDate: nil,
        listID: "inbox",
        listName: "Inbox"
      ),
    ]

    let lines = OutputRenderer.renderReminderItemsPlain(reminders)

    #expect(
      lines == [
        "a-id\tInbox\t0\tnone\t\tAlpha",
        "b-id\tInbox\t1\thigh\t\tBeta",
      ]
    )
  }

  @Test("Legacy empty reminder standard output is unchanged")
  func emptyStandardLines() {
    #expect(OutputRenderer.renderReminderItemsStandard([]) == ["No reminders found"])
  }
}
