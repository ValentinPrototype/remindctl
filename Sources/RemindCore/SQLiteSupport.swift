import Foundation
import SQLite3

enum SQLiteError: LocalizedError {
  case openFailed(String)
  case prepareFailed(String)
  case stepFailed(String)
  case bindFailed(String)
  case executionFailed(String)

  var errorDescription: String? {
    switch self {
    case .openFailed(let message),
      .prepareFailed(let message),
      .stepFailed(let message),
      .bindFailed(let message),
      .executionFailed(let message):
      return message
    }
  }
}

final class SQLiteConnection {
  private let database: OpaquePointer?

  init(url: URL) throws {
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    var handle: OpaquePointer?
    let result = sqlite3_open_v2(url.path, &handle, flags, nil)
    guard result == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error"
      sqlite3_close(handle)
      throw SQLiteError.openFailed(message)
    }
    self.database = handle
    sqlite3_busy_timeout(handle, 5_000)
  }

  deinit {
    sqlite3_close(database)
  }

  func execute(_ sql: String) throws {
    var errorPointer: UnsafeMutablePointer<Int8>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
    if result != SQLITE_OK {
      let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage()
      sqlite3_free(errorPointer)
      throw SQLiteError.executionFailed(message)
    }
  }

  func prepare(_ sql: String) throws -> SQLiteStatement {
    try SQLiteStatement(database: database, sql: sql)
  }

  func lastInsertRowID() -> Int64 {
    sqlite3_last_insert_rowid(database)
  }

  func lastErrorMessage() -> String {
    guard let database else { return "Unknown SQLite error" }
    return String(cString: sqlite3_errmsg(database))
  }
}

final class SQLiteStatement {
  private let database: OpaquePointer?
  private let statement: OpaquePointer?

  init(database: OpaquePointer?, sql: String) throws {
    self.database = database
    var statement: OpaquePointer?
    let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard result == SQLITE_OK, let statement else {
      throw SQLiteError.prepareFailed(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite prepare error")
    }
    self.statement = statement
  }

  deinit {
    sqlite3_finalize(statement)
  }

  func reset() {
    sqlite3_reset(statement)
    sqlite3_clear_bindings(statement)
  }

  func bind(_ value: String?, at index: Int32) throws {
    guard let statement else { return }
    if let value {
      let result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
      guard result == SQLITE_OK else {
        throw SQLiteError.bindFailed(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite bind error")
      }
    } else {
      let result = sqlite3_bind_null(statement, index)
      guard result == SQLITE_OK else {
        throw SQLiteError.bindFailed(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite bind error")
      }
    }
  }

  func bind(_ value: Int64?, at index: Int32) throws {
    guard let statement else { return }
    let result: Int32
    if let value {
      result = sqlite3_bind_int64(statement, index, value)
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    guard result == SQLITE_OK else {
      throw SQLiteError.bindFailed(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite bind error")
    }
  }

  func bind(_ value: Bool, at index: Int32) throws {
    try bind(Int64(value ? 1 : 0), at: index)
  }

  func bind(_ value: Date?, at index: Int32) throws {
    if let value {
      try bind(ISO8601Timestamps.string(from: value), at: index)
    } else {
      try bind(Optional<String>.none, at: index)
    }
  }

  @discardableResult
  func step() throws -> Bool {
    let result = sqlite3_step(statement)
    switch result {
    case SQLITE_ROW:
      return true
    case SQLITE_DONE:
      return false
    default:
      throw SQLiteError.stepFailed(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite step error")
    }
  }

  func string(at column: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: pointer)
  }

  func int64(at column: Int32) -> Int64 {
    sqlite3_column_int64(statement, column)
  }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
