# File Logging for Selected Categories

## Problem

tian uses `os.Logger` (unified logging) for all log output. macOS does not persist `info`/`debug`/`warning` level messages, so when the IPC server silently died, there was zero forensic evidence. Post-mortem debugging requires logs that survive past the current Console.app session.

## Design

Add a file logging layer that dual-writes to both `os.Logger` and a log file for selected categories.

### Components

**`FileLogWriter`** (new file: `tian/Utilities/FileLogWriter.swift`)
- Singleton (`@unchecked Sendable`) managing file I/O for `~/Library/Logs/tian/tian.log`
- Serial `DispatchQueue` for thread-safe writes
- Rotates when file exceeds 5MB; keeps current + 1 backup (`tian.1.log`)
- Line format: `2026-04-11 20:03:10.123 [ERROR] [ipc] message`
- Creates log directory on init if missing
- Silent failure throughout — logging errors must never crash the app

**`FileLogger`** (new file: `tian/Utilities/FileLogger.swift`)
- `Sendable` struct wrapping an `os.Logger` + reference to `FileLogWriter.shared`
- Methods: `debug()`, `info()`, `warning()`, `error()` — all take `String`
- Each call forwards to both `os.Logger` and `FileLogWriter`

### Changes to Existing Code

**`Logger.swift`** — Three categories switch from `Logger` to `FileLogger`:
- `ipc` — IPC server lifecycle, accept errors, socket recovery
- `lifecycle` — App launch, window close, quit flow
- `persistence` — Session save/restore

All other categories (`core`, `view`, `ghostty`, `perf`, `worktree`, `git`) remain `os.Logger` only.

### No Call-Site Changes

Existing `Log.ipc.info("message \(value)")` calls work unchanged. Swift resolves the string interpolation to `String` when the receiver is `FileLogger` instead of `os.Logger`.

## Scope

- 2 new files, 1 modified file
- No changes to any log call sites
