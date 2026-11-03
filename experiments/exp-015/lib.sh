# Shared by exp-015's scripts. Sourced, not run.
#
# Every client runs test-side, in a node's network namespace (`--network container:vx-<node>-infra`),
# so only container nodes can host one. Test containers are named vxt-*, which check-leaks.sh
# counts, so one left behind fails the run.

BROKER=${BROKER:-10.100.0.50:55555}
KV2=${KV2:-localhost/vxperiments/kv2:1}
CAN=ghcr.io/eclipse-kuksa/kuksa-can-provider/can-provider@sha256:41f5abffe30be4dd0bf6d82f28ca149d327e2d6de8619b562a12035a30da0c8e
DATABROKER=vx-hpc1-kuksa-databroker

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }
obs() { echo "OBS   $1"; }
h() { echo; echo "== $*"; }

# kv <node> <kv2 args...>: one client call, its JSON lines on stdout.
kv() {
    local node=$1
    shift
    timeout 60 podman run --rm --init --network "container:vx-$node-infra" "$KV2" --server "$BROKER" "$@" 2>&1
}

# kvbg <name> <node> <kv2 args...>: a client left running as vxt-<name>.
kvbg() {
    local name=$1 node=$2
    shift 2
    podman rm -f -t 0 "vxt-$name" >/dev/null 2>&1
    podman run -d --init --name "vxt-$name" --network "container:vx-$node-infra" "$KV2" \
        --server "$BROKER" "$@" >/dev/null
}

# until_log <name> <op> <result> [tries]: wait for a background client's line.
until_log() {
    local i
    for i in $(seq "${4:-50}"); do
        podman logs "vxt-$1" 2>/dev/null | field "$2" result | grep -qx "$3" && return 0
        sleep 0.2
    done
    return 1
}

# field <op> <key>: that key of every JSON line whose op matches, one per line; empty if unset.
field() {
    python3 -c '
import json, sys
op, key = sys.argv[1], sys.argv[2]
for line in sys.stdin:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("op") == op:
        v = d.get(key)
        print("" if v is None else v if isinstance(v, str) else json.dumps(v))' "$1" "$2"
}

# verdict <op>: ok, refused or unclear, from a call's output. refused needs the client's own
# connection error, so a broken client or a gRPC error cannot pass as either.
verdict() {
    local out
    out=$(cat)
    if echo "$out" | field connect result | grep -qx refused; then echo refused
    elif echo "$out" | field "$1" result | grep -qx ok; then echo ok
    else echo unclear; fi
}

rx_packets() {
    ip -s -j link show "vz-$1" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)[0]["stats64"]["rx"]["packets"])'
}

# drop_provider <name> <path>: remove a provider and wait for the databroker to release its claim.
# The broker sweeps for gone providers on a timer, so the release is not immediate.
drop_provider() {
    local i
    podman rm -f -t 0 "vxt-$1" >/dev/null 2>&1
    for i in $(seq 20); do
        kv hpc1 provide-actuator "$2" --duration-s 0.2 | field provide result | grep -qx ok && return 0
        sleep 0.5
    done
    fail "the claim on $2 was not released 10 s after its provider was removed"
}

broker_state() {
    podman inspect -f 'running={{.State.Running}} restarts={{.RestartCount}} started={{.State.StartedAt}}' \
        "$DATABROKER"
}

indent() { sed 's/^/      /'; }
