// Persistence — PetMochi state + meal log on disk.
//
// Storage:
//   ~/Library/Application Support/Mochi/state.json    — single PetMochi blob
//   ~/Library/Application Support/Mochi/meals.jsonl   — append-only meal log
//
// Privacy: meal entries hold ext + size + category + hour + weekday only.
// Never the filename or full path.

import Foundation

struct PetMochi: Codable {
    var bornAt: TimeInterval

    /// "red"/"blue"/"green"/"purple"/"gold". Locked at S1 (10 GP) based on
    /// dominant category in first 10 meals. Nil before that.
    var color: String? = nil

    /// "DRAKKIN"/"MOCHIMA"/"AVIORN"/"FELIQ"/"MAGUS". Locked at S3 hatching.
    /// v1 defaults to DRAKKIN at hatching; species detection lands in v2.
    var species: String? = nil

    /// 0..6.  S0 Common → S1 Egg → S2 Cracking → S3 Hatchling → S4 Juvenile
    ///        → S5 Adult → S6 Ultimate
    var stage: Int = 0

    var gp: Int = 0
    var gpToday: Int = 0
    var gpTodayDate: String = ""

    var totalMeals: Int = 0

    /// First 10 meal categories, used to elect color when count reaches 10.
    var firstTenCategories: [String] = []

    /// Active personality traits. v2 will populate this; we keep the field
    /// so older state files don't break decoding.
    var traits: [String] = []

    static func fresh() -> PetMochi {
        PetMochi(bornAt: Date().timeIntervalSince1970)
    }
}

/// One row in meals.jsonl. Used by SpeciesElector + TraitEvaluator.
struct MealRecord {
    let ts: TimeInterval
    let ext: String
    let size: Int64
    let category: String
    let hour: Int
    let weekday: Int
}

final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var mochi: PetMochi

    private let dir: URL
    private let stateURL: URL
    private let mealsURL: URL
    private let restoresURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let d = appSupport.appendingPathComponent("Mochi", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        self.dir = d
        self.stateURL = d.appendingPathComponent("state.json")
        self.mealsURL = d.appendingPathComponent("meals.jsonl")
        self.restoresURL = d.appendingPathComponent("restores.jsonl")

        if let data = try? Data(contentsOf: stateURL),
           let m = try? JSONDecoder().decode(PetMochi.self, from: data) {
            self.mochi = m
            NSLog("Mochi: loaded state — stage=\(m.stage) color=\(m.color ?? "?") species=\(m.species ?? "?") gp=\(m.gp) total=\(m.totalMeals)")
        } else {
            self.mochi = PetMochi.fresh()
            NSLog("Mochi: initialised fresh state")
        }
    }

    /// Atomically replace the state file. Cheap; called after every meal.
    func saveState() {
        do {
            let data = try JSONEncoder().encode(mochi)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            NSLog("Mochi: saveState failed — \(error)")
        }
    }

    /// Append a meal entry to the JSONL log (privacy-safe metadata only).
    func appendMeal(_ meal: TrashMeal) {
        let entry: [String: Any] = [
            "ts":       meal.when.timeIntervalSince1970,
            "ext":      meal.ext,
            "size":     meal.size,
            "category": meal.category.rawValue,
            "hour":     Calendar.current.component(.hour,    from: meal.when),
            "weekday":  Calendar.current.component(.weekday, from: meal.when),
        ]
        guard
            let json = try? JSONSerialization.data(withJSONObject: entry, options: []),
            let line = String(data: json, encoding: .utf8)
        else { return }

        let payload = (line + "\n").data(using: .utf8)!

        if FileManager.default.fileExists(atPath: mealsURL.path) {
            if let h = try? FileHandle(forWritingTo: mealsURL) {
                h.seekToEndOfFile()
                h.write(payload)
                try? h.close()
            }
        } else {
            try? payload.write(to: mealsURL, options: [.atomic])
        }
    }

    /// Replace the whole mochi record. Triggers SwiftUI re-render.
    func update(_ block: (inout PetMochi) -> Void) {
        var copy = mochi
        block(&copy)
        mochi = copy
        saveState()
    }

    /// Append a restore event (file left Trash) to restores.jsonl. Used by
    /// TraitEvaluator to compute the Indecisive predicate.
    func appendRestore(at when: Date = Date()) {
        let payload = "{\"ts\":\(when.timeIntervalSince1970)}\n".data(using: .utf8)!
        if FileManager.default.fileExists(atPath: restoresURL.path) {
            if let h = try? FileHandle(forWritingTo: restoresURL) {
                h.seekToEndOfFile()
                h.write(payload)
                try? h.close()
            }
        } else {
            try? payload.write(to: restoresURL, options: [.atomic])
        }
    }

    /// Read meals.jsonl, optionally filtering to recent N days.
    /// Cheap on real-life logs (a heavy user is ~30/day → ~10k lines/year).
    func readMeals(withinDays days: Int? = nil) -> [MealRecord] {
        guard let txt = try? String(contentsOf: mealsURL, encoding: .utf8) else { return [] }
        let cutoff: TimeInterval? = days.map {
            Date().timeIntervalSince1970 - Double($0) * 86400
        }
        var out: [MealRecord] = []
        out.reserveCapacity(2048)
        for raw in txt.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = obj["ts"] as? Double,
                  let ext = obj["ext"] as? String,
                  let cat = obj["category"] as? String,
                  let hour = obj["hour"] as? Int,
                  let wd  = obj["weekday"] as? Int
            else { continue }
            if let cutoff, ts < cutoff { continue }
            let size = (obj["size"] as? NSNumber)?.int64Value ?? -1
            out.append(MealRecord(ts: ts, ext: ext, size: size, category: cat, hour: hour, weekday: wd))
        }
        return out
    }

    /// Count restore events in the last N days.
    func restoreCount(withinDays days: Int) -> Int {
        guard let txt = try? String(contentsOf: restoresURL, encoding: .utf8) else { return 0 }
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
        var n = 0
        for raw in txt.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = obj["ts"] as? Double else { continue }
            if ts >= cutoff { n += 1 }
        }
        return n
    }

    /// Debug: wipe state file (used by Reset Mochi action).
    func reset() {
        mochi = PetMochi.fresh()
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: mealsURL)
        try? FileManager.default.removeItem(at: restoresURL)
        NSLog("Mochi: state reset")
    }
}
