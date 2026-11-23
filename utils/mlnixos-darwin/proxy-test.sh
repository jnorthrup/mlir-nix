#!/bin/bash
# Name resolution as a chrooted process has it (no mDNSResponder socket), with and without mlnixos-chroot's proxy:
#   proxy-test.sh HELPER CURL
# Starts `HELPER --proxy` (unprivileged; it exits with this script), then fetches through nouds.sb.
D=$(cd "$(dirname "$0")" && pwd)
H=$1 C=$2
T=$(mktemp -d)
"$H" --proxy > "$T/port" &
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/port" ] && break; sleep 0.2; done
P=$(cat "$T/port")
echo "proxy on 127.0.0.1:$P"
fetch() { # LABEL URL [CURL ARGS]
  local l=$1 u=$2; shift 2
  printf '  %-34s ' "$l"
  timeout 60 sandbox-exec -f "$D/nouds.sb" "$C" -s -o "$T/body" -w '%{http_code} %{size_download} bytes' --max-time 40 "$@" "$u"
  echo " rc=$?"
}
fetch "no proxy, http" http://tarballs.nixos.org/
fetch "proxy, http" http://tarballs.nixos.org/ -x "socks5h://127.0.0.1:$P"
export all_proxy=socks5h://127.0.0.1:$P
fetch "all_proxy, https -k" https://cache.nixos.org/nix-cache-info -k
fetch "all_proxy, https + CA file" https://cache.nixos.org/nix-cache-info --cacert /etc/ssl/cert.pem
fetch "all_proxy, gnu mirror redirect" https://ftpmirror.gnu.org/hello/hello-2.12.1.tar.gz -k -L
echo "  hello-2.12.1.tar.gz sha256 $(shasum -a 256 "$T/body" | cut -c1-64)"
fetch "all_proxy, github archive" https://github.com/apple-oss-distributions/adv_cmds/archive/adv_cmds-231.tar.gz -k -L
unset all_proxy
kill %1 2>/dev/null
rm -rf "$T"
