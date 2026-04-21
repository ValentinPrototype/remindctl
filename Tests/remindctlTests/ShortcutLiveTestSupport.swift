import Darwin
import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

struct ManagedReminderFixture {
  let reminder: ReminderItem
  let managedID: String
  let title: String
}

struct ManagedReminderSeed {
  let titlePrefix: String
  let tags: [String]
}

struct CapturedCommandResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

enum ShortcutLiveTestSupport {
  static func withManagedReminders(
    seeds: [ManagedReminderSeed],
    body: ([ManagedReminderFixture]) async throws -> Void
  ) async throws {
    let store = RemindersStore()
    try await store.requestAccess()

    let targetList = try #require(await store.defaultListName())
    var createdReminders: [ReminderItem] = []
    var createdFixtures: [ManagedReminderFixture] = []

    do {
      for (index, seed) in seeds.enumerated() {
        let managedID = UUID().uuidString.lowercased()
        let title = "\(seed.titlePrefix) \(UUID().uuidString)"
        let notes = """
        Reminder created by remindctl live test \(index)

        [remindctl-gtd:v1 id=\(managedID)]
        """
        let reminder = try await store.createReminder(
          ReminderDraft(title: title, notes: notes, dueDate: nil, priority: .none),
          listName: targetList
        )
        createdReminders.append(reminder)
        createdFixtures.append(
          ManagedReminderFixture(reminder: reminder, managedID: managedID, title: title)
        )
      }

      for (fixture, seed) in zip(createdFixtures, seeds) where seed.tags.isEmpty == false {
        _ = try runMutationShortcut(
          request: ShortcutTagMutationRequest(
            targetManagedID: fixture.managedID,
            operation: .set(seed.tags)
          )
        )
      }

      try await body(createdFixtures)
    } catch {
      if createdReminders.isEmpty == false {
        _ = try? await store.deleteReminders(ids: createdReminders.map(\.id))
      }
      throw error
    }

    if createdReminders.isEmpty == false {
      _ = try? await store.deleteReminders(ids: createdReminders.map(\.id))
    }
  }

  static func withDuplicateManagedReminders(
    reminderCount: Int,
    titlePrefix: String,
    body: ([ManagedReminderFixture]) async throws -> Void
  ) async throws {
    let store = RemindersStore()
    try await store.requestAccess()

    let targetList = try #require(await store.defaultListName())
    let managedID = UUID().uuidString.lowercased()
    var createdReminders: [ReminderItem] = []
    var fixtures: [ManagedReminderFixture] = []

    do {
      for index in 0..<reminderCount {
        let title = "\(titlePrefix) \(UUID().uuidString)"
        let notes = """
        Reminder created by remindctl live duplicate test \(index)

        [remindctl-gtd:v1 id=\(managedID)]
        """
        let reminder = try await store.createReminder(
          ReminderDraft(title: title, notes: notes, dueDate: nil, priority: .none),
          listName: targetList
        )
        createdReminders.append(reminder)
        fixtures.append(ManagedReminderFixture(reminder: reminder, managedID: managedID, title: title))
      }

      try await body(fixtures)
    } catch {
      if createdReminders.isEmpty == false {
        _ = try? await store.deleteReminders(ids: createdReminders.map(\.id))
      }
      throw error
    }

    if createdReminders.isEmpty == false {
      _ = try? await store.deleteReminders(ids: createdReminders.map(\.id))
    }
  }

  static func runMutationShortcut(request: ShortcutTagMutationRequest) throws -> ShortcutTagMutationResponse {
    let rawOutput = try runShortcut(name: ShortcutTagMutation.shortcutName, input: ShortcutTagMutation.encodeRequest(request))
    return try ShortcutTagMutation.decodeResponse(from: rawOutput)
  }

  static func runHierarchyShortcut(request: ShortcutHierarchyMutationRequest) throws -> ShortcutHierarchyMutationResponse {
    let rawOutput = try runShortcut(name: ShortcutHierarchyMutation.shortcutName, input: ShortcutHierarchyMutation.encodeRequest(request))
    return try ShortcutHierarchyMutation.decodeResponse(from: rawOutput)
  }

  static func runSearchShortcut(tags: [String]) throws -> ShortcutTagSearchPayload {
    let query = ShortcutTagSearch.makeQuery(tags: try ShortcutTagSearch.normalizeTags(tags))
    let rawOutput = try runShortcut(name: ShortcutTagSearch.shortcutName, input: ShortcutTagSearch.encodeQuery(query))
    return try ShortcutTagSearch.decodePayload(from: rawOutput)
  }

  static func runSearchShortcutRaw(input: String) throws -> [String: Any] {
    try decodeJSONObject(runShortcut(name: ShortcutTagSearch.shortcutName, input: input))
  }

  static func runMutationShortcutRaw(input: String) throws -> [String: Any] {
    try decodeJSONObject(runShortcut(name: ShortcutTagMutation.shortcutName, input: input))
  }

  static func runHierarchyShortcutRaw(input: String) throws -> [String: Any] {
    try decodeJSONObject(runShortcut(name: ShortcutHierarchyMutation.shortcutName, input: input))
  }

  static func runRemindctl(_ args: [String]) async throws -> CapturedCommandResult {
    let router = CommandRouter()
    return try await captureStandardStreams {
      await router.run(argv: ["remindctl"] + args)
    }
  }

  private static func runShortcut(name: String, input: String) throws -> String {
    let runFiles = try ShortcutRunFilesFactory.make()
    defer {
      try? FileManager.default.removeItem(at: runFiles.directoryURL)
    }

    let result: ProcessResult
    do {
      result = try ProcessExecutor.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
        arguments: [
          "run",
          name,
          "--output-path",
          runFiles.outputURL.path,
        ],
        stdin: input,
        timeout: timeout(for: name)
      )
    } catch let error as ProcessExecutionError {
      throw ShortcutProcessErrorFormatter.timeout(
        shortcutName: name,
        category: category(for: name),
        timeout: timeout(for: name),
        outputURL: runFiles.outputURL,
        underlyingError: error,
        installGuidance: installGuidance(for: name)
      )
    } catch {
      throw error
    }

    guard result.status == 0 else {
      let output = (try? String(contentsOf: runFiles.outputURL, encoding: .utf8)) ?? "<missing>"
      Issue.record(
        """
        Shortcut "\(name)" exited with status \(result.status)
        stdin: \(input)
        stdout: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))
        """
      )
      throw ShortcutProcessErrorFormatter.processFailure(
        shortcutName: name,
        category: category(for: name),
        result: result,
        outputURL: runFiles.outputURL,
        missingShortcutGuidance: "Shortcut \"\(name)\" is required for live Shortcut tests. \(installGuidance(for: name))",
        installGuidance: installGuidance(for: name)
      )
    }

    guard FileManager.default.fileExists(atPath: runFiles.outputURL.path) else {
      Issue.record(
        """
        Shortcut "\(name)" produced no output file
        stdin: \(input)
        stdout: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        """
      )
      throw ShortcutProcessErrorFormatter.noOutputFile(
        shortcutName: name,
        category: category(for: name),
        outputURL: runFiles.outputURL,
        installGuidance: installGuidance(for: name)
      )
    }

    return try String(contentsOf: runFiles.outputURL, encoding: .utf8)
  }

  private static func timeout(for shortcutName: String) -> TimeInterval {
    switch shortcutName {
    case ShortcutTagSearch.shortcutName:
      return ShortcutTagSearch.timeout
    case ShortcutTagMutation.shortcutName:
      return ShortcutTagMutation.timeout
    case ShortcutHierarchyMutation.shortcutName:
      return ShortcutHierarchyMutation.timeout
    default:
      return 60
    }
  }

  private static func category(for shortcutName: String) -> String {
    switch shortcutName {
    case ShortcutTagSearch.shortcutName:
      return "search"
    case ShortcutTagMutation.shortcutName:
      return "tag mutation"
    case ShortcutHierarchyMutation.shortcutName:
      return "hierarchy mutation"
    default:
      return "Shortcut execution"
    }
  }

  private static func installGuidance(for shortcutName: String) -> String {
    switch shortcutName {
    case ShortcutTagMutation.shortcutName:
      return "Install the tag mutation helper and see the README."
    case ShortcutHierarchyMutation.shortcutName:
      return "Install the hierarchy mutation helper and see the README."
    default:
      return "Reinstall the bundled .shortcut file and see the README."
    }
  }

  private static func decodeJSONObject(_ rawOutput: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(rawOutput.utf8))
    guard let dictionary = object as? [String: Any] else {
      Issue.record("Shortcut output was not a JSON object: \(rawOutput)")
      return [:]
    }
    return dictionary
  }

  private static func captureStandardStreams(
    operation: () async throws -> Int32
  ) async throws -> CapturedCommandResult {
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdoutReader = PipeOutputReader(fileHandle: stdoutPipe.fileHandleForReading)
    let stderrReader = PipeOutputReader(fileHandle: stderrPipe.fileHandleForReading)
    let savedStdout = dup(STDOUT_FILENO)
    let savedStderr = dup(STDERR_FILENO)
    precondition(savedStdout != -1 && savedStderr != -1, "Failed to duplicate standard file descriptors")

    fflush(stdout)
    fflush(stderr)
    dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

    let result: Result<Int32, Error>
    do {
      result = .success(try await operation())
    } catch {
      result = .failure(error)
    }

    fflush(stdout)
    fflush(stderr)
    dup2(savedStdout, STDOUT_FILENO)
    dup2(savedStderr, STDERR_FILENO)
    close(savedStdout)
    close(savedStderr)

    try? stdoutPipe.fileHandleForWriting.close()
    try? stderrPipe.fileHandleForWriting.close()

    let stdoutData = stdoutReader.waitForData()
    let stderrData = stderrReader.waitForData()

    let exitCode = try result.get()

    return CapturedCommandResult(
      exitCode: exitCode,
      stdout: String(decoding: stdoutData, as: UTF8.self),
      stderr: String(decoding: stderrData, as: UTF8.self)
    )
  }
}

private final class PipeOutputReader: @unchecked Sendable {
  private let group = DispatchGroup()
  private let queue: DispatchQueue
  private var data = Data()

  init(fileHandle: FileHandle) {
    queue = DispatchQueue(label: "remindctl.tests.pipe-output-reader.\(UUID().uuidString)")
    group.enter()
    queue.async { [self] in
      data = fileHandle.readDataToEndOfFile()
      group.leave()
    }
  }

  func waitForData() -> Data {
    group.wait()
    return data
  }
}
