import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NetFareStore
    @State private var showingDeleteConfirmation = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Label("Local-first storage", systemImage: "lock.shield")
                    Text("NetFare does not require an account or cloud database. Speed tests send bounded measurement traffic only after you start them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Your data") {
                    Button {
                        exportURL = store.exportState()
                    } label: {
                        Label("Export local data", systemImage: "square.and.arrow.up")
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share exported JSON", systemImage: "arrow.up.doc")
                        }
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete all local data", systemImage: "trash")
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "NetFare")
                    LabeledContent("Calculation version", value: "1.0")
                    Text("Scores are measurements and comparisons, not a guarantee from your internet provider.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all NetFare data?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { store.deleteAllData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes all profiles, tests and bills from this device. It cannot be undone.")
            }
        }
    }
}
