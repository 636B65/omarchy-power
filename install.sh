#!/bin/bash
# Install (or remove) omarchy-power.
#
#   ./install.sh              install / upgrade, including cleanup of 1.x
#   ./install.sh --uninstall  remove everything this script installs
#
# Run as your normal user. User-side files are written directly; the steps
# that touch /etc and /usr/local/bin go through sudo.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

PLUGIN_ID="omarchy-power.idle-sleep"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
LOGIND_DROPIN="/etc/systemd/logind.conf.d/20-omarchy-power.conf"
TUI_BIN="/usr/local/bin/omarchy-power-config"

# Files from 1.x, which rewrote a logind drop-in from udev on every plug event.
LEGACY_FILES=(
  /etc/udev/rules.d/99-power-behavior.rules
  /etc/systemd/system/omarchy-power-behavior.service
  /usr/local/bin/omarchy-power-behavior
  /etc/systemd/logind.conf.d/20-user-power-behavior.conf
)
LEGACY_DIRS=(/etc/omarchy-power)

step() { printf '\n==> %s\n' "$*"; }

# `omarchy plugin add` clones this repo straight into $PLUGIN_DIR; that
# checkout is the plugin, managed by `omarchy plugin update/remove`.
plugin_is_git_managed() {
  [[ -d $PLUGIN_DIR/.git || $REPO_DIR -ef $PLUGIN_DIR ]]
}

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not root; it uses sudo where needed." >&2
  exit 1
fi

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# Ask for the sudo password once, before changing anything.
if ! sudo -v; then
  echo "sudo is needed for the /etc parts; run this from a terminal where it can ask for your password." >&2
  exit 1
fi

# Rewrites shell.json through a jq filter, keeping the file in place so the
# shell's watcher sees an ordinary change.
edit_shell_json() {
  local tmp
  tmp="$(mktemp)"
  jq "$@" "$SHELL_JSON" > "$tmp"
  cat "$tmp" > "$SHELL_JSON"
  rm -f "$tmp"
}

remove_legacy() {
  local found=0 f
  for f in "${LEGACY_FILES[@]}" "${LEGACY_DIRS[@]}"; do
    [[ -e $f ]] && found=1
  done
  [[ $found == 1 ]] || return 0

  step "Removing omarchy-power 1.x (udev rule, boot service, root script)"
  sudo systemctl disable --now omarchy-power-behavior.service 2>/dev/null || true
  sudo rm -f "${LEGACY_FILES[@]}"
  sudo rm -rf "${LEGACY_DIRS[@]}"
  sudo udevadm control --reload-rules
  sudo systemctl daemon-reload
}

install_all() {
  local plugin_upgraded=0 f
  if plugin_is_git_managed; then
    step "Idle-sleep plugin is managed by 'omarchy plugin' in $PLUGIN_DIR; leaving it as is"
  else
    step "Installing the idle-sleep shell plugin to $PLUGIN_DIR"
    for f in manifest.json Service.qml; do
      if [[ -f $PLUGIN_DIR/$f ]] && ! cmp -s "$REPO_DIR/$f" "$PLUGIN_DIR/$f"; then
        plugin_upgraded=1
      fi
    done
    mkdir -p "$PLUGIN_DIR"
    install -m 0644 "$REPO_DIR/manifest.json" "$REPO_DIR/Service.qml" "$PLUGIN_DIR/"
  fi

  # Without a user shell.json the shell runs on the packaged defaults, and it
  # does not merge them back in once the file exists, so start from a copy.
  if [[ ! -f $SHELL_JSON ]]; then
    mkdir -p "$(dirname "$SHELL_JSON")"
    cp "$OMARCHY_PATH/config/omarchy/shell.json" "$SHELL_JSON"
  fi

  step "Enabling $PLUGIN_ID in $SHELL_JSON"
  # shellcheck disable=SC2016 # $id is a jq variable, not a shell one.
  edit_shell_json --arg id "$PLUGIN_ID" '
    .plugins = (.plugins // [])
    | if any(.plugins[]; .id == $id) then .
      else .plugins += [{
        id: $id,
        acAction: "ignore", acTimeout: 0,
        batteryAction: "suspend", batteryTimeout: 1800
      }] end'

  remove_legacy

  step "Installing the logind lid drop-in and the TUI (sudo)"
  sudo install -m 0644 -D "$REPO_DIR/logind/20-omarchy-power.conf" "$LOGIND_DROPIN"
  sudo install -m 0755 "$REPO_DIR/omarchy-power-config" "$TUI_BIN"
  sudo systemctl reload systemd-logind

  # The shell's plugin hot-reload keeps serving cached QML for a changed
  # file, so an upgraded plugin only takes effect after a shell restart.
  if [[ $plugin_upgraded == 1 ]]; then
    step "Restarting the Omarchy shell to load the updated plugin"
    omarchy restart shell >/dev/null 2>&1 || echo "Run 'omarchy restart shell' to load the new plugin code."
  else
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi

  step "Done"
  echo "Configure with: omarchy-power-config"
}

uninstall_all() {
  if plugin_is_git_managed; then
    step "Leaving the idle-sleep plugin to 'omarchy plugin'; remove it with: omarchy plugin remove $PLUGIN_ID"
  else
    step "Removing the idle-sleep plugin"
    rm -rf "$PLUGIN_DIR"
  fi
  if [[ -f $SHELL_JSON ]] && ! plugin_is_git_managed; then
    # shellcheck disable=SC2016 # $id is a jq variable, not a shell one.
    edit_shell_json --arg id "$PLUGIN_ID" '
      if .plugins then .plugins |= map(select(.id != $id)) else . end'
  fi

  remove_legacy

  step "Removing the logind lid drop-in and the TUI (sudo)"
  sudo rm -f "$LOGIND_DROPIN" "$TUI_BIN"
  sudo systemctl reload systemd-logind

  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  step "Done"
}

case "${1:-}" in
  "") install_all ;;
  --uninstall) uninstall_all ;;
  *)
    echo "Usage: $0 [--uninstall]" >&2
    exit 1
    ;;
esac
