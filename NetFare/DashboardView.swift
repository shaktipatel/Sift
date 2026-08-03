import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: NetFareStore
    @State private var showingSetup = false
    @State private var showingSpeedTest = false
    @State private var showingBill = false

    private var profile: ConnectionProfile? { store.selectedProfile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let profile {
                        profilePicker(profile)
                        scoreCard(profile)
                        actionRow(profile)
                        billCard(profile)
                        lastTestCard(profile)
                    } else {
                        ContentUnavailableView("Add a connection", systemImage: "wifi.router", description: Text("NetFare needs a provider profile before it can show a comparison."))
                    }
                }
                .padding()
            }
            .navigationTitle("NetFare")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSetup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add connection")
                }
            }
            .sheet(isPresented: $showingSetup) { SetupView() }
            .sheet(isPresented: $showingSpeedTest) {
                if let profile { SpeedTestView(profile: profile) }
            }
            .sheet(isPresented: $showingBill) {
                if let profile { BillEntryView(profile: profile) }
            }
        }
    }

    private func profilePicker(_ profile: ConnectionProfile) -> some View {
        Menu {
            ForEach(store.state.profiles) { candidate in
                Button {
                    store.selectProfile(candidate.id)
                } label: {
                    Label(candidate.displayName, systemImage: candidate.id == profile.id ? "checkmark" : "wifi")
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(profile.displayName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scoreCard(_ profile: ConnectionProfile) -> some View {
        let latest = store.latestTest(for: profile.id)
        let score = latest.map { NetFareScoring.score(profile: profile, run: $0) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(score?.overall.map { String($0) } ?? "—")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text(score?.overall == nil ? "score" : "/ 100")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: score?.overall == nil ? "questionmark.circle" : "checkmark.seal")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Text(score?.title ?? "No test yet")
                .font(.title3.bold())
            Text(score?.detail ?? "Run a 10-second test to see your live speed and detect your ISP. Add plan details later for a value comparison.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let latest {
                Text("Last measured \(latest.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(latest.confidence.displayName) confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            Text("CURRENT PATH")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.trailing, 16)
        }
    }

    private func actionRow(_ profile: ConnectionProfile) -> some View {
        HStack(spacing: 12) {
            Button {
                showingSpeedTest = true
            } label: {
                Label("Test now", systemImage: "gauge.with.dots.needle.67percent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingBill = true
            } label: {
                Label("Add bill", systemImage: "doc.text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func billCard(_ profile: ConnectionProfile) -> some View {
        let bills = store.bills(for: profile.id)
        let drift: PriceDrift? = {
            guard bills.count >= 2 else { return nil }
            return NetFareScoring.priceDrift(previous: bills[1], current: bills[0])
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Label("Bill watch", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            if let drift {
                Text(drift.isIncrease ? "Your latest bill is up \(currency(drift.deltaCents))" : "Your latest bill is down \(currency(abs(drift.deltaCents)))")
                    .font(.subheadline.bold())
                Text("That is a \(drift.percent.formatted(.number.precision(.fractionLength(1))))% change from the last confirmed bill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add two confirmed bills to see price drift and promotion changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private func lastTestCard(_ profile: ConnectionProfile) -> some View {
        let latest = store.latestTest(for: profile.id)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Latest measurements", systemImage: "waveform.path.ecg")
                .font(.headline)
            HStack(spacing: 8) {
                MetricTile(title: "Download", value: latest?.medianDownloadMbps.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Mbps" } ?? "—")
                MetricTile(title: "Upload", value: latest?.medianUploadMbps.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Mbps" } ?? "—")
                MetricTile(title: "Latency", value: latest?.medianLatencyMs.map { "\($0.formatted(.number.precision(.fractionLength(0)))) ms" } ?? "—")
            }
            if let latest, let reason = latest.failureReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func currency(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
