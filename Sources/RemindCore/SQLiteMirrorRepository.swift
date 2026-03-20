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
  private let connection: SQLiteConnection

  init(databaseURL: URL) throws {
    self.databaseURL = databaseURL
    self.connection = try SQLiteConnection(url: databaseURL)
    try migrate()
    try seedValidationGates()
  }

  func replaceSnapshot(
    nativeReminders: [NativeReminderRecord],
    canonicalRecords: [CanonicalReminderRecord],
    resolvedShortcutPayloads: [ResolvedShortcutPayload],
    completedAt: Date
  ) throws -> MirrorSyncSummary {
    let canonicalByNativeIdentifier = Dictionary(
      uniqueKeysWithValues: canonicalRecords.compactMap { record in
        record.nativeCalendarItemIdentifier.map { ($0, record) }
      }
    )

    try connection.execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      try clearCurrentSnapshot()

      try insertNativeSyncRun(itemCount: nativeReminders.count, completedAt: completedAt)

      for reminder in nativeReminders {
        try insertNativeReminder(
          reminder,
          canonicalRecord: canonicalByNativeIdentifier[reminder.nativeCalendarItemIdentifier],
          seenAt: completedAt
        )
      }

      for canonicalRecord in canonicalRecords {
        try insertCanonicalReminder(canonicalRecord)
      }

      var unresolvedCount = 0
      for resolvedPayload in resolvedShortcutPayloads {
        let contractRunID = try insertShortcutContractRun(
          resolvedPayload.payload,
          completedAt: completedAt
        )

        for item in resolvedPayload.resolvedItems {
          try insertShortcutItem(item, contractRunID: contractRunID, insertedAt: completedAt)
          if item.record.canonicalID == nil {
            unresolvedCount += 1
            try insertUnresolvedShortcutItem(item, insertedAt: completedAt)
          }
        }

        if resolvedPayload.payload.contractID == .productivityHierarchy {
          try insertRelationships(
            resolvedPayload.resolvedItems,
            insertedAt: completedAt
          )
        }
      }

      try connection.execute("COMMIT")

      return MirrorSyncSummary(
        databasePath: databaseURL.path,
        nativeReminderCount: nativeReminders.count,
        canonicalReminderCount: canonicalRecords.count,
        unresolvedShortcutCount: unresolvedCount,
        contractRunCount: resolvedShortcutPayloads.count,
        completedAt: completedAt
      )
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  func fetchCanonicalQueryItems() throws -> [GTDQueryItem] {
    let statement = try connection.prepare(
      """
      SELECT canonical_id, identity_status, title, notes, list_title, is_completed, priority,
             due_date, created_at, updated_at, matched_semantics_json, observed_tags_json,
             acquisition_sources_json
      FROM canonical_reminders
      """
    )
    defer { statement.reset() }

    var items: [GTDQueryItem] = []
    while try statement.step() {
      items.append(
        GTDQueryItem(
          id: statement.string(at: 0) ?? UUID().uuidString,
          canonicalID: statement.string(at: 0),
          identityStatus: IdentityStatus(rawValue: statement.string(at: 1) ?? "") ?? .localOnlyUnstable,
          title: statement.string(at: 2) ?? "",
          notes: statement.string(at: 3),
          listTitle: statement.string(at: 4) ?? "",
          isCompleted: statement.int64(at: 5) == 1,
          priority: ReminderPriority(rawValue: statement.string(at: 6) ?? "") ?? .none,
          dueAt: decodeDate(statement.string(at: 7)),
          createdAt: decodeDate(statement.string(at: 8)),
          updatedAt: decodeDate(statement.string(at: 9)),
          matchedSemantics: decodeJSONStringArray(statement.string(at: 10)) ?? [],
          observedTags: decodeJSONStringArray(statement.string(at: 11)) ?? [],
          acquisitionSources: decodeJSONStringArray(statement.string(at: 12)) ?? []
        )
      )
    }
    return items
  }

  func fetchUnresolvedItems(for contractID: ShortcutContractID) throws -> [GTDQueryItem] {
    let statement = try connection.prepare(
      """
      SELECT source_item_id, identity_status, title, notes, list_title, is_completed, priority,
             due_at, created_at, updated_at, matched_semantics_json, observed_tags_json
      FROM unresolved_shortcut_items
      WHERE contract_id = ?
      """
    )
    defer { statement.reset() }
    try statement.bind(contractID.rawValue, at: 1)

    var items: [GTDQueryItem] = []
    while try statement.step() {
      let sourceItemID = statement.string(at: 0) ?? UUID().uuidString
      items.append(
        GTDQueryItem(
          id: "\(contractID.rawValue)::\(sourceItemID)",
          canonicalID: nil,
          identityStatus: IdentityStatus(rawValue: statement.string(at: 1) ?? "") ?? .shortcutUnresolved,
          title: statement.string(at: 2) ?? "",
          notes: statement.string(at: 3),
          listTitle: statement.string(at: 4) ?? "",
          isCompleted: statement.int64(at: 5) == 1,
          priority: ReminderPriority(rawValue: statement.string(at: 6) ?? "") ?? .none,
          dueAt: decodeDate(statement.string(at: 7)),
          createdAt: decodeDate(statement.string(at: 8)),
          updatedAt: decodeDate(statement.string(at: 9)),
          matchedSemantics: decodeJSONStringArray(statement.string(at: 10)) ?? [],
          observedTags: decodeJSONStringArray(statement.string(at: 11)) ?? [],
          acquisitionSources: [contractID.rawValue]
        )
      )
    }
    return items
  }

  func latestNativeSyncAt() throws -> Date? {
    let statement = try connection.prepare(
      """
      SELECT completed_at
      FROM sync_runs
      WHERE source_kind = ?
      ORDER BY id DESC
      LIMIT 1
      """
    )
    defer { statement.reset() }
    try statement.bind(AcquisitionSourceKind.nativeEventKit.rawValue, at: 1)
    guard try statement.step() else { return nil }
    return decodeDate(statement.string(at: 0))
  }

  func latestContractRun(for contractID: ShortcutContractID) throws -> MirrorContractRunRecord? {
    let statement = try connection.prepare(
      """
      SELECT status, generated_at, warnings_json, errors_json
      FROM shortcut_contract_runs
      WHERE contract_id = ?
      ORDER BY id DESC
      LIMIT 1
      """
    )
    defer { statement.reset() }
    try statement.bind(contractID.rawValue, at: 1)
    guard try statement.step() else { return nil }

    return MirrorContractRunRecord(
      status: ShortcutContractRunStatus(rawValue: statement.string(at: 0) ?? "") ?? .error,
      generatedAt: decodeDate(statement.string(at: 1)) ?? Date.distantPast,
      warnings: decodeDiagnosticMessages(statement.string(at: 2)),
      errors: decodeDiagnosticMessages(statement.string(at: 3))
    )
  }

  func listValidationGates() throws -> [ValidationGateRecord] {
    let statement = try connection.prepare(
      """
      SELECT gate_id, state, updated_at, evidence
      FROM validation_gates
      ORDER BY gate_id
      """
    )
    defer { statement.reset() }

    var recordsByID: [ValidationGateID: ValidationGateRecord] = [:]
    while try statement.step() {
      guard let gateID = ValidationGateID(rawValue: statement.string(at: 0) ?? "") else {
        continue
      }

      recordsByID[gateID] = ValidationGateRecord(
        gateID: gateID,
        state: ValidationGateState(rawValue: statement.string(at: 1) ?? "") ?? .pending,
        updatedAt: decodeDate(statement.string(at: 2)) ?? Date.distantPast,
        evidence: statement.string(at: 3)
      )
    }

    return ValidationGateID.allCases.map { gateID in
      recordsByID[gateID] ?? ValidationGateRecord(
        gateID: gateID,
        state: .pending,
        updatedAt: Date.distantPast,
        evidence: nil
      )
    }
  }

  func validationGate(_ gateID: ValidationGateID) throws -> ValidationGateRecord {
    try listValidationGates().first(where: { $0.gateID == gateID }) ?? ValidationGateRecord(
      gateID: gateID,
      state: .pending,
      updatedAt: Date.distantPast,
      evidence: nil
    )
  }

  func setValidationGate(
    _ gateID: ValidationGateID,
    state: ValidationGateState,
    evidence: String?,
    updatedAt: Date
  ) throws -> ValidationGateRecord {
    let statement = try connection.prepare(
      """
      INSERT INTO validation_gates (gate_id, state, updated_at, evidence)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(gate_id) DO UPDATE SET
        state = excluded.state,
        updated_at = excluded.updated_at,
        evidence = excluded.evidence
      """
    )
    defer { statement.reset() }
    try statement.bind(gateID.rawValue, at: 1)
    try statement.bind(state.rawValue, at: 2)
    try statement.bind(updatedAt, at: 3)
    try statement.bind(evidence, at: 4)
    _ = try statement.step()

    return ValidationGateRecord(
      gateID: gateID,
      state: state,
      updatedAt: updatedAt,
      evidence: evidence
    )
  }

  private func migrate() throws {
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
        source_scope_id TEXT NOT NULL,
        calendar_id TEXT NOT NULL,
        list_title TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT,
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
        native_calendar_item_identifier TEXT,
        native_external_identifier TEXT,
        title TEXT NOT NULL,
        notes TEXT,
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
        source_scope_id TEXT NOT NULL,
        calendar_id TEXT NOT NULL,
        list_title TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT,
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
        native_calendar_item_identifier TEXT,
        native_external_identifier TEXT,
        title TEXT NOT NULL,
        notes TEXT,
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

  private func seedValidationGates() throws {
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

  private func clearCurrentSnapshot() throws {
    try connection.execute(
      """
      DELETE FROM native_reminders;
      DELETE FROM shortcut_items;
      DELETE FROM canonical_reminders;
      DELETE FROM unresolved_shortcut_items;
      DELETE FROM reminder_relationships;
      """
    )
  }

  private func insertNativeSyncRun(itemCount: Int, completedAt: Date) throws {
    let statement = try connection.prepare(
      """
      INSERT INTO sync_runs (
        source_kind, source_query_family, contract_id, started_at, completed_at, status, item_count,
        warnings_json, errors_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(AcquisitionSourceKind.nativeEventKit.rawValue, at: 1)
    try statement.bind("full-native-sync", at: 2)
    try statement.bind(Optional<String>.none, at: 3)
    try statement.bind(completedAt, at: 4)
    try statement.bind(completedAt, at: 5)
    try statement.bind("ok", at: 6)
    try statement.bind(Int64(itemCount), at: 7)
    try statement.bind(encodeJSONString([] as [String]), at: 8)
    try statement.bind(encodeJSONString([] as [String]), at: 9)
    _ = try statement.step()
  }

  private func insertNativeReminder(
    _ reminder: NativeReminderRecord,
    canonicalRecord: CanonicalReminderRecord?,
    seenAt: Date
  ) throws {
    let statement = try connection.prepare(
      """
      INSERT INTO native_reminders (
        native_calendar_item_identifier, canonical_id, identity_status, source_scope_id, calendar_id,
        list_title, title, notes, is_completed, completion_date, priority, due_date, created_at,
        updated_at, url, native_external_identifier, last_seen_at, last_native_sync_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(reminder.nativeCalendarItemIdentifier, at: 1)
    try statement.bind(canonicalRecord?.canonicalID ?? reminder.nativeCalendarItemIdentifier, at: 2)
    try statement.bind(canonicalRecord?.identityStatus.rawValue ?? IdentityStatus.localOnlyUnstable.rawValue, at: 3)
    try statement.bind(reminder.sourceScopeID, at: 4)
    try statement.bind(reminder.calendarID, at: 5)
    try statement.bind(reminder.listTitle, at: 6)
    try statement.bind(reminder.title, at: 7)
    try statement.bind(reminder.notes, at: 8)
    try statement.bind(reminder.isCompleted, at: 9)
    try statement.bind(reminder.completionDate, at: 10)
    try statement.bind(reminder.priority.rawValue, at: 11)
    try statement.bind(reminder.dueDate, at: 12)
    try statement.bind(reminder.createdAt, at: 13)
    try statement.bind(reminder.updatedAt, at: 14)
    try statement.bind(reminder.url, at: 15)
    try statement.bind(reminder.nativeExternalIdentifier, at: 16)
    try statement.bind(seenAt, at: 17)
    try statement.bind(seenAt, at: 18)
    _ = try statement.step()
  }

  private func insertCanonicalReminder(_ reminder: CanonicalReminderRecord) throws {
    let statement = try connection.prepare(
      """
      INSERT INTO canonical_reminders (
        canonical_id, identity_status, source_scope_id, calendar_id, list_title, title, notes,
        is_completed, completion_date, priority, due_date, created_at, updated_at, url,
        native_calendar_item_identifier, native_external_identifier, matched_semantics_json,
        observed_tags_json, acquisition_sources_json, last_native_sync_at, last_semantic_sync_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(reminder.canonicalID, at: 1)
    try statement.bind(reminder.identityStatus.rawValue, at: 2)
    try statement.bind(reminder.sourceScopeID, at: 3)
    try statement.bind(reminder.calendarID, at: 4)
    try statement.bind(reminder.listTitle, at: 5)
    try statement.bind(reminder.title, at: 6)
    try statement.bind(reminder.notes, at: 7)
    try statement.bind(reminder.isCompleted, at: 8)
    try statement.bind(reminder.completionDate, at: 9)
    try statement.bind(reminder.priority.rawValue, at: 10)
    try statement.bind(reminder.dueDate, at: 11)
    try statement.bind(reminder.createdAt, at: 12)
    try statement.bind(reminder.updatedAt, at: 13)
    try statement.bind(reminder.url, at: 14)
    try statement.bind(reminder.nativeCalendarItemIdentifier, at: 15)
    try statement.bind(reminder.nativeExternalIdentifier, at: 16)
    try statement.bind(encodeJSONString(reminder.matchedSemantics), at: 17)
    try statement.bind(encodeJSONString(reminder.observedTags), at: 18)
    try statement.bind(encodeJSONString(reminder.acquisitionSources), at: 19)
    try statement.bind(reminder.lastNativeSyncAt, at: 20)
    try statement.bind(reminder.lastSemanticSyncAt, at: 21)
    _ = try statement.step()
  }

  private func insertShortcutContractRun(
    _ payload: ValidatedShortcutContractPayload,
    completedAt: Date
  ) throws -> Int64 {
    let syncRunStatement = try connection.prepare(
      """
      INSERT INTO sync_runs (
        source_kind, source_query_family, contract_id, started_at, completed_at, status, item_count,
        warnings_json, errors_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { syncRunStatement.reset() }
    try syncRunStatement.bind(AcquisitionSourceKind.shortcut.rawValue, at: 1)
    try syncRunStatement.bind(payload.contractID.sourceQueryFamily, at: 2)
    try syncRunStatement.bind(payload.contractID.rawValue, at: 3)
    try syncRunStatement.bind(payload.generatedAt, at: 4)
    try syncRunStatement.bind(completedAt, at: 5)
    try syncRunStatement.bind(payload.status.rawValue, at: 6)
    try syncRunStatement.bind(Int64(payload.items.count), at: 7)
    try syncRunStatement.bind(encodeJSONString(payload.warnings.map(\.message)), at: 8)
    try syncRunStatement.bind(encodeJSONString(payload.errors.map(\.message)), at: 9)
    _ = try syncRunStatement.step()

    let statement = try connection.prepare(
      """
      INSERT INTO shortcut_contract_runs (
        contract_id, contract_version, generated_at, completed_at, status, item_count,
        warnings_json, errors_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(payload.contractID.rawValue, at: 1)
    try statement.bind(payload.contractVersion, at: 2)
    try statement.bind(payload.generatedAt, at: 3)
    try statement.bind(completedAt, at: 4)
    try statement.bind(payload.status.rawValue, at: 5)
    try statement.bind(Int64(payload.items.count), at: 6)
    try statement.bind(encodeJSONString(payload.warnings), at: 7)
    try statement.bind(encodeJSONString(payload.errors), at: 8)
    _ = try statement.step()
    return connection.lastInsertRowID()
  }

  private func insertShortcutItem(
    _ resolvedItem: ResolvedShortcutItem,
    contractRunID: Int64,
    insertedAt: Date
  ) throws {
    let statement = try connection.prepare(
      """
      INSERT INTO shortcut_items (
        contract_run_id, contract_id, source_item_id, canonical_id, identity_status,
        native_calendar_item_identifier, native_external_identifier, title, notes, list_title,
        is_completed, priority, due_at, created_at, updated_at, url, matched_semantics_json,
        observed_tags_json, parent_source_item_id, child_source_item_ids_json, inserted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(contractRunID, at: 1)
    try statement.bind(resolvedItem.contractID.rawValue, at: 2)
    try statement.bind(resolvedItem.item.sourceItemID, at: 3)
    try statement.bind(resolvedItem.record.canonicalID, at: 4)
    try statement.bind(resolvedItem.record.identityStatus.rawValue, at: 5)
    try statement.bind(resolvedItem.item.nativeCalendarItemIdentifier, at: 6)
    try statement.bind(resolvedItem.item.nativeExternalIdentifier, at: 7)
    try statement.bind(resolvedItem.item.title, at: 8)
    try statement.bind(resolvedItem.item.notes, at: 9)
    try statement.bind(resolvedItem.item.listTitle, at: 10)
    try statement.bind(resolvedItem.item.isCompleted, at: 11)
    try statement.bind(resolvedItem.item.priority.rawValue, at: 12)
    try statement.bind(resolvedItem.item.dueAt, at: 13)
    try statement.bind(resolvedItem.item.createdAt, at: 14)
    try statement.bind(resolvedItem.item.updatedAt, at: 15)
    try statement.bind(resolvedItem.item.url, at: 16)
    try statement.bind(encodeJSONString(resolvedItem.item.matchedSemantics), at: 17)
    try statement.bind(encodeJSONString(resolvedItem.item.observedTags ?? []), at: 18)
    try statement.bind(resolvedItem.item.parentSourceItemID, at: 19)
    try statement.bind(encodeJSONString(resolvedItem.item.childSourceItemIDs), at: 20)
    try statement.bind(insertedAt, at: 21)
    _ = try statement.step()
  }

  private func insertUnresolvedShortcutItem(
    _ resolvedItem: ResolvedShortcutItem,
    insertedAt: Date
  ) throws {
    let statement = try connection.prepare(
      """
      INSERT INTO unresolved_shortcut_items (
        contract_id, source_item_id, identity_status, native_calendar_item_identifier,
        native_external_identifier, title, notes, list_title, is_completed, priority, due_at,
        created_at, updated_at, url, matched_semantics_json, observed_tags_json,
        parent_source_item_id, child_source_item_ids_json, inserted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(resolvedItem.contractID.rawValue, at: 1)
    try statement.bind(resolvedItem.item.sourceItemID, at: 2)
    try statement.bind(IdentityStatus.shortcutUnresolved.rawValue, at: 3)
    try statement.bind(resolvedItem.item.nativeCalendarItemIdentifier, at: 4)
    try statement.bind(resolvedItem.item.nativeExternalIdentifier, at: 5)
    try statement.bind(resolvedItem.item.title, at: 6)
    try statement.bind(resolvedItem.item.notes, at: 7)
    try statement.bind(resolvedItem.item.listTitle, at: 8)
    try statement.bind(resolvedItem.item.isCompleted, at: 9)
    try statement.bind(resolvedItem.item.priority.rawValue, at: 10)
    try statement.bind(resolvedItem.item.dueAt, at: 11)
    try statement.bind(resolvedItem.item.createdAt, at: 12)
    try statement.bind(resolvedItem.item.updatedAt, at: 13)
    try statement.bind(resolvedItem.item.url, at: 14)
    try statement.bind(encodeJSONString(resolvedItem.item.matchedSemantics), at: 15)
    try statement.bind(encodeJSONString(resolvedItem.item.observedTags ?? []), at: 16)
    try statement.bind(resolvedItem.item.parentSourceItemID, at: 17)
    try statement.bind(encodeJSONString(resolvedItem.item.childSourceItemIDs), at: 18)
    try statement.bind(insertedAt, at: 19)
    _ = try statement.step()
  }

  private func insertRelationships(
    _ resolvedItems: [ResolvedShortcutItem],
    insertedAt: Date
  ) throws {
    let canonicalLookup = Dictionary(uniqueKeysWithValues: resolvedItems.map {
      ($0.item.sourceItemID, $0.record.canonicalID)
    })

    for resolvedItem in resolvedItems {
      for childSourceItemID in resolvedItem.item.childSourceItemIDs {
        let statement = try connection.prepare(
          """
          INSERT INTO reminder_relationships (
            contract_id, parent_source_item_id, child_source_item_id, parent_canonical_id,
            child_canonical_id, inserted_at
          ) VALUES (?, ?, ?, ?, ?, ?)
          """
        )
        defer { statement.reset() }
        try statement.bind(resolvedItem.contractID.rawValue, at: 1)
        try statement.bind(resolvedItem.item.sourceItemID, at: 2)
        try statement.bind(childSourceItemID, at: 3)
        try statement.bind(canonicalLookup[resolvedItem.item.sourceItemID] ?? nil, at: 4)
        try statement.bind(canonicalLookup[childSourceItemID] ?? nil, at: 5)
        try statement.bind(insertedAt, at: 6)
        _ = try statement.step()
      }
    }
  }

  private func decodeDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return ISO8601Timestamps.parse(value)
  }

  private func encodeJSONString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(value)) ?? Data("[]".utf8)
    return String(decoding: data, as: UTF8.self)
  }

  private func decodeJSONStringArray(_ value: String?) -> [String]? {
    guard let value else { return nil }
    return try? JSONDecoder().decode([String].self, from: Data(value.utf8))
  }

  private func decodeDiagnosticMessages(_ value: String?) -> [String] {
    guard let value else { return [] }

    if let diagnostics = try? JSONDecoder().decode([ContractDiagnostic].self, from: Data(value.utf8)) {
      return diagnostics.map(\.message)
    }

    return (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
  }
}
