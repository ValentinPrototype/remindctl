import Foundation
import Testing

@testable import RemindCore

struct ShortcutContractValidatorTests {
  @Test("Validate active-project contract payload")
  func validateActiveProjectsPayload() throws {
    let payload = """
      {
        "contract_id": "shortcut.active_projects.v1",
        "contract_version": "v1",
        "generated_at": "2026-03-20T12:00:00Z",
        "status": "ok",
        "items": [
          {
            "source_item_id": "shortcut-item-001",
            "native_calendar_item_identifier": "native-1",
            "native_external_identifier": "external-1",
            "title": "Launch billing cleanup",
            "notes": null,
            "list_title": "Work",
            "is_completed": false,
            "priority": "medium",
            "due_at": "2026-03-21T09:00:00Z",
            "created_at": "2026-03-01T09:00:00Z",
            "updated_at": "2026-03-18T08:15:00Z",
            "url": null,
            "matched_semantics": ["active-project"],
            "observed_tags": ["active-project"]
          }
        ],
        "warnings": [],
        "errors": []
      }
      """

    let validated = try ShortcutContractValidator.validate(
      data: Data(payload.utf8),
      expectedContractID: .activeProjects
    )

    #expect(validated.contractID == .activeProjects)
    #expect(validated.status == .ok)
    #expect(validated.items.count == 1)
    #expect(validated.items.first?.matchedSemantics == ["active-project"])
  }

  @Test("Reject semantic contract with invalid completion state")
  func rejectCompletedSemanticItem() {
    let payload = """
      {
        "contract_id": "shortcut.next_actions.v1",
        "contract_version": "v1",
        "generated_at": "2026-03-20T12:00:00Z",
        "status": "ok",
        "items": [
          {
            "source_item_id": "shortcut-item-001",
            "native_calendar_item_identifier": null,
            "native_external_identifier": null,
            "title": "Reply to finance",
            "notes": null,
            "list_title": "Work",
            "is_completed": true,
            "priority": "high",
            "due_at": null,
            "created_at": "2026-03-01T09:00:00Z",
            "updated_at": "2026-03-18T08:15:00Z",
            "url": null,
            "matched_semantics": ["next-action"],
            "observed_tags": ["next-action"]
          }
        ],
        "warnings": [],
        "errors": []
      }
      """

    #expect(throws: ShortcutContractValidationError.self) {
      _ = try ShortcutContractValidator.validate(
        data: Data(payload.utf8),
        expectedContractID: .nextActions
      )
    }
  }
}
