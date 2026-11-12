# Troubleshooting

| Problem | Fix |
|---|---|
| [The shortcut does nothing](#the-shortcut-does-nothing) | Turn off macOS's input-source shortcut, or pick another one |
| [Panel shows in screen shares](#is-the-panel-really-hidden-in-screen-shares) | Test once with your meeting app |
| [Translation asks to download a language](#translation-asks-to-download-a-language) | Normal on first use of a language pair |
| [A tool fails in a sandboxed card](#a-tool-fails-in-a-sandboxed-card) | Check **Blocked Actions** |
| [A program can't connect in a Strict card](#a-program-hangs-or-cant-connect-in-a-strict-card) | Check **Agent Traffic › All** |
| [Calls missing from Agent Traffic](#a-tools-calls-dont-show-up-in-agent-traffic) | The tool ignores `HTTPS_PROXY` |
| [No notification from an agent](#no-notification-when-an-agent-asks-something) | Allow notifications, use the installed app |
| [Hints are hard to read](#hints-in-a-terminal-card-are-hard-to-read) | Tell the tool your theme |
| [Build fails after `git pull`](#the-build-fails-after-git-pull) | `swift package reset` |
| [Shade stops responding](#shade-stops-responding) | Force Quit (⌥⌘⎋) |

### The shortcut does nothing
macOS uses ⌃Space for "Select the previous input source" by default and takes it before any app sees it. Shade
detects this and shows a banner. Either turn that shortcut off in System Settings › Keyboard › Keyboard Shortcuts ›
Input Sources, or pick ⌃⇧Space, ⌃⌥Space, ⌃\` or ⌥\` in ⚙︎ › Shortcut. The app also tells you when another app has
already taken a combination.

### Is the panel really hidden in screen shares?
"Hide from screen sharing" uses `NSWindow.sharingType = .none`. Some capture methods on recent macOS versions ignore
it, so check it once with your meeting app before relying on it.

### Translation asks to download a language
That's macOS fetching the on-device model the first time you use a language pair. Manage downloaded languages in
System Settings › General › Language & Region › Translation Languages.

### A tool fails in a sandboxed card
Click **Blocked Actions** in the card's bar: it lists, live, what the sandbox denied. Expected ones are `git push`
over SSH, `brew install`, and builds that read secrets from `~/.gradle/gradle.properties`; run those in a normal
terminal card. If something harmless is blocked, open an issue with the denied path.

### A program hangs or can't connect in a Strict card
Strict has no network unless **Record Agent Traffic** is on, and even then only agent services are reachable. Open
**Agent Traffic** and choose **All**: refused connections show as **BLOCKED**. If the host belongs to your agent, add
it in ⚙︎ › **Agent Traffic** and open a new card.

### A tool's calls don't show up in Agent Traffic
It ignores the `HTTPS_PROXY` setting and connects directly, so Shade can't see it. Most command-line tools follow it;
some need their own proxy setting.

### No notification when an agent asks something
Check that notifications for Shade are allowed in System Settings › Notifications, and that ⚙︎ › Terminal › *Notify
when a terminal needs you* is on. Shade doesn't notify about the card you're looking at. Builds started with
`swift run` can't post notifications; install the app with `./scripts/install.sh`.

### Hints in a terminal card are hard to read
Shade raises any text color that's too close to its background, but a tool that picks colors for the wrong
brightness still looks off. Tell it the theme, for example `/theme` in Copilot CLI.

### The build fails after `git pull`
With an error about SwiftTerm, such as *"Traits [PortableGraphics] have been enabled on package 'swiftterm'"*, the
build folder still holds the previous SwiftTerm version. Run `swift package reset && ./scripts/install.sh`.

### Shade stops responding
Force-quit it from the Apple menu › **Force Quit** (⌥⌘⎋) or by right-clicking its Dock icon with ⌥ held. This needs
⚙︎ › **Show in Dock**, which is on by default.

### Terminal cards after a restart
The cards come back, each with a fresh shell; running programs don't survive quitting the app.
