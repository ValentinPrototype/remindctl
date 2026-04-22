import Commander
import Foundation
import RemindCore

enum DoctorCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "doctor",
      abstract: "Diagnose local remindctl integration setup",
      discussion: "Use doctor shortcuts to verify required Apple Shortcut helpers, canonical names, and duplicate copies.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "check", help: "shortcuts", isOptional: true)
          ],
          flags: [
            .make(
              label: "strict",
              names: [.long("strict")],
              help: "Exit non-zero when required helper checks fail"
            )
          ]
        )
      ),
      usageExamples: [
        "remindctl doctor shortcuts",
        "remindctl doctor shortcuts --json",
        "remindctl doctor shortcuts --strict",
      ]
    ) { values, runtime in
      let check = values.positional.first ?? "shortcuts"
      guard check == "shortcuts" else {
        throw RemindCoreError.operationFailed("Unknown doctor check: \(check) (use shortcuts)")
      }

      let report = ShortcutDoctor.run()
      OutputRenderer.printShortcutDoctor(report, format: runtime.outputFormat)

      if values.flag("strict"), report.status == .failed {
        throw RemindCoreError.operationFailed("Shortcut doctor failed")
      }
    }
  }
}
