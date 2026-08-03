import XCTest
@testable import NetFareCore

final class NetFareCoreTests: XCTestCase {
    func testMedianHandlesOddAndEvenSamples() {
        XCTAssertEqual(NetFareStatistics.median([3, 1, 2]), 2)
        XCTAssertEqual(NetFareStatistics.median([1, 2, 3, 4]), 2.5)
        XCTAssertNil(NetFareStatistics.median([]))
        XCTAssertNil(NetFareStatistics.median([.nan, -.infinity]))
    }

    func testThroughputRejectsInvalidDurations() {
        XCTAssertEqual(NetFareStatistics.throughputMbps(bytes: 1_000_000, seconds: 1), 8)
        XCTAssertNil(NetFareStatistics.throughputMbps(bytes: 0, seconds: 1))
        XCTAssertNil(NetFareStatistics.throughputMbps(bytes: 1_000_000, seconds: 0))
        XCTAssertNil(NetFareStatistics.throughputMbps(bytes: 1_000_000, seconds: .infinity))
    }

    func testTrimmedMedianIgnoresExtremeOutliers() {
        let samples = [95.0, 100.0, 102.0, 105.0, 10_000.0]
        XCTAssertEqual(NetFareStatistics.trimmedMedian(samples), 101)
    }

    func testConsistencyIsNotCalculatedForEmptyOrZeroSamples() {
        XCTAssertNil(NetFareStatistics.consistencyPercent([]))
        XCTAssertNil(NetFareStatistics.consistencyPercent([0, 0]))
        XCTAssertGreaterThan(NetFareStatistics.consistencyPercent([98, 100, 102]) ?? 0, 90)
    }

    func testJitterUsesTimeOrderInsteadOfSortedSpread() {
        XCTAssertEqual(NetFareStatistics.jitterMilliseconds([20, 50, 21]) ?? 0, 29.5, accuracy: 0.001)
        XCTAssertNil(NetFareStatistics.jitterMilliseconds([.nan, .infinity]))
    }

    func testProviderMatchingNormalizesPunctuation() {
        XCTAssertEqual(ProviderCatalog.match("AT&T Fiber")?.id, "att")
        XCTAssertEqual(ProviderCatalog.match("  xfinity ")?.id, "comcast")
        XCTAssertNil(ProviderCatalog.match("Unknown Local ISP"))
    }

    func testScoreDoesNotClaimPlanMatchWithoutAdvertisedSpeed() {
        let profile = ConnectionProfile(providerName: "Local ISP")
        let run = NetFareScoring.makeRun(
            profileID: profile.id,
            interface: .wifi,
            status: .completed,
            latency: [20, 22, 21],
            download: [100, 110, 90],
            upload: [15, 14],
            interfaceStable: true
        )

        let score = NetFareScoring.score(profile: profile, run: run)
        XCTAssertNil(score.overall)
        XCTAssertFalse(score.comparisonAvailable)
        XCTAssertEqual(score.title, "Add plan speeds")
    }

    func testScoreFlagsConnectionBelowAdvertisedPlan() {
        let profile = ConnectionProfile(
            providerName: "Example ISP",
            advertisedDownloadMbps: 500,
            advertisedUploadMbps: 20
        )
        let run = NetFareScoring.makeRun(
            profileID: profile.id,
            interface: .wifi,
            status: .completed,
            latency: [20, 22, 21],
            download: [190, 210, 200],
            upload: [18, 20],
            interfaceStable: true
        )

        let score = NetFareScoring.score(profile: profile, run: run)
        XCTAssertNotNil(score.overall)
        XCTAssertTrue(score.comparisonAvailable)
        XCTAssertEqual(score.downloadMatch, 35)
        XCTAssertEqual(score.title, "Below your plan")
    }

    func testIncompleteRunCannotProduceAPlanScore() {
        let profile = ConnectionProfile(providerName: "Example ISP", advertisedDownloadMbps: 500)
        let run = NetFareScoring.makeRun(
            profileID: profile.id,
            interface: .wifi,
            status: .incomplete,
            failureReason: "Network path changed.",
            download: [200, 220]
        )

        let score = NetFareScoring.score(profile: profile, run: run)
        XCTAssertNil(score.overall)
        XCTAssertEqual(score.title, "Incomplete test")
    }

    func testPriceDriftUsesCentsAndHandlesDecrease() {
        let profileID = UUID()
        let previous = BillSnapshot(profileID: profileID, providerName: "ISP", totalCents: 7_500)
        let current = BillSnapshot(profileID: profileID, providerName: "ISP", totalCents: 8_250)
        let increase = NetFareScoring.priceDrift(previous: previous, current: current)
        XCTAssertEqual(increase?.deltaCents, 750)
        XCTAssertEqual(increase?.percent, 10)

        let lower = BillSnapshot(profileID: profileID, providerName: "ISP", totalCents: 6_000)
        XCTAssertEqual(NetFareScoring.priceDrift(previous: previous, current: lower)?.deltaCents, -1_500)
    }

    func testSiftScoreIsExplainableForFoodIngredients() {
        let result = SiftScoring.analyze(
            ingredientsText: "whole grain oats, sugar, sodium benzoate, red 40",
            category: .food
        )

        XCTAssertGreaterThan(result.score ?? 0, 50)
        XCTAssertLessThan(result.score ?? 100, 100)
        XCTAssertTrue(result.insights.contains { $0.name == "sugar" && $0.risk == .review })
        XCTAssertTrue(result.insights.contains { $0.name == "red 40" && $0.risk == .caution })
    }

    func testSiftBeautyScoreFlagsSensitivityPatterns() {
        let result = SiftScoring.analyze(
            ingredientsText: "water, aloe vera, glycerin, fragrance, sodium laureth sulfate",
            category: .beauty
        )

        XCTAssertNotNil(result.score)
        XCTAssertTrue(result.insights.contains { $0.name == "fragrance" && $0.risk == .review })
        XCTAssertTrue(result.insights.contains { $0.name == "sodium laureth sulfate" && $0.risk == .review })
        XCTAssertTrue(result.insights.contains { $0.name == "glycerin" && $0.risk == .positive })
    }

    func testSiftDoesNotInventScoreWithoutIngredients() {
        let result = SiftScoring.analyze(ingredientsText: "", category: .food)

        XCTAssertNil(result.score)
        XCTAssertTrue(result.insights.isEmpty)
    }
}
