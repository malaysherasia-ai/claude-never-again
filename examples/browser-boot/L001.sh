#!/usr/bin/env bash
# never-again L001 — boot the build in a real browser before committing.
# The boot command and the watched files live in state.json (state.snippet.json).
# Run by hand: bash .claude/hooks/na/L001.sh --run
ID="L001"
RULE="Boot the build in a real browser before committing"
TRIGGER="commit"
source "$(dirname "${BASH_SOURCE[0]}")/na-verify.sh"
