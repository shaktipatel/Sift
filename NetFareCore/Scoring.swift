import Foundation

public enum NetFareScoring {
    public static let calculationVersion = "1.0"

    public static func score(profile: ConnectionProfile, run: SpeedTestRun) -> NetFareScore {
        let isComplete = run.status == .completed && run.confidence != .incomplete
        let download = isComplete
            ? matchScore(actual: run.medianDownloadMbps, advertised: profile.advertisedDownloadMbps)
            : nil
        let upload = isComplete
            ? matchScore(actual: run.medianUploadMbps, advertised: profile.advertisedUploadMbps)
            : nil
        let latency = isComplete ? qualityScore(forLatency: run.medianLatencyMs) : nil
        let consistency = isComplete ? qualityScore(forConsistency: run.consistencyPercent) : nil

        var weightedTotal = 0.0
        var totalWeight = 0.0
        if let download { weightedTotal += Double(download) * 0.45; totalWeight += 0.45 }
        if let upload { weightedTotal += Double(upload) * 0.25; totalWeight += 0.25 }
        if let latency { weightedTotal += Double(latency) * 0.15; totalWeight += 0.15 }
        if let consistency { weightedTotal += Double(consistency) * 0.15; totalWeight += 0.15 }

        let overall = isComplete && totalWeight >= 0.55 ? Int((weightedTotal / totalWeight).rounded()) : nil
        let hasPlanComparison = isComplete && (download != nil || upload != nil)
        let title: String
        let detail: String

        if run.status != .completed || run.confidence == .incomplete {
            title = "Incomplete test"
            detail = run.failureReason ?? "Run the test again when your connection is stable."
        } else if let overall {
            if overall >= 90 {
                title = hasPlanComparison ? "Meeting your plan" : "Strong connection"
            } else if overall >= 70 {
                title = hasPlanComparison ? "Mostly meeting your plan" : "Usable connection"
            } else {
                title = hasPlanComparison ? "Below your plan" : "Needs attention"
            }
            detail = hasPlanComparison
                ? "Based on the median of your valid samples, not the fastest result."
                : "Add your advertised plan speed to compare value accurately."
        } else {
            title = "Add plan speeds"
            detail = "Your measurements are saved. Add the advertised download and upload speeds to calculate a plan match."
        }

        return NetFareScore(
            overall: overall,
            downloadMatch: download,
            uploadMatch: upload,
            latencyQuality: latency,
            consistencyQuality: consistency,
            comparisonAvailable: hasPlanComparison,
            title: title,
            detail: detail
        )
    }

    public static func makeRun(
        profileID: UUID,
        interface: NetworkInterfaceKind,
        status: TestStatus,
        failureReason: String? = nil,
        latency: [Double] = [],
        download: [Double] = [],
        upload: [Double] = [],
        dataUsedBytes: Int64 = 0,
        startedAt: Date = .now,
        endedAt: Date = .now,
        interfaceStable: Bool = true
    ) -> SpeedTestRun {
        let medianLatency = NetFareStatistics.trimmedMedian(latency)
        let medianDownload = NetFareStatistics.trimmedMedian(download)
        let medianUpload = NetFareStatistics.trimmedMedian(upload)
        let confidence = confidence(
            status: status,
            latencyCount: latency.count,
            downloadCount: download.count,
            uploadCount: upload.count,
            download: download,
            upload: upload,
            interfaceStable: interfaceStable
        )

        return SpeedTestRun(
            profileID: profileID,
            startedAt: startedAt,
            endedAt: endedAt,
            interface: interface,
            status: status,
            failureReason: failureReason,
            latencySamplesMs: latency,
            downloadSamplesMbps: download,
            uploadSamplesMbps: upload,
            medianLatencyMs: medianLatency,
            medianDownloadMbps: medianDownload,
            medianUploadMbps: medianUpload,
            jitterMs: NetFareStatistics.jitterMilliseconds(latency),
            consistencyPercent: NetFareStatistics.consistencyPercent(download),
            dataUsedBytes: dataUsedBytes,
            confidence: confidence,
            calculationVersion: calculationVersion
        )
    }

    public static func priceDrift(previous: BillSnapshot, current: BillSnapshot) -> PriceDrift? {
        guard let old = previous.totalCents, let new = current.totalCents, old > 0 else { return nil }
        let delta = new - old
        return PriceDrift(previousCents: old, currentCents: new, deltaCents: delta, percent: Double(delta) / Double(old) * 100)
    }

    private static func matchScore(actual: Double?, advertised: Double?) -> Int? {
        guard let actual, let advertised, actual.isFinite, advertised.isFinite, advertised > 0, actual >= 0 else { return nil }
        let ratio = actual / advertised
        switch ratio {
        case 1.0...: return 100
        case 0.9..<1.0: return 95
        case 0.75..<0.9: return 82
        case 0.5..<0.75: return 60
        case 0.25..<0.5: return 35
        default: return 15
        }
    }

    private static func qualityScore(forLatency latency: Double?) -> Int? {
        guard let latency, latency.isFinite, latency >= 0 else { return nil }
        switch latency {
        case 0..<20: return 100
        case 20..<50: return 90
        case 50..<100: return 75
        case 100..<200: return 50
        case 200..<300: return 30
        default: return 15
        }
    }

    private static func qualityScore(forConsistency consistency: Double?) -> Int? {
        guard let consistency, consistency.isFinite else { return nil }
        return Int(min(100, max(0, consistency)).rounded())
    }

    private static func confidence(
        status: TestStatus,
        latencyCount: Int,
        downloadCount: Int,
        uploadCount: Int,
        download: [Double],
        upload: [Double],
        interfaceStable: Bool
    ) -> Confidence {
        guard status == .completed, downloadCount > 0 else { return .incomplete }
        let consistency = NetFareStatistics.consistencyPercent(download) ?? 0
        if latencyCount >= 3, downloadCount >= 3, uploadCount >= 2, interfaceStable, consistency >= 80 { return .high }
        if latencyCount >= 2, downloadCount >= 2, interfaceStable, consistency >= 55 { return .medium }
        return .low
    }
}

// MARK: - Sift ingredient scoring

public struct SiftScoreResult: Sendable, Hashable {
    public let score: Int?
    public let insights: [SiftIngredientInsight]

    public init(score: Int?, insights: [SiftIngredientInsight]) {
        self.score = score
        self.insights = insights
    }
}

public enum SiftScoring {
    public static let calculationVersion = "1.0"

    /// This is a transparent screening indicator based on the supplied ingredient text.
    /// It is intentionally not a medical safety verdict: the UI explains the rule that
    /// produced each flag and never calls an item "safe" or "unsafe".
    public static func analyze(ingredientsText: String, category: SiftCategory) -> SiftScoreResult {
        let ingredients = splitIngredients(ingredientsText)
        guard !ingredients.isEmpty else {
            return SiftScoreResult(score: nil, insights: [])
        }

        var insights: [SiftIngredientInsight] = []
        var penalty = 0
        var positiveCount = 0

        for ingredient in ingredients {
            let normalized = normalize(ingredient)
            let match = classify(normalized: normalized, category: category)
            guard let match else { continue }

            penalty += match.penalty
            if match.risk == .positive { positiveCount += 1 }
            insights.append(
                SiftIngredientInsight(
                    name: ingredient,
                    risk: match.risk,
                    reason: match.reason,
                    tags: match.tags
                )
            )
        }

        let score = max(0, min(100, 100 - penalty + min(positiveCount * 2, 8)))
        return SiftScoreResult(score: score, insights: insights)
    }

    private struct Match {
        let risk: SiftIngredientRisk
        let penalty: Int
        let reason: String
        let tags: [String]
    }

    private static func classify(normalized: String, category: SiftCategory) -> Match? {
        if normalized.isEmpty { return nil }

        let positive: [(String, String, [String])] = [
            ("whole grain", "Whole-grain ingredient", ["fiber"]),
            ("whole wheat", "Whole-grain ingredient", ["fiber"]),
            ("oat", "Oat-based ingredient", ["fiber"]),
            ("olive oil", "Unsaturated plant oil", ["plant-based"]),
            ("avocado oil", "Unsaturated plant oil", ["plant-based"]),
            ("aloe", "Soothing botanical ingredient", ["botanical"]),
            ("glycerin", "Humectant that helps retain moisture", ["hydration"]),
            ("vitamin c", "Vitamin ingredient", ["vitamin"]),
            ("vitamin e", "Antioxidant vitamin ingredient", ["vitamin"])
        ]
        for (needle, reason, tags) in positive where normalized.contains(needle) {
            return Match(risk: .positive, penalty: 0, reason: reason, tags: tags)
        }

        let caution: [(String, Int, String, [String])] = [
            ("partially hydrogenated", 24, "Industrial trans-fat source to review", ["high priority"]),
            ("trans fat", 24, "Trans-fat wording to review", ["high priority"]),
            ("sodium nitrite", 18, "Curing preservative to review", ["preservative"]),
            ("sodium nitrate", 18, "Curing preservative to review", ["preservative"]),
            ("high fructose corn syrup", 16, "Added sweetener", ["sweetener"]),
            ("methylisothiazolinone", 22, "Preservative commonly flagged for sensitivity review", ["preservative", "sensitivity"]),
            ("methylchloroisothiazolinone", 22, "Preservative commonly flagged for sensitivity review", ["preservative", "sensitivity"]),
            ("formaldehyde", 24, "Ingredient to review in personal-care products", ["preservative"]),
            ("formalin", 24, "Ingredient to review in personal-care products", ["preservative"]),
            ("triclosan", 20, "Antimicrobial ingredient to review", ["antimicrobial"]),
            ("oxybenzone", 16, "UV-filter ingredient to review", ["uv filter"]),
            ("coal tar", 20, "Colorant ingredient to review", ["colorant"]),
            ("red 3", 12, "Synthetic colorant", ["colorant"]),
            ("red 40", 10, "Synthetic colorant", ["colorant"]),
            ("yellow 5", 10, "Synthetic colorant", ["colorant"]),
            ("yellow 6", 10, "Synthetic colorant", ["colorant"]),
            ("blue 1", 10, "Synthetic colorant", ["colorant"])
        ]
        for (needle, value, reason, tags) in caution where normalized.contains(needle) {
            return Match(risk: .caution, penalty: value, reason: reason, tags: tags)
        }

        let review: [(String, Int, String, [String])] = [
            ("added sugar", 7, "Added sweetener", ["sweetener"]),
            ("sugar", 5, "Added sweetener", ["sweetener"]),
            ("corn syrup", 7, "Added sweetener", ["sweetener"]),
            ("artificial flavor", 6, "Flavor additive", ["additive"]),
            ("artificial color", 6, "Color additive", ["additive"]),
            ("sodium benzoate", 6, "Preservative", ["preservative"]),
            ("potassium sorbate", 5, "Preservative", ["preservative"]),
            ("palm oil", 4, "Highly processed plant oil", ["processing"]),
            ("sucralose", 6, "Non-sugar sweetener", ["sweetener"]),
            ("aspartame", 6, "Non-sugar sweetener", ["sweetener"]),
            ("saccharin", 6, "Non-sugar sweetener", ["sweetener"]),
            ("fragrance", 7, "Fragrance blend; review if sensitive", ["sensitivity"]),
            ("parfum", 7, "Fragrance blend; review if sensitive", ["sensitivity"]),
            ("parabens", 7, "Preservative family to review", ["preservative"]),
            ("phthalate", 8, "Plasticizer family to review", ["fragrance"]),
            ("sodium lauryl sulfate", 6, "Cleansing surfactant; review if sensitive", ["surfactant"]),
            ("sodium laureth sulfate", 6, "Cleansing surfactant; review if sensitive", ["surfactant"]),
            ("denatured alcohol", 5, "Drying alcohol; review if sensitive", ["sensitivity"]),
            ("silicone", 3, "Film-forming ingredient", ["texture"]),
            ("quaternary ammonium", 12, "Strong cleaning active to handle carefully", ["cleaner"]),
            ("chlorine bleach", 12, "Strong cleaning active to handle carefully", ["cleaner"]),
            ("ammonia", 12, "Strong cleaning active to handle carefully", ["cleaner"])
        ]
        for (needle, value, reason, tags) in review where normalized.contains(needle) {
            let adjustedRisk: SiftIngredientRisk = category == .household && tags.contains("cleaner") ? .caution : .review
            return Match(risk: adjustedRisk, penalty: value, reason: reason, tags: tags)
        }

        return nil
    }

    private static func splitIngredients(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { part in
                part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"^\d+(?:\.\d+)?%\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func normalize(_ ingredient: String) -> String {
        ingredient
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0 == "(" || $0 == ")" || $0 == ":" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
