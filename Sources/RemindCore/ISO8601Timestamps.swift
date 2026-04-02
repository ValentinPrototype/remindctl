import Foundation

enum ISO8601Timestamps {
  private static func fractionalSecondsFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private static func basicFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }

  static func string(from date: Date) -> String {
    fractionalSecondsFormatter().string(from: date)
  }

  static func parse(_ rawValue: String) -> Date? {
    fractionalSecondsFormatter().date(from: rawValue) ?? basicFormatter().date(from: rawValue)
  }

  static func isUTCString(_ rawValue: String) -> Bool {
    rawValue.hasSuffix("Z")
  }
}
