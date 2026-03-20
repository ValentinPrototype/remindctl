import Foundation

public actor GTDMirrorStore {
  private let repository: SQLiteMirrorRepository
  private let canonicalizationPolicy: CanonicalizationPolicy

  public init(
    databaseURL: URL? = nil,
    canonicalizationPolicy: CanonicalizationPolicy = CanonicalizationPolicy()
  ) throws {
    let resolvedURL = try databaseURL ?? MirrorPaths.defaultDatabaseURL()
    self.repository = try SQLiteMirrorRepository(databaseURL: resolvedURL)
    self.canonicalizationPolicy = canonicalizationPolicy
  }

  public func validationGates() throws -> [ValidationGateRecord] {
    try repository.listValidationGates()
  }

  @discardableResult
  public func setValidationGate(
    _ gateID: ValidationGateID,
    state: ValidationGateState,
    evidence: String? = nil,
    updatedAt: Date = Date()
  ) throws -> ValidationGateRecord {
    try repository.setValidationGate(
      gateID,
      state: state,
      evidence: evidence,
      updatedAt: updatedAt
    )
  }

  public func replaceSnapshot(
    nativeReminders: [NativeReminderRecord],
    shortcutPayloads: [ValidatedShortcutContractPayload],
    completedAt: Date = Date()
  ) throws -> MirrorSyncSummary {
    let gateStates = try validationGateStateLookup()
    let effectiveCanonicalizationPolicy =
      gateStates[.g4ExternalIDReliability] == .passed ? canonicalizationPolicy : CanonicalizationPolicy()
    let allowCanonicalPromotion = gateStates[.g3ShortcutIdentifier] == .passed

    var canonicalRecordsByID: [String: CanonicalReminderRecord] = [:]
    var canonicalOrder: [String] = []
    var nativeLookupByCalendarItemID: [String: CanonicalReminderRecord] = [:]
    var nativeLookupByExternalIdentifier: [String: [CanonicalReminderRecord]] = [:]

    for reminder in nativeReminders.sorted(by: Self.nativeReminderLessThan) {
      let identity = effectiveCanonicalizationPolicy.canonicalIdentity(for: reminder)
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
        lastNativeSyncAt: completedAt,
        lastSemanticSyncAt: nil
      )
      canonicalRecordsByID[canonicalRecord.canonicalID] = canonicalRecord
      canonicalOrder.append(canonicalRecord.canonicalID)
      nativeLookupByCalendarItemID[reminder.nativeCalendarItemIdentifier] = canonicalRecord
      if let externalIdentifier = reminder.nativeExternalIdentifier, externalIdentifier.isEmpty == false {
        nativeLookupByExternalIdentifier[externalIdentifier, default: []].append(canonicalRecord)
      }
    }

    let resolvedShortcutPayloads = try shortcutPayloads.map { payload in
      try resolveShortcutPayload(
        payload,
        nativeLookupByCalendarItemID: nativeLookupByCalendarItemID,
        nativeLookupByExternalIdentifier: nativeLookupByExternalIdentifier,
        canonicalRecordsByID: &canonicalRecordsByID,
        snapshotTimestamp: completedAt,
        allowCanonicalPromotion: allowCanonicalPromotion
      )
    }

    let canonicalRecords = canonicalOrder.compactMap { canonicalRecordsByID[$0] }
    return try repository.replaceSnapshot(
      nativeReminders: nativeReminders,
      canonicalRecords: canonicalRecords,
      resolvedShortcutPayloads: resolvedShortcutPayloads,
      completedAt: completedAt
    )
  }

  public func querySemantic(
    contractID: ShortcutContractID,
    listTitle: String? = nil,
    dueFilter: GTDDueFilter = .any,
    olderThanDays: Int? = nil,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    let gateLookup = try validationGateLookup()
    let tagGate = gateLookup[.g1TagVisibility]?.state ?? .pending
    guard tagGate == .passed else {
      return GTDQueryResult(
        queryFamily: contractID.sourceQueryFamily,
        status: .unsupported,
        confidence: .low,
        freshness: QueryFreshness(
          evaluatedAt: now,
          nativeSyncedAt: try repository.latestNativeSyncAt(),
          shortcutGeneratedAt: nil
        ),
        acquisitionSources: [contractID.rawValue],
        warnings: [
          "\(ValidationGateID.g1TagVisibility.rawValue) is \(tagGate.rawValue). Tag-based semantic queries remain unsupported until the gate passes."
        ],
        items: []
      )
    }

    guard let latestContractRun = try repository.latestContractRun(for: contractID) else {
      return GTDQueryResult(
        queryFamily: contractID.sourceQueryFamily,
        status: .unsupported,
        confidence: .low,
        freshness: QueryFreshness(
          evaluatedAt: now,
          nativeSyncedAt: try repository.latestNativeSyncAt(),
          shortcutGeneratedAt: nil
        ),
        acquisitionSources: [contractID.rawValue],
        warnings: ["No mirror data found for \(contractID.rawValue). Run sync first."],
        items: []
      )
    }

    let freshness = QueryFreshness(
      evaluatedAt: now,
      nativeSyncedAt: try repository.latestNativeSyncAt(),
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

    let identifierGateState = gateLookup[.g3ShortcutIdentifier]?.state ?? .pending
    let semantic = semanticLabel(for: contractID)
    let canonicalItems: [GTDQueryItem]
    if identifierGateState == .passed {
      canonicalItems = try repository.fetchCanonicalQueryItems().filter { item in
        semantic == nil || item.matchedSemantics.contains(semantic!)
      }
    } else {
      canonicalItems = []
    }

    let unresolvedItems = try repository.fetchUnresolvedItems(for: contractID)
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

    var warnings = latestContractRun.warnings
    if identifierGateState != .passed {
      warnings.append(
        "\(ValidationGateID.g3ShortcutIdentifier.rawValue) is \(identifierGateState.rawValue). Canonical promotion is disabled, so semantic results are returned only from unresolved Shortcut rows."
      )
    } else if unresolvedItems.isEmpty == false {
      warnings.append("One or more Shortcut items could not be canonicalized and remain low-confidence.")
    }

    let confidence: QueryConfidence
    if identifierGateState != .passed {
      confidence = .low
    } else {
      confidence = unresolvedItems.isEmpty ? .medium : .low
    }

    return GTDQueryResult(
      queryFamily: contractID.sourceQueryFamily,
      status: filteredItems.isEmpty ? .empty : .ok,
      confidence: confidence,
      freshness: freshness,
      acquisitionSources: Array(
        Set(filteredItems.flatMap { $0.acquisitionSources } + [contractID.rawValue])
      ).sorted(),
      warnings: warnings,
      items: filteredItems
    )
  }

  public func queryOldIncompleteEmptyNotes(
    olderThanDays: Int = 7,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    let gateLookup = try validationGateLookup()
    let allowUpdatedAt = gateLookup[.g5LastModifiedReliability]?.state == .passed

    let items = try repository.fetchCanonicalQueryItems()
      .filter { item in
        guard item.isCompleted == false else { return false }
        guard item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return false }
        return isOlderThanThreshold(
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
          days: olderThanDays,
          now: now,
          allowUpdatedAt: allowUpdatedAt
        )
      }
      .sorted(by: Self.queryItemLessThan)

    let warnings = allowUpdatedAt ? [] : [
      "\(ValidationGateID.g5LastModifiedReliability.rawValue) is not passed. Native stale-age logic is using created_at only."
    ]

    return GTDQueryResult(
      queryFamily: "old-empty-notes",
      status: items.isEmpty ? .empty : .ok,
      confidence: .high,
      freshness: QueryFreshness(
        evaluatedAt: now,
        nativeSyncedAt: try repository.latestNativeSyncAt(),
        shortcutGeneratedAt: nil
      ),
      acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
      warnings: warnings,
      items: items
    )
  }

  public func queryOldVagueIncompleteReminders(
    olderThanDays: Int = 7,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    let gateLookup = try validationGateLookup()
    let allowUpdatedAt = gateLookup[.g5LastModifiedReliability]?.state == .passed

    let items = try repository.fetchCanonicalQueryItems()
      .filter { item in
        guard item.isCompleted == false else { return false }
        guard isOlderThanThreshold(
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
          days: olderThanDays,
          now: now,
          allowUpdatedAt: allowUpdatedAt
        ) else {
          return false
        }
        return looksVague(title: item.title)
      }
      .sorted(by: Self.queryItemLessThan)

    let warnings = allowUpdatedAt ? [] : [
      "\(ValidationGateID.g5LastModifiedReliability.rawValue) is not passed. Native stale-age logic is using created_at only."
    ]

    return GTDQueryResult(
      queryFamily: "old-vague-tasks",
      status: items.isEmpty ? .empty : .ok,
      confidence: .high,
      freshness: QueryFreshness(
        evaluatedAt: now,
        nativeSyncedAt: try repository.latestNativeSyncAt(),
        shortcutGeneratedAt: nil
      ),
      acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
      warnings: warnings,
      items: items
    )
  }

  private func validationGateLookup() throws -> [ValidationGateID: ValidationGateRecord] {
    Dictionary(uniqueKeysWithValues: try validationGates().map { ($0.gateID, $0) })
  }

  private func validationGateStateLookup() throws -> [ValidationGateID: ValidationGateState] {
    Dictionary(uniqueKeysWithValues: try validationGates().map { ($0.gateID, $0.state) })
  }

  private func resolveShortcutPayload(
    _ payload: ValidatedShortcutContractPayload,
    nativeLookupByCalendarItemID: [String: CanonicalReminderRecord],
    nativeLookupByExternalIdentifier: [String: [CanonicalReminderRecord]],
    canonicalRecordsByID: inout [String: CanonicalReminderRecord],
    snapshotTimestamp: Date,
    allowCanonicalPromotion: Bool
  ) throws -> ResolvedShortcutPayload {
    var resolvedItems: [ResolvedShortcutItem] = []

    for item in payload.items {
      let canonicalMatch: CanonicalReminderRecord? = if allowCanonicalPromotion {
        resolveCanonicalMatch(
          for: item,
          nativeLookupByCalendarItemID: nativeLookupByCalendarItemID,
          nativeLookupByExternalIdentifier: nativeLookupByExternalIdentifier
        )
      } else {
        nil
      }

      if let canonicalMatch, var existingCanonicalRecord = canonicalRecordsByID[canonicalMatch.canonicalID] {
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
      isOlderThanThreshold(
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        days: olderThanDays,
        now: now,
        allowUpdatedAt: true
      ) == false
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
    now: Date,
    allowUpdatedAt: Bool
  ) -> Bool {
    let referenceDate = allowUpdatedAt ? (updatedAt ?? createdAt) : createdAt
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
}
