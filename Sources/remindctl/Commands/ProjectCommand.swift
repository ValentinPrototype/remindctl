import Commander
import Foundation
import RemindCore

enum ProjectCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "project",
      abstract: "Manage GTD project reminders and subtasks",
      discussion: "Projects are top-level reminders; executable work is represented as child reminders.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "action", help: "create|add-step|attach|show"),
            .make(label: "id-or-title", help: "Project title, project ID, or task ID", isOptional: true),
            .make(label: "title", help: "Step title for add-step", isOptional: true),
          ],
          options: [
            .make(label: "area", names: [.long("area")], help: "Project area, for example work or area-work", parsing: .singleValue),
            .make(label: "list", names: [.short("l"), .long("list")], help: "List name for project creation", parsing: .singleValue),
            .make(label: "status", names: [.long("status")], help: "active|someday", parsing: .singleValue),
            .make(label: "supportURL", names: [.long("support-url")], help: "Obsidian or support-material URL", parsing: .singleValue),
            .make(label: "step", names: [.long("step")], help: "Initial child step title (repeatable)", parsing: .singleValue),
            .make(label: "kind", names: [.long("kind")], help: "next-action|waiting-on|task|scheduled", parsing: .singleValue),
            .make(label: "context", names: [.long("context")], help: "Context tag, for example phone-call or c-phone-call", parsing: .singleValue),
            .make(label: "energy", names: [.long("energy")], help: "Energy tag, for example low or e-low", parsing: .singleValue),
            .make(label: "due", names: [.short("d"), .long("due")], help: "Due date for a child step", parsing: .singleValue),
            .make(label: "notes", names: [.short("n"), .long("notes")], help: "Notes for a child step", parsing: .singleValue),
            .make(label: "priority", names: [.short("p"), .long("priority")], help: "none|low|medium|high", parsing: .singleValue),
            .make(label: "to", names: [.long("to")], help: "Project ID for attach", parsing: .singleValue),
            .make(label: "mirror", names: [.long("mirror")], help: "Path to the mirror SQLite database for project show", parsing: .singleValue),
          ],
          flags: [
            .make(label: "all", names: [.long("all")], help: "Show completed and incomplete hierarchy items"),
            .make(label: "completed", names: [.long("completed")], help: "Show completed hierarchy items only"),
          ]
        )
      ),
      usageExamples: [
        "remindctl project create \"Ship v1\" --area work --step \"Draft release notes\"",
        "remindctl project add-step 2 \"Email supplier\" --kind next-action --context messenger --energy low",
        "remindctl project attach 4 --to 2",
        "remindctl project show 2 --all",
      ]
    ) { values, runtime in
      let action = try values.argument(0).unwrap(or: ParsedValuesError.missingArgument("action"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

      switch action {
      case "create":
        try await createProject(values: values, runtime: runtime)
      case "add-step":
        try await addStep(values: values, runtime: runtime)
      case "attach":
        try await attachTask(values: values, runtime: runtime)
      case "show":
        try await showProject(values: values, runtime: runtime)
      default:
        throw RemindCoreError.operationFailed("Unknown project action: \(action) (use create|add-step|attach|show)")
      }
    }
  }

  private static func createProject(values: ParsedValues, runtime: RuntimeOptions) async throws {
    let title = try requiredArgument(values, index: 1, name: "title")
    let areaTag = try ProjectWorkflow.normalizeAreaTag(values.optionRequired("area"))
    let status = try ProjectWorkflow.parseStatus(values.option("status"))
    let projectTags = ProjectWorkflow.projectTags(areaTag: areaTag, status: status)

    let store = RemindersStore()
    try await store.requestAccess()
    let targetList = try await resolveTargetList(values.option("list"), store: store)

    let notes = values.option("supportURL").map { "Support: \($0)" }
    let project = try await store.createReminder(
      ReminderDraft(title: title, notes: notes, dueDate: nil, priority: .none),
      listName: targetList
    )

    let projectTarget = try await store.mutationTarget(forReminderID: project.id)
    do {
      try ShortcutTagMutation.apply(.set(projectTags), to: projectTarget)
    } catch {
      throw RemindCoreError.operationFailed("Project created, but tag mutation failed. \(error.localizedDescription)")
    }

    for stepTitle in values.optionValues("step") {
      _ = try createChild(
        parentManagedID: projectTarget.canonicalManagedID,
        title: stepTitle,
        notes: nil,
        dueDate: nil,
        priority: .none,
        tags: [areaTag],
        failurePrefix: "Project created, but initial step creation failed."
      )
    }

    OutputRenderer.printReminder(project, format: runtime.outputFormat)
  }

  private static func addStep(values: ParsedValues, runtime: RuntimeOptions) async throws {
    let projectInput = try requiredArgument(values, index: 1, name: "project-id")
    let title = try requiredArgument(values, index: 2, name: "title")
    let dueDate = try values.option("due").map(CommandHelpers.parseDueDate)
    let priority = try values.option("priority").map(CommandHelpers.parsePriority) ?? .none
    let kind = try ProjectWorkflow.parseStepKind(values.option("kind"))

    let store = RemindersStore()
    try await store.requestAccess()
    let parentTarget = try await mutationTarget(for: projectInput, store: store)
    let areaTag = try ProjectWorkflow.findAreaTag(forParentManagedID: parentTarget.canonicalManagedID)
    let tags = try ProjectWorkflow.childTags(
      areaTag: areaTag,
      kind: kind,
      context: values.option("context"),
      energy: values.option("energy"),
      dueDate: dueDate
    )

    let childManagedID = try createChild(
      parentManagedID: parentTarget.canonicalManagedID,
      title: title,
      notes: values.option("notes"),
      dueDate: dueDate,
      priority: priority,
      tags: tags,
      failurePrefix: "Project step creation failed."
    )

    printChildResult(title: title, managedID: childManagedID, format: runtime.outputFormat)
  }

  private static func attachTask(values: ParsedValues, runtime: RuntimeOptions) async throws {
    let taskInput = try requiredArgument(values, index: 1, name: "task-id")
    let projectInput = try values.optionRequired("to")

    let store = RemindersStore()
    try await store.requestAccess()
    let parentTarget = try await mutationTarget(for: projectInput, store: store)
    let childTarget = try await mutationTarget(for: taskInput, store: store)
    guard parentTarget.canonicalManagedID != childTarget.canonicalManagedID else {
      throw RemindCoreError.operationFailed("Cannot attach a project to itself")
    }

    let request = ShortcutHierarchyMutationRequest(
      operation: .attachExisting(
        parentManagedID: parentTarget.canonicalManagedID,
        childManagedID: childTarget.canonicalManagedID
      )
    )
    do {
      _ = try ShortcutHierarchyMutation.apply(request)
    } catch {
      throw RemindCoreError.operationFailed("Project attach failed. \(error.localizedDescription)")
    }

    let areaTag = try ProjectWorkflow.findAreaTag(forParentManagedID: parentTarget.canonicalManagedID)
    do {
      try ShortcutTagMutation.apply(.add([areaTag]), to: childTarget)
    } catch {
      throw RemindCoreError.operationFailed("Task attached, but inherited area tag mutation failed. \(error.localizedDescription)")
    }

    switch runtime.outputFormat {
    case .standard:
      Swift.print("Attached task to project")
    case .plain:
      Swift.print("\(parentTarget.canonicalManagedID)\t\(childTarget.canonicalManagedID)")
    case .json:
      OutputRenderer.printProjectMutation(
        ProjectMutationSummary(
          operation: "attach_existing",
          parentManagedID: parentTarget.canonicalManagedID,
          childManagedID: childTarget.canonicalManagedID
        ),
        format: .json
      )
    case .quiet:
      break
    }
  }

  private static func showProject(values: ParsedValues, runtime: RuntimeOptions) async throws {
    let projectInput = try requiredArgument(values, index: 1, name: "project-id")
    if values.flag("all") && values.flag("completed") {
      throw RemindCoreError.operationFailed("Use either --all or --completed, not both")
    }

    let store = RemindersStore()
    try await store.requestAccess()
    let parentTarget = try await mutationTarget(for: projectInput, store: store)
    let mirrorURL = if let mirrorPath = values.option("mirror") {
      URL(fileURLWithPath: mirrorPath)
    } else {
      try MirrorPaths.defaultDatabaseURL()
    }

    let mirror = try GTDMirrorStore(databaseURL: mirrorURL)
    let result = try await mirror.queryHierarchy(parentCanonicalID: parentTarget.canonicalManagedID)
    let filteredItems = result.items.filter { item in
      if values.flag("all") {
        return true
      }
      if values.flag("completed") {
        return item.isCompleted
      }
      return item.canonicalID == parentTarget.canonicalManagedID || item.isCompleted == false
    }
    let filteredResult = GTDQueryResult(
      queryFamily: result.queryFamily,
      status: filteredItems.isEmpty && result.status == .ok ? .empty : result.status,
      confidence: result.confidence,
      freshness: result.freshness,
      acquisitionSources: result.acquisitionSources,
      identityStatuses: result.identityStatuses,
      warnings: result.warnings,
      items: filteredItems
    )
    OutputRenderer.printGTDQueryResult(filteredResult, format: runtime.outputFormat)
  }

  private static func createChild(
    parentManagedID: String,
    title: String,
    notes: String?,
    dueDate: Date?,
    priority: ReminderPriority,
    tags: [String],
    failurePrefix: String
  ) throws -> String {
    let childManagedID = CanonicalNoteFooter.generateCanonicalManagedID()
    let child = ShortcutHierarchyChildDraft(
      managedID: childManagedID,
      title: title,
      notes: notes,
      dueAt: ProjectWorkflow.isoString(from: dueDate),
      priority: priority == .none ? nil : priority
    )
    let request = ShortcutHierarchyMutationRequest(
      operation: .createChild(parentManagedID: parentManagedID, child: child)
    )

    do {
      _ = try ShortcutHierarchyMutation.apply(request)
    } catch {
      throw RemindCoreError.operationFailed("\(failurePrefix) \(error.localizedDescription)")
    }

    do {
      try ShortcutTagMutation.apply(.set(tags), to: ReminderMutationTarget(reminderID: childManagedID, canonicalManagedID: childManagedID))
    } catch {
      throw RemindCoreError.operationFailed("\(failurePrefix) Child was created, but tag mutation failed. \(error.localizedDescription)")
    }
    return childManagedID
  }

  private static func mutationTarget(for input: String, store: RemindersStore) async throws -> ReminderMutationTarget {
    let reminders = try await store.reminders(in: nil)
    let resolved = try IDResolver.resolve([input], from: reminders)
    guard let reminder = resolved.first else {
      throw RemindCoreError.reminderNotFound(input)
    }
    return try await store.mutationTarget(forReminderID: reminder.id)
  }

  private static func resolveTargetList(_ listName: String?, store: RemindersStore) async throws -> String {
    if let listName {
      return listName
    }
    guard let defaultList = await store.defaultListName() else {
      throw RemindCoreError.operationFailed("No default list found. Specify --list.")
    }
    return defaultList
  }

  private static func requiredArgument(_ values: ParsedValues, index: Int, name: String) throws -> String {
    guard let value = values.argument(index)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      throw ParsedValuesError.missingArgument(name)
    }
    return value
  }

  private static func printChildResult(title: String, managedID: String, format: OutputFormat) {
    switch format {
    case .standard:
      Swift.print("✓ \(title) child=\(managedID)")
    case .plain:
      Swift.print("\(managedID)\t\(title)")
    case .json:
      OutputRenderer.printProjectMutation(
        ProjectMutationSummary(operation: "create_child", parentManagedID: nil, childManagedID: managedID),
        format: .json
      )
    case .quiet:
      break
    }
  }
}

struct ProjectMutationSummary: Codable, Sendable, Equatable {
  let operation: String
  let parentManagedID: String?
  let childManagedID: String

  private enum CodingKeys: String, CodingKey {
    case operation
    case parentManagedID = "parent_managed_id"
    case childManagedID = "child_managed_id"
  }
}

private extension Optional {
  func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
    guard let value = self else { throw error() }
    return value
  }
}
