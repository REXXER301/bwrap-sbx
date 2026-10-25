# shellcheck shell=bash
# Processes, IPC, privileges and environment. No signal is sent to anything
# outside the sandbox except the helpers this suite starts itself.

section "Processes"

marker=sbx-outer-marker-$RAND
start_bg bash -c "exec -a $marker sleep 600"
sleep 0.3

# Script that exits $1 if the marker process is visible and $2 if not. It
# compares argv[0] with bash builtins only, so no helper process carries the
# marker in its own command line; the marker is split for the same reason.
marker_scan() {
    printf '%s' "m=\"sbx-outer-\"\"marker-$RAND\"
for f in /proc/[0-9]*/cmdline; do
    IFS= read -r -d '' a0 <\"\$f\" 2>/dev/null || true
    [ \"\$a0\" = \"\$m\" ] && exit $1
done
exit $2"
}

check "control: marker process visible outside sbx" bash -c "$(marker_scan 0 1)"
expect_ok "outer processes are invisible inside" "$(marker_scan 1 0)"
expect_ok "the sandbox sees only its own few processes" '[ "$(ls -d /proc/[0-9]* | wc -l)" -le 8 ]'
expect_ok "pid 1 inside is bwrap" '[ "$(cat /proc/1/comm)" = bwrap ]'

section "IPC"

shm_file=/dev/shm/sbx-outer-$RAND
printf 'outer shm\n' >"$shm_file"
track "$shm_file"
expect_ok "outer /dev/shm files are invisible" "[ ! -e '$shm_file' ]"

if shm_id=$(ipcmk -M 4096 2>/dev/null | grep -o '[0-9]*$'); then
    SHM_IDS+=("$shm_id")
    check "control: SysV shared memory segment visible outside" bash -c "ipcs -m | awk '\$2 == $shm_id' | grep -q ."
    expect_ok "outer SysV shared memory is invisible" "[ -z \"\$(ipcs -m | awk '\$2 ~ /^[0-9]+\$/')\" ]"
else
    known "skipped SysV IPC check, ipcmk failed in the container"
fi

section "Privileges"

status=$(sbx_sh 'cat /proc/self/status')
check "no effective capabilities" has_line '^CapEff:[[:space:]]+0+$' "$status"
check "no permitted capabilities" has_line '^CapPrm:[[:space:]]+0+$' "$status"
check "no ambient capabilities" has_line '^CapAmb:[[:space:]]+0+$' "$status"
check "no_new_privs is set" has_line '^NoNewPrivs:[[:space:]]+1$' "$status"
expect_ok "runs as the invoking uid, not root" "[ \"\$(id -u)\" = $(id -u) ]"

if OUT=$(sbx_sh 'unshare -r true'); then
    known "nested user namespaces are allowed by default (Claude Code and Codex need them)"
else
    fail "nested user namespaces should work without --no-userns"
fi
expect_denied "--no-userns forbids nested user namespaces" 'unshare -r true' --no-userns

section "Environment"

export SBX_TEST_SECRET=secret-$RAND
OUT=$(sbx_sh 'env -0 | tr "\0\n" "\n " | cut -d= -f1')
check "only sbx's own variables reach the sandbox" only_names \
    "HOME USER SHELL PATH TERM LANG TMPDIR SBX OPENAI_BASE_URL OPENAI_API_KEY COLORTERM \
     DO_NOT_TRACK DISABLE_TELEMETRY DISABLE_ERROR_REPORTING DISABLE_FEEDBACK_COMMAND \
     CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY PI_OFFLINE PI_TELEMETRY PI_SKIP_VERSION_CHECK \
     HF_HUB_DISABLE_TELEMETRY GRADIO_ANALYTICS_ENABLED NEXT_TELEMETRY_DISABLED \
     DOTNET_CLI_TELEMETRY_OPTOUT PWD OLDPWD SHLVL _" "$OUT"
expect_ok "a host variable is not inherited" '[ -z "${SBX_TEST_SECRET+x}" ]'
SBX_ENV=SBX_TEST_SECRET expect_ok "  ... unless passed with SBX_ENV" "[ \"\$SBX_TEST_SECRET\" = secret-$RAND ]"
expect_ok "HOME is the project's .sbx-home" "[ \"\$HOME\" = '$PROJ/.sbx-home' ]"
unset SBX_TEST_SECRET
