# shellcheck shell=bash
# Network namespaces and sockets. The container runs with --network none, so
# everything here stays on the container's own loopback.

section "Network"

tcp_port=18765
bridge_port=18801
abstract=sbx-test-$RAND
unix_sock=/tmp/sbx-outer-$RAND.sock
track "$unix_sock"

# Listeners outside sbx that answer "pong".
start_bg socat TCP-LISTEN:$tcp_port,bind=127.0.0.1,reuseaddr,fork SYSTEM:"echo pong"
start_bg socat TCP-LISTEN:$bridge_port,bind=127.0.0.1,reuseaddr,fork SYSTEM:"echo pong"
start_bg socat ABSTRACT-LISTEN:$abstract,fork SYSTEM:"echo pong"
start_bg socat UNIX-LISTEN:$unix_sock,fork SYSTEM:"echo pong"

# pong_script ADDRESS: script that succeeds when a socat ADDRESS answers "pong". Retries
# briefly, since listeners (and sbx's offline bridge) start in the background.
pong_script() {
    printf '%s' "for i in 1 2 3 4 5 6 7 8 9 10; do
    [ \"\$(timeout 3 socat -u $1 - 2>/dev/null)\" = pong ] && exit 0
    sleep 0.2
done
exit 1"
}

check "control: TCP listener answers outside sbx" bash -c "$(pong_script TCP:127.0.0.1:$tcp_port)"
check "control: abstract socket answers outside sbx" bash -c "$(pong_script ABSTRACT-CONNECT:$abstract)"
check "control: unix socket answers outside sbx" bash -c "$(pong_script UNIX-CONNECT:$unix_sock)"

outer_ns=$(readlink /proc/self/ns/net)
online_ns=$(sbx_sh 'readlink /proc/self/ns/net' | tail -n1)
offline_ns=$(sbx_sh 'readlink /proc/self/ns/net' --offline --port $bridge_port | tail -n1)

# Online mode shares the host network by design (README: "Anything over the
# network when online"), so these are reported, not failed.
if [[ $online_ns == "$outer_ns" ]]; then
    known "online mode shares the host network namespace"
else
    OUT="outer $outer_ns, inside $online_ns"
    fail "online mode should share the host network namespace"
fi
if OUT=$(sbx_sh "$(pong_script TCP:127.0.0.1:$tcp_port)"); then
    known "online mode reaches TCP services on the host's 127.0.0.1"
else
    fail "online mode should reach the host's 127.0.0.1"
fi
if OUT=$(sbx_sh "$(pong_script ABSTRACT-CONNECT:$abstract)"); then
    known "online mode reaches abstract unix sockets of the host network namespace"
else
    pass "online mode can't reach abstract unix sockets"
fi
expect_denied "unix socket in the host's /tmp is unreachable (online)" "$(pong_script UNIX-CONNECT:$unix_sock)"

section "Network --offline"

check "offline mode has its own network namespace" test "$offline_ns" != "$outer_ns" -a -n "$offline_ns"
OUT=$(sbx_sh 'tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d " "' --offline --port $bridge_port)
check "offline mode has only a loopback interface" test "$OUT" = lo
expect_denied "offline: host TCP service unreachable" "$(pong_script TCP:127.0.0.1:$tcp_port)" --offline --port $bridge_port
expect_denied "offline: abstract unix socket unreachable" "$(pong_script ABSTRACT-CONNECT:$abstract)" --offline --port $bridge_port
expect_denied "offline: unix socket in the host's /tmp unreachable" "$(pong_script UNIX-CONNECT:$unix_sock)" --offline --port $bridge_port
expect_ok "offline: the one bridged model port still works" "$(pong_script TCP:127.0.0.1:$bridge_port)" --offline --port $bridge_port
