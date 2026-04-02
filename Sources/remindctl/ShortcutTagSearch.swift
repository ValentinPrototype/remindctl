import Foundation
import RemindCore

struct ShortcutTagSearchPayload: Codable, Sendable, Equatable {
  let success: Bool
  let count: Int
  let request: String
  let data: [ShortcutTagReminder]
  let errorMessage: String?
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
    self.notes = CanonicalNoteFooter.parse(rawNotes: notes).notesBody
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
    notes = CanonicalNoteFooter.parse(
      rawNotes: try Self.decodeOptionalString(from: container, key: .notes)
    ).notesBody
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

struct ShortcutSearchQueryV1: Encodable, Sendable, Equatable {
  let schemaVersion: Int
  let filters: Filters
  let tags: [String]

  init(tagsAll: [String]) {
    schemaVersion = 1
    filters = Filters(tagsAll: tagsAll)
    tags = tagsAll
  }

  struct Filters: Encodable, Sendable, Equatable {
    let tagsAll: [String]?
    let isCompleted: Bool?
    let isFlagged: Bool?
    let priority: Priority?
    let hasSubtasks: Bool?
    let date: [DatePredicate]?

    init(
      tagsAll: [String]? = nil,
      isCompleted: Bool? = nil,
      isFlagged: Bool? = nil,
      priority: Priority? = nil,
      hasSubtasks: Bool? = nil,
      date: [DatePredicate]? = nil
    ) {
      self.tagsAll = tagsAll
      self.isCompleted = isCompleted
      self.isFlagged = isFlagged
      self.priority = priority
      self.hasSubtasks = hasSubtasks
      self.date = date
    }
  }

  enum Priority: String, Codable, Sendable, Equatable {
    case high
    case medium
    case low
  }

  struct DatePredicate: Encodable, Sendable, Equatable {
    let field: Field
    let op: Operation
    let value: String

    enum Field: String, Codable, Sendable, Equatable {
      case createdAt
      case completedAt
      case dueAt
      case updatedAt
    }

    enum Operation: String, Codable, Sendable, Equatable {
      case before
      case after
    }
  }
}

private struct ShortcutRunFiles {
  let directoryURL: URL
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
      outputURL: runDirectoryURL.appendingPathComponent("output.txt")
    )
  }
}

enum ShortcutTagSearch {
  static let shortcutName = "remindctl - Search Reminders By Tag with JSON Output"

  static func search(tag rawTag: String) throws -> [ShortcutTagReminder] {
    try search(tags: [rawTag])
  }

  static func search(tags rawTags: [String]) throws -> [ShortcutTagReminder] {
    let tags = try normalizeTags(rawTags)
    let query = makeQuery(tags: tags)
    let encodedQuery = try encodeQuery(query)

    let runFiles = try ShortcutRunFilesFactory.make()
    defer {
      try? FileManager.default.removeItem(at: runFiles.directoryURL)
    }

    let result = try ProcessExecutor.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
      arguments: shortcutsArguments(outputPath: runFiles.outputURL.path),
      stdin: encodedQuery
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
      let detail = payload.errorMessage ?? "unknown error"
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" reported failure: \(detail). Reinstall the bundled .shortcut file and see the README."
      )
    }
    guard payload.count == payload.data.count else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned an invalid count (\(payload.count) vs \(payload.data.count)). Reinstall the bundled .shortcut file and see the README."
      )
    }

    return payload.data
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

  static func normalizeTags(_ rawTags: [String]) throws -> [String] {
    let tags = try rawTags.map(normalizeTag)
    guard !tags.isEmpty else {
      throw RemindCoreError.operationFailed("At least one tag is required for --tag searches.")
    }
    return tags
  }

  static func makeQuery(tags: [String]) -> ShortcutSearchQueryV1 {
    ShortcutSearchQueryV1(tagsAll: tags)
  }

  static func encodeQuery(_ query: ShortcutSearchQueryV1) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(query)
    return String(decoding: data, as: UTF8.self)
  }

  static func shortcutsArguments(outputPath: String) -> [String] {
    [
      "run",
      shortcutName,
      "--output-path",
      outputPath,
    ]
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
