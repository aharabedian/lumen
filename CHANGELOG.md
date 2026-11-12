# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **`lumen`**: the power screen. Every LSC the computer reaches, found by itself: stored and capacity, fill
  bar, EU/t in, out and net, time to full or empty, 5 min and 1 h net, maintenance, and a fill history
  chart. A total panel when there are several LSCs, two columns on wide screens, tier 2 supported, and
  `resolution` for big screens.
- Alerts: low and critical fill, draining toward empty, maintenance, an LSC that can't be read, none found.
  A new bad alert beeps once. Drain alerts use the LSC's 1 hour net by default (`drainAverage`), so
  generators that cycle, like a vacuum reactor, don't raise them on every off cycle.
- Optional reporting to LENS (`lensPort`, `lensNode`, `lensToken`): `lumen_*` metrics per LSC (including
  `lumen_drain_seconds`, time to empty at the drain alerts' average), alerts and health.
- `/home/lumen.cfg` (optional) and `config/lumen.example.cfg`; docs: setup, configuration.
- Repository scaffold: test runner, lint, CI.
- **`lumen-discover`**: components and their methods; `--read` shows what the read-only methods of a component
  type return (default `gt_machine`), calling nothing that could change anything.
- **`lumen-update`**: installs and updates LUMEN from GitHub.
- `lumen.lsc`: reads an LSC's own figures (`getSensorInformation`), the ones its screen shows.
