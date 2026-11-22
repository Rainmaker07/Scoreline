# Scoreline for iPhone

A native SwiftUI score tracker styled after Apple Sports.

| League | What you get |
|---|---|
| NBA, MLB | Live scores (Yesterday / Today / Upcoming), line score, game leaders / pitching decisions, team stats, box scores, standings with playoff zones, stat leaders. The NBA page also has the NBA Cup (groups, wild cards, knockout). |
| easyCredit BBL | Live scores, quarter scores, box scores, team stats, standings with playoff, play-in and relegation zones. Data from easycredit-bbl.de, since ESPN doesn't cover the BBL. |
| Premier League, Bundesliga, 2. Bundesliga | Live scores with scorers, match events, lineups on a formation pitch, team stats, live tables with labelled zones, top scorers and assists |
| Champions League, Europa League, Conference League | The same, with league-phase tables (Round of 16 / knockout play-offs / eliminated) |
| DFB-Pokal, FA Cup | Results and fixtures by round, including penalties |
| ATP | The full season: Grand Slams, Masters 1000, 500, 250, ATP Finals (group tables), Next Gen Finals, plus Davis Cup and Laver Cup from Wikipedia. Draws, live scores and ATP rankings. |
| Cycling Grand Tours | Stages, stage results, GC after every stage, jersey holders, final classifications, stage reports, rider pages |

**Everywhere:**
* An Apple Sports-style league switcher with search and live league status.
* Favourite teams, players and riders, with a My Teams section on Home.
* Tap any team or player to open their page: schedule, roster, stats, game log and career.
  Football teams and players can be filtered by competition (league, cup or European).

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
