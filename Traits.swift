// Traits — evaluates which personality flavors are active on a 30-day window.
//
// Per DESIGN.md Axis 3:
//   Nocturnal     ≥ 40% meals in [22:00, 06:00)
//   Indecisive    ≥ 20 trash-restore events
//   Voracious     mean ≥ 30 meals/day
//   Hibernator    mean ≤ 2 meals/day
//   Polyglot      ≥ 10 distinct extensions seen
//   Cipherheart   ≥ 10% archive/encrypted meals
//
// At most 2 active traits at any time. We score each predicate by how far past
// its threshold it is, and keep the top 2 by strength.
//
// Special trait COMPANION is force-set on the 1-year anniversary.

import Foundation

enum TraitEvaluator {

    static let WINDOW_DAYS = 30
    static let MAX_ACTIVE  = 2

    /// Re-evaluate all traits against current meal/restore history. Returns
    /// the new active list (≤ 2 entries plus optional COMPANION).
    static func evaluate(state: PetMochi) -> [String] {
        let meals    = Store.shared.readMeals(withinDays: WINDOW_DAYS)
        let restores = Store.shared.restoreCount(withinDays: WINDOW_DAYS)
        let days     = Double(WINDOW_DAYS)

        let nightCount  = meals.filter { $0.hour >= 22 || $0.hour < 6 }.count
        let nightPct    = meals.isEmpty ? 0 : Double(nightCount) / Double(meals.count)

        let avgPerDay   = Double(meals.count) / days
        let exts        = Set(meals.map { $0.ext }.filter { !$0.isEmpty })
        let archiveCount = meals.filter { $0.category == "archive" }.count
        let archivePct  = meals.isEmpty ? 0 : Double(archiveCount) / Double(meals.count)

        // Score = how far past threshold (>=1 means "active"). Larger = stronger.
        var scores: [(name: String, score: Double)] = []
        if nightPct  >= 0.40 { scores.append(("NOCTURNAL",   nightPct  / 0.40)) }
        if restores  >= 20   { scores.append(("INDECISIVE",  Double(restores) / 20.0)) }
        if avgPerDay >= 30   { scores.append(("VORACIOUS",   avgPerDay / 30.0)) }
        if avgPerDay <= 2 && meals.count >= 5 {
            // Hibernator: only fires once we have *some* baseline so day-1 doesn't
            // mistakenly mark a brand-new pet as a hibernator.
            scores.append(("HIBERNATOR", 2.0 / max(0.5, avgPerDay)))
        }
        if exts.count >= 10  { scores.append(("POLYGLOT",    Double(exts.count) / 10.0)) }
        if archivePct >= 0.10 { scores.append(("CIPHERHEART", archivePct / 0.10)) }

        scores.sort { $0.score > $1.score }
        var picks = Array(scores.prefix(MAX_ACTIVE)).map { $0.name }

        // Companion: force-active starting at 365 days since born_at.
        let ageDays = (Date().timeIntervalSince1970 - state.bornAt) / 86400.0
        if ageDays >= 365 && !picks.contains("COMPANION") {
            picks.append("COMPANION")
        }

        return picks
    }

    /// User-friendly tag map for bubble lookup. (We use these as bubble tags
    /// later if we extend bubbles.json to include trait-keyed lines; for now
    /// they just feed the spriteVersion debug log.)
    static let LABELS: [String: String] = [
        "NOCTURNAL":   "Nocturnal",
        "INDECISIVE":  "Indecisive",
        "VORACIOUS":   "Voracious",
        "HIBERNATOR":  "Hibernator",
        "POLYGLOT":    "Polyglot",
        "CIPHERHEART": "Cipherheart",
        "COMPANION":   "Companion",
    ]
}
