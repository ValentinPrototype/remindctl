import Foundation
import RemindCore

enum OutputFormat {
  case standard
  case plain
  case json
  case quiet
}

struct ListSummary: Codable, Sendable, Equatable {
  let id: String
  let title: String
  let reminderCount: Int
  let overdueCount: Int
}

struct AuthorizationSummary: Codable, Sendable, Equatable {
  let status: String
  let authorized: Bool
}

protocol ReminderDisplayItem: ReminderFilteringItem {
  var displayID: String { get }
  var listName: String { get }
  var priority: ReminderPriority { get }
}

extension ReminderItem: ReminderDisplayItem {
  var displayID: String { id }
}

extension ShortcutTagReminder: ReminderDisplayItem {
  var displayID: String { "" }
}

enum OutputRenderer {
  static func printReminders(_ reminders: [ReminderItem], format: OutputFormat) {
    switch format {
    case .standard:
      printLines(renderRemindersStandard(reminders))
    case .plain:
      printLines(renderRemindersPlain(reminders))
    case .json:
      printJSON(reminders)
    case .quiet:
      Swift.print(reminders.count)
    }
  }

  static func printShortcutTagReminders(_ reminders: [ShortcutTagReminder], format: OutputFormat) {
    switch format {
    case .standard:
      printLines(renderRemindersStandard(reminders))
    case .plain:
      printLines(renderRemindersPlain(reminders))
    case .json:
      printJSON(reminders)
    case .quiet:
      Swift.print(reminders.count)
    }
  }

  static func printLists(_ summaries: [ListSummary], format: OutputFormat) {
    switch format {
    case .standard:
      printListsStandard(summaries)
    case .plain:
      printListsPlain(summaries)
    case .json:
      printJSON(summaries)
    case .quiet:
      Swift.print(summaries.count)
    }
  }

  static func printReminder(_ reminder: ReminderItem, format: OutputFormat) {
    switch format {
    case .standard:
      let due = reminder.dueDate.map { DateParsing.formatDisplay($0) } ?? "no due date"
      Swift.print("✓ \(reminder.title) [\(reminder.listName)] — \(due)")
    case .plain:
      Swift.print(plainLine(for: reminder))
    case .json:
      printJSON(reminder)
    case .quiet:
      break
    }
  }

  static func printDeleteResult(_ count: Int, format: OutputFormat) {
    switch format {
    case .standard:
      Swift.print("Deleted \(count) reminder(s)")
    case .plain:
      Swift.print("\(count)")
    case .json:
      let payload = ["deleted": count]
      printJSON(payload)
    case .quiet:
      break
    }
  }

  static func printAuthorizationStatus(_ status: RemindersAuthorizationStatus, format: OutputFormat) {
    switch format {
    case .standard:
      Swift.print("Reminders access: \(status.displayName)")
    case .plain:
      Swift.print(status.rawValue)
    case .json:
      printJSON(AuthorizationSummary(status: status.rawValue, authorized: status.isAuthorized))
    case .quiet:
      Swift.print(status.isAuthorized ? "1" : "0")
    }
  }

  static func renderShortcutTagRemindersPlain(_ reminders: [ShortcutTagReminder]) -> [String] {
    renderRemindersPlain(reminders)
  }

  static func renderReminderItemsStandard(_ reminders: [ReminderItem]) -> [String] {
    renderRemindersStandard(reminders)
  }

  static func renderReminderItemsPlain(_ reminders: [ReminderItem]) -> [String] {
    renderRemindersPlain(reminders)
  }

  private static func renderRemindersStandard<T: ReminderDisplayItem>(_ reminders: [T]) -> [String] {
    let sorted = ReminderFiltering.sort(reminders)
    guard !sorted.isEmpty else {
      return ["No reminders found"]
    }
    return sorted.enumerated().map { index, reminder in
      let status = reminder.isCompleted ? "x" : " "
      let due = reminder.dueDate.map { DateParsing.formatDisplay($0) } ?? "no due date"
      let priority = reminder.priority == .none ? "" : " priority=\(reminder.priority.rawValue)"
      return "[\(index + 1)] [\(status)] \(reminder.title) [\(reminder.listName)] — \(due)\(priority)"
    }
  }

  private static func renderRemindersPlain<T: ReminderDisplayItem>(_ reminders: [T]) -> [String] {
    let sorted = ReminderFiltering.sort(reminders)
    return sorted.map { reminder in
      plainLine(for: reminder)
    }
  }

  private static func plainLine<T: ReminderDisplayItem>(for reminder: T) -> String {
    let due = reminder.dueDate.map { isoFormatter().string(from: $0) } ?? ""
    return [
      reminder.displayID,
      reminder.listName,
      reminder.isCompleted ? "1" : "0",
      reminder.priority.rawValue,
      due,
      reminder.title,
    ].joined(separator: "\t")
  }

  private static func printListsStandard(_ summaries: [ListSummary]) {
    guard !summaries.isEmpty else {
      Swift.print("No reminder lists found")
      return
    }
    for summary in summaries.sorted(by: { $0.title < $1.title }) {
      let overdue = summary.overdueCount > 0 ? " (\(summary.overdueCount) overdue)" : ""
      Swift.print("\(summary.title) — \(summary.reminderCount) reminders\(overdue)")
    }
  }

  private static func printListsPlain(_ summaries: [ListSummary]) {
    for summary in summaries.sorted(by: { $0.title < $1.title }) {
      Swift.print("\(summary.title)\t\(summary.reminderCount)\t\(summary.overdueCount)")
    }
  }

  private static func printLines(_ lines: [String]) {
    for line in lines {
      Swift.print(line)
    }
  }

  private static func printJSON<T: Encodable>(_ payload: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    do {
      let data = try encoder.encode(payload)
      if let json = String(data: data, encoding: .utf8) {
        Swift.print(json)
      }
    } catch {
      Swift.print("Failed to encode JSON: \(error)")
    }
  }

  private static func isoFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }
}
