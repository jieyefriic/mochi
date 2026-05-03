// Evolution — pure functions that decide what happens when Mochi eats.
//
// Single entry point: `EvolutionEngine.processMeal(meal, &state) -> [Event]`.
// Caller is responsible for reading the events and showing UI.

import Foundation

enum EvolutionEvent {
    case colorLocked(String)        // first 10 meals dominant → element
    case stageEvolved(Int)          // 0→1, 1→2, 2→3, ...
    case speciesLocked(String)      // at S3 hatching (v1: always DRAKKIN)
}

enum EvolutionEngine {

    // ─── tunables ─────────────────────────────────────────────────
    static let DAILY_GP_CAP   = 30
    static let GP_PER_MEAL    = 1
    static let COLOR_LOCK_AT  = 10           // GP & meal count
    static let STAGE_GP: [Int: Int] = [      // gp → stage
        0: 0,
        1: 10,    // S1 elemental egg
        2: 100,   // S2 cracking
        3: 110,   // S3 hatchling
        4: 300,   // S4 juvenile
        5: 700,   // S5 adult
        6: 1500,  // S6 ultimate
    ]

    // Diet category → element coat. Tie-break order: archive > code > image > doc > junk.
    static let TIE_BREAK_ORDER = ["archive", "code", "image", "doc", "junk"]

    // ─── meal processing ─────────────────────────────────────────
    static func processMeal(_ meal: TrashMeal, _ state: inout PetMochi) -> [EvolutionEvent] {
        var events: [EvolutionEvent] = []

        // Reset daily GP counter on date change.
        let today = Self.todayKey()
        if state.gpTodayDate != today {
            state.gpToday = 0
            state.gpTodayDate = today
        }

        // GP increments only while the daily cap isn't hit.
        if state.gpToday < DAILY_GP_CAP {
            state.gp += GP_PER_MEAL
            state.gpToday += GP_PER_MEAL
        }

        state.totalMeals += 1

        // Track first-10 meals for color election (skip after color locked).
        if state.color == nil && state.firstTenCategories.count < COLOR_LOCK_AT {
            state.firstTenCategories.append(meal.category.rawValue)
            if state.firstTenCategories.count == COLOR_LOCK_AT {
                let chosen = electColor(state.firstTenCategories)
                state.color = chosen
                events.append(.colorLocked(chosen))
            }
        }

        // Stage transition — fires once per crossed threshold.
        let newStage = stageFor(gp: state.gp)
        if newStage > state.stage {
            // Walk through every intermediate stage so we don't drop events
            // if a heavy daily-cap-bypass debug grant skipped levels.
            for s in (state.stage + 1)...newStage {
                state.stage = s
                events.append(.stageEvolved(s))
                // S3 hatching also locks species — pick by rhythm centroid.
                if s == 3 && state.species == nil {
                    let history = Store.shared.readMeals(withinDays: nil)
                    let chosen = SpeciesElector.elect(from: history)
                    state.species = chosen
                    events.append(.speciesLocked(chosen))
                }
            }
        }

        // Re-evaluate trait flavors after every meal (cheap; reads 30d JSONL).
        let newTraits = TraitEvaluator.evaluate(state: state)
        if newTraits != state.traits {
            state.traits = newTraits
            NSLog("Mochi: traits → \(newTraits)")
        }

        return events
    }

    // ─── helpers ─────────────────────────────────────────────────
    static func stageFor(gp: Int) -> Int {
        var stage = 0
        for s in 1...6 {
            if let t = STAGE_GP[s], gp >= t { stage = s }
        }
        return stage
    }

    static func electColor(_ categories: [String]) -> String {
        let total = max(1, categories.count)
        var counts: [String: Int] = [:]
        for c in categories { counts[c, default: 0] += 1 }

        // Highest count wins; tie broken by TIE_BREAK_ORDER (rarer-first).
        var best: (cat: String, score: Int)? = nil
        for cat in TIE_BREAK_ORDER {
            let n = counts[cat] ?? 0
            if best == nil || n > best!.score { best = (cat, n) }
        }
        // Also consider categories not in the priority list (video/audio/app/other).
        for (cat, n) in counts where !TIE_BREAK_ORDER.contains(cat) {
            if let b = best, n > b.score { best = (cat, n) }
            else if best == nil { best = (cat, n) }
        }

        // Need ≥30% to actually elect; otherwise default to Toxin.
        guard let chosen = best, chosen.score * 100 / total >= 30 else { return "green" }
        return colorFor(category: chosen.cat)
    }

    static func colorFor(category: String) -> String {
        switch category {
        case "code":                    return "red"     // Magma
        case "image":                   return "gold"    // Solar
        case "doc":                     return "blue"    // Frost
        case "archive", "app":          return "purple"  // Arcane
        case "junk", "other",
             "video", "audio":          return "green"   // Toxin
        default:                        return "green"
        }
    }

    static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    // ─── sprite asset resolution ─────────────────────────────────
    /// Returns the bundled resource basename (no extension) for the current
    /// (stage, color, species). Falls back gracefully — e.g. if species isn't
    /// set yet but stage ≥ 3, defaults to DRAKKIN.
    static func spriteName(stage: Int, color: String?, species: String?) -> String {
        let c = color ?? "red"
        let sp = species ?? "DRAKKIN"
        switch stage {
        case 0:
            return "egg_common"
        case 1:
            return c == "red" ? "egg_idle" : "egg_\(c)"
        case 2:
            return "cracking_\(c)"
        default:  // 3..6
            let stages = SPECIES_STAGES[sp] ?? SPECIES_STAGES["DRAKKIN"]!
            let idx = max(0, min(3, stage - 3))
            return "\(c)_\(stages[idx])"
        }
    }

    /// Returns the resource prefix for the idle animation (frames are
    /// `<prefix>_0`..`<prefix>_8` in the bundle), or nil if no anim.
    static func animPrefix(stage: Int, color: String?, species: String?) -> String? {
        let c = color ?? "red"
        let sp = species ?? "DRAKKIN"
        switch stage {
        case 0:  return nil                          // common — no anim
        case 1:  return "anim_\(c)"
        case 2:  return "anim_cracking_\(c)"
        default:
            let stages = SPECIES_STAGES[sp] ?? SPECIES_STAGES["DRAKKIN"]!
            let idx = max(0, min(3, stage - 3))
            return "anim_\(c)_\(stages[idx])"
        }
    }

    /// Resource prefix for the one-shot **feed reaction** animation.
    /// Layout matches build.sh's flattened bundle naming.
    static func feedPrefix(stage: Int, color: String?, species: String?) -> String? {
        let c = color ?? "red"
        let sp = species ?? "DRAKKIN"
        switch stage {
        case 0:  return "feed_common"
        case 1:  return "feed_\(c)"
        case 2:  return "feed_cracking_\(c)"
        default:
            let stages = SPECIES_STAGES[sp] ?? SPECIES_STAGES["DRAKKIN"]!
            let idx = max(0, min(3, stage - 3))
            return "feed_\(c)_\(stages[idx])"
        }
    }

    static let SPECIES_STAGES: [String: [String]] = [
        "DRAKKIN": ["drakling",  "drakwhelp",  "drakwarden",  "drakon"],
        "MOCHIMA": ["mochilet",  "mochinix",   "mochilord",   "mochiavatar"],
        "AVIORN":  ["pip",       "fledge",     "skylord",     "talonglyph"],
        "FELIQ":   ["felikit",   "felisprout", "felisaber",   "felimythos"],
        "TIDLE":   ["sigil",     "acolyte",    "archmage",    "aeonmage"],
    ]

    static let STAGE_NAMES: [Int: String] = [
        0: "Common",
        1: "Elemental Egg",
        2: "Cracking",
        3: "Hatchling",
        4: "Juvenile",
        5: "Adult",
        6: "Ultimate",
    ]
}
