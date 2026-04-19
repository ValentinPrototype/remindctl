import Foundation
import Testing

@testable import remindctl

@Suite(.serialized)
struct ShortcutTagSearchLiveTests {
  @Test("Installed search shortcut rejects malformed input with structured JSON")
  func malformedInputReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runSearchShortcutRaw(input: "not-json")

    #expect(response["success"] as? Bool == false)
    #expect(response["request"] as? String == "not-json")
    #expect((response["errorMessage"] as? String)?.isEmpty == false)
  }

  @Test("Installed search shortcut rejects empty tag arrays with structured JSON")
  func emptyTagArrayReturnsStructuredFailure() throws {
    guard Self.shouldRunLiveTests else { return }

    let response = try ShortcutLiveTestSupport.runSearchShortcutRaw(input: #"{"tags":[]}"#)

    #expect(response["success"] as? Bool == false)
    #expect(response["request"] as? String == #"{"tags":[]}"#)
    #expect((response["errorMessage"] as? String)?.isEmpty == false)
  }

  @Test("Installed search shortcut returns the reminder for a unique single-tag query")
  func uniqueSingleTagQueryReturnsExpectedReminder() async throws {
    guard Self.shouldRunLiveTests else { return }

    let uniqueTag = uniqueTag(prefix: "codex-live-search-single")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Search Single", tags: [uniqueTag])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)
      let payload = try ShortcutLiveTestSupport.runSearchShortcut(tags: [uniqueTag])

      #expect(payload.success)
      #expect(payload.count == payload.data.count)
      #expect(payload.data.contains(where: { $0.title == fixture.title && $0.tags.contains(uniqueTag) }))
    }
  }

  @Test("Installed search shortcut enforces AND semantics for repeated tags")
  func repeatedTagsUseAndSemantics() async throws {
    guard Self.shouldRunLiveTests else { return }

    let firstTag = uniqueTag(prefix: "codex-live-search-and-a")
    let secondTag = uniqueTag(prefix: "codex-live-search-and-b")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex Live Search Both", tags: [firstTag, secondTag]),
        ManagedReminderSeed(titlePrefix: "Codex Live Search First", tags: [firstTag]),
        ManagedReminderSeed(titlePrefix: "Codex Live Search Second", tags: [secondTag]),
      ]
    ) { fixtures in
      let bothFixture = fixtures[0]
      let firstOnlyFixture = fixtures[1]
      let secondOnlyFixture = fixtures[2]

      let payload = try ShortcutLiveTestSupport.runSearchShortcut(tags: [firstTag, secondTag])
      let titles = Set(payload.data.map(\.title))

      #expect(payload.success)
      #expect(payload.count == payload.data.count)
      #expect(titles.contains(bothFixture.title))
      #expect(titles.contains(firstOnlyFixture.title) == false)
      #expect(titles.contains(secondOnlyFixture.title) == false)
    }
  }

  private static var shouldRunLiveTests: Bool {
    ProcessInfo.processInfo.environment["REMINDCTL_RUN_LIVE_SHORTCUT_TESTS"] == "1"
  }

  private func uniqueTag(prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString.prefix(8))".lowercased()
  }
}
