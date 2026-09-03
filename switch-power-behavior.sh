#!/bin/bash
# Toggle system sleep/lid behavior based on AC vs battery power.
# Requires root (writes to /etc/systemd/logind.conf.d/).
#
# AC:      never sleep (lid close ignored, idle ignored)
# Battery: sleep on lid close, sleep after 30 min idle
#
# Screensaver (5 min) and screen off / lock (10 min) are handled by the
# shell via ~/.config/omarchy/shell.json and are the same on both sources.

set -e

LOGIND_DIR="/etc/systemd/logind.conf.d"
CONF="$LOGIND_DIR/20-user-power-behavior.conf"

power_source="${1:-}"
if [[ -z $power_source ]]; then
  if [[ $(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null) == *"true"* ]]; then
    power_source="battery"
  else
    power_source="ac"
  fi
fi

case "$power_source" in
  ac)
    cat > "$CONF" <<'EOF'
# AC power: never sleep, never suspend on lid close.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
IdleAction=ignore
EOF
    ;;
  battery)
    cat > "$CONF" <<'EOF'
# Battery: sleep on lid close, sleep after 30 min idle.
[Login]
HandleLidSwitch=suspend
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=suspend
IdleAction=suspend
IdleActionSec=30min
EOF
    ;;
  *)
    echo "Usage: $0 [ac|battery]" >&2
    exit 1
    ;;
esac

# Reload, not restart: restarting logind tears down the session.
systemctl reload systemd-logind

echo "Power behavior set to: $power_source"
