import SwiftUI

@main
struct ScorelineApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Generous image cache so team logos and flags survive relaunches.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        CrashLog.install()
        // Navigation bar: see-through over the page colour at the top, dark blur when scrolled.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        scrolled.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        for nav in [edge, scrolled] {
            nav.shadowColor = .clear
            nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 34, weight: .heavy)]
            nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        }
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().compactAppearance = scrolled
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(AlertEngine.shared)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await AlertEngine.shared.refreshAuthorization()
                    // While the app is open: check followed games every minute.
                    while !Task.isCancelled {
                        await AlertEngine.shared.refresh()
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AlertEngine.scheduleBackgroundRefresh() }
        }
        .backgroundTask(.appRefresh(AlertEngine.refreshTaskId)) {
            AlertEngine.scheduleBackgroundRefresh()
            await AlertEngine.shared.refresh()
        }
    }
}
