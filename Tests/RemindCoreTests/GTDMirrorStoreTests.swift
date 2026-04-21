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

  @Test("Explicit canonical promotion supports first helper-derived sync")
  func explicitCanonicalPromotionSupportsFirstHelperSync() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)
    let managedID = "77777777-7777-4777-8777-777777777777"

    _ = try await store.setValidationGate(.g1TagVisibility, state: .passed)

    let native = [
      sampleNativeReminder(
        id: "native-helper-project",
        title: "Helper project",
        notes: managedNotes(body: "Helper project", canonicalManagedID: managedID),
        createdAt: now.addingTimeInterval(-4 * 86_400),
        updatedAt: now.addingTimeInterval(-86_400)
      )
    ]
    let payload = ValidatedShortcutContractPayload(
      contractID: .activeProjects,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        shortcutItem(
          sourceItemID: "active-helper-project",
          nativeID: "native-helper-project",
          title: "Helper project",
          managedID: managedID,
          matchedSemantics: ["active-project"],
          observedTags: ["active-project", "area-work"],
          now: now
        ),
      ],
      warnings: [],
      errors: []
    )

    _ = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [payload],
      completedAt: now,
      allowCanonicalPromotion: true
    )
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .passed)

    let result = try await store.querySemantic(contractID: .activeProjects, now: now)
    #expect(result.confidence == .medium)
    #expect(result.items.count == 1)
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

  @Test("Mirror-backed project health joins active projects and hierarchy")
  func projectHealthJoinsSemanticAndHierarchyData() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)
    let healthyProjectID = "11111111-1111-4111-8111-111111111111"
    let childID = "22222222-2222-4222-8222-222222222222"
    let emptyProjectID = "33333333-3333-4333-8333-333333333333"

    _ = try await store.setValidationGate(.g1TagVisibility, state: .passed)
    _ = try await store.setValidationGate(.g2HierarchyVisibility, state: .passed)
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .passed)

    let native = [
      sampleNativeReminder(
        id: "native-healthy-project",
        title: "Healthy project",
        notes: managedNotes(body: "Project", canonicalManagedID: healthyProjectID),
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-2 * 86_400)
      ),
      sampleNativeReminder(
        id: "native-child",
        title: "Do concrete thing",
        notes: managedNotes(body: "Child", canonicalManagedID: childID),
        createdAt: now.addingTimeInterval(-9 * 86_400),
        updatedAt: now.addingTimeInterval(-1 * 86_400)
      ),
      sampleNativeReminder(
        id: "native-empty-project",
        title: "Empty project",
        notes: managedNotes(body: "Empty", canonicalManagedID: emptyProjectID),
        createdAt: now.addingTimeInterval(-8 * 86_400),
        updatedAt: now.addingTimeInterval(-1 * 86_400)
      ),
    ]

    let activePayload = ValidatedShortcutContractPayload(
      contractID: .activeProjects,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        shortcutItem(
          sourceItemID: "active-healthy",
          nativeID: "native-healthy-project",
          title: "Healthy project",
          managedID: healthyProjectID,
          matchedSemantics: ["active-project"],
          observedTags: ["active-project", "area-work"],
          now: now
        ),
        shortcutItem(
          sourceItemID: "active-empty",
          nativeID: "native-empty-project",
          title: "Empty project",
          managedID: emptyProjectID,
          matchedSemantics: ["active-project"],
          observedTags: ["active-project", "area-work"],
          now: now
        ),
      ],
      warnings: [],
      errors: []
    )
    let hierarchyPayload = ValidatedShortcutContractPayload(
      contractID: .productivityHierarchy,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        shortcutItem(
          sourceItemID: "hierarchy-healthy",
          nativeID: "native-healthy-project",
          title: "Healthy project",
          managedID: healthyProjectID,
          matchedSemantics: [],
          observedTags: ["active-project", "area-work"],
          childSourceItemIDs: ["hierarchy-child"],
          now: now
        ),
        shortcutItem(
          sourceItemID: "hierarchy-child",
          nativeID: "native-child",
          title: "Do concrete thing",
          managedID: childID,
          matchedSemantics: [],
          observedTags: ["area-work", "next-action"],
          parentSourceItemID: "hierarchy-healthy",
          now: now
        ),
        shortcutItem(
          sourceItemID: "hierarchy-empty",
          nativeID: "native-empty-project",
          title: "Empty project",
          managedID: emptyProjectID,
          matchedSemantics: [],
          observedTags: ["active-project", "area-work"],
          now: now
        ),
      ],
      warnings: [],
      errors: []
    )

    _ = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [activePayload, hierarchyPayload],
      completedAt: now
    )

    let result = try await store.queryProjectHealth(areaTag: "area-work", now: now)
    #expect(result.status == .ok)
    #expect(result.projectCount == 2)
    #expect(result.healthyCount == 1)
    let healthy = try #require(result.projects.first(where: { $0.title == "Healthy project" }))
    #expect(healthy.status == .healthy)
    #expect(healthy.nextActionCount == 1)
    let empty = try #require(result.projects.first(where: { $0.title == "Empty project" }))
    #expect(empty.status == .needsNextAction)
    #expect(empty.issues.contains(.noOpenChildren))
  }

  @Test("Weekly review composes mirror-backed sections")
  func weeklyReviewComposesMirrorData() async throws {
    let store = try GTDMirrorStore(databaseURL: temporaryDatabaseURL())
    let now = Date(timeIntervalSince1970: 1_742_472_000)
    let projectID = "44444444-4444-4444-8444-444444444444"
    let nextID = "55555555-5555-4555-8555-555555555555"
    let waitingID = "66666666-6666-4666-8666-666666666666"

    _ = try await store.setValidationGate(.g1TagVisibility, state: .passed)
    _ = try await store.setValidationGate(.g2HierarchyVisibility, state: .passed)
    _ = try await store.setValidationGate(.g3ShortcutIdentifier, state: .passed)

    let native = [
      sampleNativeReminder(
        id: "native-project",
        title: "Weekly project",
        notes: managedNotes(body: "Project", canonicalManagedID: projectID),
        createdAt: now.addingTimeInterval(-20 * 86_400),
        updatedAt: now.addingTimeInterval(-2 * 86_400)
      ),
      sampleNativeReminder(
        id: "native-next",
        title: "Do next thing",
        notes: managedNotes(body: "Next", canonicalManagedID: nextID),
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-8 * 86_400),
        dueDate: now.addingTimeInterval(-86_400)
      ),
      sampleNativeReminder(
        id: "native-waiting",
        title: "Waiting on supplier",
        notes: managedNotes(body: "Waiting", canonicalManagedID: waitingID),
        createdAt: now.addingTimeInterval(-10 * 86_400),
        updatedAt: now.addingTimeInterval(-8 * 86_400)
      ),
    ]

    let activePayload = ValidatedShortcutContractPayload(
      contractID: .activeProjects,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        shortcutItem(
          sourceItemID: "active-project",
          nativeID: "native-project",
          title: "Weekly project",
          managedID: projectID,
          matchedSemantics: ["active-project"],
          observedTags: ["active-project", "area-work"],
          now: now
        ),
      ],
      warnings: [],
      errors: []
    )
    let nextPayload = ValidatedShortcutContractPayload(
      contractID: .nextActions,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        shortcutItem(
          sourceItemID: "next-action",
          nativeID: "native-next",
          title: "Do next thing",
          managedID: nextID,
          matchedSemantics: ["next-action"],
          observedTags: ["area-work", "next-action"],
          dueAt: now.addingTimeInterval(-86_400),
          now: now
        ),
      ],
      warnings: [],
      errors: []
    )
    let waitingPayload = ValidatedShortcutContractPayload(
      contractID: .waitingOns,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        shortcutItem(
          sourceItemID: "waiting-on",
          nativeID: "native-waiting",
          title: "Waiting on supplier",
          managedID: waitingID,
          matchedSemantics: ["waiting-on"],
          observedTags: ["area-work", "waiting-on"],
          updatedAt: now.addingTimeInterval(-8 * 86_400),
          now: now
        ),
      ],
      warnings: [],
      errors: []
    )
    let hierarchyPayload = ValidatedShortcutContractPayload(
      contractID: .productivityHierarchy,
      contractVersion: "v1",
      generatedAt: now,
      status: .ok,
      items: [
        shortcutItem(
          sourceItemID: "hierarchy-project",
          nativeID: "native-project",
          title: "Weekly project",
          managedID: projectID,
          matchedSemantics: [],
          observedTags: ["active-project", "area-work"],
          childSourceItemIDs: ["hierarchy-next"],
          now: now
        ),
        shortcutItem(
          sourceItemID: "hierarchy-next",
          nativeID: "native-next",
          title: "Do next thing",
          managedID: nextID,
          matchedSemantics: [],
          observedTags: ["area-work", "next-action"],
          parentSourceItemID: "hierarchy-project",
          now: now
        ),
      ],
      warnings: [],
      errors: []
    )

    _ = try await store.replaceSnapshot(
      nativeReminders: native,
      shortcutPayloads: [activePayload, nextPayload, waitingPayload, hierarchyPayload],
      completedAt: now
    )

    let review = try await store.queryWeeklyReview(
      areaTag: "area-work",
      olderThanDays: 7,
      waitingOnDays: 7,
      now: now
    )
    #expect(review.status == .ok)
    #expect(review.projectHealth.healthyCount == 1)
    #expect(review.nextActionCount == 1)
    #expect(review.overdueActionableCount == 1)
    #expect(review.waitingOnCount == 1)
    #expect(review.warnings.contains(where: { $0.contains("G5") }))
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
    dueDate: Date? = nil,
    externalIdentifier: String? = nil
  ) -> NativeReminderRecord {
    let noteFields = ManagedNoteFields(
      parsedNotes: CanonicalNoteFooter.normalize(rawNotes: notes)
    )
    return NativeReminderRecord(
      id: id,
      sourceScopeID: "local-source",
      calendarID: "calendar-1",
      listTitle: "Work",
      title: title,
      noteFields: noteFields,
      isCompleted: false,
      completionDate: nil,
      priority: .medium,
      dueDate: dueDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      url: nil,
      nativeCalendarItemIdentifier: id,
      nativeExternalIdentifier: externalIdentifier ?? "external-\(id)"
    )
  }

  private func shortcutItem(
    sourceItemID: String,
    nativeID: String,
    title: String,
    managedID: String,
    matchedSemantics: [String],
    observedTags: [String],
    dueAt: Date? = nil,
    updatedAt: Date? = nil,
    parentSourceItemID: String? = nil,
    childSourceItemIDs: [String] = [],
    now: Date
  ) -> ShortcutContractItem {
    ShortcutContractItem(
      sourceItemID: sourceItemID,
      nativeCalendarItemIdentifier: nativeID,
      nativeExternalIdentifier: nil,
      title: title,
      rawNotes: managedNotes(body: title, canonicalManagedID: managedID),
      notes: title,
      canonicalManagedID: managedID,
      footerState: .valid,
      listTitle: "Work",
      isCompleted: false,
      priority: .medium,
      dueAt: dueAt,
      createdAt: now.addingTimeInterval(-10 * 86_400),
      updatedAt: updatedAt ?? now.addingTimeInterval(-2 * 86_400),
      url: nil,
      matchedSemantics: matchedSemantics,
      observedTags: observedTags,
      parentSourceItemID: parentSourceItemID,
      childSourceItemIDs: childSourceItemIDs
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
