# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Architecture diagram (`docs/architecture.drawio`), shown in the README.
  A new `Diagram` workflow exports it to `docs/architecture.svg` with
  draw.io desktop and commits the result whenever the source changes.

## [2.0.0] - 2026-10-25

### Changed

- **Idle sleep moved into the Omarchy shell** as the
  `omarchy-power.idle-sleep` service plugin. logind's `IdleAction=` never
  fired on Omarchy because nothing in the session reports an idle hint to
  logind, so "suspend after 30 minutes idle on battery" never happened. The
  plugin tracks Wayland idle itself, picks the AC or battery timeout when it
  fires, and honours Stay Awake, Wayland idle inhibitors and
  `systemd-inhibit --what=idle`.
- **Lid close is a static logind drop-in** (`logind/20-omarchy-power.conf`):
  logind already chooses `HandleLidSwitchExternalPower=` on AC and
  `HandleLidSwitch=` on battery, so nothing needs to switch on plug/unplug.
- **Configuration TUI** (`omarchy-power-config`) now edits the plugin entry in
  `~/.config/omarchy/shell.json` (no sudo) and the lid drop-in (sudo, only
  when a lid setting changed), plus the shell screensaver / lock timings.
- New `install.sh` installs, upgrades from 1.x, and uninstalls
  (`--uninstall`).

### Removed

- The udev rule, boot service and `switch-power-behavior.sh` that rewrote the
  logind drop-in as root on every AC change, and the `power.conf` they read.
  `install.sh` removes an existing 1.x install, including setups whose root
  udev rule / service still ran a user-writable script from
  `~/.config/omarchy/power/`.

## [1.0.2] - 2026-10-07

### Fixed

- Hardened `switch-power-behavior.sh` by removing the unsafe `eval` config loader
  and replacing it with strict validation of the supported AC/battery keys and
  numeric idle timeout values.

## [1.0.1] - 2026-09-03

### Fixed

- Replace hardcoded `/home/user/.config/omarchy/power/switch-power-behavior.sh`
  paths in udev rule and systemd service with the documented install location
  `/usr/local/bin/omarchy-power-behavior`.

## [1.0.0] - 2026-09-03

### Added

- **Power-aware sleep and lid behavior**:
  - On battery: suspend on lid close and after 30 minutes of inactivity.
  - On AC adapter: never sleep, even when the lid is closed.
- **Automatic power-source switching**:
  - Udev rule (`udev/99-power-behavior.rules`) reacts to AC plug/unplug.
  - Systemd oneshot (`systemd/omarchy-power-behavior.service`) applies the
    correct behavior at boot.
- **Driver script** (`switch-power-behavior.sh`) that rewrites the
  `systemd-logind` drop-in and reloads logind for instant effect.
- **Screensaver / screen-off timing** configured for the Omarchy shell:
  - Screensaver after 5 minutes.
  - Screen off / lock after 10 minutes.
- **Repository hygiene**:
  - `.gitignore` guarding sensitive data (keys, certs, `.env`).
  - `README.md` documenting behavior, files, and installation.