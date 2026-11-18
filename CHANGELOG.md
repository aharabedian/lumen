# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Big mode**: after `glanceAfter` seconds (5 minutes) with no tap and nobody near, or **BIG** in the header, a few big
  characters for across the room (`glanceScale` times bigger): how full, time to full or empty, the net, how many
  run, the groups, faults and trips, the worst alert. A tap wakes it; so does a player walking up to a Computronics
  Radar (`wakeRange`, `wakePlayers`; standing there keeps it awake). `lumen-setup`'s GENERAL tab sets it.
- **Reactor tiles**: POWER shows each switch and its source as a tile (TILES or ROWS, kept across restarts): what
  it runs and makes, its heat on a bar that ends at its trip mark, why, RESET and AUTO / ON / OFF. A tile's title
  turns red for a fault, a trip, an error or a reactor still running while switched off. Twelve reactors fit a
  7 x 3 wall at 160 x 33.
- **Heat trips** (`heatTrip`, `heatRise` on a switch): off and latched (across restarts) when its reactor reaches a
  % of its max heat, or climbs too fast; RESET while still hot lets it run to cool down, tripping 5 points higher.
  A bad alert; LENS gets `lumen_switch_trip`.
- **Groups** (`groups`, and `group` on a switch): a ladder of steps runs as many members as the fill needs; the
  least run time starts first (`rotate`), and a member that's faulted, tripped or set by hand is skipped. A line
  per group on the main screen with its members under it ("Not in a group" after); tap it for its page (the
  ladder and who starts next). LENS gets
  `lumen_group_needed` and `lumen_group_running`.
- **Always-on switches** (`always = true`): no marks, ON / OFF on the screen; faults and heat trips still stop it
  (a breeder that should never stop). `lumen-setup`'s **Runs ▸** picks by fill, always, or a group.
- **`lumen-setup`: PAIR** runs each redstone switch alone, after explaining and a START, to find which reactor it
  runs (crossed wiring, blocks that start nothing, and switches with a fault on are said), then puts every output
  back; APPLY sets the sources. **▲ ▼** order the switches (the order on the main screen), a **GROUPS** tab, and
  heat trip fields on each switch.
- **`lumen-setup` on the touchscreen**: tabs for LSCs, sources, switches and general settings (alerts, LENS,
  start on boot); tap a row to change it. For a row of reactors, **COPY** makes the next switch from the one
  selected (the next name and the next free redstone block, the same side, marks and fault input); long
  choices open a list; **READ** shows which sides of a block have a signal coming in, to find it. **SAVE** shows
  the changes and warnings first (two switches on one output, a component not found...). `--text` (or a screen
  under 80x25) asks the questions on the terminal as before.
- **Fault inputs on switches** (`fault`): a redstone line from whatever a switch runs that means trouble, such
  as Steve's Factory Manager's error output on a vacuum reactor. A fault shows FAULT, raises a bad alert, and
  switches off until it clears; `latch` holds it until RESET on the screen (kept across restarts), `invert`
  reads an "OK" signal, `stop = false` only alerts. `lumen-setup` asks; LENS gets `lumen_switch_fault`.
- **`lumen-discover --probe`**: what reactor control needs to know, read only: each IC2 reactor's methods,
  `getSlotInfo(x, y)` for every slot, and each transposer side's inventory and stacks, timed (one by one, and
  `getAllStacks`), how long the reactor's own calls take, and how fast each part that stores heat fills
  (heat/s and time to full, read twice 5 s apart).
- **`lumen-discover --release`**: `setActive(false)` on each IC2 reactor. A computer's `setActive(true)` holds a
  reactor on whatever its redstone says, even after the computer is gone; this hands it back to its redstone.

### Changed
- `lumen-setup`'s switch panel: READ sits with COPY and DELETE and says what it read on the message line.
- **POWER shows a switch and its source as one row**: the switch's state, then what the reactor or generator is
  doing (running, EU/t, heat). Off for 10 s while the source still makes power shows **STILL RUNNING** in red.
  Twelve reactors on switches take twelve rows instead of twenty-four, and POWER may take up to a third of the
  screen (was a quarter), so all twelve fit on a 160x50 screen (and on a 7 x 3 wall at 160x33).
- **`resolution = "fit"` is the default**: the text fills the screen's shape, read from its size in blocks (a wall
  7 wide, 3 tall gets 160 x 33 instead of 160 x 50 with black bars at the sides). `"max"` is the old behaviour;
  `{ width, height }` still works. `lumen-setup`'s screen fits too, keeping at least 80 x 25.

### Fixed
- IC2 reactors showed "can't be read: no answer", and GT generators never showed as running. LUMEN skipped any
  method that wasn't a Lua function, and in game a component's methods never are. The LSC's stored-EU fallback
  had the same fault.

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
