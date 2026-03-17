import Foundation
import RemindCore

struct ShortcutTagSearchPayload: Codable, Sendable, Equatable {
  let success: Bool
  let count: Int
  let request: String
  let data: [ShortcutTagReminder]
}

struct ShortcutTagReminder: Codable, Sendable, Equatable, ReminderFilteringItem {
  let id: String?
  let title: String
  let notes: String?
  let isCompleted: Bool
  let completedAt: Date?
  let priority: ReminderPriority
  let dueAt: Date?
  let listName: String
  let tags: [String]
  let subTasks: [String]
  let parent: String?
  let url: String?
  let hasSubtasks: Bool
  let location: String?
  let whenMessagingPerson: String?
  let isFlagged: Bool
  let hasAlarms: Bool
  let createdAt: Date?
  let updatedAt: Date?

  var dueDate: Date? { dueAt }
  var completionDate: Date? { completedAt }

  private enum RawCodingKeys: String, CodingKey {
    case id
    case title
    case notes
    case isCompleted
    case completedAt
    case priority
    case dueAt
    case list
    case tags
    case subTasks
    case parent
    case url
    case hasSubtasks
    case location
    case whenMessagingPerson
    case isFlagged
    case hasAlarms
    case createdAt
    case updatedAt
    case udpatedAt
  }

  init(
    id: String?,
    title: String,
    notes: String?,
    isCompleted: Bool,
    completedAt: Date?,
    priority: ReminderPriority,
    dueAt: Date?,
    listName: String,
    tags: [String],
    subTasks: [String] = [],
    parent: String? = nil,
    url: String? = nil,
    hasSubtasks: Bool = false,
    location: String? = nil,
    whenMessagingPerson: String? = nil,
    isFlagged: Bool = false,
    hasAlarms: Bool = false,
    createdAt: Date?,
    updatedAt: Date?
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.completedAt = completedAt
    self.priority = priority
    self.dueAt = dueAt
    self.listName = listName
    self.tags = tags
    self.subTasks = subTasks
    self.parent = parent
    self.url = url
    self.hasSubtasks = hasSubtasks
    self.location = location
    self.whenMessagingPerson = whenMessagingPerson
    self.isFlagged = isFlagged
    self.hasAlarms = hasAlarms
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: RawCodingKeys.self)

    id = try Self.decodeOptionalString(from: container, key: .id)
    title = try container.decode(String.self, forKey: .title)
    notes = try Self.decodeOptionalString(from: container, key: .notes)
    isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
    completedAt = try Self.decodeOptionalDate(from: container, key: .completedAt)
    priority = try Self.decodePriority(from: container, key: .priority)
    dueAt = try Self.decodeOptionalDate(from: container, key: .dueAt)
    listName = try container.decode(String.self, forKey: .list)
    tags = try Self.decodeLines(from: container, key: .tags)
    subTasks = try Self.decodeLines(from: container, key: .subTasks)
    parent = try Self.decodeOptionalString(from: container, key: .parent)
    url = try Self.decodeOptionalString(from: container, key: .url)
    hasSubtasks = try container.decode(Bool.self, forKey: .hasSubtasks)
    location = try Self.decodeOptionalString(from: container, key: .location)
    whenMessagingPerson = try Self.decodeOptionalString(from: container, key: .whenMessagingPerson)
    isFlagged = try container.decode(Bool.self, forKey: .isFlagged)
    hasAlarms = try container.decode(Bool.self, forKey: .hasAlarms)
    createdAt = try Self.decodeOptionalDate(from: container, key: .createdAt)
    updatedAt = try Self.decodeOptionalDate(from: container, key: .udpatedAt)
      ?? Self.decodeOptionalDate(from: container, key: .updatedAt)
  }

  private static func decodeOptionalString(
    from container: KeyedDecodingContainer<RawCodingKeys>,
    key: RawCodingKeys
  ) throws -> String? {
    guard let value = try container.decodeIfPresent(String.self, forKey: key)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private static func decodeOptionalDate(
    from container: KeyedDecodingContainer<RawCodingKeys>,
    key: RawCodingKeys
  ) throws -> Date? {
    guard let rawValue = try decodeOptionalString(from: container, key: key) else {
      return nil
    }

    if let date = parseISO8601Date(rawValue) {
      return date
    }

    throw DecodingError.dataCorruptedError(
      forKey: key,
      in: container,
      debugDescription: "Invalid ISO8601 date: \(rawValue)"
    )
  }

  private static func decodePriority(
    from container: KeyedDecodingContainer<RawCodingKeys>,
    key: RawCodingKeys
  ) throws -> ReminderPriority {
    let rawValue = try decodeOptionalString(from: container, key: key)?.lowercased()
    switch rawValue {
    case ReminderPriority.high.rawValue:
      return .high
    case ReminderPriority.medium.rawValue:
      return .medium
    case ReminderPriority.low.rawValue:
      return .low
    default:
      return .none
    }
  }

  private static func decodeLines(
    from container: KeyedDecodingContainer<RawCodingKeys>,
    key: RawCodingKeys
  ) throws -> [String] {
    guard let rawValue = try decodeOptionalString(from: container, key: key) else {
      return []
    }
    return rawValue
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func parseISO8601Date(_ rawValue: String) -> Date? {
    let withFractionalSeconds = ISO8601DateFormatter()
    withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractionalSeconds.date(from: rawValue) {
      return date
    }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: rawValue)
  }
}

private struct ShortcutRunFiles {
  let directoryURL: URL
  let inputURL: URL
  let outputURL: URL
}

private enum ShortcutRunFilesFactory {
  static func make(in fileManager: FileManager = .default) throws -> ShortcutRunFiles {
    let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    let baseDirectoryURL = currentDirectoryURL.appendingPathComponent(".remindctl-shortcuts", isDirectory: true)
    try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)

    let runDirectoryURL = baseDirectoryURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: runDirectoryURL, withIntermediateDirectories: true)

    return ShortcutRunFiles(
      directoryURL: runDirectoryURL,
      inputURL: runDirectoryURL.appendingPathComponent("input.txt"),
      outputURL: runDirectoryURL.appendingPathComponent("output.txt")
    )
  }
}

enum ShortcutTagSearch {
  static let shortcutName = "remindctl: Search Reminders By Tag with JSON Output"

  static func search(tag rawTag: String) throws -> [ShortcutTagReminder] {
    let tag = try normalizeTag(rawTag)
    let runFiles = try ShortcutRunFilesFactory.make()
    defer {
      try? FileManager.default.removeItem(at: runFiles.directoryURL)
    }

    try tag.write(to: runFiles.inputURL, atomically: true, encoding: .utf8)

    let result = try ProcessExecutor.run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: [
        "-c",
        osascriptShellCommand(
          inputPath: runFiles.inputURL.path,
          outputPath: runFiles.outputURL.path
        ),
      ]
    )

    if result.status != 0 {
      throw processFailure(result)
    }

    guard FileManager.default.fileExists(atPath: runFiles.outputURL.path) else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned no output file. Reinstall the bundled .shortcut file and see the README."
      )
    }

    let payload = try decodePayload(from: String(contentsOf: runFiles.outputURL, encoding: .utf8))
    guard payload.success else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" reported failure. Reinstall the bundled .shortcut file and see the README."
      )
    }
    guard payload.count == payload.data.count else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned an invalid count (\(payload.count) vs \(payload.data.count)). Reinstall the bundled .shortcut file and see the README."
      )
    }

    return payload.data
  }

  private static func appleScriptStringLiteral(_ value: String) -> String {
    "\"\(value)\""
  }

  private static func shellSingleQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
  }

  static func normalizeTag(_ rawTag: String) throws -> String {
    var tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
    while tag.hasPrefix("#") {
      tag.removeFirst()
    }
    tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !tag.isEmpty else {
      throw RemindCoreError.operationFailed("Tag cannot be empty after normalization.")
    }
    guard tag.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
      throw RemindCoreError.operationFailed("Invalid tag: \"\(rawTag)\" (use letters, numbers, hyphen, or underscore)")
    }

    return tag.lowercased()
  }

  static func shortcutsArguments(inputPath: String, outputPath: String) -> [String] {
    [
      "run",
      shortcutName,
      "--input-path",
      inputPath,
      "--output-path",
      outputPath,
    ]
  }

  static func osascriptArguments(inputPath: String, outputPath: String) -> [String] {
    [
      "-e", "set shortcutName to \(appleScriptStringLiteral(shortcutName))",
      "-e", "set inputPath to \(appleScriptStringLiteral(inputPath))",
      "-e", "set outputPath to \(appleScriptStringLiteral(outputPath))",
      "-e", "set cmd to \"shortcuts run \" & quoted form of shortcutName & \" --input-path \" & quoted form of inputPath & \" --output-path \" & quoted form of outputPath",
      "-e", "do shell script cmd",
    ]
  }

  static func osascriptShellCommand(inputPath: String, outputPath: String) -> String {
    (["osascript"] + osascriptArguments(inputPath: inputPath, outputPath: outputPath))
      .map(shellSingleQuote)
      .joined(separator: " ")
  }

  static func decodePayload(from rawOutput: String) throws -> ShortcutTagSearchPayload {
    let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned no data. Reinstall the bundled .shortcut file and see the README."
      )
    }

    do {
      return try JSONDecoder().decode(ShortcutTagSearchPayload.self, from: Data(output.utf8))
    } catch {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned invalid JSON. Reinstall the bundled .shortcut file and see the README."
      )
    }
  }

  private static func processFailure(_ result: ProcessResult) -> Error {
    let combined = [result.stderr, result.stdout]
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if combined.contains("Can’t get shortcut") || combined.contains("Can't get shortcut") {
      return RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" is required for --tag searches. Install the bundled .shortcut file and see the README."
      )
    }

    let detail = combined.isEmpty ? "unknown error" : combined
    return RemindCoreError.operationFailed(
      "Shortcut \"\(shortcutName)\" failed: \(detail)"
    )
  }
}
