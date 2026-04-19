import Testing

@testable import remindctl

struct CommandHelpersTagMutationTests {
  @Test("Add tag operation normalizes and deduplicates tags")
  func addTagOperationNormalizesAndDeduplicates() throws {
    let operation = try CommandHelpers.parseAddTagOperation(["#Active-Project", "active-project", "area_work"])

    #expect(operation == .set(["active-project", "area_work"]))
  }

  @Test("Add tag operation returns nil when no tags were provided")
  func addTagOperationAllowsNoTags() throws {
    #expect(try CommandHelpers.parseAddTagOperation([]) == nil)
  }

  @Test("Set-tag is exclusive with incremental edit tag flags")
  func setTagsAreExclusive() {
    #expect(throws: Error.self) {
      _ = try CommandHelpers.parseEditTagOperations(
        setTags: ["active-project"],
        addTags: ["waiting-on"],
        removeTags: [],
        clearTags: false
      )
    }
  }

  @Test("Clear-tags is exclusive with incremental edit tag flags")
  func clearTagsAreExclusive() {
    #expect(throws: Error.self) {
      _ = try CommandHelpers.parseEditTagOperations(
        setTags: [],
        addTags: ["waiting-on"],
        removeTags: [],
        clearTags: true
      )
    }
  }

  @Test("Incremental edit tag operations preserve order and deduplicate")
  func incrementalTagOperationsPreserveOrder() throws {
    let operations = try CommandHelpers.parseEditTagOperations(
      setTags: [],
      addTags: ["#Waiting-On", "waiting-on", "area-work"],
      removeTags: ["next-action", "NEXT-ACTION"],
      clearTags: false
    )

    #expect(
      operations == [
        .add(["waiting-on", "area-work"]),
        .remove(["next-action"]),
      ]
    )
  }

  @Test("Set-tag operation deduplicates repeated values within a single command")
  func setTagOperationDeduplicatesRepeatedValues() throws {
    let operations = try CommandHelpers.parseEditTagOperations(
      setTags: ["#Active-Project", "active-project", "ACTIVE-PROJECT"],
      addTags: [],
      removeTags: [],
      clearTags: false
    )

    #expect(operations == [.set(["active-project"])])
  }

  @Test("Incremental edit tag operations reject conflicting add and remove tags")
  func incrementalTagOperationsRejectConflicts() {
    #expect(throws: Error.self) {
      _ = try CommandHelpers.parseEditTagOperations(
        setTags: [],
        addTags: ["active-project"],
        removeTags: ["ACTIVE-PROJECT"],
        clearTags: false
      )
    }
  }

  @Test("Clear-tags produces a clear operation")
  func clearTagsOperation() throws {
    let operations = try CommandHelpers.parseEditTagOperations(
      setTags: [],
      addTags: [],
      removeTags: [],
      clearTags: true
    )

    #expect(operations == [.clear])
  }
}
