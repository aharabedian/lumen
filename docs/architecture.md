# Architecture

## Programs

| Program (`src/`) | Does |
|---|---|
| `lumen.lua` | The power screen. The event loop only: the work is in `lumen.app` |
| `lumen-setup.lua` | Guided setup: writes `/home/lumen.cfg` and `.shrc` (`lumen.setup.*`) |
| `lumen-discover.lua` | Lists components with every method and doc; `--read` shows what the read-only ones return; `--probe` reads IC2 reactors and transposers for reactor control, `--pause` also pauses a running reactor for 5 s (`lumen.discover`) |
| `lumen-update.lua` | Installs and updates from GitHub what `manifest.lua` lists. Self-contained: it installs the modules |

Programs but `lumen-update` start with the same three lines as PRISM's and LENS's: add `/home/lib/?.lua` to the
path, forget cached `lumen.*` modules, and say "run lumen-update" if they're missing.

## Modules

| Module | Does |
|---|---|
| `lumen.app` | The program's state: every `interval`, reads LSCs and sources, runs the switches, history, alerts, beep, redraw, LENS; saves state every 5 minutes and on exit |
| `lumen.power` | Finds LSCs (`gt_machine` whose `getName()` is `multimachine.supercapacitor`, checked once per address) and reads them into readings; totals; durations |
| `lumen.sources` | GT generators named in `sources`, and IC2 reactors (`reactor`, `reactor_chamber`) found by themselves. Read only |
| `lumen.control` | Switches: decides on or off from the fill (marks, `minSwitch`, holding when unreadable), sets a redstone output or a GT machine's work, reads it back; manual modes. The only module that changes the game, and only what `control` names |
| `lumen.history` | Fill at three ranges (30 s, 3 min and 9 min samples, 160 each) and hourly totals for 48 hours: EU in and out, peak draw, lowest fill, switches' time on; the net over a window |
| `lumen.state` | `/home/lumen-state.cfg`: manual modes and history between runs; a real-time clock from a file's modification time |
| `lumen.alerts` | Alerts from readings, sources and switches (pure), with a hold each; the drain judgement (`alerts.drain`); a tracker that raises after the hold and clears a minute after; health |
| `lumen.screen` | Draws a model: the header, then `lumen.pages.main` (panels, POWER, alerts) or `lumen.pages.detail` (one LSC). Sends the GPU only changed rows or segments |
| `lumen.frame` | A frame of row segments and touch targets, and widgets: buttons, bars, charts |
| `lumen.config` | `/home/lumen.cfg`: defaults and checks |
| `lumen.telemetry` | Optional reporting to LENS (lens/1) |
| `lumen.gui` | Palette (the SPECTRA logo's, LUMEN green as the accent) and GPU helpers (the same as PRISM's and LENS's) |
| `lumen.splash` | The SPECTRA logo in pixel art while `lumen` starts: `show(gpu, w, h, name, version, accent)`; `rows(scale)` is pure |
| `lumen.lens.metrics`, `lumen.lens.codec` | **Vendored from LENS**, byte for byte: never edit here. Change LENS, then `tools/sync-lens.sh` (a test compares them with `../lens`) |
| `lumen.discover` | Component reports; reading every read-only method (named get/is/has, documented as taking no arguments); the reactor probe (reactor slots, transposer sides and stacks, timed) and pause test |
| `lumen.lsc` | Reads an LSC's `getSensorInformation` lines: stored, capacity, fill %, averages (5 s / 5 min / 1 h), time to full/empty, maintenance, capacitor counts |
| `lumen.setup.steps`, `.render`, `.input` | `lumen-setup`'s questions, the commented `lumen.cfg` it writes, and terminal prompts |
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
| A **redstone** component (Redstone I/O block or card) has `getOutput(side)` and `setOutput(side, value)`, sides 0-5 (bottom, top, north, south, west, east), values 0-15 | OpenComputers' documented API; not yet tried with LUMEN |
| `setWorkAllowed(false)` on a GT generator's controller stops it, and `isWorkAllowed()` reads it back | Assumed (the methods are seen on an LSC; LUMEN never calls them on one) |
| A GT generator (an LFTR, turbines) answers `isMachineActive`, `getWorkProgress`, `getWorkMaxProgress`; its sensor lines say its EU/t in a line with "EU/t" and output / generates / produces, and maintenance as "Problems: n" or a `maintenance_status` key | Assumed: LUMEN shows "–" when a line isn't there. Run `lumen-discover --read` on an LFTR to confirm |
| An IC2 reactor is component `reactor` with `getHeat` (integer), `getMaxHeat` (integer, 10000), `getReactorEUOutput` and `getReactorEnergyOutput` (floats), `getOfferedEnergy`, `getSlotInfo`, `producesEnergy`, `setActive` | **Seen in game** (`--read reactor`, 2026-11-14, a reactor that was off) |
| An IC2 reactor's heat and parts don't change while it's off | Seen in game (the user, 2026-11-14) |
| `getSlotInfo(slot)`'s arguments and answer; `setActive(false)` stopping a reactor that a redstone signal runs; a transposer reading the reactor's parts (inventory name, damage) and how long its calls take | Assumed. Run `lumen-discover --probe` and `lumen-discover --probe --pause` |
| `filesystem.lastModified` returns real-world milliseconds, so history survives a restart | Assumed: without it, history starts again on each run |
| `math.random(m, n)` doesn't return an integer (the mock returns floats) | Seen in game (PRISM and LENS) |
| `os.sleep` (OpenOS) waits while yielding; `gpu.set` draws `▀` with the foreground on top (the splash's half-block pixels) | **Unverified** |
