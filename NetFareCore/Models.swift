import Foundation

public enum NetworkInterfaceKind: String, Codable, CaseIterable, Sendable {
    case wifi
    case wired
    case cellular
    case loopback
    case other
    case unknown

    public var displayName: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .wired: "Wired"
        case .cellular: "Cellular"
        case .loopback: "Loopback"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}

public enum TestStatus: String, Codable, Sendable {
    case completed
    case incomplete
    case failed
    case cancelled
}

public enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
    case incomplete

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum TestPhase: String, Sendable {
    case preparing
    case latency
    case download
    case upload
    case calculating
    case finished
}

public struct ProviderRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let website: URL?

    public init(id: String, name: String, aliases: [String] = [], website: URL? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.website = website
    }
}

public struct ConnectionProfile: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var providerName: String
    public var planName: String
    public var advertisedDownloadMbps: Double?
    public var advertisedUploadMbps: Double?
    public var monthlyCostCents: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        providerName: String,
        planName: String = "",
        advertisedDownloadMbps: Double? = nil,
        advertisedUploadMbps: Double? = nil,
        monthlyCostCents: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerName = providerName
        self.planName = planName
        self.advertisedDownloadMbps = advertisedDownloadMbps
        self.advertisedUploadMbps = advertisedUploadMbps
        self.monthlyCostCents = monthlyCostCents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        if planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return providerName
        }
        return "\(providerName) · \(planName)"
    }
}

public struct SpeedTestRun: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public var interface: NetworkInterfaceKind
    public var status: TestStatus
    public var failureReason: String?
    public var latencySamplesMs: [Double]
    public var downloadSamplesMbps: [Double]
    public var uploadSamplesMbps: [Double]
    public var medianLatencyMs: Double?
    public var medianDownloadMbps: Double?
    public var medianUploadMbps: Double?
    public var jitterMs: Double?
    public var consistencyPercent: Double?
    public var dataUsedBytes: Int64
    public var confidence: Confidence
    public var calculationVersion: String

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        interface: NetworkInterfaceKind = .unknown,
        status: TestStatus = .incomplete,
        failureReason: String? = nil,
        latencySamplesMs: [Double] = [],
        downloadSamplesMbps: [Double] = [],
        uploadSamplesMbps: [Double] = [],
        medianLatencyMs: Double? = nil,
        medianDownloadMbps: Double? = nil,
        medianUploadMbps: Double? = nil,
        jitterMs: Double? = nil,
        consistencyPercent: Double? = nil,
        dataUsedBytes: Int64 = 0,
        confidence: Confidence = .incomplete,
        calculationVersion: String = "1.0"
    ) {
        self.id = id
        self.profileID = profileID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.interface = `interface`
        self.status = status
        self.failureReason = failureReason
        self.latencySamplesMs = latencySamplesMs
        self.downloadSamplesMbps = downloadSamplesMbps
        self.uploadSamplesMbps = uploadSamplesMbps
        self.medianLatencyMs = medianLatencyMs
        self.medianDownloadMbps = medianDownloadMbps
        self.medianUploadMbps = medianUploadMbps
        self.jitterMs = jitterMs
        self.consistencyPercent = consistencyPercent
        self.dataUsedBytes = dataUsedBytes
        self.confidence = confidence
        self.calculationVersion = calculationVersion
    }
}

public struct BillSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: UUID
    public var capturedAt: Date
    public var statementDate: Date?
    public var providerName: String
    public var totalCents: Int?
    public var basePriceCents: Int?
    public var equipmentFeeCents: Int?
    public var promotionalText: String?
    public var sourceFileName: String?
    public var ocrConfidence: Double?
    public var userConfirmed: Bool

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        capturedAt: Date = .now,
        statementDate: Date? = nil,
        providerName: String,
        totalCents: Int? = nil,
        basePriceCents: Int? = nil,
        equipmentFeeCents: Int? = nil,
        promotionalText: String? = nil,
        sourceFileName: String? = nil,
        ocrConfidence: Double? = nil,
        userConfirmed: Bool = false
    ) {
        self.id = id
        self.profileID = profileID
        self.capturedAt = capturedAt
        self.statementDate = statementDate
        self.providerName = providerName
        self.totalCents = totalCents
        self.basePriceCents = basePriceCents
        self.equipmentFeeCents = equipmentFeeCents
        self.promotionalText = promotionalText
        self.sourceFileName = sourceFileName
        self.ocrConfidence = ocrConfidence
        self.userConfirmed = userConfirmed
    }
}

public struct NetFareScore: Hashable, Sendable {
    public let overall: Int?
    public let downloadMatch: Int?
    public let uploadMatch: Int?
    public let latencyQuality: Int?
    public let consistencyQuality: Int?
    public let comparisonAvailable: Bool
    public let title: String
    public let detail: String

    public init(
        overall: Int?,
        downloadMatch: Int?,
        uploadMatch: Int?,
        latencyQuality: Int?,
        consistencyQuality: Int?,
        comparisonAvailable: Bool,
        title: String,
        detail: String
    ) {
        self.overall = overall
        self.downloadMatch = downloadMatch
        self.uploadMatch = uploadMatch
        self.latencyQuality = latencyQuality
        self.consistencyQuality = consistencyQuality
        self.comparisonAvailable = comparisonAvailable
        self.title = title
        self.detail = detail
    }
}

public struct PriceDrift: Hashable, Sendable {
    public let previousCents: Int
    public let currentCents: Int
    public let deltaCents: Int
    public let percent: Double

    public var isIncrease: Bool { deltaCents > 0 }
}

public struct PersistedAppState: Codable, Sendable {
    public var profiles: [ConnectionProfile]
    public var tests: [SpeedTestRun]
    public var bills: [BillSnapshot]
    public var selectedProfileID: UUID?

    public init(
        profiles: [ConnectionProfile] = [],
        tests: [SpeedTestRun] = [],
        bills: [BillSnapshot] = [],
        selectedProfileID: UUID? = nil
    ) {
        self.profiles = profiles
        self.tests = tests
        self.bills = bills
        self.selectedProfileID = selectedProfileID
    }
}

// MARK: - Sift product intelligence

public enum SiftCategory: String, Codable, CaseIterable, Sendable {
    case food
    case beauty
    case household
    case pet
    case other

    public var displayName: String {
        switch self {
        case .food: "Food & drink"
        case .beauty: "Beauty & personal care"
        case .household: "Home care"
        case .pet: "Pet care"
        case .other: "Everyday item"
        }
    }

    public var iconName: String {
        switch self {
        case .food: "fork.knife"
        case .beauty: "drop.fill"
        case .household: "sparkles"
        case .pet: "pawprint.fill"
        case .other: "shippingbox.fill"
        }
    }
}

public enum SiftIngredientRisk: String, Codable, CaseIterable, Sendable {
    case positive
    case neutral
    case review
    case caution

    public var displayName: String {
        switch self {
        case .positive: "Positive"
        case .neutral: "Neutral"
        case .review: "Review"
        case .caution: "Caution"
        }
    }
}

public struct SiftIngredientInsight: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let risk: SiftIngredientRisk
    public let reason: String
    public let tags: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        risk: SiftIngredientRisk,
        reason: String,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.risk = risk
        self.reason = reason
        self.tags = tags
    }
}

public struct SiftProduct: Codable, Hashable, Identifiable, Sendable {
    public let barcode: String
    public var name: String
    public var brand: String
    public var category: SiftCategory
    public var ingredientsText: String
    public var ingredients: [SiftIngredientInsight]
    public var score: Int?
    public var source: String
    public var imageURL: URL?
    public var scannedAt: Date

    public var id: String { barcode }

    public init(
        barcode: String,
        name: String,
        brand: String = "",
        category: SiftCategory,
        ingredientsText: String,
        ingredients: [SiftIngredientInsight] = [],
        score: Int? = nil,
        source: String = "Sift",
        imageURL: URL? = nil,
        scannedAt: Date = .now
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.category = category
        self.ingredientsText = ingredientsText
        self.ingredients = ingredients
        self.score = score
        self.source = source
        self.imageURL = imageURL
        self.scannedAt = scannedAt
    }

    public var scoreLabel: String {
        guard let score else { return "Not enough data" }
        switch score {
        case 85...100: return "Great"
        case 70..<85: return "Good"
        case 50..<70: return "Review"
        default: return "Caution"
        }
    }

    public var cautionCount: Int {
        ingredients.filter { $0.risk == .caution }.count
    }

    public var reviewCount: Int {
        ingredients.filter { $0.risk == .review }.count
    }
}

public struct SiftAppState: Codable, Sendable {
    public var products: [SiftProduct]

    public init(products: [SiftProduct] = []) {
        self.products = products
    }
}
