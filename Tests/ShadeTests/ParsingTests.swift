import Foundation
import XCTest
@testable import Shade

/// Pure-logic tests: a safety net for the fixes, independent of timing.
final class RepoParsingTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)

    func testBranchFromTrackingHeader() {
        XCTAssertEqual(Repo.branchName(fromHeader: "main...origin/main [ahead 1]"), "main")
        XCTAssertEqual(Repo.branchName(fromHeader: "feature/x"), "feature/x")
        XCTAssertEqual(Repo.branchName(fromHeader: "No commits yet on main"), "main")
        XCTAssertEqual(Repo.branchName(fromHeader: "HEAD (no branch)"), "detached HEAD")
    }

    func testStatusSkipsOriginalPathOfRenames() {
        let output = "## main...origin/main\0 M Sources/a.swift\0R  new.swift\0old.swift\0?? notes.md\0"
        let status = Repo.parseStatus(output, root: root)
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.changes.map(\.path), ["Sources/a.swift", "new.swift", "notes.md"])
        XCTAssertEqual(status.changes.map(\.badge), ["M", "R", "U"])
    }

    func testStatusOfCleanRepository() {
        let status = Repo.parseStatus("## main\0", root: root)
        XCTAssertEqual(status.changes, [])
    }
}

final class HTTPRequestParsingTests: XCTestCase {
    func testWaitsForCompleteHeaders() {
        XCTAssertNil(HTTPRequest.parse(Data("POST /card/x HTTP/1.1\r\nContent-Length: 5\r\n".utf8)))
    }

    func testWaitsForCompleteBody() {
        XCTAssertNil(HTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nab".utf8)))
    }

    func testContentLengthBodyAndPipelinedRest() throws {
        let raw = Data("POST /v1 HTTP/1.1\r\ncontent-length: 5\r\nX-A: 1\r\n\r\nhelloGET /next HTTP/1.1\r\n\r\n".utf8)
        let parsed = try XCTUnwrap(HTTPRequest.parse(raw))
        XCTAssertEqual(parsed.request.method, "POST")
        XCTAssertEqual(parsed.request.target, "/v1")
        XCTAssertEqual(parsed.request.header("Content-Length"), "5")
        XCTAssertEqual(String(decoding: parsed.request.body, as: UTF8.self), "hello")
        // The second request stays in the buffer for the next round.
        let rest = raw.dropFirst(parsed.length)
        XCTAssertEqual(try XCTUnwrap(HTTPRequest.parse(Data(rest))).request.target, "/next")
    }

    func testChunkedBody() throws {
        let raw = Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\n\r\n".utf8)
        let parsed = try XCTUnwrap(HTTPRequest.parse(raw))
        XCTAssertEqual(String(decoding: parsed.request.body, as: UTF8.self), "hello world")
        XCTAssertEqual(parsed.length, raw.count)
    }

    func testIncompleteChunkedBodyWaits() {
        XCTAssertNil(HTTPRequest.parse(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel".utf8)))
    }

    func testConnectRequest() throws {
        let parsed = try XCTUnwrap(HTTPRequest.parse(Data("CONNECT api.github.com:443 HTTP/1.1\r\nHost: x\r\n\r\n".utf8)))
        XCTAssertEqual(parsed.request.method, "CONNECT")
        XCTAssertEqual(parsed.request.target, "api.github.com:443")
        XCTAssertTrue(parsed.request.body.isEmpty)
    }
}

@MainActor
final class AgentTrafficStoreTests: XCTestCase {
    private func exchange(connection: Bool, body: Int = 0) -> TrafficExchange {
        TrafficExchange(cardID: nil, started: Date(), provider: connection ? nil : .anthropic, host: "h", port: 443,
                        method: "POST", path: "/", process: nil, isAgent: !connection,
                        requestBody: Data(count: body))
    }

    func testKeepsAtMostLimitPerKind() {
        let traffic = AgentTraffic()
        for _ in 0..<(AgentTraffic.limit + 20) { traffic.record(exchange(connection: false)) }
        for _ in 0..<(AgentTraffic.connectionLimit + 20) { traffic.record(exchange(connection: true)) }
        XCTAssertEqual(traffic.exchanges.filter { !$0.isConnection }.count, AgentTraffic.limit)
        XCTAssertEqual(traffic.exchanges.filter(\.isConnection).count, AgentTraffic.connectionLimit)
    }

    func testAgentHostMatching() {
        let traffic = AgentTraffic()
        XCTAssertTrue(traffic.isAgentHost("api.anthropic.com"))
        XCTAssertTrue(traffic.isAgentHost("API.GITHUB.COM"))
        XCTAssertFalse(traffic.isAgentHost("notanthropic.com"))
        XCTAssertFalse(traffic.isAgentHost("registry.npmjs.org"))
    }
}
