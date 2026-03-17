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

  @Test("Build shortcuts run invocation")
  func shortcutsInvocation() {
    let args = ShortcutTagSearch.shortcutsArguments(
      inputPath: "/workspace/input.txt",
      outputPath: "/workspace/output.txt"
    )

    #expect(
      args == [
        "run",
        "remindctl: Search Reminders By Tag with JSON Output",
        "--input-path",
        "/workspace/input.txt",
        "--output-path",
        "/workspace/output.txt",
      ]
    )
  }

  @Test("Wrap shortcut command for AppleScript transport")
  func osascriptInvocation() {
    let args = ShortcutTagSearch.osascriptArguments(
      inputPath: "/workspace/input.txt",
      outputPath: "/workspace/output.txt"
    )

    #expect(args.count == 10)
    #expect(args[0] == "-e")
    #expect(args[1].contains("set shortcutName"))
    #expect(args[3].contains("set inputPath"))
    #expect(args[5].contains("set outputPath"))
    #expect(args[7].contains("set cmd to"))
    #expect(args[9] == "do shell script cmd")
  }

  @Test("Wrap AppleScript transport in a shell command")
  func osascriptShellInvocation() {
    let command = ShortcutTagSearch.osascriptShellCommand(
      inputPath: "/workspace/input.txt",
      outputPath: "/workspace/output.txt"
    )

    #expect(command.contains("'osascript'"))
    #expect(command.contains("'set shortcutName to "))
    #expect(command.contains("'do shell script cmd'"))
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
