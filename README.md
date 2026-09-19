# omarchy-power

Power management configuration for an Omarchy (Hyprland) laptop that
switches behavior automatically between AC adapter and battery power.

All per-source behavior is editable through a TUI (`omarchy-power-config`), no
manual config-file editing required.

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
- `python3` (`curses`) and `sudo` for the configuration TUI

## Files

| File                                  | Purpose                                                        |
| ------------------------------------- | -------------------------------------------------------------- |
| `omarchy-power-config`                | TUI to edit per-source behavior and shell idle timings         |
| `switch-power-behavior.sh`            | Reads the config and rewrites the logind drop-in               |
| `udev/99-power-behavior.rules`        | Runs the script when the AC adapter is plugged/unplugged        |
| `systemd/omarchy-power-behavior.service` | Applies the correct behavior at boot                           |
| `config/power.conf`                   | Central config template (AC / battery logind profiles)         |
| `config/shell.idle.json`              | Reference template for the shell idle (screensaver / lock)     |

## Installation

Run once to install the script, udev rule, service, and activate them:

```bash
sudo install -m 0755 switch-power-behavior.sh /usr/local/bin/omarchy-power-behavior
sudo cp udev/99-power-behavior.rules /etc/udev/rules.d/
sudo cp systemd/omarchy-power-behavior.service /etc/systemd/system/
sudo udevadm control --reload-rules
sudo systemctl enable --now omarchy-power-behavior.service
```

## Configure with the TUI

Install the TUI and run it as a normal user:

```bash
sudo install -m 0755 omarchy-power-config /usr/local/bin/omarchy-power-config
omarchy-power-config
```

The TUI lets you edit, for **AC** and **battery** power separately:

- what happens after idle (`ignore`, `suspend`, `hibernate`, …) and after how
  many minutes
- what happens when the lid closes (including on external power / docked)

and the **shell idle** timings (screensaver delay, screen off / lock delay).

Press `a` to apply: it writes `/etc/omarchy-power/power.conf`, regenerates the
logind drop-in and reloads `systemd-logind` via sudo, and updates
`~/.config/omarchy/shell.json`. Existing settings in your `shell.json` are
preserved.

Manual alternative — edit `~/.config/omarchy/shell.json` (see below) and, if
you need non-default logind behavior:

```bash
sudo mkdir -p /etc/omarchy-power
sudo cp config/power.conf /etc/omarchy-power/power.conf
sudo nano /etc/omarchy-power/power.conf      # adjust values, then re-apply
sudo /usr/local/bin/omarchy-power-behavior
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
  state changes. It reads the profile from
  `/etc/omarchy-power/power.conf` (overridable via `POWER_CONFIG`) for the
  current power source and writes the matching
  `/etc/systemd/logind.conf.d/20-user-power-behavior.conf` drop-in.
- The **systemd service** applies the same logic once at boot, so the correct
  behavior is active before the adapter is ever flipped.
- The script reloads `systemd-logind` (never restarts, which would tear down
  your session) so the new values take effect immediately.
- The **TUI** writes the same central config plus the user's
  `~/.config/omarchy/shell.json`, keeping any other keys in that file intact.

## Notes

- Editing files in `~/.config/` is safe and survives Omarchy updates. This repo
  only tracks the configuration, not Omarchy's packaged defaults.
- Never commit secrets: the `.gitignore` blocks keys, certs, and `.env` files.