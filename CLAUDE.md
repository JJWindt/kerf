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

## Build, test, install

```bash
xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Debug -derivedDataPath build/DerivedData build
cd KerfKit && swift test
scripts/install.sh   # Release build into ~/Applications, then starts it
```
