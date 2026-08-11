import SwiftUI

@main
struct NaviLyricsApp: App {
    @State private var settings = AppSettings()
    @State private var player = PlayerStore()
    @State private var session = NavidromeSession()
    @State private var history = ListeningHistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(player)
                .environment(session)
                .environment(history)
        }
    }
}
