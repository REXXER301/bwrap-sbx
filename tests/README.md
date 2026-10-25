# sbx isolation tests

Checks that `sbx` keeps sandboxed code inside its boundary. The suite runs sbx **inside a
rootless podman container**: the container plays the part of the host, so every file the
tests touch belongs to the container, never to your machine.

```bash
tests/run.sh            # build the image, run every suite
tests/run.sh 20 50      # only suites whose file name contains 20 or 50
```

Requires rootless `podman` on the host. The first build pulls `archlinux:latest` and installs
`bubblewrap` and `socat`, so it needs network. The test run itself does not.

CI runs the same `tests/run.sh` on GitHub Actions (`.github/workflows/isolation-tests.yml`)
for pushes to `main` and pull requests that touch `sbx` or `tests/`.

## Safety

- **Nothing from the host is mounted** into the container (no `-v`), and it runs with
  `--network none`, `--cap-drop ALL`, a pid limit and a memory limit, as the unprivileged
  `tester` user.
- `run-tests.sh` **refuses to run outside the test container**. It checks for
  `/run/.containerenv`, the image's `SBX_TEST_CONTAINER=1`, the `tester` user and the planted
  canary files.
- **Writes, changes and deletes only ever target single files.** These are either the canary
  files the Containerfile plants, or probe files the suite creates itself (`sbx-probe-*`,
  `sbx-outer-*`). The suite never removes a folder or deletes anything recursively.
  `00-preconditions` greps the suite and fails if a recursive delete appears. Cleanup goes
  through `remove_probe`, which refuses folders and any path outside the probe name patterns.
- **No escape attempts beyond the container.** The suite tests the sbx boundary only, and
  never touches system folders such as `/usr` or `/etc`. It only uses dedicated canary files
  inside them (`/etc/sbx-canary/canary.txt`, `/usr/share/sbx-canary/canary.txt`).

bwrap must mount a fresh `/proc` inside the container. `run.sh` first tries podman with only
`--security-opt unmask=/proc/*`. If bwrap can't start that way, it falls back to also
disabling seccomp, SELinux labels and the AppArmor profile for the container, and prints
which options it used.
Both options stay inside podman's rootless user namespace.

## How a check proves something

Each canary file and its folder belong to `tester`. Outside sbx the test user could change or
delete them, and `00-preconditions` confirms that with `test -w`. So when the same change
fails inside sbx, sbx blocked it, not file permissions. After each group of write attempts,
and once more at the end, the suite compares every canary against a baseline taken at start:
hash, mode, mtime, size, owner, and the listing of each canary folder.

`expect_denied` checks only count when the sandbox actually started (a marker is echoed first),
so a broken sbx can't pass them. For paths that don't exist inside sbx at all, a write may fail
or land in the sandbox's throwaway tmpfs. Either is fine, and the check passes if no canary
outside changed.

## What is checked

| Suite | Checks |
|---|---|
| `00-preconditions` | no recursive deletes in the suite, canaries writable outside sbx, sbx starts |
| `10-visibility` | `$HOME`, sibling projects, `/opt`, `/mnt`, `/srv`, `/root`, outer `/tmp` hidden. `/` holds only expected entries; `/usr`, `/etc` and the project readable |
| `20-writes` | project: create, change, delete one probe file. `/etc` and `/usr` canaries: append, truncate, chmod, touch, rename, delete, create beside, hard-link into the project all fail. Hidden canaries and symlinks planted in the project can't reach the real files. Private `/tmp` and `/dev/shm`; `--ro` is read-only |
| `30-mounts` | the project is the only writable host mount; `/usr`, `/etc` and `--ro` are read-only; mount, remount-rw and umount fail, even from a nested user namespace; minimal `/dev`, no block devices, `mknod` fails |
| `40-processes` | outer processes invisible, separate IPC (`/dev/shm`, SysV), no capabilities, `no_new_privs`, `--no-userns`, environment cleared, `SBX_ENV` pass-through |
| `50-network` | `--offline`: own netns with only `lo`; host TCP, abstract and path unix sockets unreachable; only the bridged model port works. Online: path unix sockets in the host's `/tmp` unreachable |
| `60-cli-guards` | sbx refuses `/`, `/tmp`, `$HOME`, `--ro` of `/`, `$HOME` or a project parent, bad `--port`/`--allow`, `--publish` without `--offline` |

`KNOWN` lines report behaviour the main README lists under "What this does not protect
against", for example that online mode shares the host network, including its loopback and
abstract unix sockets. They don't count as failures.

## Files

- `run.sh`: host side. Builds the image, picks the podman options, runs the suite.
- `Containerfile`, `containerignore`: the test image. The build context is only `sbx` and `tests/`.
- `preflight.sh`: tells whether bwrap can start in the container.
- `run-tests.sh`, `lib.sh`, `suite/*.sh`: the suite. Runs inside the container only.
