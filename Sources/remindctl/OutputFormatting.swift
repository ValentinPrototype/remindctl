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

enum OutputRenderer {
  static func printReminders(_ reminders: [ReminderItem], format: OutputFormat) {
    switch format {
    case .standard:
      printRemindersStandard(reminders)
    case .plain:
      printRemindersPlain(reminders)
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
      let details = detailSegments(for: reminder)
      let suffix = details.isEmpty ? "" : " " + details.joined(separator: " ")
      Swift.print("✓ \(reminder.title) [\(reminder.listName)] — \(due)\(suffix)")
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

  private static func printRemindersStandard(_ reminders: [ReminderItem]) {
    let sorted = ReminderFiltering.sort(reminders)
    guard !sorted.isEmpty else {
      Swift.print("No reminders found")
      return
    }
    for (index, reminder) in sorted.enumerated() {
      let status = reminder.isCompleted ? "x" : " "
      let due = reminder.dueDate.map { DateParsing.formatDisplay($0) } ?? "no due date"
      let details = detailSegments(for: reminder)
      let suffix = details.isEmpty ? "" : " " + details.joined(separator: " ")
      Swift.print("[\(index + 1)] [\(status)] \(reminder.title) [\(reminder.listName)] — \(due)\(suffix)")
    }
  }

  private static func printRemindersPlain(_ reminders: [ReminderItem]) {
    let sorted = ReminderFiltering.sort(reminders)
    for reminder in sorted {
      Swift.print(plainLine(for: reminder))
    }
  }

  private static func plainLine(for reminder: ReminderItem) -> String {
    let due = reminder.dueDate.map { isoFormatter().string(from: $0) } ?? ""
    let start = reminder.startDate.map { isoFormatter().string(from: $0) } ?? ""
    let url = reminder.url?.absoluteString ?? ""
    let created = reminder.creationDate.map { isoFormatter().string(from: $0) } ?? ""
    let modified = reminder.lastModifiedDate.map { isoFormatter().string(from: $0) } ?? ""
    let tags = reminder.tags.joined(separator: ",")
    return [
      reminder.id,
      reminder.listName,
      reminder.isCompleted ? "1" : "0",
      reminder.priority.rawValue,
      due,
      start,
      reminder.location ?? "",
      url,
      reminder.hasAlarms ? "1" : "0",
      reminder.hasRecurrenceRules ? "1" : "0",
      created,
      modified,
      tags,
      reminder.title,
    ].joined(separator: "\t")
  }

  private static func detailSegments(for reminder: ReminderItem) -> [String] {
    var details: [String] = []

    if reminder.priority != .none {
      details.append("priority=\(reminder.priority.rawValue)")
    }
    if !reminder.tags.isEmpty {
      let tagText = reminder.tags.map { "#\($0)" }.joined(separator: ",")
      details.append("tags=\(tagText)")
    }
    if let startDate = reminder.startDate {
      details.append("start=\(DateParsing.formatDisplay(startDate))")
    }
    if let location = reminder.location, !location.isEmpty {
      details.append("location=\"\(location)\"")
    }
    if let url = reminder.url {
      details.append("url=\(url.absoluteString)")
    }
    if reminder.hasAlarms {
      details.append("alarms=1")
    }
    if reminder.hasRecurrenceRules {
      details.append("recurring=1")
    }

    return details
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
