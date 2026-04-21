import Foundation
import RemindCore

enum GTDHelperSync {
  static func sync(mirrorURL: URL, generatedAt: Date = Date()) async throws -> MirrorSyncSummary {
    let store = RemindersStore()
    try await store.requestAccess()
    _ = try await store.normalizeManagedNoteFooters()
    let nativeReminders = try await store.nativeReminders()
    let payloads = try helperPayloads(generatedAt: generatedAt)

    let mirror = try GTDMirrorStore(databaseURL: mirrorURL)
    let summary = try await mirror.replaceSnapshot(
      nativeReminders: nativeReminders,
      shortcutPayloads: payloads,
      completedAt: generatedAt,
      allowCanonicalPromotion: true
    )
    _ = try await mirror.setValidationGate(
      .g1TagVisibility,
      state: .passed,
      evidence: "remindctl - Search By Tag populated semantic mirror contracts",
      updatedAt: generatedAt
    )
    _ = try await mirror.setValidationGate(
      .g2HierarchyVisibility,
      state: .passed,
      evidence: "remindctl - Search By Tag populated hierarchy mirror contract",
      updatedAt: generatedAt
    )
    _ = try await mirror.setValidationGate(
      .g3ShortcutIdentifier,
      state: .passed,
      evidence: "helper-derived sync uses managed note footers for canonical joins",
      updatedAt: generatedAt
    )
    return summary
  }

  static func helperPayloads(generatedAt: Date = Date()) throws -> [ValidatedShortcutContractPayload] {
    let activeProjects = try ShortcutTagSearch.search(tags: ["active-project"])
    let nextActions = try ShortcutTagSearch.search(tags: ["next-action"])
    let waitingOns = try ShortcutTagSearch.search(tags: ["waiting-on"])

    return try helperPayloads(
      activeProjects: activeProjects,
      nextActions: nextActions,
      waitingOns: waitingOns,
      generatedAt: generatedAt
    )
  }

  static func helperPayloads(
    activeProjects: [ShortcutTagReminder],
    nextActions: [ShortcutTagReminder],
    waitingOns: [ShortcutTagReminder],
    generatedAt: Date
  ) throws -> [ValidatedShortcutContractPayload] {
    let areaTags = Set(activeProjects.flatMap { ProjectHealth.areaTags(in: $0.tags) })
    var areaReminders: [ShortcutTagReminder] = []
    for areaTag in areaTags.sorted() {
      areaReminders.append(contentsOf: try ShortcutTagSearch.search(tags: [areaTag]))
    }

    return helperPayloads(
      activeProjects: activeProjects,
      nextActions: nextActions,
      waitingOns: waitingOns,
      areaReminders: uniqueReminders(areaReminders),
      generatedAt: generatedAt
    )
  }

  static func helperPayloads(
    activeProjects: [ShortcutTagReminder],
    nextActions: [ShortcutTagReminder],
    waitingOns: [ShortcutTagReminder],
    areaReminders: [ShortcutTagReminder],
    generatedAt: Date
  ) -> [ValidatedShortcutContractPayload] {
    [
      semanticPayload(
        contractID: .activeProjects,
        semantic: "active-project",
        reminders: activeProjects,
        generatedAt: generatedAt
      ),
      semanticPayload(
        contractID: .nextActions,
        semantic: "next-action",
        reminders: nextActions,
        generatedAt: generatedAt
      ),
      semanticPayload(
        contractID: .waitingOns,
        semantic: "waiting-on",
        reminders: waitingOns,
        generatedAt: generatedAt
      ),
      hierarchyPayload(
        activeProjects: activeProjects,
        areaReminders: areaReminders,
        generatedAt: generatedAt
      ),
    ]
  }

  private static func semanticPayload(
    contractID: ShortcutContractID,
    semantic: String,
    reminders: [ShortcutTagReminder],
    generatedAt: Date
  ) -> ValidatedShortcutContractPayload {
    let items = uniqueReminders(reminders)
      .filter { !$0.isCompleted }
      .map { item(from: $0, contractID: contractID, matchedSemantics: [semantic]) }
      .uniqueBySourceItemID()
      .sorted(by: shortcutItemLessThan)

    return ValidatedShortcutContractPayload(
      contractID: contractID,
      contractVersion: "v1",
      generatedAt: generatedAt,
      status: items.isEmpty ? .empty : .ok,
      items: items,
      warnings: [],
      errors: []
    )
  }

  private static func hierarchyPayload(
    activeProjects: [ShortcutTagReminder],
    areaReminders: [ShortcutTagReminder],
    generatedAt: Date
  ) -> ValidatedShortcutContractPayload {
    let candidates = uniqueReminders(areaReminders + activeProjects)
    var items: [ShortcutContractItem] = []
    var warnings: [ContractDiagnostic] = []
    var insertedSourceIDs = Set<String>()

    for project in uniqueReminders(activeProjects).filter({ !$0.isCompleted }) {
      let parentSourceID = sourceItemID(for: project, contractID: .productivityHierarchy)
      guard insertedSourceIDs.insert(parentSourceID).inserted else {
        warnings.append(
          ContractDiagnostic(
            code: "duplicate_hierarchy_source_item",
            message: "Skipped duplicate hierarchy parent source_item_id \(parentSourceID) for \(project.title)."
          )
        )
        continue
      }

      let childTitleSet = Set(project.subTasks)
      let children = candidates
        .filter { !$0.isCompleted }
        .filter { candidate in
          candidate.canonicalManagedID != project.canonicalManagedID
            && (candidate.parent == project.title || childTitleSet.contains(candidate.title))
        }
        .sorted { lhs, rhs in
          lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

      let resolvedChildTitles = Set(children.map(\.title))
      let unresolvedChildTitles = project.subTasks.filter { !resolvedChildTitles.contains($0) }
      let unresolvedChildSourceIDs = unresolvedChildTitles.enumerated().map { index, _ in
        "unresolved::\(parentSourceID)::\(index + 1)"
      }
      if !unresolvedChildTitles.isEmpty {
        warnings.append(
          ContractDiagnostic(
            code: "unresolved_child_details",
            message: "Project \(project.title) lists child titles that were not resolved by area-tag lookup: \(unresolvedChildTitles.joined(separator: ", "))"
          )
        )
      }

      let childSourceIDs = children.map { sourceItemID(for: $0, contractID: .productivityHierarchy) }
      items.append(
        item(
          from: project,
          contractID: .productivityHierarchy,
          matchedSemantics: [],
          parentSourceItemID: nil,
          childSourceItemIDs: childSourceIDs + unresolvedChildSourceIDs
        )
      )

      for child in children {
        let childSourceID = sourceItemID(for: child, contractID: .productivityHierarchy)
        guard insertedSourceIDs.insert(childSourceID).inserted else {
          continue
        }
        items.append(
          item(
            from: child,
            contractID: .productivityHierarchy,
            matchedSemantics: [],
            parentSourceItemID: parentSourceID,
            childSourceItemIDs: []
          )
        )
      }
    }

    return ValidatedShortcutContractPayload(
      contractID: .productivityHierarchy,
      contractVersion: "v1",
      generatedAt: generatedAt,
      status: items.isEmpty ? .empty : .ok,
      items: items.sorted(by: shortcutItemLessThan),
      warnings: warnings,
      errors: []
    )
  }

  private static func item(
    from reminder: ShortcutTagReminder,
    contractID: ShortcutContractID,
    matchedSemantics: [String],
    parentSourceItemID: String? = nil,
    childSourceItemIDs: [String] = []
  ) -> ShortcutContractItem {
    ShortcutContractItem(
      sourceItemID: sourceItemID(for: reminder, contractID: contractID),
      nativeCalendarItemIdentifier: reminder.id,
      nativeExternalIdentifier: nil,
      title: reminder.title,
      rawNotes: reminder.notes,
      notes: reminder.notes,
      canonicalManagedID: reminder.canonicalManagedID,
      footerState: reminder.canonicalManagedID == nil ? .missing : .valid,
      listTitle: reminder.listName,
      isCompleted: reminder.isCompleted,
      priority: reminder.priority,
      dueAt: reminder.dueAt,
      createdAt: reminder.createdAt,
      updatedAt: reminder.updatedAt,
      url: reminder.url,
      matchedSemantics: matchedSemantics,
      observedTags: reminder.tags,
      parentSourceItemID: parentSourceItemID,
      childSourceItemIDs: childSourceItemIDs
    )
  }

  private static func sourceItemID(for reminder: ShortcutTagReminder, contractID: ShortcutContractID) -> String {
    let stableID = reminder.id
      ?? reminder.canonicalManagedID
      ?? "\(reminder.listName)::\(reminder.title)".lowercased()
    return "\(contractID.sourceQueryFamily)::\(stableID)"
  }

  private static func shortcutItemLessThan(_ lhs: ShortcutContractItem, _ rhs: ShortcutContractItem) -> Bool {
    if lhs.listTitle != rhs.listTitle {
      return lhs.listTitle.localizedCaseInsensitiveCompare(rhs.listTitle) == .orderedAscending
    }
    if lhs.title != rhs.title {
      return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    return lhs.sourceItemID < rhs.sourceItemID
  }

  private static func uniqueReminders(_ reminders: [ShortcutTagReminder]) -> [ShortcutTagReminder] {
    var seen = Set<String>()
    var result: [ShortcutTagReminder] = []
    for reminder in reminders {
      let key = reminder.id ?? reminder.canonicalManagedID ?? "\(reminder.listName)::\(reminder.title)"
      if seen.insert(key).inserted {
        result.append(reminder)
      }
    }
    return result
  }
}

private extension Array where Element == ShortcutContractItem {
  func uniqueBySourceItemID() -> [ShortcutContractItem] {
    var seen = Set<String>()
    var result: [ShortcutContractItem] = []
    for item in self where seen.insert(item.sourceItemID).inserted {
      result.append(item)
    }
    return result
  }
}
