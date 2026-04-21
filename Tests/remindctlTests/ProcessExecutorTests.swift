import Foundation
import Testing

@testable import remindctl

struct ProcessExecutorTests {
  @Test("Process executor returns normally before timeout")
  func processReturnsBeforeTimeout() throws {
    let result = try ProcessExecutor.run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "printf ok"],
      timeout: 5
    )

    #expect(result.status == 0)
    #expect(result.stdout == "ok")
    #expect(result.stderr.isEmpty)
  }

  @Test("Process executor times out and terminates long-running commands")
  func processTimeoutTerminatesCommand() throws {
    do {
      _ = try ProcessExecutor.run(
        executableURL: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["5"],
        timeout: 0.1
      )
      Issue.record("Expected /bin/sleep to time out")
    } catch let error as ProcessExecutionError {
      guard case .timedOut(let executablePath, let arguments, let timeout, let terminationStatus) = error else {
        Issue.record("Unexpected ProcessExecutionError: \(error)")
        return
      }
      let description = try #require(error.errorDescription)

      #expect(executablePath == "/bin/sleep")
      #expect(arguments == ["5"])
      #expect(timeout == 0.1)
      #expect(terminationStatus != nil)
      #expect(description.contains("/bin/sleep"))
      #expect(description.contains("timed out"))
      #expect(description.contains("termination_status="))
    }
  }
}
