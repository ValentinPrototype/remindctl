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

  @Test("Native hygiene queries stay unsupported until native sync exists")
  func nativeQueriesRequireMirrorSync() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)

    let result = try await store.queryOldIncompleteEmptyNotes(now: now)
    #expect(result.status == .unsupported)
    #expect(result.warnings.contains(where: { $0.contains("Run sync first") }))
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
    let canonicalManagedID = "550e8400-e29b-41d4-a716-446655440000"
    let sharedNotes = managedNotes(body: "Launch billing cleanup", canonicalManagedID: canonicalManagedID)

    _ = try await store.setValidationGate(.g1TagVisibility, state: .passed)
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .passed)

    let native = [
      sampleNativeReminder(
        id: "native-1",
        title: "Launch billing cleanup",
        notes: sharedNotes,
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
          rawNotes: sharedNotes,
          notes: "Launch billing cleanup",
          notesBody: "Launch billing cleanup",
          canonicalManagedID: canonicalManagedID,
          footerState: .valid,
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
    #expect(result.items.first?.identityStatus == .canonicalManaged)
    #expect(result.items.first?.matchedSemantics == ["active-project"])
  }

  @Test("Hierarchy query requires the hierarchy gate and returns parent-child edges")
  func hierarchyQueryUsesHierarchyContract() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)
    let parentManagedID = "11111111-1111-4111-8111-111111111111"
    let childManagedID = "22222222-2222-4222-8222-222222222222"

    let blocked = try await store.queryHierarchy(now: now)
    #expect(blocked.status == .unsupported)
    #expect(blocked.warnings.contains(where: { $0.contains("G2") }))

    _ = try await store.setValidationGate(.g2HierarchyVisibility, state: .passed)
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .passed)

    let native = [
      sampleNativeReminder(
        id: "native-parent",
        title: "Launch billing cleanup",
        notes: managedNotes(body: "Parent", canonicalManagedID: parentManagedID),
        createdAt: now.addingTimeInterval(-15 * 86_400),
        updatedAt: now.addingTimeInterval(-2 * 86_400)
      ),
      sampleNativeReminder(
        id: "native-child",
        title: "Call vendor",
        notes: managedNotes(body: "Child", canonicalManagedID: childManagedID),
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-1 * 86_400)
      ),
    ]

    let hierarchyPayload = ValidatedShortcutContractPayload(
      contractID: .productivityHierarchy,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        ShortcutContractItem(
          sourceItemID: "shortcut-parent",
          nativeCalendarItemIdentifier: "native-parent",
          nativeExternalIdentifier: nil,
          title: "Launch billing cleanup",
          rawNotes: managedNotes(body: "Parent", canonicalManagedID: parentManagedID),
          notes: "Parent",
          notesBody: "Parent",
          canonicalManagedID: parentManagedID,
          footerState: .valid,
          listTitle: "Work",
          isCompleted: false,
          priority: .medium,
          dueAt: nil,
          createdAt: now.addingTimeInterval(-15 * 86_400),
          updatedAt: now.addingTimeInterval(-2 * 86_400),
          url: nil,
          matchedSemantics: [],
          observedTags: nil,
          parentSourceItemID: nil,
          childSourceItemIDs: ["shortcut-child"]
        ),
        ShortcutContractItem(
          sourceItemID: "shortcut-child",
          nativeCalendarItemIdentifier: "native-child",
          nativeExternalIdentifier: nil,
          title: "Call vendor",
          rawNotes: managedNotes(body: "Child", canonicalManagedID: childManagedID),
          notes: "Child",
          notesBody: "Child",
          canonicalManagedID: childManagedID,
          footerState: .valid,
          listTitle: "Work",
          isCompleted: false,
          priority: .medium,
          dueAt: nil,
          createdAt: now.addingTimeInterval(-10 * 86_400),
          updatedAt: now.addingTimeInterval(-1 * 86_400),
          url: nil,
          matchedSemantics: [],
          observedTags: nil,
          parentSourceItemID: "shortcut-parent",
          childSourceItemIDs: []
        ),
      ],
      warnings: [],
      errors: []
    )

    _ = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [hierarchyPayload],
      completedAt: now
    )

    let result = try await store.queryHierarchy(parentSourceItemID: "shortcut-parent", now: now)
    #expect(result.status == .ok)
    #expect(result.items.count == 2)
    #expect(result.items.first(where: { $0.sourceItemID == "shortcut-parent" })?.childSourceItemIDs == ["shortcut-child"])
    #expect(result.items.first(where: { $0.sourceItemID == "shortcut-parent" })?.childCanonicalIDs.count == 1)
    #expect(result.items.first(where: { $0.sourceItemID == "shortcut-child" })?.parentSourceItemID == "shortcut-parent")
  }

  @Test("Duplicate external identifiers do not collapse into one canonical row")
  func duplicateExternalIdentifiersRemainCollisionUnresolved() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)

    _ = try await store.setValidationGate(.g4ExternalIDReliability, state: .passed)
    _ = try await store.setValidationGate(.g5LastModifiedReliability, state: .passed)

    let native = [
      sampleNativeReminder(
        id: "native-1",
        title: "Billing system",
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-10 * 86_400),
        externalIdentifier: "shared-external"
      ),
      sampleNativeReminder(
        id: "native-2",
        title: "Finance cleanup",
        createdAt: now.addingTimeInterval(-9 * 86_400),
        updatedAt: now.addingTimeInterval(-9 * 86_400),
        externalIdentifier: "shared-external"
      ),
    ]

    _ = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [],
      completedAt: now
    )

    let result = try await store.queryOldIncompleteEmptyNotes(olderThanDays: 7, now: now)
    #expect(result.items.count == 2)
    #expect(result.items.allSatisfy { $0.identityStatus == .canonicalManaged })
    #expect(Set(result.items.compactMap(\.canonicalID)).count == 2)
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
    updatedAt: Date,
    externalIdentifier: String? = nil
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
      nativeExternalIdentifier: externalIdentifier ?? "external-\(id)"
    )
  }

  private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "remindctl-gtd-tests-\(UUID().uuidString).sqlite3",
      isDirectory: false
    )
  }

  private func managedNotes(body: String?, canonicalManagedID: String) -> String {
    CanonicalNoteFooter.render(notesBody: body, canonicalManagedID: canonicalManagedID)
  }
}
