import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

struct ShortcutTagMutationTests {
  private let target = ReminderMutationTarget(
    reminderID: "abc123",
    canonicalManagedID: "550e8400-e29b-41d4-a716-446655440000"
  )

  @Test("Encode set-tag mutation request")
  func encodeSetTagMutationRequest() throws {
    let request = ShortcutTagMutationRequest(
      targetManagedID: "550e8400-e29b-41d4-a716-446655440000",
      operation: .set(["active-project", "area-work"])
    )
    let rawRequest = try ShortcutTagMutation.encodeRequest(request)
    let object = try JSONSerialization.jsonObject(with: Data(rawRequest.utf8)) as? [String: Any]

    #expect(object?["schema_version"] as? Int == 1)
    #expect(object?["managed_id"] as? String == "550e8400-e29b-41d4-a716-446655440000")
    #expect(object?["operation"] as? String == "set")
    #expect(object?["tags"] as? [String] == ["active-project", "area-work"])
  }

  @Test("Build shortcuts run invocation for tag mutation")
  func buildShortcutsInvocation() {
    let args = ShortcutTagMutation.shortcutsArguments(outputPath: "/workspace/output.txt")

    #expect(
      args == [
        "run",
        "remindctl - Mutate Tags",
        "--output-path",
        "/workspace/output.txt",
      ]
    )
  }

  @Test("Decode tag mutation response in snake case")
  func decodeSnakeCaseResponse() throws {
    let response = try ShortcutTagMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "add",
        "managed_id": "550e8400-e29b-41d4-a716-446655440000",
        "resolved_reminder_count": 1,
        "applied_tags": ["active-project", "area-work"]
      }
      """
    )

    #expect(response.success)
    #expect(response.operation == .add)
    #expect(response.managedID == "550e8400-e29b-41d4-a716-446655440000")
    #expect(response.resolvedReminderCount == 1)
    #expect(response.appliedTags == ["active-project", "area-work"])
  }

  @Test("Apply tag mutation request allows clear operations without tags")
  func encodeClearRequestWithoutTags() throws {
    let request = ShortcutTagMutationRequest(
      targetManagedID: "550e8400-e29b-41d4-a716-446655440000",
      operation: .clear
    )
    let rawRequest = try ShortcutTagMutation.encodeRequest(request)
    let object = try JSONSerialization.jsonObject(with: Data(rawRequest.utf8)) as? [String: Any]

    #expect(object?["operation"] as? String == "clear")
    #expect(object?["tags"] == nil)
  }

  @Test("Decode tag mutation response tolerates empty optional values and newline tags")
  func decodeResponseToleratesShortcutTextValues() throws {
    let response = try ShortcutTagMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "set",
        "managed_id": "",
        "resolved_reminder_count": "",
        "applied_tags": "example-tag\\\\nsecond-tag",
        "error_message": ""
      }
      """
    )

    #expect(response.success)
    #expect(response.operation == .set)
    #expect(response.managedID == nil)
    #expect(response.resolvedReminderCount == nil)
    #expect(response.appliedTags == ["example-tag", "second-tag"])
    #expect(response.errorMessage == nil)
  }

  @Test("Successful mutation response requires exactly one resolved reminder")
  func successRequiresSingleResolvedReminder() throws {
    let request = ShortcutTagMutationRequest(targetManagedID: target.canonicalManagedID, operation: .set(["active-project"]))

    let zeroResponse = try ShortcutTagMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "set",
        "managed_id": "550e8400-e29b-41d4-a716-446655440000",
        "resolved_reminder_count": 0
      }
      """
    )
    #expect(throws: Error.self) {
      try ShortcutTagMutation.validateSuccessfulResponse(zeroResponse, for: request)
    }

    let duplicateResponse = try ShortcutTagMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "set",
        "managed_id": "550e8400-e29b-41d4-a716-446655440000",
        "resolved_reminder_count": 2
      }
      """
    )
    #expect(throws: Error.self) {
      try ShortcutTagMutation.validateSuccessfulResponse(duplicateResponse, for: request)
    }
  }

  @Test("Successful mutation response rejects mismatched managed id")
  func successRejectsMismatchedManagedID() throws {
    let request = ShortcutTagMutationRequest(targetManagedID: target.canonicalManagedID, operation: .set(["active-project"]))
    let response = try ShortcutTagMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "set",
        "managed_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "resolved_reminder_count": 1
      }
      """
    )

    #expect(throws: Error.self) {
      try ShortcutTagMutation.validateSuccessfulResponse(response, for: request)
    }
  }

  @Test("Successful mutation response rejects mismatched operation")
  func successRejectsMismatchedOperation() throws {
    let request = ShortcutTagMutationRequest(targetManagedID: target.canonicalManagedID, operation: .set(["active-project"]))
    let response = try ShortcutTagMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "add",
        "managed_id": "550e8400-e29b-41d4-a716-446655440000",
        "resolved_reminder_count": 1
      }
      """
    )

    #expect(throws: Error.self) {
      try ShortcutTagMutation.validateSuccessfulResponse(response, for: request)
    }
  }

  @Test("Successful mutation response accepts a matching success payload")
  func successAcceptsMatchingResponse() throws {
    let request = ShortcutTagMutationRequest(targetManagedID: target.canonicalManagedID, operation: .add(["active-project"]))
    let response = try ShortcutTagMutation.decodeResponse(
      from: """
      {
        "success": true,
        "operation": "add",
        "managed_id": "550e8400-e29b-41d4-a716-446655440000",
        "resolved_reminder_count": 1,
        "applied_tags": ["active-project"]
      }
      """
    )

    try ShortcutTagMutation.validateSuccessfulResponse(response, for: request)
  }

  @Test("Mutation request helper preserves operation order for incremental edits")
  func mutationRequestsPreserveOperationOrder() {
    let requests = ShortcutTagMutation.requests(
      for: [
        .add(["waiting-on", "blocked"]),
        .remove(["next-action"]),
        .clear,
      ],
      to: target
    )

    #expect(requests.map(\.operation) == [.add, .remove, .clear])
    #expect(requests[0].tags == ["waiting-on", "blocked"])
    #expect(requests[1].tags == ["next-action"])
    #expect(requests[2].tags == nil)
    #expect(requests.allSatisfy { $0.managedID == target.canonicalManagedID })
  }

  @Test("Shortcut names stay aligned with the documented integration surface")
  func documentedShortcutNames() {
    #expect(ShortcutTagMutation.shortcutName == "remindctl - Mutate Tags")
    #expect(ShortcutTagSearch.shortcutName == "remindctl - Search By Tag")
  }

  @Test("Mutation target keeps the native reminder and canonical managed IDs")
  func mutationTargetCarriesIdentifiers() {
    let target = ReminderMutationTarget(
      reminderID: "abc123",
      canonicalManagedID: "550e8400-e29b-41d4-a716-446655440000"
    )

    #expect(target.reminderID == "abc123")
    #expect(target.canonicalManagedID == "550e8400-e29b-41d4-a716-446655440000")
  }
}
