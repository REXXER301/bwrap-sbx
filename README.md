# bwrap-sbx

Minimal bubblewrap sandbox rooted at your project directory. Built for AI coding agents
(Claude Code, Codex, pi), but works for pretty much anything. Supports Linux and Windows over WSL2.

```bash
cd ~/projects/foo
sbx -- claude          # the agent can write to foo and nowhere else
```
Besides foo, the host's `/usr` and `/etc` are mounted read-only, so the host's programs,
libraries and certificates work inside without installing anything. Your home directory,
other drives and host processes are not visible. The network is shared unless you pass
`--offline`.

Minimal overhead with one bash script, no daemon, image or root. Startup takes a few milliseconds.

## What it does

`sbx` starts a command in fresh Linux namespaces (user, mount, pid, network, ipc, uts) with
an empty root filesystem, then adds exactly these mounts. Anything not listed, such as
`/home`, `/root`, `/mnt` (e.g. Windows drives on WSL), `/media` or `/opt`, doesn't exist inside:

| Path inside | What it is |
|---|---|
| project dir (real host path) | host folder, **read-write**, the only writable host path |
| `/usr`, `/etc` | host folders, read-only (not copies: readable files in them can be read) |
| `/run/systemd/resolve`, resolv.conf target | host DNS config, read-only, online mode only |
| `/`, `/tmp`, `/run`, `/var`, `/dev/shm` | new empty tmpfs, discarded on exit |
| `/dev` | new tmpfs with only `null`, `zero`, `full`, `random`, `urandom`, `tty`, a private `pts` |
| `/proc` | new procfs: only the sandbox's own processes. Host-wide kernel info such as `/proc/cpuinfo` stays readable. |
| `/bin`, `/lib`, `/lib64`, `/sbin` | symlinks into `/usr` |
| `$HOME` | `project/.sbx-home`, part of the project (sbx puts a `.gitignore` in it, so git skips it) |
| GPU devices | `/dev/nvidia*`, `/dev/dri`, `/dev/dxg` (WSL), only with `--gpu` |
| extra host folders | only with `--ro PATH`, read-only, at their real path |
| `~/.claude.json`, `~/.claude/.credentials.json` | host files, **read-write**, only with `--share-auth` |
| `/opt/claude/bin/claude` | host binary, read-only, only with `--host-claude` |

- **The environment is cleared.** Only `TERM`, `LANG`, `COLORTERM` and what sbx sets itself
  get through. API keys too must be passed explicitly: `SBX_ENV="ANTHROPIC_API_KEY HF_TOKEN"`.
- **No telemetry by default.** Telemetry, error reporting and feedback prompts are off for
  Claude Code, Codex, pi and common tools (`DO_NOT_TRACK=1`). Auto-updates stay on.
  `SBX_TELEMETRY=1` allows telemetry. Details: [docs/agents.md](docs/agents.md#telemetry-off-by-default).
- **Network:** by default the sandbox shares the host network. `--offline` removes the
  network entirely, apart from one bridged local model endpoint (llama.cpp on
  `127.0.0.1:8001`).
- **Published ports:** `--offline --publish 8188` lets connections *in* to one port, while
  code inside still can't open connections out.
- **Real paths:** the project keeps its host path, so a `.venv` made inside still works
  outside.

Check it yourself: `sbx -- cat /proc/self/mountinfo` lists every mount.

## Install

Requirements: `bubblewrap`, plus `socat` for `--offline`/`--publish`, plus `nodejs`/`npm`
for pi and Codex. The script is bash but works from any shell. The interactive shell inside
follows your login shell (fish, zsh, bash), or set `SBX_SHELL`.

```bash
install -Dm755 sbx ~/.local/bin/sbx
```

Platform guides with verification steps:

- **Linux edition** (developed on CachyOS/Arch): [docs/cachyos.md](docs/cachyos.md)
- **WSL2** (Ubuntu 24.04, Arch): [docs/wsl2.md](docs/wsl2.md)

The same script runs on both. It detects WSL and adds `/dev/dxg` for the GPU and the DNS
symlink fix where needed.

## Usage

```bash
sbx                                  # interactive shell, prompt shows (sbx)
sbx -- CMD ARGS...                   # run anything
sbx --help
```

| Option | Effect |
|---|---|
| `--offline` | No network namespace; llama.cpp still reachable at `127.0.0.1:$port` |
| `--port N` | Local model port (default `8001`) |
| `--gpu` | Expose `/dev/nvidia*`, `/dev/dri`, `/dev/dxg` (WSL) |
| `--ro PATH` | Share a host folder read-only at its real path (repeatable) |
| `--publish [ADDR:]PORT` | With `--offline`: make one sandbox port reachable from outside |
| `--allow CIDR` | Only these clients may connect to published ports |
| `--no-userns` | Code inside can't create nested namespaces (not for claude/codex) |
| `--share-auth` | Claude Code: bind the host login files read-write (see below) |
| `--host-claude` | Claude Code: use the host binary read-only, install nothing |

## Coding agents

The first run installs the agent into the project's `.sbx-home`, writes a minimal config,
and launches it. Later runs just launch it. Delete `.sbx-home` to start over.

```bash
sbx -- pi                            # local model via llama.cpp, config auto-detected
sbx --offline -- pi                  # same, no internet at all
sbx -- claude                        # Claude Code, its own bash sandbox enabled
sbx -- claude --dangerously-skip-permissions
sbx -- codex login --device-auth     # once per project
sbx -- codex
```

- Logins are **per project**, because `$HOME` is per project.
- Claude Code and Codex nest their own bubblewrap sandbox inside sbx. This works because
  sbx mounts an unmasked `/proc`.
- `~/.config/sbx/AGENTS.md` on the host, if present, is copied into each new project as the
  agents' user-level `CLAUDE.md` / `AGENTS.md`. Otherwise a one-line default is written.

Details, generated configs, telemetry and disk use: [docs/agents.md](docs/agents.md).

## Other software (e.g. ComfyUI)

sbx works for pretty much anything. For software that runs code you don't trust, install online
and then run offline, with only the web UI published:

```bash
sbx --offline --gpu --no-userns --ro ~/models --publish 8188 -- .venv/bin/python main.py
```

Full walkthrough, including LAN exposure: [docs/wsl2.md § 6](docs/wsl2.md#6-web-uis-with-untrusted-code-eg-comfyui).
The commands are the same on native Linux; skip the Windows firewall part.

## Threat model

There are two different cases, with different settings:

| | Coding agents | Untrusted software (ComfyUI custom nodes, random repos) |
|---|---|---|
| Code | trusted, from the vendor | potentially hostile |
| Risk | unpredictable *actions*: `rm -rf`, editing the wrong files, prompt-injected commands | deliberate escape, data theft, persistence |
| Network | needed (API), so online | `--offline`, with only `--publish` for the UI |
| Nested userns | needed for the agent's own sandbox | `--no-userns` |
| Typical run | `sbx -- claude` | `sbx --offline --no-userns --publish 8188 -- …` |

For agents, sbx limits the blast radius to the project directory. For hostile code, it raises
the bar a lot, but read the next section.

### What this does not protect against

- **Anything you run without `sbx`.** Only processes started through `sbx` (and their
  children) are sandboxed. Everything else runs with your full user rights, **including
  files created inside the sandbox**:
  - **Programs and scripts written in the project.** If you run `./build/app`, `python main.py`
    or `npm start` from a normal terminal, they are not sandboxed. Run them as
    `sbx -- ./build/app` instead.
  - **Files that other tools run automatically.** For example, git hooks in `.git/hooks` and
    settings in `.git/config` (`core.fsmonitor` runs a program on every `git status`),
    `.envrc` (direnv), `.vscode/tasks.json` / `settings.json`, `Makefile` and `package.json`
    scripts, a `.venv`'s `activate` script, and agent config such as the project's
    `.claude/settings.json` (hooks) and `.mcp.json`. Code inside the sandbox can write these, and
    they run outside the next time you use git, your editor or a shell in that folder. Review
    them before working on the project outside sbx, or open it in your editor's restricted
    mode (VS Code: Workspace Trust).
  - **On WSL:** Windows programs (`.exe`, `.bat`, `.ps1`, …) can't start inside sbx, but if
    you open one that sbx wrote from a normal WSL shell or from Explorer, it runs as a normal
    Windows program. The WSL distro itself can also read and write all of `C:`. See
    [docs/wsl2.md § What runs where](docs/wsl2.md#what-runs-where).
- **The project directory itself.** `rm -rf .` inside deletes your work. Use git, or
  snapshots.
- **Kernel and GPU-driver exploits.** This is a namespace boundary, not a VM. A kernel
  LPE, a user-namespace bug or a GPU-driver bug escapes it. `--gpu` exposes a large driver
  attack surface.
- **Anything over the network when online.** The online mode shares the host network: the
  internet, your LAN, and every service on the host's `127.0.0.1` (databases, dev servers,
  an unauthenticated Ollama). Only `--offline` has a hard network boundary.
- **JavaScript from web UIs.** A published UI's frontend runs in your browser, which is
  neither sandboxed nor offline. Malicious custom nodes can ship JS that sends out anything
  the page shows. Use a separate browser profile.
- **`--share-auth`.** It makes the host's `~/.claude.json` writable from inside. That file
  can define MCP servers, which later run *outside* the sandbox when you use `claude`
  normally. Only use it for agents you trust, never for untrusted software.
- **Reading system files in `/usr` and `/etc`.** The sandbox can't change them, but it can
  read them as your own user would. Files only root can read, like `/etc/shadow`, stay
  unreadable. The ordinary system config in `/etc` (hostname, `/etc/fstab`, installed
  software) is visible, which is normally harmless. It only matters if a secret was put in a
  file everyone can read, e.g. an API key in `/etc/environment`. Move such secrets
  elsewhere or make the file root-only (`sudo chmod 600`).
- **Resource exhaustion.** There are no CPU or RAM limits. Wrap it in
  `systemd-run --user --scope -p MemoryMax=32G sbx -- …` if needed.

## Compared to alternatives

| Tool | Difference |
|---|---|
| **firejail** | setuid-root, profile-based, home directory visible by default; large policy surface. sbx is unprivileged and default-deny: home is invisible, only `$PWD` is writable. |
| **Anthropic sandbox runtime** (`srt`, used by Claude Code) | Sandboxes *each command* an agent runs, with a domain allowlist proxy. sbx sandboxes the *whole agent process* (including its config, MCP servers and login), and nests `srt`-style sandboxes inside. Use both. |
| **bubblejail / flatpak** | Desktop-app oriented, with persistent per-app profiles. sbx is per-directory and one command. |
| **Docker / Podman / devcontainers** | Separate userland image, overlay storage, ~1 s startup, the CUDA stack reproduced inside. sbx reuses the host `/usr` read-only, so the toolchain is already correct. |
| **VM / microVM** | Much stronger boundary (kernel exploits) at the cost of images, boot time and GPU passthrough. Use one for fully hostile code. |
| **This Project** | Significantly lower overhead than Docker, Podman and VM solutions: no image, no daemon, no root, and the host's own tools. Easier than firejail profiles or a hand-written bwrap command, and very quick to set up and use: install one script, `cd` into a project, run `sbx`. The trade-off is a weaker boundary than a VM, and the host's `/usr` and `/etc` stay readable. |

## Status

Provided as-is. Issues and PRs are welcome, but there is no support commitment.

Written with AI assistance; tested by me on CachyOS and Ubuntu 24.04/Arch under WSL2.

The tools sbx can download and run (Claude Code, Codex, pi) are third-party software
under their own licenses and terms. sbx only installs them into your project.

## License

MIT, see [LICENSE](LICENSE).
