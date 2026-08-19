#!/usr/bin/env bash
# Renders the README's terminal screenshots (docs/terminal-*.svg) from real
# command output.
#
# SVG rather than PNG because the terminal output *is* the thing being shown:
# it stays text-sharp at any zoom, diffs cleanly in git, and needs no design
# tool to regenerate. `script -q` runs each command under a pty so ANSI colour
# survives the capture; scripts/ansi2svg.mjs turns the capture into the frame.
#
# The commands run for real, against public repos, so the screenshots cannot
# drift from what the tool actually prints — and no private repository names
# end up in the documentation.
set -euo pipefail

cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A prompt line: green sigil, bold command. Output follows unstyled, as a real
# terminal shows it.
prompt() { printf '\033[32m$\033[0m \033[1m%s\033[0m\n' "$1"; }

# Runs a command under a pty and prints what a terminal would leave on screen.
# Progress output (swift build's) redraws one line in place with \r, so keep
# only the text after the last \r and drop the escape sequences — the surviving
# lines are then greppable by callers. Failures are reported rather than
# swallowed: a silently empty capture makes a screenshot that quietly stops
# matching the tool.
capture() {
  local out
  # stdin from /dev/null, or `script` behaves differently depending on what it
  # inherits — sometimes echoing the EOT as a literal "^D" into the capture,
  # sometimes exiting non-zero on a command that succeeded.
  if ! out="$(script -q /dev/null "$@" </dev/null 2>&1)"; then
    echo "capture failed: $*" >&2
    exit 1
  fi
  printf '%s\n' "$out" | sed -e $'s/\r$//' -e $'s/.*\r//' -e $'s/\x1b\\[[0-9;]*[A-Za-z]//g'
}

render() { node scripts/ansi2svg.mjs "$1" "$2" "$3"; }

# ── 1. Build from source ────────────────────────────────────────────────────
# make-app.sh runs for real; the clone and install lines around it are shown as
# typed, since cloning and copying to /Applications on every docs build is pure
# noise.
{
  prompt "brew install gh && gh auth login"
  prompt "git clone https://github.com/manishkumar/ghs.git && cd ghs"
  prompt "./scripts/make-app.sh"
  capture ./scripts/make-app.sh | grep -E "^(Build complete|Built )"
  prompt "cp -R build/ghs.app /Applications/ && open /Applications/ghs.app"
} > "$TMP/install.txt"
render "$TMP/install.txt" docs/terminal-install.svg "Build from source"

# ── 2. Check it works ───────────────────────────────────────────────────────
# Two public repos, so this is a real run anyone can reproduce.
LIST_CMD=(./.build/debug/ghs --list --repos cli/cli,sharkdp/bat)
{
  prompt "${LIST_CMD[*]}"
  capture "${LIST_CMD[@]}" | sed -n 1,12p
} > "$TMP/list.txt"
render "$TMP/list.txt" docs/terminal-list.svg "ghs --list"
