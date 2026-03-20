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

  static func printMirrorSyncSummary(_ summary: MirrorSyncSummary, format: OutputFormat) {
    switch format {
    case .standard:
      Swift.print("Mirror updated: \(summary.databasePath)")
      Swift.print("Native reminders: \(summary.nativeReminderCount)")
      Swift.print("Canonical reminders: \(summary.canonicalReminderCount)")
      Swift.print("Unresolved Shortcut items: \(summary.unresolvedShortcutCount)")
      Swift.print("Contract runs: \(summary.contractRunCount)")
      Swift.print("Completed at: \(DateParsing.formatDisplay(summary.completedAt))")
    case .plain:
      Swift.print(
        [
          summary.databasePath,
          "\(summary.nativeReminderCount)",
          "\(summary.canonicalReminderCount)",
          "\(summary.unresolvedShortcutCount)",
          "\(summary.contractRunCount)",
          isoFormatter().string(from: summary.completedAt),
        ].joined(separator: "\t")
      )
    case .json:
      printJSON(summary)
    case .quiet:
      Swift.print(summary.canonicalReminderCount)
    }
  }

  static func printGTDQueryResult(_ result: GTDQueryResult, format: OutputFormat) {
    switch format {
    case .standard:
      Swift.print("\(result.queryFamily) [\(result.status.rawValue)] confidence=\(result.confidence.rawValue)")
      if result.identityStatuses.isEmpty == false {
        Swift.print("Identity status: \(result.identityStatuses.map(\.rawValue).joined(separator: ", "))")
      }
      if let nativeSyncedAt = result.freshness.nativeSyncedAt {
        Swift.print("Native sync: \(DateParsing.formatDisplay(nativeSyncedAt))")
      }
      if let shortcutGeneratedAt = result.freshness.shortcutGeneratedAt {
        Swift.print("Shortcut data: \(DateParsing.formatDisplay(shortcutGeneratedAt))")
      }
      for warning in result.warnings {
        Swift.print("Warning: \(warning)")
      }
      if result.items.isEmpty {
        Swift.print("No results found")
        return
      }
      for item in result.items {
        let due = item.dueAt.map { DateParsing.formatDisplay($0) } ?? "no due date"
        let semantics = item.matchedSemantics.isEmpty ? "" : " semantics=\(item.matchedSemantics.joined(separator: ","))"
        let hierarchySuffix: String
        if item.parentSourceItemID != nil || item.childSourceItemIDs.isEmpty == false {
          let parent = item.parentCanonicalID ?? item.parentSourceItemID ?? "-"
          hierarchySuffix = " parent=\(parent) children=\(item.childSourceItemIDs.count)"
        } else {
          hierarchySuffix = ""
        }
        Swift.print("[\(item.identityStatus.rawValue)] \(item.title) [\(item.listTitle)] — \(due)\(semantics)\(hierarchySuffix)")
      }
    case .plain:
      for item in result.items {
        Swift.print(
          [
            item.sourceItemID ?? "",
            item.canonicalID ?? "",
            item.identityStatus.rawValue,
            item.listTitle,
            item.priority.rawValue,
            item.dueAt.map { isoFormatter().string(from: $0) } ?? "",
            item.title,
            item.matchedSemantics.joined(separator: ","),
            item.parentCanonicalID ?? item.parentSourceItemID ?? "",
            item.childCanonicalIDs.isEmpty ? item.childSourceItemIDs.joined(separator: ",") : item.childCanonicalIDs.joined(separator: ","),
          ].joined(separator: "\t")
        )
      }
    case .json:
      printJSON(result)
    case .quiet:
      Swift.print(result.items.count)
    }
  }

  static func printValidationGates(_ records: [ValidationGateRecord], format: OutputFormat) {
    switch format {
    case .standard:
      for record in records.sorted(by: { $0.gateID.rawValue < $1.gateID.rawValue }) {
        let evidence = record.evidence.map { " — \($0)" } ?? ""
        let updatedAt = record.updatedAt == .distantPast ? "never" : DateParsing.formatDisplay(record.updatedAt)
        Swift.print("\(record.gateID.rawValue) [\(record.state.rawValue)] \(record.gateID.title) — \(updatedAt)\(evidence)")
      }
    case .plain:
      for record in records.sorted(by: { $0.gateID.rawValue < $1.gateID.rawValue }) {
        Swift.print(
          [
            record.gateID.rawValue,
            record.state.rawValue,
            record.updatedAt == .distantPast ? "" : isoFormatter().string(from: record.updatedAt),
            record.evidence ?? "",
          ].joined(separator: "\t")
        )
      }
    case .json:
      printJSON(records)
    case .quiet:
      Swift.print(records.count)
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
      let priority = reminder.priority == .none ? "" : " priority=\(reminder.priority.rawValue)"
      Swift.print("[\(index + 1)] [\(status)] \(reminder.title) [\(reminder.listName)] — \(due)\(priority)")
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
    return [
      reminder.id,
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
