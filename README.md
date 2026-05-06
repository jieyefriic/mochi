# Mochi

A desktop pixel pet that quietly watches your macOS Trash and grows from what you throw away.

It starts as an egg floating on your desktop. Every time you delete a file, Mochi takes note — `.py` is a magma snack, `.psd` is solar food, `node_modules` is toxin. Over the next few weeks Mochi locks an **element coat** (from your dominant diet), hatches into one of **five species** (decided by the *rhythm* of how you delete), and starts speaking lines in a voice tuned to who you turned out to be.

> **Status:** v0.2 — evolution + sprites + personality engine all live. The pet is a real pet now.

<p align="center">
  <em>5 species × 5 colors × 4 stages = 100 unique sprites · 999 feed-reaction frames · 125 bubble pools.</em>
</p>

## Why

`lsof`, Activity Monitor, Finder — none of them tell you anything interesting about your *digital habits*. Mochi is a tiny opinionated mirror: a soft-pixel reminder of what you just chose to throw away today, this week, this month. And it's a desktop pet. That's it.

## Privacy

This is the first thing to know. Mochi:

- Reads **extension + size + timestamp** only — never the file contents, never the filename, never a hash.
- Has **no network code**. No telemetry. No crash reporters. No analytics.
- Stores everything locally in `~/Library/Application Support/Mochi/` — `state.json` (the pet) plus an append-only `meals.jsonl` (`{ts, ext, size, category, hour, weekday}`).
- Source is short enough you can audit it in 30 minutes — start at `TrashWatcher.swift`.

## Install (from source)

Requires macOS 13+, Apple Silicon. No dependencies.

```bash
git clone https://github.com/jieyefriic/mochi.git
cd mochi
./build.sh
open ~/Applications/Mochi.app
```

`build.sh` runs `swiftc`, flattens ~2,200 sprite PNGs into `Resources/`, ad-hoc codesigns the bundle, and installs it to `~/Applications/Mochi.app`.

## First launch

You'll see a small egg in the bottom-right of your screen with a speech bubble saying `hungry... tap me`.

Tap it. A setup window walks you through the one thing that needs doing:

1. **Open System Settings** — deep-links straight to *Privacy & Security → Full Disk Access*.
2. **Reveal Mochi.app in Finder** — opens Finder with Mochi.app pre-selected, ready to drag into the access list.
3. Drop Mochi into the list and flip its switch.

The setup window auto-detects the moment access is granted and dismisses itself. Mochi starts eating.

> Why Full Disk Access? `~/.Trash` is gated behind the strictest TCC tier on modern macOS — there is no purpose-string-driven prompt for it. This is the only path. Mochi will never read anything outside `~/.Trash`.

## The three axes

Every Mochi specimen is fully described by three orthogonal axes, each driven by a different pattern in your deletion behavior. See `DESIGN.md` for the source of truth.

### Color · what you eat

Locked at **S1 (10 GP)** by your dominant diet across the first 10 meals.

| Dominant diet                     | Element  | Color  |
|-----------------------------------|----------|--------|
| `code` (.py .js .ts .swift …)     | Magma    | red    |
| `image` (.png .psd .jpg …)        | Solar    | gold   |
| `doc` (.pdf .md .docx .txt …)     | Frost    | blue   |
| `archive` (.zip .dmg .iso .rar)   | Arcane   | purple |
| `junk` (.DS_Store .cache .log …)  | Toxin    | green  |

Color is **immutable** after stage 1.

### Species · how you eat

Locked at **S3 hatching (110 GP)** by a 5-D centroid in your meal-rhythm space:

```
v_freq       mean meals per active day
v_size       log-mean file size
v_variance   stddev of meals per hour-of-day  (bursty vs steady)
v_diversity  unique extensions seen
v_workhours  fraction of meals in 9-18
```

| Species   | Body         | Strongest signals                                   |
|-----------|--------------|-----------------------------------------------------|
| **DRAKKIN** | dragon-line | high `workhours`, low `variance`, mid `diversity` |
| **MOCHIMA** | slime-line  | high `freq`, low `size`, high `diversity`          |
| **FELIQ**   | cat-line    | low `freq`, **very high** `size`, low `diversity` |
| **AVIORN**  | bird-line   | high `variance`, screenshot-heavy                  |
| **TIDLE**   | mollusk-line| low `freq`, doc/archive-heavy, low `variance`     |

Species is **immutable** after S3.

### Traits · when & how often you eat

Re-evaluated on a rolling 30-day window. Up to two active at a time.

| Trait        | Activation predicate                            |
|--------------|-------------------------------------------------|
| Nocturnal    | ≥ 40% meals in `[22:00, 06:00)`                |
| Indecisive   | ≥ 20 trash-restore events in 30 days            |
| Voracious    | mean ≥ 30 meals/day                             |
| Hibernator   | mean ≤ 2 meals/day                              |
| Polyglot     | ≥ 10 distinct extensions seen                   |
| Cipherheart  | ≥ 10% archive/encrypted meals                   |
| Companion    | force-active starting 1 year after first meal   |

Traits **don't change visuals** — they pick which voice Mochi speaks in. A `Magma DRAKKIN · Nocturnal · Polyglot` says different things from a `Solar TIDLE · Hibernator`.

## Progression

```
+1 GP per meal · daily soft cap 30 · no decay

S0 Common Egg     0 GP        (default)
S1 Elemental Egg  10 GP       — color locks, first ceremony
S2 Cracking       100 GP      — visual transition
S3 Hatchling      110 GP      — species locks
S4 Juvenile       300 GP
S5 Adult          700 GP
S6 Ultimate       1500 GP     — terminal (Mochi never dies)
```

For a steady ~15 meal/day user: S1 day 1 · S3 ~day 8 · S6 ~5 months.

## Special events

| Trigger                                       | Reaction                              |
|-----------------------------------------------|---------------------------------------|
| Trashing a `.git/` folder                     | Bubble: *"…you sure?"* (tag SPECIAL_GIT) |
| Empty Trash with ≥ 100 items at once          | One-off "feast" — `+50 GP` bonus      |
| Idle (no meal for a while)                    | 20–40 min random ambient bubble       |

## Controls

- **Left-click** the egg — opens onboarding if FDA isn't set up; otherwise pulls a contextual idle bubble.
- **Drag** anywhere on the egg — moves Mochi (position is remembered across launches; `.canJoinAllSpaces` so it follows you between desktops and into full-screen apps).
- **Right-click** — menu with `Wake Up Mochi (Setup)`, `Reset Position`, `Quit`. Build with `-D MOCHI_DEBUG_MENU` to expose stage / color / species jumps + `+50 GP` for development.

## Inspector — `codex.html`

A standalone HTML inspector lives at the repo root. Open it directly in any browser — no server needed:

```bash
open codex.html
```

Pick `(stage · color · species)` from the segmented controls and watch the idle and feed animations cycle inline. Useful for sprite QA and for showing the full 100-variant evolution tree without running the app.

## How it works

```
~/.Trash  ──FSEvents──►  TrashWatcher  ──TrashMeal──►  PetState
                                                            │
                                                            ▼
                                  EvolutionEngine.processMeal()
                                  → +GP → maybe color lock / stage jump / species hatch
                                  → TraitEvaluator (rolling 30d) → active trait set
                                                            │
                                                            ▼
                                  BubbleEngine.pick(tag, color, species, stage)
                                                            │
                                                            ▼
                                          NSPanel + EggSprite (idle + feed-reaction overlay)
```

| File                   | What it does |
|------------------------|--------------|
| `Mochi.swift`          | `@main`, `NSPanel`, drag handling, app delegate, idle bubble timer |
| `TrashWatcher.swift`   | FSEvents on `~/.Trash` + iCloud Trash, diff-based meal detection |
| `Persistence.swift`    | `state.json` + `meals.jsonl` + `restores.jsonl` |
| `Evolution.swift`      | GP ladder, color election, stage transitions, sprite resolution |
| `Species.swift`        | 5-D centroid election at S3 hatching |
| `Traits.swift`         | Rolling 30-day predicate evaluator |
| `Bubbles.swift`        | Loads `bubbles.json` (125 pools), tag-with-fallback picker |
| `Onboarding.swift`     | FDA setup window + system-settings deeplink |

## Sprite pipeline

All 111 sprites + ~2,200 animation frames were generated with [PixelLab.ai](https://www.pixellab.ai/) using the scripts under `scripts/`:

- **`match_objects_full.py`** — Recovers cloud `object_id`s by sha256 byte-matching local PNGs against every cloud preview. (Necessary because `vary_object`-derived color variants inherit the parent's prompt, so prompt-keyword classification mis-buckets them — byte-match is the only reliable way.)
- **`feed_batch.py`** — Sequential animator: fires `animate-object` per (species × color × stage), polls until done, downloads 9 frames using the URL template, retries on SSL/network/CUDA OOM. Sequential because PixelLab's per-account concurrency cap is very low (parallel fires get `429: maximum number of concurrent jobs`).
- **`objects_map_full.json`** — Persistent `object_id` registry. Commit this so the IDs survive even if a future PixelLab UI cleanup wipes their tags.

## Roadmap

- [x] Floating transparent panel + drag + position persistence
- [x] FSEvents Trash watcher (local + iCloud staging)
- [x] Onboarding flow for Full Disk Access
- [x] 100-variant species sprite tree (5 species × 5 colors × 4 stages) + idle anims
- [x] Feed-reaction animation (one-shot overlay per meal)
- [x] Local meal/restore JSONL log (extension + size + category, no filenames)
- [x] Evolution state machine — color election + 5-D species centroid + GP ladder
- [x] Trait evaluator — 6 traits + COMPANION 1y anniversary, 30d rolling window
- [x] Bubble corpus — 125 pools across (color × species × stage) with per-tag voices
- [x] Special events — `.git` warning, ≥100-item feast bonus
- [ ] S3 / S6 hatch ceremony — full-screen dim + reveal card
- [ ] 7-day cooldown on `Reset Mochi`
- [ ] Bubble localization (zh)
- [ ] AFK detection so Mochi doesn't talk to an empty desk
- [ ] External volume Trashes (`/Volumes/*/.Trashes/$UID`)
- [ ] Alpha-aware hit testing (transparent regions of the sprite click through)

## Contributing

Issues and PRs welcome. Things that are particularly useful right now: macOS 14/15 testing, additional bubble lines (especially zh), tuning the species centroids against real meal logs, and ideas for non-gimmicky special events.

## License

MIT — see [LICENSE](LICENSE).
