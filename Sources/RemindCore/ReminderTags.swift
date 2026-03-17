import Foundation

public enum ReminderTags {
  private static let regex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])#([A-Za-z0-9_-]+)"#)

  public static func extract(title: String, notes: String?) -> [String] {
    let text: String
    if let notes, !notes.isEmpty {
      text = "\(title)\n\(notes)"
    } else {
      text = title
    }

    var result: [String] = []
    var seen = Set<String>()
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in regex.matches(in: text, options: [], range: range) {
      guard
        let tagRange = Range(match.range(at: 1), in: text)
      else {
        continue
      }
      let tag = String(text[tagRange]).lowercased()
      if seen.insert(tag).inserted {
        result.append(tag)
      }
    }
    return result
  }

  public static func normalize(_ rawTags: [String]) -> [String] {
    var normalized: [String] = []
    var seen = Set<String>()

    for raw in rawTags {
      for fragment in raw.split(separator: ",") {
        var token = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("#") {
          token.removeFirst()
        }
        guard
          !token.isEmpty,
          token.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
        else {
          continue
        }
        let tag = token.lowercased()
        if seen.insert(tag).inserted {
          normalized.append(tag)
        }
      }
    }

    return normalized
  }

  public static func append(_ tags: [String], toNotes notes: String?, title: String = "") -> String? {
    let normalized = normalize(tags)
    guard !normalized.isEmpty else { return notes }

    let existing = Set(extract(title: title, notes: notes))
    let toAppend = normalized.filter { !existing.contains($0) }
    guard !toAppend.isEmpty else { return notes }

    let tagLine = toAppend.map { "#\($0)" }.joined(separator: " ")
    guard let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return tagLine
    }
    return "\(notes)\n\n\(tagLine)"
  }
}
