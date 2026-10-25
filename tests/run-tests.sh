#!/usr/bin/env bash
# Runs the sbx isolation suite. Only inside the test container started by
# tests/run.sh; it refuses to run anywhere else.
#
#   run-tests.sh            every suite
#   run-tests.sh 20 50      only suites whose file name contains 20 or 50

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

for f in "$SUITE_DIR"/suite/*.sh; do
    if (($#)); then
        want=0
        for pat in "$@"; do [[ ${f##*/} == *"$pat"* ]] && want=1; done
        ((want)) || continue
    fi
    # shellcheck source=/dev/null
    source "$f"
done

section "Final integrity"
canaries_intact "every canary file and folder unchanged after the run"

summary
