# omarchy-power

Power management for an Omarchy (Hyprland) laptop that behaves differently
on AC adapter and battery power.

All per-source behavior is editable through a TUI (`omarchy-power-config`), no
manual config-file editing required.

## Behavior

| Setting                              | AC                                        | Battery                                   |
| ------------------------------------ | ----------------------------------------- | ----------------------------------------- |
| Sleep / suspend on idle              | Never                                     | After 30 minutes of inactivity            |
| Sleep / suspend on lid close         | Never (stay on)                           | Yes (suspend)                             |
| Screensaver                          | After 5 minutes                           | After 5 minutes                           |
| Screen off / lock                    | After 10 minutes                          | After 10 minutes                          |

With the lid closed and an external display connected (docked), the machine
stays on regardless of power source.

## How it works

Nothing reacts to plug/unplug events; both halves already know the power
source at the moment they act.

- **Lid close** is a static `systemd-logind` drop-in
  (`/etc/systemd/logind.conf.d/20-omarchy-power.conf`). logind itself picks
  `HandleLidSwitchExternalPower=` on AC, `HandleLidSwitch=` on battery and
  `HandleLidSwitchDocked=` when docked or with more than one display.
- **Idle sleep** is an Omarchy shell service plugin
  (`omarchy-power.idle-sleep`). It watches Wayland idle the same way the
  built-in screensaver/lock service does and, once the timeout for the
  current power source has passed, runs `systemctl suspend` (or the
  configured action). It honours the Stay Awake toggle, Wayland idle
  inhibitors (video players, presentations, …) and `systemd-inhibit
  --what=idle` blockers. Unplugging while already idle sleeps on schedule.
- **Screensaver and lock** timing is the stock Omarchy shell idle service,
  configured by `idle.screensaver` / `idle.lock` in
  `~/.config/omarchy/shell.json`.

Why not logind's `IdleAction=`? logind only acts on it when the desktop
session reports an idle hint, and the Omarchy shell never does, so
`IdleAction=` silently never fires on Omarchy. (1.x relied on it.)

## Requirements

- Omarchy (Arch Linux + Hyprland, Quickshell-based `omarchy-shell`)
- `jq` for the installer
- `python3` (`curses`) and `sudo` for the configuration TUI

## Files

| File                            | Purpose                                                        |
| ------------------------------- | -------------------------------------------------------------- |
| `install.sh`                    | Installs / upgrades / uninstalls everything below               |
| `plugin/`                       | `omarchy-power.idle-sleep` shell service plugin                 |
| `logind/20-omarchy-power.conf`  | Lid-close behavior per power source                             |
| `omarchy-power-config`          | TUI to edit idle sleep, lid close and shell idle timings        |
| `config/shell.idle.json`        | Reference snippet for the shell screensaver / lock timings      |

## Installation

Run as your normal user (it uses `sudo` for the `/etc` parts):

```bash
./install.sh
```

This:

1. copies `plugin/` to `~/.config/omarchy/plugins/omarchy-power.idle-sleep/`
   and enables it in `~/.config/omarchy/shell.json` with the defaults above
   (an existing entry is left as is);
2. removes a 1.x install if present (udev rule, boot service,
   `/usr/local/bin/omarchy-power-behavior`, the generated logind drop-in and
   `/etc/omarchy-power`);
3. installs the logind lid drop-in and `/usr/local/bin/omarchy-power-config`,
   and reloads `systemd-logind` (reload, never restart, which would end your
   session).

Uninstall with `./install.sh --uninstall`.

## Configure with the TUI

```bash
omarchy-power-config
```

For **AC** and **battery** separately, it edits the action after idle
(`ignore`, `suspend`, `hibernate`, `hybrid-sleep`, `suspend-then-hibernate`,
`poweroff`), the idle timeout, and the lid-close action; plus lid close when
docked and the shell screensaver / lock delays.

Press `a` to apply. Idle settings go to `~/.config/omarchy/shell.json`; the
idle-sleep plugin picks them up live, and when the screensaver / lock delays
changed the TUI runs `omarchy restart shell`, because the built-in idle
service only reads new delays at startup. Lid settings rewrite the logind
drop-in via sudo and reload logind; sudo is only asked for when a lid
setting changed.

## Manual configuration

Idle sleep is the plugin's entry in `~/.config/omarchy/shell.json`. Timeouts
are seconds since idle began; `0` or `"ignore"` disables that source:

```json
{
  "idle": { "screensaver": 300, "lock": 600 },
  "plugins": [
    {
      "id": "omarchy-power.idle-sleep",
      "acAction": "ignore",
      "acTimeout": 0,
      "batteryAction": "suspend",
      "batteryTimeout": 1800
    }
  ]
}
```

Add `"dryRun": true` to get a notification instead of a real suspend, which
is handy with a short timeout for testing. Check what the plugin sees with:

```bash
omarchy-shell idle-sleep status
```

Lid behavior: edit `/etc/systemd/logind.conf.d/20-omarchy-power.conf`, then
`sudo systemctl reload systemd-logind`.

## Notes

- Editing files in `~/.config/` is safe and survives Omarchy updates. This repo
  never touches Omarchy's packaged files under `/usr/share/omarchy`.
- idle-sleep settings in `shell.json` are picked up live; new
  `idle.screensaver` / `idle.lock` values need `omarchy restart shell`. Changes to the plugin
  code need `omarchy restart shell`: the shell's plugin hot-reload keeps
  serving the cached QML for an edited file. `install.sh` restarts the shell
  for you when it upgrades the plugin.
- Never commit secrets: the `.gitignore` blocks keys, certs, and `.env` files.
