import Foundation
import RemindCore

enum ReminderTagMutationOperation: Sendable, Equatable {
  case set([String])
  case add([String])
  case remove([String])
  case clear

  var kind: ShortcutTagMutationRequest.OperationKind {
    switch self {
    case .set:
      return .set
    case .add:
      return .add
    case .remove:
      return .remove
    case .clear:
      return .clear
    }
  }

  var tags: [String]? {
    switch self {
    case .set(let tags), .add(let tags), .remove(let tags):
      return tags
    case .clear:
      return nil
    }
  }
}

struct ShortcutTagMutationRequest: Codable, Sendable, Equatable {
  let schemaVersion: Int
  let managedID: String
  let operation: OperationKind
  let tags: [String]?

  init(targetManagedID: String, operation: ReminderTagMutationOperation) {
    schemaVersion = 1
    managedID = targetManagedID
    self.operation = operation.kind
    tags = operation.tags
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case managedID = "managed_id"
    case operation
    case tags
  }

  enum OperationKind: String, Codable, Sendable, Equatable {
    case set
    case add
    case remove
    case clear
  }
}

struct ShortcutTagMutationResponse: Decodable, Sendable, Equatable {
  let success: Bool
  let operation: ShortcutTagMutationRequest.OperationKind?
  let managedID: String?
  let resolvedReminderCount: Int?
  let appliedTags: [String]?
  let errorMessage: String?

  private enum CodingKeys: String, CodingKey {
    case success
    case operation
    case managedID = "managedID"
    case managedId = "managed_id"
    case resolvedReminderCount = "resolvedReminderCount"
    case resolvedReminderCountSnake = "resolved_reminder_count"
    case appliedTags = "appliedTags"
    case appliedTagsSnake = "applied_tags"
    case errorMessage = "errorMessage"
    case errorMessageSnake = "error_message"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    success = try container.decode(Bool.self, forKey: .success)
    operation = try container.decodeIfPresent(ShortcutTagMutationRequest.OperationKind.self, forKey: .operation)
    managedID = try Self.decodeOptionalTrimmedString(from: container, preferredKey: .managedId, fallbackKey: .managedID)
    resolvedReminderCount = try Self.decodeOptionalInt(from: container, preferredKey: .resolvedReminderCountSnake, fallbackKey: .resolvedReminderCount)
    appliedTags = try Self.decodeOptionalTags(from: container, preferredKey: .appliedTagsSnake, fallbackKey: .appliedTags)
    errorMessage = try Self.decodeOptionalTrimmedString(from: container, preferredKey: .errorMessageSnake, fallbackKey: .errorMessage)
  }

  private static func decodeOptionalTrimmedString(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    fallbackKey: CodingKeys
  ) throws -> String? {
    let value = try? container.decodeIfPresent(String.self, forKey: preferredKey)
      ?? container.decodeIfPresent(String.self, forKey: fallbackKey)
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private static func decodeOptionalInt(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    fallbackKey: CodingKeys
  ) throws -> Int? {
    if let directInt = try? container.decodeIfPresent(Int.self, forKey: preferredKey)
      ?? container.decodeIfPresent(Int.self, forKey: fallbackKey) {
      return directInt
    }

    let rawString = try decodeOptionalTrimmedString(from: container, preferredKey: preferredKey, fallbackKey: fallbackKey)
    guard let rawString else {
      return nil
    }
    return Int(rawString)
  }

  private static func decodeOptionalTags(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    fallbackKey: CodingKeys
  ) throws -> [String]? {
    if let directTags = try? container.decodeIfPresent([String].self, forKey: preferredKey)
      ?? container.decodeIfPresent([String].self, forKey: fallbackKey) {
      return directTags
    }

    guard let rawString = try decodeOptionalTrimmedString(from: container, preferredKey: preferredKey, fallbackKey: fallbackKey) else {
      return nil
    }

    let normalizedValue = rawString.replacingOccurrences(of: "\\n", with: "\n")
    let tags = normalizedValue
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return tags.isEmpty ? nil : tags
  }
}

enum ShortcutTagMutation {
  static let shortcutName = "remindctl - Mutate Tags"
  static let timeout: TimeInterval = 120
  private static let category = "tag mutation"
  private static let installGuidance = "Install the tag mutation helper and see the README."

  static func requests(
    for operations: [ReminderTagMutationOperation],
    to target: ReminderMutationTarget
  ) -> [ShortcutTagMutationRequest] {
    operations.map { ShortcutTagMutationRequest(targetManagedID: target.canonicalManagedID, operation: $0) }
  }

  static func apply(_ operations: [ReminderTagMutationOperation], to target: ReminderMutationTarget) throws {
    guard operations.isEmpty == false else { return }

    var appliedOperationCount = 0
    for request in requests(for: operations, to: target) {
      do {
        try apply(request)
        appliedOperationCount += 1
      } catch {
        if appliedOperationCount > 0 {
          throw RemindCoreError.operationFailed(
            "Shortcut \"\(shortcutName)\" failed after applying previous tag operations. Tag state may be partial. \(error.localizedDescription)"
          )
        }
        throw error
      }
    }
  }

  static func apply(_ operation: ReminderTagMutationOperation, to target: ReminderMutationTarget) throws {
    let request = ShortcutTagMutationRequest(targetManagedID: target.canonicalManagedID, operation: operation)
    try apply(request)
  }

  static func validateSuccessfulResponse(
    _ response: ShortcutTagMutationResponse,
    for request: ShortcutTagMutationRequest
  ) throws {
    guard response.success else {
      let detail = response.errorMessage ?? "unknown error"
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" reported failure: \(detail). Install the tag mutation helper and see the README."
      )
    }

    guard response.resolvedReminderCount == 1 else {
      let detail = response.resolvedReminderCount.map(String.init) ?? "missing"
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned an invalid resolved reminder count (\(detail)). Install the tag mutation helper and see the README."
      )
    }

    if let managedID = response.managedID, managedID != request.managedID {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned a mismatched managed_id (\(managedID)). Install the tag mutation helper and see the README."
      )
    }

    if let operation = response.operation, operation != request.operation {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned a mismatched operation (\(operation.rawValue)). Install the tag mutation helper and see the README."
      )
    }
  }

  private static func apply(_ request: ShortcutTagMutationRequest) throws {
    let encodedRequest = try encodeRequest(request)

    let runFiles = try ShortcutRunFilesFactory.make()
    defer {
      try? FileManager.default.removeItem(at: runFiles.directoryURL)
    }

    let result: ProcessResult
    do {
      result = try ProcessExecutor.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
        arguments: shortcutsArguments(outputPath: runFiles.outputURL.path),
        stdin: encodedRequest,
        timeout: timeout
      )
    } catch let error as ProcessExecutionError {
      throw ShortcutProcessErrorFormatter.timeout(
        shortcutName: shortcutName,
        category: category,
        timeout: timeout,
        outputURL: runFiles.outputURL,
        underlyingError: error,
        installGuidance: installGuidance
      )
    } catch {
      throw error
    }

    if result.status != 0 {
      throw processFailure(result, outputURL: runFiles.outputURL)
    }

    guard FileManager.default.fileExists(atPath: runFiles.outputURL.path) else {
      throw ShortcutProcessErrorFormatter.noOutputFile(
        shortcutName: shortcutName,
        category: category,
        outputURL: runFiles.outputURL,
        installGuidance: installGuidance
      )
    }

    let response = try decodeResponse(from: String(contentsOf: runFiles.outputURL, encoding: .utf8))
    try validateSuccessfulResponse(response, for: request)
  }

  static func encodeRequest(_ request: ShortcutTagMutationRequest) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(request)
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

  static func decodeResponse(from rawOutput: String) throws -> ShortcutTagMutationResponse {
    let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned no data. \(installGuidance)"
      )
    }

    do {
      return try JSONDecoder().decode(ShortcutTagMutationResponse.self, from: Data(output.utf8))
    } catch {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned invalid JSON. \(installGuidance)"
      )
    }
  }

  private static func processFailure(_ result: ProcessResult, outputURL: URL) -> Error {
    ShortcutProcessErrorFormatter.processFailure(
      shortcutName: shortcutName,
      category: category,
      result: result,
      outputURL: outputURL,
      missingShortcutGuidance: "Shortcut \"\(shortcutName)\" is required for tag mutation. \(installGuidance)",
      installGuidance: installGuidance
    )
  }
}
