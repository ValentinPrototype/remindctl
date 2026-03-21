import Foundation

public enum CanonicalNoteFooterState: String, Codable, Sendable, CaseIterable {
  case missing
  case valid
  case invalid
}

public struct ParsedReminderNotes: Codable, Sendable, Equatable {
  public let rawNotes: String?
  public let notesBody: String?
  public let canonicalManagedID: String?
  public let footerState: CanonicalNoteFooterState

  public init(
    rawNotes: String?,
    notesBody: String?,
    canonicalManagedID: String?,
    footerState: CanonicalNoteFooterState
  ) {
    self.rawNotes = rawNotes
    self.notesBody = notesBody
    self.canonicalManagedID = canonicalManagedID
    self.footerState = footerState
  }
}

public enum CanonicalNoteFooter {
  public static let marker = "remindctl-gtd"
  public static let version = "v1"

  private static let footerPattern =
    #"^\[remindctl-gtd:v1 id=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]$"#

  public static func parse(rawNotes: String?) -> ParsedReminderNotes {
    let normalizedRawNotes = normalizeNewlines(in: rawNotes)
    let trimmedRawNotes = trimmedOptionalString(normalizedRawNotes)
    guard let trimmedRawNotes else {
      return ParsedReminderNotes(
        rawNotes: nil,
        notesBody: nil,
        canonicalManagedID: nil,
        footerState: .missing
      )
    }

    let lines = trimmedRawNotes.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let footerLineIndices = lines.enumerated().compactMap { index, line -> Int? in
      exactManagedID(in: line) == nil ? nil : index
    }
    let footerLikeLineIndices = lines.enumerated().compactMap { index, line -> Int? in
      looksLikeFooterLine(line) ? index : nil
    }
    let lastNonEmptyLineIndex = lines.lastIndex { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }

    let notesBody = stripFooterLikeLines(from: lines, footerLikeLineIndices: footerLikeLineIndices)

    if footerLineIndices.count == 1,
      footerLikeLineIndices.count == 1,
      let footerLineIndex = footerLineIndices.first,
      footerLineIndex == lastNonEmptyLineIndex,
      let canonicalManagedID = exactManagedID(in: lines[footerLineIndex])
    {
      return ParsedReminderNotes(
        rawNotes: trimmedRawNotes,
        notesBody: notesBody,
        canonicalManagedID: canonicalManagedID,
        footerState: .valid
      )
    }

    if footerLikeLineIndices.isEmpty == false {
      return ParsedReminderNotes(
        rawNotes: trimmedRawNotes,
        notesBody: notesBody,
        canonicalManagedID: nil,
        footerState: .invalid
      )
    }

    return ParsedReminderNotes(
      rawNotes: trimmedRawNotes,
      notesBody: trimmedRawNotes,
      canonicalManagedID: nil,
      footerState: .missing
    )
  }

  public static func normalize(
    rawNotes: String?,
    canonicalManagedID: String? = nil
  ) -> ParsedReminderNotes {
    let parsed = parse(rawNotes: rawNotes)
    let resolvedCanonicalManagedID = parsed.canonicalManagedID ?? canonicalManagedID ?? generateCanonicalManagedID()
    let renderedNotes = render(
      notesBody: parsed.notesBody,
      canonicalManagedID: resolvedCanonicalManagedID
    )
    return parse(rawNotes: renderedNotes)
  }

  public static func render(notesBody: String?, canonicalManagedID: String) -> String {
    let footerLine = "[\(marker):\(version) id=\(canonicalManagedID.lowercased())]"
    guard let notesBody = trimmedOptionalString(normalizeNewlines(in: notesBody)) else {
      return footerLine
    }
    return "\(notesBody)\n\n\(footerLine)"
  }

  public static func generateCanonicalManagedID() -> String {
    UUID().uuidString.lowercased()
  }

  private static func stripFooterLikeLines(
    from lines: [String],
    footerLikeLineIndices: [Int]
  ) -> String? {
    guard footerLikeLineIndices.isEmpty == false else {
      return trimmedOptionalString(lines.joined(separator: "\n"))
    }

    let footerLikeIndexSet = Set(footerLikeLineIndices)
    var strippedLines = lines.enumerated().compactMap { index, line -> String? in
      footerLikeIndexSet.contains(index) ? nil : line
    }

    while strippedLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
      _ = strippedLines.popLast()
    }

    return trimmedOptionalString(strippedLines.joined(separator: "\n"))
  }

  private static func exactManagedID(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let regex = try? NSRegularExpression(pattern: footerPattern) else {
      return nil
    }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
      match.numberOfRanges == 2,
      let idRange = Range(match.range(at: 1), in: trimmed)
    else {
      return nil
    }
    return String(trimmed[idRange])
  }

  private static func looksLikeFooterLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.contains("[\(marker):") || trimmed.hasPrefix("[\(marker)")
  }

  private static func normalizeNewlines(in value: String?) -> String? {
    value?
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func trimmedOptionalString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
