# mlnixos-rebuild [switch|boot|test|dry-activate|eval]: bring this system up from its configuration with mlnix as the
# evaluator.  Each step is printed and kept under /var/log/mlnixos-rebuild/<time>/:
#   1  mlnix (the store's runtime) evaluates the configuration to its system derivation
#   2  Nix instantiates the same configuration: the oracle, and the writer of the .drv files into this store
#   3  the two must name the same derivation, or nothing is built
#   4  Nix realises the derivation mlnix named; `switch` and `boot` set the system profile; then switch-to-configuration,
#      and mini-luci restarts to read the configuration again
# `eval` stops after step 3.  Environment: MLNIXOS_RUNTIME, MLNIXOS_NIXPKGS, MLNIXOS_CONFIG.
set -euo pipefail
ST=/mnt/wsl/mlnixos
RT=${MLNIXOS_RUNTIME:-$ST/runtime}
NIXPKGS=${MLNIXOS_NIXPKGS:-$ST/src/nixpkgs}
CONF=${MLNIXOS_CONFIG:-/etc/nixos/configuration.nix}
action=${1:-switch}
[ "$(id -u)" = 0 ] || [ "$action" = eval ] || { echo "mlnixos-rebuild: $action needs root" >&2; exit 1; }
log=${MLNIXOS_LOG:-/var/log/mlnixos-rebuild}/$(date +%Y%m%dT%H%M%S)
mkdir -p "$log"
say() { echo "mlnixos-rebuild: $*" | tee -a "$log/steps"; }
TIMEFORMAT="%R s"
expr="(import $NIXPKGS/nixos { configuration = $CONF; system = \"x86_64-linux\"; }).config.system.build.toplevel.drvPath"

say "runtime $(readlink -f "$RT"): $(tr '\n' ' ' < "$RT/VERSION")"
say "nixpkgs $NIXPKGS at $(cat "$NIXPKGS/.git-revision" 2>/dev/null || echo '?'), configuration $CONF"
say "1/4 mlnix evaluates the configuration"
t=$( { time MLNIX_STATS=1 "$RT/bin/mlnix" instantiate --readonly-mode --eval --strict -E "$expr" > "$log/mlnix.out" 2> "$log/mlnix.err"; } 2>&1 ) \
  || { say "    mlnix failed:"; grep -v '^evaluation warning' "$log/mlnix.err" | tail -20; exit 1; }
drv=$(tr -d '"' < "$log/mlnix.out")
say "    mlnix ($t, $RT/bin/mlnix): $drv"
grep -iE '^(mlnix|stats|thunks|values|files|derivations)' "$log/mlnix.err" | head -8 | sed 's/^/    /' | tee -a "$log/steps" || true

say "2/4 Nix instantiates the same configuration (the oracle)"
t=$( { time nix-instantiate "$NIXPKGS/nixos" -A system --arg configuration "$CONF" --argstr system x86_64-linux \
        > "$log/nix.out" 2> "$log/nix.err"; } 2>&1 ) || { say "    Nix failed:"; tail -20 "$log/nix.err"; exit 1; }
nixdrv=$(tail -1 "$log/nix.out")
say "    Nix ($t): $nixdrv"

say "3/4 compare"
if [ "$drv" != "$nixdrv" ]; then say "    DIFFERENT: nothing is built"; exit 1; fi
say "    the same derivation"
[ "$action" = eval ] && exit 0

say "4/4 Nix realises $drv"
nix-store --realise "$drv" --add-root "$log/result" --indirect > /dev/null 2> "$log/realise.err" || { tail -20 "$log/realise.err"; exit 1; }
out=$(readlink -f "$log/result")
say "    $out"
case $action in switch | boot) nix-env -p /nix/var/nix/profiles/system --set "$out" ;; esac
"$out/bin/switch-to-configuration" "$action" 2>&1 | tee -a "$log/activate"
# mini-luci's corpus is this configuration: read it again
[ "$action" = boot ] || systemctl try-restart mini-luci.service
say "done: $action $out"
