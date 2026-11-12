-- manifest.lua - every file lumen-update installs: { path in the repo, path under /home }.
-- tests/test_layout.lua checks that every file in src/ and lib/ is listed, so a new module only needs a line here.
-- Programs go to bin/, modules to lib/ at the same path, config/ files to /home.
return {
  { "src/lumen.lua", "bin/lumen.lua" },
  { "src/lumen-discover.lua", "bin/lumen-discover.lua" },
  { "src/lumen-update.lua", "bin/lumen-update.lua" },
  { "lib/lumen/alerts.lua", "lib/lumen/alerts.lua" },
  { "lib/lumen/app.lua", "lib/lumen/app.lua" },
  { "lib/lumen/config.lua", "lib/lumen/config.lua" },
  { "lib/lumen/discover.lua", "lib/lumen/discover.lua" },
  { "lib/lumen/gui.lua", "lib/lumen/gui.lua" },
  { "lib/lumen/lsc.lua", "lib/lumen/lsc.lua" },
  { "lib/lumen/power.lua", "lib/lumen/power.lua" },
  { "lib/lumen/screen.lua", "lib/lumen/screen.lua" },
  { "lib/lumen/telemetry.lua", "lib/lumen/telemetry.lua" },
  { "lib/lumen/version.lua", "lib/lumen/version.lua" },
  { "lib/lumen/lens/codec.lua", "lib/lumen/lens/codec.lua" },
  { "lib/lumen/lens/metrics.lua", "lib/lumen/lens/metrics.lua" },
  { "config/lumen.example.cfg", "lumen.example.cfg" },
}
