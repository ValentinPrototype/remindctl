import Testing

@testable import RemindCore
@testable import remindctl

@MainActor
struct ShowCommandTests {
  @Test("Tag searches default to all filter")
  func tagDefaultsToAll() throws {
    #expect(try ShowCommand.resolveFilter(filterToken: nil, tagName: "active-project") == .all)
  }

  @Test("Non-tag show defaults to today")
  func showDefaultsToToday() throws {
    #expect(try ShowCommand.resolveFilter(filterToken: nil, tagName: nil) == .today)
  }

  @Test("Explicit filter still wins for tag searches")
  func explicitFilterWins() throws {
    #expect(try ShowCommand.resolveFilter(filterToken: "completed", tagName: "active-project") == .completed)
  }
}
