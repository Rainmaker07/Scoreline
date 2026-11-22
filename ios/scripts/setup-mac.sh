#!/bin/bash
#
# One-time setup for building Scoreline on your Mac with Xcode.
#
#   1. Clones the repository (or reuses an existing clone)
#   2. Writes your personal signing settings to ios/Config/Local.xcconfig (git-ignored)
#   3. Installs a background job that pulls new code every few minutes,
#      so the project open in Xcode is always the latest version
#   4. Opens the project in Xcode
#
# Run it with:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Rainmaker07/Scoreline/main/ios/scripts/setup-mac.sh)
#
# Options:
#   --dir PATH        where to clone (default: ~/Developer/Scoreline)
#   --branch NAME     branch to follow (default: main)
#   --interval SECS   how often to check for updates (default: 300)
#   --team TEAMID     Apple team ID (skips auto-detection)
#   --uninstall       remove the background update job (keeps the clone)

set -euo pipefail

REPO_URL="https://github.com/Rainmaker07/Scoreline.git"
BRANCH="main"
DEST="$HOME/Developer/Scoreline"
INTERVAL=300
TEAM=""
LABEL="com.scoreline.autopull"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/Scoreline-autopull.log"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

uninstall() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    bold "Background updates removed. Your clone was left in place."
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dir) DEST="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --team) TEAM="$2"; shift 2 ;;
        --uninstall) uninstall ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
done

[ "$(uname)" = "Darwin" ] || fail "This script is for macOS."
command -v git >/dev/null || fail "git not found. Install Xcode, then run: xcode-select --install"
xcode-select -p >/dev/null 2>&1 || fail "Xcode not found. Install it from the App Store first."

# ---------------------------------------------------------------- 1. clone
bold "1/4  Getting the code"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../Scoreline.xcodeproj/project.pbxproj" ]; then
    REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
    info "Using the existing clone at $REPO"
elif [ -d "$DEST/.git" ]; then
    REPO="$DEST"
    info "Using the existing clone at $REPO"
    # Clones made before the app moved to its own repository still point at
    # the old one: switch them over (untracked files like Local.xcconfig stay).
    if [ "$(git -C "$REPO" remote get-url origin)" != "$REPO_URL" ]; then
        info "Switching $REPO to $REPO_URL"
        git -C "$REPO" remote set-url origin "$REPO_URL"
        git -C "$REPO" fetch origin "$BRANCH"
        git -C "$REPO" checkout -B "$BRANCH" "origin/$BRANCH" \
            || fail "Couldn't switch branches (local changes?). Commit or discard them, then re-run."
        git -C "$REPO" branch --set-upstream-to "origin/$BRANCH" "$BRANCH"
    fi
else
    mkdir -p "$(dirname "$DEST")"
    git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
    REPO="$DEST"
fi

cd "$REPO"
if [ "$(git rev-parse --abbrev-ref HEAD)" != "$BRANCH" ]; then
    git fetch origin "$BRANCH"
    git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" --track "origin/$BRANCH"
fi
git pull --ff-only || info "Couldn't fast-forward (local changes?). Continuing with what's there."

case "$REPO" in
    "$HOME/Desktop"*|"$HOME/Documents"*|"$HOME/Downloads"*)
        info "Note: macOS may block background access to $REPO."
        info "If updates stop arriving, move the clone to ~/Developer and re-run this script." ;;
esac

# ---------------------------------------------------------------- 2. signing
bold "2/4  Signing settings"
LOCAL="$REPO/ios/Config/Local.xcconfig"
if [ -f "$LOCAL" ] && [ -z "$TEAM" ]; then
    info "Keeping existing $LOCAL"
else
    if [ -z "$TEAM" ]; then
        # The Team ID is the OU field of your Apple Development certificate.
        TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
            | openssl x509 -noout -subject 2>/dev/null \
            | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)"
        if [ -n "$TEAM" ]; then
            info "Found your Apple team ID: $TEAM"
            read -r -p "  Press Enter to use it, or type a different Team ID: " OTHER </dev/tty || true
            [ -n "${OTHER:-}" ] && TEAM="$OTHER"
        else
            info "No Apple Development certificate found."
            info "In Xcode: Settings > Accounts > add your Apple ID > Manage Certificates > + > Apple Development."
            read -r -p "  Enter your Team ID now, or press Enter to set it later: " TEAM </dev/tty || true
        fi
    fi
    USER_SLUG="$(id -un | tr -cd 'a-zA-Z0-9' | tr 'A-Z' 'a-z')"
    BUNDLE="com.${USER_SLUG:-me}.scoreline"
    cat > "$LOCAL" <<EOF
// Personal signing settings. Git-ignored: updates never overwrite this file.
DEVELOPMENT_TEAM = ${TEAM}
PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE}
EOF
    info "Wrote $LOCAL (bundle ID $BUNDLE)"
fi

# ---------------------------------------------------------------- 3. auto-update
bold "3/4  Automatic updates"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
chmod +x "$REPO/ios/scripts/autopull.sh"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$REPO/ios/scripts/autopull.sh</string>
        <string>$REPO</string>
    </array>
    <key>StartInterval</key><integer>$INTERVAL</integer>
    <key>RunAtLoad</key><true/>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
info "Checking for updates every $((INTERVAL / 60)) min. Log: $LOG"

# ---------------------------------------------------------------- 4. open
bold "4/4  Opening Xcode"
open "$REPO/ios/Scoreline.xcodeproj"

echo
bold "Done."
info "In Xcode: pick your iPhone at the top, then press Run (Cmd-R)."
info "Don't change the Team in Signing & Capabilities. Edit $LOCAL instead,"
info "so Xcode never modifies a tracked file and updates keep applying cleanly."
info "Update now:     $REPO/ios/scripts/autopull.sh"
info "Stop updates:   bash $REPO/ios/scripts/setup-mac.sh --uninstall"
