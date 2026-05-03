# Mochi · Game Design v1

> Locked 2026-05-01. Source-of-truth for the evolution mechanics.
> Update via PR if you want to change any of this.

## Three Axes — orthogonal decomposition

Every Mochi specimen is fully described by three independent axes, each
driven by a different pattern in the user's deletion behavior:

```
吃了什么 (substance / category)  →  Color    元素皮 / Element coat
怎么吃的 (rhythm / pattern)       →  Species  物种骨 / Body archetype
如何吃的 (context / timing)       →  Traits   性格 / Personality bubbles
```

Color × Species are visual; Traits are textual. This means we paint
**5 species silhouettes × 5 element coats = 25 sprites per stage**, but the
expressive richness goes much higher because Traits add per-character lines.

---

## Axis 1 — Color (Element coat)

Decided in the **first 10 meals** of the user's life with Mochi. Whichever
diet category dominates locks the color forever.

| Dominant diet (≥30% of first 10) | Element  | Color  |
|----------------------------------|----------|--------|
| `code` (.py .js .ts .swift …)    | Magma    | red    |
| `image` (.png .psd .jpg …)       | Solar    | gold   |
| `doc` (.pdf .md .docx .txt …)    | Frost    | blue   |
| `archive` (.zip .dmg .iso .rar)  | Arcane   | purple |
| `junk` (.DS_Store node_modules .cache .log) | Toxin | green  |

Tie-break order if two categories tie at exactly 30%:
`archive > code > image > doc > junk`. (Rarer wins.)

If no category reaches 30% in the first 10 meals, default to **Toxin**
(catch-all) and keep watching — first category to cross 50% any time before
stage 2 overrides the default.

Color is **immutable** after stage 1.

---

## Axis 2 — Species (Body archetype)

Decided at **stage 3 hatching** (≥110 GP) by analyzing the rhythm/pattern
of all meals so far.

Five signal vectors per pet:

```
v_freq      = mean meals per active day
v_size      = mean file size (bytes)
v_variance  = stddev(meals per hour-of-day)   — bursty vs. steady
v_diversity = unique extensions count
v_workhours = % meals between 09:00–18:00
```

Each species is a region in this 5-dimensional space:

| Species   | Body          | Strongest signals                                   |
|-----------|---------------|-----------------------------------------------------|
| **DRAKKIN**  | dragon-line  | high `v_workhours`, low `v_variance`, mid `v_diversity` |
| **MOCHIMA**  | slime-line   | high `v_freq`, low `v_size`, high `v_diversity`     |
| **FELIQ**    | cat-line     | low `v_freq`, **very high** `v_size`, low `v_diversity` |
| **AVIORN**   | bird-line    | high `v_variance`, screenshot-heavy, mid all else   |
| **TIDLE**    | mollusk-line | low `v_freq`, doc/archive-heavy, low `v_variance`   |

Implementation: compute distance from each species' centroid; pick min.
Document the centroids when we tune. Species is **immutable** after stage 3.

---

## Axis 3 — Traits (Personality bubbles)

**Traits do NOT change visuals.** They drive the language Mochi uses.

A trait is *active* when its activation predicate is true on the rolling
30-day window. Recomputed nightly by the evaluator. **Max 2 active traits**
at any time (highest-strength wins on ties).

| Trait        | Activation predicate (rolling 30d)              |
|--------------|--------------------------------------------------|
| Nocturnal    | ≥ 40% meals in [22:00, 06:00)                   |
| Indecisive   | ≥ 20 trash-restore events                        |
| Voracious    | mean ≥ 30 meals/day                              |
| Hibernator   | mean ≤ 2 meals/day                               |
| Polyglot     | ≥ 10 distinct extensions seen                    |
| Cipherheart  | ≥ 10% archive/encrypted meals                    |

**Each trait carries a bubble pool** of 3–5 lines. Bubbles fire on:

- *Idle ticks* (every 20-40 min Mochi may say something from an active trait pool)
- *Reactive ticks* (when an event matches the trait theme — e.g. Nocturnal at 02:00 + new meal → fires its line)
- *Stage transitions* (active traits can offer color commentary on the moment)

Examples (English placeholders; actual copy will be in the locale's tone):

```
Nocturnal:    "the dark suits me." / "we're up late again." / "moonlight tastes good."
Indecisive:   "i had her... and now she's back." / "typical." / "make up your mind."
Voracious:    "nom nom nom." / "(satisfied burp)" / "more?"
Hibernator:   "...what year is it." / "(yawn)" / "any food?"
Polyglot:     "ooh, never tried .lua before." / "another flavor!"
Cipherheart:  "(the locked ones taste best.)" / "secrets..."
```

Traits compose multiplicatively with **color × species** to flavor copy.
A `Magma DRAKKIN · Nocturnal · Polyglot` says different things from a
`Solar TIDLE · Hibernator`. The bubble engine picks lines with
priority: stage-transition > reactive > idle.

---

## Progression — GP ladder

```
GP rules:
  +1 GP per meal
  daily soft cap: 30 GP / day  (overflow ignored — encourages presence over volume)
  no decay on idle days

Stages:
  S0  Common Egg     0 GP        (default at first launch)
  S1  Elemental Egg  10 GP       — color locks, first ceremony
  S2  Cracking       100 GP      — visual transition, no event
  S3  Hatchling      110 GP      — species locks, BIG ceremony
  S4  Juvenile       300 GP
  S5  Adult          700 GP
  S6  Ultimate       1500 GP     — terminal
```

For a steady ~15-meal/day user that's:

| Stage  | Days   |
|--------|--------|
| S1     | day 1  |
| S3     | ~day 8 |
| S6     | ~5 mo  |

Heavy users (>30/day) hit the cap and pace ~the same.

Light users (<5/day) take longer; that's intentional. They're not deleting much,
their pet stays small. **No catch-up mechanism.**

---

## Stage transitions — UX

| Stage           | Treatment                                                   |
|-----------------|-------------------------------------------------------------|
| S0 → S1         | Bubble:  *"you ate enough .py to feel warm 🔥"*             |
|                 | Sprite cross-fades from common to color, brief flash        |
| S1 → S2         | No event. Sprite swaps to cracking. Animation gets jittery. |
| S2 → S3 (hatch) | **Ceremony.** 1.5s screen dim, hatch sequence (TBD anim),   |
|                 | reveal card center: name + species + element + 1-line lore  |
| S3 → S4 / S4→S5 | Smaller card slide-in, particles, 3s; auto-dismisses        |
| S5 → S6         | Same ceremony as S3 but bigger and with the user's full     |
|                 | profile snapshot (top diet, fav hour, age, traits)          |

The ceremony is the only moment Mochi takes over the screen. Everything
else is small bubbles + the floating sprite.

---

## Permanence

- Mochi never dies. Ultimate stays Ultimate.
- No starvation, no neglect punishment.
- "Reset Mochi" exists in Settings → behind a confirm dialog → 7-day cooldown.

---

## Special events (ambient)

| Trigger                                          | Reaction                          |
|--------------------------------------------------|-----------------------------------|
| Trashing a `.git/` folder                        | One-off bubble: *"…you sure?"*    |
| Single Trash empty with > 100 items              | One-off "feast" — +50 GP bonus    |
| Same filename trashed→restored→trashed ≥ 3 times | Bubble: *"mochi understands now."* |
| 1-year anniversary (since first meal)            | Trait "Companion" force-activated  |
| First meal of the day                            | (silent — just normal eat bubble)  |

---

## Data model (SQLite, local only)

```sql
CREATE TABLE meals (
  id        INTEGER PRIMARY KEY,
  ts        INTEGER NOT NULL,        -- unix epoch
  ext       TEXT NOT NULL,           -- lowercased, "" if none
  size_b    INTEGER,                 -- -1 if dir/unknown
  category  TEXT NOT NULL,           -- code/image/doc/archive/junk/...
  src_dir   TEXT,                    -- last segment of parent dir (no full path)
  hour      INTEGER NOT NULL,        -- 0-23
  weekday   INTEGER NOT NULL         -- 0-6
);

CREATE TABLE mochi (
  id           INTEGER PRIMARY KEY CHECK (id = 1),
  born_at      INTEGER NOT NULL,
  color        TEXT,                   -- null until S1
  species      TEXT,                   -- null until S3
  stage        INTEGER NOT NULL,       -- 0..6
  gp           INTEGER NOT NULL,
  gp_today     INTEGER NOT NULL,
  gp_today_date TEXT NOT NULL,         -- YYYY-MM-DD
  traits_json  TEXT NOT NULL DEFAULT '[]'
);

CREATE TABLE events (
  id        INTEGER PRIMARY KEY,
  ts        INTEGER NOT NULL,
  kind      TEXT NOT NULL,         -- restore, evolve, special, bubble_fired
  payload   TEXT                   -- json
);
```

Privacy reminder: **never** stores filenames, full paths, or hashes.
Only metadata bins.

---

## Open questions for v1.1

- Bubble localization (en/zh) — tone matters; will need native pass.
- Idle bubble cadence — 20-40 min sounds right but real users will tell us.
- Should Mochi react when user is actively at the keyboard vs. AFK?
  (Detect via NSWorkspace activeApp + idle timer.) Likely yes; later.
