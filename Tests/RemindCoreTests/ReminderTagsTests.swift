import Testing

@testable import RemindCore

struct ReminderTagsTests {
  @Test("Extract tags from title and notes")
  func extractTags() {
    let tags = ReminderTags.extract(
      title: "Ship #Release",
      notes: "Coordinate with #QA and #release"
    )
    #expect(tags == ["release", "qa"])
  }

  @Test("Normalize accepts commas and hash prefixes")
  func normalizeTags() {
    let tags = ReminderTags.normalize(["#Work,home", "ops", "work"])
    #expect(tags == ["work", "home", "ops"])
  }

  @Test("Append adds only missing tags")
  func appendTags() {
    let notes = ReminderTags.append(["work", "ops"], toNotes: "Check status #work")
    #expect(notes == "Check status #work\n\n#ops")
  }
}
