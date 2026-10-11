import SwiftUI

@main
struct CindyTrackerApp: App {
    init() {
        // The daily reminder is planned on launch, and every time the app comes forward.
        MainActor.assumeIsolated { ReminderCenter.shared.start() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
