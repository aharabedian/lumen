# Contributing

## Setup

- **Lua 5.3** (`lua5.3`). Debian/Ubuntu: `sudo apt install lua5.3`. macOS: `brew install lua@5.3`.
- A C compiler, `make`, `curl` and Python 3, then **`make dev`** ([tools/setup-dev.sh](tools/setup-dev.sh)) installs
  luacheck into `.luarocks/` and a Python venv into `.venv/`, without sudo. The Makefile falls back to
  `luacheck` on the PATH.
- On Windows, use WSL; the test runner shells out to `ls`, `mkdir` and `rm`.

## Workflow

1. Write or change a test in `tests/` that shows the behavior you want.
2. Change the code.
3. `make check` (lint + tests) must pass. CI runs the same on every push and pull request.
4. Update the docs in the same change (table below).
5. If you tried it in game, say so in the PR and update the verification table in `docs/architecture.md`.

## Code conventions

- **Target OpenComputers' Lua 5.3.** No 5.4-only features. Use OpenOS's `unicode`, not `utf8` (a test checks).
- **Don't block.** Programs keep yielding (`event.pull*`) between steps.
- **Wireless packets are about 8 KB.** Split or trim; never send unbounded data.
- **No state at module load** (OpenOS caches modules); keep state in the objects a module returns.
- 2-space indent, `local` everything, short functions, a comment saying *why* when it isn't obvious.

## Docs move with code

| You changed | Update |
|---|---|
| Behavior, modules, programs, verified game APIs | `docs/architecture.md` |
| Settings | `docs/configuration.md` + `config/lumen.example.cfg` |
| LENS metrics | `docs/configuration.md` (Reporting to LENS) |
| The screen | `docs/setup.md`, and `make docs-images` |
| Anything a player would notice | `CHANGELOG.md` (Unreleased) |

### The docs on SPECTRA

`README.md` and `docs/*.md` are also published on [SPECTRA](https://aharabedian.github.io/spectra/lumen/docs/),
built from the latest release by [aharabedian/spectra](https://github.com/aharabedian/spectra). Write for GitHub
and the site follows, as long as each doc keeps to:

- One `# Title` per file: it becomes the page title and the sidebar label.
- Relative links between docs (`setup.md#updating`). Links to anything else in the repo go to GitHub.
- Images in `docs/images/`.
- Callouts as GitHub alerts (`> [!NOTE]`, `> [!WARNING]`).

A new doc shows up at the end of the site's sidebar; to place it, add it to `order` in SPECTRA's
`spectra.config.mjs`. SPECTRA's landing page for LUMEN quotes program, metric and config names: renaming one
stops the site's next build until the page is updated there.
