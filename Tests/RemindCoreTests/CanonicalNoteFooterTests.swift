import Testing

@testable import RemindCore

struct CanonicalNoteFooterTests {
  @Test("Parse valid managed footer at end of notes")
  func parseValidFooter() {
    let rawNotes = """
      Review agenda

      [remindctl-gtd:v1 id=550e8400-e29b-41d4-a716-446655440000]
      """

    let parsed = CanonicalNoteFooter.parse(rawNotes: rawNotes)

    #expect(parsed.rawNotes == rawNotes)
    #expect(parsed.notesBody == "Review agenda")
    #expect(parsed.canonicalManagedID == "550e8400-e29b-41d4-a716-446655440000")
    #expect(parsed.footerState == .valid)
  }

  @Test("Parse missing footer leaves note body unchanged")
  func parseMissingFooter() {
    let parsed = CanonicalNoteFooter.parse(rawNotes: "Review agenda")

    #expect(parsed.rawNotes == "Review agenda")
    #expect(parsed.notesBody == "Review agenda")
    #expect(parsed.canonicalManagedID == nil)
    #expect(parsed.footerState == .missing)
  }

  @Test("Parse malformed footer marks notes invalid and strips footer-like lines")
  func parseMalformedFooter() {
    let parsed = CanonicalNoteFooter.parse(
      rawNotes: """
        Review agenda

        [remindctl-gtd:v1 id=NOT-A-UUID]
        """
    )

    #expect(parsed.notesBody == "Review agenda")
    #expect(parsed.canonicalManagedID == nil)
    #expect(parsed.footerState == .invalid)
  }

  @Test("Parse duplicate footer marks notes invalid")
  func parseDuplicateFooters() {
    let parsed = CanonicalNoteFooter.parse(
      rawNotes: """
        Review agenda

        [remindctl-gtd:v1 id=550e8400-e29b-41d4-a716-446655440000]
        [remindctl-gtd:v1 id=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa]
        """
    )

    #expect(parsed.notesBody == "Review agenda")
    #expect(parsed.canonicalManagedID == nil)
    #expect(parsed.footerState == .invalid)
  }

  @Test("Normalize preserves provided canonical ID and emits canonical footer")
  func normalizeWithProvidedCanonicalID() {
    let normalized = CanonicalNoteFooter.normalize(
      rawNotes: "Review agenda",
      canonicalManagedID: "550e8400-e29b-41d4-a716-446655440000"
    )

    #expect(
      normalized.rawNotes == """
        Review agenda

        [remindctl-gtd:v1 id=550e8400-e29b-41d4-a716-446655440000]
        """
    )
    #expect(normalized.notesBody == "Review agenda")
    #expect(normalized.canonicalManagedID == "550e8400-e29b-41d4-a716-446655440000")
    #expect(normalized.footerState == .valid)
  }
}
