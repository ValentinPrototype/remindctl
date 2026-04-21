import Foundation

public enum ProjectHealthIssue: String, Codable, Sendable, Equatable, CaseIterable {
  case missingAreaTag = "missing_area_tag"
  case multipleAreaTags = "multiple_area_tags"
  case noOpenChildren = "no_open_children"
  case missingNextAction = "missing_next_action"
  case unresolvedChildDetails = "unresolved_child_details"
  case unclassifiedChildren = "unclassified_children"
}

public enum ProjectHealthStatus: String, Codable, Sendable, Equatable {
  case healthy
  case needsNextAction = "needs_next_action"
  case needsCleanup = "needs_cleanup"
}

public struct ProjectHealthSummary: Codable, Sendable, Equatable {
  public let source: String
  public let status: QueryExecutionStatus
  public let confidence: QueryConfidence
  public let freshness: QueryFreshness
  public let acquisitionSources: [String]
  public let warnings: [String]
  public let projectCount: Int
  public let healthyCount: Int
  public let needsNextActionCount: Int
  public let needsCleanupCount: Int
  public let projects: [ProjectHealthProject]

  public var needsAttentionCount: Int {
    projectCount - healthyCount
  }

  public init(
    source: String,
    status: QueryExecutionStatus,
    confidence: QueryConfidence,
    freshness: QueryFreshness,
    acquisitionSources: [String],
    warnings: [String],
    projects: [ProjectHealthProject]
  ) {
    self.source = source
    self.status = status
    self.confidence = confidence
    self.freshness = freshness
    self.acquisitionSources = acquisitionSources
    self.warnings = warnings
    self.projectCount = projects.count
    self.healthyCount = projects.filter { $0.status == .healthy }.count
    self.needsNextActionCount = projects.filter { $0.status == .needsNextAction }.count
    self.needsCleanupCount = projects.filter { $0.status == .needsCleanup }.count
    self.projects = projects
  }

  private enum CodingKeys: String, CodingKey {
    case source
    case status
    case confidence
    case freshness
    case acquisitionSources = "acquisition_sources"
    case warnings
    case projectCount = "project_count"
    case healthyCount = "healthy_count"
    case needsNextActionCount = "needs_next_action_count"
    case needsCleanupCount = "needs_cleanup_count"
    case projects
  }
}

public struct ProjectHealthProject: Codable, Sendable, Equatable {
  public let managedID: String?
  public let canonicalID: String?
  public let sourceItemID: String?
  public let title: String
  public let listName: String
  public let areaTags: [String]
  public let childCount: Int
  public let resolvedChildCount: Int
  public let unresolvedChildTitles: [String]
  public let unresolvedChildReferences: [String]
  public let nextActionCount: Int
  public let waitingOnCount: Int
  public let scheduledCount: Int
  public let unclassifiedChildCount: Int
  public let status: ProjectHealthStatus
  public let issues: [ProjectHealthIssue]
  public let children: [ProjectHealthChild]

  public init(
    managedID: String?,
    canonicalID: String?,
    sourceItemID: String?,
    title: String,
    listName: String,
    areaTags: [String],
    childCount: Int,
    resolvedChildCount: Int,
    unresolvedChildTitles: [String],
    unresolvedChildReferences: [String],
    nextActionCount: Int,
    waitingOnCount: Int,
    scheduledCount: Int,
    unclassifiedChildCount: Int,
    status: ProjectHealthStatus,
    issues: [ProjectHealthIssue],
    children: [ProjectHealthChild]
  ) {
    self.managedID = managedID
    self.canonicalID = canonicalID
    self.sourceItemID = sourceItemID
    self.title = title
    self.listName = listName
    self.areaTags = areaTags
    self.childCount = childCount
    self.resolvedChildCount = resolvedChildCount
    self.unresolvedChildTitles = unresolvedChildTitles
    self.unresolvedChildReferences = unresolvedChildReferences
    self.nextActionCount = nextActionCount
    self.waitingOnCount = waitingOnCount
    self.scheduledCount = scheduledCount
    self.unclassifiedChildCount = unclassifiedChildCount
    self.status = status
    self.issues = issues
    self.children = children
  }

  private enum CodingKeys: String, CodingKey {
    case managedID = "managed_id"
    case canonicalID = "canonical_id"
    case sourceItemID = "source_item_id"
    case title
    case listName = "list_name"
    case areaTags = "area_tags"
    case childCount = "child_count"
    case resolvedChildCount = "resolved_child_count"
    case unresolvedChildTitles = "unresolved_child_titles"
    case unresolvedChildReferences = "unresolved_child_references"
    case nextActionCount = "next_action_count"
    case waitingOnCount = "waiting_on_count"
    case scheduledCount = "scheduled_count"
    case unclassifiedChildCount = "unclassified_child_count"
    case status
    case issues
    case children
  }
}

public struct ProjectHealthChild: Codable, Sendable, Equatable {
  public let managedID: String?
  public let canonicalID: String?
  public let sourceItemID: String?
  public let title: String
  public let tags: [String]
  public let isCompleted: Bool
  public let isUnclassified: Bool

  public init(_ reminder: ProjectHealthReminder) {
    managedID = reminder.managedID
    canonicalID = reminder.canonicalID
    sourceItemID = reminder.sourceItemID
    title = reminder.title
    tags = reminder.tags
    isCompleted = reminder.isCompleted
    isUnclassified = ProjectHealth.workflowTags.isDisjoint(with: Set(reminder.tags))
  }

  private enum CodingKeys: String, CodingKey {
    case managedID = "managed_id"
    case canonicalID = "canonical_id"
    case sourceItemID = "source_item_id"
    case title
    case tags
    case isCompleted = "is_completed"
    case isUnclassified = "is_unclassified"
  }
}

public struct ProjectHealthReminder: Sendable, Equatable {
  public let id: String?
  public let sourceItemID: String?
  public let canonicalID: String?
  public let managedID: String?
  public let title: String
  public let listName: String
  public let isCompleted: Bool
  public let priority: ReminderPriority
  public let dueAt: Date?
  public let createdAt: Date?
  public let updatedAt: Date?
  public let tags: [String]
  public let childTitles: [String]

  public init(
    id: String? = nil,
    sourceItemID: String? = nil,
    canonicalID: String? = nil,
    managedID: String? = nil,
    title: String,
    listName: String,
    isCompleted: Bool,
    priority: ReminderPriority,
    dueAt: Date?,
    createdAt: Date?,
    updatedAt: Date?,
    tags: [String],
    childTitles: [String] = []
  ) {
    self.id = id
    self.sourceItemID = sourceItemID
    self.canonicalID = canonicalID
    self.managedID = managedID
    self.title = title
    self.listName = listName
    self.isCompleted = isCompleted
    self.priority = priority
    self.dueAt = dueAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.tags = tags
    self.childTitles = childTitles
  }

  public init(_ item: GTDQueryItem, tags: [String]? = nil, childTitles: [String] = []) {
    self.init(
      id: item.id,
      sourceItemID: item.sourceItemID,
      canonicalID: item.canonicalID,
      managedID: item.canonicalManagedID,
      title: item.title,
      listName: item.listTitle,
      isCompleted: item.isCompleted,
      priority: item.priority,
      dueAt: item.dueAt,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      tags: tags ?? ProjectHealth.uniqueTags(item.observedTags + item.matchedSemantics),
      childTitles: childTitles
    )
  }
}

public struct ProjectHealthInput: Sendable, Equatable {
  public let project: ProjectHealthReminder
  public let areaTags: [String]
  public let children: [ProjectHealthReminder]
  public let unresolvedChildTitles: [String]
  public let unresolvedChildReferences: [String]

  public init(
    project: ProjectHealthReminder,
    areaTags: [String],
    children: [ProjectHealthReminder],
    unresolvedChildTitles: [String] = [],
    unresolvedChildReferences: [String] = []
  ) {
    self.project = project
    self.areaTags = areaTags
    self.children = children
    self.unresolvedChildTitles = unresolvedChildTitles
    self.unresolvedChildReferences = unresolvedChildReferences
  }
}

public enum ProjectHealth {
  public static let workflowTags: Set<String> = ["next-action", "waiting-on", "scheduled"]

  public static func evaluate(
    source: String,
    status: QueryExecutionStatus = .ok,
    confidence: QueryConfidence = .medium,
    freshness: QueryFreshness = QueryFreshness(evaluatedAt: Date(), nativeSyncedAt: nil, shortcutGeneratedAt: nil),
    acquisitionSources: [String] = [],
    warnings: [String] = [],
    projects inputs: [ProjectHealthInput]
  ) -> ProjectHealthSummary {
    let projects = inputs.map(evaluateProject).sorted { lhs, rhs in
      lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    let resolvedStatus = status == .ok && projects.isEmpty ? .empty : status

    return ProjectHealthSummary(
      source: source,
      status: resolvedStatus,
      confidence: confidence,
      freshness: freshness,
      acquisitionSources: acquisitionSources,
      warnings: warnings,
      projects: projects
    )
  }

  public static func areaTags(in tags: [String]) -> [String] {
    tags.filter { $0.hasPrefix("area-") }
  }

  public static func uniqueTags(_ tags: [String]) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for tag in tags where seen.insert(tag).inserted {
      result.append(tag)
    }
    return result
  }

  private static func evaluateProject(_ input: ProjectHealthInput) -> ProjectHealthProject {
    let openChildren = input.children.filter { !$0.isCompleted }
    let resolvedChildTitles = Set(openChildren.map(\.title))
    let derivedUnresolvedChildTitles = input.project.childTitles
      .filter { !resolvedChildTitles.contains($0) }
    let unresolvedChildTitles = Array(Set(input.unresolvedChildTitles + derivedUnresolvedChildTitles))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    let unresolvedChildReferences = Array(Set(input.unresolvedChildReferences)).sorted()

    let childCount = max(
      input.project.childTitles.count,
      openChildren.count + unresolvedChildTitles.count + unresolvedChildReferences.count
    )
    let nextActionCount = openChildren.filter { $0.tags.contains("next-action") }.count
    let waitingOnCount = openChildren.filter { $0.tags.contains("waiting-on") }.count
    let scheduledCount = openChildren.filter { $0.tags.contains("scheduled") }.count
    let unclassifiedChildCount = openChildren.filter { workflowTags.isDisjoint(with: Set($0.tags)) }.count

    var issues: [ProjectHealthIssue] = []
    if input.areaTags.isEmpty {
      issues.append(.missingAreaTag)
    }
    if input.areaTags.count > 1 {
      issues.append(.multipleAreaTags)
    }
    if childCount == 0 {
      issues.append(.noOpenChildren)
    }
    if nextActionCount == 0 {
      issues.append(.missingNextAction)
    }
    if !unresolvedChildTitles.isEmpty || !unresolvedChildReferences.isEmpty {
      issues.append(.unresolvedChildDetails)
    }
    if unclassifiedChildCount > 0 {
      issues.append(.unclassifiedChildren)
    }

    return ProjectHealthProject(
      managedID: input.project.managedID,
      canonicalID: input.project.canonicalID,
      sourceItemID: input.project.sourceItemID,
      title: input.project.title,
      listName: input.project.listName,
      areaTags: input.areaTags,
      childCount: childCount,
      resolvedChildCount: openChildren.count,
      unresolvedChildTitles: unresolvedChildTitles,
      unresolvedChildReferences: unresolvedChildReferences,
      nextActionCount: nextActionCount,
      waitingOnCount: waitingOnCount,
      scheduledCount: scheduledCount,
      unclassifiedChildCount: unclassifiedChildCount,
      status: status(for: issues),
      issues: issues,
      children: openChildren.map(ProjectHealthChild.init)
    )
  }

  private static func status(for issues: [ProjectHealthIssue]) -> ProjectHealthStatus {
    if issues.isEmpty {
      return .healthy
    }
    if issues.contains(.noOpenChildren) || issues.contains(.missingNextAction) {
      return .needsNextAction
    }
    return .needsCleanup
  }
}

public struct WeeklyReviewSummary: Codable, Sendable, Equatable {
  public let generatedAt: Date
  public let status: QueryExecutionStatus
  public let confidence: QueryConfidence
  public let freshness: QueryFreshness
  public let warnings: [String]
  public let projectHealth: ProjectHealthSummary
  public let nextActions: [GTDQueryItem]
  public let waitingOns: [GTDQueryItem]
  public let overdueActionables: [GTDQueryItem]
  public let oldEmptyNotes: [GTDQueryItem]
  public let oldVagueTasks: [GTDQueryItem]

  public var nextActionCount: Int { nextActions.count }
  public var waitingOnCount: Int { waitingOns.count }
  public var overdueActionableCount: Int { overdueActionables.count }
  public var oldEmptyNoteCount: Int { oldEmptyNotes.count }
  public var oldVagueTaskCount: Int { oldVagueTasks.count }

  public init(
    generatedAt: Date,
    status: QueryExecutionStatus,
    confidence: QueryConfidence,
    freshness: QueryFreshness,
    warnings: [String],
    projectHealth: ProjectHealthSummary,
    nextActions: [GTDQueryItem],
    waitingOns: [GTDQueryItem],
    overdueActionables: [GTDQueryItem],
    oldEmptyNotes: [GTDQueryItem],
    oldVagueTasks: [GTDQueryItem]
  ) {
    self.generatedAt = generatedAt
    self.status = status
    self.confidence = confidence
    self.freshness = freshness
    self.warnings = warnings
    self.projectHealth = projectHealth
    self.nextActions = nextActions
    self.waitingOns = waitingOns
    self.overdueActionables = overdueActionables
    self.oldEmptyNotes = oldEmptyNotes
    self.oldVagueTasks = oldVagueTasks
  }

  private enum CodingKeys: String, CodingKey {
    case generatedAt = "generated_at"
    case status
    case confidence
    case freshness
    case warnings
    case projectHealth = "project_health"
    case nextActions = "next_actions"
    case waitingOns = "waiting_ons"
    case overdueActionables = "overdue_actionables"
    case oldEmptyNotes = "old_empty_notes"
    case oldVagueTasks = "old_vague_tasks"
  }
}
