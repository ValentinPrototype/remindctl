import Foundation
import RemindCore

enum ProjectStatus: String, Sendable, Equatable {
  case active
  case someday

  var tag: String {
    switch self {
    case .active:
      return "active-project"
    case .someday:
      return "someday/maybe"
    }
  }
}

enum ProjectStepKind: String, Sendable, Equatable {
  case nextAction = "next-action"
  case waitingOn = "waiting-on"
  case task
  case scheduled
}

enum ProjectWorkflow {
  static let knownAreaTags = [
    "area-work",
    "area-family",
    "area-partner",
    "area-personal",
    "area-health",
    "area-home",
    "area-people",
  ]

  static func parseStatus(_ rawValue: String?) throws -> ProjectStatus {
    guard let rawValue else {
      return .active
    }
    guard let status = ProjectStatus(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
      throw RemindCoreError.operationFailed("Invalid project status: \(rawValue) (use active|someday)")
    }
    return status
  }

  static func parseStepKind(_ rawValue: String?) throws -> ProjectStepKind {
    guard let rawValue else {
      return .task
    }
    guard let kind = ProjectStepKind(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
      throw RemindCoreError.operationFailed("Invalid step kind: \(rawValue) (use next-action|waiting-on|task|scheduled)")
    }
    return kind
  }

  static func normalizeAreaTag(_ rawValue: String) throws -> String {
    let normalized = try ShortcutTagSearch.normalizeTag(rawValue)
    if normalized.hasPrefix("area-") {
      return normalized
    }
    return "area-\(normalized)"
  }

  static func normalizeContextTag(_ rawValue: String) throws -> String {
    let normalized = try ShortcutTagSearch.normalizeTag(rawValue)
    if normalized.hasPrefix("c-") {
      return normalized
    }
    return "c-\(normalized)"
  }

  static func normalizeEnergyTag(_ rawValue: String) throws -> String {
    let normalized = try ShortcutTagSearch.normalizeTag(rawValue)
    if normalized.hasPrefix("e-") {
      return normalized
    }
    return "e-\(normalized)"
  }

  static func projectTags(areaTag: String, status: ProjectStatus) -> [String] {
    uniqueTags([status.tag, areaTag])
  }

  static func childTags(
    areaTag: String,
    kind: ProjectStepKind,
    context: String?,
    energy: String?,
    dueDate: Date?
  ) throws -> [String] {
    if kind == .scheduled, dueDate == nil {
      throw RemindCoreError.operationFailed("Scheduled project steps require --due")
    }

    var tags = [areaTag]
    switch kind {
    case .nextAction:
      tags.append("next-action")
    case .waitingOn:
      tags.append("waiting-on")
    case .scheduled:
      tags.append("scheduled")
    case .task:
      break
    }
    if let context {
      tags.append(try normalizeContextTag(context))
    }
    if let energy {
      tags.append(try normalizeEnergyTag(energy))
    }
    return uniqueTags(tags)
  }

  static func findAreaTag(forParentManagedID parentManagedID: String) throws -> String {
    var matches: [String] = []
    for areaTag in knownAreaTags {
      let reminders = try ShortcutTagSearch.search(tags: [areaTag])
      if reminders.contains(where: { $0.canonicalManagedID == parentManagedID }) {
        matches.append(areaTag)
      }
    }

    if matches.count == 1, let match = matches.first {
      return match
    }
    if matches.isEmpty {
      throw RemindCoreError.operationFailed(
        "Unable to determine parent project area tag. Ensure the project has exactly one known area-* tag."
      )
    }
    throw RemindCoreError.operationFailed(
      "Parent project has multiple area tags: \(matches.joined(separator: ", "))"
    )
  }

  static func isoString(from date: Date?) -> String? {
    guard let date else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  static func uniqueTags(_ tags: [String]) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for tag in tags where seen.insert(tag).inserted {
      result.append(tag)
    }
    return result
  }
}
