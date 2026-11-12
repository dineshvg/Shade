# Security model

Shade itself makes no network calls and stores everything locally. Most of the security work is about **what
programs in terminal cards, especially AI agents, can do**.

## Sandboxed terminal cards

Run Claude Code, Copilot CLI or any other tool in a sandboxed terminal card (the 🛡 button next to **+**). You pick
the project folder; everything started in that card, the agent and every command it runs, is confined by macOS's
built-in sandbox.

| Mode | What it allows |
|---|---|
| **Project Only** | Changes only in the project folder, temp, tool caches (Gradle, npm, Kotlin/Native…) and the agents' own state. Everything else is read-only. |
| **Strict (No Network)** | The same, plus no network except to your own Mac. With **Record Agent Traffic**, programs can also reach agent services through Shade, and nothing else. |

In both modes:
- **Keys and credentials can't be read**: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.docker`, gcloud and GitHub
  CLI tokens, `.netrc`, `.npmrc`, `~/.gradle/gradle.properties` and similar.
- **No way out through files that run later**: folders on your `PATH` (`~/.local/bin`, `~/.cargo/bin`…), Gradle init
  scripts, git configuration and the project's `.git/hooks` and `.git/config`, and Claude Code's settings and
  `CLAUDE.md` can't be written, because they'd run outside the sandbox the next time you use them.
- The tab shows a green shield, and **Blocked Actions** opens a live log of everything the sandbox denied.

Good to know:
- The sandbox is fixed when the card starts, so `cd`-ing elsewhere doesn't widen it.
- Blocked on purpose: `git push` over SSH, installing with Homebrew, and builds that need secrets from
  `~/.gradle/gradle.properties`. Run those in a normal terminal card.
- It uses `sandbox-exec`, which Apple marks as deprecated but still ships and which tools like Chrome and coding
  agents rely on. It's a strong safety net, not a guarantee.
- Sandbox profiles are stored in `~/Library/Application Support/Shade/Sandbox`.

## What it doesn't protect against

- **Reading other files.** In *Project Only*, programs can still read the rest of your home folder, such as
  documents, other repositories and app data, and send it out. Use *Strict*, ideally with *Record Agent Traffic*, when
  nothing may leave your Mac.
- **Asking other apps to act.** A sandboxed program can still open a link in your browser, or, after macOS asks you,
  control other apps with AppleScript. Those apps run outside the sandbox. Decline automation prompts you didn't
  expect.
- **Bad changes inside the project.** The sandbox limits *where* an agent can write, not *what* it writes there.
  Review its changes in the sidebar before you build or commit them.
- **macOS vulnerabilities**, and the future of `sandbox-exec`: Apple marks it as deprecated; it still works on
  macOS 15 and 26.
- **Normal terminal cards**, which run with your full user permissions, like Terminal.app.

## Agent Traffic

Recorded calls contain your code and prompts. They stay in Shade's memory and are never written to disk. The relay
listens only on your Mac's loopback interface. Its proxy lets a program reach any host only when Shade traces the
connection to a process in a card that isn't Strict; everything else, including programs outside Shade, may reach
only agent services. The card names a program sends in its proxy credentials only label the call and never widen
that. Note that agent services can carry data out too: Strict + Record Agent Traffic shows you every such
connection, it doesn't stop them. See [agent-traffic.md](agent-traffic.md).

## Privacy

- No account, no analytics, no network calls of its own.
- Notes and settings are stored locally in the app's preferences.
- Translation uses Apple's on-device Translation framework. The only feature that sends text anywhere is the 🌐
  button, which opens Google Translate in your browser.
- Record Agent Traffic keeps the recorded calls in memory only, for the cards you turn it on for; they never
  leave your Mac and are gone when you quit Shade.
- Terminal cards run your shell with your user's normal permissions, exactly like Terminal.app.
- Highlighting runs locally. Shade only goes online when you click **Download** in *Get More Themes*, and then
  only to cdnjs for that theme file.
- The repository view runs `git status`, `git diff` and `git ls-files` locally and never writes with git. Files
  are written only when you save them in a file card.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting (the repository's *Security* tab) rather than a public issue.
