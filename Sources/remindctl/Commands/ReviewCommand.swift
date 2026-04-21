import Commander
import Foundation
import RemindCore

enum ReviewCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "review",
      abstract: "Generate GTD review summaries from the local mirror",
      discussion: "Weekly review reads the GTD mirror. Use --sync to refresh the mirror first.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "cadence", help: "weekly")
          ],
          options: [
            .make(label: "mirror", names: [.long("mirror")], help: "Path to the mirror SQLite database", parsing: .singleValue),
            .make(label: "area", names: [.long("area")], help: "Limit review to an area tag, for example work or area-work", parsing: .singleValue),
            .make(label: "list", names: [.short("l"), .long("list")], help: "Limit review to a reminder list", parsing: .singleValue),
            .make(label: "olderThanDays", names: [.long("older-than-days")], help: "Age threshold for stale/vague task candidates", parsing: .singleValue),
            .make(label: "waitingOnDays", names: [.long("waiting-on-days")], help: "Age threshold for waiting-on follow-up debt", parsing: .singleValue),
          ],
          flags: [
            .make(label: "sync", names: [.long("sync")], help: "Refresh the GTD mirror before generating the review")
          ]
        )
      ),
      usageExamples: [
        "remindctl review weekly",
        "remindctl review weekly --sync",
        "remindctl review weekly --area work --waiting-on-days 7 --older-than-days 14",
      ]
    ) { values, runtime in
      let cadence = try values.argument(0).unwrap(or: ParsedValuesError.missingArgument("cadence"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      guard cadence == "weekly" else {
        throw RemindCoreError.operationFailed("Unknown review cadence: \(cadence) (use weekly)")
      }

      let mirrorURL = if let mirrorPath = values.option("mirror") {
        URL(fileURLWithPath: mirrorPath)
      } else {
        try MirrorPaths.defaultDatabaseURL()
      }
      if values.flag("sync") {
        _ = try await GTDHelperSync.sync(mirrorURL: mirrorURL)
      }

      let mirror = try GTDMirrorStore(databaseURL: mirrorURL)
      let summary = try await mirror.queryWeeklyReview(
        areaTag: try values.option("area").map(ProjectWorkflow.normalizeAreaTag),
        listTitle: values.option("list"),
        olderThanDays: try values.option("olderThanDays").map(parseNonNegativeInt) ?? 14,
        waitingOnDays: try values.option("waitingOnDays").map(parseNonNegativeInt) ?? 7
      )
      OutputRenderer.printWeeklyReview(summary, format: runtime.outputFormat)
    }
  }

  private static func parseNonNegativeInt(_ token: String) throws -> Int {
    guard let value = Int(token), value >= 0 else {
      throw RemindCoreError.operationFailed("Invalid day threshold: \(token)")
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
