# shellcheck shell=bash
# What the sandbox can see. Read-only checks.

section "Filesystem visibility"

outer_tmp=/tmp/sbx-outer-$RAND.txt
printf 'outer tmp\n' >"$outer_tmp"
track "$outer_tmp"

for p in /home/tester/canary.txt /home/tester/work/other-project /home/tester/ro-share \
         /opt/sbx-canary /mnt/sbx-canary /srv/sbx-canary /opt/sbx-tests /root \
         /run/.containerenv "$outer_tmp"; do
    if [[ -e $p ]]; then
        expect_ok "hidden inside sbx: $p" "[ ! -e '$p' ] && [ ! -L '$p' ]"
    else
        known "skipped, $p does not exist in the container either"
    fi
done

expect_ok "only the project's own path exists under /home" \
    '[ "$(ls -1A /home)" = tester ] && [ "$(ls -1A /home/tester)" = work ] && [ "$(ls -1A /home/tester/work)" = proj ]'

OUT=$(sbx_sh 'ls -1A /')
check "/ holds only the expected top-level entries" \
    only_names "bin dev etc home lib lib64 proc run sbin tmp usr var" "$OUT"

expect_ok "project files are visible" "grep -qx 'project file' '$PROJ/existing.txt'"
expect_ok "/usr and /etc are readable" 'test -r /etc/os-release && test -x /usr/bin/bash'
expect_ok "read-only canaries are readable with their original content" \
    "grep -qx 'sbx canary: must never change' /etc/sbx-canary/canary.txt /usr/share/sbx-canary/canary.txt"
