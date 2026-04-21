import Foundation

public extension GTDMirrorStore {
  func queryProjectHealth(
    areaTag: String? = nil,
    listTitle: String? = nil,
    now: Date = Date()
  ) throws -> ProjectHealthSummary {
    let activeProjects = try querySemantic(
      contractID: .activeProjects,
      listTitle: listTitle,
      dueFilter: .any,
      olderThanDays: nil,
      now: now
    )
    let hierarchy = try queryHierarchy(now: now)
    let freshness = combinedFreshness(
      evaluatedAt: now,
      [activeProjects.freshness, hierarchy.freshness]
    )
    let warnings = uniqueStrings(activeProjects.warnings + hierarchy.warnings)
    let acquisitionSources = uniqueStrings(activeProjects.acquisitionSources + hierarchy.acquisitionSources)
    let confidence = lowestConfidence([activeProjects.confidence, hierarchy.confidence])

    guard activeProjects.status != .sourceError else {
      return emptyProjectHealth(
        source: "mirror",
        status: .sourceError,
        confidence: confidence,
        freshness: freshness,
        acquisitionSources: acquisitionSources,
        warnings: warnings
      )
    }
    guard hierarchy.status != .sourceError else {
      return emptyProjectHealth(
        source: "mirror",
        status: .sourceError,
        confidence: confidence,
        freshness: freshness,
        acquisitionSources: acquisitionSources,
        warnings: warnings
      )
    }
    guard activeProjects.status != .unsupported else {
      return emptyProjectHealth(
        source: "mirror",
        status: .unsupported,
        confidence: .low,
        freshness: freshness,
        acquisitionSources: acquisitionSources,
        warnings: warnings
      )
    }
    guard hierarchy.status != .unsupported else {
      return emptyProjectHealth(
        source: "mirror",
        status: .unsupported,
        confidence: .low,
        freshness: freshness,
        acquisitionSources: acquisitionSources,
        warnings: warnings
      )
    }

    let normalizedAreaTag = areaTag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let activeItems = activeProjects.items
      .filter { !$0.isCompleted }
      .filter { item in
        guard let normalizedAreaTag else { return true }
        return semanticTags(for: item).contains(normalizedAreaTag)
      }
    let hierarchyItems = hierarchy.items
    var hierarchyBySourceID: [String: GTDQueryItem] = [:]
    for item in hierarchyItems {
      guard let sourceItemID = item.sourceItemID, hierarchyBySourceID[sourceItemID] == nil else {
        continue
      }
      hierarchyBySourceID[sourceItemID] = item
    }

    var projectWarnings: [String] = []
    let inputs = activeItems.map { activeItem in
      let parent = hierarchyParent(for: activeItem, in: hierarchyItems)
      let childReferences = parent?.childSourceItemIDs ?? []
      let resolvedChildItems = childReferences.compactMap { hierarchyBySourceID[$0] }
      let unresolvedChildReferences = childReferences.filter { hierarchyBySourceID[$0] == nil }
      if parent == nil {
        projectWarnings.append("No hierarchy row matched active project \(activeItem.title).")
      }
      if unresolvedChildReferences.isEmpty == false {
        projectWarnings.append(
          "Hierarchy row for \(activeItem.title) referenced unresolved children: \(unresolvedChildReferences.joined(separator: ", "))."
        )
      }

      let projectTags = semanticTags(for: activeItem)
      return ProjectHealthInput(
        project: ProjectHealthReminder(activeItem, tags: projectTags),
        areaTags: ProjectHealth.areaTags(in: projectTags),
        children: resolvedChildItems.map { ProjectHealthReminder($0, tags: semanticTags(for: $0)) },
        unresolvedChildReferences: unresolvedChildReferences
      )
    }

    return ProjectHealth.evaluate(
      source: "mirror",
      status: .ok,
      confidence: confidence,
      freshness: freshness,
      acquisitionSources: acquisitionSources,
      warnings: uniqueStrings(warnings + projectWarnings),
      projects: inputs
    )
  }

  func queryWeeklyReview(
    areaTag: String? = nil,
    listTitle: String? = nil,
    olderThanDays: Int = 14,
    waitingOnDays: Int = 7,
    now: Date = Date()
  ) throws -> WeeklyReviewSummary {
    let projectHealth = try queryProjectHealth(areaTag: areaTag, listTitle: listTitle, now: now)
    let nextActions = try querySemantic(
      contractID: .nextActions,
      listTitle: listTitle,
      dueFilter: .any,
      olderThanDays: nil,
      now: now
    )
    let waitingOns = try querySemantic(
      contractID: .waitingOns,
      listTitle: listTitle,
      dueFilter: .any,
      olderThanDays: waitingOnDays,
      now: now
    )
    let overdueActionables = try querySemantic(
      contractID: .nextActions,
      listTitle: listTitle,
      dueFilter: .overdue,
      olderThanDays: nil,
      now: now
    )
    let oldEmptyNotes = try queryOldIncompleteEmptyNotes(olderThanDays: olderThanDays, now: now)
    let oldVagueTasks = try queryOldVagueIncompleteReminders(olderThanDays: olderThanDays, now: now)

    let normalizedAreaTag = areaTag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let queryResults = [nextActions, waitingOns, overdueActionables, oldEmptyNotes, oldVagueTasks]
    let freshness = combinedFreshness(
      evaluatedAt: now,
      [projectHealth.freshness] + queryResults.map(\.freshness)
    )
    let status = combinedStatus([projectHealth.status] + queryResults.map(\.status))
    let confidence = lowestConfidence([projectHealth.confidence] + queryResults.map(\.confidence))
    let warnings = uniqueStrings(projectHealth.warnings + queryResults.flatMap(\.warnings))

    return WeeklyReviewSummary(
      generatedAt: now,
      status: status,
      confidence: confidence,
      freshness: freshness,
      warnings: warnings,
      projectHealth: projectHealth,
      nextActions: filterByArea(nextActions.items, areaTag: normalizedAreaTag),
      waitingOns: filterByArea(waitingOns.items, areaTag: normalizedAreaTag),
      overdueActionables: filterByArea(overdueActionables.items, areaTag: normalizedAreaTag),
      oldEmptyNotes: filterByArea(oldEmptyNotes.items, areaTag: normalizedAreaTag),
      oldVagueTasks: filterByArea(oldVagueTasks.items, areaTag: normalizedAreaTag)
    )
  }
}

private func emptyProjectHealth(
  source: String,
  status: QueryExecutionStatus,
  confidence: QueryConfidence,
  freshness: QueryFreshness,
  acquisitionSources: [String],
  warnings: [String]
) -> ProjectHealthSummary {
  ProjectHealth.evaluate(
    source: source,
    status: status,
    confidence: confidence,
    freshness: freshness,
    acquisitionSources: acquisitionSources,
    warnings: warnings,
    projects: []
  )
}

private func hierarchyParent(for activeItem: GTDQueryItem, in hierarchyItems: [GTDQueryItem]) -> GTDQueryItem? {
  if let canonicalID = activeItem.canonicalID,
    let match = hierarchyItems.first(where: { $0.canonicalID == canonicalID })
  {
    return match
  }
  if let managedID = activeItem.canonicalManagedID,
    let match = hierarchyItems.first(where: { $0.canonicalManagedID == managedID })
  {
    return match
  }
  return hierarchyItems.first { item in
    item.parentSourceItemID == nil
      && item.title == activeItem.title
      && item.listTitle == activeItem.listTitle
  }
}

private func filterByArea(_ items: [GTDQueryItem], areaTag: String?) -> [GTDQueryItem] {
  guard let areaTag else { return items }
  return items.filter { semanticTags(for: $0).contains(areaTag) }
}

private func semanticTags(for item: GTDQueryItem) -> [String] {
  ProjectHealth.uniqueTags(item.observedTags + item.matchedSemantics)
}

private func combinedStatus(_ statuses: [QueryExecutionStatus]) -> QueryExecutionStatus {
  if statuses.contains(.sourceError) {
    return .sourceError
  }
  if statuses.contains(.unsupported) {
    return .unsupported
  }
  if statuses.contains(.ok) {
    return .ok
  }
  return .empty
}

private func lowestConfidence(_ confidences: [QueryConfidence]) -> QueryConfidence {
  if confidences.contains(.low) {
    return .low
  }
  if confidences.contains(.medium) {
    return .medium
  }
  return .high
}

private func combinedFreshness(evaluatedAt: Date, _ freshnesses: [QueryFreshness]) -> QueryFreshness {
  QueryFreshness(
    evaluatedAt: evaluatedAt,
    nativeSyncedAt: freshnesses.compactMap(\.nativeSyncedAt).max(),
    shortcutGeneratedAt: freshnesses.compactMap(\.shortcutGeneratedAt).max()
  )
}

private func uniqueStrings(_ values: [String]) -> [String] {
  var result: [String] = []
  var seen = Set<String>()
  for value in values where seen.insert(value).inserted {
    result.append(value)
  }
  return result
}
