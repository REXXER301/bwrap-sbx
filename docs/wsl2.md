# `sbx` on WSL2 — quick install

Runs `sbx` inside a WSL2 distro on Windows 11. It's the same script as on native Linux;
it detects WSL by itself. The guarantee is the same as on Linux: only `$PWD` is writable inside the
sandbox. Your Windows drives (`/mnt/c`, …) don't exist in there at all.

> **Note:** Only processes started through `sbx` are confined. If you start a process
> without this prefix, it is **not** sandboxed, and the WSL distro itself can read and write
> all of `C:`. That includes programs the sandbox created (see [What runs where](#what-runs-where)).

---

## 1. WSL2 + distro (PowerShell)

```powershell
wsl --install -d Ubuntu-24.04      # or: wsl --install archlinux
wsl --set-default-version 2
wsl -l -v                          # VERSION column must say 2
```

Optional but recommended, in `%UserProfile%\.wslconfig` (then `wsl --shutdown`):

```ini
[wsl2]
memory=32GB                 # cap the VM
networkingMode=mirrored     # makes a Windows-side llama.cpp reachable on 127.0.0.1

[experimental]
autoMemoryReclaim=gradual   # hand page cache back to Windows
```

## 2. Packages (inside WSL)

```bash
# Ubuntu
sudo apt update
sudo apt install -y bubblewrap socat curl git nodejs npm

# Arch
sudo pacman -S --needed bubblewrap socat curl git nodejs npm
```

`socat` is only needed for `--offline`. `nodejs`/`npm` are only needed for pi and Codex. Ubuntu's
packaged Node may be too old for pi; if so, install a current one via `fnm` or NodeSource.
`sbx -- claude` uses the native installer and needs no Node at all.

## 3. Install the script

```bash
mkdir -p ~/.local/bin
cp /mnt/c/Users/<you>/Downloads/sbx ~/.local/bin/sbx   # adjust path, or git clone in WSL
chmod 755 ~/.local/bin/sbx
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

The script already handles everything WSL needs, so there's nothing to patch:

- `/lib64` and `/sbin` point at `usr/lib64` and `usr/sbin`, which works on Ubuntu and Arch.
- DNS works even though WSL's `/etc/resolv.conf` is a symlink into hidden paths.
- `--gpu` exposes `/dev/dxg` and puts `/usr/lib/wsl/lib` (with `nvidia-smi`) on `PATH`.
- The interactive shell is your login shell (bash by default on Ubuntu).
- The environment is cleared (`--clearenv`). Only `TERM`, `LANG` and `COLORTERM` are
  passed through. Pass more, API keys included, with `SBX_ENV`, e.g.
  `SBX_ENV="HF_TOKEN" sbx -- pi`.
- It refuses to run in, or `--ro` share, `/`, `/tmp`, or your home directory and its
  parents, and warns if the project is on a Windows drive.

## 4. Verify (once)

```bash
mkdir -p ~/projects/foo && cd ~/projects/foo
sbx -- ls -1 /                                  # minimal tree: bin dev etc home … usr var
sbx -- ls /mnt                                  # absent, or only "wsl" (holds resolv.conf) — no c, d, …
sbx -- touch /etc/passwd                        # "Permission denied" — not writable
sbx -- ls -1 ..                                 # only your project folder
sbx -- env                                      # only the variables the script sets
sbx -- curl -sI https://example.com | head -1   # DNS works
sbx --offline -- curl -sm3 https://example.com  # fails, no route
sbx --offline -- curl -sm3 127.0.0.1:8001/health
sbx --gpu -- nvidia-smi                         # GPU visible
```

Nested bubblewrap check, needed for Claude Code's own sandbox. Expect `0`:

```bash
sbx -- bwrap --unshare-all --proc /proc --dev /dev \
  --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 \
  --symlink usr/bin /bin -- /bin/true; echo $?
```

### Windows interop test

WSL can launch Windows `.exe` files through a kernel-wide handler, and that handler is
not removed by the sandbox's mounts. The sandbox hides the interop socket, so this
*should* fail, but confirm it:

```bash
cat /proc/sys/fs/binfmt_misc/WSLInterop        # shows the handler and its flags
cd ~/projects/foo
cp /mnt/c/Windows/System32/whoami.exe .
sbx -- ./whoami.exe; echo "exit: $?"            # expect an error and a non-zero exit
rm whoami.exe
```

- **It fails:** nothing to do. Keep interop on, so `code .` and `explorer.exe .` keep
  working in normal WSL shells.
- **It prints your Windows user name:** the sandbox can start Windows programs. Disable
  interop in `/etc/wsl.conf`, then run `wsl --shutdown` in PowerShell and reopen the distro.
  This also breaks `code .` from WSL; open the folder from VS Code's WSL extension instead.

  ```ini
  [interop]
  enabled=false
  ```

### What runs where

WSL starts Windows programs through that kernel-wide handler: when you run a Windows `.exe`
file, the handler passes it to WSL, which asks Windows to start it over a socket under
`/run/WSL` (`$WSL_INTEROP`). sbx replaces `/run` with an empty tmpfs and clears the
environment, so inside the sandbox that socket isn't there and the start fails. That's what
the test above confirms.

Outside sbx nothing stops it, and a Windows program started this way **isn't inside WSL at
all**. It's a normal Windows process with your Windows account's full rights: every drive, the
network, the registry, your browser profiles.

| File in the project | Inside `sbx` | Normal WSL shell | Windows (Explorer, PowerShell) |
|---|---|---|---|
| Linux programs and scripts | sandboxed | runs with your WSL user's rights, including `/mnt/c` and starting Windows programs | can't run them directly; `wsl.exe …` runs them in WSL, unsandboxed |
| Windows programs: `.exe`, `.bat`, `.cmd`, `.ps1`, `.msi` | won't start | run as normal Windows programs | run as normal Windows programs |
| Files that run when opened on Windows: `.lnk`, `.js`, `.vbs`, `.hta`, Office files with macros | can't be opened | opened in their Windows app (`explorer.exe file`, `cmd.exe /c file`) | run or open when double-clicked |

What this means in practice:

- **Files from the WSL filesystem usually get no SmartScreen warning.** Windows adds a
  "downloaded from the internet" mark to files from a browser, but not to files created inside
  WSL. Double-clicking an `.exe` an agent built in `\\wsl$\…` runs it without a prompt.
- **Windows builds can't be tested inside sbx.** If an agent cross-compiles a Windows app,
  running it means trusting it like any program from the internet. For untrusted builds, use
  Windows Sandbox (Windows Pro/Enterprise) or a VM.
- **Don't add `/mnt/c` with `--ro` for convenience.** Reading `C:` only lets code read files,
  not run them as Windows programs, but it exposes everything on that drive.

## 5. Use

```bash
cd ~/projects/foo
sbx                         # interactive bash, prompt shows (sbx)
sbx -- claude
sbx -- codex
sbx --gpu -- pi
sbx --offline -- pi
```

Login URLs (Claude Code, `codex login --device-auth`) are opened in the Windows browser; paste
the code back. Everything about the agents is in [agents.md](agents.md); the Codex points below
are repeated here because they come up most on WSL.

### Codex

```bash
cd ~/projects/foo
sbx -- codex login --device-auth   # once per project: open the URL on Windows, enter the code
sbx -- codex
```

- **API key instead of a ChatGPT login:** `export OPENAI_API_KEY=...` in WSL, then run
  `SBX_ENV="OPENAI_API_KEY" sbx -- codex`. Without `SBX_ENV`, the script deliberately
  removes `OPENAI_API_KEY` and `OPENAI_BASE_URL` for Codex. Those two variables point pi at
  your local llama.cpp, and Codex would otherwise follow them there.
- **Instructions file:** `.sbx-home/.codex/AGENTS.md` is written on first run, from
  `~/.config/sbx/AGENTS.md` if you have one. Edit or delete it freely; the script won't overwrite it.
- **Inner sandbox:** Codex sandboxes its own commands with bubblewrap, nested inside sbx just
  like Claude Code, so the nesting check in step 4 applies. If Codex ever reports a sandbox
  error, run it without its inner sandbox — sbx remains the boundary:
  `sbx -- codex --sandbox danger-full-access`.
- **No `--offline`:** Codex needs OpenAI's API, so the script rejects `--offline` for it.

## 6. Web UIs with untrusted code (e.g. ComfyUI)

For software that runs code you don't trust, such as ComfyUI custom nodes, the strongest
local setup is **offline**. The sandbox has no network at all, and `--publish` lets
connections *in* to one port:

| Option | Effect |
|---|---|
| `--publish 8188` | Sandbox port 8188 reachable at `127.0.0.1:8188` (and from Windows' browser) |
| `--publish 0.0.0.0:8188` | Reachable from the LAN too (needs the firewall rule below) |
| `--allow 192.168.1.0/24` | Only these clients may connect to published ports |
| `--ro ~/models` | Host folder shared read-only at the same path (repeatable) |
| `--no-userns` | Code inside can't create nested sandboxes — removes a common kernel attack surface |

Connections can only be opened from outside, so code inside can answer requests but can't
reach the internet, your LAN, or other local services. `--publish` requires `--offline`.

### Install (online, once)

```bash
mkdir -p ~/models ~/projects/comfy && cd ~/projects/comfy
sbx -- git clone https://github.com/comfyanonymous/ComfyUI.git .
sbx -- python3 -m venv .venv          # Ubuntu: sudo apt install python3-venv first
sbx --gpu -- .venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
sbx -- .venv/bin/pip install -r requirements.txt
```

Point ComfyUI at the shared model folder in `extra_model_paths.yaml`, using the real path
(e.g. `/home/<you>/models`). Download models into `~/models` from a normal WSL shell, outside
the sandbox.

### Run (offline)

```bash
cd ~/projects/comfy
sbx --offline --gpu --no-userns --ro ~/models --publish 8188 -- .venv/bin/python main.py
```

Open `http://127.0.0.1:8188` in Windows. Keep ComfyUI's own default of listening on
`127.0.0.1`: that's the sandbox's private loopback, which only the bridge can reach.

### Expose to the LAN

```bash
sbx --offline --gpu --no-userns --ro ~/models \
    --publish 0.0.0.0:8188 --allow 192.168.1.0/24 -- .venv/bin/python main.py
```

This needs `networkingMode=mirrored` (step 1) and an inbound rule for WSL in Windows'
Hyper-V firewall. Run once in an elevated PowerShell:

```powershell
New-NetFirewallHyperVRule -Name ComfyUI-8188 -DisplayName "ComfyUI 8188" -Direction Inbound `
  -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 8188
```

Then browse to `http://<your-PC's-LAN-IP>:8188` from another device. ComfyUI has no login,
so anyone who can connect can queue workflows. Always set `--allow`.

### Rules for untrusted workflows

- **Install in online runs, run untrusted workflows offline.** Don't let a workflow
  auto-install missing nodes. Look each one up first, prefer known authors, and pin versions.
- **`.safetensors` only.** `.ckpt`, `.pt` and `.bin` files can run code when loaded.
- **Use a separate browser profile for the UI.** Custom nodes can ship JavaScript that runs
  in your browser, which isn't sandboxed and does have internet access. That code could send
  out anything the UI shows it.
- **Fully hostile workflows** (unknown nodes from unknown sources): use a disposable cloud
  GPU instead. The remaining risk here is a kernel or GPU-driver exploit, which would escape
  into WSL and from there reach `C:`.

See the [README](../README.md#what-this-does-not-protect-against) for the full list of what
sbx doesn't protect against.

Avoid `--share-auth`. It makes `~/.claude.json` writable, and that file can hold MCP
server definitions that run outside the sandbox; the script prints a warning when you
use it. Log in per project, or `export ANTHROPIC_API_KEY=...` in WSL and run
`SBX_ENV="ANTHROPIC_API_KEY" sbx -- claude`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `bwrap: setting up uid map: Permission denied` | Unprivileged userns blocked (Ubuntu AppArmor). Run `sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0` and persist it in `/etc/sysctl.d/`. |
| `Could not resolve host` | `wsl --shutdown` after changing `networkingMode`, then retry. Check what `readlink -f /etc/resolv.conf` points to. |
| llama.cpp on Windows unreachable | Use `networkingMode=mirrored`, or run llama.cpp inside WSL. |
| `--gpu: no /dev/dxg …` / `nvidia-smi` not found | Install the NVIDIA driver on the **Windows** side only; never install a Linux driver inside WSL. |
| A tool misses an environment variable | Pass it with `SBX_ENV="NAME"`. |
| Published port: "connection refused" | The program inside must listen on `127.0.0.1:<port>` (ComfyUI's default). |
| Published port works locally but not from the LAN | `networkingMode=mirrored` set? Hyper-V firewall rule added? Client inside `--allow`? |
| `--no-userns needs bubblewrap 0.8` | Update bubblewrap, or drop the flag. |
| Codex says it's not logged in | Logins are per project: `sbx -- codex login --device-auth` in this project. |
| Orphaned `socat` after a hard kill | `pkill -f sbx-llama` |
| Slow `git status`, `npm install` etc. | The project is on a Windows drive (`/mnt/c/...`), which WSL reaches through a slow file-sharing bridge. sbx works there, just slower. Moving the project into the WSL filesystem (e.g. `~/foo`) makes it fast; Windows can still open it at `\\wsl$\<distro>\home\<you>`. |
| No btrfs snapshots | Commit often, or back up the whole distro: `wsl --export <distro> backup.tar` |
