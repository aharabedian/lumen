-- manifest.lua - every file lumen-update installs: { path in the repo, path under /home }.
-- tests/test_layout.lua checks that every file in src/ and lib/ is listed, so a new module only needs a line here.
-- Programs go to bin/, modules to lib/ at the same path, config/ files to /home.
return {
  { "src/lumen-discover.lua", "bin/lumen-discover.lua" },
  { "src/lumen-update.lua", "bin/lumen-update.lua" },
  { "lib/lumen/discover.lua", "lib/lumen/discover.lua" },
  { "lib/lumen/lsc.lua", "lib/lumen/lsc.lua" },
  { "lib/lumen/version.lua", "lib/lumen/version.lua" },
}
