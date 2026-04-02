import Foundation

extension SQLiteMirrorRepository {
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
        native_calendar_item_identifier, canonical_id, identity_status, canonical_managed_id,
        footer_state, source_scope_id, calendar_id, list_title, title, raw_notes, notes_body,
        is_completed, completion_date, priority, due_date, created_at, updated_at, url,
        native_external_identifier, last_seen_at, last_native_sync_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(reminder.nativeCalendarItemIdentifier, at: 1)
    try statement.bind(canonicalRecord?.canonicalID ?? "managed::\(reminder.canonicalManagedID ?? reminder.nativeCalendarItemIdentifier)", at: 2)
    try statement.bind(canonicalRecord?.identityStatus.rawValue ?? IdentityStatus.canonicalManaged.rawValue, at: 3)
    try statement.bind(reminder.canonicalManagedID, at: 4)
    try statement.bind(reminder.footerState.rawValue, at: 5)
    try statement.bind(reminder.sourceScopeID, at: 6)
    try statement.bind(reminder.calendarID, at: 7)
    try statement.bind(reminder.listTitle, at: 8)
    try statement.bind(reminder.title, at: 9)
    try statement.bind(reminder.rawNotes, at: 10)
    try statement.bind(reminder.notesBody, at: 11)
    try statement.bind(reminder.isCompleted, at: 12)
    try statement.bind(reminder.completionDate, at: 13)
    try statement.bind(reminder.priority.rawValue, at: 14)
    try statement.bind(reminder.dueDate, at: 15)
    try statement.bind(reminder.createdAt, at: 16)
    try statement.bind(reminder.updatedAt, at: 17)
    try statement.bind(reminder.url, at: 18)
    try statement.bind(reminder.nativeExternalIdentifier, at: 19)
    try statement.bind(seenAt, at: 20)
    try statement.bind(seenAt, at: 21)
    _ = try statement.step()
  }

  private func insertCanonicalReminder(_ reminder: CanonicalReminderRecord) throws {
    let statement = try connection.prepare(
      """
      INSERT INTO canonical_reminders (
        canonical_id, identity_status, canonical_managed_id, footer_state, source_scope_id, calendar_id,
        list_title, title, raw_notes, notes_body, is_completed, completion_date, priority, due_date,
        created_at, updated_at, url, native_calendar_item_identifier, native_external_identifier,
        matched_semantics_json, observed_tags_json, acquisition_sources_json, last_native_sync_at,
        last_semantic_sync_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(reminder.canonicalID, at: 1)
    try statement.bind(reminder.identityStatus.rawValue, at: 2)
    try statement.bind(reminder.canonicalManagedID, at: 3)
    try statement.bind(reminder.footerState.rawValue, at: 4)
    try statement.bind(reminder.sourceScopeID, at: 5)
    try statement.bind(reminder.calendarID, at: 6)
    try statement.bind(reminder.listTitle, at: 7)
    try statement.bind(reminder.title, at: 8)
    try statement.bind(reminder.rawNotes, at: 9)
    try statement.bind(reminder.notesBody, at: 10)
    try statement.bind(reminder.isCompleted, at: 11)
    try statement.bind(reminder.completionDate, at: 12)
    try statement.bind(reminder.priority.rawValue, at: 13)
    try statement.bind(reminder.dueDate, at: 14)
    try statement.bind(reminder.createdAt, at: 15)
    try statement.bind(reminder.updatedAt, at: 16)
    try statement.bind(reminder.url, at: 17)
    try statement.bind(reminder.nativeCalendarItemIdentifier, at: 18)
    try statement.bind(reminder.nativeExternalIdentifier, at: 19)
    try statement.bind(encodeJSONString(reminder.matchedSemantics), at: 20)
    try statement.bind(encodeJSONString(reminder.observedTags), at: 21)
    try statement.bind(encodeJSONString(reminder.acquisitionSources), at: 22)
    try statement.bind(reminder.lastNativeSyncAt, at: 23)
    try statement.bind(reminder.lastSemanticSyncAt, at: 24)
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
        canonical_managed_id, footer_state, native_calendar_item_identifier,
        native_external_identifier, title, raw_notes, notes_body, list_title, is_completed, priority,
        due_at, created_at, updated_at, url, matched_semantics_json, observed_tags_json,
        parent_source_item_id, child_source_item_ids_json, inserted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(contractRunID, at: 1)
    try statement.bind(resolvedItem.contractID.rawValue, at: 2)
    try statement.bind(resolvedItem.item.sourceItemID, at: 3)
    try statement.bind(resolvedItem.record.canonicalID, at: 4)
    try statement.bind(resolvedItem.record.identityStatus.rawValue, at: 5)
    try statement.bind(resolvedItem.record.canonicalManagedID, at: 6)
    try statement.bind(resolvedItem.record.footerState.rawValue, at: 7)
    try statement.bind(resolvedItem.item.nativeCalendarItemIdentifier, at: 8)
    try statement.bind(resolvedItem.item.nativeExternalIdentifier, at: 9)
    try statement.bind(resolvedItem.item.title, at: 10)
    try statement.bind(resolvedItem.item.rawNotes, at: 11)
    try statement.bind(resolvedItem.item.notesBody, at: 12)
    try statement.bind(resolvedItem.item.listTitle, at: 13)
    try statement.bind(resolvedItem.item.isCompleted, at: 14)
    try statement.bind(resolvedItem.item.priority.rawValue, at: 15)
    try statement.bind(resolvedItem.item.dueAt, at: 16)
    try statement.bind(resolvedItem.item.createdAt, at: 17)
    try statement.bind(resolvedItem.item.updatedAt, at: 18)
    try statement.bind(resolvedItem.item.url, at: 19)
    try statement.bind(encodeJSONString(resolvedItem.item.matchedSemantics), at: 20)
    try statement.bind(encodeJSONString(resolvedItem.item.observedTags ?? []), at: 21)
    try statement.bind(resolvedItem.item.parentSourceItemID, at: 22)
    try statement.bind(encodeJSONString(resolvedItem.item.childSourceItemIDs), at: 23)
    try statement.bind(insertedAt, at: 24)
    _ = try statement.step()
  }

  private func insertUnresolvedShortcutItem(
    _ resolvedItem: ResolvedShortcutItem,
    insertedAt: Date
  ) throws {
    let statement = try connection.prepare(
      """
      INSERT INTO unresolved_shortcut_items (
        contract_id, source_item_id, identity_status, canonical_managed_id, footer_state,
        native_calendar_item_identifier, native_external_identifier, title, raw_notes, notes_body,
        list_title, is_completed, priority, due_at, created_at, updated_at, url,
        matched_semantics_json, observed_tags_json, parent_source_item_id,
        child_source_item_ids_json, inserted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { statement.reset() }
    try statement.bind(resolvedItem.contractID.rawValue, at: 1)
    try statement.bind(resolvedItem.item.sourceItemID, at: 2)
    try statement.bind(resolvedItem.record.identityStatus.rawValue, at: 3)
    try statement.bind(resolvedItem.record.canonicalManagedID, at: 4)
    try statement.bind(resolvedItem.record.footerState.rawValue, at: 5)
    try statement.bind(resolvedItem.item.nativeCalendarItemIdentifier, at: 6)
    try statement.bind(resolvedItem.item.nativeExternalIdentifier, at: 7)
    try statement.bind(resolvedItem.item.title, at: 8)
    try statement.bind(resolvedItem.item.rawNotes, at: 9)
    try statement.bind(resolvedItem.item.notesBody, at: 10)
    try statement.bind(resolvedItem.item.listTitle, at: 11)
    try statement.bind(resolvedItem.item.isCompleted, at: 12)
    try statement.bind(resolvedItem.item.priority.rawValue, at: 13)
    try statement.bind(resolvedItem.item.dueAt, at: 14)
    try statement.bind(resolvedItem.item.createdAt, at: 15)
    try statement.bind(resolvedItem.item.updatedAt, at: 16)
    try statement.bind(resolvedItem.item.url, at: 17)
    try statement.bind(encodeJSONString(resolvedItem.item.matchedSemantics), at: 18)
    try statement.bind(encodeJSONString(resolvedItem.item.observedTags ?? []), at: 19)
    try statement.bind(resolvedItem.item.parentSourceItemID, at: 20)
    try statement.bind(encodeJSONString(resolvedItem.item.childSourceItemIDs), at: 21)
    try statement.bind(insertedAt, at: 22)
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
}
