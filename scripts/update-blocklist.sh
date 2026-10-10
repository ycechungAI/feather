#!/bin/bash
# Downloads a community blocklist into Feather's blocklist folder.
# Default: StevenBlack unified hosts (ads + malware, ~80k domains). Pass another hosts/domain-list URL to override.
# Then choose Shields > Reload Blocklists in Feather (or restart it).
set -euo pipefail
URL="${1:-https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts}"
DIR="$HOME/Library/Containers/dev.feather.browser/Data/Library/Application Support/Feather"
mkdir -p "$DIR"
# Only fetch over HTTPS (a downgraded or redirected plain-HTTP list could be tampered with).
curl -fsSL --proto '=https' --tlsv1.2 "$URL" -o "$DIR/community.txt.tmp"
mv "$DIR/community.txt.tmp" "$DIR/community.txt"
echo "Saved $(grep -cv '^#' "$DIR/community.txt") lines to $DIR/community.txt"
