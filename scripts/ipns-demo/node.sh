#!/bin/sh
# scripts/ipns-demo/node.sh HOST SWARM_PORT API_PORT GATEWAY_PORT [PEER_MULTIADDR...]
#
# A kubo node for the IPNS demo (docs/IPNS-DEMO.md), beside the breadcrumbs hive node of the same host: the hive's swarm.key (so
# only the hive's members connect), its own repo and ports, the peers given as Peering (kept connected), the DHT among those
# peers only, and IPNS over pubsub.  The hive nodes are not touched: they run with Routing none, where a name published on one
# host is never seen by another.
#
#   node.sh init  mac 4012 5012 8092           make the repo (once), print the peer id
#   node.sh peer  mac /ip4/H/tcp/P/p2p/ID ...   set the peers
#   node.sh start mac                           start the daemon (background; log in the repo)
#   node.sh stop  mac
set -e
cmd=$1; host=$2; shift 2
export IPFS_PATH="$HOME/.cache/bc-coop/ipfs-demo-$host"
HIVE_KEY="$HOME/.cache/bc-coop/ipfs-$host/swarm.key"
case $cmd in
init)
  sw=$1; api=$2; gw=$3
  if [ ! -f "$IPFS_PATH/config" ]; then
    ipfs init --profile=lowpower >/dev/null
    cp "$HIVE_KEY" "$IPFS_PATH/swarm.key"
  fi
  ipfs config --json Bootstrap '[]'
  ipfs config --json Addresses.Swarm "[\"/ip4/0.0.0.0/tcp/$sw\"]"
  ipfs config Addresses.API "/ip4/127.0.0.1/tcp/$api"
  ipfs config Addresses.Gateway "/ip4/127.0.0.1/tcp/$gw"
  ipfs config --json Discovery.MDNS.Enabled false
  ipfs config Routing.Type dhtserver
  ipfs config --json Pubsub.Enabled true
  ipfs config --json Ipns.UsePubsub true
  ipfs config --json AutoConf.Enabled false 2>/dev/null || true
  ipfs config --json Swarm.Transports.Network.QUIC false
  ipfs config --json Swarm.Transports.Network.WebTransport false
  ipfs config --json Swarm.Transports.Network.WebRTCDirect false
  ipfs config Identity.PeerID
  ;;
peer)
  json="["; sep=""
  for a in "$@"; do id=${a##*/p2p/}; ad=${a%/p2p/*}; json="$json$sep{\"ID\":\"$id\",\"Addrs\":[\"$ad\"]}"; sep=","; done
  ipfs config --json Peering.Peers "$json]"
  ;;
start)
  LIBP2P_FORCE_PNET=1 nohup ipfs daemon > "$IPFS_PATH/daemon.log" 2>&1 < /dev/null &
  # wait for the API: an online-only call (an offline `ipfs id` would take the repo lock from the starting daemon)
  for i in $(seq 1 30); do sleep 1; ipfs swarm addrs local >/dev/null 2>&1 && break; done
  ipfs swarm addrs local >/dev/null || { tail -5 "$IPFS_PATH/daemon.log"; exit 1; }
  ipfs config Identity.PeerID
  ;;
stop)
  ipfs shutdown
  ;;
esac
