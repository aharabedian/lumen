# Architecture

## Programs

| Program (`src/`) | Does |
|---|---|
| `lumen-discover.lua` | Lists components with every method and doc; `--read` shows what the read-only ones return (`lumen.discover`) |
| `lumen-update.lua` | Installs and updates from GitHub what `manifest.lua` lists. Self-contained: it installs the modules |

Programs but `lumen-update` start with the same three lines as PRISM's and LENS's: add `/home/lib/?.lua` to the
path, forget cached `lumen.*` modules, and say "run lumen-update" if they're missing.

## Modules

| Module | Does |
|---|---|
| `lumen.discover` | Component reports, and reading every read-only method (named get/is/has, documented as taking no arguments) |
| `lumen.version` | The release string; `lumen-update` keeps its own copy (a test checks) |

## What's verified in game

The tests run against `tests/mocks/oc.lua`. This table says which of its behaviors we've confirmed in game.

| API / behavior | Status |
|---|---|
| An LSC (and other GT multiblocks) is component `gt_machine` with: `getEUStored`, `getEUMaxStored`, `getEUCapacity`, `getStoredEU` (the last two **clamped to Long.MaxValue**), `getEUCapacityString`, `getStoredEUString` (exact, as text, for huge amounts), `getEUInputAverage`, `getEUOutputAverage`, `getAverageElectricInput`, `getAverageElectricOutput` (last 5 ticks), `getInputVoltage`, `getOutputVoltage`, `getOutputAmperage`, `getSteamStored`, `getSteamMaxStored`, `getSteamCapacity`, `getStoredSteam`, `getSensorInformation` (table), `getName`, `getOwnerName`, `getCoordinates`, `getWorkProgress`, `getWorkMaxProgress`, `hasWork`, `isMachineActive`, `isWorkAllowed`, `setWorkAllowed(bool)` | **Seen in game** (method list, 2026-11-12). What they return on an LSC: not yet |
| `math.random(m, n)` doesn't return an integer (the mock returns floats) | Seen in game (PRISM and LENS) |
