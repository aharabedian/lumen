# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **`lumen-discover --probe`**: what reactor control needs to know, read only: each IC2 reactor's methods,
  `getSlotInfo(x, y)` for every slot, and each transposer side's inventory and stacks, timed (one by one, and
  `getAllStacks`), how long the reactor's own calls take, and how fast each part that stores heat fills
  (heat/s and time to full, read twice 5 s apart).
- **`lumen-discover --release`**: `setActive(false)` on each IC2 reactor. A computer's `setActive(true)` holds a
  reactor on whatever its redstone says, even after the computer is gone; this hands it back to its redstone.

## [0.2.0] - 2026-11-13

### Added
- **The SPECTRA logo** in pixel art for a moment while `lumen` starts, with LUMEN's name and version.

### Changed
- **Colors** follow the SPECTRA logo: LUMEN green (`#4FD17A`) as the accent, and the logo's ink, background
  and green, yellow, red and blue for status.

## [0.1.0] - 2026-11-12

The first release: the power screen, generators and reactors, switches, history, and alerts that don't cry wolf.

### Added
- **`lumen`**: the power screen. Every LSC the computer reaches, found by itself: stored and capacity, fill
  bar, EU/t in, out and net, time to full or empty, 5 min and 1 h net, maintenance, and a fill history
  chart. A total panel when there are several LSCs, two columns on wide screens, tier 2 supported, and
  `resolution` for big screens.
- **An LSC's page** (tap it): fill over 80 min, 8 h or 24 h; averages over 5 s, 5 min and 1 h; capacitors,
  wireless, loss; **the last 24 hours** against the 24 before: EU in and out, the highest draw and when, the
  lowest fill, each switch's time on. History survives a restart (`/home/lumen-state.cfg`).
- **Switches** (`control`): generators on below one fill mark and off above another, by a **redstone signal**
  (Redstone I/O block or card, any side, `invert` for a signal that means stop: an SFM line for a vacuum
  reactor) or a **GT machine's work switch** (an LFTR...). Waits between switches, holds while the LSCs can't be
  read, never flips anything on a restart, and **AUTO / ON / OFF** on the screen (kept across restarts).
- **Sources** (`sources`): GT generators (an LFTR, turbines...) and IC2 reactors, under POWER: running or idle,
  EU/t, heat, recipe progress, maintenance problems.
- **Alerts** for low and critical fill, draining toward empty, maintenance, an LSC that can't be read, none
  found; reactor heat (`heatWarn`, `heatBad`); a source that can't be read, needs maintenance or stopped
  (`alwaysOn`); a switch that can't switch, or is on while its source isn't running; optionally input down
  (`inputDrop`) and passive loss (`maxPassiveLoss`). A new bad alert beeps once.
- **No false alarms:** each alert must last a while before it's raised (15 s to 5 min by kind) and stays a
  minute after it clears. Drain alerts know the switches: while a switch has the generators off above its
  mark, draining is standby, not an alert; once they've been on 10 minutes, the alert judges the rate since
  they came on. LSCs without switches use the 1 hour net (`drainAverage`).
- **`lumen-setup`**: names the LSCs, offers generators and reactors, sets up switches, alerts, LENS and start on
  boot, and writes a commented `/home/lumen.cfg` (keeping a `.bak`).
- Optional reporting to LENS (`lensPort`, `lensNode`, `lensToken`): `lumen_*` metrics per LSC (including
  `lumen_drain_seconds`, time to empty as the drain alerts judge it, and the last 24 hours' EU in and out),
  sources (`lumen_source_*`, `lumen_reactor_heat_ratio`), switches (`lumen_switch_on`, `lumen_switch_auto`),
  alerts and health.
- **`lumen-discover`**: components and their methods; `--read` shows what the read-only methods of a component
  type return (default `gt_machine`), calling nothing that could change anything.
- **`lumen-update`**: installs and updates LUMEN from GitHub.
- Docs: setup, configuration, architecture (with what's been verified in game).

### Not yet seen in game
- What an LFTR's (and other GT generators') sensor lines say, and the IC2 reactor's methods: run
  `lumen-discover --read` on them ([architecture](docs/architecture.md#whats-verified-in-game)).
