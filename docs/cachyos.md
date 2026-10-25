<!-- topic: Linux/Virtual_Machines/Sandbox -->
# `sbx` — Linux edition

Developed on CachyOS (Arch) with KDE, fish, a llama.cpp server on the host and an NVIDIA
GPU. Any distro with bubblewrap and unprivileged user namespaces works the same way.

See the [README](../README.md) for what sbx does and doesn't protect against, and
[agents.md](agents.md) for pi, Claude Code and Codex.

---

## 1. Install

```fish
paru -S bubblewrap socat nodejs npm     # socat: --offline/--publish; node: pi, codex
install -Dm755 sbx ~/.local/bin/sbx
fish_add_path ~/.local/bin
```

The script is bash, so it runs from fish without changes. Inside, the interactive shell is
your login shell (fish here), and that's also what agents see as `$SHELL`. Use
`SBX_SHELL=/usr/bin/bash sbx` for a different one.

Unprivileged user namespaces must be enabled. That's the default on Arch/CachyOS:

```fish
sysctl kernel.unprivileged_userns_clone 2>/dev/null; or echo "not present = fine on Arch"
```

Ubuntu and derivatives restrict them through AppArmor; see the troubleshooting table in
[wsl2.md](wsl2.md#troubleshooting). It applies to native Ubuntu too.

## 2. Verify the boundary

Run these once, and again after any change to the script:

```fish
cd ~/projects/foo
sbx -- ls -1 /                                    # bin dev etc lib lib64 proc run sbin tmp usr var
sbx -- cat ~/.ssh/id_ed25519                      # no such file
sbx -- touch /etc/passwd                          # read-only file system
sbx -- ls -1 ..                                   # only your project folder
sbx -- env                                        # only the variables sbx sets
sbx -- curl -sI https://example.com | head -1     # DNS works
sbx --offline -- curl -sm3 https://example.com    # fails, no route
sbx --offline -- curl -sm3 127.0.0.1:8001/health  # {"status":"ok"}
sbx --gpu -- nvidia-smi                           # GPU visible
```

Nested bubblewrap check, needed by Claude Code's and Codex's own sandboxes. Expect `0`:

```fish
sbx -- bwrap --unshare-all --proc /proc --dev /dev \
  --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 \
  --symlink usr/bin /bin -- /bin/true; echo $status
```

A `Can't mount proc` error means nesting is broken; see
[agents.md § The inner sandbox](agents.md#the-inner-sandbox).

## 3. How it works

`bwrap` unshares the user, mount, pid, net, ipc and uts namespaces, builds a fresh root from the
bind mounts on its command line, then `execve()`s your program into it. There's no image, no
daemon and no overlayfs. Startup takes a few milliseconds, and nothing is written outside the
project.

Online mode shares the host network namespace, so llama.cpp is already on loopback. On
systemd-resolved systems, sbx binds `/run/systemd/resolve` read-only so DNS keeps working.
Offline mode unshares the network entirely and bridges the model server in over a unix socket,
re-exposed on the sandbox's private loopback.

### Python and toolchains

The sandbox uses the host interpreter directly: the same `/usr/bin/python3` and the same
`site-packages`, read-only.

- System-wide installs fail (read-only, plus PEP 668). That's intended.
- `python -m venv .venv` and `uv venv` work normally; the writable parts land in the project.
- `uv python install` fetches a private interpreter into `$HOME`, which is `.sbx-home`.
- pip, uv and npm caches also land in `.sbx-home`, so they persist across runs inside the
  project.

The same goes for node, cargo and others: host binaries, project-local state.

## 4. Linux-specific notes

**Snapshots.** sbx doesn't protect the project directory itself. On the CachyOS btrfs
default, snapshot before risky runs (with the project as its own subvolume):
`sudo btrfs subvolume snapshot . .snap-(date +%s)`.

**Resource limits.** None by default. Use
`systemd-run --user --scope -p MemoryMax=32G -p CPUQuota=800% sbx -- pi`.

**GPU.** `--gpu` exposes `/dev/nvidia*` and `/dev/dri` with full access. There's no VRAM
partitioning, so the sandbox can starve a llama.cpp server running on the host.

**Terminal.** `--new-session` is deliberately left out, because it breaks Ctrl-C and TUIs. On
kernels ≥ 6.2 `TIOCSTI` is disabled by default (`dev.tty.legacy_tiocsti=0`), and that's what
the flag would otherwise protect against. Check with `sysctl dev.tty.legacy_tiocsti`.

**Tighter `/etc`.** `/etc` is readable. If that matters, replace `--ro-bind /etc /etc` with
individual binds of `resolv.conf`, `ssl`, `passwd`, `group` and whatever else your tools need.

**Orphaned `socat`.** A hard kill (`kill -9` on sbx) can leave the host-side bridge running.
`pkill -f sbx-llama` cleans up.

## 5. Why this approach

**Mounts rather than a container image.** "Can't touch anything outside this folder" is a
property of the mount list, not of a runtime. Bubblewrap expresses exactly that list, so the
whole security argument fits in one script you can audit by reading it.

**Not Podman.** It would work, but it costs an image, overlay writes per run, about 1 s of
startup, and a userland that diverges from the host: CUDA, Python and tooling all have to be
reproduced inside. It's the better choice if you *want* a different distro userland.

**Not a VM.** It's a stronger boundary, but it means a disk image, boot time, GPU passthrough
and a file share back to the project. That's worth it for hostile code, not for confused
agents.

**Not `chroot` or a dedicated user.** `chroot` needs root and isn't a security boundary. A
dedicated user is stateful host setup, and still leaves the whole readable filesystem exposed.

**Offline is a socket bridge, not a firewall rule.** nftables needs root, is global, and is
easy to leave broken. An unshared netns is unprivileged, scoped to one process tree, and
self-cleaning. Bridging the single model endpoint back in keeps "no route anywhere" literally
true.
