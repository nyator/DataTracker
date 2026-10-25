import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.scenePhase) private var scenePhase

    /// Re-reads the counters every minute while the app is on screen.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            DashboardView()
                .navigationTitle("DataTracker")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
        }
        .task {
            await Notifier.requestAuthorization()
            model.refresh()   // a threshold already crossed alerts now that it can
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.refresh()
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
        .onReceive(ticker) { _ in
            if scenePhase == .active { model.refresh() }
        }
    }
}
