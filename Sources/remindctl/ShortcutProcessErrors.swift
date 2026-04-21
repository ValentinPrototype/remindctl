import Foundation
import RemindCore

enum ShortcutProcessErrorFormatter {
  static func timeout(
    shortcutName: String,
    category: String,
    timeout: TimeInterval,
    outputURL: URL,
    underlyingError: Error,
    installGuidance: String
  ) -> RemindCoreError {
    let outputExists = FileManager.default.fileExists(atPath: outputURL.path)
    return .operationFailed(
      """
      Shortcut "\(shortcutName)" timed out during \(category) after \(ProcessExecutor.formatTimeout(timeout))s. \
      output_path=\(outputURL.path) output_file_exists=\(outputExists). \
      The shortcuts process was terminated. \(installGuidance) \
      Detail: \(underlyingError.localizedDescription)
      """
    )
  }

  static func noOutputFile(
    shortcutName: String,
    category: String,
    outputURL: URL,
    installGuidance: String
  ) -> RemindCoreError {
    let outputExists = FileManager.default.fileExists(atPath: outputURL.path)
    return .operationFailed(
      """
      Shortcut "\(shortcutName)" returned no output file during \(category). \
      output_path=\(outputURL.path) output_file_exists=\(outputExists). \(installGuidance)
      """
    )
  }

  static func processFailure(
    shortcutName: String,
    category: String,
    result: ProcessResult,
    outputURL: URL,
    missingShortcutGuidance: String,
    installGuidance: String
  ) -> RemindCoreError {
    let combined = [result.stderr, result.stdout]
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if combined.contains("Can’t get shortcut") || combined.contains("Can't get shortcut") {
      return .operationFailed(missingShortcutGuidance)
    }

    let outputExists = FileManager.default.fileExists(atPath: outputURL.path)
    let detail = combined.isEmpty ? "unknown error" : combined
    return .operationFailed(
      """
      Shortcut "\(shortcutName)" failed during \(category) with status \(result.status). \
      output_path=\(outputURL.path) output_file_exists=\(outputExists). \(installGuidance) \
      Detail: \(detail)
      """
    )
  }
}
