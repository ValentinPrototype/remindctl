import Foundation
import RemindCore

enum ShortcutDoctorStatus: String, Codable, Sendable, Equatable {
  case ok
  case warning
  case failed
}

struct ShortcutDoctorHelper: Codable, Sendable, Equatable {
  let name: String
  let category: String
  let timeoutSeconds: Int
  let installed: Bool
  let duplicateNames: [String]

  enum CodingKeys: String, CodingKey {
    case name
    case category
    case timeoutSeconds = "timeout_seconds"
    case installed
    case duplicateNames = "duplicate_names"
  }
}

struct ShortcutDoctorReport: Codable, Sendable, Equatable {
  let status: ShortcutDoctorStatus
  let requiredHelpers: [ShortcutDoctorHelper]
  let warnings: [String]
  let errors: [String]
  let notes: [String]

  enum CodingKeys: String, CodingKey {
    case status
    case requiredHelpers = "required_helpers"
    case warnings
    case errors
    case notes
  }
}

struct ShortcutHelperDefinition: Sendable, Equatable {
  let name: String
  let category: String
  let timeout: TimeInterval

  var assetFilename: String {
    "\(name).shortcut"
  }
}

enum ShortcutHelperCatalog {
  static let required = [
    ShortcutHelperDefinition(
      name: ShortcutTagSearch.shortcutName,
      category: "search",
      timeout: ShortcutTagSearch.timeout
    ),
    ShortcutHelperDefinition(
      name: ShortcutTagMutation.shortcutName,
      category: "tag mutation",
      timeout: ShortcutTagMutation.timeout
    ),
    ShortcutHelperDefinition(
      name: ShortcutHierarchyMutation.shortcutName,
      category: "hierarchy mutation",
      timeout: ShortcutHierarchyMutation.timeout
    ),
  ]
}

enum ShortcutDoctor {
  private static let shortcutsListTimeout: TimeInterval = 15

  static func installedShortcutNames() throws -> [String] {
    let result = try ProcessExecutor.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
      arguments: ["list"],
      timeout: shortcutsListTimeout
    )

    guard result.status == 0 else {
      let detail = [result.stderr, result.stdout]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw RemindCoreError.operationFailed(
        "Unable to list installed Shortcuts: \(detail.isEmpty ? "unknown error" : detail)"
      )
    }

    return parseShortcutList(result.stdout)
  }

  static func run() -> ShortcutDoctorReport {
    do {
      return evaluate(installedShortcutNames: try installedShortcutNames())
    } catch {
      return evaluate(
        installedShortcutNames: [],
        additionalErrors: ["Unable to inspect installed Shortcuts: \(error.localizedDescription)"]
      )
    }
  }

  static func parseShortcutList(_ rawOutput: String) -> [String] {
    rawOutput
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  static func evaluate(
    installedShortcutNames: [String],
    additionalErrors: [String] = []
  ) -> ShortcutDoctorReport {
    let installedSet = Set(installedShortcutNames)
    var warnings: [String] = []
    var errors = additionalErrors

    let helpers = ShortcutHelperCatalog.required.map { helper in
      let duplicateNames = duplicateNames(for: helper.name, in: installedShortcutNames)
      if duplicateNames.isEmpty == false {
        warnings.append(
          "Duplicate Shortcut helpers found for \"\(helper.name)\": \(duplicateNames.joined(separator: ", ")). Keep the canonical helper and delete numbered copies to reduce ambiguity."
        )
      }
      if !installedSet.contains(helper.name) {
        errors.append("Missing required Shortcut helper: \(helper.name)")
      }

      return ShortcutDoctorHelper(
        name: helper.name,
        category: helper.category,
        timeoutSeconds: Int(helper.timeout),
        installed: installedSet.contains(helper.name),
        duplicateNames: duplicateNames
      )
    }

    let status: ShortcutDoctorStatus
    if errors.isEmpty == false {
      status = .failed
    } else if warnings.isEmpty == false {
      status = .warning
    } else {
      status = .ok
    }

    return ShortcutDoctorReport(
      status: status,
      requiredHelpers: helpers,
      warnings: warnings,
      errors: errors,
      notes: [
        "The CLI invokes exact canonical Shortcut names; numbered copies are not used but make manual maintenance ambiguous.",
        "First-run macOS Shortcuts and Reminders permission prompts can block helper execution until approved.",
        "Search helpers use a 60s timeout; tag and hierarchy mutation helpers use 120s timeouts.",
      ]
    )
  }

  private static func duplicateNames(for canonicalName: String, in installedShortcutNames: [String]) -> [String] {
    let duplicatePrefix = "\(canonicalName) "
    return installedShortcutNames
      .filter { name in
        guard name.hasPrefix(duplicatePrefix) else { return false }
        let suffix = name.dropFirst(duplicatePrefix.count)
        return suffix.isEmpty == false && suffix.allSatisfy(\.isNumber)
      }
      .sorted()
  }
}
