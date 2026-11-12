# Configuration

`/home/lumen.cfg` is optional: anything you leave out takes its default. **`lumen-setup`** writes it (and keeps
what it doesn't ask about); [`config/lumen.example.cfg`](../config/lumen.example.cfg) (installed as
`/home/lumen.example.cfg`) shows every setting. It's a Lua file returning a table; `lumen` checks it at start and
names any setting that's wrong.

| Setting | Default | Meaning |
|---|---|---|
| `interval` | `5` | Seconds between readings |
| `names` | `{}` | Names for LSCs, by the start of their address: `{ ["d2440f27"] = "Main" }`. Unnamed ones show as `LSC d244` (the first four characters of the address). `lumen-discover --read` shows the addresses |
| `resolution` | `nil` | `{ width, height }`: fewer, bigger characters, for a wall of screens (`{ 80, 25 }` doubles their size). `nil` means the screen's largest |
| `lowFill` | `25` | Warn when an LSC is below this % full |
| `criticalFill` | `10` | Bad below this % full |
| `drainWarnHours` | `4` | Warn when an LSC is draining and will be empty within this many hours |
| `drainBadHours` | `1` | Bad when it will be empty within this many hours |
| `drainAverage` | `"1h"` | For LSCs without a [switch](#switches): which net the drain alerts use, the LSC's `"5s"`, `"5m"` or `"1h"` average. The 1 hour average rides out short dips; `"5s"` warns soonest but on every dip |
| `inputDrop` | `nil` | Warn when an LSC's input over 5 minutes is this % below its hour's (a generator stopped). Not while a switch is off or switched in the last hour. Leave `nil` if generators cycle by themselves |
| `maxPassiveLoss` | `nil` | Warn when an LSC's passive loss is above this many EU/t |
| `heatWarn`, `heatBad` | `25`, `50` | Warn / bad when an IC2 reactor's heat is at this % of its max |
| `beep` | `true` | Beep once when a bad alert appears (or a warning becomes bad) |
| `lensPort` | `nil` | Report to LENS on this port (LENS's default is `4243`). `nil` means no reporting. Needs a network card |
| `lensNode` | `"lumen"` | This computer's name in LENS. Give each LUMEN computer its own |
| `lensToken` | `nil` | The LENS hub's token, if it has one |
| `sources` | `{}` | Generators to show, [below](#sources) |
| `control` | `{}` | Switches, [below](#switches) |

## Sources

GT generators show under POWER when listed here; IC2 reactors show by themselves (list one to name it).

```lua
sources = {
  { address = "a1b2c3d4", name = "LFTR", alwaysOn = true },
  { address = "eeee0000", name = "Vac nuke" },
},
```

| Key | Meaning |
|---|---|
| `address` | The start of its adapter's component address (`lumen-discover` lists them) |
| `name` | Its name on screen, in alerts and in LENS |
| `alwaysOn` | Warn when it hasn't run for 5 minutes (not while a switch has it off) |

What LUMEN reads: a GT generator's `isMachineActive()`, recipe progress, and from its sensor lines its EU/t and
maintenance problems when they say; a reactor's heat and EU/t. [Architecture](architecture.md#whats-verified-in-game)
says which of these have been seen in game.

## Switches

How switches behave: [setup](setup.md#switches).

```lua
control = {
  { name = "Vac nuke", redstone = "5e1f0000", side = "north", onBelow = 30, offAbove = 90, source = "Vac nuke" },
  { name = "LFTR", machine = "a1b2c3d4", lsc = "Main", onBelow = 50, offAbove = 95 },
},
```

| Key | Default | Meaning |
|---|---|---|
| `name` | | Its name on screen, in alerts and in LENS |
| `redstone` | | The start of a Redstone I/O block's or card's address: switch with a signal. Or: |
| `machine` | | The start of a GT machine's address: switch its work (never an LSC) |
| `side` | | Redstone: `"bottom"`, `"top"`, `"north"`, `"south"`, `"west"`, `"east"` (or 0-5) |
| `invert` | `false` | Redstone: a signal means off |
| `strength` | `15` | Redstone: the signal's strength when on |
| `onBelow`, `offAbove` | | On below this % full, off above this % |
| `lsc` | all LSCs | Follow one LSC, by name |
| `source` | | The source it switches: warns when on and it isn't running, or off and it is |
| `minSwitch` | `60` | Seconds to wait after switching before switching again |

## Alerts

Each alert must last a while before it's raised, so a blip doesn't set one off, and stays a minute after the
problem goes.

| Alert | Level | Raised after |
|---|---|---|
| An LSC can't be read (unloaded chunk, broken adapter) | bad | 15 s |
| Below `criticalFill` % / below `lowFill` % | bad / warn | 30 s |
| Empty within `drainBadHours` / `drainWarnHours` (below) | bad / warn | 5 min |
| An LSC needs maintenance | warn | at once |
| Input down by `inputDrop` % (when set) | warn | 5 min |
| Passive loss above `maxPassiveLoss` (when set) | warn | 1 min |
| A reactor at `heatBad` % / `heatWarn` % of its max heat | bad / warn | at once |
| A source can't be read / needs maintenance | warn | 30 s / 1 min |
| An `alwaysOn` source stopped | warn | 5 min |
| A switch can't be found or switched | bad | 15 s |
| A switch is on but its source isn't running, or off but it is | warn | 5 min |
| No LSC found | warn | at once |

**Empty within:** for an LSC with switches (its own, or ones following all LSCs), nothing while one is off in
AUTO (the generators come on at its mark); once all have been on 10 minutes, the rate since they came on. A
switch set OFF by hand doesn't count. For other LSCs, the `drainAverage` net. The time to empty on the panel is
the LSC's own figure, which follows the last few seconds.

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
| `lumen_drain_seconds` | s | Time until empty, as the drain alerts judge it ([above](#alerts)); nothing while not draining, or on standby |
| `lumen_full_seconds` / `lumen_empty_seconds` | s | Time until full or empty: the LSC's own figure, which follows the last few seconds |
| `lumen_in_24h_eu`, `lumen_out_24h_eu` | EU | In and out over the last 24 hours |

Sources have a `source` label and switches a `switch` label:

| Metric | Unit | Meaning |
|---|---|---|
| `lumen_source_up` | | 1 when the source can be read, else 0 |
| `lumen_source_active` | | 1 while it runs |
| `lumen_source_output_eut` | EU/t | What it makes (when it says) |
| `lumen_reactor_heat_ratio` | 0..1 | A reactor's heat over its max |
| `lumen_switch_on` | | 1 while the switch has its generators on |
| `lumen_switch_auto` | | 1 on AUTO, 0 when set by hand |

LUMEN's alerts go to LENS too, and its health is the worst alert's level.

In `/home/lens-hub.cfg` (LENS 0.3), a panel and HUD lines; [LENS's examples](https://github.com/aharabedian/lens/blob/main/docs/examples.md)
have more:

```lua
panels = {
  { label = "Power", value = "sum(lumen_stored_eu) / sum(lumen_capacity_eu)", format = "percent",
    warnBelow = 0.25, badBelow = 0.1 },
  { label = "Vac nuke", text = "{h} heat", values = { h = 'max(lumen_reactor_heat_ratio{source="Vac nuke"})' },
    format = "percent", status = { { "good", 'sum(lumen_switch_on{switch="Vac nuke"}) > 0' } } },
},
```

A bare metric name adds up every LSC on every LUMEN computer, so these show the whole base.
