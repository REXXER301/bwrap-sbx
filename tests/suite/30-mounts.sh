# shellcheck shell=bash
# Mount table, mount attempts and device nodes. Nothing here writes a file
# outside the sandbox's own throwaway tmpfs.

section "Mount table"

# Writable mounts inside sbx that share a device with a container mount are
# host folders. Only the project (and the /dev nodes bwrap binds) may be one.
writable_host_mounts() {
    local outer_devs id parent dev root mp opts rest bad=0
    outer_devs=" $(awk '{print $3}' /proc/self/mountinfo | sort -u | tr '\n' ' ') "
    while read -r id parent dev root mp opts rest; do
        [[ $id =~ ^[0-9]+$ ]] || continue
        [[ ,$opts, == *,rw,* && $outer_devs == *" $dev "* ]] || continue
        case $mp in
            "$PROJ" | /dev/null | /dev/zero | /dev/full | /dev/random | /dev/urandom | /dev/tty | /dev/console) ;;
            *) echo "writable host mount: $mp (device $dev, source root $root)"; bad=1 ;;
        esac
    done <<<"$1"
    return "$bad"
}

# mount_has MOUNTPOINT OPTION MOUNTINFO
mount_has() {
    local id parent dev root mp opts rest
    while read -r id parent dev root mp opts rest; do
        [[ $mp == "$1" && ,$opts, == *,"$2",* ]] && return 0
    done <<<"$3"
    echo "no $2 mount at $1"
    return 1
}

mountinfo=$(sbx_sh 'cat /proc/self/mountinfo')
check "the project is the only writable host mount" writable_host_mounts "$mountinfo"
check "/usr is mounted read-only" mount_has /usr ro "$mountinfo"
check "/etc is mounted read-only" mount_has /etc ro "$mountinfo"
check "the project is mounted read-write" mount_has "$PROJ" rw "$mountinfo"

mountinfo=$(sbx_sh 'cat /proc/self/mountinfo' --ro /home/tester/ro-share)
check "--ro folder is mounted read-only" mount_has /home/tester/ro-share ro "$mountinfo"
check "--ro adds no writable host mount" writable_host_mounts "$mountinfo"

section "Mount attempts (must fail)"

expect_denied "mount a tmpfs" 'mount -t tmpfs none /tmp'
expect_denied "remount /usr read-write from a nested user namespace" 'unshare -rm mount -o remount,bind,rw /usr'
expect_denied "remount /etc read-write from a nested user namespace" 'unshare -rm mount -o remount,bind,rw /etc'
expect_denied "unmount /usr from a nested user namespace" 'unshare -rm umount /usr'
canaries_intact "canaries unchanged after mount attempts"

section "Devices"

OUT=$(sbx_sh 'ls -1A /dev')
check "/dev holds only the minimal device set" \
    only_names "console core fd full mqueue null ptmx pts random shm stderr stdin stdout tty urandom zero" "$OUT"
expect_ok "no block devices in /dev" '[ -z "$(find /dev -type b 2>/dev/null)" ]'
expect_denied "mknod a block device" "mknod /tmp/sbx-probe-blk-$RAND b 8 0"
expect_denied "mknod a block device in a nested user namespace" "unshare -r mknod /tmp/sbx-probe-blk-$RAND b 8 0"
