# Architecture

## Programs

| Program (`src/`) | Does |
|---|---|
| `lumen.lua` | The power screen. The event loop only: the work is in `lumen.app` |
| `lumen-discover.lua` | Lists components with every method and doc; `--read` shows what the read-only ones return (`lumen.discover`) |
| `lumen-update.lua` | Installs and updates from GitHub what `manifest.lua` lists. Self-contained: it installs the modules |

Programs but `lumen-update` start with the same three lines as PRISM's and LENS's: add `/home/lib/?.lua` to the
path, forget cached `lumen.*` modules, and say "run lumen-update" if they're missing.

## Modules

| Module | Does |
|---|---|
| `lumen.app` | The program's state: reads every `interval`, alerts, beep, history (30 s samples), redraw, LENS |
| `lumen.power` | Finds LSCs (`gt_machine` whose `getName()` is `multimachine.supercapacitor`, checked once per address) and reads them into readings; totals; durations |
| `lumen.alerts` | Alerts from readings (pure), a tracker for when each started and which are new, health |
| `lumen.screen` | Draws a model: header, panels, alerts. Builds a frame of row segments and sends the GPU only changed rows or segments |
| `lumen.config` | `/home/lumen.cfg`: defaults and checks |
| `lumen.telemetry` | Optional reporting to LENS (lens/1) |
| `lumen.gui` | Palette and GPU helpers (the same as PRISM's and LENS's) |
| `lumen.lens.metrics`, `lumen.lens.codec` | **Vendored from LENS**, byte for byte: never edit here. Change LENS, then `tools/sync-lens.sh` (a test compares them with `../lens`) |
| `lumen.discover` | Component reports, and reading every read-only method (named get/is/has, documented as taking no arguments) |
| `lumen.lsc` | Reads an LSC's `getSensorInformation` lines: stored, capacity, fill %, averages (5 s / 5 min / 1 h), time to full/empty, maintenance, capacitor counts |
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
| `math.random(m, n)` doesn't return an integer (the mock returns floats) | Seen in game (PRISM and LENS) |
