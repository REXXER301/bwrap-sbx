# shellcheck shell=bash
# Create, modify and delete. Every target is a single file: a canary planted by
# the Containerfile or a probe file created here. No folder is ever removed.

section "Project folder: create, modify, delete one probe file (must work)"

probe=$PROJ/sbx-probe-$RAND.txt
track "$probe"
expect_ok "create a new file in the project" "printf 'created\n' >'$probe'"
check "  ... visible outside with the same content" grep -qx created "$probe"
check "  ... owned by the invoking user outside" test -O "$probe"
expect_ok "append to that file" "printf 'modified\n' >>'$probe'"
check "  ... change visible outside" grep -qx modified "$probe"
expect_ok "delete that file (plain rm on one file)" "rm -- '$probe'"
check "  ... gone outside" test ! -e "$probe"

home_probe=$PROJ/.sbx-home/sbx-probe-$RAND.txt
track "$home_probe"
expect_ok "\$HOME writes land in the project's .sbx-home" "printf 'home\n' >\"\$HOME/sbx-probe-$RAND.txt\""
check "  ... visible outside at $home_probe" grep -qx home "$home_probe"
expect_ok "  ... and can be deleted again" "rm -- \"\$HOME/sbx-probe-$RAND.txt\""

section "Read-only host paths: modify, delete, create must fail"

n=0
for c in /etc/sbx-canary/canary.txt /usr/share/sbx-canary/canary.txt; do
    d=${c%/*}
    n=$((n + 1))
    expect_denied "append to $c" "printf tamper >>'$c'"
    expect_denied "truncate $c" ": >'$c'"
    expect_denied "chmod $c" "chmod 600 '$c'"
    expect_denied "touch (change mtime of) $c" "touch '$c'"
    expect_denied "rename $c" "mv -- '$c' '$d/sbx-probe-renamed.txt'"
    expect_denied "delete $c" "rm -- '$c'"
    expect_denied "create a new file in $d" "printf x >'$d/sbx-probe-$RAND.txt'"
    expect_denied "hard-link $c into the project" "ln -- '$c' '$PROJ/sbx-probe-hardlink-$n-$RAND'"
    track "$PROJ/sbx-probe-hardlink-$n-$RAND"
done
canaries_intact "read-only canaries and their folders unchanged"

section "Hidden host paths: writes can't reach them"

for c in /home/tester/canary.txt /home/tester/work/other-project/canary.txt \
         /opt/sbx-canary/canary.txt /mnt/sbx-canary/canary.txt /srv/sbx-canary/canary.txt; do
    expect_contained "append to hidden $c" "printf tamper >>'$c'"
    expect_contained "delete hidden $c" "rm -- '$c'"
done
canaries_intact "hidden canaries and their folders unchanged"

section "Symlinks planted in the project"

link_home=$PROJ/sbx-probe-link-home-$RAND
link_etc=$PROJ/sbx-probe-link-etc-$RAND
ln -s /home/tester/canary.txt "$link_home"
ln -s /etc/sbx-canary/canary.txt "$link_etc"
track "$link_home"
track "$link_etc"

expect_contained "write through a symlink to the hidden home canary" "printf tamper >>'$link_home'"
expect_denied "write through a symlink to the read-only /etc canary" "printf tamper >>'$link_etc'"
expect_ok "rm on the symlink removes only the link" "rm -- '$link_etc'"
check "  ... link gone outside" test ! -L "$link_etc"
canaries_intact "symlink targets unchanged"

section "Private /tmp and /dev/shm"

for d in /tmp /dev/shm; do
    p=$d/sbx-probe-$RAND.txt
    track "$p"
    expect_ok "write a probe file in the sandbox's $d" "printf x >'$p'"
    check "  ... not visible in the container's $d" test ! -e "$p"
done

section "--ro shared folder"

ro=/home/tester/ro-share
expect_ok "readable with --ro" "grep -q canary '$ro/canary.txt'" --ro "$ro"
expect_denied "append with --ro" "printf tamper >>'$ro/canary.txt'" --ro "$ro"
expect_denied "chmod with --ro" "chmod 600 '$ro/canary.txt'" --ro "$ro"
expect_denied "delete with --ro" "rm -- '$ro/canary.txt'" --ro "$ro"
expect_denied "create a new file in a --ro folder" "printf x >'$ro/sbx-probe-$RAND.txt'" --ro "$ro"
canaries_intact "--ro canary and folder unchanged"
