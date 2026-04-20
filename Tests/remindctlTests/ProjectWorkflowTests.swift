import Foundation
import Testing

@testable import remindctl

struct ProjectWorkflowTests {
  @Test("Project area status context and energy tags normalize")
  func normalizeWorkflowTags() throws {
    #expect(try ProjectWorkflow.normalizeAreaTag("work") == "area-work")
    #expect(try ProjectWorkflow.normalizeAreaTag("#area-personal") == "area-personal")
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
}
