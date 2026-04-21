import Foundation

enum ProjectHealthIssue: String, Codable, Sendable, Equatable, CaseIterable {
  case missingAreaTag = "missing_area_tag"
  case multipleAreaTags = "multiple_area_tags"
  case noOpenChildren = "no_open_children"
  case missingNextAction = "missing_next_action"
  case unresolvedChildDetails = "unresolved_child_details"
  case unclassifiedChildren = "unclassified_children"
}

enum ProjectHealthStatus: String, Codable, Sendable, Equatable {
  case healthy
  case needsNextAction = "needs_next_action"
  case needsCleanup = "needs_cleanup"
}

struct ProjectHealthSummary: Codable, Sendable, Equatable {
  let source: String
  let projectCount: Int
  let healthyCount: Int
  let needsNextActionCount: Int
  let needsCleanupCount: Int
  let projects: [ProjectHealthProject]

  var needsAttentionCount: Int {
    projectCount - healthyCount
  }

  private enum CodingKeys: String, CodingKey {
    case source
    case projectCount = "project_count"
    case healthyCount = "healthy_count"
    case needsNextActionCount = "needs_next_action_count"
    case needsCleanupCount = "needs_cleanup_count"
    case projects
  }
}

struct ProjectHealthProject: Codable, Sendable, Equatable {
  let managedID: String?
  let title: String
  let listName: String
  let areaTags: [String]
  let childCount: Int
  let resolvedChildCount: Int
  let unresolvedChildTitles: [String]
  let nextActionCount: Int
  let waitingOnCount: Int
  let scheduledCount: Int
  let unclassifiedChildCount: Int
  let status: ProjectHealthStatus
  let issues: [ProjectHealthIssue]
  let children: [ProjectHealthChild]

  private enum CodingKeys: String, CodingKey {
    case managedID = "managed_id"
    case title
    case listName = "list_name"
    case areaTags = "area_tags"
    case childCount = "child_count"
    case resolvedChildCount = "resolved_child_count"
    case unresolvedChildTitles = "unresolved_child_titles"
    case nextActionCount = "next_action_count"
    case waitingOnCount = "waiting_on_count"
    case scheduledCount = "scheduled_count"
    case unclassifiedChildCount = "unclassified_child_count"
    case status
    case issues
    case children
  }
}

struct ProjectHealthChild: Codable, Sendable, Equatable {
  let managedID: String?
  let title: String
  let tags: [String]
  let isCompleted: Bool
  let isUnclassified: Bool

  init(_ reminder: ShortcutTagReminder) {
    managedID = reminder.canonicalManagedID
    title = reminder.title
    tags = reminder.tags
    isCompleted = reminder.isCompleted
    isUnclassified = ProjectHealth.workflowTags.isDisjoint(with: Set(reminder.tags))
  }

  private enum CodingKeys: String, CodingKey {
    case managedID = "managed_id"
    case title
    case tags
    case isCompleted = "is_completed"
    case isUnclassified = "is_unclassified"
  }
}

struct ProjectHealthInput: Sendable, Equatable {
  let project: ShortcutTagReminder
  let areaTags: [String]
  let children: [ShortcutTagReminder]
}

enum ProjectHealth {
  static let workflowTags: Set<String> = ["next-action", "waiting-on", "scheduled"]

  static func evaluate(source: String, projects inputs: [ProjectHealthInput]) -> ProjectHealthSummary {
    let projects = inputs.map(evaluateProject).sorted { lhs, rhs in
      lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    let healthyCount = projects.filter { $0.status == .healthy }.count
    let needsNextActionCount = projects.filter { $0.status == .needsNextAction }.count
    let needsCleanupCount = projects.filter { $0.status == .needsCleanup }.count

    return ProjectHealthSummary(
      source: source,
      projectCount: projects.count,
      healthyCount: healthyCount,
      needsNextActionCount: needsNextActionCount,
      needsCleanupCount: needsCleanupCount,
      projects: projects
    )
  }

  static func areaTags(in tags: [String]) -> [String] {
    ProjectWorkflow.areaTags(in: tags)
  }

  private static func evaluateProject(_ input: ProjectHealthInput) -> ProjectHealthProject {
    let openChildren = input.children.filter { !$0.isCompleted }
    let resolvedChildTitles = Set(openChildren.map(\.title))
    let unresolvedChildTitles = input.project.subTasks
      .filter { !resolvedChildTitles.contains($0) }
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    let childCount = max(input.project.subTasks.count, openChildren.count)
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
    if !unresolvedChildTitles.isEmpty {
      issues.append(.unresolvedChildDetails)
    }
    if unclassifiedChildCount > 0 {
      issues.append(.unclassifiedChildren)
    }

    return ProjectHealthProject(
      managedID: input.project.canonicalManagedID,
      title: input.project.title,
      listName: input.project.listName,
      areaTags: input.areaTags,
      childCount: childCount,
      resolvedChildCount: openChildren.count,
      unresolvedChildTitles: unresolvedChildTitles,
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
