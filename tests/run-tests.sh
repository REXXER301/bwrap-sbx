#!/usr/bin/env bash
# Runs the sbx isolation suite. Only inside the test container started by
# tests/run.sh; it refuses to run anywhere else.
#
#   run-tests.sh            every suite
#   run-tests.sh 20 50      only suites whose file name contains 20 or 50
#
# 00-preconditions always runs first. If any of its control checks fail, the
# later results would mean nothing, so the run stops there.

set -u

die() { echo "run-tests.sh: $*" >&2; exit 1; }

[[ -f /run/.containerenv ]] || die "not inside a podman container — use tests/run.sh"
[[ ${SBX_TEST_CONTAINER-} == 1 ]] || die "not the sbx test image — use tests/run.sh"
[[ $(id -un) == tester ]] && ((EUID != 0)) || die "must run as the unprivileged 'tester' user"
[[ -f /etc/sbx-canary/canary.txt ]] || die "canary files missing — not the sbx test image"

SUITE_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib.sh
source "$SUITE_DIR/lib.sh"
trap cleanup EXIT

BASELINE=$(snapshot)

suites=()
for f in "$SUITE_DIR"/suite/*.sh; do
    [[ -f $f ]] || continue
    if (($#)) && [[ ${f##*/} != 00-* ]]; then
        want=0
        for pat in "$@"; do [[ ${f##*/} == *"$pat"* ]] && want=1; done
        ((want)) || continue
    fi
    suites+=("$f")
done

# An empty run would pass with nothing checked.
[[ ${suites[0]-} == */00-preconditions.sh ]] || die "00-preconditions.sh not found in $SUITE_DIR/suite"
((${#suites[@]} > 1)) || die "no suite matches: $*"

for f in "${suites[@]}"; do
    # shellcheck source=/dev/null
    source "$f"
    if [[ ${f##*/} == 00-* ]] && ((FAIL)); then
        section "Aborted"
        echo "  preconditions failed, so the remaining checks would not prove anything"
        summary
        exit 1
    fi
done

section "Final integrity"
canaries_intact "every canary file and folder unchanged after the run"

summary
