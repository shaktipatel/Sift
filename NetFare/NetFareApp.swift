import SwiftUI

@main
struct SiftApp: App {
    @StateObject private var store = SiftStore()

    var body: some Scene {
        WindowGroup {
            SiftRootView()
                .environmentObject(store)
        }
    }
}
