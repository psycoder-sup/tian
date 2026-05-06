import Foundation
import Testing

struct PollTimeoutError: Error {}

@MainActor
func pollUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock().now.advanced(by: timeout)
    while ContinuousClock().now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw PollTimeoutError()
}
