# Architecture

## Programs

| Program (`src/`) | Does |
|---|---|
| `lumen.lua` | The power screen. The event loop only: the work is in `lumen.app` |
| `lumen-setup.lua` | Setup: the touchscreen editor (80x25 or more), or the text questions (`--text`, or a smaller screen); writes `/home/lumen.cfg` and `.shrc` (`lumen.setup.*`) |
| `lumen-discover.lua` | Lists components with every method and doc; `--read` shows what the read-only ones return; `--probe` reads IC2 reactors and transposers for reactor control; `--release` calls `setActive(false)` on reactors (`lumen.discover`) |
| `lumen-update.lua` | Installs and updates from GitHub what `manifest.lua` lists. Self-contained: it installs the modules |

Programs but `lumen-update` start with the same three lines as PRISM's and LENS's: add `/home/lib/?.lua` to the
path, forget cached `lumen.*` modules, and say "run lumen-update" if they're missing.

## Modules

| Module | Does |
|---|---|
| `lumen.app` | The program's state: every `interval`, reads LSCs and sources, runs the switches, history, alerts, beep, redraw, LENS; saves state every 5 minutes and on exit; big mode (when to go big, waking on a tap or someone arriving) |
| `lumen.presence` | Whether someone is at the screen: a Computronics radar's players within `wakeRange` (`wakePlayers`) |
| `lumen.power` | Finds LSCs (`gt_machine` whose `getName()` is `multimachine.supercapacitor`, checked once per address) and reads them into readings; totals; durations |
| `lumen.sources` | GT generators named in `sources`, and IC2 reactors (`reactor`, `reactor_chamber`) found by themselves. Read only |
| `lumen.supplies` | Supplies counted in an AE2 ME system through an adapter on an ME interface or controller: one lookup each; `lumen-setup`'s search; what's wrong with one (`status`) |
| `lumen.control` | Switches: decides on or off from the fill (marks, `minSwitch`, holding when unreadable), sets a redstone output or a GT machine's work, reads it back; manual modes; fault inputs (read a redstone input, stop, latch, RESET). The only module that changes the game, and only what `control` names; heat trips (a source reactor's heat or how fast it climbs: off and latched until RESET, raised 5 points after a RESET while still hot); groups (a ladder of steps sets how many members run; the least run time starts first; manual, faulted and tripped members are left out); what happened (on and off and why, faults, trips, resets, modes set by hand) for the log |
| `lumen.history` | Fill at three ranges (30 s, 3 min and 9 min samples, 160 each) and hourly totals for 48 hours: EU in and out, peak draw, lowest fill, switches' time on; the net over a window; each source's output (9 min samples) and per hour its EU, time running, starts and the most it made; the LSCs' EU/t in and out per 9 min; each switch's state as changes over 7 days (with "gone" while LUMEN isn't running) |
| `lumen.energy` | The last 24 hours' energy from the history (pure): bands by group and source, "other" (input no source accounts for, over the hours sources were kept), each one's EU, share, uptime, starts and at full; headroom |
| `lumen.log` | What happened, kept 7 days in `/home/lumen-log.cfg`: an event per line, added as it happens; filtered for the timeline |
| `lumen.timeline` | The timeline page's model (pure): each switch's state per column (the worst state in it), how many ran, the fill at its times, the events |
| `lumen.state` | `/home/lumen-state.cfg`: manual modes, latched faults, heat trips, group steps, TILES or ROWS, and history (LSCs, sources and switches over time) between runs; a real-time clock from a file's modification time |
| `lumen.alerts` | Alerts from readings, sources and switches (pure), with a hold each; the drain judgement (`alerts.drain`); a tracker that raises after the hold and clears a minute after; health |
| `lumen.screen` | Draws a model: the header, then `lumen.pages.main` (panels; POWER: group lines, then each switch with its source as tiles or rows; alerts), `lumen.pages.detail` (one LSC) `lumen.pages.group` (a group's ladder and order), `lumen.pages.energy` (the last 24 hours' energy), `lumen.pages.timeline` (what happened), `lumen.pages.supplies` (the supplies' day), or `lumen.pages.glance` (big mode, at its own resolution). Sends the GPU only changed rows or segments |
| `lumen.frame` | A frame of row segments and touch targets, and widgets: buttons, bars, charts; `paint` sends the GPU only what changed (a row with overlapping segments, whole) |
| `lumen.config` | `/home/lumen.cfg`: defaults and checks |
| `lumen.telemetry` | Optional reporting to LENS (lens/1) |
| `lumen.gui` | Palette (the SPECTRA logo's, LUMEN green as the accent), GPU helpers (the same as PRISM's and LENS's), and the resolution to draw at (`"fit"`: the screen's shape) |
| `lumen.splash` | The SPECTRA logo in pixel art while `lumen` starts: `show(gpu, w, h, name, version, accent)`; `rows(scale)` is pure |
| `lumen.lens.metrics`, `lumen.lens.codec` | **Vendored from LENS**, byte for byte: never edit here. Change LENS, then `tools/sync-lens.sh` (a test compares them with `../lens`) |
| `lumen.discover` | Component reports; reading every read-only method (named get/is/has, documented as taking no arguments); the reactor probe (reactor slots, transposer sides and stacks, timed) and release |
| `lumen.lsc` | Reads an LSC's `getSensorInformation` lines: stored, capacity, fill %, averages (5 s / 5 min / 1 h), time to full/empty, maintenance, capacitor counts |
| `lumen.setup.screen` | `lumen-setup`'s touchscreen editor: tabs (switches with ▲ ▼, groups), the pick view, PAIR, review before SAVE. Draws with `lumen.frame` |
| `lumen.setup.editor` | The config as the editor changes it (pure): rows per tab, switches (+ NEW, COPY to the next block and name, DELETE, move), groups and their steps, checks, changes, warnings |
| `lumen.setup.scan` | What's attached, for the editor: LSCs, reactors, GT machines, redstone components; a block's redstone inputs (READ). Read only |
| `lumen.setup.pair` | PAIR: every redstone switch off, then each on alone until a reactor starts (15 s at most), outputs back as they were at the end or on STOP. The only part of setup that switches anything |
| `lumen.setup.files` | Loading the old `lumen.cfg`, `.shrc`'s lumen line, filling defaults and checking before writing, saving with `.bak`: shared by both modes |
| `lumen.setup.steps`, `.render`, `.input` | The text setup's questions, the commented `lumen.cfg` both modes write, and terminal prompts |
| `lumen.version` | The release string; `lumen-update` keeps its own copy (a test checks) |

## What's verified in game

The tests run against `tests/mocks/oc.lua`. This table says which of its behaviors we've confirmed in game.

| API / behavior | Status |
|---|---|
| An LSC (and other GT multiblocks) is component `gt_machine` with: `getEUStored`, `getEUMaxStored`, `getEUCapacity`, `getStoredEU` (the last two **clamped to Long.MaxValue**), `getEUCapacityString`, `getStoredEUString` (exact, as text, for huge amounts), `getEUInputAverage`, `getEUOutputAverage`, `getAverageElectricInput`, `getAverageElectricOutput` (last 5 ticks), `getInputVoltage`, `getOutputVoltage`, `getOutputAmperage`, `getSteamStored`, `getSteamMaxStored`, `getSteamCapacity`, `getStoredSteam`, `getSensorInformation` (table), `getName`, `getOwnerName`, `getCoordinates`, `getWorkProgress`, `getWorkMaxProgress`, `hasWork`, `isMachineActive`, `isWorkAllowed`, `setWorkAllowed(bool)` | **Seen in game** (method list, 2026-11-12) |
| On an 11.34 G EU LSC every EU method returns an **integer** (`getEUStored` 10773223656, `getEUMaxStored` 11340000000); the clamp at Long.MaxValue isn't reached | Seen in game (`--read`, 2026-11-12) |
| `getEUInputAverage` / `getAverageElectricInput` (122880) and the output ones (33280) **don't match** the LSC's own averages (65,536 / 64,716 EU/t over 5 s); LUMEN uses `getSensorInformation` | Seen in game (2026-11-12) |
| `getName()` of an LSC is `"multimachine.supercapacitor"` | Seen in game (2026-11-12) |
| `getSensorInformation` lines are `kekztech.infodata.…` keys, then values, split by `\\`, with `§` codes and thousands commas: `eu_stored`, `used_capacity` (`95.00%`), `total_capacity` (each also as `1.08x10^10`), `passive_loss`, `eu_in`, `eu_out`, `avg_eu_in/out.sec` (value, then seconds: 5), `.min5`, `.hour1`, `time_to.full` (`10.42 hours`), `multi.maintenance_status.ok`, `wireless_mode.disabled`, `capacitors` (tier, count) ×4, `wireless_eu` ×2. `tests/test_lsc.lua` holds them verbatim | Seen in game (2026-11-12) |
| `time_to.empty`, other time units, and the maintenance key when something needs fixing | Assumed (not seen yet) |
| `getSensorInformation` raises (or returns nothing) when the LSC's chunk is unloaded or the multiblock is broken | Assumed: LUMEN shows "can't be read" either way |
| A **redstone** component (Redstone I/O block or card) has `getOutput(side)` and `setOutput(side, value)`, sides 0-5 (bottom, top, north, south, west, east), values 0-15 | Seen in game (the user's vac nuke switch, 0.1.0) |
| `getInput(side)` returns the signal coming in on that side, 0-15 (fault inputs) | OpenComputers' documented API; not yet tried with LUMEN |
| `setWorkAllowed(false)` on a GT generator's controller stops it, and `isWorkAllowed()` reads it back | Assumed (the methods are seen on an LSC; LUMEN never calls them on one) |
| A GT generator (an LFTR, turbines) answers `isMachineActive`, `getWorkProgress`, `getWorkMaxProgress`; its sensor lines say its EU/t in a line with "EU/t" and output / generates / produces, and maintenance as "Problems: n" or a `maintenance_status` key | Assumed: LUMEN shows "–" when a line isn't there. Run `lumen-discover --read` on an LFTR to confirm |
| An IC2 reactor is component `reactor` with `getHeat` (integer), `getMaxHeat` (integer, 10000), `getReactorEUOutput` and `getReactorEnergyOutput` (floats; 1200 running), `getOfferedEnergy` (float), `getSlotInfo(x:int, y:int)`, `producesEnergy`, `setActive(active): boolean` | **Seen in game** (`--probe`, 2026-11-14) |
| A proxy's methods are **callable tables**, not functions: `type(proxy.getHeat)` is `"table"`, so code checks `proxy.x ~= nil`, never `type(...) == "function"` (the mock hands out the same) | **Seen in game** (2026-11-15: every reactor read "no answer") |
| An IC2 reactor's heat and parts don't change while it's off | Seen in game (the user, 2026-11-14) |
| `setActive` is a second "on" input beside redstone: the reactor runs if **either** is on. `setActive(false)` can't stop a reactor its redstone runs; `setActive(true)` holds one on whatever its redstone says | Seen in game (with the redstone on, then off, 2026-11-14) |
| The `setActive(true)` flag is **kept in the reactor**: it stayed on with the computer off, the adapter broken, and a lever switched on and off. Only `setActive(false)` clears it. LUMEN never sets it | Seen in game (the user, 2026-11-14) |
| `screen.getAspectRatio()` gives a multiblock screen's size in blocks; text is drawn as large as fits keeping the resolution's shape; characters are twice as tall as wide; about 1/8 block of border at each edge (`resolution = "fit"`: 160 × 33 on 7 × 3) | Seen in game on a 3 × 4 screen with the same formula (2026-11-12); the 1/8-block border is an estimate |
| A Computronics **Radar** block is component `radar`: `getPlayers([distance])` -> `{ { name, distance }... }` (x, y, z only if its config allows), within `distance` (8 at most, a sphere, no line of sight needed); each call pauses the computer 0.5 s and costs 5 energy a block | **Seen in game** (2026-11-18): walking up wakes big mode. The pause and the fields are from GTNH 2.9.0's source (Computronics 1.9.13) |
| An adapter on an AE2 **ME interface** is component `me_interface` (on a controller, `me_controller`): `getItemInNetwork(name, damage)` -> the stored item (`name`, `label`, `damage`, `size` as a long...) or nil when there's none, without listing the network; `getFluidInNetwork(name)` -> `{ name, label, amount }` or nil; `getItemsInNetwork(filter)` matches every field given exactly on the server; `getFluidsInNetwork()` lists the fluids | From GTNH 2.9.0's source (OpenComputers 1.12.68-GTNH, `integration/appeng/NetworkControl`); not yet seen in game |
| A **Redstone I/O block keeps its output** when its computer shuts down, and when the cable to it is broken | Seen in game (2026-11-14): never run a reactor through one |
| A **redstone card** in the computer's case drops its output to 0 when the computer shuts down (cleanly) | Seen in game (2026-11-14) |
| A redstone card's output drops to 0 when the computer loses power | Seen in game (2026-11-14) |
| `getSlotInfo(x, y)` (x column, y row, from 0) -> `{ item, heat, maxHeat, canStoreHeat }`: a 360k He coolant cell's exact heat (40056 of 360000) where the transposer's `damage` says 11 of 100 | Seen in game (`--probe`, 2026-11-14) |
| A transposer's `getAllStacks(side)` returns a table of every slot (empty ones too) in 2 ticks (0.10 s for 18 or 54 slots) | Seen in game (`--probe`, 2026-11-14) |
| A transposer sees the reactor as `"blockGenerator"`, 18 slots with no chambers; stacks have `name` (`IC2:reactorVentGold`, `IC2:reactorHeatSwitchDiamond`, `gregtech:gt.rodUranium4`), `label`, `damage` (a vent's or exchanger's heat, of `maxDamage` 10000; a quad uranium rod's of 100), `size`, `hasTag`, `tag` | Seen in game (`--probe`, 2026-11-14) |
| The reactor's own calls take a tick each too: 10 `getHeat` in 0.50 s, 70 `getSlotInfo` in 3.50 s. An adapter on a chamber is component `reactor_chamber`, the same methods; with 6 chambers `getSlotInfo` answers 9 × 6 slots | Seen in game (`--probe`, 2026-11-15) |
| A running breeder held its hull at 61496 of 72000 (85%) while its 360k cells gained 45–89 heat/s (full in 50 min to 2 h) | Seen in game (`--probe`, 2026-11-15); design dependent |
| A transposer's `getStackInSlot` takes a tick (18 calls in 0.90 s, 54 in 2.70 s), so a remove then insert is never atomic | Seen in game (`--probe`, 2026-11-14) |
| The transposer's slots go row by row: slot = y × width + x + 1, width 3 with no chambers (slot 4 is (0, 1), a coolant cell in both) | Seen for a reactor with no chambers (2026-11-14); assumed width 3 + chambers |
| `filesystem.lastModified` returns real-world milliseconds, so history survives a restart | **Seen in game** (2026-11-18): the LSC page's last 24 hours are still there after a restart |
| A `touch` event carries the player's name (`touch: screen, x, y, button, player`) | **Seen in game** (2026-11-18, by LENS's per-player HUDs) |
| `math.random(m, n)` doesn't return an integer (the mock returns floats) | Seen in game (PRISM and LENS) |
| `os.sleep` (OpenOS) waits while yielding; `gpu.set` draws `▀` with the foreground on top (the splash's half-block pixels) | **Unverified** |
