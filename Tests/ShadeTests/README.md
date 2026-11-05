# Shade tests

```sh
# Quit Shade first: the relay tests listen on port 18090.
swift test                                   # everything
swift test --filter Parsing                  # quick logic tests only
swift test --filter Stability 2>&1 | grep -E "Test Case|→|stall|ms|error"   # the diagnostics with their numbers
```

| File | What it checks |
|---|---|
| `ParsingTests.swift` | `git status` parsing, the relay's HTTP parser (Content-Length, chunked, pipelined, CONNECT), Agent Traffic limits. Should pass today. |
| `SocketOwnerTests.swift` | The caller lookup still finds a child process's connection; prints what one lookup costs. |
| `RelayStabilityTests.swift` | Offline behavior of the proxy and the main-thread cost of Agent Traffic over long sessions. |
| `TerminalStabilityTests.swift` | Real shells (zsh without your profile): startup, title-update storms, output floods, cleanup. |

Tests marked **REPRODUCES** are expected to **fail on the current code**; each failure message says what it measured.
They are the acceptance criteria for the fixes:

| Test | Fails today because | Passes when |
|---|---|---|
| `testOfflineRetryStormKeepsMainThreadResponsive` | every proxied connection scans all processes on the main thread | caller lookup moves off the main thread (or is cached per client port / shell tree) |
| `testStreamingAppendCostIsLinear` | each streamed chunk copies the @Published array and the whole body so far | chunks are buffered outside the published array |
| `testStreamingDoesNotPublishPerChunk` | each chunk publishes `exchanges`, re-rendering the whole panel | updates are coalesced (e.g. every 250 ms) |
| `testTrafficListRenderCost` | each list row parses its full request and response JSON on every render | summaries are cached per exchange; then swap this measurement for a test that the row reads the cache |
| `testTitleAnimationIsCoalesced` | every terminal-title change re-renders the whole panel | title updates are coalesced or skipped when unchanged on screen |

Timing thresholds are deliberately generous (one frame = 16 ms, a noticeable stall = 100 ms) and compare ratios where
possible, so they don't depend much on the Mac.
