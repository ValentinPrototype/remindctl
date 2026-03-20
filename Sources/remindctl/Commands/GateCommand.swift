import Commander
import Foundation
import RemindCore

enum GateCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "gate",
      abstract: "List or update validation gates for the GTD mirror",
      discussion: "Use this to make the SDD validation-gate state explicit instead of implicit.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "action", help: "list|set", isOptional: true),
            .make(label: "gate", help: "G1|G2|G3|G4|G5", isOptional: true),
          ],
          options: [
            .make(
              label: "mirror",
              names: [.long("mirror")],
              help: "Path to the mirror SQLite database",
              parsing: .singleValue
            ),
            .make(
              label: "state",
              names: [.long("state")],
              help: "pending|passed|failed",
              parsing: .singleValue
            ),
            .make(
              label: "evidence",
              names: [.long("evidence")],
              help: "Optional note describing the validation decision",
              parsing: .singleValue
            ),
          ]
        )
      ),
      usageExamples: [
        "remindctl gate",
        "remindctl gate list",
        "remindctl gate set G1 --state passed --evidence \"Verified live tag payloads\"",
        "remindctl gate set G3 --state failed --evidence \"Shortcut IDs are not stable enough for joins\"",
      ]
    ) { values, runtime in
      let action = values.argument(0)?.lowercased() ?? "list"
      let mirrorURL = if let mirrorPath = values.option("mirror") {
        URL(fileURLWithPath: mirrorPath)
      } else {
        try MirrorPaths.defaultDatabaseURL()
      }

      let mirror = try GTDMirrorStore(databaseURL: mirrorURL)

      switch action {
      case "list":
        let records = try await mirror.validationGates()
        OutputRenderer.printValidationGates(records, format: runtime.outputFormat)
      case "set":
        guard let gateToken = values.argument(1) else {
          throw ParsedValuesError.missingArgument("gate")
        }
        let gateID = try parseGateID(gateToken)
        guard let stateToken = values.option("state") else {
          throw ParsedValuesError.missingOption("state")
        }
        let state = try parseGateState(stateToken)
        let record = try await mirror.setValidationGate(
          gateID,
          state: state,
          evidence: values.option("evidence")
        )
        OutputRenderer.printValidationGates([record], format: runtime.outputFormat)
      default:
        throw RemindCoreError.operationFailed("Unknown gate action: \(action)")
      }
    }
  }

  private static func parseGateID(_ token: String) throws -> ValidationGateID {
    guard let gateID = ValidationGateID(rawValue: token.uppercased()) else {
      throw RemindCoreError.operationFailed("Unknown gate ID: \(token)")
    }
    return gateID
  }

  private static func parseGateState(_ token: String) throws -> ValidationGateState {
    guard let gateState = ValidationGateState(rawValue: token.lowercased()) else {
      throw RemindCoreError.operationFailed("Unknown gate state: \(token)")
    }
    return gateState
  }
}
