import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: NetFareStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider = ""
    @State private var planName = ""
    @State private var download = ""
    @State private var upload = ""
    @State private var monthlyCost = ""

    private var suggestions: [ProviderRecord] {
        ProviderCatalog.suggestions(for: provider)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Provider", text: $provider)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    if !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       ProviderCatalog.match(provider) == nil {
                        ForEach(suggestions) { suggestion in
                            Button(suggestion.name) { provider = suggestion.name }
                        }
                    }
                    TextField("Plan name (optional)", text: $planName)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Provider and plan details are optional. NetFare can identify your ISP during a test, and you can edit details later.")
                }

                Section {
                    decimalField("Advertised download Mbps", text: $download)
                    decimalField("Advertised upload Mbps", text: $upload)
                    decimalField("Monthly bill amount", text: $monthlyCost)
                } header: {
                    Text("Optional plan details")
                } footer: {
                    Text("NetFare will still measure your connection if you leave these blank, but it will not invent a plan-value score.")
                }

                Section {
                    Label("Private by default", systemImage: "lock.shield")
                    Text("Profiles and test history are saved locally. A speed test sends only bounded measurement traffic to the documented test endpoint.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continue without details" : "Save") { save() }
                }
            }
        }
    }

    private func decimalField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
    }

    private func save() {
        let downloadValue = positiveDouble(download)
        let uploadValue = positiveDouble(upload)
        let cents = positiveCents(monthlyCost)
        store.addProfile(
            providerName: provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown ISP" : provider,
            planName: planName,
            advertisedDownloadMbps: downloadValue,
            advertisedUploadMbps: uploadValue,
            monthlyCostCents: cents
        )
        dismiss()
    }

    private func positiveDouble(_ text: String) -> Double? {
        let value = Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value, value.isFinite, value > 0, value <= 1_000_000 else { return nil }
        return value
    }

    private func positiveCents(_ text: String) -> Int? {
        let value = Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value, value.isFinite, value > 0, value <= Double(Int.max) / 100 else { return nil }
        return Int((value * 100).rounded())
    }
}
