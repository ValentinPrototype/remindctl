import Foundation
import RemindCore

enum ShortcutInstallAction: String, Codable, Sendable, Equatable {
  case install
  case update
}

enum ShortcutInstallStatus: String, Codable, Sendable, Equatable {
  case ready
  case opened
  case blocked
  case failed
}

struct ShortcutInstallAsset: Codable, Sendable, Equatable {
  let helperName: String
  let path: String
  let exists: Bool

  enum CodingKeys: String, CodingKey {
    case helperName = "helper_name"
    case path
    case exists
  }
}

struct ShortcutInstallPlan: Codable, Sendable, Equatable {
  let action: ShortcutInstallAction
  let status: ShortcutInstallStatus
  let assetDirectory: String
  let assets: [ShortcutInstallAsset]
  let existingHelperNames: [String]
  let duplicateHelperNames: [String]
  let openedPaths: [String]
  let instructions: [String]
  let doctor: ShortcutDoctorReport

  enum CodingKeys: String, CodingKey {
    case action
    case status
    case assetDirectory = "asset_directory"
    case assets
    case existingHelperNames = "existing_helper_names"
    case duplicateHelperNames = "duplicate_helper_names"
    case openedPaths = "opened_paths"
    case instructions
    case doctor
  }
}

enum ShortcutInstaller {
  static func defaultAssetsDirectory(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    if let override = environment["REMINDCTL_SHORTCUTS_DIR"], !override.isEmpty {
      return URL(fileURLWithPath: override, isDirectory: true)
    }

    let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    var searchDirectory = currentDirectory
    while true {
      let supportDirectory = searchDirectory.appendingPathComponent("Support/Shortcuts", isDirectory: true)
      if fileManager.fileExists(atPath: supportDirectory.path) {
        return supportDirectory
      }

      let parent = searchDirectory.deletingLastPathComponent()
      if parent.path == searchDirectory.path {
        break
      }
      searchDirectory = parent
    }

    return currentDirectory.appendingPathComponent("Support/Shortcuts", isDirectory: true)
  }

  static func plan(
    action: ShortcutInstallAction,
    report: ShortcutDoctorReport,
    assetsDirectory: URL,
    forceOpen: Bool,
    openedPaths: [String] = [],
    fileManager: FileManager = .default
  ) -> ShortcutInstallPlan {
    let assets = ShortcutHelperCatalog.required.map { helper in
      let path = assetsDirectory.appendingPathComponent(helper.assetFilename).path
      return ShortcutInstallAsset(
        helperName: helper.name,
        path: path,
        exists: fileManager.fileExists(atPath: path)
      )
    }

    let existingHelperNames = report.requiredHelpers
      .filter(\.installed)
      .map(\.name)
      .sorted()
    let duplicateHelperNames = report.requiredHelpers
      .flatMap(\.duplicateNames)
      .sorted()
    let missingAssets = assets
      .filter { !$0.exists }
      .map(\.path)
    let inspectionErrors = report.errors
      .filter { !$0.hasPrefix("Missing required Shortcut helper:") }

    let status: ShortcutInstallStatus
    if inspectionErrors.isEmpty == false || missingAssets.isEmpty == false {
      status = .failed
    } else if forceOpen == false && (existingHelperNames.isEmpty == false || duplicateHelperNames.isEmpty == false) {
      status = .blocked
    } else if openedPaths.isEmpty == false {
      status = .opened
    } else {
      status = .ready
    }

    return ShortcutInstallPlan(
      action: action,
      status: status,
      assetDirectory: assetsDirectory.path,
      assets: assets,
      existingHelperNames: existingHelperNames,
      duplicateHelperNames: duplicateHelperNames,
      openedPaths: openedPaths,
      instructions: instructions(
        action: action,
        status: status,
        existingHelperNames: existingHelperNames,
        duplicateHelperNames: duplicateHelperNames,
        missingAssets: missingAssets,
        inspectionErrors: inspectionErrors,
        forceOpen: forceOpen
      ),
      doctor: report
    )
  }

  static func run(
    action: ShortcutInstallAction,
    assetsDirectory: URL,
    openFiles: Bool,
    forceOpen: Bool
  ) throws -> ShortcutInstallPlan {
    let report = ShortcutDoctor.run()
    let dryPlan = plan(
      action: action,
      report: report,
      assetsDirectory: assetsDirectory,
      forceOpen: forceOpen
    )
    guard openFiles, dryPlan.status == .ready else {
      return dryPlan
    }

    let paths = dryPlan.assets.map(\.path)
    let result = try ProcessExecutor.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/open"),
      arguments: paths,
      timeout: 15
    )
    guard result.status == 0 else {
      let detail = [result.stderr, result.stdout]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw RemindCoreError.operationFailed(
        "Unable to open Shortcut assets: \(detail.isEmpty ? "unknown error" : detail)"
      )
    }

    return plan(
      action: action,
      report: report,
      assetsDirectory: assetsDirectory,
      forceOpen: forceOpen,
      openedPaths: paths
    )
  }

  private static func instructions(
    action: ShortcutInstallAction,
    status: ShortcutInstallStatus,
    existingHelperNames: [String],
    duplicateHelperNames: [String],
    missingAssets: [String],
    inspectionErrors: [String],
    forceOpen: Bool
  ) -> [String] {
    if inspectionErrors.isEmpty == false {
      return ["Could not inspect installed Shortcuts safely: \(inspectionErrors.joined(separator: "; "))"]
    }
    if missingAssets.isEmpty == false {
      return ["Missing bundled Shortcut assets: \(missingAssets.joined(separator: ", "))"]
    }
    if status == .blocked {
      let namesToDelete = (existingHelperNames + duplicateHelperNames).sorted()
      return [
        "To avoid creating numbered duplicates, delete these Shortcuts in Shortcuts.app first: \(namesToDelete.joined(separator: ", ")).",
        "Then run `remindctl shortcuts \(action.rawValue)` again to open the bundled replacement assets.",
        "Use `--open-anyway` only if you intentionally want Shortcuts.app to create duplicate imports.",
      ]
    }
    if status == .opened {
      return [
        "Shortcuts.app was opened with the bundled helper assets.",
        "Approve each Add Shortcut prompt, then run `remindctl doctor shortcuts` to verify canonical names.",
      ]
    }
    if forceOpen {
      return [
        "Ready to open bundled Shortcut assets despite existing helper state because --open-anyway was used."
      ]
    }
    switch action {
    case .install:
      return ["Ready to install bundled Shortcut helpers."]
    case .update:
      return ["Ready to import bundled Shortcut helpers after old helpers have been removed."]
    }
  }
}
