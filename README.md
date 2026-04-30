# Mochi

A desktop pixel pet that quietly watches your macOS Trash and grows from what you throw away.

It starts as an egg floating on your desktop. Every time you delete a file, Mochi takes note — `.py` is a snack, `.psd` is a feast, `node_modules` is junk food. Over time it will hatch into different forms based on what you've been throwing away.

> **Status:** v0 — early prototype. The eat-from-trash loop and onboarding flow work; sprite is a placeholder, the evolution state machine is not yet built. See [Roadmap](#roadmap).

## Why

`lsof`, Activity Monitor, Finder — none of them tell you anything interesting about your *digital habits*. Mochi is a tiny opinionated mirror: a soft-pixel reminder of what you just chose to throw away today, this week, this month. And it's a desktop pet. That's it.

## Privacy

This is the first thing to know. Mochi:

- Reads **filename + extension + size** only — never the file contents.
- Has **no network code**. No telemetry. No crash reporters. No analytics.
- Stores everything locally (currently in-memory; future: a local SQLite log of `(timestamp, ext, size, category)` — still no filenames).
- Source is short enough you can audit it in 15 minutes — see `TrashWatcher.swift`.

## Install (from source)

Requires macOS 13+, Apple Silicon. No dependencies.

```bash
git clone https://github.com/jieyefriic/mochi.git
cd mochi
./build.sh
open ~/Applications/Mochi.app
```

`build.sh` runs `swiftc`, ad-hoc codesigns the bundle, and installs it to `~/Applications/Mochi.app`.

## First launch

You'll see a small egg in the bottom-right of your screen with a speech bubble saying `hungry... tap me`.

Tap it. A setup window walks you through the one thing that needs doing:

1. **Open System Settings** — deep-links straight to *Privacy & Security → Full Disk Access*.
2. **Reveal Mochi.app in Finder** — opens Finder with Mochi.app pre-selected, ready to drag into the access list.
3. Drop Mochi into the list and flip its switch.

The setup window auto-detects the moment access is granted and dismisses itself. Mochi starts eating.

> Why Full Disk Access? `~/.Trash` is gated behind the strictest TCC tier on modern macOS — there is no purpose-string-driven prompt for it. This is the only path. Mochi will never read anything outside `~/.Trash`.

## How it works

```
~/.Trash  ──FSEvents──►  TrashWatcher  ──TrashMeal──►  PetState  ──SwiftUI──►  egg + speech bubble
```

- **`Mochi.swift`** — `@main` entry, transparent borderless `NSPanel` (with `.canJoinAllSpaces` + `.fullScreenAuxiliary` so the egg follows you), drag-to-move with persistent position, placeholder pixel egg drawn in `Canvas`, right-click menu.
- **`TrashWatcher.swift`** — `FSEventStream` on `~/.Trash`, diffs directory contents on each event, classifies each newcomer by extension into one of `code / image / video / audio / doc / archive / app / junk / other`. Pure observation — never writes, never deletes.
- **`Onboarding.swift`** — Setup window with a 1.5s polling loop and a `x-apple.systempreferences:` deep-link to Full Disk Access.

## Controls

- **Left-click** the egg — when access isn't set up, opens the onboarding window. After setup, shows a status bubble.
- **Drag** anywhere on the egg's window — moves Mochi (position is remembered across launches).
- **Right-click** — menu with `Wake Up Mochi (Setup)`, `Reset Position`, `Quit`.

## Roadmap

- [x] Floating transparent panel + drag + position persistence
- [x] FSEvents Trash watcher + extension classifier
- [x] Onboarding flow for Full Disk Access
- [ ] Real pixel sprites (PixelLab-generated egg idle/eat/hatch sequences)
- [ ] Local SQLite meal log (timestamp + ext + size + category, no filenames)
- [ ] Evolution state machine — egg hatches into one of `coder / artist / scholar / junk / media` after ~100 meals based on dominant diet
- [ ] Behavior traits — late-night-deleter, indecisive-restorer, hoarder
- [ ] External volume Trashes (`/Volumes/*/.Trashes/$UID`)
- [ ] Alpha-aware hit testing so transparent areas click through

## Contributing

Issues and PRs welcome. Things that are particularly useful right now: macOS 14/15 testing, ideas for evolution branches that don't feel gimmicky, and anyone who knows how to make the FDA permission story less painful than it is.

## License

MIT — see [LICENSE](LICENSE).
