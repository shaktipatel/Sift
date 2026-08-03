import Foundation
import Combine

@MainActor
final class NetFareStore: ObservableObject {
    @Published private(set) var state: PersistedAppState
    @Published private(set) var lastPersistenceError: String?

    private let persistence = LocalPersistence()

    init() {
        state = persistence.load()
    }

    var selectedProfile: ConnectionProfile? {
        guard let selectedProfileID = state.selectedProfileID else { return state.profiles.first }
        return state.profiles.first(where: { $0.id == selectedProfileID }) ?? state.profiles.first
    }

    func selectProfile(_ id: UUID) {
        state.selectedProfileID = id
        persist()
    }

    @discardableResult
    func addProfile(
        providerName: String,
        planName: String,
        advertisedDownloadMbps: Double?,
        advertisedUploadMbps: Double?,
        monthlyCostCents: Int?
    ) -> UUID {
        let profile = ConnectionProfile(
            providerName: providerName.trimmingCharacters(in: .whitespacesAndNewlines),
            planName: planName.trimmingCharacters(in: .whitespacesAndNewlines),
            advertisedDownloadMbps: advertisedDownloadMbps,
            advertisedUploadMbps: advertisedUploadMbps,
            monthlyCostCents: monthlyCostCents
        )
        state.profiles.insert(profile, at: 0)
        state.selectedProfileID = profile.id
        persist()
        return profile.id
    }

    @discardableResult
    func addQuickProfile() -> UUID {
        addProfile(
            providerName: "Unknown ISP",
            planName: "",
            advertisedDownloadMbps: nil,
            advertisedUploadMbps: nil,
            monthlyCostCents: nil
        )
    }

    func updateProfile(_ profile: ConnectionProfile) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.updatedAt = .now
        state.profiles[index] = updated
        persist()
    }

    func deleteProfile(_ id: UUID) {
        state.profiles.removeAll { $0.id == id }
        state.tests.removeAll { $0.profileID == id }
        state.bills.removeAll { $0.profileID == id }
        if state.selectedProfileID == id {
            state.selectedProfileID = state.profiles.first?.id
        }
        persist()
    }

    func addTest(_ test: SpeedTestRun) {
        state.tests.insert(test, at: 0)
        persist()
    }

    func tests(for profileID: UUID) -> [SpeedTestRun] {
        state.tests.filter { $0.profileID == profileID }.sorted { $0.startedAt > $1.startedAt }
    }

    func latestTest(for profileID: UUID) -> SpeedTestRun? {
        tests(for: profileID).first
    }

    func addBill(_ bill: BillSnapshot) {
        state.bills.insert(bill, at: 0)
        persist()
    }

    func bills(for profileID: UUID) -> [BillSnapshot] {
        state.bills.filter { $0.profileID == profileID }.sorted { $0.capturedAt > $1.capturedAt }
    }

    func exportState() -> URL? {
        persistence.export(state: state)
    }

    func deleteAllData() {
        state = PersistedAppState()
        persistence.deletePersistedState()
    }

    private func persist() {
        do {
            try persistence.save(state)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }
}

private final class LocalPersistence {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let stateURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("NetFare", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        stateURL = directory.appendingPathComponent("state.json")
    }

    func load() -> PersistedAppState {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? decoder.decode(PersistedAppState.self, from: data) else {
            return PersistedAppState()
        }
        return decoded
    }

    func save(_ state: PersistedAppState) throws {
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic, .completeFileProtection])
    }

    func export(state: PersistedAppState) -> URL? {
        guard let data = try? encoder.encode(state) else { return nil }
        let exportURL = fileManager.temporaryDirectory.appendingPathComponent("NetFare-export.json")
        do {
            try data.write(to: exportURL, options: [.atomic])
            return exportURL
        } catch {
            return nil
        }
    }

    func deletePersistedState() {
        try? fileManager.removeItem(at: stateURL)
    }
}

// MARK: - Sift product store and lookup

@MainActor
final class SiftStore: ObservableObject {
    @Published private(set) var products: [SiftProduct]
    @Published private(set) var isLookingUp = false
    @Published private(set) var lastError: String?

    private let persistence = SiftPersistence()

    init() {
        products = persistence.load().products
    }

    var recentProducts: [SiftProduct] {
        products.sorted { $0.scannedAt > $1.scannedAt }
    }

    func lookup(barcode: String) async -> SiftProduct? {
        let normalized = Self.normalizeBarcode(barcode)
        guard normalized.count >= 8, normalized.count <= 14 else {
            lastError = "Enter an 8–14 digit barcode."
            return nil
        }

        isLookingUp = true
        lastError = nil
        defer { isLookingUp = false }

        let result = await SiftLookupService.lookup(barcode: normalized)
        guard let product = result.product else {
            lastError = result.errorMessage ?? "No product match found. Try the ingredient list instead."
            return nil
        }

        upsert(product)
        return product
    }

    @discardableResult
    func saveManualProduct(name: String, brand: String, category: SiftCategory, ingredientsText: String) -> SiftProduct {
        let analysis = SiftScoring.analyze(ingredientsText: ingredientsText, category: category)
        let product = SiftProduct(
            barcode: "manual-\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Manual ingredient check" : name,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            ingredientsText: ingredientsText,
            ingredients: analysis.insights,
            score: analysis.score,
            source: "Entered on device"
        )
        upsert(product)
        return product
    }

    func delete(_ product: SiftProduct) {
        products.removeAll { $0.id == product.id }
        persist()
    }

    func clearHistory() {
        products = []
        persistence.delete()
    }

    private func upsert(_ product: SiftProduct) {
        products.removeAll { $0.id == product.id }
        products.insert(product, at: 0)
        persist()
    }

    private func persist() {
        do {
            try persistence.save(SiftAppState(products: products))
            lastError = nil
        } catch {
            lastError = "Could not save this scan on the device."
        }
    }

    static func normalizeBarcode(_ value: String) -> String {
        value.filter(\.isNumber)
    }
}

private final class SiftPersistence {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let stateURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Sift", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        stateURL = directory.appendingPathComponent("products.json")
    }

    func load() -> SiftAppState {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? decoder.decode(SiftAppState.self, from: data) else {
            return SiftAppState()
        }
        return decoded
    }

    func save(_ state: SiftAppState) throws {
        try encoder.encode(state).write(to: stateURL, options: [.atomic, .completeFileProtection])
    }

    func delete() {
        try? fileManager.removeItem(at: stateURL)
    }
}

struct SiftLookupResult: Sendable {
    let product: SiftProduct?
    let errorMessage: String?
}

enum SiftLookupService {
    private struct Endpoint: Sendable {
        let source: String
        let bases: [String]
    }

    private enum FetchOutcome: Sendable {
        case product(SiftProduct)
        case notFound
        case networkFailure
    }

    private struct Envelope: Decodable {
        let status: Int?
        let product: RemoteProduct?
    }

    private struct RemoteProduct: Decodable {
        let productName: String?
        let productNameEnglish: String?
        let brands: String?
        let categoriesTags: [String]?
        let ingredientsText: String?
        let ingredientsTextEnglish: String?
        let imageURLString: String?

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case productNameEnglish = "product_name_en"
            case brands
            case categoriesTags = "categories_tags"
            case ingredientsText = "ingredients_text"
            case ingredientsTextEnglish = "ingredients_text_en"
            case imageURLString = "image_url"
        }
    }

    static func lookup(barcode: String) async -> SiftLookupResult {
        if let sample = SiftSampleCatalog.product(for: barcode) {
            return SiftLookupResult(product: sample, errorMessage: nil)
        }

        // The .net Open Food Facts host is the current documented API host. Keep
        // the legacy .org and the sister catalogs as fallbacks because DNS/CDN
        // availability can vary by carrier and region.
        let endpoints = [
            Endpoint(
                source: "Open Food Facts",
                bases: [
                    "https://world.openfoodfacts.net/api/v3/product/",
                    "https://world.openfoodfacts.org/api/v2/product/"
                ]
            ),
            Endpoint(
                source: "Open Beauty Facts",
                bases: [
                    "https://world.openbeautyfacts.org/api/v3/product/",
                    "https://world.openbeautyfacts.org/api/v2/product/"
                ]
            ),
            Endpoint(
                source: "Open Products Facts",
                bases: ["https://world.openproductsfacts.org/api/v3/product/"]
            )
        ]

        var sawNetworkError = false
        var sawCatalogResponse = false
        let foundProduct: SiftProduct? = await withTaskGroup(of: FetchOutcome.self, returning: SiftProduct?.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await fetch(barcode: barcode, endpoint: endpoint)
                }
            }

            for await outcome in group {
                switch outcome {
                case .product(let product):
                    group.cancelAll()
                    return product
                case .networkFailure:
                    sawNetworkError = true
                case .notFound:
                    sawCatalogResponse = true
                }
            }
            return nil
        }

        if let foundProduct {
            return SiftLookupResult(product: foundProduct, errorMessage: nil)
        }

        return SiftLookupResult(
            product: nil,
            errorMessage: sawCatalogResponse
                ? "No product was found for this barcode. Paste the ingredients to check them."
                : sawNetworkError
                ? "The product database is temporarily unavailable. Check your connection and try again, or paste the ingredients instead."
                : "No product was found for this barcode. Paste the ingredients to check them."
        )
    }

    private static func fetch(barcode: String, endpoint: Endpoint) async -> FetchOutcome {
        var sawNetworkFailure = false
        var sawValidResponse = false
        for base in endpoint.bases {
            guard let url = URL(string: "\(base)\(barcode).json?product_type=all&lc=en&fields=product_name,product_name_en,brands,categories_tags,ingredients_text,ingredients_text_en,image_url") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 6
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Sift/1.0 (iOS; com.sift.health)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    sawNetworkFailure = true
                    continue
                }
                guard 200..<300 ~= http.statusCode else {
                    // A 404/410 is a valid "not in this catalog" response; only
                    // transport/server failures should be reported as unavailable.
                    if (400..<500).contains(http.statusCode) {
                        sawValidResponse = true
                    } else if http.statusCode >= 500 {
                        sawNetworkFailure = true
                    }
                    continue
                }
                sawValidResponse = true
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                guard envelope.status != 0, let remote = envelope.product else {
                    continue
                }
                return .product(makeProduct(barcode: barcode, remote: remote, source: endpoint.source))
            } catch is CancellationError {
                return .notFound
            } catch {
                sawNetworkFailure = true
            }
        }
        return sawValidResponse || !sawNetworkFailure ? .notFound : .networkFailure
    }

    private static func makeProduct(barcode: String, remote: RemoteProduct, source: String) -> SiftProduct {
        let name = remote.productNameEnglish ?? remote.productName ?? "Unnamed product"
        let ingredientsText = remote.ingredientsTextEnglish ?? remote.ingredientsText ?? ""
        let category = category(from: remote.categoriesTags, source: source)
        let analysis = SiftScoring.analyze(ingredientsText: ingredientsText, category: category)
        return SiftProduct(
            barcode: barcode,
            name: name,
            brand: remote.brands ?? "",
            category: category,
            ingredientsText: ingredientsText,
            ingredients: analysis.insights,
            score: analysis.score,
            source: source,
            imageURL: remote.imageURLString.flatMap(URL.init(string:))
        )
    }

    private static func category(from tags: [String]?, source: String) -> SiftCategory {
        let joined = (tags ?? []).joined(separator: " ").lowercased()
        if source.contains("Beauty") || joined.contains("cosmetic") || joined.contains("shampoo") || joined.contains("skin-care") || joined.contains("hair-care") {
            return .beauty
        }
        if joined.contains("cleaning") || joined.contains("detergent") || joined.contains("household") {
            return .household
        }
        if joined.contains("pet") || joined.contains("cat") || joined.contains("dog") {
            return .pet
        }
        return .food
    }
}

enum SiftSampleCatalog {
    static func product(for barcode: String) -> SiftProduct? {
        let samples: [(String, String, String, SiftCategory, String)] = [
            ("000000000001", "Everyday Oat Crunch", "Sift Sample", .food, "whole grain oats, almonds, sugar, sunflower oil, salt"),
            ("000000000002", "Calm Clean Shampoo", "Sift Sample", .beauty, "water, aloe vera, glycerin, fragrance, sodium laureth sulfate"),
            ("000000000003", "Fresh Home Spray", "Sift Sample", .household, "water, citric acid, fragrance, sodium benzoate")
        ]
        guard let match = samples.first(where: { $0.0 == barcode }) else { return nil }
        let analysis = SiftScoring.analyze(ingredientsText: match.4, category: match.3)
        return SiftProduct(
            barcode: match.0,
            name: match.1,
            brand: match.2,
            category: match.3,
            ingredientsText: match.4,
            ingredients: analysis.insights,
            score: analysis.score,
            source: "Sift sample catalog"
        )
    }
}
