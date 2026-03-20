import Testing

@testable import RemindCore
@testable import remindctl

@MainActor
struct ShowCommandTests {
  @Test("Tag searches default to all filter")
  func tagDefaultsToAll() throws {
    #expect(try ShowCommand.resolveFilter(filterToken: nil, tagNames: ["active-project"]) == .all)
  }

  @Test("Non-tag show defaults to today")
  func showDefaultsToToday() throws {
    #expect(try ShowCommand.resolveFilter(filterToken: nil, tagNames: []) == .today)
  }

  @Test("Explicit filter still wins for tag searches")
  func explicitFilterWins() throws {
    #expect(try ShowCommand.resolveFilter(filterToken: "completed", tagNames: ["active-project"]) == .completed)
  }

  @Test("Multiple tags still default to all filter")
  func multiTagDefaultsToAll() throws {
    #expect(try ShowCommand.resolveFilter(filterToken: nil, tagNames: ["active-project", "area-work"]) == .all)
  }
}
