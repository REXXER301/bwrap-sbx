# shellcheck shell=bash
# Helpers for the sbx isolation suite. Sourced by run-tests.sh, which only runs
# inside the test container.
#
# Safety rules every suite follows:
#   - Writes, changes and deletes only ever target single files: the canaries
#     planted by the Containerfile, or probe files the suite creates itself.
#   - No recursive deletes and no folder removal anywhere (00-preconditions
#     greps the suite to enforce this).
#   - Cleanup goes through remove_probe, which only removes single probe files
#     matching fixed name patterns and refuses folders.

PROJ=/home/tester/work/proj
RAND=$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')
READY=__sbx_ready__

# Planted by the Containerfile. Outside sbx the test user may change all of them.
CANARIES=(
    /etc/sbx-canary/canary.txt
    /usr/share/sbx-canary/canary.txt
    /opt/sbx-canary/canary.txt
    /mnt/sbx-canary/canary.txt
    /srv/sbx-canary/canary.txt
    /home/tester/canary.txt
    /home/tester/work/other-project/canary.txt
    /home/tester/ro-share/canary.txt
    "$PROJ/existing.txt"
)
# Their folders, listed to catch files created, renamed or removed in them.
CANARY_DIRS=(
    /etc/sbx-canary
    /usr/share/sbx-canary
    /opt/sbx-canary
    /mnt/sbx-canary
    /srv/sbx-canary
    /home/tester/work/other-project
    /home/tester/ro-share
)

PASS=0 FAIL=0 KNOWN=0
FAILED=()
CLEANUP=()
BG_PIDS=()
SHM_IDS=()
OUT=""

if [[ -t 1 ]]; then
    c_ok=$'\e[32m' c_bad=$'\e[31m' c_info=$'\e[33m' c_head=$'\e[1m' c_off=$'\e[0m'
else
    c_ok="" c_bad="" c_info="" c_head="" c_off=""
fi

section() { printf '\n%s== %s%s\n' "$c_head" "$*" "$c_off"; }

pass() { PASS=$((PASS + 1)); printf '  %sPASS%s   %s\n' "$c_ok" "$c_off" "$1"; }

fail() {
    FAIL=$((FAIL + 1))
    FAILED+=("$1")
    printf '  %sFAIL%s   %s\n' "$c_bad" "$c_off" "$1"
    [[ -n $OUT ]] && printf '%s\n' "$OUT" | head -n 15 | sed 's/^/         | /'
    return 0
}

# Behaviour sbx documents as outside its guarantees (README, "What this does
# not protect against"). Reported, not counted as a failure.
known() { KNOWN=$((KNOWN + 1)); printf '  %sKNOWN%s  %s\n' "$c_info" "$c_off" "$1"; }

# ---- running things ---------------------------------------------------------

# sbx_sh SCRIPT [SBX_OPTIONS...]: run SCRIPT with bash inside sbx, from the project.
sbx_sh() {
    local script=$1
    shift
    (cd "$PROJ" && sbx "$@" -- /usr/bin/bash -c "$script") </dev/null 2>&1
}

# sbx_cli ARGS...: call sbx itself from the project, for option handling tests.
sbx_cli() { (cd "$PROJ" && sbx "$@") </dev/null 2>&1; }

# check NAME CMD...: pass when CMD (run outside sbx) succeeds.
check() {
    local name=$1
    shift
    if OUT=$("$@" 2>&1); then pass "$name"; else fail "$name"; fi
}

# check_exit NAME CODE TEXT CMD...: pass when CMD exits with CODE and prints TEXT.
check_exit() {
    local name=$1 want=$2 text=$3 rc=0
    shift 3
    OUT=$("$@" </dev/null 2>&1) || rc=$?
    if ((rc == want)) && [[ $OUT == *"$text"* ]]; then
        pass "$name"
    else
        OUT="exit $rc (expected $want, output should contain '$text'):"$'\n'"$OUT"
        fail "$name"
    fi
}

# expect_ok NAME SCRIPT [SBX_OPTIONS...]: SCRIPT must succeed inside sbx.
expect_ok() {
    local name=$1 script=$2
    shift 2
    if OUT=$(sbx_sh "$script" "$@"); then pass "$name"; else fail "$name"; fi
}

# expect_denied NAME SCRIPT [SBX_OPTIONS...]: SCRIPT must fail inside sbx. The
# READY marker proves the sandbox started, so a broken sbx can't pass this.
expect_denied() {
    local name=$1 script=$2 rc=0
    shift 2
    OUT=$(sbx_sh "echo $READY; $script" "$@") || rc=$?
    if ((rc == 0)); then
        fail "$name (it was allowed)"
    elif [[ $OUT != *"$READY"* ]]; then
        OUT="sbx did not start (exit $rc):"$'\n'"$OUT"
        fail "$name"
    else
        pass "$name"
    fi
}

# expect_contained NAME SCRIPT [SBX_OPTIONS...]: for paths that don't exist
# inside sbx. A write there may fail, or land in the sandbox's throwaway tmpfs;
# either is fine as long as no canary outside changed.
expect_contained() {
    local name=$1 script=$2 rc=0 how
    shift 2
    OUT=$(sbx_sh "echo $READY; $script" "$@") || rc=$?
    if [[ $OUT != *"$READY"* ]]; then
        OUT="sbx did not start (exit $rc):"$'\n'"$OUT"
        fail "$name"
        return
    fi
    ((rc)) && how="refused" || how="landed in the sandbox tmpfs"
    if [[ $(snapshot) == "$BASELINE" ]]; then
        pass "$name ($how, canaries unchanged)"
    else
        OUT=$(diff <(printf '%s\n' "$BASELINE") <(snapshot))
        fail "$name"
    fi
}

# start_bg CMD...: start a helper process outside sbx; killed on exit.
start_bg() {
    "$@" >/dev/null 2>&1 &
    BG_PIDS+=($!)
}

# ---- canaries ---------------------------------------------------------------

# Content hash, mode, mtime, size and owner of each canary, plus folder listings.
snapshot() {
    local f d
    for f in "${CANARIES[@]}"; do
        if [[ -e $f ]]; then
            printf '%s %s %s\n' "$(sha256sum <"$f" | cut -d' ' -f1)" "$(stat -c '%a %Y %s %u' -- "$f")" "$f"
        else
            printf 'MISSING %s\n' "$f"
        fi
    done
    for d in "${CANARY_DIRS[@]}"; do
        printf '[%s] %s\n' "$d" "$(ls -1A -- "$d" | tr '\n' ' ')"
    done
}

canaries_intact() {
    local now
    now=$(snapshot)
    if [[ $now == "$BASELINE" ]]; then
        OUT=""
        pass "$1"
    else
        OUT=$(diff <(printf '%s\n' "$BASELINE") <(printf '%s\n' "$now"))
        fail "$1"
    fi
}

# ---- cleanup ----------------------------------------------------------------

track() { CLEANUP+=("$1"); }

# Remove one probe file the suite created. Anything that is not a single file
# matching a probe pattern is refused.
remove_probe() {
    local p=$1
    case $p in
        "$PROJ"/sbx-probe-* | "$PROJ"/.sbx-home/sbx-probe-* | /tmp/sbx-outer-* | /tmp/sbx-probe-* | /dev/shm/sbx-*) ;;
        *) echo "remove_probe: refusing '$p': not a probe file path" >&2; return 1 ;;
    esac
    if [[ -d $p && ! -L $p ]]; then
        echo "remove_probe: refusing '$p': it is a folder" >&2
        return 1
    fi
    if [[ -e $p || -L $p ]]; then rm -f -- "$p"; fi
    return 0
}

cleanup() {
    local p id
    ((${#BG_PIDS[@]})) && kill "${BG_PIDS[@]}" 2>/dev/null
    for id in "${SHM_IDS[@]}"; do ipcrm -m "$id" 2>/dev/null; done
    for p in "${CLEANUP[@]}"; do remove_probe "$p"; done
    return 0
}

# ---- small predicates -------------------------------------------------------

# has_line REGEX TEXT
has_line() { grep -qE -- "$1" <<<"$2"; }

# only_names "ALLOWED NAMES" TEXT: every line of TEXT is one of the allowed names.
only_names() {
    local allowed=" $1 " line bad=()
    while IFS= read -r line; do
        [[ -z $line || $allowed == *" $line "* ]] || bad+=("$line")
    done <<<"$2"
    ((${#bad[@]} == 0)) || { echo "unexpected: ${bad[*]}"; return 1; }
}

summary() {
    printf '\n%s%d passed, %d failed, %d known/documented%s\n' "$c_head" "$PASS" "$FAIL" "$KNOWN" "$c_off"
    if ((FAIL)); then
        printf '%sFailed:%s\n' "$c_bad" "$c_off"
        printf '  - %s\n' "${FAILED[@]}"
        return 1
    fi
}
