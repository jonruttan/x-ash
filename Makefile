# x-ash -- the ASH lang for x-lang
#
# INSTALL PUTS THIS BUNDLE WHERE `-l` LOOKS, which is the whole of it: an
# installed x searches <share>/langs/*/lang.xon, so a lang is "installed" when
# its files are there.  No registry, no database, no per-project pin.
#
#   make install                  into the x on PATH
#   PREFIX=$HOME/.local make install    into a particular prefix
#
# PIN OR INSTALL, AND THEY ANSWER DIFFERENT QUESTIONS.  A pin (lang.pin.xon +
# Pin bundle) freezes a verified tarball for ONE project and is what a build
# should depend on.  An install puts one copy on the machine for every project
# and for the prompt -- convenient, unversioned, and exactly like installing a
# language runtime.  Use the pin when it matters which version; use this when
# you just want `x -l ash` to work.

X ?= x
# PREFIX wins when given, so this matches x-lang's own `PREFIX=... make
# install`.  Otherwise ask the x on PATH where its tree is -- the question
# --share-dir exists to answer.
SHARE := $(if $(PREFIX),$(PREFIX)/share/x,$(shell $(X) --share-dir))
DEST  := $(SHARE)/langs/ash

# What a consumer needs to RUN the lang: the declaration, the entry, the
# modules.  Not the suite, not the tooling, not CI -- those are this
# repository's business, not the installed platform's.
PAYLOAD := lang.xon run.x ash

.PHONY: install
install: ## Install into <share>/langs/ash
	@test -n "$(SHARE)" || { echo "x-ash: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-ash: no x tree at $(SHARE)" >&2; exit 1; }
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -R $(PAYLOAD) "$(DEST)/"
	@echo "x-ash: installed to $(DEST)"
	@echo "x-ash: try  x -l ash"

.PHONY: uninstall
uninstall: ## Remove it again
	rm -rf "$(DEST)"
	@echo "x-ash: removed $(DEST)"

.PHONY: test
test: ## Run the spec suite
	X="$(X)" sh tests/spec-runner.sh

.PHONY: bundle
bundle: ## Roll a release tarball and print its pin
	sh tools/bundle.sh

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[32m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
