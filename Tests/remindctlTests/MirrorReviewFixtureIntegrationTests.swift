import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

struct MirrorReviewFixtureIntegrationTests {
  @Test("Project health and weekly review read fixture-backed mirror JSON")
  func projectHealthAndWeeklyReviewReadFixtureBackedMirrorJSON() async throws {
    let mirrorURL = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: mirrorURL) }

    let runner = ShortcutContractRunner()
    let payloads = try ShortcutContractID.requiredV1Contracts.map {
      try runner.loadFixture(contractID: $0, directoryURL: fixturesURL)
    }
    let nativeReminders = payloads.flatMap(\.items).map(nativeReminder)
    let store = try GTDMirrorStore(databaseURL: mirrorURL)
    _ = try await store.setValidationGate(.g1TagVisibility, state: .passed)
    _ = try await store.setValidationGate(.g2HierarchyVisibility, state: .passed)
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .passed)
    _ = try await store.replaceSnapshot(
      nativeReminders: nativeReminders,
      shortcutPayloads: payloads,
      completedAt: Date(timeIntervalSince1970: 1_742_472_000),
      allowCanonicalPromotion: true
    )

    let healthResult = try await ShortcutLiveTestSupport.runRemindctl([
      "project",
      "health",
      "--mirror",
      mirrorURL.path,
      "--area",
      "work",
      "--json",
      "--no-input",
    ])
    try requireSuccess(healthResult, context: "project health")
    let health = try jsonObject(healthResult.stdout)
    let projects = try #require(health["projects"] as? [[String: Any]])
    #expect(projects.contains(where: { $0["title"] as? String == "Launch billing cleanup" }))

    let reviewResult = try await ShortcutLiveTestSupport.runRemindctl([
      "review",
      "weekly",
      "--mirror",
      mirrorURL.path,
      "--area",
      "work",
      "--json",
      "--no-input",
    ])
    try requireSuccess(reviewResult, context: "review weekly")
    let review = try jsonObject(reviewResult.stdout)
    let nextActions = try #require(review["next_actions"] as? [[String: Any]])
    let waitingOns = try #require(review["waiting_ons"] as? [[String: Any]])
    #expect(nextActions.contains(where: { $0["title"] as? String == "Reply to finance" }))
    #expect(waitingOns.contains(where: { $0["title"] as? String == "Waiting on supplier quote" }))
  }

  private var fixturesURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Support/Shortcuts/fixtures")
  }

  private func nativeReminder(from item: ShortcutContractItem) -> NativeReminderRecord {
    NativeReminderRecord(
      id: item.nativeCalendarItemIdentifier ?? item.sourceItemID,
      sourceScopeID: "fixture-source",
      calendarID: "fixture-calendar",
      listTitle: item.listTitle,
      title: item.title,
      noteFields: ManagedNoteFields(
        rawNotes: item.rawNotes,
        notesBody: item.notesBody,
        canonicalManagedID: item.canonicalManagedID,
        footerState: item.footerState
      ),
      isCompleted: item.isCompleted,
      completionDate: nil,
      priority: item.priority,
      dueDate: item.dueAt,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      url: item.url,
      nativeCalendarItemIdentifier: item.nativeCalendarItemIdentifier ?? item.sourceItemID,
      nativeExternalIdentifier: item.nativeExternalIdentifier ?? "fixture-\(item.sourceItemID)"
    )
  }

  private func jsonObject(_ rawJSON: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(rawJSON.utf8))
    return try #require(object as? [String: Any])
  }

  private func requireSuccess(_ result: CapturedCommandResult, context: String) throws {
    guard result.exitCode == 0 else {
      throw NSError(domain: "MirrorReviewFixtureIntegrationTests", code: 1, userInfo: [
        NSLocalizedDescriptionKey: """
        \(context) failed with exit code \(result.exitCode)
        stdout: \(result.stdout)
        stderr: \(result.stderr)
        """,
      ])
    }
  }

  private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "remindctl-review-fixture-tests-\(UUID().uuidString).sqlite3",
      isDirectory: false
    )
  }
}
