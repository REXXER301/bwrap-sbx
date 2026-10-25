#!/usr/bin/env bash
# Can bubblewrap build a full sandbox in this container? run.sh uses the exit
# code to pick the podman security options.
exec bwrap --unshare-all --die-with-parent \
    --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/bin /bin \
    --proc /proc --dev /dev --tmpfs /tmp \
    -- /usr/bin/true
