# Scoreline for iPhone

**Version 1.6.2 (build 11)**. The installed version is shown under Settings → About.

A native SwiftUI score tracker styled after Apple Sports.

| League | What you get |
|---|---|
| NBA, MLB | Live scores (Yesterday / Today / Upcoming), line score, game leaders / pitching decisions, team stats, box scores, standings with playoff zones, stat leaders. The NBA page also has the NBA Cup (groups, wild cards, knockout). |
| easyCredit BBL | Live scores, quarter scores, box scores, team stats, standings with playoff, play-in and relegation zones. Data from easycredit-bbl.de, since ESPN doesn't cover the BBL. |
| Premier League, Bundesliga, 2. Bundesliga | Live scores with scorers, match events, lineups on a formation pitch, team stats, live tables with labelled zones, top scorers and assists |
| Champions League, Europa League, Conference League | The same, with league-phase tables (Round of 16 / knockout play-offs / eliminated) |
| DFB-Pokal, FA Cup | Results and fixtures by round, including penalties |
| Premiership Rugby | Live scores, scoring events (tries, conversions, penalties), lineups, table with bonus points and play-off zone |
| ATP World Tour | The full season, with tournament logos: Grand Slams, Masters 1000, 500, 250, ATP Finals (group tables), Next Gen Finals, plus Davis Cup and Laver Cup from Wikipedia. Draws, live scores and ATP rankings. |
| UCI World Tour | Grand Tours in full, plus the whole WorldTour calendar: stage races (stages, GC, jerseys) and one-day races (results, Monuments). Rider pages (team history, major wins, season results) and team pages (roster, season wins). |

**Everywhere:**
* An Apple Sports-style league switcher with search and live league status.
* Favourite teams, players and riders, with a My Teams section on Home.
* Tap any team or player to open their page: schedule, roster, stats, game log and career.
  Football teams and players can be filtered by competition (league, cup or European).
* Football player photos come from FotMob, matched by name and club.

## Notifications and Live Activities

* Follow a team, player or rider (star or bell on their page), or a competition (bell on the league page).
* **Per subscription:** a 15-minute start reminder, kick-off, goals/tries/runs, half-time and period ends, the final result, and an automatic Lock Screen Live Activity.
* Game pages have a **Live Activity** button for one-off games.
* **How updates arrive now:** they're local. While the app is open it checks every minute; while it's closed, iOS background refresh decides when it may check (typically every 15–60 minutes). Start reminders are scheduled ahead and are always on time.
* **Real time later:** `Services/Alerts.swift` defines an `AlertBackend` protocol. A future server-backed implementation (paid Apple Developer account + a small server such as a Cloudflare Worker sending APNs pushes) would receive the same `AlertSubscription` list and the Live Activity push tokens. The Live Activity's `ContentState` is already push-compatible.
* The Live Activity lives in a widget extension (`ios/ScorelineWidgets`). Code shared by the app and the extension is in `ios/Shared`.

## Checks and screenshots on every build

Every push to `main` builds the app on GitHub, then runs it on an iPhone 13 simulator:

* **Data source checks:** about 40 live checks of ESPN, easycredit-bbl.de, Wikipedia and FotMob
  (standings, scores, box scores, lineups, team and player pages, tennis draws and rankings,
  Grand Tours, WorldTour races, rider pages, logos and photos). The results appear in the run's
  summary, and the build is marked failed if a source changed its format. The same checks can be
  run on the phone under Settings → Check data sources.
* **Screenshots** of the main screens (every league, game pages with lineups and stats, team and
  player pages, NBA Cup, tennis, cycling, settings) are published to the
  [`screenshots` branch](../../tree/screenshots) and attached to the run.

## Version history

| Version | Changes |
|---|---|
| 1.5.3 (8) | Polish round: league name as page title, alerts bell in the top bar, one German date style, short club names, collapsible sport groups, lineup pitch readability, NBA Cup knockout only from real Cup games, Grand Tours filter fix; new data: BBL stat leaders, MLB stats by league (MLB/AL/NL) and type (hitting/pitching/fielding), full team stats, tennis player season and career stats, rugby squads, tier and tournament logos, backup player photos, clickable game logs |
| 1.6 (9) | Match data: game previews (predictor, odds, form, season series, head-to-head, injuries), NBA/MLB play-by-play with win probability chart, football expected goals, shot map, momentum and player ratings (FotMob); cycling Race Calendar and Rankings tabs (UCI World Tour riders and teams, most wins), race logos, clickable jersey winners, fixed cycling team pages; rugby squads; tennis tournament logos from German Wikipedia, ATP tier logos; bigger game leader numbers, BBL league ranks, MLB division leaders and AL/NL titles, reliable AL/NL stat leaders, football competition table with logos and links |
| 1.6.1 (10) | Fixes and polish: swipeable win probability and football momentum with key moments, play-by-play by quarter (faster), box score redesign (starters/bench, positions, photos, leaders in bold), BBL game leaders, decimal odds, clickable form and last five meetings, live standings with full names and opponent codes, no cut-off team names, player photos from FotMob/Wikipedia when ESPN has none, football competition table (logos, DFB-Pokal/FA Cup), bundled ATP 250/500/1000 badges, tennis match pages and headshots from ATP Tour/SofaScore, transparent race logos, cycling Teams tab |
| 1.6.2 (11) | Fixes: key moments as runs and lead changes, Plays split into Win Probability and Play-by-Play, box scores with fixed columns (team row aligned) and alternating full-row shading, game leader names fit, BBL whole minutes and Rostock, FotMob lookup for Champions League, momentum icons and 90' mark, moneyline-only decimal odds, one-line team names in standings, transparent World Cup logo, cycling ProTeams without duplicates, team logo fallback, rider photos in rankings |
| 1.5.1 (7) | Fix: the Live Activity extension's bundle ID was ".widgets" instead of the app ID plus ".widgets", so Xcode couldn't register it |
| 1.5 (6) | Data source checks (Settings → Check data sources, and on every GitHub build), iPhone 13 simulator screenshots on every build, faster loading: image cache, instant tab switching and back navigation, My Teams loads in parallel |
| 1.4 (5) | Notifications and Live Activities for followed teams and competitions; version number in Settings |
| 1.3 (4) | Premiership Rugby, NBA Cup page, Stats tabs, all UCI WorldTour races, rider and team pages, tournament logos, Davis Cup and Laver Cup, rankings with flags and photos, expandable league menu |
| 1.2 (3) | easyCredit BBL rename, iPhone 13 layout fixes, player photos for stat leaders, game detail tabs with formations, ATP 1000/500/250, ATP Finals and rankings, Europa League, Conference League, DFB-Pokal, FA Cup, NBA Cup |
| 1.1 (2) | Live standings with zones, favourites, team and player pages, league switcher, logos, Basketball Bundesliga |
| 1.0 (1) | First version: NBA, MLB, Premier League, Bundesliga, 2. Bundesliga, Champions League, Grand Slams, Grand Tours |

The version is set in `ios/Config/Base.xcconfig` (`MARKETING_VERSION` and the build number `CURRENT_PROJECT_VERSION`) and is raised with every update.

## Install on your iPhone (always up to date)

**Requirements:** a Mac with Xcode 16 or newer, and your Apple ID added in Xcode (Settings → Accounts).

Run this once in Terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Rainmaker07/Scoreline/main/ios/scripts/setup-mac.sh)
```

It does four things:

1. Clones the repository to `~/Developer/Scoreline`.
2. Detects your Apple team ID and writes `ios/Config/Local.xcconfig`, which holds your signing team and bundle ID.
   Git ignores that file, so updates never conflict with it.
3. Installs a background job (`~/Library/LaunchAgents/com.scoreline.autopull.plist`) that fast-forwards the clone every 5 minutes.
   Xcode reloads the project automatically when files change, and a notification tells you when there's something new.
4. Opens `ios/Scoreline.xcodeproj` in Xcode.

Then pick your iPhone at the top of Xcode and press **Run** (⌘R).
After an update notification, press **Run** again to install the new version.

* **Signing:** don't change the Team in Xcode's Signing & Capabilities tab, because that edits the shared project file and would block updates.
  Edit `ios/Config/Local.xcconfig` instead.
* **Update now:** `~/Developer/Scoreline/ios/scripts/autopull.sh`
* **Update log:** `~/Library/Logs/Scoreline-autopull.log`
* **Stop automatic updates:** `bash ~/Developer/Scoreline/ios/scripts/setup-mac.sh --uninstall`
* **Local changes:** updates never overwrite them. If you edit a file that a new commit also changes, the update is skipped and the log says so.

First launch on the phone: open **Settings → General → VPN & Device Management** and trust your developer certificate.
Also turn on **Settings → Privacy & Security → Developer Mode**.
With a free Apple ID, the app expires after 7 days; press Run in Xcode again to renew it.

### Unsigned IPA from GitHub Actions

Every push that touches `ios/` is compiled on a GitHub-hosted Mac (`.github/workflows/ios.yml`).
The run's **Artifacts** section contains `Scoreline-unsigned-ipa`.
Sideloading tools such as Sideloadly or AltStore can sign it with your Apple ID and install it.

## Data sources

* **ESPN public JSON API** (`site.api.espn.com`): scores, summaries, standings, leaders and tennis. It's unofficial and can change without notice.
  Parsing lives in `Services/ESPN.swift`.
* **easycredit-bbl.de:** easyCredit BBL games, standings, teams and players, read from the JSON embedded in its public pages.
* **Wikipedia** (`en.wikipedia.org/api/rest_v1/page/html/…`): Grand Tour results, NBA Cup groups, Davis Cup and Laver Cup results, football player photos (ESPN has none), rider and player summaries and competition logos, all licensed CC BY-SA.
  Logos are loaded at runtime and are never stored in the repository.
  The app reads the edition article (for example "2026 Tour de France") and its stage articles ("…, Stage 1 to Stage 11").
  Parsing lives in `Services/WikiHTML.swift` and `Services/Cycling.swift`.

### Caching

`Support/HTTP.swift` caches every response in memory and on disk:

* Live scoreboards are cached for 15 s, and the app polls every 20 s while a game is live.
* Standings are cached for 5 min, stat leaders for 30 min, and a running Grand Tour for 10 min.
* **Finished Grand Tours are stored permanently in Application Support and never downloaded again.**
* If the network is unavailable, the last cached copy is shown.

## Project layout

```
.github/workflows/ios.yml   builds an unsigned IPA on every push
ios/
  Scoreline.xcodeproj
  Config/                   Base.xcconfig (shared), Local.xcconfig (yours, git-ignored)
  scripts/                  setup-mac.sh (one-time setup), autopull.sh (background updates)
  Scoreline/
    ScorelineApp.swift
    Support/   JSON, HTTP cache, Theme (colours, shared views), Store (favourites, league order)
    Services/  Leagues, ESPN, ESPNTeams, BBL, WikiHTML, Cycling, LogoAssets
    Views/     RootView (league menu, search, settings), ScoresView (home, league page), GameCard,
               GameDetailView, StandingsView, LeadersView, DetailPages (team, player, favourites),
               TennisView, CyclingView, StageDetailView, Loader
```

The Xcode project uses a synchronized folder (Xcode 16+): any Swift file added under `ios/Scoreline/` is compiled automatically.
