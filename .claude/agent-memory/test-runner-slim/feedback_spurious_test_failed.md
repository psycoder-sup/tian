---
name: xcodebuild spurious TEST FAILED
description: xcodebuild exits non-zero with ** TEST FAILED ** due to a passcode-locked iOS device connected to the Mac, even when all macOS test suites pass
type: feedback
---

xcodebuild may print `** TEST FAILED **` and exit 65 even when every test suite and every individual test reports `passed`. The root cause is a connected iOS device being passcode-locked, which triggers a `DTDKRemoteDeviceConnection` error in the xcodebuild output.

**Why:** The test scheme targets macOS (arm64), but xcodebuild still attempts to contact connected devices for notification_proxy setup. The passcode-lock blocks that handshake, causing the process to exit non-zero.

**How to apply:** When parsing xcodebuild test output, check individual test and suite results (`passed after` / `failed after`) rather than relying solely on the final `** TEST FAILED **` / `** TEST SUCCEEDED **` banner. If all suites pass and the only failure-related line is a `DTDKRemoteDeviceConnection` / `com.apple.mobile.notification_proxy` error, treat the test run as passing.
