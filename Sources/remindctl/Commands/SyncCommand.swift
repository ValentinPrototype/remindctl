import Commander
import Foundation
import RemindCore

enum SyncCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "sync",
      abstract: "Sync native reminders and optional Shortcut contracts into the GTD mirror",
      discussion: "By default syncs native EventKit data only. Add --all-contracts or --contract to ingest semantic Shortcut payloads.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          options: [
            .make(
              label: "mirror",
              names: [.long("mirror")],
              help: "Path to the mirror SQLite database",
              parsing: .singleValue
            ),
            .make(
              label: "fixturesDir",
              names: [.long("fixtures-dir")],
              help: "Directory containing contract fixtures",
              parsing: .singleValue
            ),
            .make(
              label: "contract",
              names: [.long("contract")],
              help: "Contract IDs or query-family aliases",
              parsing: .upToNextOption
            ),
          ],
          flags: [
            .make(
              label: "allContracts",
              names: [.long("all-contracts")],
              help: "Sync all required v1 Shortcut contracts"
            )
          ]
        )
      ),
      usageExamples: [
        "remindctl sync",
        "remindctl sync --all-contracts",
        "remindctl sync --fixtures-dir ./fixtures",
        "remindctl sync --contract active-projects next-actions --fixtures-dir ./fixtures",
      ]
    ) { values, runtime in
      let mirrorURL = if let mirrorPath = values.option("mirror") {
        URL(fileURLWithPath: mirrorPath)
      } else {
        try MirrorPaths.defaultDatabaseURL()
      }
      let fixturesDirectory = values.option("fixturesDir").map { URL(fileURLWithPath: $0) }
      let selectedContracts = try resolveContracts(
        tokens: values.optionValues("contract"),
        allContracts: values.flag("allContracts"),
        fixturesDirectory: fixturesDirectory
      )

      let store = RemindersStore()
      try await store.requestAccess()
      let nativeReminders = try await store.nativeReminders()

      let contractRunner = ShortcutContractRunner()
      let contractPayloads = try selectedContracts.map { contractID in
        if let fixturesDirectory {
          return try contractRunner.loadFixture(contractID: contractID, directoryURL: fixturesDirectory)
        }
        return try contractRunner.runLive(contractID: contractID)
      }

      let mirror = try GTDMirrorStore(databaseURL: mirrorURL)
      let summary = try await mirror.replaceSnapshot(
        nativeReminders: nativeReminders,
        shortcutPayloads: contractPayloads
      )
      OutputRenderer.printMirrorSyncSummary(summary, format: runtime.outputFormat)
    }
  }

  private static func resolveContracts(
    tokens: [String],
    allContracts: Bool,
    fixturesDirectory: URL?
  ) throws -> [ShortcutContractID] {
    if allContracts {
      return ShortcutContractID.requiredV1Contracts
    }

    if tokens.isEmpty == false {
      return try tokens.map(parseContractID)
    }

    if fixturesDirectory != nil {
      return ShortcutContractID.requiredV1Contracts
    }

    return []
  }

  private static func parseContractID(_ token: String) throws -> ShortcutContractID {
    if let exact = ShortcutContractID(rawValue: token) {
      return exact
    }

    let normalized = token.lowercased()
    if let alias = ShortcutContractID.allCases.first(where: {
      $0.sourceQueryFamily == normalized
        || $0.rawValue.replacingOccurrences(of: ".v1", with: "") == normalized
        || $0.rawValue == "shortcut.\(normalized).v1"
    }) {
      return alias
    }

    throw RemindCoreError.operationFailed("Unknown contract ID: \(token)")
  }
}
