import SwiftUI

@main
struct MessengerApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(Prefs.shared)
                .environmentObject(AppUI.shared)
        }
    }
}
