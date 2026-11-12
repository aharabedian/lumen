# Configuration

`/home/lumen.cfg` is optional: anything you leave out takes its default. Start from
[`config/lumen.example.cfg`](../config/lumen.example.cfg) (installed as `/home/lumen.example.cfg`). It's a
Lua file returning a table; `lumen` checks it at start and names any setting that's wrong.

| Setting | Default | Meaning |
|---|---|---|
| `interval` | `5` | Seconds between readings |
| `names` | `{}` | Names for LSCs, by the start of their address: `{ ["d2440f27"] = "Main" }`. Unnamed ones show as `LSC d244` (the first four characters of the address). `lumen-discover --read` shows the addresses |
| `resolution` | `nil` | `{ width, height }`: fewer, bigger characters, for a wall of screens (`{ 80, 25 }` doubles their size). `nil` means the screen's largest |
| `lowFill` | `25` | Warn when an LSC is below this % full |
| `criticalFill` | `10` | Bad below this % full |
| `drainWarnHours` | `4` | Warn when an LSC is draining and will be empty within this many hours |
| `drainBadHours` | `1` | Bad when it will be empty within this many hours |
| `drainAverage` | `"1h"` | Which net the drain alerts use: the LSC's `"5s"`, `"5m"` or `"1h"` average. The 1 hour average rides out generators that cycle (a vacuum reactor's off cycle); `"5s"` warns soonest but on every dip |
| `beep` | `true` | Beep once when a bad alert appears (or a warning becomes bad) |
| `lensPort` | `nil` | Report to LENS on this port (LENS's default is `4243`). `nil` means no reporting. Needs a network card |
| `lensNode` | `"lumen"` | This computer's name in LENS. Give each LUMEN computer its own |
| `lensToken` | `nil` | The LENS hub's token, if it has one |

## Alerts

| Alert | Level |
|---|---|
| An LSC can't be read (unloaded chunk, broken adapter) | bad |
| Below `criticalFill` % / below `lowFill` % | bad / warn |
| Draining at the `drainAverage` net, and empty within `drainBadHours` / `drainWarnHours` | bad / warn |
| Maintenance needed | warn |
| No LSC found | warn |

The time to empty on screen is the LSC's own figure, which follows the last few seconds. When the LSC
doesn't give one, LUMEN works it out from the 5-minute net. The drain alerts use the `drainAverage` net
instead, so a short dip doesn't raise them; the low-fill alerts still catch a real shortage.

## Reporting to LENS

With `lensPort` set, LUMEN sends LENS a snapshot after every reading, using the lens/1 protocol
([LENS telemetry spec](https://github.com/aharabedian/lens/blob/main/docs/telemetry.md)). Each LSC is one
`lsc` label, its name on screen:

| Metric | Unit | Meaning |
|---|---|---|
| `lumen_lsc_up` | | 1 when the LSC can be read, else 0 (and nothing else is sent for it) |
| `lumen_stored_eu` | EU | Stored |
| `lumen_capacity_eu` | EU | Capacity |
| `lumen_fill_ratio` | 0..1 | Stored / capacity |
| `lumen_input_eut`, `lumen_output_eut`, `lumen_net_eut` | EU/t | In, out, and in minus out: the LSC's 5-second averages |
| `lumen_net_5m_eut`, `lumen_net_1h_eut` | EU/t | In minus out over 5 minutes, and over 1 hour |
| `lumen_drain_seconds` | s | Time until empty at the `drainAverage` net (what the drain alerts use); nothing while that net isn't negative |
| `lumen_full_seconds` / `lumen_empty_seconds` | s | Time until full or empty: the LSC's own figure, which follows the last few seconds |

LUMEN's alerts go to LENS too, and its health is the worst alert's level.

A power bar for the LENS HUD, and a panel, in `/home/lens-hub.cfg`:

```lua
hud = { bars = {
  { label = "Power", value = "lumen_stored_eu / lumen_capacity_eu", percent = true, warnBelow = 0.25, badBelow = 0.1 },
} },
panels = {
  { label = "Power stored", value = "lumen_stored_eu / lumen_capacity_eu", percent = true, warnBelow = 0.25, badBelow = 0.1 },
  { label = "Net EU/t", value = "lumen_net_eut", unit = "EU/t" },
},
```

A bare metric name adds up every LSC on every LUMEN computer, so these show the whole base.
