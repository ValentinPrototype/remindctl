import Foundation

private enum SQLiteMirrorSchemaMigrator {
  static let schemaVersion: Int64 = 2

  static func migrate(connection: SQLiteConnection) throws {
    let currentVersion = try userVersion(connection: connection)
    guard currentVersion < schemaVersion else {
      return
    }

    switch currentVersion {
    case 0, 1:
      try rebuildSchema(connection: connection)
    default:
      throw SQLiteError.executionFailed("Unsupported mirror schema version: \(currentVersion)")
    }

    try setUserVersion(schemaVersion, connection: connection)
  }

  private static func userVersion(connection: SQLiteConnection) throws -> Int64 {
    let statement = try connection.prepare("PRAGMA user_version")
    defer { statement.reset() }
    guard try statement.step() else { return 0 }
    return statement.int64(at: 0)
  }

  private static func setUserVersion(_ version: Int64, connection: SQLiteConnection) throws {
    try connection.execute("PRAGMA user_version = \(version)")
  }

  private static func rebuildSchema(connection: SQLiteConnection) throws {
    try connection.execute(
      """
      DROP TABLE IF EXISTS sync_runs;
      DROP TABLE IF EXISTS native_reminders;
      DROP TABLE IF EXISTS shortcut_contract_runs;
      DROP TABLE IF EXISTS shortcut_items;
      DROP TABLE IF EXISTS canonical_reminders;
      DROP TABLE IF EXISTS unresolved_shortcut_items;
      DROP TABLE IF EXISTS reminder_relationships;
      DROP TABLE IF EXISTS local_annotations;
      DROP TABLE IF EXISTS validation_gates;
      """
    )

    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS sync_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_kind TEXT NOT NULL,
        source_query_family TEXT NOT NULL,
        contract_id TEXT,
        started_at TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        status TEXT NOT NULL,
        item_count INTEGER NOT NULL,
        warnings_json TEXT NOT NULL,
        errors_json TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS native_reminders (
        native_calendar_item_identifier TEXT PRIMARY KEY,
        canonical_id TEXT NOT NULL,
        identity_status TEXT NOT NULL,
        canonical_managed_id TEXT,
        footer_state TEXT NOT NULL,
        source_scope_id TEXT NOT NULL,
        calendar_id TEXT NOT NULL,
        list_title TEXT NOT NULL,
        title TEXT NOT NULL,
        raw_notes TEXT,
        notes_body TEXT,
        is_completed INTEGER NOT NULL,
        completion_date TEXT,
        priority TEXT NOT NULL,
        due_date TEXT,
        created_at TEXT,
        updated_at TEXT,
        url TEXT,
        native_external_identifier TEXT,
        last_seen_at TEXT NOT NULL,
        last_native_sync_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS shortcut_contract_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contract_id TEXT NOT NULL,
        contract_version TEXT NOT NULL,
        generated_at TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        status TEXT NOT NULL,
        item_count INTEGER NOT NULL,
        warnings_json TEXT NOT NULL,
        errors_json TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS shortcut_items (
        contract_run_id INTEGER NOT NULL,
        contract_id TEXT NOT NULL,
        source_item_id TEXT NOT NULL,
        canonical_id TEXT,
        identity_status TEXT NOT NULL,
        canonical_managed_id TEXT,
        footer_state TEXT NOT NULL,
        native_calendar_item_identifier TEXT,
        native_external_identifier TEXT,
        title TEXT NOT NULL,
        raw_notes TEXT,
        notes_body TEXT,
        list_title TEXT NOT NULL,
        is_completed INTEGER NOT NULL,
        priority TEXT NOT NULL,
        due_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        url TEXT,
        matched_semantics_json TEXT NOT NULL,
        observed_tags_json TEXT NOT NULL,
        parent_source_item_id TEXT,
        child_source_item_ids_json TEXT NOT NULL,
        inserted_at TEXT NOT NULL,
        PRIMARY KEY (contract_id, source_item_id)
      );

      CREATE TABLE IF NOT EXISTS canonical_reminders (
        canonical_id TEXT PRIMARY KEY,
        identity_status TEXT NOT NULL,
        canonical_managed_id TEXT,
        footer_state TEXT NOT NULL,
        source_scope_id TEXT NOT NULL,
        calendar_id TEXT NOT NULL,
        list_title TEXT NOT NULL,
        title TEXT NOT NULL,
        raw_notes TEXT,
        notes_body TEXT,
        is_completed INTEGER NOT NULL,
        completion_date TEXT,
        priority TEXT NOT NULL,
        due_date TEXT,
        created_at TEXT,
        updated_at TEXT,
        url TEXT,
        native_calendar_item_identifier TEXT,
        native_external_identifier TEXT,
        matched_semantics_json TEXT NOT NULL,
        observed_tags_json TEXT NOT NULL,
        acquisition_sources_json TEXT NOT NULL,
        last_native_sync_at TEXT,
        last_semantic_sync_at TEXT
      );

      CREATE TABLE IF NOT EXISTS unresolved_shortcut_items (
        contract_id TEXT NOT NULL,
        source_item_id TEXT NOT NULL,
        identity_status TEXT NOT NULL,
        canonical_managed_id TEXT,
        footer_state TEXT NOT NULL,
        native_calendar_item_identifier TEXT,
        native_external_identifier TEXT,
        title TEXT NOT NULL,
        raw_notes TEXT,
        notes_body TEXT,
        list_title TEXT NOT NULL,
        is_completed INTEGER NOT NULL,
        priority TEXT NOT NULL,
        due_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        url TEXT,
        matched_semantics_json TEXT NOT NULL,
        observed_tags_json TEXT NOT NULL,
        parent_source_item_id TEXT,
        child_source_item_ids_json TEXT NOT NULL,
        inserted_at TEXT NOT NULL,
        PRIMARY KEY (contract_id, source_item_id)
      );

      CREATE TABLE IF NOT EXISTS reminder_relationships (
        contract_id TEXT NOT NULL,
        parent_source_item_id TEXT NOT NULL,
        child_source_item_id TEXT NOT NULL,
        parent_canonical_id TEXT,
        child_canonical_id TEXT,
        inserted_at TEXT NOT NULL,
        PRIMARY KEY (contract_id, parent_source_item_id, child_source_item_id)
      );

      CREATE TABLE IF NOT EXISTS local_annotations (
        canonical_id TEXT NOT NULL,
        annotation_key TEXT NOT NULL,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (canonical_id, annotation_key)
      );

      CREATE TABLE IF NOT EXISTS validation_gates (
        gate_id TEXT PRIMARY KEY,
        state TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        evidence TEXT
      );
      """
    )
  }
}

extension SQLiteMirrorRepository {
  func migrate() throws {
    try SQLiteMirrorSchemaMigrator.migrate(connection: connection)
  }

  func seedValidationGates() throws {
    let statement = try connection.prepare(
      """
      INSERT INTO validation_gates (gate_id, state, updated_at, evidence)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(gate_id) DO NOTHING
      """
    )
    defer { statement.reset() }

    let seededAt = Date.distantPast
    for gateID in ValidationGateID.allCases {
      statement.reset()
      try statement.bind(gateID.rawValue, at: 1)
      try statement.bind(ValidationGateState.pending.rawValue, at: 2)
      try statement.bind(seededAt, at: 3)
      try statement.bind(Optional<String>.none, at: 4)
      _ = try statement.step()
    }
  }
}
