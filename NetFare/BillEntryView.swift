import PhotosUI
import SwiftUI

struct BillEntryView: View {
    @EnvironmentObject private var store: NetFareStore
    @Environment(\.dismiss) private var dismiss
    let profile: ConnectionProfile

    @State private var providerName: String
    @State private var total = ""
    @State private var basePrice = ""
    @State private var equipmentFee = ""
    @State private var promotionalText = ""
    @State private var confirmed = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isScanning = false
    @State private var scanMessage: String?

    init(profile: ConnectionProfile) {
        self.profile = profile
        _providerName = State(initialValue: profile.providerName)
    }

    var body: some View {
        let scanning = isScanning
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(scanning ? "Reading bill…" : "Scan a bill photo", systemImage: "camera.viewfinder")
                    }
                    .disabled(scanning)
                    .onChange(of: selectedPhoto) { _, item in
                        guard let item else { return }
                        Task { await scan(item) }
                    }
                    if let scanMessage {
                        Text(scanMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Local scan")
                } footer: {
                    Text("NetFare uses on-device text recognition. Confirm every extracted field before saving.")
                }

                Section("Confirm bill details") {
                    TextField("Provider", text: $providerName)
                    currencyField("Total bill", text: $total)
                    currencyField("Base service", text: $basePrice)
                    currencyField("Equipment fee", text: $equipmentFee)
                    TextField("Promotion or price note", text: $promotionalText, axis: .vertical)
                    Toggle("I confirmed these fields", isOn: $confirmed)
                }
            }
            .navigationTitle("Add bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!confirmed || positiveCents(total) == nil)
                }
            }
        }
    }

    private func currencyField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
    }

    private func scan(_ item: PhotosPickerItem) async {
        isScanning = true
        defer { isScanning = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw BillScannerError.invalidImage }
            let draft = try await BillScanner.scan(data: data)
            providerName = draft.providerName.isEmpty ? profile.providerName : draft.providerName
            total = draft.totalCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            basePrice = draft.basePriceCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            equipmentFee = draft.equipmentFeeCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            promotionalText = draft.promotionalText ?? ""
            scanMessage = "Scan complete. Review every field before saving."
        } catch {
            scanMessage = error.localizedDescription
        }
    }

    private func save() {
        store.addBill(BillSnapshot(
            profileID: profile.id,
            providerName: providerName.isEmpty ? profile.providerName : providerName,
            totalCents: positiveCents(total),
            basePriceCents: positiveCents(basePrice),
            equipmentFeeCents: positiveCents(equipmentFee),
            promotionalText: promotionalText.isEmpty ? nil : promotionalText,
            ocrConfidence: scanMessage == nil ? nil : 0.5,
            userConfirmed: confirmed
        ))
        dismiss()
    }

    private func positiveCents(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value.isFinite, value > 0, value <= Double(Int.max) / 100 else { return nil }
        return Int((value * 100).rounded())
    }
}
