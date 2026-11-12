# CLAUDE.md

Guidance for Claude Code working in this repo. Keep it short and current; details live in `docs/`.

## What this is

**LUMEN** (Load, Usage & Management of Energy Networks): power monitoring for GregTech: New Horizons on
OpenComputers: LSCs, generators and other GT power. Siblings: PRISM (`../prism`, item routing) and LENS
(`../lens`, base-wide monitoring hub). LUMEN stands alone and may report to LENS over the lens/1 protocol,
the way PRISM does (vendored `lens.metrics` / `lens.codec`).

## Commands

```
make check                        # lint + all tests: run before every commit
lua5.3 tests/run.lua [filter]     # tests (add -v for every check)
luacheck .                        # lint
make screens                      # render the screens the tests draw to PNGs (Python + Pillow)
```

## Rules

- **Focused and isolated.** Change only this repo for LUMEN's needs; never add LUMEN features to PRISM or LENS.
- **Scope:** monitoring, alerts, and simple safe control (generators on/off by LSC fill). **No automated
  reactor control**: OpenComputers can't swap reactor parts atomically (SFM does that better).
- **Test first, against the mock.** Every behavior change gets a check in `tests/`. Never mark work done
  without `make check` passing.
- **Mocks mirror the game.** Probe in game before designing against an API; when the user reports in-game
  behavior that differs, fix the mock first, then the code, and update the verification table in
  `docs/architecture.md`. Don't present unverified API assumptions as fact.
- **Runtime constraints (OpenComputers):** Lua 5.3, OpenOS `unicode` instead of `utf8`; never block without
  yielding; wireless packets are ~8 KB; `math.random(m, n)` isn't an integer in game.
- A new file in `src/` or `lib/` goes in `manifest.lua` (a test checks).
- **`lib/lumen/lens/` is vendored from LENS** (`../lens`): never edit it here; change LENS, then
  `tools/sync-lens.sh` (a test checks they match when `../lens` exists).
- **Only `lumen.control` changes the game**, and only the redstone outputs and GT machines `control` names
  (never an LSC). Everything else only reads. The mock LSC raises if `setWorkAllowed` is called.
- **Docs move with code**, in the same change (table in `CONTRIBUTING.md`). Tables over prose; link, don't repeat.

## Layout

```
src/        programs: lumen.lua (the screen), lumen-setup.lua, lumen-discover.lua, lumen-update.lua
lib/lumen/  modules: pages/ (the screen's pages), setup/ (lumen-setup), lens/ (vendored from LENS)
config/     lumen.example.cfg
manifest.lua  every file the updater installs
docs/       setup, configuration, architecture (with the in-game verification table), images/
tests/      run.lua, helper.lua, mocks/ (oc, net, lsc, gen), test_*.lua
tools/      setup-dev.sh, sync-lens.sh, render_screens.py
```
