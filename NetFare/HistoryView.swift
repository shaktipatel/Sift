import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: NetFareStore

    var body: some View {
        NavigationStack {
            List {
                if store.state.tests.isEmpty && store.state.bills.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath", description: Text("Your confirmed tests and bills will appear here."))
                } else {
                    if !store.state.tests.isEmpty {
                        Section("Speed tests") {
                            ForEach(store.state.tests) { test in
                                TestHistoryRow(test: test, provider: provider(for: test.profileID))
                            }
                        }
                    }
                    if !store.state.bills.isEmpty {
                        Section("Bills") {
                            ForEach(store.state.bills) { bill in
                                BillHistoryRow(bill: bill, provider: provider(for: bill.profileID))
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func provider(for profileID: UUID) -> String {
        store.state.profiles.first(where: { $0.id == profileID })?.providerName ?? "Connection"
    }
}

private struct TestHistoryRow: View {
    let test: SpeedTestRun
    let provider: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider).font(.headline)
                Spacer()
                Text(test.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Label(test.medianDownloadMbps.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Mbps" } ?? "—", systemImage: "arrow.down")
                Label(test.medianUploadMbps.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Mbps" } ?? "—", systemImage: "arrow.up")
                Label(test.medianLatencyMs.map { "\($0.formatted(.number.precision(.fractionLength(0)))) ms" } ?? "—", systemImage: "timer")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(test.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct BillHistoryRow: View {
    let bill: BillSnapshot
    let provider: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(provider).font(.headline)
                Text(bill.capturedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let total = bill.totalCents {
                Text((Double(total) / 100).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                    .font(.headline.monospacedDigit())
            } else {
                Text("Needs review").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
