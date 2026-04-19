import Foundation
import RemindCore

enum CommandHelpers {
  static func parsePriority(_ value: String) throws -> ReminderPriority {
    switch value.lowercased() {
    case "none":
      return .none
    case "low":
      return .low
    case "medium", "med":
      return .medium
    case "high":
      return .high
    default:
      throw RemindCoreError.operationFailed("Invalid priority: \"\(value)\" (use none|low|medium|high)")
    }
  }

  static func parseDueDate(_ value: String) throws -> Date {
    guard let date = DateParsing.parseUserDate(value) else {
      throw RemindCoreError.invalidDate(value)
    }
    return date
  }

  static func parseAddTagOperation(_ rawTags: [String]) throws -> ReminderTagMutationOperation? {
    let tags = try normalizeUniqueTags(rawTags, optionName: "tag")
    guard !tags.isEmpty else {
      return nil
    }
    return .set(tags)
  }

  static func parseEditTagOperations(
    setTags rawSetTags: [String],
    addTags rawAddTags: [String],
    removeTags rawRemoveTags: [String],
    clearTags: Bool
  ) throws -> [ReminderTagMutationOperation] {
    let setTags = try normalizeUniqueTags(rawSetTags, optionName: "set-tag")
    let addTags = try normalizeUniqueTags(rawAddTags, optionName: "add-tag")
    let removeTags = try normalizeUniqueTags(rawRemoveTags, optionName: "remove-tag")

    if setTags.isEmpty == false && (clearTags || addTags.isEmpty == false || removeTags.isEmpty == false) {
      throw RemindCoreError.operationFailed(
        "Use either --set-tag or incremental tag flags (--add-tag/--remove-tag/--clear-tags), not both"
      )
    }

    if clearTags && (addTags.isEmpty == false || removeTags.isEmpty == false) {
      throw RemindCoreError.operationFailed(
        "Use either --clear-tags or --add-tag/--remove-tag, not both"
      )
    }

    if setTags.isEmpty == false {
      return [.set(setTags)]
    }

    if clearTags {
      return [.clear]
    }

    let conflictingTags = Set(addTags).intersection(removeTags).sorted()
    if conflictingTags.isEmpty == false {
      throw RemindCoreError.operationFailed(
        "The same tag cannot be passed to both --add-tag and --remove-tag: \(conflictingTags.joined(separator: ", "))"
      )
    }

    var operations: [ReminderTagMutationOperation] = []
    if addTags.isEmpty == false {
      operations.append(.add(addTags))
    }
    if removeTags.isEmpty == false {
      operations.append(.remove(removeTags))
    }
    return operations
  }

  private static func normalizeUniqueTags(_ rawTags: [String], optionName: String) throws -> [String] {
    guard rawTags.isEmpty == false else {
      return []
    }

    var normalizedTags: [String] = []
    var seenTags = Set<String>()
    for rawTag in rawTags {
      let normalizedTag = try ShortcutTagSearch.normalizeTag(rawTag)
      if seenTags.insert(normalizedTag).inserted {
        normalizedTags.append(normalizedTag)
      }
    }

    guard normalizedTags.isEmpty == false else {
      throw RemindCoreError.operationFailed("At least one tag is required for --\(optionName)")
    }

    return normalizedTags
  }
}
