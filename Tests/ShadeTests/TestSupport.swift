import Foundation
import Network
import XCTest

/// Measures how long the main run loop was blocked: a timer that should fire every `interval` records the
/// largest gap it saw. A user feels anything above ~100 ms as lag, above ~1 s as "stuck".
@MainActor
final class MainThreadWatchdog {
    private var timer: Timer?
    private var last = Date()
    private(set) var maxGap: TimeInterval = 0
    private(set) var ticks = 0

    func start(interval: TimeInterval = 0.01) {
        last = Date()
        maxGap = 0
        ticks = 0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                self.maxGap = max(self.maxGap, now.timeIntervalSince(self.last))
                self.last = now
                self.ticks += 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// A raw TCP client that runs on its own queue, so it keeps working while the main thread is busy.
/// Sends `request` once and collects everything until the server closes or `timeout` passes.
final class RawClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "shade.tests.rawclient")
    private let connection: NWConnection
    private var received = Data()
    private let done: XCTestExpectation
    private(set) var localPort: UInt16?
    private(set) var firstByteAt: Date?
    let startedAt = Date()

    init(port: UInt16, request: Data, done: XCTestExpectation) {
        self.done = done
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if case .hostPort(_, let port) = self.connection.currentPath?.localEndpoint {
                    self.localPort = port.rawValue
                }
                self.connection.send(content: request, completion: .contentProcessed { _ in })
                self.receive()
            case .failed, .cancelled:
                self.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    var response: String { queue.sync { String(decoding: received, as: UTF8.self) } }
    var statusLine: String { response.components(separatedBy: "\r\n").first ?? "" }

    func cancel() { connection.cancel() }

    private var isFinished = false
    /// Called on `queue` only.
    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        done.fulfill()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                if self.firstByteAt == nil { self.firstByteAt = Date() }
                self.received.append(data)
            }
            if isComplete || error != nil {
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }
}

/// Median wall time of `body`, after one warm-up run.
func medianTime(runs: Int = 9, _ body: () -> Void) -> TimeInterval {
    body()
    var times: [TimeInterval] = []
    for _ in 0..<runs {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
    }
    return times.sorted()[times.count / 2]
}

func ms(_ seconds: TimeInterval) -> String { String(format: "%.1f ms", seconds * 1000) }
