import Foundation

public enum ShortcutContractValidationError: LocalizedError, Equatable {
  case invalidJSON(String)
  case invalidEnvelope(String)
  case invalidItem(String)

  public var errorDescription: String? {
    switch self {
    case .invalidJSON(let message), .invalidEnvelope(let message), .invalidItem(let message):
      return message
    }
  }
}

private struct RawContractDiagnostic: Decodable {
  let code: String
  let message: String
  let retryable: Bool?
}

private struct RawShortcutContractItem: Decodable {
  let sourceItemID: String
  let nativeCalendarItemIdentifier: String?
  let nativeExternalIdentifier: String?
  let title: String
  let notes: String?
  let listTitle: String
  let isCompleted: Bool
  let priority: String
  let dueAt: String?
  let createdAt: String?
  let updatedAt: String?
  let url: String?
  let matchedSemantics: [String]
  let observedTags: [String]?
  let parentSourceItemID: String?
  let childSourceItemIDs: [String]?

  enum CodingKeys: String, CodingKey {
    case sourceItemID = "source_item_id"
    case nativeCalendarItemIdentifier = "native_calendar_item_identifier"
    case nativeExternalIdentifier = "native_external_identifier"
    case title
    case notes
    case listTitle = "list_title"
    case isCompleted = "is_completed"
    case priority
    case dueAt = "due_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case url
    case matchedSemantics = "matched_semantics"
    case observedTags = "observed_tags"
    case parentSourceItemID = "parent_source_item_id"
    case childSourceItemIDs = "child_source_item_ids"
  }
}

private struct RawShortcutContractEnvelope: Decodable {
  let contractID: String
  let contractVersion: String
  let generatedAt: String
  let status: String
  let items: [RawShortcutContractItem]
  let warnings: [RawContractDiagnostic]
  let errors: [RawContractDiagnostic]

  enum CodingKeys: String, CodingKey {
    case contractID = "contract_id"
    case contractVersion = "contract_version"
    case generatedAt = "generated_at"
    case status
    case items
    case warnings
    case errors
  }
}

public enum ShortcutContractValidator {
  public static func validate(
    data: Data,
    expectedContractID: ShortcutContractID
  ) throws -> ValidatedShortcutContractPayload {
    let decoder = JSONDecoder()
    let rawEnvelope: RawShortcutContractEnvelope
    do {
      rawEnvelope = try decoder.decode(RawShortcutContractEnvelope.self, from: data)
    } catch {
      throw ShortcutContractValidationError.invalidJSON("Failed to decode contract payload: \(error.localizedDescription)")
    }

    guard rawEnvelope.contractID == expectedContractID.rawValue else {
      throw ShortcutContractValidationError.invalidEnvelope(
        "Contract ID mismatch. Expected \(expectedContractID.rawValue), got \(rawEnvelope.contractID)."
      )
    }

    guard rawEnvelope.contractVersion == "v1" else {
      throw ShortcutContractValidationError.invalidEnvelope(
        "Unsupported contract version for \(expectedContractID.rawValue): \(rawEnvelope.contractVersion)"
      )
    }

    guard let status = ShortcutContractRunStatus(rawValue: rawEnvelope.status) else {
      throw ShortcutContractValidationError.invalidEnvelope(
        "Invalid contract status for \(expectedContractID.rawValue): \(rawEnvelope.status)"
      )
    }

    guard let generatedAt = parseRequiredUTCDate(rawEnvelope.generatedAt, fieldName: "generated_at") else {
      throw ShortcutContractValidationError.invalidEnvelope("Invalid generated_at timestamp in \(expectedContractID.rawValue)")
    }

    if status == .ok && rawEnvelope.items.isEmpty {
      throw ShortcutContractValidationError.invalidEnvelope("Contract status ok requires at least one item")
    }

    if status != .ok && rawEnvelope.items.isEmpty == false {
      throw ShortcutContractValidationError.invalidEnvelope("Only ok contract payloads may carry items")
    }

    let warnings = try rawEnvelope.warnings.map { rawWarning in
      try validateDiagnostic(rawWarning, isError: false)
    }
    let errors = try rawEnvelope.errors.map { rawError in
      try validateDiagnostic(rawError, isError: true)
    }

    if status == .error && errors.isEmpty {
      throw ShortcutContractValidationError.invalidEnvelope("Contract status error requires at least one error object")
    }

    let items = try rawEnvelope.items.map { rawItem in
      try validateItem(rawItem, expectedContractID: expectedContractID)
    }

    if items != items.sorted(by: contractItemLessThan) {
      throw ShortcutContractValidationError.invalidEnvelope(
        "Items for \(expectedContractID.rawValue) are not in deterministic order"
      )
    }

    return ValidatedShortcutContractPayload(
      contractID: expectedContractID,
      contractVersion: rawEnvelope.contractVersion,
      generatedAt: generatedAt,
      status: status,
      items: items,
      warnings: warnings,
      errors: errors
    )
  }

  private static func validateDiagnostic(
    _ rawDiagnostic: RawContractDiagnostic,
    isError: Bool
  ) throws -> ContractDiagnostic {
    guard rawDiagnostic.code.isEmpty == false else {
      throw ShortcutContractValidationError.invalidEnvelope("Diagnostic code must not be empty")
    }
    guard rawDiagnostic.message.isEmpty == false else {
      throw ShortcutContractValidationError.invalidEnvelope("Diagnostic message must not be empty")
    }
    if isError, rawDiagnostic.retryable == nil {
      throw ShortcutContractValidationError.invalidEnvelope("Error diagnostics must provide retryable")
    }
    return ContractDiagnostic(
      code: rawDiagnostic.code,
      message: rawDiagnostic.message,
      retryable: rawDiagnostic.retryable
    )
  }

  private static func validateItem(
    _ rawItem: RawShortcutContractItem,
    expectedContractID: ShortcutContractID
  ) throws -> ShortcutContractItem {
    guard rawItem.sourceItemID.isEmpty == false else {
      throw ShortcutContractValidationError.invalidItem("source_item_id must not be empty")
    }
    guard rawItem.title.isEmpty == false else {
      throw ShortcutContractValidationError.invalidItem("title must not be empty")
    }
    guard rawItem.listTitle.isEmpty == false else {
      throw ShortcutContractValidationError.invalidItem("list_title must not be empty")
    }

    guard let priority = ReminderPriority(rawValue: rawItem.priority) else {
      throw ShortcutContractValidationError.invalidItem("Invalid priority value: \(rawItem.priority)")
    }

    let dueAt = try parseOptionalUTCDate(rawItem.dueAt, fieldName: "due_at")
    let createdAt = try parseOptionalUTCDate(rawItem.createdAt, fieldName: "created_at")
    let updatedAt = try parseOptionalUTCDate(rawItem.updatedAt, fieldName: "updated_at")

    try validateSemantics(rawItem.matchedSemantics, fieldName: "matched_semantics")
    if let observedTags = rawItem.observedTags {
      try validateSemantics(observedTags, fieldName: "observed_tags")
    }

    switch expectedContractID {
    case .activeProjects:
      try requireIncomplete(item: rawItem, semantic: "active-project")
    case .nextActions:
      try requireIncomplete(item: rawItem, semantic: "next-action")
    case .waitingOns:
      try requireIncomplete(item: rawItem, semantic: "waiting-on")
    case .productivityHierarchy:
      break
    case .productivityRecentlyUpdated:
      break
    }

    let childSourceItemIDs = rawItem.childSourceItemIDs ?? []
    if expectedContractID == .productivityHierarchy, rawItem.childSourceItemIDs == nil {
      throw ShortcutContractValidationError.invalidItem(
        "Hierarchy contract items must include child_source_item_ids"
      )
    }

    let parsedNotes = CanonicalNoteFooter.parse(rawNotes: rawItem.notes)

    return ShortcutContractItem(
      sourceItemID: rawItem.sourceItemID,
      nativeCalendarItemIdentifier: rawItem.nativeCalendarItemIdentifier,
      nativeExternalIdentifier: rawItem.nativeExternalIdentifier,
      title: rawItem.title,
      rawNotes: parsedNotes.rawNotes,
      notes: parsedNotes.notesBody,
      notesBody: parsedNotes.notesBody,
      canonicalManagedID: parsedNotes.canonicalManagedID,
      footerState: parsedNotes.footerState,
      listTitle: rawItem.listTitle,
      isCompleted: rawItem.isCompleted,
      priority: priority,
      dueAt: dueAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      url: rawItem.url,
      matchedSemantics: rawItem.matchedSemantics,
      observedTags: rawItem.observedTags,
      parentSourceItemID: rawItem.parentSourceItemID,
      childSourceItemIDs: childSourceItemIDs
    )
  }

  private static func parseRequiredUTCDate(_ rawValue: String, fieldName: String) -> Date? {
    guard ISO8601Timestamps.isUTCString(rawValue) else { return nil }
    return ISO8601Timestamps.parse(rawValue)
  }

  private static func parseOptionalUTCDate(_ rawValue: String?, fieldName: String) throws -> Date? {
    guard let rawValue else { return nil }
    guard let parsed = parseRequiredUTCDate(rawValue, fieldName: fieldName) else {
      throw ShortcutContractValidationError.invalidItem("Invalid UTC timestamp for \(fieldName): \(rawValue)")
    }
    return parsed
  }

  private static func validateSemantics(_ values: [String], fieldName: String) throws {
    for value in values {
      if value.isEmpty {
        throw ShortcutContractValidationError.invalidItem("\(fieldName) values must not be empty")
      }
      if value.contains("#") {
        throw ShortcutContractValidationError.invalidItem("\(fieldName) values must not include # prefixes")
      }
      if value != value.lowercased() {
        throw ShortcutContractValidationError.invalidItem("\(fieldName) values must be normalized lowercase")
      }
    }
  }

  private static func requireIncomplete(
    item: RawShortcutContractItem,
    semantic: String
  ) throws {
    if item.isCompleted {
      throw ShortcutContractValidationError.invalidItem("Completed reminders are not allowed in semantic slice contracts")
    }
    guard item.matchedSemantics.contains(semantic) else {
      throw ShortcutContractValidationError.invalidItem("Expected semantic \(semantic) in matched_semantics")
    }
  }

  private static func contractItemLessThan(
    lhs: ShortcutContractItem,
    rhs: ShortcutContractItem
  ) -> Bool {
    if lhs.listTitle != rhs.listTitle {
      return lhs.listTitle.localizedCaseInsensitiveCompare(rhs.listTitle) == .orderedAscending
    }

    switch (lhs.dueAt, rhs.dueAt) {
    case let (left?, right?):
      if left != right {
        return left < right
      }
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    case (.none, .none):
      break
    }

    if lhs.title != rhs.title {
      return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    return lhs.sourceItemID < rhs.sourceItemID
  }
}

public struct ShortcutContractRunner {
  public init() {}

  public func loadFixture(
    contractID: ShortcutContractID,
    directoryURL: URL,
    variant: String = "ok"
  ) throws -> ValidatedShortcutContractPayload {
    let fileURL = directoryURL.appendingPathComponent("\(contractID.fixtureBaseName).\(variant).json")
    let data = try Data(contentsOf: fileURL)
    return try ShortcutContractValidator.validate(data: data, expectedContractID: contractID)
  }

  public func runLive(contractID: ShortcutContractID) throws -> ValidatedShortcutContractPayload {
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "remindctl-gtd-\(UUID().uuidString).json",
      isDirectory: false
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "shortcuts",
      "run",
      contractID.deployedShortcutName,
      "--output-path",
      outputURL.path,
      "--output-type",
      "public.json",
    ]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw RemindCoreError.operationFailed("Failed to launch shortcuts for \(contractID.rawValue): \(error.localizedDescription)")
    }

    defer {
      try? FileManager.default.removeItem(at: outputURL)
    }

    if process.terminationStatus != 0 {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let stderr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw RemindCoreError.operationFailed(
        "Shortcut execution failed for \(contractID.rawValue): \(stderr.isEmpty ? "unknown error" : stderr)"
      )
    }

    let data = try Data(contentsOf: outputURL)
    return try ShortcutContractValidator.validate(data: data, expectedContractID: contractID)
  }
}
