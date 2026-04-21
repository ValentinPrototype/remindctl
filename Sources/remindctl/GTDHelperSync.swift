import Foundation
import RemindCore

struct GTDHelperSyncSnapshot {
  let payloads: [ValidatedShortcutContractPayload]
  let tagObservationItems: [ShortcutContractItem]
}

enum GTDHelperSync {
  static func sync(mirrorURL: URL, generatedAt: Date = Date()) async throws -> MirrorSyncSummary {
    let store = RemindersStore()
    try await store.requestAccess()
    _ = try await store.normalizeManagedNoteFooters()
    let nativeReminders = try await store.nativeReminders()
    let snapshot = try helperSnapshot(generatedAt: generatedAt)

    let mirror = try GTDMirrorStore(databaseURL: mirrorURL)
    let summary = try await mirror.replaceSnapshot(
      nativeReminders: nativeReminders,
      shortcutPayloads: snapshot.payloads,
      tagObservationItems: snapshot.tagObservationItems,
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
    try helperSnapshot(generatedAt: generatedAt).payloads
  }

  static func helperSnapshot(generatedAt: Date = Date()) throws -> GTDHelperSyncSnapshot {
    let activeProjects = try ShortcutTagSearch.search(tags: ["active-project"])
    let nextActions = try ShortcutTagSearch.search(tags: ["next-action"])
    let waitingOns = try ShortcutTagSearch.search(tags: ["waiting-on"])

    return try helperSnapshot(
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
    try helperSnapshot(
      activeProjects: activeProjects,
      nextActions: nextActions,
      waitingOns: waitingOns,
      generatedAt: generatedAt
    ).payloads
  }

  static func helperSnapshot(
    activeProjects: [ShortcutTagReminder],
    nextActions: [ShortcutTagReminder],
    waitingOns: [ShortcutTagReminder],
    generatedAt: Date
  ) throws -> GTDHelperSyncSnapshot {
    let areaTags = Set((activeProjects + nextActions + waitingOns).flatMap { ProjectHealth.areaTags(in: $0.tags) })
    var areaReminders: [ShortcutTagReminder] = []
    for areaTag in areaTags.sorted() {
      areaReminders.append(contentsOf: try ShortcutTagSearch.search(tags: [areaTag]))
    }

    return helperSnapshot(
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
    helperSnapshot(
      activeProjects: activeProjects,
      nextActions: nextActions,
      waitingOns: waitingOns,
      areaReminders: areaReminders,
      generatedAt: generatedAt
    ).payloads
  }

  static func helperSnapshot(
    activeProjects: [ShortcutTagReminder],
    nextActions: [ShortcutTagReminder],
    waitingOns: [ShortcutTagReminder],
    areaReminders: [ShortcutTagReminder],
    generatedAt: Date
  ) -> GTDHelperSyncSnapshot {
    GTDHelperSyncSnapshot(
      payloads: [
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
      ],
      tagObservationItems: tagObservationItems(from: areaReminders)
    )
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

      let resolution = resolveChildren(for: project, in: candidates)
      warnings.append(contentsOf: resolution.warnings)
      let children = resolution.children
        .filter { !insertedSourceIDs.contains(sourceItemID(for: $0, contractID: .productivityHierarchy)) }
        .sorted { lhs, rhs in
          lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
      let skippedChildren = resolution.children.filter {
        insertedSourceIDs.contains(sourceItemID(for: $0, contractID: .productivityHierarchy))
      }
      if skippedChildren.isEmpty == false {
        warnings.append(
          ContractDiagnostic(
            code: "duplicate_hierarchy_child_reference",
            message: "Project \(project.title) referenced children already assigned to another parent: \(skippedChildren.map(\.title).joined(separator: ", "))"
          )
        )
      }

      let unresolvedChildTitles = resolution.unresolvedTitles
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

  private static func tagObservationItems(from reminders: [ShortcutTagReminder]) -> [ShortcutContractItem] {
    uniqueReminders(reminders)
      .filter { !$0.isCompleted }
      .map { reminder in
        ShortcutContractItem(
          sourceItemID: "tag-observation::\(reminder.id ?? reminder.canonicalManagedID ?? "\(reminder.listName)::\(reminder.title)")",
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
          matchedSemantics: [],
          observedTags: reminder.tags,
          parentSourceItemID: nil,
          childSourceItemIDs: []
        )
      }
      .uniqueBySourceItemID()
  }

  private static func resolveChildren(
    for project: ShortcutTagReminder,
    in candidates: [ShortcutTagReminder]
  ) -> ChildResolution {
    let candidatePool = candidates
      .filter { !$0.isCompleted }
      .filter { $0.canonicalManagedID != project.canonicalManagedID }

    var children: [ShortcutTagReminder] = []
    var childSourceIDs = Set<String>()
    var unresolvedTitles: [String] = []
    var warnings: [ContractDiagnostic] = []

    func appendChild(_ child: ShortcutTagReminder) {
      let childSourceID = sourceItemID(for: child, contractID: .productivityHierarchy)
      if childSourceIDs.insert(childSourceID).inserted {
        children.append(child)
      }
    }

    let parentMatches = candidatePool.filter { $0.parent == project.title }
    for child in parentMatches {
      appendChild(child)
    }

    let parentMatchedTitles = Set(parentMatches.map(\.title))
    for childTitle in project.subTasks where !parentMatchedTitles.contains(childTitle) {
      let titleMatches = candidatePool.filter { $0.title == childTitle }
      if titleMatches.count == 1, let onlyMatch = titleMatches.first, onlyMatch.parent == nil {
        appendChild(onlyMatch)
        continue
      }

      unresolvedTitles.append(childTitle)
      if titleMatches.count > 1 || titleMatches.contains(where: { $0.parent != nil && $0.parent != project.title }) {
        warnings.append(
          ContractDiagnostic(
            code: "ambiguous_child_title",
            message: "Project \(project.title) lists child title \(childTitle), but title lookup matched another parent or multiple reminders. Parent field match is required."
          )
        )
      }
    }

    return ChildResolution(
      children: children,
      unresolvedTitles: unresolvedTitles,
      warnings: warnings
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

private struct ChildResolution {
  let children: [ShortcutTagReminder]
  let unresolvedTitles: [String]
  let warnings: [ContractDiagnostic]
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
