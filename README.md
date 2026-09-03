# omarchy-power

Power management configuration for an Omarchy (Hyprland) laptop that
switches behavior automatically between AC adapter and battery power.

## Behavior

| Setting                              | AC                                        | Battery                                   |
| ------------------------------------ | ----------------------------------------- | ----------------------------------------- |
| Sleep / suspend on idle              | Never                                     | After 30 minutes of inactivity            |
| Sleep / suspend on lid close         | Never (stay on)                           | Yes (suspend)                             |
| Screensaver                          | After 5 minutes                           | After 5 minutes                           |
| Screen off / lock                    | After 10 minutes                          | After 10 minutes                          |

The screensaver and screen-off timing are the same on both sources and are
driven by the Omarchy shell (`~/.config/omarchy/shell.json`). The sleep and
lid-close behavior differs per power source and is driven by a `systemd-logind`
drop-in that is rewritten on every AC plug/unplug and at boot.

## Requirements

- Omarchy (Arch Linux + Hyprland)
- `systemd-logind` with `busctl` (UPower) for power-source detection

## Files

| File                                  | Purpose                                                        |
| ------------------------------------- | -------------------------------------------------------------- |
| `switch-power-behavior.sh`            | Waits for a power-source change and rewrites the logind drop-in |
| `udev/99-power-behavior.rules`        | Runs the script when the AC adapter is plugged/unplugged        |
| `systemd/omarchy-power-behavior.service` | Applies the correct behavior at boot                           |
| `config/shell.idle.json`              | Omarchy shell idle values (screensaver / lock timing)          |

## Installation

Run once to install the script, udev rule, service, and activate them:

```bash
sudo install -m 0755 switch-power-behavior.sh /usr/local/bin/omarchy-power-behavior
sudo cp udev/99-power-behavior.rules /etc/udev/rules.d/
sudo cp systemd/omarchy-power-behavior.service /etc/systemd/system/
sudo udevadm control --reload-rules
sudo systemctl enable --now omarchy-power-behavior.service
```

Merge the idle timing into your shell config (`~/.config/omarchy/shell.json`):

```json
{
  "idle": {
    "screensaver": 300,
    "lock": 600
  }
}
```

## How it works

- The **udev rule** runs `switch-power-behavior.sh` every time the AC adapter
  state changes. It reads the current power source via UPower and writes the
  matching `/etc/systemd/logind.conf.d/20-user-power-behavior.conf` drop-in.
- The **systemd service** applies the same logic once at boot, so the correct
  behavior is active before the adapter is ever flipped.
- The script reloads `systemd-logind` (never restarts, which would tear down
  your session) so the new values take effect immediately.

## Notes

- Editing files in `~/.config/` is safe and survives Omarchy updates. This repo
  only tracks the configuration, not Omarchy's packaged defaults.
- Never commit secrets: the `.gitignore` blocks keys, certs, and `.env` files.