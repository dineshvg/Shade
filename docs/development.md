# Development

## Building

Requirements: macOS 15 or later and Xcode 26+ (Swift 6.2, or matching Command Line Tools).

| Command | Does |
|---|---|
| `./scripts/install.sh` | Builds the app, moves it to `/Applications` and starts it |
| `./scripts/bundle.sh` | Builds the app into `build/` without installing it |
| `swift run` | Runs from source (can't post notifications) |
| `open Package.swift` | Opens the package in Xcode |

Coming from **Drop Prompter** (Shade's earlier name)? `install.sh` removes the old app, and Shade copies your cards
and settings over on its first launch. If you used *Launch at login*, turn it on again in ⚙︎.

## Code layout

| File | What it does |
|---|---|
| `AppDelegate.swift` | Panel, menu bar item, show/hide animation, shortcut, resizing |
| `ContentView.swift` | Toolbar, cards, editor, translation, settings |
| `WindowButtons.swift` | The close, roll-up and maximize buttons |
| `Terminal.swift` | Terminal cards (built on [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) and noticing when one needs you |
| `Notifier.swift` | macOS notifications for terminal cards |
| `Sandbox.swift` | Sandbox profiles for sandboxed terminal cards |
| `AgentTraffic.swift`, `TrafficView.swift` | The relay and proxy that record model API calls and connections, and the Agent Traffic card |
| `Repo.swift`, `RepoViews.swift` | Repository detection, sidebar, diffs, file cards and Quick Open |
| `FileBuffers.swift` | Editing, saving and conflict handling for file cards |
| `MarkdownPreview.swift` | Renders Markdown files for the preview in file cards |
| `SyntaxHighlighting.swift`, `Highlightr/` | Syntax highlighting (highlight.js via an adapted Highlightr), themes and downloads |
| `HotKey.swift` | Global shortcut and conflict detection |
| `Theme.swift` | Dark, Light and Paper themes |
| `scripts/make_icon.py` | Draws the app icon (`Resources/AppIcon.png` / `.icns`) with Pillow |
| `scripts/release.sh` | Builds a signed, notarized DMG for a release |

Issues and pull requests are welcome.

## Customizing syntax highlighting

- **Themes**: ⚙︎ › Syntax Highlighting › *Get More Themes…* lists every theme of the bundled highlight.js release
  (11.11.1). Downloaded themes go to `~/Library/Application Support/Shade/Highlighting/themes`; you can also drop
  any highlight.js theme `.css` file there.
- **Languages**: about 190 are built in. For another one, put its highlight.js *browser build* (a `.js` file that
  calls `hljs.registerLanguage`) into `~/Library/Application Support/Shade/Highlighting/languages` and restart
  Shade. *Open Folder* in ⚙︎ takes you there.
- Files over 500 KB stay plain so typing stays fast.

## Making a release

Needs an Apple Developer Program membership. Once: create a *Developer ID Application* certificate (Xcode ›
Settings › Accounts › Manage Certificates) and store notarization credentials with
`xcrun notarytool store-credentials shade-notary --apple-id <apple-id> --team-id <TEAMID>`.

The version lives in one place, the [`VERSION`](../VERSION) file. `bundle.sh`, `install.sh` and `release.sh` read it,
so the About window, Finder, the DMG name and the tag all agree. To release:

1. Bump `VERSION` in a pull request and merge it.
2. Tag the merge and build the DMG:

```bash
git tag -a v1.0.0 -m "Shade 1.0.0" && git push origin v1.0.0
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
gh release create v1.0.0 build/Shade-1.0.0.dmg --title "Shade 1.0.0" --generate-notes
```
