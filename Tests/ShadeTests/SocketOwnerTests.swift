import Foundation
import Network
import XCTest
@testable import Shade

/// SocketOwner.find is how Agent Traffic tells which card a connection came from. It's correct, but it lists
/// every process on the Mac and every socket of the card's process tree — and it runs on the main thread, once per
/// proxied connection and once per model call. These tests check that it still works and report what it costs.
final class SocketOwnerTests: XCTestCase {
    private var listener: NWListener!
    private var listenerPort: UInt16 = 0
    private var accepted: [NWConnection] = []
    private var clientPorts: [UInt16] = []
    private let queue = DispatchQueue(label: "shade.tests.socketowner")

    /// A loopback listener on a free port; records the client's port of every connection it accepts.
    private func startListener() throws -> XCTestExpectation {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
        let ready = expectation(description: "listening")
        let connected = expectation(description: "client connected")
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = self?.listener.port?.rawValue {
                self?.listenerPort = port
                ready.fulfill()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            if case .hostPort(_, let port) = connection.endpoint { self.clientPorts.append(port.rawValue) }
            self.accepted.append(connection)
            connection.start(queue: self.queue)
            connected.fulfill()
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)
        return connected
    }

    override func tearDown() {
        accepted.forEach { $0.cancel() }
        listener?.cancel()
        super.tearDown()
    }

    /// Like a program in a terminal card: a child process (nc, standing in for node or curl) connects, and the
    /// lookup has to find it below the card's shell (here: this test process).
    func testFindsConnectionOfChildProcess() throws {
        let connected = try startListener()
        let nc = Process()
        nc.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        nc.arguments = ["127.0.0.1", String(listenerPort)]
        let stdin = Pipe()
        nc.standardInput = stdin // keeps nc connected until we close it
        nc.standardOutput = FileHandle.nullDevice
        try nc.run()
        defer {
            try? stdin.fileHandleForWriting.close()
            nc.terminate()
        }
        wait(for: [connected], timeout: 5)
        let clientPort = try XCTUnwrap(queue.sync { clientPorts.first })

        let found = SocketOwner.find(localPort: clientPort, remotePort: listenerPort, under: [getpid()])
        XCTAssertEqual(found?.pid, nc.processIdentifier)
        XCTAssertEqual(found?.shell, getpid())
        XCTAssertEqual(SocketOwner.name(of: nc.processIdentifier), "nc")

        let cost = medianTime { _ = SocketOwner.find(localPort: clientPort, remotePort: listenerPort, under: [getpid()]) }
        print("SocketOwner.find: \(ms(cost)) per lookup, on the main thread in Shade")
        // Not a frame budget: a sanity bound. The real problem is the count — see RelayStabilityTests.
        XCTAssertLessThan(cost, 0.05, "one caller lookup takes \(ms(cost))")
    }

    func testUnknownPortIsNotFound() {
        XCTAssertNil(SocketOwner.find(localPort: 1, remotePort: 1, under: [getpid()]))
        XCTAssertNil(SocketOwner.find(localPort: 1, remotePort: 1, under: []))
    }
}
