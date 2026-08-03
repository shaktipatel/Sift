import AVFoundation
import SwiftUI
import UIKit

struct SiftRootView: View {
    var body: some View {
        TabView {
            SiftScanView()
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
            SiftHistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SiftSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(SiftTheme.accent)
    }
}

private enum SiftTheme {
    static let accent = Color(red: 0.11, green: 0.47, blue: 0.40)
    static let mint = Color(red: 0.78, green: 0.96, blue: 0.87)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.13)
    static let cream = Color(red: 0.98, green: 0.98, blue: 0.95)
}

struct SiftScanView: View {
    @EnvironmentObject private var store: SiftStore
    @State private var barcode = ""
    @State private var scannerPresented = false
    @State private var manualPresented = false
    @State private var selectedProduct: SiftProduct?
    @State private var inputError: String?
    @FocusState private var barcodeFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    scannerButton
                    lookupField
                    privacyCard

                    if let error = inputError ?? store.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                    }

                    recentSection
                }
                .padding(20)
            }
            .background(SiftTheme.cream.ignoresSafeArea())
            .navigationTitle("Sift")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manualPresented = true
                    } label: {
                        Image(systemName: "text.viewfinder")
                    }
                    .accessibilityLabel("Check an ingredient list")
                }
            }
            .sheet(isPresented: $scannerPresented) {
                SiftScannerSheet { code in
                    scannerPresented = false
                    lookup(code)
                }
            }
            .sheet(isPresented: $manualPresented) {
                SiftManualEntryView { product in
                    manualPresented = false
                    selectedProduct = product
                }
                .environmentObject(store)
            }
            .sheet(item: $selectedProduct) { product in
                SiftProductDetailView(product: product)
            }
            .overlay {
                if store.isLookingUp {
                    ProgressView("Finding ingredients…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 18, y: 8)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "barcode.viewfinder")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SiftTheme.accent)
                Text("SIFT")
                    .font(.caption.weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(SiftTheme.accent)
                Spacer()
                Text("BETA")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SiftTheme.mint, in: Capsule())
            }
            Text("Know what’s\nin the cart.")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(SiftTheme.ink)
            Text("Scan food, shampoo, skincare, cleaners, and everyday products. Sift turns the ingredient list into a clear, explainable score.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(
            LinearGradient(colors: [SiftTheme.mint, Color.white], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 72))
                .foregroundStyle(SiftTheme.accent.opacity(0.11))
                .rotationEffect(.degrees(-18))
                .padding(18)
                .accessibilityHidden(true)
        }
    }

    private var scannerButton: some View {
        Button {
            scannerPresented = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "barcode.viewfinder")
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scan a barcode")
                        .font(.headline)
                    Text("Instant product lookup")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(SiftTheme.accent, in: RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityHint("Opens the camera barcode scanner")
    }

    private var lookupField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or enter a barcode")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                TextField("UPC or EAN", text: $barcode)
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .focused($barcodeFocused)
                    .onChange(of: barcode) { _, value in
                        barcode = String(value.filter(\.isNumber).prefix(14))
                        inputError = nil
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                Button("Sift") { lookup(barcode) }
                    .buttonStyle(.borderedProminent)
                    .tint(SiftTheme.accent)
                    .disabled(barcode.isEmpty || store.isLookingUp)
            }
            Text("Try sample barcode 000000000001")
                .font(.caption)
                .foregroundStyle(.secondary)
                .onTapGesture {
                    barcode = "000000000001"
                    barcodeFocused = false
                    lookup(barcode)
                }
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(SiftTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Private by default")
                    .font(.subheadline.weight(.semibold))
                Text("Your history stays on this iPhone. Sift only sends a barcode when you ask for a product match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent checks")
                    .font(.title3.bold())
                Spacer()
                if !store.recentProducts.isEmpty {
                    Text("\(store.recentProducts.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            if store.recentProducts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "cart.badge.questionmark")
                        .font(.system(size: 30))
                        .foregroundStyle(SiftTheme.accent)
                    Text("Your first check starts here")
                        .font(.headline)
                    Text("Scan something from the shelf to see its score and ingredient notes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
            } else {
                ForEach(store.recentProducts.prefix(5)) { product in
                    Button { selectedProduct = product } label: {
                        SiftProductRow(product: product)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func lookup(_ rawValue: String) {
        let normalized = SiftStore.normalizeBarcode(rawValue)
        guard normalized.count >= 8 else {
            inputError = "A barcode usually has 8–14 digits."
            return
        }
        inputError = nil
        Task {
            if let product = await store.lookup(barcode: normalized) {
                selectedProduct = product
            }
        }
    }
}

struct SiftHistoryView: View {
    @EnvironmentObject private var store: SiftStore
    @State private var selectedProduct: SiftProduct?

    var body: some View {
        NavigationStack {
            Group {
                if store.recentProducts.isEmpty {
                    ContentUnavailableView("No checks yet", systemImage: "clock.arrow.circlepath", description: Text("Scanned products will appear here for quick comparison.") )
                } else {
                    List {
                        ForEach(store.recentProducts) { product in
                            Button { selectedProduct = product } label: {
                                SiftProductRow(product: product)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { store.delete(product) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(SiftTheme.cream.ignoresSafeArea())
            .navigationTitle("History")
            .sheet(item: $selectedProduct) { product in
                SiftProductDetailView(product: product)
            }
        }
    }
}

struct SiftSettingsView: View {
    @EnvironmentObject private var store: SiftStore
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("On-device history")
                                .font(.headline)
                            Text("Sift stores scans locally. There is no account or profile to sell.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(SiftTheme.accent)
                    }
                }

                Section("How scores work") {
                    NavigationLink {
                        SiftMethodologyView()
                    } label: {
                        Label("Ingredient methodology", systemImage: "list.bullet.clipboard")
                    }
                }

                Section("Data") {
                    LabeledContent("Saved checks", value: "\(store.recentProducts.count)")
                    Button("Delete all local history", role: .destructive) {
                        confirmClear = true
                    }
                }

                Section {
                    Text("Sift scores are screening indicators based on the ingredient text returned by the product database or entered by you. They are not medical advice, allergy guarantees, or a substitute for a clinician or label check.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete every saved check?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete history", role: .destructive) { store.clearHistory() }
            }
        }
    }
}

struct SiftMethodologyView: View {
    var body: some View {
        List {
            Section("The score") {
                Text("Sift starts at 100 and applies small, visible deductions for ingredient patterns that shoppers commonly want to review. The result is a clarity score, not a diagnosis.")
            }
            Section("Every flag is explainable") {
                Label("Sweeteners and additives", systemImage: "drop.fill")
                Label("Preservatives and colorants", systemImage: "paintpalette.fill")
                Label("Fragrance and sensitivity notes", systemImage: "nose")
                Label("Strong household cleaning actives", systemImage: "sparkles")
            }
            Section("Good to know") {
                Text("Ingredient lists change. Sift shows the source and the exact ingredient text used for each check so you can make the final call.")
            }
        }
        .navigationTitle("Methodology")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SiftProductRow: View {
    let product: SiftProduct

    var body: some View {
        HStack(spacing: 13) {
            SiftMiniScore(score: product.score)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SiftTheme.ink)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: product.category.iconName)
                    Text(product.brand.isEmpty ? product.category.displayName : product.brand)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(13)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SiftMiniScore: View {
    let score: Int?

    var body: some View {
        ZStack {
            Circle().fill(scoreColor.opacity(0.14))
            Text(score.map(String.init) ?? "—")
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(scoreColor)
        }
        .frame(width: 48, height: 48)
        .accessibilityLabel(score.map { "Score \($0) out of 100" } ?? "No score")
    }

    private var scoreColor: Color {
        guard let score else { return .secondary }
        switch score {
        case 85...100: return .green
        case 70..<85: return SiftTheme.accent
        case 50..<70: return .orange
        default: return .red
        }
    }
}

struct SiftProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let product: SiftProduct

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 18) {
                        SiftScoreRing(score: product.score)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(product.scoreLabel.uppercased())
                                .font(.caption.weight(.black))
                                .tracking(1.2)
                                .foregroundStyle(scoreColor)
                            Text(product.name)
                                .font(.title2.bold())
                            if !product.brand.isEmpty {
                                Text(product.brand)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Label(product.category.displayName, systemImage: product.category.iconName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if product.score == nil {
                        Label("This product did not include a readable ingredient list.", systemImage: "questionmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding(14)
                            .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        HStack(spacing: 10) {
                            SiftStat(value: "\(product.cautionCount)", title: "Caution", color: .red)
                            SiftStat(value: "\(product.reviewCount)", title: "Review", color: .orange)
                            SiftStat(value: "\(product.ingredients.count)", title: "Explained", color: SiftTheme.accent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        Text("Ingredient notes")
                            .font(.headline)
                        if product.ingredients.isEmpty {
                            Text("No flagged patterns were found in the supplied text. Check the label if you have allergies or specific sensitivities.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(product.ingredients) { ingredient in
                                SiftIngredientRow(ingredient: ingredient)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ingredient list used", systemImage: "text.alignleft")
                            .font(.headline)
                        Text(product.ingredientsText.isEmpty ? "Not provided by the source." : product.ingredientsText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18))

                    Text("Source: \(product.source) · Barcode: \(product.barcode)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
            }
            .background(SiftTheme.cream.ignoresSafeArea())
            .navigationTitle("Product check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var scoreColor: Color {
        guard let score = product.score else { return .secondary }
        switch score {
        case 85...100: return .green
        case 70..<85: return SiftTheme.accent
        case 50..<70: return .orange
        default: return .red
        }
    }
}

struct SiftScoreRing: View {
    let score: Int?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.14), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                if score != nil { Text("/100").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .frame(width: 112, height: 112)
    }

    private var scoreColor: Color {
        guard let score else { return .secondary }
        switch score {
        case 85...100: return .green
        case 70..<85: return SiftTheme.accent
        case 50..<70: return .orange
        default: return .red
        }
    }
}

struct SiftStat: View {
    let value: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SiftIngredientRow: View {
    let ingredient: SiftIngredientInsight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.semibold))
                Text(ingredient.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(ingredient.risk.displayName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch ingredient.risk {
        case .positive: return .green
        case .neutral: return .secondary
        case .review: return .orange
        case .caution: return .red
        }
    }

    private var iconName: String {
        switch ingredient.risk {
        case .positive: return "checkmark.circle.fill"
        case .neutral: return "minus.circle.fill"
        case .review: return "questionmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        }
    }
}

struct SiftManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SiftStore
    @State private var name = ""
    @State private var brand = ""
    @State private var category: SiftCategory = .food
    @State private var ingredients = ""
    let onSaved: (SiftProduct) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Product name (optional)", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    Picker("Category", selection: $category) {
                        ForEach(SiftCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                Section("Ingredients") {
                    TextEditor(text: $ingredients)
                        .frame(minHeight: 150)
                    Text("Paste the label exactly as printed. Sift will show the patterns it recognized.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Check ingredients") {
                        let product = store.saveManualProduct(name: name, brand: brand, category: category, ingredientsText: ingredients)
                        onSaved(product)
                    }
                    .disabled(ingredients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Check ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct SiftScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    let onCode: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                SiftCameraPreview { code in
                    onCode(code)
                }
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal)

                Text("Line up the barcode inside the frame")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Enter barcode instead", text: $manualCode)
                        .keyboardType(.numberPad)
                        .onChange(of: manualCode) { _, value in
                            manualCode = String(value.filter(\.isNumber).prefix(14))
                        }
                        .textFieldStyle(.roundedBorder)
                    Button("Use") { onCode(manualCode) }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualCode.count < 8)
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct SiftCameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> SiftCameraViewController {
        SiftCameraViewController(onCode: context.coordinator.handle)
    }

    func updateUIViewController(_ uiViewController: SiftCameraViewController, context: Context) {}

    final class Coordinator {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func handle(_ code: String) { onCode(code) }
    }
}

@MainActor
final class SiftCameraViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let onCode: (String) -> Void
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didSendCode = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !session.isRunning { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            addCameraInput()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.addCameraInput() }
            }
        default:
            addMessage("Camera access is off. Use the barcode field below.")
        }
    }

    private func addCameraInput() {
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            addMessage("Camera unavailable. Use the barcode field below.")
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        view.layer.insertSublayer(layer, at: 0)
    }

    private func addMessage(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didSendCode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue,
              !code.isEmpty else { return }
        didSendCode = true
        onCode(code)
    }
}
