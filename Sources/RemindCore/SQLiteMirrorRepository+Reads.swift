import Foundation

extension SQLiteMirrorRepository {
  func fetchCanonicalQueryItems() throws -> [GTDQueryItem] {
    let statement = try connection.prepare(
      """
      SELECT canonical_id, identity_status, canonical_managed_id, footer_state, title, raw_notes,
             notes_body, list_title, is_completed, priority, due_date, created_at, updated_at,
             matched_semantics_json, observed_tags_json, acquisition_sources_json
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
          identityStatus: IdentityStatus(rawValue: statement.string(at: 1) ?? "") ?? .footerInvalid,
          title: statement.string(at: 4) ?? "",
          noteFields: ManagedNoteFields(
            rawNotes: statement.string(at: 5),
            notesBody: statement.string(at: 6),
            canonicalManagedID: statement.string(at: 2),
            footerState: CanonicalNoteFooterState(rawValue: statement.string(at: 3) ?? "") ?? .missing
          ),
          listTitle: statement.string(at: 7) ?? "",
          isCompleted: statement.int64(at: 8) == 1,
          priority: ReminderPriority(rawValue: statement.string(at: 9) ?? "") ?? .none,
          dueAt: decodeDate(statement.string(at: 10)),
          createdAt: decodeDate(statement.string(at: 11)),
          updatedAt: decodeDate(statement.string(at: 12)),
          matchedSemantics: decodeJSONStringArray(statement.string(at: 13)) ?? [],
          observedTags: decodeJSONStringArray(statement.string(at: 14)) ?? [],
          acquisitionSources: decodeJSONStringArray(statement.string(at: 15)) ?? []
        )
      )
    }
    return items
  }

  func fetchHierarchyItems() throws -> [GTDQueryItem] {
    let statement = try connection.prepare(
      """
      SELECT source_item_id, canonical_id, identity_status, canonical_managed_id, footer_state,
             title, raw_notes, notes_body, list_title, is_completed, priority, due_at, created_at,
             updated_at, matched_semantics_json, observed_tags_json, parent_source_item_id,
             child_source_item_ids_json
      FROM shortcut_items
      WHERE contract_id = ?
      """
    )
    defer { statement.reset() }
    try statement.bind(ShortcutContractID.productivityHierarchy.rawValue, at: 1)

    struct RawHierarchyItem {
      let sourceItemID: String
      let canonicalID: String?
      let identityStatus: IdentityStatus
      let noteFields: ManagedNoteFields
      let title: String
      let listTitle: String
      let isCompleted: Bool
      let priority: ReminderPriority
      let dueAt: Date?
      let createdAt: Date?
      let updatedAt: Date?
      let matchedSemantics: [String]
      let observedTags: [String]
      let parentSourceItemID: String?
      let childSourceItemIDs: [String]
    }

    var rawItems: [RawHierarchyItem] = []
    while try statement.step() {
      rawItems.append(
        RawHierarchyItem(
          sourceItemID: statement.string(at: 0) ?? UUID().uuidString,
          canonicalID: statement.string(at: 1),
          identityStatus: IdentityStatus(rawValue: statement.string(at: 2) ?? "") ?? .shortcutUnresolved,
          noteFields: ManagedNoteFields(
            rawNotes: statement.string(at: 6),
            notesBody: statement.string(at: 7),
            canonicalManagedID: statement.string(at: 3),
            footerState: CanonicalNoteFooterState(rawValue: statement.string(at: 4) ?? "") ?? .missing
          ),
          title: statement.string(at: 5) ?? "",
          listTitle: statement.string(at: 8) ?? "",
          isCompleted: statement.int64(at: 9) == 1,
          priority: ReminderPriority(rawValue: statement.string(at: 10) ?? "") ?? .none,
          dueAt: decodeDate(statement.string(at: 11)),
          createdAt: decodeDate(statement.string(at: 12)),
          updatedAt: decodeDate(statement.string(at: 13)),
          matchedSemantics: decodeJSONStringArray(statement.string(at: 14)) ?? [],
          observedTags: decodeJSONStringArray(statement.string(at: 15)) ?? [],
          parentSourceItemID: statement.string(at: 16),
          childSourceItemIDs: decodeJSONStringArray(statement.string(at: 17)) ?? []
        )
      )
    }

    let sourceToCanonical = Dictionary(uniqueKeysWithValues: rawItems.compactMap { item in
      item.canonicalID.map { (item.sourceItemID, $0) }
    })

    return rawItems.map { item in
      GTDQueryItem(
        id: "\(ShortcutContractID.productivityHierarchy.rawValue)::\(item.sourceItemID)",
        sourceItemID: item.sourceItemID,
        canonicalID: item.canonicalID,
        identityStatus: item.identityStatus,
        title: item.title,
        noteFields: item.noteFields,
        listTitle: item.listTitle,
        isCompleted: item.isCompleted,
        priority: item.priority,
        dueAt: item.dueAt,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        matchedSemantics: item.matchedSemantics,
        observedTags: item.observedTags,
        acquisitionSources: item.canonicalID == nil
          ? [ShortcutContractID.productivityHierarchy.rawValue]
          : [AcquisitionSourceKind.nativeEventKit.rawValue, ShortcutContractID.productivityHierarchy.rawValue],
        parentSourceItemID: item.parentSourceItemID,
        parentCanonicalID: item.parentSourceItemID.flatMap { sourceToCanonical[$0] },
        childSourceItemIDs: item.childSourceItemIDs,
        childCanonicalIDs: item.childSourceItemIDs.compactMap { sourceToCanonical[$0] }
      )
    }
  }

  func fetchUnresolvedItems(for contractID: ShortcutContractID) throws -> [GTDQueryItem] {
    let statement = try connection.prepare(
      """
      SELECT source_item_id, identity_status, canonical_managed_id, footer_state, title, raw_notes,
             notes_body, list_title, is_completed, priority, due_at, created_at, updated_at,
             matched_semantics_json, observed_tags_json
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
          title: statement.string(at: 4) ?? "",
          noteFields: ManagedNoteFields(
            rawNotes: statement.string(at: 5),
            notesBody: statement.string(at: 6),
            canonicalManagedID: statement.string(at: 2),
            footerState: CanonicalNoteFooterState(rawValue: statement.string(at: 3) ?? "") ?? .missing
          ),
          listTitle: statement.string(at: 7) ?? "",
          isCompleted: statement.int64(at: 8) == 1,
          priority: ReminderPriority(rawValue: statement.string(at: 9) ?? "") ?? .none,
          dueAt: decodeDate(statement.string(at: 10)),
          createdAt: decodeDate(statement.string(at: 11)),
          updatedAt: decodeDate(statement.string(at: 12)),
          matchedSemantics: decodeJSONStringArray(statement.string(at: 13)) ?? [],
          observedTags: decodeJSONStringArray(statement.string(at: 14)) ?? [],
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
}
