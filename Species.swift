// Species — elects body archetype at S3 hatching from meal rhythm signals.
//
// 5-D feature vector per pet (per DESIGN.md Axis 2):
//   v_freq      = mean meals per active day
//   v_size      = mean file size (bytes, ignoring -1)
//   v_variance  = stddev(meals per hour-of-day)
//   v_diversity = unique extensions count
//   v_workhours = % meals between 09:00–18:00
//
// Each species owns a centroid in this normalized space; we pick the nearest.

import Foundation

enum SpeciesElector {

    static let ALL: [String] = ["DRAKKIN", "MOCHIMA", "FELIQ", "AVIORN", "TIDLE"]

    /// Centroids in NORMALIZED space (each axis z-scored to typical user ranges
    /// below). Tuned from DESIGN.md "strongest signals" column.
    /// Order: [freq, size_log, variance, diversity, workhours]
    private static let CENTROIDS: [String: [Double]] = [
        "DRAKKIN":  [ 0.2,  0.1,  -0.6,   0.0,   1.0 ],   // workhours code grinder
        "MOCHIMA":  [ 1.0, -0.8,   0.3,   1.0,   0.0 ],   // high freq, small files, varied
        "FELIQ":    [-0.6,  1.2,  -0.3,  -0.6,   0.0 ],   // big files, rare, focused
        "AVIORN":   [ 0.0,  0.0,   1.2,   0.0,  -0.3 ],   // bursty, screenshots
        "TIDLE":    [-0.5,  0.2,  -0.7,  -0.2,  -0.5 ],   // slow, doc/archive heavy
    ]

    /// Normalization scales — divide raw value by this to get ~unit-stddev.
    private static let SCALES: (freq: Double, sizeLog: Double, variance: Double, diversity: Double, workhours: Double) =
        (freq: 15.0, sizeLog: 8.0, variance: 4.0, diversity: 12.0, workhours: 0.5)

    /// Pre-feature-extraction shifts (subtract before scaling so centroid 0 = "average user").
    private static let CENTERS: (freq: Double, sizeLog: Double, variance: Double, diversity: Double, workhours: Double) =
        (freq: 10.0, sizeLog: 14.0, variance: 4.0, diversity: 8.0, workhours: 0.45)

    /// Elect a species from the user's meal history.
    /// Falls back to MOCHIMA if there's not enough data (< 5 meals total).
    static func elect(from meals: [MealRecord]) -> String {
        guard meals.count >= 5 else { return "MOCHIMA" }

        let v = features(from: meals)
        var best: (sp: String, dist: Double)? = nil
        for (sp, c) in CENTROIDS {
            let d = squaredDistance(v, c)
            if best == nil || d < best!.dist { best = (sp, d) }
        }
        let chosen = best?.sp ?? "MOCHIMA"
        NSLog("Mochi: SpeciesElector → \(chosen)  features=\(v)")
        return chosen
    }

    // MARK: - features

    /// Returns the normalized 5-D feature vector.
    static func features(from meals: [MealRecord]) -> [Double] {
        // v_freq: meals per active day
        let dayKeys = Set(meals.map { dayKey(ts: $0.ts) })
        let activeDays = max(1, dayKeys.count)
        let freq = Double(meals.count) / Double(activeDays)

        // v_size: log-mean (skip -1 / dirs / unknowns)
        let sized = meals.compactMap { $0.size > 0 ? Double($0.size) : nil }
        let sizeLog: Double = sized.isEmpty
            ? 0
            : sized.reduce(0) { $0 + log2(max(1, $1)) } / Double(sized.count)

        // v_variance: stddev across the 24 hour buckets
        var hourCounts = [Int](repeating: 0, count: 24)
        for m in meals { hourCounts[max(0, min(23, m.hour))] += 1 }
        let mean = Double(meals.count) / 24.0
        let variance = sqrt(hourCounts.reduce(0.0) { acc, c in
            acc + pow(Double(c) - mean, 2)
        } / 24.0)

        // v_diversity: unique non-empty extensions
        let exts = Set(meals.map { $0.ext }.filter { !$0.isEmpty })
        let diversity = Double(exts.count)

        // v_workhours: fraction of meals in [09:00, 18:00)
        let workhoursCount = meals.filter { $0.hour >= 9 && $0.hour < 18 }.count
        let workhours = Double(workhoursCount) / Double(max(1, meals.count))

        return [
            (freq      - CENTERS.freq)      / SCALES.freq,
            (sizeLog   - CENTERS.sizeLog)   / SCALES.sizeLog,
            (variance  - CENTERS.variance)  / SCALES.variance,
            (diversity - CENTERS.diversity) / SCALES.diversity,
            (workhours - CENTERS.workhours) / SCALES.workhours,
        ]
    }

    private static func squaredDistance(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + pow($1.0 - $1.1, 2) }
    }

    private static func dayKey(ts: TimeInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}
