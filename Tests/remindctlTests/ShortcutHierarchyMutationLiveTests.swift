import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

@Suite(.serialized)
struct ShortcutHierarchyMutationLiveTests {
  @Test("Installed hierarchy shortcut rejects malformed input with structured JSON")
  func malformedInputReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    let response = try ShortcutLiveTestSupport.runHierarchyShortcutRaw(input: "not-json")

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed hierarchy shortcut rejects missing schema version")
  func missingSchemaVersionReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    let response = try ShortcutLiveTestSupport.runHierarchyShortcutRaw(
      input: #"{"operation":"attach_existing","parent_managed_id":"11111111-1111-4111-8111-111111111111","child_managed_id":"22222222-2222-4222-8222-222222222222"}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed hierarchy shortcut rejects wrong schema version")
  func wrongSchemaVersionReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    let response = try ShortcutLiveTestSupport.runHierarchyShortcutRaw(
      input: #"{"schema_version":2,"operation":"attach_existing","parent_managed_id":"11111111-1111-4111-8111-111111111111","child_managed_id":"22222222-2222-4222-8222-222222222222"}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed hierarchy shortcut rejects missing parent managed id")
  func missingParentManagedIDReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    let response = try ShortcutLiveTestSupport.runHierarchyShortcutRaw(
      input: #"{"schema_version":1,"operation":"attach_existing","child_managed_id":"22222222-2222-4222-8222-222222222222"}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed hierarchy shortcut rejects missing child for attach")
  func missingAttachChildReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    let response = try ShortcutLiveTestSupport.runHierarchyShortcutRaw(
      input: #"{"schema_version":1,"operation":"attach_existing","parent_managed_id":"11111111-1111-4111-8111-111111111111"}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed hierarchy shortcut rejects missing child object for create-child")
  func missingCreateChildObjectReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    let response = try ShortcutLiveTestSupport.runHierarchyShortcutRaw(
      input: #"{"schema_version":1,"operation":"create_child","parent_managed_id":"11111111-1111-4111-8111-111111111111"}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed hierarchy shortcut reports zero-match parent for create-child")
  func zeroMatchParentReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    let request = ShortcutHierarchyMutationRequest(
      operation: .createChild(
        parentManagedID: "11111111-1111-4111-8111-111111111111",
        child: ShortcutHierarchyChildDraft(
          managedID: "22222222-2222-4222-8222-222222222222",
          title: "Codex Missing Parent Child"
        )
      )
    )
    let response = try ShortcutLiveTestSupport.runHierarchyShortcut(request: request)

    #expect(response.success == false)
    #expect(response.resolvedParentCount == 0)
    #expect(response.errorMessage?.isEmpty == false)
  }

  @Test("Installed hierarchy shortcut creates a true child reminder")
  func createChildReturnsValidatedSuccessPayload() async throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Hierarchy Parent", tags: [])
      ]
    ) { fixtures in
      let parent = try #require(fixtures.first)
      let childManagedID = UUID().uuidString.lowercased()
      let request = ShortcutHierarchyMutationRequest(
        operation: .createChild(
          parentManagedID: parent.managedID,
          child: ShortcutHierarchyChildDraft(
            managedID: childManagedID,
            title: "Codex Live Hierarchy Child \(UUID().uuidString)",
            notes: "Created by live hierarchy test",
            priority: .low
          )
        )
      )
      let response = try ShortcutLiveTestSupport.runHierarchyShortcut(request: request)

      #expect(response.success)
      #expect(response.operation == .createChild)
      #expect(response.parentManagedID == parent.managedID)
      #expect(response.childManagedID == childManagedID)
      #expect(response.resolvedParentCount == 1)
      #expect(response.resolvedChildCount == 1)
      #expect(response.childIsSubtask == true)
      try ShortcutHierarchyMutation.validateSuccessfulResponse(response, for: request)
    }
  }

  @Test("Installed hierarchy shortcut attaches an existing reminder")
  func attachExistingReturnsValidatedSuccessPayload() async throws {
    guard Self.shouldRunLiveHierarchyTests else { return }

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Hierarchy Attach Parent", tags: []),
        ManagedReminderSeed(titlePrefix: "Codex Live Hierarchy Attach Child", tags: []),
      ]
    ) { fixtures in
      let parent = try #require(fixtures.first)
      let child = try #require(fixtures.dropFirst().first)
      let request = ShortcutHierarchyMutationRequest(
        operation: .attachExisting(parentManagedID: parent.managedID, childManagedID: child.managedID)
      )
      let response = try ShortcutLiveTestSupport.runHierarchyShortcut(request: request)

      #expect(response.success)
      #expect(response.operation == .attachExisting)
      #expect(response.parentManagedID == parent.managedID)
      #expect(response.childManagedID == child.managedID)
      #expect(response.resolvedParentCount == 1)
      #expect(response.resolvedChildCount == 1)
      #expect(response.childIsSubtask == true)
      try ShortcutHierarchyMutation.validateSuccessfulResponse(response, for: request)
    }
  }

  private static var shouldRunLiveHierarchyTests: Bool {
    ProcessInfo.processInfo.environment["REMINDCTL_RUN_LIVE_HIERARCHY_TESTS"] == "1"
  }
}
