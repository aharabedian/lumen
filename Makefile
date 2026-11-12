LUA ?= lua5.3
# Tools installed by `make dev` (tools/setup-dev.sh) are used when present, else the ones on PATH.
LUACHECK ?= $(if $(wildcard .luarocks/bin/luacheck),.luarocks/bin/luacheck,luacheck)
PYTHON   ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

.PHONY: check test lint screens docs-images dev clean

check: lint test

test:
	$(LUA) tests/run.lua

lint:
	$(LUACHECK) .

# Render every screen the tests draw into build/screens/*.png
screens:
	rm -rf build/screens && mkdir -p build/screens
	SCREENS=build/screens $(LUA) tests/run.lua
	$(PYTHON) tools/render_screens.py build/screens build/screens

# Refresh the images used in the docs
docs-images: screens
	mkdir -p docs/images
	cp build/screens/lumen-one.png docs/images/lumen-one.png
	cp build/screens/lumen-three.png docs/images/lumen-three.png
	cp build/screens/lumen-tier2.png docs/images/lumen-tier2.png
	cp build/screens/lumen-control.png docs/images/lumen-control.png
	cp build/screens/lumen-detail.png docs/images/lumen-detail.png

# Install luacheck (.luarocks/) and a Python venv (.venv/), no sudo needed
dev:
	tools/setup-dev.sh

clean:
	rm -rf build
