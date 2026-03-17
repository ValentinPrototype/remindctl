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

  static func parseURL(_ value: String) throws -> URL {
    guard let url = URL(string: value), url.scheme != nil else {
      throw RemindCoreError.operationFailed("Invalid URL: \"\(value)\"")
    }
    return url
  }

  static func parseTags(_ values: [String]) throws -> [String] {
    var normalized: [String] = []
    var seen = Set<String>()

    for value in values {
      for fragment in value.split(separator: ",") {
        var token = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { continue }
        if token.hasPrefix("#") {
          token.removeFirst()
        }
        guard
          !token.isEmpty,
          token.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
        else {
          throw RemindCoreError.operationFailed(
            "Invalid tag: \"\(fragment)\". Use letters, numbers, _ or -."
          )
        }
        let normalizedToken = token.lowercased()
        if seen.insert(normalizedToken).inserted {
          normalized.append(normalizedToken)
        }
      }
    }

    return normalized
  }
}
