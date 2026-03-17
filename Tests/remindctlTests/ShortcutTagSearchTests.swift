import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

@MainActor
struct ShortcutTagSearchTests {
  @Test("Normalize strips leading hash")
  func normalizeTag() throws {
    #expect(try ShortcutTagSearch.normalizeTag("#active-project") == "active-project")
    #expect(try ShortcutTagSearch.normalizeTag("##ACTIVE_PROJECT") == "active_project")
  }

  @Test("Normalize rejects empty tag")
  func rejectEmptyTag() {
    #expect(throws: Error.self) {
      try ShortcutTagSearch.normalizeTag("###")
    }
  }

  @Test("Normalize rejects empty tag lists")
  func rejectEmptyTagList() {
    #expect(throws: Error.self) {
      try ShortcutTagSearch.normalizeTags([])
    }
  }

  @Test("Encode single-tag versioned query")
  func encodeSingleTagQuery() throws {
    let normalizedTags = try ShortcutTagSearch.normalizeTags(["#active-project"])
    let query = ShortcutTagSearch.makeQuery(tags: normalizedTags)
    let rawQuery = try ShortcutTagSearch.encodeQuery(query)
    let object = try JSONSerialization.jsonObject(with: Data(rawQuery.utf8)) as? [String: Any]
    let filters = object?["filters"] as? [String: Any]

    #expect(object?["schemaVersion"] as? Int == 1)
    #expect(filters?["tagsAll"] as? [String] == ["active-project"])
    #expect(object?["tags"] as? [String] == ["active-project"])
  }

  @Test("Encode repeated tags in normalized input order")
  func encodeRepeatedTags() throws {
    let normalizedTags = try ShortcutTagSearch.normalizeTags(["#Area-Work", "active-project"])
    let query = ShortcutTagSearch.makeQuery(tags: normalizedTags)
    let rawQuery = try ShortcutTagSearch.encodeQuery(query)
    let object = try JSONSerialization.jsonObject(with: Data(rawQuery.utf8)) as? [String: Any]
    let filters = object?["filters"] as? [String: Any]

    #expect(filters?["tagsAll"] as? [String] == ["area-work", "active-project"])
    #expect(object?["tags"] as? [String] == ["area-work", "active-project"])
  }

  @Test("Build shortcuts run invocation")
  func shortcutsInvocation() {
    let args = ShortcutTagSearch.shortcutsArguments(outputPath: "/workspace/output.txt")

    #expect(
      args == [
        "run",
        "remindctl: Search Reminders By Tag with JSON Output",
        "--output-path",
        "/workspace/output.txt",
      ]
    )
  }

  @Test("Decode shortcut payload JSON")
  func decodePayload() throws {
    let payload = try ShortcutTagSearch.decodePayload(
      from: """
      {
        "success": true,
        "count": 1,
        "request": "active-project",
        "data": [
          {
            "id": "Build Main Agent",
            "title": "Build Main Agent",
            "notes": "ship it",
            "isCompleted": false,
            "completedAt": "",
            "priority": "High",
            "dueAt": "2026-03-18T10:00:00Z",
            "list": "Work",
            "tags": "active-project\\nopenclaw",
            "subTasks": "Define next action\\nShip it",
            "parent": "",
            "url": "https://example.com/reminder",
            "hasSubtasks": true,
            "location": "",
            "whenMessagingPerson": "",
            "isFlagged": true,
            "hasAlarms": false,
            "createdAt": "2026-03-17T10:00:00Z",
            "udpatedAt": "2026-03-17T11:00:00Z"
          }
        ]
      }
      """
    )

    #expect(payload.success)
    #expect(payload.count == 1)
    #expect(payload.request == "active-project")
    #expect(payload.data.count == 1)
    #expect(payload.data[0].id == "Build Main Agent")
    #expect(payload.data[0].priority == .high)
    #expect(payload.data[0].tags == ["active-project", "openclaw"])
    #expect(payload.data[0].subTasks == ["Define next action", "Ship it"])
    #expect(payload.data[0].url == "https://example.com/reminder")
    #expect(payload.data[0].isFlagged)
    #expect(payload.data[0].listName == "Work")
  }

  @Test("Decoded shortcut reminders reuse filter and sort behavior")
  func decodedRemindersFilterAndSort() throws {
    let payload = try ShortcutTagSearch.decodePayload(
      from: """
      {
        "success": true,
        "count": 3,
        "request": "active-project",
        "data": [
          {
            "id": "Later",
            "title": "Later",
            "notes": "",
            "isCompleted": false,
            "completedAt": "",
            "priority": "None",
            "dueAt": "2026-03-20T00:00:00Z",
            "list": "Work",
            "tags": "active-project",
            "subTasks": "",
            "parent": "",
            "url": "",
            "hasSubtasks": false,
            "location": "",
            "whenMessagingPerson": "",
            "isFlagged": false,
            "hasAlarms": false,
            "createdAt": "",
            "udpatedAt": ""
          },
          {
            "id": "abc123",
            "title": "Done",
            "notes": "",
            "isCompleted": true,
            "completedAt": "2026-03-17T10:00:00Z",
            "priority": "Low",
            "dueAt": "2026-03-18T00:00:00Z",
            "list": "Work",
            "tags": "active-project",
            "subTasks": "",
            "parent": "",
            "url": "",
            "hasSubtasks": false,
            "location": "",
            "whenMessagingPerson": "",
            "isFlagged": false,
            "hasAlarms": false,
            "createdAt": "",
            "udpatedAt": ""
          },
          {
            "id": "xyz789",
            "title": "Sooner",
            "notes": "",
            "isCompleted": false,
            "completedAt": "",
            "priority": "Medium",
            "dueAt": "2026-03-18T00:00:00Z",
            "list": "Work",
            "tags": "active-project",
            "subTasks": "",
            "parent": "",
            "url": "",
            "hasSubtasks": false,
            "location": "",
            "whenMessagingPerson": "",
            "isFlagged": false,
            "hasAlarms": false,
            "createdAt": "",
            "udpatedAt": ""
          }
        ]
      }
      """
    )

    let completed = ReminderFiltering.apply(payload.data, filter: .completed)
    #expect(completed.map(\.title) == ["Done"])

    let sorted = ReminderFiltering.sort(payload.data)
    #expect(sorted.map(\.title) == ["Done", "Sooner", "Later"])
  }

  @Test("Plain output tolerates missing IDs")
  func plainOutputWithMissingID() {
    let reminder = ShortcutTagReminder(
      id: nil,
      title: "Build Main Agent",
      notes: nil,
      isCompleted: false,
      completedAt: nil,
      priority: .medium,
      dueAt: nil,
      listName: "Work",
      tags: ["active-project"],
      subTasks: [],
      createdAt: nil,
      updatedAt: nil
    )

    let lines = OutputRenderer.renderShortcutTagRemindersPlain([reminder])
    #expect(lines.count == 1)
    #expect(lines[0].hasPrefix("\tWork\t0\tmedium\t\tBuild Main Agent"))
  }
}
