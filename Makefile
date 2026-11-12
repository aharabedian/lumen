LUA ?= lua5.3
# Tools installed by `make dev` (tools/setup-dev.sh) are used when present, else the ones on PATH.
LUACHECK ?= $(if $(wildcard .luarocks/bin/luacheck),.luarocks/bin/luacheck,luacheck)

.PHONY: check test lint dev clean

check: lint test

test:
	$(LUA) tests/run.lua

lint:
	$(LUACHECK) .

# Install luacheck (.luarocks/) and a Python venv (.venv/), no sudo needed
dev:
	tools/setup-dev.sh

clean:
	rm -rf build
