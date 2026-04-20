import Foundation
import Testing

@testable import remindctl

struct ShortcutHierarchyMutationTests {
  private let parentID = "11111111-1111-4111-8111-111111111111"
  private let childID = "22222222-2222-4222-8222-222222222222"

  @Test("Encode create-child hierarchy mutation request")
  func encodeCreateChildRequest() throws {
    let request = ShortcutHierarchyMutationRequest(
      operation: .createChild(
        parentManagedID: parentID,
        child: ShortcutHierarchyChildDraft(
          managedID: childID,
          title: "Draft proposal outline",
          notes: "Use project notes as context"
        )
      )
    )

    let rawRequest = try ShortcutHierarchyMutation.encodeRequest(request)
    let object = try JSONSerialization.jsonObject(with: Data(rawRequest.utf8)) as? [String: Any]
    let child = object?["child"] as? [String: Any]

    #expect(object?["schema_version"] as? Int == 1)
    #expect(object?["operation"] as? String == "create_child")
    #expect(object?["parent_managed_id"] as? String == parentID)
    #expect(object?["child_managed_id"] == nil)
    #expect(child?["managed_id"] as? String == childID)
    #expect(child?["title"] as? String == "Draft proposal outline")
    #expect(child?["notes"] as? String == "Use project notes as context")
    #expect(child?["due_at"] == nil)
    #expect(child?["priority"] == nil)
  }

  @Test("Encode attach-existing hierarchy mutation request")
  func encodeAttachExistingRequest() throws {
    let request = ShortcutHierarchyMutationRequest(
      operation: .attachExisting(parentManagedID: parentID, childManagedID: childID)
    )

    let rawRequest = try ShortcutHierarchyMutation.encodeRequest(request)
    let object = try JSONSerialization.jsonObject(with: Data(rawRequest.utf8)) as? [String: Any]

    #expect(object?["schema_version"] as? Int == 1)
    #expect(object?["operation"] as? String == "attach_existing")
    #expect(object?["parent_managed_id"] as? String == parentID)
    #expect(object?["child_managed_id"] as? String == childID)
    #expect(object?["child"] == nil)
  }

  @Test("Decode hierarchy mutation response in snake case")
  func decodeResponse() throws {
    let response = try ShortcutHierarchyMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "create_child",
        "parent_managed_id": "\(parentID)",
        "child_managed_id": "\(childID)",
        "resolved_parent_count": 1,
        "resolved_child_count": 1,
        "child_is_subtask": true
      }
      """
    )

    #expect(response.success)
    #expect(response.operation == .createChild)
    #expect(response.parentManagedID == parentID)
    #expect(response.childManagedID == childID)
    #expect(response.resolvedParentCount == 1)
    #expect(response.resolvedChildCount == 1)
    #expect(response.childIsSubtask == true)
  }

  @Test("Successful hierarchy mutation response requires exact success invariants")
  func successRequiresCountsAndSubtaskConfirmation() throws {
    let request = ShortcutHierarchyMutationRequest(
      operation: .attachExisting(parentManagedID: parentID, childManagedID: childID)
    )

    let badParentCount = try ShortcutHierarchyMutation.decodeResponse(
      from: successPayload(parentCount: 0, childCount: 1, childIsSubtask: true)
    )
    #expect(throws: Error.self) {
      try ShortcutHierarchyMutation.validateSuccessfulResponse(badParentCount, for: request)
    }

    let badChildCount = try ShortcutHierarchyMutation.decodeResponse(
      from: successPayload(parentCount: 1, childCount: 2, childIsSubtask: true)
    )
    #expect(throws: Error.self) {
      try ShortcutHierarchyMutation.validateSuccessfulResponse(badChildCount, for: request)
    }

    let notSubtask = try ShortcutHierarchyMutation.decodeResponse(
      from: successPayload(parentCount: 1, childCount: 1, childIsSubtask: false)
    )
    #expect(throws: Error.self) {
      try ShortcutHierarchyMutation.validateSuccessfulResponse(notSubtask, for: request)
    }
  }

  @Test("Successful hierarchy mutation response rejects mismatched echoes")
  func successRejectsMismatchedEchoes() throws {
    let request = ShortcutHierarchyMutationRequest(
      operation: .attachExisting(parentManagedID: parentID, childManagedID: childID)
    )

    let wrongOperation = try ShortcutHierarchyMutation.decodeResponse(
      from: successPayload(operation: "create_child", parentID: parentID, childID: childID)
    )
    #expect(throws: Error.self) {
      try ShortcutHierarchyMutation.validateSuccessfulResponse(wrongOperation, for: request)
    }

    let wrongParent = try ShortcutHierarchyMutation.decodeResponse(
      from: successPayload(operation: "attach_existing", parentID: childID, childID: childID)
    )
    #expect(throws: Error.self) {
      try ShortcutHierarchyMutation.validateSuccessfulResponse(wrongParent, for: request)
    }

    let wrongChild = try ShortcutHierarchyMutation.decodeResponse(
      from: successPayload(operation: "attach_existing", parentID: parentID, childID: parentID)
    )
    #expect(throws: Error.self) {
      try ShortcutHierarchyMutation.validateSuccessfulResponse(wrongChild, for: request)
    }
  }

  @Test("Successful hierarchy mutation response accepts matching payload")
  func successAcceptsMatchingPayload() throws {
    let request = ShortcutHierarchyMutationRequest(
      operation: .attachExisting(parentManagedID: parentID, childManagedID: childID)
    )
    let response = try ShortcutHierarchyMutation.decodeResponse(
      from: successPayload(operation: "attach_existing", parentID: parentID, childID: childID)
    )

    try ShortcutHierarchyMutation.validateSuccessfulResponse(response, for: request)
  }

  @Test("Build shortcuts run invocation for hierarchy mutation")
  func buildShortcutsInvocation() {
    let args = ShortcutHierarchyMutation.shortcutsArguments(outputPath: "/workspace/output.txt")

    #expect(
      args == [
        "run",
        "remindctl - Mutate Hierarchy",
        "--output-path",
        "/workspace/output.txt",
      ]
    )
  }

  private func successPayload(
    operation: String = "attach_existing",
    parentID: String? = nil,
    childID: String? = nil,
    parentCount: Int = 1,
    childCount: Int = 1,
    childIsSubtask: Bool = true
  ) -> String {
    """
    {
      "success": true,
      "operation": "\(operation)",
      "parent_managed_id": "\(parentID ?? self.parentID)",
      "child_managed_id": "\(childID ?? self.childID)",
      "resolved_parent_count": \(parentCount),
      "resolved_child_count": \(childCount),
      "child_is_subtask": \(childIsSubtask)
    }
    """
  }
}
