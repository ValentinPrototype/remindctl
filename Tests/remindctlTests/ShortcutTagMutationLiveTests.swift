import Foundation
import Testing

@testable import remindctl

@Suite(.serialized)
struct ShortcutTagMutationLiveTests {
  @Test("Installed mutate shortcut rejects malformed input with structured JSON")
  func malformedInputReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runMutationShortcutRaw(input: "not-json")

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed mutate shortcut rejects missing schema version")
  func missingSchemaVersionReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runMutationShortcutRaw(
      input: #"{"managed_id":"11111111-1111-1111-1111-111111111111","operation":"set","tags":["example-tag"]}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed mutate shortcut rejects wrong schema version")
  func wrongSchemaVersionReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runMutationShortcutRaw(
      input: #"{"schema_version":2,"managed_id":"11111111-1111-1111-1111-111111111111","operation":"set","tags":["example-tag"]}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed mutate shortcut rejects missing managed id")
  func missingManagedIDReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runMutationShortcutRaw(
      input: #"{"schema_version":1,"operation":"set","tags":["example-tag"]}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed mutate shortcut rejects missing operation")
  func missingOperationReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runMutationShortcutRaw(
      input: #"{"schema_version":1,"managed_id":"11111111-1111-1111-1111-111111111111","tags":["example-tag"]}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed mutate shortcut rejects missing tags for set")
  func missingTagsForSetReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runMutationShortcutRaw(
      input: #"{"schema_version":1,"managed_id":"11111111-1111-1111-1111-111111111111","operation":"set"}"#
    )

    #expect(response["success"] as? Bool == false)
    #expect((response["error_message"] as? String)?.isEmpty == false)
  }

  @Test("Installed mutate shortcut returns a matching success response for one reminder")
  func singleMatchReturnsValidatedSuccessPayload() async throws {
    guard Self.shouldRunLiveTests else { return }

    let firstTag = uniqueTag(prefix: "codex-live-mutate-a")
    let secondTag = uniqueTag(prefix: "codex-live-mutate-b")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Mutate Single", tags: [])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)
      let request = ShortcutTagMutationRequest(
        targetManagedID: fixture.managedID,
        operation: .set([firstTag, secondTag])
      )
      let response = try ShortcutLiveTestSupport.runMutationShortcut(request: request)
      let appliedTags = try #require(response.appliedTags)

      #expect(response.success)
      #expect(response.operation == .set)
      #expect(response.managedID == fixture.managedID)
      #expect(response.resolvedReminderCount == 1)
      #expect(appliedTags.count == 2)
      #expect(Set(appliedTags) == Set([firstTag, secondTag]))
    }
  }

  @Test("Installed mutate shortcut add operation keeps existing tags and appends new tags")
  func addOperationReturnsExpectedTagSet() async throws {
    guard Self.shouldRunLiveTests else { return }

    let originalTag = uniqueTag(prefix: "codex-live-add-original")
    let addedTag = uniqueTag(prefix: "codex-live-add-added")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Mutate Add", tags: [originalTag])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)
      let response = try ShortcutLiveTestSupport.runMutationShortcut(
        request: ShortcutTagMutationRequest(
          targetManagedID: fixture.managedID,
          operation: .add([addedTag])
        )
      )
      let appliedTags = try #require(response.appliedTags)

      #expect(response.success)
      #expect(response.operation == .add)
      #expect(response.managedID == fixture.managedID)
      #expect(response.resolvedReminderCount == 1)
      #expect(appliedTags.count == 2)
      #expect(Set(appliedTags) == Set([originalTag, addedTag]))

      let addedTagSearch = try ShortcutLiveTestSupport.runSearchShortcut(tags: [addedTag])
      #expect(addedTagSearch.data.contains(where: { $0.title == fixture.title }))
    }
  }

  @Test("Installed mutate shortcut remove operation removes only the requested tags")
  func removeOperationReturnsExpectedTagSet() async throws {
    guard Self.shouldRunLiveTests else { return }

    let keptTag = uniqueTag(prefix: "codex-live-remove-keep")
    let removedTag = uniqueTag(prefix: "codex-live-remove-drop")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Mutate Remove", tags: [keptTag, removedTag])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)
      let response = try ShortcutLiveTestSupport.runMutationShortcut(
        request: ShortcutTagMutationRequest(
          targetManagedID: fixture.managedID,
          operation: .remove([removedTag])
        )
      )
      let appliedTags = try #require(response.appliedTags)

      #expect(response.success)
      #expect(response.operation == .remove)
      #expect(response.managedID == fixture.managedID)
      #expect(response.resolvedReminderCount == 1)
      #expect(appliedTags.count == 1)
      #expect(appliedTags == [keptTag])

      let removedTagSearch = try ShortcutLiveTestSupport.runSearchShortcut(tags: [removedTag])
      #expect(removedTagSearch.data.contains(where: { $0.title == fixture.title }) == false)

      let keptTagSearch = try ShortcutLiveTestSupport.runSearchShortcut(tags: [keptTag])
      #expect(keptTagSearch.data.contains(where: { $0.title == fixture.title }))
    }
  }

  @Test("Installed mutate shortcut clear operation removes all tags")
  func clearOperationRemovesAllTags() async throws {
    guard Self.shouldRunLiveTests else { return }

    let firstTag = uniqueTag(prefix: "codex-live-clear-a")
    let secondTag = uniqueTag(prefix: "codex-live-clear-b")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Mutate Clear", tags: [firstTag, secondTag])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)
      let response = try ShortcutLiveTestSupport.runMutationShortcut(
        request: ShortcutTagMutationRequest(
          targetManagedID: fixture.managedID,
          operation: .clear
        )
      )

      #expect(response.success)
      #expect(response.operation == .clear)
      #expect(response.managedID == fixture.managedID)
      #expect(response.resolvedReminderCount == 1)
      #expect((response.appliedTags ?? []).isEmpty)

      let firstTagSearch = try ShortcutLiveTestSupport.runSearchShortcut(tags: [firstTag])
      #expect(firstTagSearch.data.contains(where: { $0.title == fixture.title }) == false)

      let secondTagSearch = try ShortcutLiveTestSupport.runSearchShortcut(tags: [secondTag])
      #expect(secondTagSearch.data.contains(where: { $0.title == fixture.title }) == false)
    }
  }

  @Test("Installed mutate shortcut fails duplicate reminder matches")
  func duplicateMatchReturnsCountTwo() async throws {
    guard Self.shouldRunLiveTests else { return }

    let tag = uniqueTag(prefix: "codex-live-mutate-dup")

    try await ShortcutLiveTestSupport.withDuplicateManagedReminders(
      reminderCount: 2,
      titlePrefix: "Codex Live Mutate Duplicate"
    ) { fixtures in
      let fixture = try #require(fixtures.first)
      let response = try ShortcutLiveTestSupport.runMutationShortcut(
        request: ShortcutTagMutationRequest(
          targetManagedID: fixture.managedID,
          operation: .set([tag])
        )
      )

      #expect(response.success == false)
      #expect(response.resolvedReminderCount == 2)
      #expect(response.errorMessage?.isEmpty == false)
    }
  }

  private static var shouldRunLiveTests: Bool {
    ProcessInfo.processInfo.environment["REMINDCTL_RUN_LIVE_SHORTCUT_TESTS"] == "1"
  }

  private func uniqueTag(prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString.prefix(8))".lowercased()
  }
}
