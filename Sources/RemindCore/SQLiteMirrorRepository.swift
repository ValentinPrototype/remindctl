import Foundation

struct MirrorContractRunRecord {
  let status: ShortcutContractRunStatus
  let generatedAt: Date
  let warnings: [String]
  let errors: [String]
}

struct ResolvedShortcutItem {
  let contractID: ShortcutContractID
  let item: ShortcutContractItem
  let record: GTDQueryItem
}

struct ResolvedShortcutPayload {
  let payload: ValidatedShortcutContractPayload
  let resolvedItems: [ResolvedShortcutItem]
}

final class SQLiteMirrorRepository {
  let databaseURL: URL
  let connection: SQLiteConnection

  init(databaseURL: URL) throws {
    self.databaseURL = databaseURL
    self.connection = try SQLiteConnection(url: databaseURL)
    try migrate()
    try seedValidationGates()
  }

  func decodeDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return ISO8601Timestamps.parse(value)
  }

  func encodeJSONString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(value)) ?? Data("[]".utf8)
    return String(decoding: data, as: UTF8.self)
  }

  func decodeJSONStringArray(_ value: String?) -> [String]? {
    guard let value else { return nil }
    return try? JSONDecoder().decode([String].self, from: Data(value.utf8))
  }

  func decodeDiagnosticMessages(_ value: String?) -> [String] {
    guard let value else { return [] }

    if let diagnostics = try? JSONDecoder().decode([ContractDiagnostic].self, from: Data(value.utf8)) {
      return diagnostics.map(\.message)
    }

    return (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
  }
}
