import AppKit
import SwiftUI
import Testing

@testable import tian

@MainActor
struct WindowVisibilityStateTests {
    @Test func defaultsToVisible() {
        let state = WindowVisibilityState()
        #expect(state.isVisible)
    }

    @Test func emptyOcclusionStateHidesWindow() {
        let state = WindowVisibilityState()
        state.update(from: [])
        #expect(!state.isVisible)
    }

    @Test func visibleOcclusionStateShowsWindow() {
        let state = WindowVisibilityState()
        state.update(from: [])
        state.update(from: .visible)
        #expect(state.isVisible)
    }

    @Test func redundantUpdateKeepsValueStable() {
        let state = WindowVisibilityState()
        state.update(from: .visible)
        #expect(state.isVisible)
        state.update(from: [])
        state.update(from: [])
        #expect(!state.isVisible)
    }

    @Test func environmentDefaultsAreVisible() {
        let env = EnvironmentValues()
        #expect(env.windowIsVisible)
        #expect(env.sessionIsVisible)
    }
}

@MainActor
struct SystemMonitorLifecycleTests {
    /// Exercises the shared singleton's start/stop lifecycle. Runs as one
    /// test (not several) so the shared state transitions in a fixed order,
    /// and ends in the started state to match the app's steady state.
    @Test func startStopLifecycle() {
        let monitor = SystemMonitor.shared
        let wasRunning = monitor.isRunning

        monitor.start()
        #expect(monitor.isRunning)
        monitor.start()  // idempotent
        #expect(monitor.isRunning)

        monitor.stop()
        #expect(!monitor.isRunning)
        monitor.stop()  // no-op when stopped
        #expect(!monitor.isRunning)

        monitor.start()
        #expect(monitor.isRunning)

        if !wasRunning {
            monitor.stop()
        }
    }
}
