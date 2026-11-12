# LUMEN

**Load, Usage & Management of Energy Networks.** Power monitoring for **GregTech: New Horizons** on
**OpenComputers**: Lapotronic Supercapacitors, generators and the rest of a base's power, as GTNH
progresses.

A sibling of [PRISM](https://github.com/aharabedian/prism) (item routing) and
[LENS](https://github.com/aharabedian/lens) (base-wide monitoring). Like PRISM, LUMEN runs on its own and
can report to a LENS hub.

> Status: before the first release. **`lumen`** shows every LSC a computer reaches on one screen, with
> alerts, and can report to LENS. Generators come later.

![LUMEN on a tier 3 screen](docs/images/lumen-three.png)

## Scope

| In | Out |
|---|---|
| Reading LSCs and other GT energy storage: stored EU, input, output, time to full or empty | **Automated reactor control.** OpenComputers can't swap reactor components atomically; a mod built for it (Steve's Factory Manager) does it better |
| Simple, safe control: switching generators on and off with the LSC's fill | Anything that needs reactions faster than a computer polling every few seconds |
| Alerts (low power, draining fast), and reporting to LENS | |

## Install

On a computer with an Internet Card:

```
wget -f https://raw.githubusercontent.com/aharabedian/lumen/main/src/lumen-update.lua /home/lumen-update.lua
/home/lumen-update
```

Then run **`lumen`**. What you need, configuration and the screen: [docs/setup.md](docs/setup.md).

| Program | Does |
|---|---|
| `lumen` | The power screen: every LSC's fill, flows, time to full or empty, history, and alerts. Optionally reports to LENS |
| `lumen-discover` | Lists components and their methods; `--read` shows what an LSC (or any GT machine) reports |
| `lumen-update` | Installs and updates LUMEN |

## Docs

| | |
|---|---|
| [Setup](docs/setup.md) | Hardware, install, running, the screen |
| [Configuration](docs/configuration.md) | Every setting, the alerts, LENS metrics and a HUD example |
| [Architecture](docs/architecture.md) | Programs, modules, and what's been verified in game |

## Development

```
make dev      # install luacheck into .luarocks/ (once)
make check    # lint + tests
```

MIT licensed. See [CONTRIBUTING.md](CONTRIBUTING.md).
