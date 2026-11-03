# Features

This fork narrows Kerf down to agentic coding: the notch is for Claude Code (and Copilot) sessions.
Everything else already has a good home in the menu bar.

Removed features are not lost. They live in the upstream repo
([paultje1900/kerf](https://github.com/paultje1900/kerf), remote `upstream`) and in this repo's
history before the `v1-agentic` branch. To bring one back, restore its files from `upstream/main`:

```bash
git checkout upstream/main -- Kerf/Modules/Music
```

…then wire it up again where the table below says.

## Kept in v1

| Feature | Where |
|---|---|
| The island: notch shape, springs, compact and open views, tab band | `Kerf/Island/*` |
| Permission requests (Allow / Always / Deny) in the notch | `Modules/Agents/AgentsPage.swift` (`PermissionCard`), `KerfKit/Agents/HookOutput.swift` |
| Questions with options (AskUserQuestion) | `AgentsPage.swift` (`QuestionCard`) |
| Session list: working, waiting, done, per project | `Modules/Agents/AgentCenter.swift`, `AgentsPage.swift` |
| Done notice: tick and sound in the notch | `AgentCenter.notices`, `Island/Compact.swift` (`.agentNotice`) |
| Jump to the session's app (terminal, editor) | `AgentCenter.open` |
| Find sessions already running at launch | `KerfKit/Agents/RunningThreads.swift` |
| `kerf notify` / `kerf answer` / `kerf debug` CLI | `App/CommandLineTool.swift` |
| Open pull requests on the AI page (via `gh`) | `AgentsPage.swift`, `Modules/Agents/PullRequests.swift` |
| Hook installer for Claude Code and GitHub Copilot | `Modules/Agents/AgentSettings.swift`, `KerfKit/Agents/HookInstaller.swift` |
| Ask (⌥ Space): a question to Claude Code, a few words to Google | `Modules/Ask/AskModule.swift`, `AskPage.swift` |
| Settings: open at login, close on leave, hover delay, sounds | `App/SettingsView.swift`, `App/Preferences.swift` |
| Lab: screenshots of any state without real data | `Island/Lab.swift` |

## Removed in v1

| Feature | Upstream files | Wired up in |
|---|---|---|
| Codex support | `KerfKit/Agents/*` (`AgentKind.codex`), `AgentSettings.swift` | `HookInstaller`, `AgentSettings` |
| T3 Code / P3 Code chat links | `KerfKit/Agents/CodeThreadLink.swift` | `AgentCenter.open` |
| Ask about selected text (⌥⇧ Space) | `Modules/Ask/AskInputs.swift` (`SelectionReader`) | `AppDelegate` hot keys, `IslandManager` |
| Ask with screenshot or files | `AskInputs.swift` (`Screenshot`), `AskModule` attachments | `IslandManager`, `AskPage` |
| Dictation in Ask | `AskInputs.swift` (`Dictation`) | `AskPage` |
| Now Playing: artwork, waveform, scroll for volume | `Modules/Music/NowPlayingModule.swift`, `MusicPage.swift`, `AudioLevels.swift`, `Vendor/mediaremote-adapter`, `scripts/build-adapter.sh` | `Hub`, `Compact.swift`, `AppDelegate` |
| Mixer: volume per app | `Modules/Music/AppMixer.swift`, `MixerPage.swift`, `SystemControls.swift` | `Pages.swift`, `AppDelegate` |
| Volume and brightness HUD in the notch | `System/MediaKeys.swift`, `System/SystemVolume.swift` | `SettingsView` (`HUDSetting`), `Hub.show`, `Compact.swift` (`.level`) |
| AirPods and charging | `Modules/Extras/BluetoothWatcher.swift`, `PowerWatcher` in `TimerModule.swift` | `SettingsView`, `AppDelegate` |
| Overview (home) page | `Modules/Today/HomePage.swift` | `Pages.swift` |
| Today: calendar with Join button | `Modules/Today/CalendarModule.swift`, `TodayPage` in `Island/Pages.swift` | `Pages.swift`, `AppDelegate` |
| Weather and rain, Focus status | `Modules/Extras/WeatherModule.swift` | `TodayPage` |
| Timers | `Modules/Extras/TimerModule.swift`, `TimerPage.swift` | `Hub`, `Pages.swift` |
| Shelf: files for 24 hours, AirDrop, drop to ask Claude | `Modules/Shelf/*` | `IslandController` (drag), `Pages.swift` |
| Clipboard history | `Modules/Extras/ClipboardModule.swift`, `Modules/Shelf/ClipboardList.swift` | `ShelfPage` |
| GitHub page: PRs, CI, issues, branches, files | `Modules/GitHub/GitHubPage.swift`, `KerfKit/Today/BranchGraph.swift` | `Pages.swift` |
| Camera mirror | `Modules/Extras/CameraPage.swift` | `Pages.swift` |
| Camera card offload with checksums | `Modules/Offload/*`, `KerfKit/Offload/*` | `Hub`, `Pages.swift`, `AppDelegate` |
| Browser download progress | `Modules/Extras/DownloadsWatcher.swift` | `Hub`, `SettingsView` |
| DaVinci Resolve render progress | `RenderWatcher` in `DownloadsWatcher.swift` | `Hub`, `AppDelegate` |

## Added in this fork

| Feature | Where |
|---|---|
| Waiting dot that stays: orange while any thread is blocked on you (a permission or a question), with the count when more than one, until that thread moves on (a tool runs, it stops, you prompt again, it ends). Answering in the terminal or a hook timing out no longer clears it. | `AgentCenter.waitingSessions`, `Hub.waitingCount`, `Compact.swift` (`AgentDot`), `PostToolUse`/`PostToolUseFailure` hooks in `HookInstaller` |
| "Update…" in Settings → Agents when the installed hooks are older than this version's | `HookInstaller.isCurrent`, `AgentSettings.swift` |
| Copilot threads show GitHub's Copilot mark instead of the generic tile | `AgentMark` in `AgentsPage.swift`, `Assets.xcassets/Copilot.imageset` |
| A finished thread makes no sound unless you turn it on (Settings → Agents) | `AgentCenter.soundsDoneKey`, `AgentSettings.swift` |
| A click opens the thread's own place: its Terminal or iTerm tab (by tty, AppleScript), its Claude desktop session (`claude://code/continue?session=…`), or its editor window by project name (Accessibility) | `ThreadLink`, `AgentCenter.open`, `System/WindowRaiser.swift` |
| How long a thread has worked, waited or been done: "Waiting for you · 12 min" | `Session.stateSince`, `ThreadRow.details` |
| Subagents per thread: "Working · 2 subagents" | `SubagentStart`/`SubagentStop` hooks, `Session.subagents` |
| A turn that ended on an API error (rate limit, overloaded, …) shows as stopped, with a red triangle in the notch instead of the tick | `StopFailure` hook, `Session.failure`, `Compact.swift` |
| CI and reviews on your pull requests: "Checks failed", "Changes requested", "Checks running" | `GitHub.searchQuery`, `PullRequests.refresh`, `PullDetails` |
| The island stays in the MacBook's notch; floating islands on other displays are off by default | `Preferences.swift`, `IslandManager.currentController` |

## Wishlist

Nothing open. Left out on purpose: live activity per thread ("Bash: npm test"); the app the
thread runs in shows that better.
