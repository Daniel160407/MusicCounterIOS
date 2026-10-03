import SwiftUI

@main
struct MusicCounterApp: App {
    @StateObject private var store: Store
    @StateObject private var tracker: Tracker

    init() {
        let store = Store()
        _store = StateObject(wrappedValue: store)
        _tracker = StateObject(wrappedValue: Tracker(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(tracker)
                .task { tracker.start() }
        }
    }
}
