import Foundation
import Testing

@testable import remindctl

@Suite(.serialized)
struct RemindctlTagMutationE2ETests {
  @Test("Setting a tag makes the reminder discoverable through remindctl")
  func settingSingleTag() async throws {
    guard Self.shouldRunReminderE2ETests else { return }

    let tag = uniqueTag(prefix: "codex-e2e-single")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex E2E Single", tags: [])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)

      let editResult = try await ShortcutLiveTestSupport.runRemindctl([
        "edit",
        fixture.reminder.id,
        "--set-tag",
        tag,
        "--json",
        "--no-input",
      ])
      #expect(editResult.exitCode == 0)

      let matches = try await showTag(tag)
      let matchingReminders = matches.filter { $0.title == fixture.title }
      let matchedReminder = try #require(matchingReminders.first)
      #expect(matchingReminders.count == 1)
      #expect(matchedReminder.tags == [tag])
    }
  }

  @Test("Setting a tag when another tag already exists replaces the previous tag set")
  func settingTagWhenAnotherExistsReplacesPreviousTags() async throws {
    guard Self.shouldRunReminderE2ETests else { return }

    let originalTag = uniqueTag(prefix: "codex-e2e-original")
    let additionalTag = uniqueTag(prefix: "codex-e2e-additional")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex E2E Additive", tags: [originalTag])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)

      let editResult = try await ShortcutLiveTestSupport.runRemindctl([
        "edit",
        fixture.reminder.id,
        "--set-tag",
        additionalTag,
        "--json",
        "--no-input",
      ])
      #expect(editResult.exitCode == 0)

      let additionalMatches = try await showTag(additionalTag)
      let additionalMatchingReminders = additionalMatches.filter { $0.title == fixture.title }
      let additionalReminder = try #require(additionalMatchingReminders.first)
      #expect(additionalMatchingReminders.count == 1)
      #expect(additionalReminder.tags == [additionalTag])
      #expect(additionalReminder.tags.filter { $0 == additionalTag }.count == 1)

      let originalMatches = try await showTag(originalTag)
      let originalMatchingReminders = originalMatches.filter { $0.title == fixture.title }
      #expect(originalMatchingReminders.isEmpty)
    }
  }

  @Test("Running the same set-tag edit repeatedly stays idempotent")
  func settingSameTagRepeatedly() async throws {
    guard Self.shouldRunReminderE2ETests else { return }

    let tag = uniqueTag(prefix: "codex-e2e-repeat")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex E2E Repeat", tags: [])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)

      for _ in 0..<3 {
        let editResult = try await ShortcutLiveTestSupport.runRemindctl([
          "edit",
          fixture.reminder.id,
          "--set-tag",
          tag,
          "--json",
          "--no-input",
        ])
        #expect(editResult.exitCode == 0)
      }

      let matches = try await showTag(tag)
      let matchingReminders = matches.filter { $0.title == fixture.title }
      let matchedReminder = try #require(matchingReminders.first)
      #expect(matchingReminders.count == 1)
      #expect(matchedReminder.tags == [tag])
    }
  }

  @Test("Clearing tags removes discoverability for previously added tags")
  func clearingTagsRemovesDiscoverability() async throws {
    guard Self.shouldRunReminderE2ETests else { return }

    let tag = uniqueTag(prefix: "codex-e2e-clear")

    try await ShortcutLiveTestSupport.withManagedReminders(
      seeds: [
        ManagedReminderSeed(titlePrefix: "Codex E2E Clear", tags: [tag])
      ]
    ) { fixtures in
      let fixture = try #require(fixtures.first)

      let matchesBeforeClear = try await showTag(tag)
      #expect(matchesBeforeClear.filter { $0.title == fixture.title }.count == 1)

      let clearResult = try await ShortcutLiveTestSupport.runRemindctl([
        "edit",
        fixture.reminder.id,
        "--clear-tags",
        "--json",
        "--no-input",
      ])
      #expect(clearResult.exitCode == 0)

      let matchesAfterClear = try await showTag(tag)
      #expect(matchesAfterClear.contains(where: { $0.title == fixture.title }) == false)
    }
  }

  private static var shouldRunReminderE2ETests: Bool {
    ProcessInfo.processInfo.environment["REMINDCTL_RUN_REMINDER_E2E_TESTS"] == "1"
  }

  private func showTag(_ tag: String) async throws -> [EncodedShortcutTagReminder] {
    let result = try await ShortcutLiveTestSupport.runRemindctl([
      "show",
      "--tag",
      tag,
      "--json",
      "--no-input",
    ])
    #expect(result.exitCode == 0)
    let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
    guard let items = object as? [[String: Any]] else {
      throw NSError(domain: "RemindctlTagMutationE2ETests", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Unexpected remindctl JSON output: \(result.stdout)",
      ])
    }

    return items.compactMap(EncodedShortcutTagReminder.init)
  }

  private func uniqueTag(prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString.prefix(8))".lowercased()
  }
}

private struct EncodedShortcutTagReminder {
  let title: String
  let tags: [String]

  init?(json: [String: Any]) {
    guard let title = json["title"] as? String else {
      return nil
    }
    self.title = title
    self.tags = json["tags"] as? [String] ?? []
  }
}
