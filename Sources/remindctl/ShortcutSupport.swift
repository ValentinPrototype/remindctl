import Foundation

struct ShortcutRunFiles {
  let directoryURL: URL
  let outputURL: URL
}

enum ShortcutRunFilesFactory {
  static func make(in fileManager: FileManager = .default) throws -> ShortcutRunFiles {
    let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    let baseDirectoryURL = currentDirectoryURL.appendingPathComponent(".remindctl-shortcuts", isDirectory: true)
    try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)

    let runDirectoryURL = baseDirectoryURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: runDirectoryURL, withIntermediateDirectories: true)

    return ShortcutRunFiles(
      directoryURL: runDirectoryURL,
      outputURL: runDirectoryURL.appendingPathComponent("output.txt")
    )
  }
}
