import ActivityKit
import BackgroundTasks
import Foundation
import UserNotifications

// MARK: - Preferences

/// What to be told about a followed team, player, rider or competition.
struct AlertPrefs: Codable, Hashable {
    var reminder = true      // 15 minutes before start
    var start = true         // kick-off / tip-off / first pitch
    var scores = true        // goals, tries, runs (football, rugby, baseball)
    var periods = false      // half-time, end of quarter / period
    var final = true         // final result
    var liveActivity = true  // Lock Screen live score while playing

    static let competitionDefault = AlertPrefs(reminder: false, start: false, scores: false, periods: false, final: true, liveActivity: false)
}

/// One subscription: a team, player, rider or competition with its preferences.
/// Codable so a future push server can receive exactly this list.
struct AlertSubscription: Codable, Hashable {
    enum Kind: String, Codable { case team, competition, tennisPlayer, rider }
    let kind: Kind
    let leagueId: String
    let entityId: String
    let name: String
    let prefs: AlertPrefs
}

// MARK: - Backend (local now, push server later)

/// Where alerts come from. `LocalAlertBackend` does everything on the phone.
/// A future `RemoteAlertBackend` would upload the device token, subscriptions and
/// Live Activity push tokens to a server that sends APNs pushes in real time.
/// Swapping backends doesn't change preferences, UI or the Live Activity layout.
protocol AlertBackend {
    /// True when a server pushes updates (Live Activities then use push tokens).
    var deliversRemotely: Bool { get }
    func register(deviceToken: Data) async
    func sync(_ subscriptions: [AlertSubscription]) async
    func liveActivityStarted(gameId: String, pushToken: Data?) async
}

struct LocalAlertBackend: AlertBackend {
    var deliversRemotely: Bool { false }
    func register(deviceToken: Data) async {}
    func sync(_ subscriptions: [AlertSubscription]) async {}
    func liveActivityStarted(gameId: String, pushToken: Data?) async {}
}

// MARK: - Engine

@MainActor
final class AlertEngine: ObservableObject {
    static let shared = AlertEngine()
    static let refreshTaskId = "com.scoreline.refresh"

    /// Replace with a remote backend once a push server exists.
    var backend: AlertBackend = LocalAlertBackend()

    @Published private(set) var authorized = false

    private let snapshotKey = "alertSnapshot"
    private let store = AppStore.shared

    // MARK: Permission

    func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = ok
        return ok
    }

    // MARK: Subscriptions

    var subscriptions: [AlertSubscription] {
        var out: [AlertSubscription] = store.favorites.map { f in
            let kind: AlertSubscription.Kind = f.kind == .team ? .team : f.kind == .rider ? .rider : .tennisPlayer
            return AlertSubscription(kind: kind, leagueId: f.leagueId, entityId: f.entityId, name: f.name,
                                     prefs: store.alertPrefs[f.id] ?? AlertPrefs())
        }
        for id in store.followedCompetitions {
            out.append(AlertSubscription(kind: .competition, leagueId: id, entityId: id, name: League.byId(id)?.name ?? id,
                                         prefs: store.alertPrefs["league:\(id)"] ?? .competitionDefault))
        }
        // Alerts for hidden (unfollowed) leagues pause; their settings stay saved.
        // Tennis players and riders belong to the "atp" / "cycling" leagues.
        let hidden = store.hiddenLeagues
        return out.filter { !hidden.contains($0.leagueId) }
    }

    // MARK: Refresh (foreground timer and background task)

    /// Checks followed games, posts notifications for changes, keeps Live Activities current
    /// and schedules start reminders.
    func refresh() async {
        let subs = subscriptions
        await backend.sync(subs)
        guard !subs.isEmpty else { return }
        let games = await watchedGames(subs)
        var snapshot = (UserDefaults.standard.dictionary(forKey: snapshotKey) as? [String: String]) ?? [:]
        for (game, prefs) in games {
            let key = "\(game.state.rawValue)|\(game.home.score ?? "")|\(game.away.score ?? "")|\(game.statusText)"
            if let old = snapshot[game.id], old != key, authorized {
                notifyChanges(game: game, old: old, prefs: prefs)
            }
            snapshot[game.id] = key
            if prefs.liveActivity { await updateLiveActivity(for: game, autoStart: true) }
        }
        // Keep the snapshot small.
        let ids = Set(games.map(\.0.id))
        snapshot = snapshot.filter { ids.contains($0.key) }
        UserDefaults.standard.set(snapshot, forKey: snapshotKey)
        await scheduleReminders(games)
        await endFinishedActivities()
    }

    /// Today's (and soon-starting) games for followed teams and competitions, with the prefs that apply.
    private func watchedGames(_ subs: [AlertSubscription]) async -> [(Game, AlertPrefs)] {
        var byLeague: [String: [AlertSubscription]] = [:]
        for s in subs where s.kind == .team || s.kind == .competition { byLeague[s.leagueId, default: []].append(s) }
        var out: [(Game, AlertPrefs)] = []
        for (leagueId, list) in byLeague {
            guard let league = League.byId(leagueId), league.isTeamSport else { continue }
            // Keep background work small: yesterday (late games), today and tomorrow.
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let days = [-1, 0, 1].compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            let games: [Game]
            if league.provider == .bbl {
                games = ((try? await BBL.games()) ?? []).filter { abs($0.date.timeIntervalSinceNow) < 86_400 * 1.5 }
            } else {
                games = ((try? await GameFeed.days(league, days)) ?? []).filter { abs($0.date.timeIntervalSinceNow) < 86_400 * 1.5 }
            }
            for g in games {
                let teamSub = list.first { $0.kind == .team && ($0.entityId == g.home.id || $0.entityId == g.away.id) }
                let compSub = list.first { $0.kind == .competition }
                if let prefs = teamSub?.prefs ?? compSub?.prefs { out.append((g, prefs)) }
            }
        }
        return out
    }

    private func notifyChanges(game g: Game, old: String, prefs: AlertPrefs) {
        let parts = old.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return }
        let oldState = parts[0], oldHome = parts[1], oldAway = parts[2], oldStatus = parts[3]
        let l = g.ordered.left, r = g.ordered.right
        let line = "\(l.short) \(l.score ?? "0")–\(r.score ?? "0") \(r.short)"
        let fam = g.league.family

        if oldState == "pre" && g.state == .live && prefs.start {
            post(id: "start-\(g.id)", title: "\(l.short) vs \(r.short) has started", body: g.league.name)
        }
        let homeChanged = oldHome != (g.home.score ?? "")
        let awayChanged = oldAway != (g.away.score ?? "")
        if oldState == "in" && g.state == .live && prefs.scores && fam != .basketball && (homeChanged || awayChanged) {
            let team = homeChanged ? g.home.short : g.away.short
            let detail = g.scorers.last?.text ?? g.events.last.map { "\($0.kind) · \($0.player) \($0.minute)" }
            let emoji = fam == .soccer ? "⚽ " : fam == .rugby ? "🏉 " : fam == .baseball ? "⚾ " : ""
            post(id: "score-\(g.id)-\(g.home.score ?? "")-\(g.away.score ?? "")",
                 title: "\(emoji)\(team) score\(fam == .soccer ? "" : "s")" + (fam == .soccer ? "s!" : ""),
                 body: [line, detail].compactMap { $0 }.joined(separator: " · "))
        }
        if g.state == .live && prefs.periods && oldStatus != g.statusText {
            let s = g.statusText.lowercased()
            if s == "ht" || s.contains("half") || s.hasPrefix("end of") {
                post(id: "period-\(g.id)-\(g.statusText)", title: "\(g.statusText == "HT" ? "Half-time" : g.statusText)", body: line)
            }
        }
        if oldState != "post" && g.state == .post && prefs.final {
            post(id: "final-\(g.id)", title: "Final: \(line)", body: g.league.name)
        }
    }

    private func post(id: String, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = "scores"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// "Starts in 15 minutes" reminders, scheduled ahead so they're on time even when the app is closed.
    private func scheduleReminders(_ games: [(Game, AlertPrefs)]) async {
        guard authorized else { return }
        let center = UNUserNotificationCenter.current()
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        for (g, prefs) in games where prefs.reminder && g.state == .pre {
            let fire = g.date.addingTimeInterval(-15 * 60)
            let id = "reminder-\(g.id)"
            guard fire > Date(), !pending.contains(id) else { continue }
            let c = UNMutableNotificationContent()
            c.title = "\(g.ordered.left.short) vs \(g.ordered.right.short)"
            c.body = "Starts in 15 minutes · \(g.league.name)"
            c.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: id, content: c,
                                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    // MARK: Live Activities

    static func attributes(for g: Game) -> ScoreActivityAttributes {
        ScoreActivityAttributes(gameId: g.id, leagueId: g.leagueId, leagueName: g.league.name,
                                homeName: g.home.short, homeAbbr: g.home.abbr, homeColor: g.home.tintHex ?? "444444",
                                awayName: g.away.short, awayAbbr: g.away.abbr, awayColor: g.away.tintHex ?? "444444",
                                start: g.date, homeFirst: g.league.family == .soccer || g.league.family == .rugby)
    }

    static func content(for g: Game) -> ScoreActivityAttributes.ContentState {
        let last = g.scorers.last.map { "⚽ \($0.text)" } ?? g.events.last.map { "\($0.kind): \($0.player) \($0.minute)" }
        return .init(homeScore: g.home.score ?? "0", awayScore: g.away.score ?? "0",
                     status: g.state == .post ? "Final" : g.statusText, state: g.state.rawValue, lastEvent: last)
    }

    func activity(for gameId: String) -> Activity<ScoreActivityAttributes>? {
        Activity<ScoreActivityAttributes>.activities.first { $0.attributes.gameId == gameId }
    }

    /// Starts (if allowed) or updates the Live Activity for a game.
    func updateLiveActivity(for g: Game, autoStart: Bool) async {
        let state = Self.content(for: g)
        if let a = activity(for: g.id) {
            if g.state == .post {
                await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
            } else {
                await a.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60)))
            }
            return
        }
        guard autoStart, g.state == .live || (g.state == .pre && g.date.timeIntervalSinceNow < 15 * 60) else { return }
        _ = startActivity(for: g)
    }

    @discardableResult
    func startActivity(for g: Game) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity(for: g.id) == nil, g.state != .post else { return false }
        do {
            let a = try Activity.request(attributes: Self.attributes(for: g),
                                         content: ActivityContent(state: Self.content(for: g), staleDate: Date().addingTimeInterval(30 * 60)),
                                         pushType: backend.deliversRemotely ? .token : nil)
            if backend.deliversRemotely {
                Task {
                    for await token in a.pushTokenUpdates { await backend.liveActivityStarted(gameId: g.id, pushToken: token) }
                }
            }
            return true
        } catch {
            return false
        }
    }

    func stopActivity(gameId: String) async {
        await activity(for: gameId)?.end(nil, dismissalPolicy: .immediate)
    }

    private func endFinishedActivities() async {
        for a in Activity<ScoreActivityAttributes>.activities where a.content.state.state == "post" || a.attributes.start < Date().addingTimeInterval(-6 * 3600) {
            await a.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
        }
    }

    // MARK: Background refresh

    /// iOS decides when this actually runs (typically every 15–60 minutes).
    nonisolated static func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        req.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
