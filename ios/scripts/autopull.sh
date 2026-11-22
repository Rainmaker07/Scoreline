#!/bin/bash
#
# Fast-forwards the Scoreline clone to the latest commit on its branch.
# Run by the background job that setup-mac.sh installs, or by hand.
# Never overwrites local changes: if a fast-forward isn't possible it does nothing.

REPO="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
cd "$REPO" || exit 1

stamp() { date '+%Y-%m-%d %H:%M:%S'; }

git fetch --quiet origin 2>/dev/null || { echo "$(stamp) offline, skipped"; exit 0; }

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || { echo "$(stamp) no upstream branch"; exit 0; }
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "$UPSTREAM")"
[ "$LOCAL" = "$REMOTE" ] && exit 0

if git merge-base --is-ancestor "$LOCAL" "$REMOTE"; then
    if git merge --ff-only --quiet "$UPSTREAM"; then
        COUNT="$(git rev-list --count "$LOCAL..$REMOTE")"
        MSG="$(git log -1 --format=%s)"
        echo "$(stamp) updated: $COUNT new commit(s), latest: $MSG"
        osascript -e "display notification \"$COUNT new commit(s): ${MSG//\"/}\" with title \"Scoreline updated\" subtitle \"Press Run in Xcode to install\"" 2>/dev/null || true
    else
        echo "$(stamp) fast-forward blocked by local edits; leaving files alone"
    fi
else
    echo "$(stamp) local commits differ from $UPSTREAM; not updating automatically"
fi
