import Foundation

struct ProcessResult: Sendable, Equatable {
  let status: Int32
  let stdout: String
  let stderr: String
}

enum ProcessExecutor {
  static func run(executableURL: URL, arguments: [String], stdin: String? = nil) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    if let stdin {
      stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
    }
    try? stdinPipe.fileHandleForWriting.close()

    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
      status: process.terminationStatus,
      stdout: String(decoding: stdoutData, as: UTF8.self),
      stderr: String(decoding: stderrData, as: UTF8.self)
    )
  }
}
