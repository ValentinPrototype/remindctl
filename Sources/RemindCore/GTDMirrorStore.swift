import Foundation

public actor GTDMirrorStore {
  private struct ContractRunRecord {
    let status: ShortcutContractRunStatus
    let generatedAt: Date
    let warnings: [String]
    let errors: [String]
  }

  private let databaseURL: URL
  private let connection: SQLiteConnection
  private let canonicalizationPolicy: CanonicalizationPolicy

  public init(
    databaseURL: URL? = nil,
    canonicalizationPolicy: CanonicalizationPolicy = CanonicalizationPolicy()
  ) throws {
    let resolvedURL = try databaseURL ?? MirrorPaths.defaultDatabaseURL()
    self.databaseURL = resolvedURL
    self.connection = try SQLiteConnection(url: resolvedURL)
    self.canonicalizationPolicy = canonicalizationPolicy
    try Self.migrate(connection: connection)
  }

  public func replaceSnapshot(
    nativeReminders: [NativeReminderRecord],
    shortcutPayloads: [ValidatedShortcutContractPayload],
    completedAt: Date = Date()
  ) throws -> MirrorSyncSummary {
    let snapshotTimestamp = completedAt
    var canonicalRecordsByID: [String: CanonicalReminderRecord] = [:]
    var canonicalOrder: [String] = []
    var nativeLookupByCalendarItemID: [String: CanonicalReminderRecord] = [:]
    var nativeLookupByExternalIdentifier: [String: [CanonicalReminderRecord]] = [:]

    for reminder in nativeReminders.sorted(by: Self.nativeReminderLessThan) {
      let identity = canonicalizationPolicy.canonicalIdentity(for: reminder)
      let canonicalRecord = CanonicalReminderRecord(
        id: identity.canonicalID,
        canonicalID: identity.canonicalID,
        identityStatus: identity.identityStatus,
        sourceScopeID: reminder.sourceScopeID,
        calendarID: reminder.calendarID,
        listTitle: reminder.listTitle,
        title: reminder.title,
        notes: reminder.notes,
        isCompleted: reminder.isCompleted,
        completionDate: reminder.completionDate,
        priority: reminder.priority,
        dueDate: reminder.dueDate,
        createdAt: reminder.createdAt,
        updatedAt: reminder.updatedAt,
        url: reminder.url,
        nativeCalendarItemIdentifier: reminder.nativeCalendarItemIdentifier,
        nativeExternalIdentifier: reminder.nativeExternalIdentifier,
        matchedSemantics: [],
        observedTags: [],
        acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
        lastNativeSyncAt: snapshotTimestamp,
        lastSemanticSyncAt: nil
      )
      canonicalRecordsByID[canonicalRecord.canonicalID] = canonicalRecord
      canonicalOrder.append(canonicalRecord.canonicalID)
      nativeLookupByCalendarItemID[reminder.nativeCalendarItemIdentifier] = canonicalRecord
      if let externalIdentifier = reminder.nativeExternalIdentifier, externalIdentifier.isEmpty == false {
        nativeLookupByExternalIdentifier[externalIdentifier, default: []].append(canonicalRecord)
      }
    }

    let resolvedShortcutItems = try shortcutPayloads.map { payload in
      try resolveShortcutPayload(
        payload,
        nativeLookupByCalendarItemID: nativeLookupByCalendarItemID,
        nativeLookupByExternalIdentifier: nativeLookupByExternalIdentifier,
        canonicalRecordsByID: &canonicalRecordsByID,
        snapshotTimestamp: snapshotTimestamp
      )
    }

    try connection.execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      try clearCurrentSnapshot()

      try insertNativeSyncRun(itemCount: nativeReminders.count, completedAt: snapshotTimestamp)

      for reminder in nativeReminders {
        let canonicalRecord = nativeLookupByCalendarItemID[reminder.nativeCalendarItemIdentifier]
        try insertNativeReminder(reminder, canonicalRecord: canonicalRecord, seenAt: snapshotTimestamp)
      }

      for canonicalID in canonicalOrder {
        if let canonicalRecord = canonicalRecordsByID[canonicalID] {
          try insertCanonicalReminder(canonicalRecord)
        }
      }

      var unresolvedCount = 0

      for resolvedPayload in resolvedShortcutItems {
        let contractRunID = try insertShortcutContractRun(
          resolvedPayload.payload,
          completedAt: snapshotTimestamp
        )

        for item in resolvedPayload.resolvedItems {
          try insertShortcutItem(item, contractRunID: contractRunID, insertedAt: snapshotTimestamp)
          if item.record.canonicalID == nil {
            unresolvedCount += 1
            try insertUnresolvedShortcutItem(item, insertedAt: snapshotTimestamp)
          }
        }

        if resolvedPayload.payload.contractID == .productivityHierarchy {
          try insertRelationships(
            resolvedPayload.resolvedItems,
            insertedAt: snapshotTimestamp
          )
        }
      }

      try connection.execute("COMMIT")

      return MirrorSyncSummary(
        databasePath: databaseURL.path,
        nativeReminderCount: nativeReminders.count,
        canonicalReminderCount: canonicalRecordsByID.count,
        unresolvedShortcutCount: unresolvedCount,
        contractRunCount: shortcutPayloads.count,
        completedAt: snapshotTimestamp
      )
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  public func querySemantic(
    contractID: ShortcutContractID,
    listTitle: String? = nil,
    dueFilter: GTDDueFilter = .any,
    olderThanDays: Int? = nil,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    guard let latestContractRun = try latestContractRun(for: contractID) else {
      return GTDQueryResult(
        queryFamily: contractID.sourceQueryFamily,
        status: .unsupported,
        confidence: .low,
        freshness: QueryFreshness(
          evaluatedAt: now,
          nativeSyncedAt: try latestNativeSyncAt(),
          shortcutGeneratedAt: nil
        ),
        acquisitionSources: [contractID.rawValue],
        warnings: ["No mirror data found for \(contractID.rawValue). Run sync first."],
        items: []
      )
    }

    let freshness = QueryFreshness(
      evaluatedAt: now,
      nativeSyncedAt: try latestNativeSyncAt(),
      shortcutGeneratedAt: latestContractRun.generatedAt
    )

    if latestContractRun.status == .error {
      return GTDQueryResult(
        queryFamily: contractID.sourceQueryFamily,
        status: .sourceError,
        confidence: .low,
        freshness: freshness,
        acquisitionSources: [contractID.rawValue],
        warnings: latestContractRun.errors,
        items: []
      )
    }

    let semantic = semanticLabel(for: contractID)
    let canonicalItems = try fetchCanonicalQueryItems().filter { item in
      semantic == nil || item.matchedSemantics.contains(semantic!)
    }
    let unresolvedItems = try fetchUnresolvedItems(for: contractID)

    let filteredItems = (canonicalItems + unresolvedItems)
      .filter { item in
        semanticQueryFilter(
          item: item,
          listTitle: listTitle,
          dueFilter: dueFilter,
          olderThanDays: olderThanDays,
          now: now
        )
      }
      .sorted(by: Self.queryItemLessThan)

    let status: QueryExecutionStatus = filteredItems.isEmpty ? .empty : .ok
    let confidence: QueryConfidence = unresolvedItems.isEmpty ? .medium : .low
    let acquisitionSources = Array(
      Set(filteredItems.flatMap { $0.acquisitionSources } + [contractID.rawValue])
    ).sorted()
    let warnings = latestContractRun.warnings + (unresolvedItems.isEmpty ? [] : [
      "One or more Shortcut items could not be canonicalized and remain low-confidence."
    ])

    return GTDQueryResult(
      queryFamily: contractID.sourceQueryFamily,
      status: status,
      confidence: confidence,
      freshness: freshness,
      acquisitionSources: acquisitionSources,
      warnings: warnings,
      items: filteredItems
    )
  }

  public func queryOldIncompleteEmptyNotes(
    olderThanDays: Int = 7,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    let freshness = QueryFreshness(
      evaluatedAt: now,
      nativeSyncedAt: try latestNativeSyncAt(),
      shortcutGeneratedAt: nil
    )

    let items = try fetchCanonicalQueryItems()
      .filter { item in
        guard item.isCompleted == false else { return false }
        guard item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return false }
        return isOlderThanThreshold(createdAt: item.createdAt, updatedAt: item.updatedAt, days: olderThanDays, now: now)
      }
      .sorted(by: Self.queryItemLessThan)

    return GTDQueryResult(
      queryFamily: "old-empty-notes",
      status: items.isEmpty ? .empty : .ok,
      confidence: .high,
      freshness: freshness,
      acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
      warnings: [],
      items: items
    )
  }

  public func queryOldVagueIncompleteReminders(
    olderThanDays: Int = 7,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    let freshness = QueryFreshness(
      evaluatedAt: now,
      nativeSyncedAt: try latestNativeSyncAt(),
      shortcutGeneratedAt: nil
    )

    let items = try fetchCanonicalQueryItems()
      .filter { item in
        guard item.isCompleted == false else { return false }
        guard isOlderThanThreshold(createdAt: item.createdAt, updatedAt: item.updatedAt, days: olderThanDays, now: now) else {
          return false
        }
        return looksVague(title: item.title)
      }
      .sorted(by: Self.queryItemLessThan)

    return GTDQueryResult(
      queryFamily: "old-vague-tasks",
      status: items.isEmpty ? .empty : .ok,
      confidence: .high,
      freshness: freshness,
      acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
      warnings: [],
      items: items
    )
  }

  private static func migrate(connection: SQLiteConnection) throws {
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
      """
    )
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

  private struct ResolvedShortcutItem {
    let contractID: ShortcutContractID
    let item: ShortcutContractItem
    let record: GTDQueryItem
  }

  private struct ResolvedShortcutPayload {
    let payload: ValidatedShortcutContractPayload
    let resolvedItems: [ResolvedShortcutItem]
  }

  private func resolveShortcutPayload(
    _ payload: ValidatedShortcutContractPayload,
    nativeLookupByCalendarItemID: [String: CanonicalReminderRecord],
    nativeLookupByExternalIdentifier: [String: [CanonicalReminderRecord]],
    canonicalRecordsByID: inout [String: CanonicalReminderRecord],
    snapshotTimestamp: Date
  ) throws -> ResolvedShortcutPayload {
    var resolvedItems: [ResolvedShortcutItem] = []

    for item in payload.items {
      let canonicalMatch = resolveCanonicalMatch(
        for: item,
        nativeLookupByCalendarItemID: nativeLookupByCalendarItemID,
        nativeLookupByExternalIdentifier: nativeLookupByExternalIdentifier
      )

      if let canonicalMatch {
        if var existingCanonicalRecord = canonicalRecordsByID[canonicalMatch.canonicalID] {
          existingCanonicalRecord = mergeShortcutItem(
            item,
            contractID: payload.contractID,
            into: existingCanonicalRecord,
            semanticTimestamp: snapshotTimestamp
          )
          canonicalRecordsByID[canonicalMatch.canonicalID] = existingCanonicalRecord
          resolvedItems.append(
            ResolvedShortcutItem(
              contractID: payload.contractID,
              item: item,
              record: GTDQueryItem(
                id: "\(payload.contractID.rawValue)::\(item.sourceItemID)",
                canonicalID: existingCanonicalRecord.canonicalID,
                identityStatus: existingCanonicalRecord.identityStatus,
                title: existingCanonicalRecord.title,
                notes: existingCanonicalRecord.notes,
                listTitle: existingCanonicalRecord.listTitle,
                isCompleted: existingCanonicalRecord.isCompleted,
                priority: existingCanonicalRecord.priority,
                dueAt: existingCanonicalRecord.dueDate,
                createdAt: existingCanonicalRecord.createdAt,
                updatedAt: existingCanonicalRecord.updatedAt,
                matchedSemantics: existingCanonicalRecord.matchedSemantics,
                observedTags: existingCanonicalRecord.observedTags,
                acquisitionSources: existingCanonicalRecord.acquisitionSources
              )
            )
          )
        }
      } else {
        resolvedItems.append(
          ResolvedShortcutItem(
            contractID: payload.contractID,
            item: item,
            record: GTDQueryItem(
              id: "\(payload.contractID.rawValue)::\(item.sourceItemID)",
              canonicalID: nil,
              identityStatus: .shortcutUnresolved,
              title: item.title,
              notes: item.notes,
              listTitle: item.listTitle,
              isCompleted: item.isCompleted,
              priority: item.priority,
              dueAt: item.dueAt,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
              matchedSemantics: item.matchedSemantics,
              observedTags: item.observedTags ?? [],
              acquisitionSources: [payload.contractID.rawValue]
            )
          )
        )
      }
    }

    return ResolvedShortcutPayload(payload: payload, resolvedItems: resolvedItems)
  }

  private func resolveCanonicalMatch(
    for item: ShortcutContractItem,
    nativeLookupByCalendarItemID: [String: CanonicalReminderRecord],
    nativeLookupByExternalIdentifier: [String: [CanonicalReminderRecord]]
  ) -> CanonicalReminderRecord? {
    if let nativeCalendarItemIdentifier = item.nativeCalendarItemIdentifier,
      let record = nativeLookupByCalendarItemID[nativeCalendarItemIdentifier]
    {
      return record
    }

    if let nativeExternalIdentifier = item.nativeExternalIdentifier,
      let matches = nativeLookupByExternalIdentifier[nativeExternalIdentifier],
      matches.count == 1
    {
      return matches[0]
    }

    return nil
  }

  private func mergeShortcutItem(
    _ item: ShortcutContractItem,
    contractID: ShortcutContractID,
    into canonicalRecord: CanonicalReminderRecord,
    semanticTimestamp: Date
  ) -> CanonicalReminderRecord {
    var semantics = Set(canonicalRecord.matchedSemantics)
    semantics.formUnion(item.matchedSemantics)

    var observedTags = Set(canonicalRecord.observedTags)
    observedTags.formUnion(item.observedTags ?? [])

    var acquisitionSources = Set(canonicalRecord.acquisitionSources)
    acquisitionSources.insert(contractID.rawValue)

    return CanonicalReminderRecord(
      id: canonicalRecord.id,
      canonicalID: canonicalRecord.canonicalID,
      identityStatus: canonicalRecord.identityStatus,
      sourceScopeID: canonicalRecord.sourceScopeID,
      calendarID: canonicalRecord.calendarID,
      listTitle: canonicalRecord.listTitle,
      title: canonicalRecord.title,
      notes: canonicalRecord.notes,
      isCompleted: canonicalRecord.isCompleted,
      completionDate: canonicalRecord.completionDate,
      priority: canonicalRecord.priority,
      dueDate: canonicalRecord.dueDate,
      createdAt: canonicalRecord.createdAt,
      updatedAt: canonicalRecord.updatedAt,
      url: canonicalRecord.url,
      nativeCalendarItemIdentifier: canonicalRecord.nativeCalendarItemIdentifier,
      nativeExternalIdentifier: canonicalRecord.nativeExternalIdentifier,
      matchedSemantics: Array(semantics).sorted(),
      observedTags: Array(observedTags).sorted(),
      acquisitionSources: Array(acquisitionSources).sorted(),
      lastNativeSyncAt: canonicalRecord.lastNativeSyncAt,
      lastSemanticSyncAt: semanticTimestamp
    )
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

  private func fetchCanonicalQueryItems() throws -> [GTDQueryItem] {
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
      let item = GTDQueryItem(
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
      items.append(item)
    }
    return items
  }

  private func fetchUnresolvedItems(for contractID: ShortcutContractID) throws -> [GTDQueryItem] {
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

  private func latestNativeSyncAt() throws -> Date? {
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

  private func latestContractRun(for contractID: ShortcutContractID) throws -> ContractRunRecord? {
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

    return ContractRunRecord(
      status: ShortcutContractRunStatus(rawValue: statement.string(at: 0) ?? "") ?? .error,
      generatedAt: decodeDate(statement.string(at: 1)) ?? Date.distantPast,
      warnings: decodeDiagnosticMessages(statement.string(at: 2)),
      errors: decodeDiagnosticMessages(statement.string(at: 3))
    )
  }

  private func semanticLabel(for contractID: ShortcutContractID) -> String? {
    switch contractID {
    case .activeProjects:
      return "active-project"
    case .nextActions:
      return "next-action"
    case .waitingOns:
      return "waiting-on"
    case .productivityHierarchy, .productivityRecentlyUpdated:
      return nil
    }
  }

  private func semanticQueryFilter(
    item: GTDQueryItem,
    listTitle: String?,
    dueFilter: GTDDueFilter,
    olderThanDays: Int?,
    now: Date
  ) -> Bool {
    if let listTitle, item.listTitle != listTitle {
      return false
    }

    if let olderThanDays,
      isOlderThanThreshold(createdAt: item.createdAt, updatedAt: item.updatedAt, days: olderThanDays, now: now) == false
    {
      return false
    }

    switch dueFilter {
    case .any:
      return true
    case .overdue:
      guard let dueAt = item.dueAt else { return false }
      return dueAt < now
    case .today:
      guard let dueAt = item.dueAt else { return false }
      return Calendar.current.isDate(dueAt, inSameDayAs: now)
    case .none:
      return item.dueAt == nil
    }
  }

  private func isOlderThanThreshold(
    createdAt: Date?,
    updatedAt: Date?,
    days: Int,
    now: Date
  ) -> Bool {
    let referenceDate = updatedAt ?? createdAt
    guard let referenceDate else { return false }
    guard let threshold = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return false }
    return referenceDate < threshold
  }

  private func looksVague(title: String) -> Bool {
    let normalized = title.lowercased()
    let actionVerbs = [
      "call", "email", "send", "draft", "review", "write", "fix", "buy", "book", "plan", "schedule",
      "reply", "update", "prepare", "ship", "clean", "organize", "follow", "meet", "ask", "make",
    ]
    return actionVerbs.contains { normalized.hasPrefix("\($0) ") } == false
  }
}

private extension GTDMirrorStore {
  static func nativeReminderLessThan(lhs: NativeReminderRecord, rhs: NativeReminderRecord) -> Bool {
    if lhs.listTitle != rhs.listTitle {
      return lhs.listTitle.localizedCaseInsensitiveCompare(rhs.listTitle) == .orderedAscending
    }

    switch (lhs.dueDate, rhs.dueDate) {
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

    return lhs.id < rhs.id
  }

  static func queryItemLessThan(lhs: GTDQueryItem, rhs: GTDQueryItem) -> Bool {
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

    return lhs.id < rhs.id
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
