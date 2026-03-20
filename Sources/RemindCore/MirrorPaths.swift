import Foundation

public enum MirrorPaths {
  public static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
    guard let applicationSupportURL = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw RemindCoreError.operationFailed("Unable to locate Application Support directory")
    }

    let directoryURL = applicationSupportURL.appendingPathComponent("remindctl-gtd", isDirectory: true)
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL.appendingPathComponent("mirror.sqlite3", isDirectory: false)
  }
}
