import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject private var store: NetFareStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var pathMonitor = NetworkPathMonitor()
    @StateObject private var engine = SpeedTestEngine()
    @State private var allowCellular = true
    @State private var allowConstrained = true
    @State private var isRunning = false
    @State private var completedRun: SpeedTestRun?
    @State private var detectedProviderName: String?

    let profile: ConnectionProfile

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    pathCard
                    speedometerCard
                    if let completedRun {
                        resultCard(completedRun)
                    }
                    if !isRunning && completedRun == nil {
                        consentCard
                    }
                    Button(isRunning ? "Cancel test" : "Test my connection") {
                        if isRunning {
                            engine.cancel()
                        } else {
                            startTest()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!pathMonitor.snapshot.isSatisfied && !isRunning)
                }
                .padding()
            }
            .navigationTitle("Speed test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isRunning)
                }
            }
            .task { pathMonitor.start() }
            .onDisappear { pathMonitor.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, isRunning {
                    engine.cancel()
                }
            }
        }
    }

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current path", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            HStack {
                Text(pathMonitor.snapshot.statusText)
                    .font(.title3.bold())
                Spacer()
                Circle()
                    .fill(pathMonitor.snapshot.isSatisfied ? .green : .red)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel(pathMonitor.snapshot.isSatisfied ? "Connected" : "Offline")
            }
            HStack(spacing: 8) {
                Image(systemName: "building.2")
                    .foregroundStyle(.tint)
                Text(detectedProviderName ?? (isRunning ? "Detecting your ISP…" : "ISP detected during the test"))
                    .font(.subheadline.weight(.medium))
            }
            Text("NetFare measures this path only. If your phone switches networks, the test stops instead of mixing results.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var speedometerCard: some View {
        VStack(spacing: 10) {
            SpeedometerView(speedMbps: engine.progress.liveMbps ?? 0, phase: engine.progress.phase)
            HStack {
                Text(engine.progress.message)
                    .font(.headline)
                Spacer()
                Text("\(engine.progress.remainingSeconds)s")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: engine.progress.fraction)
                .tint(.accentColor)
            Text("10-second test • live results stay on this device")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Allow cellular / metered testing", isOn: $allowCellular)
            Toggle("Allow Low Data Mode testing", isOn: $allowConstrained)
            Text("Estimated maximum: \(estimatedDataBudget)")
                .font(.footnote.monospacedDigit())
            Text("One tap is ready by default. Cellular tests use a smaller transfer; you can turn either option off any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var estimatedDataBudget: String {
        let metered = pathMonitor.snapshot.isExpensive || pathMonitor.snapshot.interface == .cellular
        let bytes: Int64 = metered ? 5_000_000 : 25_000_000
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func resultCard(_ run: SpeedTestRun) -> some View {
        let score = NetFareScoring.score(profile: profile, run: run)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(score.overall.map { String($0) } ?? "—")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text(score.overall == nil ? "score" : "/ 100")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(run.confidence.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            Text(score.title).font(.title3.bold())
            Text(score.detail).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                MetricTile(title: "Down", value: run.medianDownloadMbps.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Mbps" } ?? "—")
                MetricTile(title: "Up", value: run.medianUploadMbps.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Mbps" } ?? "—")
                MetricTile(title: "Ping", value: run.medianLatencyMs.map { "\($0.formatted(.number.precision(.fractionLength(0)))) ms" } ?? "—")
            }
            Text("Data used: \(ByteCountFormatter.string(fromByteCount: run.dataUsedBytes, countStyle: .file)). \(run.interface.displayName).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let failureReason = run.failureReason, !failureReason.isEmpty {
                Text(failureReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func startTest() {
        completedRun = nil
        detectedProviderName = nil
        isRunning = true
        let initial = pathMonitor.snapshot
        Task {
            let run = await engine.run(
                profileID: profile.id,
                initialPath: initial,
                allowCellular: allowCellular,
                allowConstrained: allowConstrained,
                currentPath: { pathMonitor.snapshot }
            )
            if let detected = engine.detectedProviderName {
                detectedProviderName = detected
                if profile.providerName.isEmpty || profile.providerName == "Unknown ISP" {
                    var updated = profile
                    updated.providerName = detected
                    store.updateProfile(updated)
                }
            }
            store.addTest(run)
            completedRun = run
            isRunning = false
        }
    }
}

private struct SpeedometerView: View {
    let speedMbps: Double
    let phase: TestPhase

    private var maximum: Double {
        max(100, ceil(max(speedMbps, 1) / 100) * 100)
    }

    private var normalized: Double {
        min(1, max(0, speedMbps / maximum))
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.125, to: 0.875)
                .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.125, to: 0.125 + 0.75 * normalized)
                .stroke(AngularGradient(colors: [.blue, .cyan, .green, .yellow], center: .center), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.35), value: speedMbps)
            Rectangle()
                .fill(.primary)
                .frame(width: 3, height: 72)
                .offset(y: -36)
                .rotationEffect(.degrees(-135 + 270 * normalized))
                .animation(.easeOut(duration: 0.35), value: speedMbps)
            Circle()
                .fill(.primary)
                .frame(width: 12, height: 12)
            VStack(spacing: 1) {
                Text(speedMbps > 0 ? speedMbps.formatted(.number.precision(.fractionLength(0))) : "—")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Mbps")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(phaseLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .offset(y: 26)
        }
        .frame(height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(speedMbps.formatted(.number.precision(.fractionLength(0)))) megabits per second, \(phaseLabel)")
    }

    private var phaseLabel: String {
        switch phase {
        case .preparing: "Ready"
        case .latency: "Ping"
        case .download: "Download"
        case .upload: "Upload"
        case .calculating: "Finishing"
        case .finished: "Complete"
        }
    }
}
