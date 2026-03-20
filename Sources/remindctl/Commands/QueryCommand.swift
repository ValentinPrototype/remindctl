import Commander
import Foundation
import RemindCore

enum QueryCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "query",
      abstract: "Run GTD queries against the local mirror",
      discussion: "Supports semantic Shortcut-backed slices plus native hygiene queries.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "family", help: "active-projects|next-actions|waiting-ons|old-empty-notes|old-vague")
          ],
          options: [
            .make(
              label: "mirror",
              names: [.long("mirror")],
              help: "Path to the mirror SQLite database",
              parsing: .singleValue
            ),
            .make(
              label: "list",
              names: [.short("l"), .long("list")],
              help: "Filter results to a specific list",
              parsing: .singleValue
            ),
            .make(
              label: "due",
              names: [.long("due")],
              help: "any|overdue|today|none",
              parsing: .singleValue
            ),
            .make(
              label: "olderThanDays",
              names: [.long("older-than-days")],
              help: "Age threshold for stale queries",
              parsing: .singleValue
            ),
          ]
        )
      ),
      usageExamples: [
        "remindctl query active-projects",
        "remindctl query next-actions --due today",
        "remindctl query waiting-ons --older-than-days 7",
        "remindctl query old-empty-notes --older-than-days 14",
      ]
    ) { values, runtime in
      let family = try values.argument(0).unwrap(or: ParsedValuesError.missingArgument("family"))
      let mirrorURL = if let mirrorPath = values.option("mirror") {
        URL(fileURLWithPath: mirrorPath)
      } else {
        try MirrorPaths.defaultDatabaseURL()
      }
      let dueFilter = try values.option("due").map(parseDueFilter) ?? .any
      let olderThanDays = try values.option("olderThanDays").map(parseOlderThanDays)

      let mirror = try GTDMirrorStore(databaseURL: mirrorURL)
      let result: GTDQueryResult

      switch family.lowercased() {
      case "active-projects":
        result = try await mirror.querySemantic(
          contractID: .activeProjects,
          listTitle: values.option("list"),
          dueFilter: dueFilter,
          olderThanDays: olderThanDays
        )
      case "next-actions":
        result = try await mirror.querySemantic(
          contractID: .nextActions,
          listTitle: values.option("list"),
          dueFilter: dueFilter,
          olderThanDays: olderThanDays
        )
      case "waiting-ons":
        result = try await mirror.querySemantic(
          contractID: .waitingOns,
          listTitle: values.option("list"),
          dueFilter: dueFilter,
          olderThanDays: olderThanDays
        )
      case "old-empty-notes":
        result = try await mirror.queryOldIncompleteEmptyNotes(
          olderThanDays: olderThanDays ?? 7
        )
      case "old-vague", "old-vague-tasks":
        result = try await mirror.queryOldVagueIncompleteReminders(
          olderThanDays: olderThanDays ?? 7
        )
      default:
        throw RemindCoreError.operationFailed("Unknown GTD query family: \(family)")
      }

      OutputRenderer.printGTDQueryResult(result, format: runtime.outputFormat)
    }
  }

  private static func parseDueFilter(_ token: String) throws -> GTDDueFilter {
    guard let dueFilter = GTDDueFilter(rawValue: token.lowercased()) else {
      throw RemindCoreError.operationFailed("Invalid due filter: \(token)")
    }
    return dueFilter
  }

  private static func parseOlderThanDays(_ token: String) throws -> Int {
    guard let value = Int(token), value >= 0 else {
      throw RemindCoreError.operationFailed("Invalid older-than-days value: \(token)")
    }
    return value
  }
}

private extension Optional {
  func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
    guard let value = self else { throw error() }
    return value
  }
}
