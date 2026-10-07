# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- **Configuration TUI** (`omarchy-power-config`): interactive editor for the
  per-power-source logind behavior (idle action / timeout, lid close on
  normal, external power, and docked) and the shell idle timings
  (screensaver / screen off-lock). No external dependencies; pure stdlib
  `curses`. Applying writes the central config under sudo, regenerates the
  logind drop-in, and updates `~/.config/omarchy/shell.json`.
- **Central config** (`config/power.conf` → `/etc/omarchy-power/power.conf`):
  `switch-power-behavior.sh` now reads AC/battery profiles from this file
  (falling back to the previous hardcoded defaults when absent), overridable
  via the `POWER_CONFIG` environment variable.

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