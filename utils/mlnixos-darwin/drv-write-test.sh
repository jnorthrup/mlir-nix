#!/bin/bash
# Does `mlnix instantiate` write the .drv?  BIN: an mlnix; WORK: a scratch dir.
#   drv-write-test.sh BIN WORK
B=$1 W=$2; mkdir -p "$W"
E='derivation { name = "t"; system = "aarch64-darwin"; builder = "/bin/sh"; args = [ "-c" "echo hi > $out" ]; }'
p=$(NIX_STORE_DIR=$W/store MLNIX_STATE_DIR=$W/state "$B" instantiate -E "$E")
echo "printed: $p"
ls -la "$W/store" | sed 1d
[ -f "$p" ] && { echo "written:"; cat "$p"; echo; } || echo "NOT written"
p2=$(NIX_STORE_DIR=$W/store MLNIX_STATE_DIR=$W/state "$B" instantiate --add-root "$W/r" -E "$E" 2>&1)
echo "with --add-root: $p2 -> $(readlink "$W/r" 2>/dev/null)"; [ -f "$(readlink "$W/r")" ] && echo "  written" || echo "  NOT written"
