// Bubbles — load `bubbles.json` from the app bundle and pick lines by
// (color, species, stage) + tag.
//
// Key format inside the JSON: "<element>_<species_lowercase>_s<stage>"
// where element ∈ {magma,frost,toxin,arcane,solar}, mapped from color.

import Foundation

enum BubbleEngine {

    private static let pools: [String: [String]] = loadPools()

    /// Pick a line for the current Mochi state.
    /// - Parameters:
    ///   - tag: e.g. "EAT", "EAT_code", "IDLE", "IDLE_NIGHT", "RESTORE", "EVOLVE",
    ///          "SPECIAL_GIT", "META". Subtag-then-tag fallback is automatic
    ///          (so "EAT_code" falls through to "EAT" if no specific line exists).
    static func pick(tag: String, color: String?, species: String?, stage: Int) -> String? {
        guard stage >= 2 else { return nil }   // S0/S1 don't have personality lines
        let key = poolKey(color: color, species: species, stage: stage)
        guard let pool = pools[key], !pool.isEmpty else { return nil }

        // Try the most specific tag first, then the bare prefix.
        for candidate in tagFallbacks(tag) {
            let matches = pool.compactMap { line -> String? in
                guard let body = stripTag(line, expected: candidate) else { return nil }
                return body
            }
            if let pick = matches.randomElement() { return pick }
        }
        return nil
    }

    // ─── internals ───────────────────────────────────────────────

    private static func poolKey(color: String?, species: String?, stage: Int) -> String {
        let element: String = {
            switch color {
            case "red":    return "magma"
            case "blue":   return "frost"
            case "green":  return "toxin"
            case "purple": return "arcane"
            case "gold":   return "solar"
            default:       return "magma"
            }
        }()
        // bubbles.json was authored using "magus" — keep that as the bubble-pool
        // key while the rest of the engine uses "TIDLE" (DESIGN.md canonical).
        let canonical = species ?? "DRAKKIN"
        let sp: String
        switch canonical {
        case "TIDLE": sp = "magus"
        default:      sp = canonical.lowercased()
        }
        return "\(element)_\(sp)_s\(stage)"
    }

    /// "EAT_code" → ["EAT_code", "EAT"]; "IDLE_NIGHT" → ["IDLE_NIGHT", "IDLE"];
    /// bare "EAT" → ["EAT"].
    private static func tagFallbacks(_ tag: String) -> [String] {
        if let underscore = tag.firstIndex(of: "_") {
            return [tag, String(tag[..<underscore])]
        }
        return [tag]
    }

    /// Returns the body (text after the closing bracket) iff the line's tag
    /// matches `expected`. Lines look like "[EAT_code] semicolons taste spicy.".
    private static func stripTag(_ line: String, expected: String) -> String? {
        guard line.hasPrefix("[") else { return nil }
        guard let close = line.firstIndex(of: "]") else { return nil }
        let tag = String(line[line.index(after: line.startIndex)..<close])
        guard tag == expected else { return nil }
        let after = line.index(after: close)
        return String(line[after...]).trimmingCharacters(in: .whitespaces)
    }

    private static func loadPools() -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: "bubbles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("Mochi: bubbles.json missing or unreadable")
            return [:]
        }
        var out: [String: [String]] = [:]
        for (key, val) in obj {
            if key.hasPrefix("_") { continue }      // skip _README/_voices/_species/_stages
            if let arr = val as? [String] { out[key] = arr }
        }
        NSLog("Mochi: loaded \(out.count) bubble pools")
        return out
    }
}
