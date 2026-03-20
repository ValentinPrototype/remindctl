import Foundation
import Testing

@testable import RemindCore

struct GTDMirrorStoreTests {
  @Test("Semantic queries stay blocked until the tag gate passes")
  func semanticQueriesRequireTagGate() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)

    let result = try await store.querySemantic(contractID: .activeProjects, now: now)
    #expect(result.status == .unsupported)
    #expect(result.warnings.contains(where: { $0.contains("G1") }))
  }

  @Test("Mirror keeps unresolved semantic rows at low confidence")
  func unresolvedSemanticRowsStayLowConfidence() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)

    _ = try await store.setValidationGate(.g1TagVisibility, state: .passed)
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .failed)

    let native = [
      sampleNativeReminder(
        id: "native-1",
        title: "Call vendor",
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-5 * 86_400)
      )
    ]

    let payload = ValidatedShortcutContractPayload(
      contractID: .activeProjects,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        ShortcutContractItem(
          sourceItemID: "shortcut-1",
          nativeCalendarItemIdentifier: nil,
          nativeExternalIdentifier: nil,
          title: "Launch billing cleanup",
          notes: nil,
          listTitle: "Work",
          isCompleted: false,
          priority: .medium,
          dueAt: nil,
          createdAt: now.addingTimeInterval(-15 * 86_400),
          updatedAt: now.addingTimeInterval(-3 * 86_400),
          url: nil,
          matchedSemantics: ["active-project"],
          observedTags: ["active-project"],
          parentSourceItemID: nil,
          childSourceItemIDs: []
        )
      ],
      warnings: [],
      errors: []
    )

    let summary = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [payload],
      completedAt: now
    )
    #expect(summary.unresolvedShortcutCount == 1)

    let result = try await store.querySemantic(contractID: .activeProjects, now: now)
    #expect(result.status == .ok)
    #expect(result.confidence == .low)
    #expect(result.items.count == 1)
    #expect(result.items.first?.identityStatus == .shortcutUnresolved)
  }

  @Test("Mirror promotes deterministic shortcut joins into canonical reminders")
  func semanticRowsJoinNativeMirror() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)

    _ = try await store.setValidationGate(.g1TagVisibility, state: .passed)
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .passed)

    let native = [
      sampleNativeReminder(
        id: "native-1",
        title: "Launch billing cleanup",
        createdAt: now.addingTimeInterval(-15 * 86_400),
        updatedAt: now.addingTimeInterval(-2 * 86_400)
      )
    ]

    let payload = ValidatedShortcutContractPayload(
      contractID: .activeProjects,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        ShortcutContractItem(
          sourceItemID: "shortcut-1",
          nativeCalendarItemIdentifier: "native-1",
          nativeExternalIdentifier: nil,
          title: "Launch billing cleanup",
          notes: nil,
          listTitle: "Work",
          isCompleted: false,
          priority: .medium,
          dueAt: nil,
          createdAt: now.addingTimeInterval(-15 * 86_400),
          updatedAt: now.addingTimeInterval(-2 * 86_400),
          url: nil,
          matchedSemantics: ["active-project"],
          observedTags: ["active-project"],
          parentSourceItemID: nil,
          childSourceItemIDs: []
        )
      ],
      warnings: [],
      errors: []
    )

    _ = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [payload],
      completedAt: now
    )

    let result = try await store.querySemantic(contractID: .activeProjects, now: now)
    #expect(result.status == .ok)
    #expect(result.confidence == .medium)
    #expect(result.items.count == 1)
    #expect(result.items.first?.canonicalID != nil)
    #expect(result.items.first?.matchedSemantics == ["active-project"])
  }

  @Test("Native hygiene queries use mirrored timestamps and notes")
  func nativeHygieneQueries() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)

    let native = [
      sampleNativeReminder(
        id: "native-1",
        title: "Billing system",
        notes: nil,
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-10 * 86_400)
      ),
      sampleNativeReminder(
        id: "native-2",
        title: "Call supplier",
        notes: nil,
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-10 * 86_400)
      ),
    ]

    _ = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [],
      completedAt: now
    )

    let emptyNotes = try await store.queryOldIncompleteEmptyNotes(olderThanDays: 7, now: now)
    #expect(emptyNotes.items.count == 2)
    #expect(emptyNotes.confidence == .high)

    let vague = try await store.queryOldVagueIncompleteReminders(olderThanDays: 7, now: now)
    #expect(vague.items.count == 1)
    #expect(vague.items.first?.title == "Billing system")
  }

  private func sampleNativeReminder(
    id: String,
    title: String,
    notes: String? = nil,
    createdAt: Date,
    updatedAt: Date
  ) -> NativeReminderRecord {
    NativeReminderRecord(
      id: id,
      sourceScopeID: "local-source",
      calendarID: "calendar-1",
      listTitle: "Work",
      title: title,
      notes: notes,
      isCompleted: false,
      completionDate: nil,
      priority: .medium,
      dueDate: nil,
      createdAt: createdAt,
      updatedAt: updatedAt,
      url: nil,
      nativeCalendarItemIdentifier: id,
      nativeExternalIdentifier: "external-\(id)"
    )
  }

  private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "remindctl-gtd-tests-\(UUID().uuidString).sqlite3",
      isDirectory: false
    )
  }
}
