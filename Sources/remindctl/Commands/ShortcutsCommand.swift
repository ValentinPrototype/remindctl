import Commander
import Foundation
import RemindCore

enum ShortcutsCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "shortcuts",
      abstract: "Install or update remindctl Apple Shortcut helpers",
      discussion: "Assisted installer for bundled Shortcut helpers. It refuses to open assets when existing canonical or numbered helper copies would cause duplicate imports.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "action", help: "install|update", isOptional: true)
          ],
          options: [
            .make(
              label: "assetsDir",
              names: [.long("assets-dir")],
              help: "Directory containing remindctl .shortcut assets",
              parsing: .singleValue
            ),
          ],
          flags: [
            .make(
              label: "dryRun",
              names: [.short("n"), .long("dry-run")],
              help: "Plan the install/update without opening Shortcut files"
            ),
            .make(
              label: "openAnyway",
              names: [.long("open-anyway")],
              help: "Open bundled Shortcut files even if existing helpers may create numbered duplicates"
            ),
          ]
        )
      ),
      usageExamples: [
        "remindctl shortcuts install",
        "remindctl shortcuts update",
        "remindctl shortcuts update --dry-run --json",
        "remindctl shortcuts install --assets-dir ./Support/Shortcuts",
      ]
    ) { values, runtime in
      let action = try parseAction(values.positional.first)
      let assetsDirectory = values.option("assetsDir")
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? ShortcutInstaller.defaultAssetsDirectory()
      let dryRun = values.flag("dryRun")
      let plan = try ShortcutInstaller.run(
        action: action,
        assetsDirectory: assetsDirectory,
        openFiles: !dryRun,
        forceOpen: values.flag("openAnyway")
      )

      OutputRenderer.printShortcutInstallPlan(plan, format: runtime.outputFormat)

      switch plan.status {
      case .ready, .opened:
        return
      case .blocked:
        if dryRun {
          return
        }
        throw RemindCoreError.operationFailed("Shortcut \(action.rawValue) is blocked to avoid duplicate imports.")
      case .failed:
        throw RemindCoreError.operationFailed("Shortcut \(action.rawValue) failed.")
      }
    }
  }

  private static func parseAction(_ rawValue: String?) throws -> ShortcutInstallAction {
    let value = rawValue ?? ShortcutInstallAction.install.rawValue
    guard let action = ShortcutInstallAction(rawValue: value) else {
      throw RemindCoreError.operationFailed("Unknown shortcuts action: \(value) (use install|update)")
    }
    return action
  }
}
