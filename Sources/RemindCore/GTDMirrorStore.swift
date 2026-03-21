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
    let allowCanonicalPromotion = gateStates[.g3ShortcutIdentifier] == .passed

    var canonicalRecordsByID: [String: CanonicalReminderRecord] = [:]
    var canonicalOrder: [String] = []
    var canonicalRecordsByManagedID: [String: CanonicalReminderRecord] = [:]

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
        noteFields: ManagedNoteFields(
          rawNotes: reminder.rawNotes,
          notesBody: reminder.notesBody,
          canonicalManagedID: reminder.canonicalManagedID,
          footerState: reminder.footerState
        ),
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
      if let canonicalManagedID = reminder.canonicalManagedID {
        canonicalRecordsByManagedID[canonicalManagedID] = canonicalRecord
      }
    }

    let resolvedShortcutPayloads = try shortcutPayloads.map { payload in
      try resolveShortcutPayload(
        payload,
        canonicalRecordsByManagedID: canonicalRecordsByManagedID,
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
        identityStatuses: [],
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
        identityStatuses: [],
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
        identityStatuses: [],
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
        "\(ValidationGateID.g3ShortcutIdentifier.rawValue) is \(identifierGateState.rawValue). Canonical promotion is disabled unless Shortcut notes preserve a valid managed footer."
      )
    } else if unresolvedItems.isEmpty == false {
      warnings.append("One or more Shortcut items could not be canonicalized and remain low-confidence.")
    }

    let identityStatuses = distinctIdentityStatuses(in: filteredItems)
    let confidence: QueryConfidence
    if identifierGateState != .passed {
      confidence = .low
    } else if identityStatuses.contains(.shortcutUnresolved) || identityStatuses.contains(.collisionUnresolved) {
      confidence = .low
    } else {
      confidence = .medium
    }

    return GTDQueryResult(
      queryFamily: contractID.sourceQueryFamily,
      status: filteredItems.isEmpty ? .empty : .ok,
      confidence: confidence,
      freshness: freshness,
      acquisitionSources: Array(
        Set(filteredItems.flatMap { $0.acquisitionSources } + [contractID.rawValue])
      ).sorted(),
      identityStatuses: identityStatuses,
      warnings: warnings,
      items: filteredItems
    )
  }

  public func queryHierarchy(
    parentSourceItemID: String? = nil,
    parentCanonicalID: String? = nil,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    let gateLookup = try validationGateLookup()
    let hierarchyGate = gateLookup[.g2HierarchyVisibility]?.state ?? .pending
    guard hierarchyGate == .passed else {
      return GTDQueryResult(
        queryFamily: ShortcutContractID.productivityHierarchy.sourceQueryFamily,
        status: .unsupported,
        confidence: .low,
        freshness: QueryFreshness(
          evaluatedAt: now,
          nativeSyncedAt: try repository.latestNativeSyncAt(),
          shortcutGeneratedAt: nil
        ),
        acquisitionSources: [ShortcutContractID.productivityHierarchy.rawValue],
        identityStatuses: [],
        warnings: [
          "\(ValidationGateID.g2HierarchyVisibility.rawValue) is \(hierarchyGate.rawValue). Hierarchy queries remain unsupported until the gate passes."
        ],
        items: []
      )
    }

    guard let latestContractRun = try repository.latestContractRun(for: .productivityHierarchy) else {
      return GTDQueryResult(
        queryFamily: ShortcutContractID.productivityHierarchy.sourceQueryFamily,
        status: .unsupported,
        confidence: .low,
        freshness: QueryFreshness(
          evaluatedAt: now,
          nativeSyncedAt: try repository.latestNativeSyncAt(),
          shortcutGeneratedAt: nil
        ),
        acquisitionSources: [ShortcutContractID.productivityHierarchy.rawValue],
        identityStatuses: [],
        warnings: ["No mirror data found for \(ShortcutContractID.productivityHierarchy.rawValue). Run sync first."],
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
        queryFamily: ShortcutContractID.productivityHierarchy.sourceQueryFamily,
        status: .sourceError,
        confidence: .low,
        freshness: freshness,
        acquisitionSources: [ShortcutContractID.productivityHierarchy.rawValue],
        identityStatuses: [],
        warnings: latestContractRun.errors,
        items: []
      )
    }

    let identifierGateState = gateLookup[.g3ShortcutIdentifier]?.state ?? .pending
    let items = try repository.fetchHierarchyItems()
      .filter { item in
        hierarchyQueryFilter(
          item: item,
          parentSourceItemID: parentSourceItemID,
          parentCanonicalID: parentCanonicalID
        )
      }
      .sorted(by: Self.queryItemLessThan)

    var warnings = latestContractRun.warnings
    if identifierGateState != .passed {
      warnings.append(
        "\(ValidationGateID.g3ShortcutIdentifier.rawValue) is \(identifierGateState.rawValue). Hierarchy rows cannot be safely joined unless Shortcut notes preserve valid managed footers."
      )
    }

    let identityStatuses = distinctIdentityStatuses(in: items)
    let confidence: QueryConfidence = identityStatuses.allSatisfy { $0 == .canonicalManaged }
      && identifierGateState == .passed ? .medium : .low

    return GTDQueryResult(
      queryFamily: ShortcutContractID.productivityHierarchy.sourceQueryFamily,
      status: items.isEmpty ? .empty : .ok,
      confidence: confidence,
      freshness: freshness,
      acquisitionSources: Array(
        Set(items.flatMap { $0.acquisitionSources } + [ShortcutContractID.productivityHierarchy.rawValue])
      ).sorted(),
      identityStatuses: identityStatuses,
      warnings: warnings,
      items: items
    )
  }

  public func queryOldIncompleteEmptyNotes(
    olderThanDays: Int = 7,
    now: Date = Date()
  ) throws -> GTDQueryResult {
    let gateLookup = try validationGateLookup()
    let allowUpdatedAt = gateLookup[.g5LastModifiedReliability]?.state == .passed
    let latestNativeSyncAt = try repository.latestNativeSyncAt()
    guard let latestNativeSyncAt else {
      return GTDQueryResult(
        queryFamily: "old-empty-notes",
        status: .unsupported,
        confidence: .low,
        freshness: QueryFreshness(
          evaluatedAt: now,
          nativeSyncedAt: nil,
          shortcutGeneratedAt: nil
        ),
        acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
        identityStatuses: [],
        warnings: ["No native mirror data found. Run sync first."],
        items: []
      )
    }

    let items = try repository.fetchCanonicalQueryItems()
      .filter { item in
        guard item.isCompleted == false else { return false }
        guard item.notesBody?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return false }
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
        nativeSyncedAt: latestNativeSyncAt,
        shortcutGeneratedAt: nil
      ),
      acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
      identityStatuses: distinctIdentityStatuses(in: items),
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
    let latestNativeSyncAt = try repository.latestNativeSyncAt()
    guard let latestNativeSyncAt else {
      return GTDQueryResult(
        queryFamily: "old-vague-tasks",
        status: .unsupported,
        confidence: .low,
        freshness: QueryFreshness(
          evaluatedAt: now,
          nativeSyncedAt: nil,
          shortcutGeneratedAt: nil
        ),
        acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
        identityStatuses: [],
        warnings: ["No native mirror data found. Run sync first."],
        items: []
      )
    }

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
        nativeSyncedAt: latestNativeSyncAt,
        shortcutGeneratedAt: nil
      ),
      acquisitionSources: [AcquisitionSourceKind.nativeEventKit.rawValue],
      identityStatuses: distinctIdentityStatuses(in: items),
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
    canonicalRecordsByManagedID: [String: CanonicalReminderRecord],
    canonicalRecordsByID: inout [String: CanonicalReminderRecord],
    snapshotTimestamp: Date,
    allowCanonicalPromotion: Bool
  ) throws -> ResolvedShortcutPayload {
    var resolvedItems: [ResolvedShortcutItem] = []

    for item in payload.items {
      let canonicalMatch: CanonicalReminderRecord? = if allowCanonicalPromotion {
        resolveCanonicalMatch(
          for: item,
          canonicalRecordsByManagedID: canonicalRecordsByManagedID
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
              noteFields: ManagedNoteFields(
                rawNotes: existingCanonicalRecord.rawNotes,
                notesBody: existingCanonicalRecord.notesBody,
                canonicalManagedID: existingCanonicalRecord.canonicalManagedID,
                footerState: existingCanonicalRecord.footerState
              ),
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
              identityStatus: item.footerState == .invalid ? .footerInvalid : .shortcutUnresolved,
              title: item.title,
              noteFields: ManagedNoteFields(
                rawNotes: item.rawNotes,
                notesBody: item.notesBody,
                canonicalManagedID: item.canonicalManagedID,
                footerState: item.footerState
              ),
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
    canonicalRecordsByManagedID: [String: CanonicalReminderRecord]
  ) -> CanonicalReminderRecord? {
    guard item.footerState == .valid, let canonicalManagedID = item.canonicalManagedID else {
      return nil
    }
    return canonicalRecordsByManagedID[canonicalManagedID]
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
      noteFields: ManagedNoteFields(
        rawNotes: canonicalRecord.rawNotes ?? item.rawNotes,
        notesBody: canonicalRecord.notesBody,
        canonicalManagedID: canonicalRecord.canonicalManagedID,
        footerState: canonicalRecord.footerState
      ),
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

  private func hierarchyQueryFilter(
    item: GTDQueryItem,
    parentSourceItemID: String?,
    parentCanonicalID: String?
  ) -> Bool {
    if let parentSourceItemID {
      return item.sourceItemID == parentSourceItemID || item.parentSourceItemID == parentSourceItemID
    }

    if let parentCanonicalID {
      return item.canonicalID == parentCanonicalID || item.parentCanonicalID == parentCanonicalID
    }

    return item.parentSourceItemID != nil || item.childSourceItemIDs.isEmpty == false
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

  private func distinctIdentityStatuses(in items: [GTDQueryItem]) -> [IdentityStatus] {
    Array(Set(items.map(\.identityStatus))).sorted { $0.rawValue < $1.rawValue }
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
