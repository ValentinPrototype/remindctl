import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

struct ProjectWorkflowTests {
  @Test("Project area status context and energy tags normalize")
  func normalizeWorkflowTags() throws {
    #expect(try ProjectWorkflow.normalizeAreaTag("work") == "area-work")
    #expect(try ProjectWorkflow.normalizeAreaTag("#area-personal") == "area-personal")
    #expect(ProjectWorkflow.areaTags(in: ["active-project", "area-custom", "next-action"]) == ["area-custom"])
    #expect(try ProjectWorkflow.normalizeContextTag("phone-call") == "c-phone-call")
    #expect(try ProjectWorkflow.normalizeContextTag("c-computer") == "c-computer")
    #expect(try ProjectWorkflow.normalizeEnergyTag("low") == "e-low")
    #expect(try ProjectWorkflow.normalizeEnergyTag("e-high") == "e-high")
  }

  @Test("Someday status maps to the documented slash tag")
  func somedayStatusTag() throws {
    let status = try ProjectWorkflow.parseStatus("someday")

    #expect(status == .someday)
    #expect(ProjectWorkflow.projectTags(areaTag: "area-work", status: status) == ["someday/maybe", "area-work"])
    #expect(try ShortcutTagSearch.normalizeTag("someday/maybe") == "someday/maybe")
  }

  @Test("Project child tags inherit area and add workflow tags only")
  func childTags() throws {
    let nextActionTags = try ProjectWorkflow.childTags(
      areaTag: "area-work",
      kind: .nextAction,
      context: "computer",
      energy: "low",
      dueDate: nil
    )

    #expect(nextActionTags == ["area-work", "next-action", "c-computer", "e-low"])

    let plainTaskTags = try ProjectWorkflow.childTags(
      areaTag: "area-work",
      kind: .task,
      context: nil,
      energy: nil,
      dueDate: nil
    )
    #expect(plainTaskTags == ["area-work"])
  }

  @Test("Scheduled project steps require due date")
  func scheduledRequiresDueDate() {
    #expect(throws: Error.self) {
      try ProjectWorkflow.childTags(
        areaTag: "area-work",
        kind: .scheduled,
        context: nil,
        energy: nil,
        dueDate: nil
      )
    }
  }

  @Test("Project command is registered")
  func projectCommandIsRegistered() {
    let router = CommandRouter()

    #expect(router.specs.contains(where: { $0.name == "project" }))
  }

  @Test("Project create command parses GTD project options")
  func projectCreateCommandParsesOptions() throws {
    let invocation = try CommandRouter().program.resolve(
      argv: [
        "remindctl",
        "project",
        "create",
        "Ship v1",
        "--area",
        "work",
        "--status",
        "active",
        "--step",
        "Draft release notes",
        "--step",
        "Publish build",
        "--json",
      ]
    )

    #expect(invocation.path == ["remindctl", "project"])
    #expect(invocation.parsedValues.positional == ["create", "Ship v1"])
    #expect(invocation.parsedValues.option("area") == "work")
    #expect(invocation.parsedValues.option("status") == "active")
    #expect(invocation.parsedValues.optionValues("step") == ["Draft release notes", "Publish build"])
    #expect(invocation.parsedValues.flag("jsonOutput"))
  }

  @Test("Project add-step command parses workflow tags")
  func projectAddStepCommandParsesOptions() throws {
    let invocation = try CommandRouter().program.resolve(
      argv: [
        "remindctl",
        "project",
        "add-step",
        "A1B2",
        "Email supplier",
        "--kind",
        "next-action",
        "--context",
        "messenger",
        "--energy",
        "low",
        "--due",
        "tomorrow",
      ]
    )

    #expect(invocation.parsedValues.positional == ["add-step", "A1B2", "Email supplier"])
    #expect(invocation.parsedValues.option("kind") == "next-action")
    #expect(invocation.parsedValues.option("context") == "messenger")
    #expect(invocation.parsedValues.option("energy") == "low")
    #expect(invocation.parsedValues.option("due") == "tomorrow")
  }

  @Test("Project health command parses area and output options")
  func projectHealthCommandParsesOptions() throws {
    let invocation = try CommandRouter().program.resolve(
      argv: [
        "remindctl",
        "project",
        "health",
        "--sync",
        "--area",
        "work",
        "--json",
      ]
    )

    #expect(invocation.parsedValues.positional == ["health"])
    #expect(invocation.parsedValues.option("area") == "work")
    #expect(invocation.parsedValues.flag("sync"))
    #expect(invocation.parsedValues.flag("jsonOutput"))
  }

  @Test("Sync gtd command parses")
  func syncGTDCommandParses() throws {
    let invocation = try CommandRouter().program.resolve(
      argv: [
        "remindctl",
        "sync",
        "--gtd",
        "--mirror",
        "/tmp/remindctl-test.sqlite3",
        "--json",
      ]
    )

    #expect(invocation.path == ["remindctl", "sync"])
    #expect(invocation.parsedValues.flag("gtd"))
    #expect(invocation.parsedValues.option("mirror") == "/tmp/remindctl-test.sqlite3")
    #expect(invocation.parsedValues.flag("jsonOutput"))
  }

  @Test("Review weekly command parses")
  func reviewWeeklyCommandParses() throws {
    let invocation = try CommandRouter().program.resolve(
      argv: [
        "remindctl",
        "review",
        "weekly",
        "--sync",
        "--area",
        "work",
        "--older-than-days",
        "14",
        "--waiting-on-days",
        "7",
        "--json",
      ]
    )

    #expect(invocation.path == ["remindctl", "review"])
    #expect(invocation.parsedValues.positional == ["weekly"])
    #expect(invocation.parsedValues.flag("sync"))
    #expect(invocation.parsedValues.option("area") == "work")
    #expect(invocation.parsedValues.option("olderThanDays") == "14")
    #expect(invocation.parsedValues.option("waitingOnDays") == "7")
    #expect(invocation.parsedValues.flag("jsonOutput"))
  }

  @Test("Project health marks projects with next actions as healthy")
  func projectHealthMarksHealthyProjects() {
    let project = shortcutReminder(
      title: "Ship v1",
      tags: ["active-project", "area-work"],
      subTasks: ["Draft release notes"]
    )
    let child = shortcutReminder(
      title: "Draft release notes",
      tags: ["area-work", "next-action"],
      parent: "Ship v1"
    )

    let summary = ProjectHealth.evaluate(
      source: "test",
      projects: [ProjectHealthInput(project: project, areaTags: ["area-work"], children: [child])]
    )

    #expect(summary.projectCount == 1)
    #expect(summary.healthyCount == 1)
    #expect(summary.projects.first?.status == .healthy)
    #expect(summary.projects.first?.issues == [])
    #expect(summary.projects.first?.nextActionCount == 1)
  }

  @Test("Project health flags projects with no open children")
  func projectHealthFlagsNoOpenChildren() {
    let project = shortcutReminder(
      title: "Empty project",
      tags: ["active-project", "area-work"]
    )

    let summary = ProjectHealth.evaluate(
      source: "test",
      projects: [ProjectHealthInput(project: project, areaTags: ["area-work"], children: [])]
    )

    let health = summary.projects.first
    #expect(health?.status == .needsNextAction)
    #expect(health?.issues.contains(.noOpenChildren) == true)
    #expect(health?.issues.contains(.missingNextAction) == true)
  }

  @Test("Project health flags unresolved child details")
  func projectHealthFlagsUnresolvedChildDetails() {
    let project = shortcutReminder(
      title: "Partially visible project",
      tags: ["active-project", "area-work"],
      subTasks: ["Invisible child"]
    )

    let summary = ProjectHealth.evaluate(
      source: "test",
      projects: [ProjectHealthInput(project: project, areaTags: ["area-work"], children: [])]
    )

    let health = summary.projects.first
    #expect(health?.childCount == 1)
    #expect(health?.resolvedChildCount == 0)
    #expect(health?.unresolvedChildTitles == ["Invisible child"])
    #expect(health?.issues.contains(.unresolvedChildDetails) == true)
  }

  @Test("Project health flags unclassified children")
  func projectHealthFlagsUnclassifiedChildren() {
    let project = shortcutReminder(
      title: "Ambiguous project",
      tags: ["active-project", "area-work"],
      subTasks: ["Think about launch"]
    )
    let child = shortcutReminder(
      title: "Think about launch",
      tags: ["area-work"],
      parent: "Ambiguous project"
    )

    let summary = ProjectHealth.evaluate(
      source: "test",
      projects: [ProjectHealthInput(project: project, areaTags: ["area-work"], children: [child])]
    )

    let health = summary.projects.first
    #expect(health?.unclassifiedChildCount == 1)
    #expect(health?.issues.contains(.unclassifiedChildren) == true)
    #expect(health?.issues.contains(.missingNextAction) == true)
  }

  private func shortcutReminder(
    title: String,
    tags: [String],
    subTasks: [String] = [],
    parent: String? = nil,
    isCompleted: Bool = false
  ) -> ProjectHealthReminder {
    ProjectHealthReminder(
      id: UUID().uuidString,
      sourceItemID: UUID().uuidString,
      canonicalID: UUID().uuidString,
      managedID: UUID().uuidString,
      title: title,
      listName: "Projects",
      isCompleted: isCompleted,
      priority: .none,
      dueAt: nil,
      createdAt: nil,
      updatedAt: nil,
      tags: tags,
      childTitles: subTasks
    )
  }
}
