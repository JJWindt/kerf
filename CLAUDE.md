# Kerf (agentic fork)

A fork of [paultje1900/kerf](https://github.com/paultje1900/kerf), narrowed down to agentic coding:
the MacBook notch shows Claude Code (and Copilot) sessions, their permission requests and
questions, and an Ask field. macOS 26.

## Read first

1. `FEATURES.md`: what this fork keeps, what it removed (and where to find it upstream), the wishlist.
2. `README.md`: upstream's description; parts of it describe features this fork removed.
3. Apple's HIG through the `apple-design` skill. Everything in the island looks exactly like Apple's own island.

## Working

- Code, comments and commit messages in English. UI text in English with Dutch translations in `Localizable.xcstrings`.
- Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency. Pure logic in `KerfKit`, `nonisolated`, tested with Swift Testing.
- File-system synchronized groups: new and deleted files are picked up by themselves.
- No work in `body`, only animate what you see, measure in Release.
- No third-party packages. No secrets in git.
- Kerf has no server of its own and talks to nothing but the user's own tools (Claude Code, `gh`). Keep it that way.
- Check UI changes with the lab: `Kerf --lab shot <scene> <file.png>` (scenes in `Kerf/Island/Lab.swift`).
- The user has no admin rights: install to `~/Applications`, never `/Applications`; no Homebrew.
- Signing is ad hoc ("Sign to Run Locally"); bundle ID `nl.jjwindt.kerf`.

## Branches

- `main` mirrors Paul's `main` (`upstream`, paultje1900/kerf). Never commit to it; sync with
  `git fetch upstream && git push origin upstream/main:main`.
- `v1-agentic` is the user's own build: Paul's `main` minus the removed features, plus personal
  preferences. It is what gets installed. Bring Paul's changes in by merging `main`, never by
  rebasing (no force-pushes). When a merged PR was ported from this branch, conflicts resolve to
  this branch's version.
- A change Paul might want starts on a `feature/…` or `fix/…` branch cut from `main` (worktree
  `~/Code/kerf-upstream`) and goes to him as one PR per change. After he merges it, sync `main`
  and merge it into `v1-agentic`. Changes only the user wants go straight into `v1-agentic`.

## Build, test, install

```bash
xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Debug -derivedDataPath build/DerivedData build
cd KerfKit && swift test
scripts/install.sh   # Release build into ~/Applications, then starts it
```
