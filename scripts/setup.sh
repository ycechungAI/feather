#!/usr/bin/env bash
# FeatherA setup (no sudo, non-admin friendly)
# - Installs/updates Ollama into ~/Applications
# - Restarts and starts Ollama
# - Waits for Ollama API
# - Auto-pulls default models: tev1:0.8b, granite4:3b
#
# Usage: scripts/setup.sh [--install-ollama] [--restart] [--pull-models]
set -euo pipefail

status() { echo ">>> $*"; }
warn() { echo ">>> WARNING: $*" >&2; }

APPDIR="$HOME/Applications"
BINDIR="$HOME/.local/bin"
OLLAMA_APP="$APPDIR/Ollama.app"
OLLAMA_CLI="$BINDIR/ollama"
DEFAULT_MODELS=("tev1:0.8b" "granite4:3b")

mkdir -p "$APPDIR" "$BINDIR"

restart_ollama() {
  status "Restarting Ollama..."
  pkill -x Ollama 2>/dev/null || true
  pkill -f "ollama serve" 2>/dev/null || true
  sleep 2
}

install_ollama() {
  local os arch url tmp
  os="$(uname -s)"
  [ "$os" = "Darwin" ] || { echo "setup.sh currently supports macOS only."; exit 1; }
  arch="$(uname -m)"
  case "$arch" in x86_64) arch="amd64" ;; aarch64|arm64) arch="arm64" ;; *) echo "Unsupported arch: $arch"; exit 1;; esac
  url="https://ollama.com/download/Ollama-darwin.zip${OLLAMA_VERSION:+?version=$OLLAMA_VERSION}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if pgrep -x Ollama >/dev/null 2>&1; then
    status "Stopping running Ollama..."
    pkill -x Ollama 2>/dev/null || true
    sleep 2
  fi
  if [ -d "$OLLAMA_APP" ]; then
    status "Updating Ollama in ~/Applications..."
    rm -rf "$OLLAMA_APP"
  else
    status "Installing Ollama to ~/Applications (no sudo)..."
  fi
  status "Downloading Ollama..."
  curl --fail --show-error --location --progress-bar -o "$tmp/Ollama-darwin.zip" "$url"
  unzip -q "$tmp/Ollama-darwin.zip" -d "$tmp"
  mv "$tmp/Ollama.app" "$OLLAMA_APP"
  ln -sf "$OLLAMA_APP/Contents/Resources/ollama" "$OLLAMA_CLI"
  status "Ollama installed: $OLLAMA_APP"
  status "CLI linked: $OLLAMA_CLI"
}

# Install if missing (or force with --install-ollama)
if [ "${1:-}" = "--install-ollama" ] || [ ! -d "$OLLAMA_APP" ]; then
  install_ollama
else
  status "Ollama already present at $OLLAMA_APP (use --install-ollama to reinstall/update)"
  ln -sf "$OLLAMA_APP/Contents/Resources/ollama" "$OLLAMA_CLI" 2>/dev/null || true
fi

# Restart/start Ollama (also restart if --restart passed)
if [ "${1:-}" = "--restart" ] || [ "${2:-}" = "--restart" ] || [ "${3:-}" = "--restart" ]; then
  restart_ollama
fi
status "Starting Ollama..."
open -a "$OLLAMA_APP" --args hidden >/dev/null 2>&1 || open "$OLLAMA_APP" >/dev/null 2>&1 || true
# Also try serving via CLI if API doesn't come up (helpful on some setups)
sleep 2

# Wait for API
status "Waiting for Ollama API (http://127.0.0.1:11434)..."
ready=0
for i in $(seq 1 45); do
  if curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    ready=1; break
  fi
  # after a few tries, attempt `ollama serve` in background (user-local)
  if [ "$i" -eq 8 ] && [ -x "$OLLAMA_APP/Contents/Resources/ollama" ]; then
    "$OLLAMA_APP/Contents/Resources/ollama" serve >/tmp/feathera-ollama-serve.log 2>&1 &
  fi
  sleep 1
done

if [ "$ready" -ne 1 ]; then
  warn "Ollama API not reachable yet. Open Ollama.app and re-run to auto-pull models:"
  warn "  scripts/setup.sh --pull-models"
  exit 1
fi
status "Ollama is ready."

# Auto-pull default models
pull_models() {
  local bin="$OLLAMA_CLI"
  [ -x "$bin" ] || bin="$OLLAMA_APP/Contents/Resources/ollama"
  for m in "${DEFAULT_MODELS[@]}"; do
    status "Pulling model: $m"
    "$bin" pull "$m"
  done
  status "Default models ready: ${DEFAULT_MODELS[*]}"
}

if [ "${1:-}" = "--pull-models" ] || [ "${2:-}" = "--pull-models" ] || [ "$ready" -eq 1 ]; then
  # auto-pull when ready (default behavior)
  :
fi

# If called only to install and it wasn't ready we exited; if ready, pull.
if [ "$ready" -eq 1 ]; then
  pull_models
fi

status "Setup complete. If 'ollama' isn't on your PATH, add: export PATH=\"$BINDIR:\$PATH\""
