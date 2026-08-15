import SwiftUI

@main
struct NaviLyricsApp: App {
    @State private var settings = AppSettings()
    @State private var player = PlayerStore()
    @State private var session = NavidromeSession()
    @State private var history = ListeningHistoryStore()
    @State private var behavior = PlaybackBehaviorStore()
    @State private var favorites = FavoritesStore()
    @State private var recommendationCache = PersonalizedRecommendationCache()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(player)
                .environment(session)
                .environment(history)
                .environment(behavior)
                .environment(favorites)
                .environment(recommendationCache)
        }
    }
}
