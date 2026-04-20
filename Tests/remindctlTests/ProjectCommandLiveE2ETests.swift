import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

@Suite(.serialized)
struct ProjectCommandLiveE2ETests {
  @Test("Project create with an initial step creates tagged project and child reminders")
  func createProjectWithInitialStep() async throws {
    guard Self.shouldRunProjectE2ETests else { return }

    let runID = UUID().uuidString
    let projectTitle = "Codex Project Create \(runID)"
    let stepTitle = "Codex Project Initial Step \(runID)"

    try await withCleanup(titleFragments: [projectTitle, stepTitle]) { cleanup in
      let createResult = try await ShortcutLiveTestSupport.runRemindctl([
        "project",
        "create",
        projectTitle,
        "--area",
        "work",
        "--step",
        stepTitle,
        "--json",
        "--no-input",
      ])
      try requireSuccess(createResult, context: "project create")

      let project = try decodeReminderJSON(createResult.stdout)
      cleanup.ids.insert(project.id)

      let areaMatches = try await showTags(["area-work"])
      #expect(areaMatches.contains(where: { $0.title == projectTitle }))
      #expect(areaMatches.contains(where: { $0.title == stepTitle }))

      let activeProjectMatches = try await showTags(["active-project"])
      #expect(activeProjectMatches.contains(where: { $0.title == projectTitle }))
      #expect(activeProjectMatches.contains(where: { $0.title == stepTitle }) == false)
    }
  }

  @Test("Project add-step creates a scheduled child with metadata and hierarchy confirmation")
  func addScheduledProjectStep() async throws {
    guard Self.shouldRunProjectE2ETests else { return }

    let runID = UUID().uuidString
    let projectTitle = "Codex Project Add Step \(runID)"
    let stepTitle = "Codex Project Scheduled Step \(runID)"

    try await withCleanup(titleFragments: [projectTitle, stepTitle]) { cleanup in
      let createResult = try await ShortcutLiveTestSupport.runRemindctl([
        "project",
        "create",
        projectTitle,
        "--area",
        "work",
        "--json",
        "--no-input",
      ])
      try requireSuccess(createResult, context: "project create")

      let project = try decodeReminderJSON(createResult.stdout)
      cleanup.ids.insert(project.id)

      let addStepResult = try await ShortcutLiveTestSupport.runRemindctl([
        "project",
        "add-step",
        project.id,
        stepTitle,
        "--kind",
        "scheduled",
        "--due",
        "tomorrow",
        "--priority",
        "high",
        "--context",
        "messenger",
        "--energy",
        "low",
        "--notes",
        "Created by project E2E test",
        "--json",
        "--no-input",
      ])
      try requireSuccess(addStepResult, context: "project add-step")

      let mutation = try decodeProjectMutationJSON(addStepResult.stdout)
      #expect(mutation.operation == "create_child")
      #expect(mutation.childManagedID.isEmpty == false)
      #expect(mutation.resolvedParentCount == 1)
      #expect(mutation.resolvedChildCount == 1)
      #expect(mutation.childIsSubtask == true)

      let scheduledMatches = try await showTags(["area-work", "scheduled"])
      let step = try #require(scheduledMatches.first(where: { $0.title == stepTitle }))
      cleanup.ids.insert(step.id)
      #expect(step.priority == "high")
      #expect(step.dueAt != nil)
      #expect(step.tags.contains("area-work"))
      #expect(step.tags.contains("scheduled"))
      #expect(step.tags.contains("c-messenger"))
      #expect(step.tags.contains("e-low"))
    }
  }

  @Test("Project attach moves an inbox reminder under a project and inherits area tag")
  func attachExistingTaskToProject() async throws {
    guard Self.shouldRunProjectE2ETests else { return }

    let runID = UUID().uuidString
    let projectTitle = "Codex Project Attach \(runID)"
    let taskTitle = "Codex Project Attach Task \(runID)"

    try await withCleanup(titleFragments: [projectTitle, taskTitle]) { cleanup in
      let createProjectResult = try await ShortcutLiveTestSupport.runRemindctl([
        "project",
        "create",
        projectTitle,
        "--area",
        "work",
        "--json",
        "--no-input",
      ])
      try requireSuccess(createProjectResult, context: "project create")
      let project = try decodeReminderJSON(createProjectResult.stdout)
      cleanup.ids.insert(project.id)

      let addTaskResult = try await ShortcutLiveTestSupport.runRemindctl([
        "add",
        taskTitle,
        "--json",
        "--no-input",
      ])
      try requireSuccess(addTaskResult, context: "add task")
      let task = try decodeReminderJSON(addTaskResult.stdout)
      cleanup.ids.insert(task.id)

      let attachResult = try await ShortcutLiveTestSupport.runRemindctl([
        "project",
        "attach",
        task.id,
        "--to",
        project.id,
        "--json",
        "--no-input",
      ])
      try requireSuccess(attachResult, context: "project attach")

      let mutation = try decodeProjectMutationJSON(attachResult.stdout)
      #expect(mutation.operation == "attach_existing")
      #expect(mutation.resolvedParentCount == 1)
      #expect(mutation.resolvedChildCount == 1)
      #expect(mutation.childIsSubtask == true)

      let areaMatches = try await showTags(["area-work"])
      let attachedTask = try #require(areaMatches.first(where: { $0.title == taskTitle }))
      #expect(attachedTask.tags.contains("area-work"))
    }
  }

  private static var shouldRunProjectE2ETests: Bool {
    ProcessInfo.processInfo.environment["REMINDCTL_RUN_PROJECT_E2E_TESTS"] == "1"
  }

  private func withCleanup(
    titleFragments: [String],
    body: (ProjectE2ECleanup) async throws -> Void
  ) async throws {
    let cleanup = ProjectE2ECleanup(titleFragments: Set(titleFragments))
    do {
      try await body(cleanup)
    } catch {
      await deleteCreatedReminders(cleanup)
      throw error
    }
    await deleteCreatedReminders(cleanup)
  }

  private func deleteCreatedReminders(_ cleanup: ProjectE2ECleanup) async {
    let store = RemindersStore()
    guard (try? await store.requestAccess()) != nil else { return }

    var ids = cleanup.ids
    if let reminders = try? await store.reminders(in: nil) {
      for reminder in reminders where cleanup.titleFragments.contains(where: { reminder.title.contains($0) }) {
        ids.insert(reminder.id)
      }
    }
    if ids.isEmpty == false {
      _ = try? await store.deleteReminders(ids: Array(ids))
    }
  }

  private func showTags(_ tags: [String]) async throws -> [ProjectE2EReminder] {
    var args = ["show"]
    for tag in tags {
      args.append("--tag")
      args.append(tag)
    }
    args += ["--json", "--no-input"]

    let result = try await ShortcutLiveTestSupport.runRemindctl(args)
    try requireSuccess(result, context: "show --tag \(tags.joined(separator: ","))")

    let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
    guard let items = object as? [[String: Any]] else {
      throw testError("Unexpected show JSON output: \(result.stdout)")
    }
    return items.compactMap(ProjectE2EReminder.init)
  }

  private func decodeReminderJSON(_ rawJSON: String) throws -> ProjectE2ENativeReminder {
    let object = try JSONSerialization.jsonObject(with: Data(rawJSON.utf8))
    guard let dictionary = object as? [String: Any],
      let id = dictionary["id"] as? String,
      let title = dictionary["title"] as? String
    else {
      throw testError("Unexpected reminder JSON output: \(rawJSON)")
    }
    return ProjectE2ENativeReminder(id: id, title: title)
  }

  private func decodeProjectMutationJSON(_ rawJSON: String) throws -> ProjectE2EMutation {
    let object = try JSONSerialization.jsonObject(with: Data(rawJSON.utf8))
    guard let dictionary = object as? [String: Any],
      let operation = dictionary["operation"] as? String,
      let childManagedID = dictionary["child_managed_id"] as? String
    else {
      throw testError("Unexpected project mutation JSON output: \(rawJSON)")
    }
    return ProjectE2EMutation(
      operation: operation,
      childManagedID: childManagedID,
      resolvedParentCount: dictionary["resolved_parent_count"] as? Int,
      resolvedChildCount: dictionary["resolved_child_count"] as? Int,
      childIsSubtask: dictionary["child_is_subtask"] as? Bool
    )
  }

  private func requireSuccess(_ result: CapturedCommandResult, context: String) throws {
    guard result.exitCode == 0 else {
      throw testError(
        """
        \(context) failed with exit code \(result.exitCode)
        stdout: \(result.stdout)
        stderr: \(result.stderr)
        """
      )
    }
  }

  private func testError(_ message: String) -> NSError {
    NSError(domain: "ProjectCommandLiveE2ETests", code: 1, userInfo: [
      NSLocalizedDescriptionKey: message,
    ])
  }
}

private final class ProjectE2ECleanup {
  var ids: Set<String> = []
  let titleFragments: Set<String>

  init(titleFragments: Set<String>) {
    self.titleFragments = titleFragments
  }
}

private struct ProjectE2ENativeReminder {
  let id: String
  let title: String
}

private struct ProjectE2EMutation {
  let operation: String
  let childManagedID: String
  let resolvedParentCount: Int?
  let resolvedChildCount: Int?
  let childIsSubtask: Bool?
}

private struct ProjectE2EReminder {
  let id: String
  let title: String
  let priority: String
  let dueAt: String?
  let tags: [String]

  init?(json: [String: Any]) {
    guard let id = json["id"] as? String,
      let title = json["title"] as? String
    else {
      return nil
    }

    self.id = id
    self.title = title
    self.priority = (json["priority"] as? String)?.lowercased() ?? "none"
    self.dueAt = json["dueAt"] as? String
    self.tags = json["tags"] as? [String] ?? []
  }
}
