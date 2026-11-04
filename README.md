# Kerf

A Dynamic Island for the MacBook notch, built to look and move like Apple's own island.

<p>
  <img src="Design/home.png" width="410" alt="The open island: what plays, and the rest of today">
  <img src="Design/question.png" width="410" alt="Claude Code asks a question in the notch">
</p>

- **Music**: whatever plays (Music, Spotify, podcasts) in Apple Music's island card. Scroll over the notch for volume.
- **Agents**: Claude Code and Codex ask for permission or answers in the notch, in full, wherever they run (Terminal, an editor, T3 Code). Copilot's sessions and questions show too; its approvals stay in Copilot, so its Allow All holds. An orange dot stays until you answer. Opening Kerf shows the pending decision; from the thread list, a waiting thread's Answer pill opens its decision, and half-typed answers stay. With two threads in one repository, each shows its branch. Any other tool can use `kerf notify`.
- **Ask**: ⌥ Space. A question goes to Claude through your own Claude Code, a few words to Google. ⌥⇧ Space asks about the selected text. Drop files or take a screenshot to ask about them; speak instead of typing.
- **Offload**: put in a camera card, click Offload, pick the drive and the project. Every file is copied, checked with xxHash64, and skipped if the project already has it.
- **Shelf**: drop files on the notch; they stay 24 hours. AirDrop, share, show in Finder, and a clipboard history.
- **Today**: your calendar with a join button for calls, the weather and rain, timers.
- **GitHub**: pull requests, CI, issues and a repo's files, through `gh`. Your PRs and review requests also show under the threads, the ones a thread works on first; a quiet alert in the notch when checks newly fail or a reviewer asks for changes.
- **Camera** mirror, **volume and brightness** in the notch, AirPods and charging, downloads, DaVinci Resolve renders.

## Install

```bash
brew install --cask paultje1900/tap/kerf
```

Needs macOS 26 (Tahoe). Kerf is signed and notarized by Apple. It opens at login and lives in the notch; on a display without a notch it floats at the top.

Update with `brew upgrade --cask kerf`. To remove it, first press Disconnect in Settings → Agents, then `brew uninstall --cask kerf` (add `--zap` to remove its settings too).

## First steps

1. **Settings → Agents → Connect** Claude Code, Codex and Copilot. Kerf shows the exact change to their config first and keeps a backup; Copilot gets its own file in `~/.copilot/hooks`. For Codex, type `/hooks` once to trust them.
2. **Settings → General → Allow Accessibility**: volume and brightness in the notch, and ⌥⇧ Space for selected text.
3. **Today**: tap the calendar and weather buttons once. Downloads and AirPods are off until you switch them on in Settings → Pages.
4. **Ask** uses [Claude Code](https://claude.com/claude-code) (`claude`, signed in); **GitHub** uses the [GitHub CLI](https://cli.github.com) (`gh auth login`).
5. **DaVinci Resolve**: Preferences → General → External scripting using: Local.

## Privacy

Kerf has no server and no account. Everything stays on your Mac, except:

- the weather: your approximate location goes to [Open-Meteo](https://open-meteo.com);
- what you ask Claude goes through your own Claude Code, and GitHub through your own `gh`;
- a search opens Google in your browser.

## Build from source

```bash
xcodebuild -project Kerf.xcodeproj -scheme Kerf build
cd KerfKit && swift test
scripts/install.sh   # Release build into /Applications
```

macOS 26, Xcode 27, Swift 6. `Kerf --lab shot <scene> <file.png>` saves a frame of any state without real data (scenes in `Kerf/Island/Lab.swift`).

Releases: raise `MARKETING_VERSION`, then `scripts/release.sh --publish` archives, signs with Developer ID, notarizes, publishes the GitHub release and updates the cask in [paultje1900/homebrew-tap](https://github.com/paultje1900/homebrew-tap).

## License

MIT. Third-party: [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause), vendored in `Vendor/`.
