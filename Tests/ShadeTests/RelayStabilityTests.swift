import Combine
import Foundation
import Network
import XCTest
@testable import Shade

/// Agent Traffic under the conditions that were reported: no internet, and an app left open for a long time
/// with agents streaming. Everything in AgentTraffic runs on the main queue, so anything slow here is UI lag.
///
/// Quit Shade before running these: the relay listens on the fixed port 18090.
@MainActor
final class RelayStabilityTests: XCTestCase {
    /// Time spent identifying callers, i.e. scanning processes on the main thread.
    private final class LookupCost {
        var calls = 0
        var seconds = 0.0
    }

    /// A relay listening on 127.0.0.1:18090. Callers are identified like production does it — a scan of every
    /// process on the Mac — but are never restricted, so connections reach upstream instead of Strict's block.
    private func startRelay(cost: LookupCost = LookupCost()) throws -> AgentTraffic {
        let traffic = AgentTraffic()
        _ = traffic.environment(for: UUID())
        // A port that's taken only shows up asynchronously, in the listener's state handler.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let error = traffic.listenerError {
            traffic.stop()
            throw XCTSkip("Relay can't listen (quit Shade before running these tests): \(error)")
        }
        traffic.identifyCaller = { port in
            let start = Date()
            _ = SocketOwner.find(localPort: port, remotePort: AgentTraffic.port, under: [getpid()])
            cost.calls += 1
            cost.seconds += Date().timeIntervalSince(start)
            return AgentTraffic.Caller(cardID: UUID(), process: "test", restricted: false)
        }
        return traffic
    }

    private func connect(to target: String, expectation: XCTestExpectation) -> RawClient {
        RawClient(port: AgentTraffic.port,
                  request: Data("CONNECT \(target) HTTP/1.1\r\nHost: \(target)\r\n\r\n".utf8),
                  done: expectation)
    }

    // MARK: - Offline

    /// Offline, names don't resolve. The program must get an error right away instead of hanging.
    func testConnectToUnresolvableHostFailsFast() throws {
        let traffic = try startRelay()
        defer { traffic.stop() }
        let done = expectation(description: "response")
        let client = connect(to: "shade-test.invalid:443", expectation: done)
        wait(for: [done], timeout: 10)
        XCTAssertTrue(client.statusLine.hasPrefix("HTTP/1.1 502"), "got: \(client.statusLine)")
        XCTAssertLessThan(Date().timeIntervalSince(client.startedAt), 5)
        let recorded = traffic.exchanges.last
        XCTAssertNotNil(recorded?.error, "the failed connection should be recorded with its error")
        XCTAssertTrue(recorded?.isFinished == true, "a failed connection must not stay 'in progress' forever")
    }

    /// Offline, connections are refused. Same expectation as above.
    func testConnectRefusedFailsFast() throws {
        let traffic = try startRelay()
        defer { traffic.stop() }
        let done = expectation(description: "response")
        let client = connect(to: "127.0.0.1:1", expectation: done)
        wait(for: [done], timeout: 10)
        XCTAssertTrue(client.statusLine.hasPrefix("HTTP/1.1 502"), "got: \(client.statusLine)")
    }

    /// REPRODUCES the offline lag. Without internet, npm, gradle, git, brew, Claude Code and Copilot CLI all retry,
    /// so dozens of proxy connections arrive at once and fail at once. For each, Shade scans every process on the
    /// Mac (SocketOwner.find) on the main thread before it can answer.
    func testOfflineRetryStormKeepsMainThreadResponsive() throws {
        let cost = LookupCost()
        let traffic = try startRelay(cost: cost)
        defer { traffic.stop() }
        let watchdog = MainThreadWatchdog()
        watchdog.start()

        var clients: [RawClient] = []
        for wave in 0..<3 {
            let done = expectation(description: "wave \(wave)")
            done.expectedFulfillmentCount = 40
            for index in 0..<40 {
                let target = index.isMultiple(of: 2) ? "shade-test-\(index).invalid:443" : "127.0.0.1:1"
                clients.append(connect(to: target, expectation: done))
            }
            wait(for: [done], timeout: 30)
        }
        watchdog.stop()

        let average = cost.calls > 0 ? cost.seconds / Double(cost.calls) : 0
        print("Retry storm: \(cost.calls) caller lookups, \(ms(average)) each, \(ms(cost.seconds)) total on the main "
            + "thread; longest main-thread stall \(ms(watchdog.maxGap))")
        XCTAssertTrue(clients.allSatisfy { $0.statusLine.hasPrefix("HTTP/1.1 502") })
        XCTAssertLessThan(watchdog.maxGap, 0.1, "the main thread stalled for \(ms(watchdog.maxGap)) "
            + "(caller lookups: \(ms(cost.seconds)) in total) — this is the lag in the terminal")
    }

    // MARK: - Long sessions

    /// REPRODUCES the slowdown over long sessions. A streamed reply arrives in hundreds of small chunks and each one
    /// goes through `update`, which mutates an element of a @Published array. @Published has no in-place `_modify`,
    /// so every chunk copies the array and the whole response body so far: the cost grows with the square of the
    /// reply's length, all on the main thread. Doubling the chunks should double the time, not quadruple it.
    func testStreamingAppendCostIsLinear() {
        func streamCost(chunks: Int) -> TimeInterval {
            let traffic = AgentTraffic()
            // A realistic store: earlier calls with whole conversations in their requests.
            for _ in 0..<50 {
                traffic.record(TrafficExchange(cardID: nil, started: Date(), provider: .anthropic, host: "h", port: 443,
                                               method: "POST", path: "/v1/messages", process: nil, isAgent: true,
                                               requestBody: Data(count: 200_000)))
            }
            let id = traffic.exchanges.last!.id
            let chunk = Data(repeating: 0x61, count: 256)
            let start = Date()
            for _ in 0..<chunks { traffic.update(id) { $0.responseBody.append(chunk) } }
            return Date().timeIntervalSince(start)
        }
        let small = streamCost(chunks: 1_500)
        let large = streamCost(chunks: 3_000)
        print("Streaming 1500 chunks: \(ms(small)); 3000 chunks: \(ms(large)); ratio \(String(format: "%.1f", large / small))")
        XCTAssertLessThan(large / small, 3, "2× the chunks took \(String(format: "%.1f", large / small))× the time: "
            + "appending is quadratic (\(ms(large)) for a 768 KB reply)")
    }

    /// Every chunk and every byte-count update publishes `exchanges`, and ContentView (the whole panel) observes
    /// AgentTraffic, so the entire panel re-renders per chunk even when Agent Traffic isn't on screen.
    func testStreamingDoesNotPublishPerChunk() {
        let traffic = AgentTraffic()
        traffic.record(TrafficExchange(cardID: nil, started: Date(), provider: .anthropic, host: "h", port: 443,
                                       method: "POST", path: "/", process: nil, isAgent: true, requestBody: Data()))
        let id = traffic.exchanges[0].id
        var publishes = 0
        let subscription = traffic.objectWillChange.sink { publishes += 1 }
        for _ in 0..<1_000 { traffic.update(id) { $0.responseBody.append(Data(count: 64)) } }
        // Let any coalescing timer fire.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        subscription.cancel()
        print("1000 streamed chunks → \(publishes) objectWillChange notifications")
        XCTAssertLessThanOrEqual(publishes, 20, "each chunk re-renders the whole panel (\(publishes) publishes)")
    }

    /// Cost of what the Agent Traffic list does on every re-render: a TrafficSummary per visible row, each parsing
    /// the full request JSON and the full streamed response. Combined with the per-chunk publishing above, this is
    /// what freezes the panel when the Agent Traffic card is open during a long agent session.
    func testTrafficListRenderCost() throws {
        let conversation = (0..<400).map { index in
            ["role": index.isMultiple(of: 2) ? "user" : "assistant",
             "content": [["type": "text", "text": String(repeating: "word ", count: 500)]]] as [String: Any]
        }
        let request = try JSONSerialization.data(withJSONObject: ["model": "claude", "messages": conversation])
        let events = (0..<1_000).map { _ in #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hello "}}"# }
        let response = Data(events.joined(separator: "\n\n").utf8)
        var rows: [TrafficExchange] = []
        for _ in 0..<15 {
            var exchange = TrafficExchange(cardID: nil, started: Date(), provider: .anthropic, host: "h", port: 443,
                                           method: "POST", path: "/v1/messages", process: nil, isAgent: true,
                                           requestBody: request)
            exchange.responseBody = response
            rows.append(exchange)
        }
        let perRender = medianTime(runs: 3) { for row in rows { _ = TrafficSummary(row) } }
        print("Agent Traffic list, 15 visible rows of \(request.count / 1024) KB requests: \(ms(perRender)) per re-render")
        // One frame is 16 ms. Each streamed chunk triggers a re-render, so anything near this freezes the panel.
        XCTAssertLessThan(perRender, 0.016, "one re-render of the traffic list costs \(ms(perRender))")
    }
}
