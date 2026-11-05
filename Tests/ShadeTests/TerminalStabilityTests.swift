import Combine
import Foundation
import XCTest
@testable import Shade

/// Terminal cards under long-running agents. These start real shells (zsh with an empty ZDOTDIR, so your own
/// profile isn't involved) and drive them the way Claude Code and Copilot CLI do.
@MainActor
final class TerminalStabilityTests: XCTestCase {
    /// Runs `body` with a predictable login shell: /bin/zsh without the user's startup files.
    private func withCleanShell(_ body: () throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shade-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Empty startup files, so zsh doesn't offer its first-run setup menu.
        for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data())
        }
        let saved = (shell: ProcessInfo.processInfo.environment["SHELL"],
                     zdotdir: ProcessInfo.processInfo.environment["ZDOTDIR"])
        setenv("SHELL", "/bin/zsh", 1)
        setenv("ZDOTDIR", directory.path, 1)
        defer {
            if let shell = saved.shell { setenv("SHELL", shell, 1) } else { unsetenv("SHELL") }
            if let zdotdir = saved.zdotdir { setenv("ZDOTDIR", zdotdir, 1) } else { unsetenv("ZDOTDIR") }
            try? FileManager.default.removeItem(at: directory)
        }
        try body()
    }

    /// Spins the main run loop (where the shell's output is read) until `condition` holds.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return true
    }

    func testShellStartsAndRunsInitialCommand() throws {
        try withCleanShell {
            let sessions = TerminalSessions()
            let card = UUID()
            sessions.run("printf '\\033]0;shade-ready\\007'", whenStarting: card)
            _ = sessions.view(for: card)
            defer { sessions.close(card) }
            XCTAssertTrue(waitUntil(timeout: 10) { sessions.titles[card] == "shade-ready" },
                          "the shell didn't start or didn't run the command; title: \(sessions.titles[card] ?? "nil")")
            XCTAssertNil(sessions.runningProgram(in: card), "an idle shell has no foreground program")
        }
    }

    /// REPRODUCES a source of constant re-rendering. Claude Code and Copilot CLI animate a spinner in the terminal
    /// title, many times a second, for as long as they work. Each title change publishes `titles`, and ContentView
    /// (the whole panel: tab bar, sidebar, file tree) observes TerminalSessions, so the whole panel re-renders for
    /// every spinner frame — hours of it in a long session, also while the panel is hidden.
    func testTitleAnimationIsCoalesced() throws {
        try withCleanShell {
            let sessions = TerminalSessions()
            let card = UUID()
            sessions.visibleCardID = card
            // 500 title changes as fast as the shell can print them, then a marker.
            sessions.run("for i in {1..500}; do printf '\\033]0;spinner %d\\007' $i; done; "
                + "sleep 1; printf '\\033]0;done\\007'", whenStarting: card)
            var publishes = 0
            let subscription = sessions.objectWillChange.sink { publishes += 1 }
            _ = sessions.view(for: card)
            defer {
                subscription.cancel()
                sessions.close(card)
            }
            XCTAssertTrue(waitUntil(timeout: 20) { sessions.titles[card] == "done" })
            print("500 title changes → \(publishes) objectWillChange notifications (each re-renders the panel)")
            XCTAssertLessThanOrEqual(publishes, 60, "every title change re-renders the whole panel")
        }
    }

    /// A card in the background streaming lots of output (a build, an agent at work) must not stall the UI.
    /// Also exercises the per-chunk bookkeeping (unseen-output dot, throttled repository refresh).
    func testBackgroundOutputFloodKeepsMainThreadResponsive() throws {
        try withCleanShell {
            let sessions = TerminalSessions()
            let card = UUID()
            sessions.visibleCardID = nil
            sessions.run("yes 'Compiling module Shade with a fairly long line of output' | head -n 100000; "
                + "printf '\\033]0;flood-done\\007'", whenStarting: card)
            _ = sessions.view(for: card)
            defer { sessions.close(card) }
            let watchdog = MainThreadWatchdog()
            watchdog.start()
            XCTAssertTrue(waitUntil(timeout: 60) { sessions.titles[card] == "flood-done" })
            watchdog.stop()
            print("100k lines in a background card: longest main-thread stall \(ms(watchdog.maxGap))")
            XCTAssertTrue(sessions.unseenOutput.contains(card))
            XCTAssertLessThan(watchdog.maxGap, 0.25, "the main thread stalled for \(ms(watchdog.maxGap))")
        }
    }

    /// `exit` restarts the shell; closing a card must not, and must leave no state behind.
    func testClosingCardCleansUp() throws {
        try withCleanShell {
            let sessions = TerminalSessions()
            let card = UUID()
            sessions.run("printf '\\033]0;up\\007'", whenStarting: card)
            _ = sessions.view(for: card)
            XCTAssertTrue(waitUntil(timeout: 10) { sessions.titles[card] == "up" })
            sessions.close(card)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            XCTAssertNil(sessions.titles[card])
            XCTAssertNil(sessions.repos[card])
            XCTAssertFalse(sessions.unseenOutput.contains(card))
            XCTAssertTrue(sessions.runningPrograms.isEmpty)
        }
    }
}
