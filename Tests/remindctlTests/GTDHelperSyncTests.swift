import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

struct GTDHelperSyncTests {
  @Test("Helper payloads synthesize semantic and hierarchy contracts")
  func helperPayloadsSynthesizeContracts() {
    let generatedAt = Date(timeIntervalSince1970: 1_742_472_000)
    let project = shortcutReminder(
      title: "Launch billing cleanup",
      managedID: "11111111-1111-4111-8111-111111111111",
      tags: ["active-project", "area-work"],
      subTasks: ["Reply to finance", "Missing child"]
    )
    let child = shortcutReminder(
      title: "Reply to finance",
      managedID: "22222222-2222-4222-8222-222222222222",
      tags: ["area-work", "next-action"],
      parent: "Launch billing cleanup"
    )

    let payloads = GTDHelperSync.helperPayloads(
      activeProjects: [project],
      nextActions: [child],
      waitingOns: [],
      areaReminders: [project, child],
      generatedAt: generatedAt
    )

    #expect(payloads.count == 4)
    let active = payloads.first(where: { $0.contractID == .activeProjects })
    #expect(active?.status == .ok)
    #expect(active?.items.first?.matchedSemantics == ["active-project"])

    let next = payloads.first(where: { $0.contractID == .nextActions })
    #expect(next?.status == .ok)
    #expect(next?.items.first?.observedTags == ["area-work", "next-action"])

    let waiting = payloads.first(where: { $0.contractID == .waitingOns })
    #expect(waiting?.status == .empty)
    #expect(waiting?.items.isEmpty == true)

    let hierarchy = payloads.first(where: { $0.contractID == .productivityHierarchy })
    #expect(hierarchy?.status == .ok)
    #expect(hierarchy?.warnings.count == 1)
    let parent = hierarchy?.items.first(where: { $0.title == "Launch billing cleanup" })
    let hierarchyChild = hierarchy?.items.first(where: { $0.title == "Reply to finance" })
    #expect(parent?.childSourceItemIDs.count == 2)
    #expect(parent?.childSourceItemIDs.contains(where: { $0.contains("22222222-2222-4222-8222-222222222222") }) == true)
    #expect(parent?.childSourceItemIDs.contains(where: { $0.hasPrefix("unresolved::") }) == true)
    #expect(hierarchyChild?.parentSourceItemID == parent?.sourceItemID)
  }

  @Test("Helper snapshot carries area tag observations without hierarchy pollution")
  func helperSnapshotCarriesAreaTagObservations() {
    let generatedAt = Date(timeIntervalSince1970: 1_742_472_000)
    let project = shortcutReminder(
      title: "Launch billing cleanup",
      managedID: "11111111-1111-4111-8111-111111111111",
      tags: ["active-project", "area-work"]
    )
    let standalone = shortcutReminder(
      title: "Clarify standalone task",
      managedID: "22222222-2222-4222-8222-222222222222",
      tags: ["area-work"]
    )

    let snapshot = GTDHelperSync.helperSnapshot(
      activeProjects: [project],
      nextActions: [],
      waitingOns: [],
      areaReminders: [project, standalone],
      generatedAt: generatedAt
    )

    #expect(snapshot.payloads.count == 4)
    #expect(snapshot.tagObservationItems.map(\.title).contains("Clarify standalone task"))
    let hierarchy = snapshot.payloads.first(where: { $0.contractID == .productivityHierarchy })
    #expect(hierarchy?.items.map(\.title).contains("Clarify standalone task") == false)
  }

  @Test("Helper hierarchy refuses ambiguous title-only child matches")
  func helperHierarchyRejectsAmbiguousTitleMatches() {
    let generatedAt = Date(timeIntervalSince1970: 1_742_472_000)
    let project = shortcutReminder(
      title: "Launch billing cleanup",
      managedID: "11111111-1111-4111-8111-111111111111",
      tags: ["active-project", "area-work"],
      subTasks: ["Email supplier"]
    )
    let otherParentChild = shortcutReminder(
      title: "Email supplier",
      managedID: "22222222-2222-4222-8222-222222222222",
      tags: ["area-work", "next-action"],
      parent: "Another project"
    )
    let topLevelSameTitle = shortcutReminder(
      title: "Email supplier",
      managedID: "33333333-3333-4333-8333-333333333333",
      tags: ["area-work", "next-action"]
    )

    let payloads = GTDHelperSync.helperPayloads(
      activeProjects: [project],
      nextActions: [],
      waitingOns: [],
      areaReminders: [project, otherParentChild, topLevelSameTitle],
      generatedAt: generatedAt
    )

    let hierarchy = payloads.first(where: { $0.contractID == .productivityHierarchy })
    let parent = hierarchy?.items.first(where: { $0.title == "Launch billing cleanup" })
    #expect(hierarchy?.items.contains(where: { $0.title == "Email supplier" }) == false)
    #expect(parent?.childSourceItemIDs.count == 1)
    #expect(parent?.childSourceItemIDs.first?.hasPrefix("unresolved::") == true)
    #expect(hierarchy?.warnings.contains(where: { $0.code == "ambiguous_child_title" }) == true)
  }

  private func shortcutReminder(
    title: String,
    managedID: String,
    tags: [String],
    subTasks: [String] = [],
    parent: String? = nil
  ) -> ShortcutTagReminder {
    ShortcutTagReminder(
      id: "native-\(managedID)",
      title: title,
      notes: nil,
      canonicalManagedID: managedID,
      isCompleted: false,
      completedAt: nil,
      priority: .none,
      dueAt: nil,
      listName: "ActiveGoals",
      tags: tags,
      subTasks: subTasks,
      parent: parent,
      createdAt: Date(timeIntervalSince1970: 1_742_472_000),
      updatedAt: Date(timeIntervalSince1970: 1_742_472_100)
    )
  }
}
