import Foundation
import Testing

@testable import remindctl

struct ShortcutDoctorTests {
  @Test("Shortcut doctor reports canonical helpers as ok")
  func canonicalHelpersPass() {
    let report = ShortcutDoctor.evaluate(
      installedShortcutNames: [
        "remindctl - Search By Tag",
        "remindctl - Mutate Tags",
        "remindctl - Mutate Hierarchy",
      ]
    )

    #expect(report.status == .ok)
    #expect(report.errors.isEmpty)
    #expect(report.warnings.isEmpty)
    #expect(report.requiredHelpers.count == 3)
    #expect(report.requiredHelpers.allSatisfy { $0.installed })
  }

  @Test("Shortcut doctor flags numbered duplicate helper copies")
  func numberedDuplicatesWarn() {
    let report = ShortcutDoctor.evaluate(
      installedShortcutNames: [
        "remindctl - Search By Tag",
        "remindctl - Search By Tag 1",
        "remindctl - Mutate Tags",
        "remindctl - Mutate Tags 1",
        "remindctl - Mutate Hierarchy",
        "remindctl - Mutate Hierarchy 2",
        "remindctl - Mutate Tags Copy",
      ]
    )

    #expect(report.status == .warning)
    #expect(report.errors.isEmpty)
    #expect(report.warnings.count == 3)
    #expect(
      report.requiredHelpers.first(where: { $0.name == "remindctl - Mutate Tags" })?.duplicateNames
        == ["remindctl - Mutate Tags 1"]
    )
  }

  @Test("Shortcut doctor fails when a canonical helper is missing")
  func missingCanonicalHelperFails() {
    let report = ShortcutDoctor.evaluate(
      installedShortcutNames: [
        "remindctl - Search By Tag 1",
        "remindctl - Mutate Tags",
        "remindctl - Mutate Hierarchy",
      ]
    )

    #expect(report.status == .failed)
    #expect(report.errors.contains("Missing required Shortcut helper: remindctl - Search By Tag"))
    #expect(
      report.requiredHelpers.first(where: { $0.name == "remindctl - Search By Tag" })?.installed == false
    )
  }

  @Test("Shortcut doctor command parses")
  func doctorCommandParses() throws {
    let invocation = try CommandRouter().program.resolve(
      argv: [
        "remindctl",
        "doctor",
        "shortcuts",
        "--strict",
        "--json",
      ]
    )

    #expect(invocation.path == ["remindctl", "doctor"])
    #expect(invocation.parsedValues.positional == ["shortcuts"])
    #expect(invocation.parsedValues.flag("strict"))
    #expect(invocation.parsedValues.flag("jsonOutput"))
  }

  @Test("Shortcut doctor command is registered")
  func doctorCommandRegistered() {
    let router = CommandRouter()

    #expect(router.specs.contains(where: { $0.name == "doctor" }))
  }

  @Test("Shortcut install plan is ready when assets exist and no helpers are installed")
  func shortcutInstallPlanReady() throws {
    let assetsDirectory = try makeTemporaryShortcutAssets()
    defer { try? FileManager.default.removeItem(at: assetsDirectory) }
    let report = ShortcutDoctor.evaluate(installedShortcutNames: [])

    let plan = ShortcutInstaller.plan(
      action: .install,
      report: report,
      assetsDirectory: assetsDirectory,
      forceOpen: false
    )

    #expect(plan.status == .ready)
    #expect(plan.assets.count == 3)
    #expect(plan.assets.allSatisfy { $0.exists })
    #expect(plan.existingHelperNames.isEmpty)
    #expect(plan.duplicateHelperNames.isEmpty)
  }

  @Test("Shortcut update plan blocks when installed helpers would create duplicate imports")
  func shortcutUpdatePlanBlocksExistingHelpers() throws {
    let assetsDirectory = try makeTemporaryShortcutAssets()
    defer { try? FileManager.default.removeItem(at: assetsDirectory) }
    let report = ShortcutDoctor.evaluate(
      installedShortcutNames: [
        "remindctl - Search By Tag",
        "remindctl - Mutate Tags",
        "remindctl - Mutate Tags 1",
        "remindctl - Mutate Hierarchy",
      ]
    )

    let plan = ShortcutInstaller.plan(
      action: .update,
      report: report,
      assetsDirectory: assetsDirectory,
      forceOpen: false
    )

    #expect(plan.status == .blocked)
    #expect(plan.existingHelperNames == [
      "remindctl - Mutate Hierarchy",
      "remindctl - Mutate Tags",
      "remindctl - Search By Tag",
    ])
    #expect(plan.duplicateHelperNames == ["remindctl - Mutate Tags 1"])
    #expect(plan.instructions.contains(where: { $0.contains("delete these Shortcuts") }))
  }

  @Test("Shortcut install plan fails when bundled assets are missing")
  func shortcutInstallPlanFailsMissingAssets() throws {
    let assetsDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("remindctl-empty-shortcuts-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: assetsDirectory) }

    let plan = ShortcutInstaller.plan(
      action: .install,
      report: ShortcutDoctor.evaluate(installedShortcutNames: []),
      assetsDirectory: assetsDirectory,
      forceOpen: false
    )

    #expect(plan.status == .failed)
    #expect(plan.assets.allSatisfy { !$0.exists })
    #expect(plan.instructions.contains(where: { $0.contains("Missing bundled Shortcut assets") }))
  }

  @Test("Shortcuts install command parses")
  func shortcutsInstallCommandParses() throws {
    let invocation = try CommandRouter().program.resolve(
      argv: [
        "remindctl",
        "shortcuts",
        "update",
        "--dry-run",
        "--assets-dir",
        "/tmp/shortcuts",
        "--json",
      ]
    )

    #expect(invocation.path == ["remindctl", "shortcuts"])
    #expect(invocation.parsedValues.positional == ["update"])
    #expect(invocation.parsedValues.flag("dryRun"))
    #expect(invocation.parsedValues.option("assetsDir") == "/tmp/shortcuts")
    #expect(invocation.parsedValues.flag("jsonOutput"))
  }

  @Test("Shortcuts command is registered")
  func shortcutsCommandRegistered() {
    let router = CommandRouter()

    #expect(router.specs.contains(where: { $0.name == "shortcuts" }))
  }

  private func makeTemporaryShortcutAssets() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("remindctl-shortcuts-assets-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for helper in ShortcutHelperCatalog.required {
      let url = directory.appendingPathComponent(helper.assetFilename)
      try Data("shortcut".utf8).write(to: url)
    }

    return directory
  }
}
