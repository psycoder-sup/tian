import Foundation

final class PTYProcess: Sendable {
    let masterFD: Int32
    let childPID: pid_t
    private let processSource: DispatchSourceProcess
    private let exitContinuation: AsyncStream<Int32>.Continuation
    let exitStream: AsyncStream<Int32>

    init(columns: UInt16 = 80, rows: UInt16 = 24) throws {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw PTYError.openptyFailed(errno)
        }

        var winsize = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &winsize)

        let shellPath = PTYProcess.defaultShell()
        let shellName = "-" + (shellPath as NSString).lastPathComponent

        let env = PTYProcess.buildEnvironment(columns: columns, rows: rows)

        let pid = pty_fork()
        guard pid >= 0 else {
            close(masterFD)
            close(slaveFD)
            throw PTYError.forkFailed(errno)
        }

        if pid == 0 {
            // Child process
            close(masterFD)
            setsid()
            _ = ioctl(slaveFD, TIOCSCTTY, 0)
            dup2(slaveFD, STDIN_FILENO)
            dup2(slaveFD, STDOUT_FILENO)
            dup2(slaveFD, STDERR_FILENO)
            if slaveFD > STDERR_FILENO {
                close(slaveFD)
            }

            for (key, value) in env {
                setenv(key, value, 1)
            }

            shellPath.withCString { path in
                shellName.withCString { name in
                    var argv: [UnsafeMutablePointer<CChar>?] = [
                        UnsafeMutablePointer(mutating: name),
                        nil,
                    ]
                    execvp(path, &argv)
                    _exit(127)
                }
            }
            _exit(127)
        }

        // Parent process
        close(slaveFD)
        self.masterFD = masterFD
        self.childPID = pid

        var continuation: AsyncStream<Int32>.Continuation!
        self.exitStream = AsyncStream { continuation = $0 }
        self.exitContinuation = continuation

        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: .global(qos: .utility)
        )
        self.processSource = source

        let cont = self.exitContinuation
        source.setEventHandler {
            var status: Int32 = 0
            // Use WNOHANG to avoid blocking forever if terminate() already reaped
            let result = waitpid(pid, &status, WNOHANG)
            let exitCode: Int32
            if result == pid {
                exitCode = pty_wifexited(status) != 0 ? pty_wexitstatus(status) : -1
            } else {
                exitCode = -1
            }
            cont.yield(exitCode)
            cont.finish()
        }
        source.setCancelHandler { }
        source.resume()

        Log.pty.info("Spawned shell \(shellPath) with PID \(pid)")
    }

    func resize(columns: UInt16, rows: UInt16) {
        var winsize = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &winsize)
        // Send SIGWINCH to the foreground process group on this PTY
        let pgrp = tcgetpgrp(masterFD)
        if pgrp > 0 {
            kill(-pgrp, SIGWINCH)
        }
    }

    func terminate() {
        processSource.cancel()
        kill(childPID, SIGHUP)
        close(masterFD)
        // WNOHANG poll with SIGKILL fallback to avoid blocking forever
        var status: Int32 = 0
        var reaped = false
        for _ in 0..<50 {
            let result = waitpid(childPID, &status, WNOHANG)
            if result == childPID || (result == -1 && errno == ECHILD) {
                reaped = true
                break
            }
            usleep(10_000)
        }
        if !reaped {
            kill(childPID, SIGKILL)
            waitpid(childPID, &status, 0)
        }
        Log.pty.info("Shell PID \(self.childPID) terminated")
    }

    deinit {
        processSource.cancel()
    }

    // MARK: - Private

    private static func defaultShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            return String(cString: shell)
        }
        return "/bin/zsh"
    }

    private static func buildEnvironment(columns: UInt16, rows: UInt16) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["COLUMNS"] = "\(columns)"
        env["LINES"] = "\(rows)"
        env.removeValue(forKey: "TERM_PROGRAM")
        env.removeValue(forKey: "TERM_PROGRAM_VERSION")
        if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }
        return env
    }
}

enum PTYError: Error, LocalizedError {
    case openptyFailed(Int32)
    case forkFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .openptyFailed(let code):
            return "openpty() failed with errno \(code): \(String(cString: strerror(code)))"
        case .forkFailed(let code):
            return "fork() failed with errno \(code): \(String(cString: strerror(code)))"
        }
    }
}
