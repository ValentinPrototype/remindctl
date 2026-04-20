import Foundation
import RemindCore

enum ReminderHierarchyMutationOperation: Sendable, Equatable {
  case createChild(parentManagedID: String, child: ShortcutHierarchyChildDraft)
  case attachExisting(parentManagedID: String, childManagedID: String)

  var kind: ShortcutHierarchyMutationRequest.OperationKind {
    switch self {
    case .createChild:
      return .createChild
    case .attachExisting:
      return .attachExisting
    }
  }
}

struct ShortcutHierarchyChildDraft: Codable, Sendable, Equatable {
  let managedID: String
  let title: String
  let notes: String?
  let dueAt: String?
  let priority: ReminderPriority?

  init(
    managedID: String,
    title: String,
    notes: String? = nil,
    dueAt: String? = nil,
    priority: ReminderPriority? = nil
  ) {
    self.managedID = managedID
    self.title = title
    self.notes = notes
    self.dueAt = dueAt
    self.priority = priority
  }

  private enum CodingKeys: String, CodingKey {
    case managedID = "managed_id"
    case title
    case notes
    case dueAt = "due_at"
    case priority
  }
}

struct ShortcutHierarchyMutationRequest: Codable, Sendable, Equatable {
  let schemaVersion: Int
  let operation: OperationKind
  let parentManagedID: String
  let childManagedID: String?
  let child: ShortcutHierarchyChildDraft?

  init(operation: ReminderHierarchyMutationOperation) {
    schemaVersion = 1
    self.operation = operation.kind
    switch operation {
    case .createChild(let parentManagedID, let child):
      self.parentManagedID = parentManagedID
      self.childManagedID = nil
      self.child = child
    case .attachExisting(let parentManagedID, let childManagedID):
      self.parentManagedID = parentManagedID
      self.childManagedID = childManagedID
      self.child = nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case operation
    case parentManagedID = "parent_managed_id"
    case childManagedID = "child_managed_id"
    case child
  }

  enum OperationKind: String, Codable, Sendable, Equatable {
    case createChild = "create_child"
    case attachExisting = "attach_existing"
  }
}

struct ShortcutHierarchyMutationResponse: Decodable, Sendable, Equatable {
  let success: Bool
  let operation: ShortcutHierarchyMutationRequest.OperationKind?
  let parentManagedID: String?
  let childManagedID: String?
  let resolvedParentCount: Int?
  let resolvedChildCount: Int?
  let childIsSubtask: Bool?
  let errorMessage: String?

  private enum CodingKeys: String, CodingKey {
    case success
    case operation
    case parentManagedID = "parent_managed_id"
    case childManagedID = "child_managed_id"
    case resolvedParentCount = "resolved_parent_count"
    case resolvedChildCount = "resolved_child_count"
    case childIsSubtask = "child_is_subtask"
    case errorMessage = "error_message"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    success = try container.decode(Bool.self, forKey: .success)
    operation = try container.decodeIfPresent(ShortcutHierarchyMutationRequest.OperationKind.self, forKey: .operation)
    parentManagedID = try Self.decodeOptionalTrimmedString(from: container, key: .parentManagedID)
    childManagedID = try Self.decodeOptionalTrimmedString(from: container, key: .childManagedID)
    resolvedParentCount = try Self.decodeOptionalInt(from: container, key: .resolvedParentCount)
    resolvedChildCount = try Self.decodeOptionalInt(from: container, key: .resolvedChildCount)
    childIsSubtask = try Self.decodeOptionalBool(from: container, key: .childIsSubtask)
    errorMessage = try Self.decodeOptionalTrimmedString(from: container, key: .errorMessage)
  }

  private static func decodeOptionalTrimmedString(
    from container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) throws -> String? {
    guard let value = try container.decodeIfPresent(String.self, forKey: key)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private static func decodeOptionalInt(
    from container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) throws -> Int? {
    if let directInt = try? container.decodeIfPresent(Int.self, forKey: key) {
      return directInt
    }
    guard let rawString = try decodeOptionalTrimmedString(from: container, key: key) else {
      return nil
    }
    return Int(rawString)
  }

  private static func decodeOptionalBool(
    from container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) throws -> Bool? {
    if let directBool = try? container.decodeIfPresent(Bool.self, forKey: key) {
      return directBool
    }
    guard let rawString = try decodeOptionalTrimmedString(from: container, key: key)?.lowercased() else {
      return nil
    }
    switch rawString {
    case "true", "1", "yes":
      return true
    case "false", "0", "no":
      return false
    default:
      return nil
    }
  }
}

enum ShortcutHierarchyMutation {
  static let shortcutName = "remindctl - Mutate Hierarchy"

  @discardableResult
  static func apply(_ operation: ReminderHierarchyMutationOperation) throws -> ShortcutHierarchyMutationResponse {
    try apply(ShortcutHierarchyMutationRequest(operation: operation))
  }

  @discardableResult
  static func apply(_ request: ShortcutHierarchyMutationRequest) throws -> ShortcutHierarchyMutationResponse {
    let encodedRequest = try encodeRequest(request)

    let runFiles = try ShortcutRunFilesFactory.make()
    defer {
      try? FileManager.default.removeItem(at: runFiles.directoryURL)
    }

    let result = try ProcessExecutor.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
      arguments: shortcutsArguments(outputPath: runFiles.outputURL.path),
      stdin: encodedRequest
    )

    if result.status != 0 {
      throw processFailure(result)
    }

    guard FileManager.default.fileExists(atPath: runFiles.outputURL.path) else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned no output file. Install the hierarchy mutation helper and see the README."
      )
    }

    let response = try decodeResponse(from: String(contentsOf: runFiles.outputURL, encoding: .utf8))
    try validateSuccessfulResponse(response, for: request)
    return response
  }

  static func validateSuccessfulResponse(
    _ response: ShortcutHierarchyMutationResponse,
    for request: ShortcutHierarchyMutationRequest
  ) throws {
    guard response.success else {
      let detail = response.errorMessage ?? "unknown error"
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" reported failure: \(detail). Install the hierarchy mutation helper and see the README."
      )
    }

    guard response.resolvedParentCount == 1 else {
      let detail = response.resolvedParentCount.map(String.init) ?? "missing"
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned an invalid resolved parent count (\(detail)). Install the hierarchy mutation helper and see the README."
      )
    }

    guard response.resolvedChildCount == 1 else {
      let detail = response.resolvedChildCount.map(String.init) ?? "missing"
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned an invalid resolved child count (\(detail)). Install the hierarchy mutation helper and see the README."
      )
    }

    guard response.childIsSubtask == true else {
      let detail = response.childIsSubtask.map(String.init) ?? "missing"
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" did not confirm child_is_subtask=true (\(detail)). Install the hierarchy mutation helper and see the README."
      )
    }

    if let operation = response.operation, operation != request.operation {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned a mismatched operation (\(operation.rawValue)). Install the hierarchy mutation helper and see the README."
      )
    }

    if let parentManagedID = response.parentManagedID, parentManagedID != request.parentManagedID {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned a mismatched parent_managed_id (\(parentManagedID)). Install the hierarchy mutation helper and see the README."
      )
    }

    if let childManagedID = response.childManagedID, childManagedID != expectedChildManagedID(for: request) {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned a mismatched child_managed_id (\(childManagedID)). Install the hierarchy mutation helper and see the README."
      )
    }
  }

  static func encodeRequest(_ request: ShortcutHierarchyMutationRequest) throws -> String {
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

  static func decodeResponse(from rawOutput: String) throws -> ShortcutHierarchyMutationResponse {
    let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned no data. Install the hierarchy mutation helper and see the README."
      )
    }

    do {
      return try JSONDecoder().decode(ShortcutHierarchyMutationResponse.self, from: Data(output.utf8))
    } catch {
      throw RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" returned invalid JSON. Install the hierarchy mutation helper and see the README."
      )
    }
  }

  private static func expectedChildManagedID(for request: ShortcutHierarchyMutationRequest) -> String? {
    switch request.operation {
    case .createChild:
      return request.child?.managedID
    case .attachExisting:
      return request.childManagedID
    }
  }

  private static func processFailure(_ result: ProcessResult) -> Error {
    let combined = [result.stderr, result.stdout]
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if combined.contains("Can’t get shortcut") || combined.contains("Can't get shortcut") {
      return RemindCoreError.operationFailed(
        "Shortcut \"\(shortcutName)\" is required for hierarchy mutation. Install the helper shortcut and see the README."
      )
    }

    let detail = combined.isEmpty ? "unknown error" : combined
    return RemindCoreError.operationFailed(
      "Shortcut \"\(shortcutName)\" failed: \(detail)"
    )
  }
}
