# LUMEN

**Load, Usage & Management of Energy Networks.** Power monitoring for **GregTech: New Horizons** on
**OpenComputers**: Lapotronic Supercapacitors, generators and the rest of a base's power, as GTNH
progresses.

A sibling of [PRISM](https://github.com/aharabedian/prism) (item routing) and
[LENS](https://github.com/aharabedian/lens) (base-wide monitoring). Like PRISM, LUMEN runs on its own and
can report to a LENS hub.

> Status: starting. The first step is reading what the game's power blocks actually report.

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

`lumen-discover --read` (with an adapter on an LSC) shows what it reports.

## Development

```
make dev      # install luacheck into .luarocks/ (once)
make check    # lint + tests
```

MIT licensed. See [CONTRIBUTING.md](CONTRIBUTING.md).
