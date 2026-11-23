import ActivityKit
import SwiftUI

/// Bell button: opens the alert settings for a team / player / rider / competition.
struct AlertBell: View {
    let key: String
    let title: String
    var competition = false
    var favorite: Favorite? = nil
    @EnvironmentObject private var store: AppStore
    @State private var open = false

    var body: some View {
        let on = competition ? store.followedCompetitions.contains(key.replacingOccurrences(of: "league:", with: ""))
                             : (favorite.map { f in store.favorites.contains { $0.id == f.id } } ?? false)
        Button { open = true } label: {
            Image(systemName: on ? "bell.fill" : "bell")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(on ? .yellow : .white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) {
            AlertSettingsSheet(key: key, title: title, competition: competition, favorite: favorite)
                .presentationDetents([.medium, .large])
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct AlertSettingsSheet: View {
    let key: String
    let title: String
    var competition = false
    var favorite: Favorite? = nil
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var engine = AlertEngine.shared
    @Environment(\.dismiss) private var dismiss

    private var leagueId: String { key.replacingOccurrences(of: "league:", with: "") }

    private var following: Binding<Bool> {
        Binding(
            get: {
                if competition { return store.followedCompetitions.contains(leagueId) }
                guard let f = favorite else { return false }
                return store.favorites.contains { $0.id == f.id }
            },
            set: { on in
                if competition {
                    if on { store.followedCompetitions.insert(leagueId) } else { store.followedCompetitions.remove(leagueId) }
                } else if let f = favorite {
                    let has = store.favorites.contains { $0.id == f.id }
                    if on != has { store.toggle(f) }
                }
                if on { Task { await engine.requestPermission() } }
            })
    }

    private func pref(_ kp: WritableKeyPath<AlertPrefs, Bool>) -> Binding<Bool> {
        Binding(
            get: { (store.alertPrefs[key] ?? (competition ? .competitionDefault : AlertPrefs()))[keyPath: kp] },
            set: { v in
                var p = store.alertPrefs[key] ?? (competition ? .competitionDefault : AlertPrefs())
                p[keyPath: kp] = v
                store.alertPrefs[key] = p
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(competition ? "Follow \(title)" : "Follow \(title)", isOn: following)
                } footer: {
                    Text(competition ? "Alerts for every game in this competition." : "Also adds \(title) to My Teams.")
                }
                if following.wrappedValue {
                    Section("Notify me about") {
                        Toggle("Starts in 15 minutes", isOn: pref(\.reminder))
                        Toggle("Kick-off / start", isOn: pref(\.start))
                        Toggle("Goals, tries and runs", isOn: pref(\.scores))
                        Toggle("Half-time and period ends", isOn: pref(\.periods))
                        Toggle("Final result", isOn: pref(\.final))
                    }
                    Section {
                        Toggle("Live Activity on the Lock Screen", isOn: pref(\.liveActivity))
                    } footer: {
                        Text("Starts automatically when the game begins.")
                    }
                }
                Section {
                    if !engine.authorized {
                        Button("Allow notifications") { Task { await engine.requestPermission() } }
                    }
                } footer: {
                    Text("While Scoreline is closed, iOS decides when it may check for updates (usually every 15–60 minutes), so alerts and Live Activity scores can be delayed. Start reminders are always on time. Real-time alerts need a push server, which can be added later.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await engine.refreshAuthorization() }
        }
    }
}

/// Start / stop a Live Activity for a game from its page.
struct LiveActivityButton: View {
    let game: Game
    @State private var running = false

    var body: some View {
        if game.state != .post && ActivityAuthorizationInfo().areActivitiesEnabled {
            Button {
                Task { @MainActor in
                    if running {
                        await AlertEngine.shared.stopActivity(gameId: game.id)
                        running = false
                    } else {
                        running = AlertEngine.shared.startActivity(for: game)
                    }
                }
            } label: {
                Label(running ? "Live Activity on" : "Live Activity", systemImage: running ? "bolt.fill" : "bolt")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(running ? Color.yellow.opacity(0.25) : .white.opacity(0.15), in: Capsule())
                    .foregroundStyle(running ? .yellow : .white)
            }
            .buttonStyle(.plain)
            .task { running = AlertEngine.shared.activity(for: game.id) != nil }
        }
    }
}

/// Settings section listing everything that sends alerts.
struct NotificationSettingsSection: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var engine = AlertEngine.shared

    var body: some View {
        Section {
            HStack {
                Text("Notifications")
                Spacer()
                Text(engine.authorized ? "Allowed" : "Off").foregroundStyle(Theme.secondary)
            }
            if !engine.authorized {
                Button("Allow notifications") { Task { await engine.requestPermission() } }
            }
            ForEach(store.favorites) { f in
                NavigationLink {
                    AlertSettingsSheet(key: f.id, title: f.name, favorite: f)
                } label: {
                    Label(f.name, systemImage: f.kind == .team ? "person.3" : f.kind == .rider ? "bicycle" : "tennis.racket")
                }
            }
            ForEach(Array(store.followedCompetitions).sorted(), id: \.self) { id in
                if let l = League.byId(id) {
                    NavigationLink {
                        AlertSettingsSheet(key: "league:\(id)", title: l.name, competition: true)
                    } label: {
                        Label(l.name, systemImage: "trophy")
                    }
                }
            }
        } header: {
            Text("Alerts & Live Activities")
        } footer: {
            Text("Follow teams with the star or bell on their page, and competitions with the bell on the league page.")
        }
    }
}
