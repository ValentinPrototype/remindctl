import Darwin
import Foundation

struct ProcessResult: Sendable, Equatable {
  let status: Int32
  let stdout: String
  let stderr: String
}

enum ProcessExecutionError: LocalizedError, Sendable, Equatable {
  case timedOut(
    executablePath: String,
    arguments: [String],
    timeout: TimeInterval,
    terminationStatus: Int32?
  )

  var errorDescription: String? {
    switch self {
    case .timedOut(let executablePath, let arguments, let timeout, let terminationStatus):
      let command = ([executablePath] + arguments).joined(separator: " ")
      let status = terminationStatus.map(String.init) ?? "still running after terminate"
      return "Process timed out after \(ProcessExecutor.formatTimeout(timeout))s: \(command) (termination_status=\(status))"
    }
  }
}

enum ProcessExecutor {
  static func run(
    executableURL: URL,
    arguments: [String],
    stdin: String? = nil,
    timeout: TimeInterval? = nil
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdoutReader = ProcessPipeReader(fileHandle: stdoutPipe.fileHandleForReading)
    let stderrReader = ProcessPipeReader(fileHandle: stderrPipe.fileHandleForReading)
    let termination = DispatchSemaphore(value: 0)

    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.terminationHandler = { _ in
      termination.signal()
    }

    try process.run()

    if let stdin {
      stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
    }
    try? stdinPipe.fileHandleForWriting.close()

    if let timeout {
      let deadline = DispatchTime.now() + timeout
      if termination.wait(timeout: deadline) == .timedOut {
        process.terminate()
        if termination.wait(timeout: .now() + .seconds(2)) == .timedOut {
          kill(process.processIdentifier, SIGKILL)
          _ = termination.wait(timeout: .now() + .seconds(1))
        }

        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        _ = stdoutReader.waitForData()
        _ = stderrReader.waitForData()

        throw ProcessExecutionError.timedOut(
          executablePath: executableURL.path,
          arguments: arguments,
          timeout: timeout,
          terminationStatus: process.isRunning ? nil : process.terminationStatus
        )
      }
    } else {
      process.waitUntilExit()
    }

    let stdoutData = stdoutReader.waitForData()
    let stderrData = stderrReader.waitForData()

    return ProcessResult(
      status: process.terminationStatus,
      stdout: String(decoding: stdoutData, as: UTF8.self),
      stderr: String(decoding: stderrData, as: UTF8.self)
    )
  }

  static func formatTimeout(_ timeout: TimeInterval) -> String {
    if timeout.rounded() == timeout {
      return "\(Int(timeout))"
    }
    return String(format: "%.3f", timeout)
  }
}

private final class ProcessPipeReader: @unchecked Sendable {
  private let group = DispatchGroup()
  private let queue: DispatchQueue
  private var data = Data()

  init(fileHandle: FileHandle) {
    queue = DispatchQueue(label: "remindctl.process-pipe-reader.\(UUID().uuidString)")
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
