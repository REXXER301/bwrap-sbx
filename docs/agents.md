# Coding agents under `sbx`

All three agents follow the same contract. The first `sbx -- <agent>` run **with the network
on** installs the agent into the project's `.sbx-home` and writes a minimal config. Every
file is only created if absent, so edit freely; sbx never overwrites. Delete `.sbx-home` to
start over.

## Agent instructions (CLAUDE.md / AGENTS.md)

Inside the sandbox, `$HOME` is `.sbx-home`, so that is where Claude Code and Codex look for
their user-level instructions: `.sbx-home/.claude/CLAUDE.md` and `.sbx-home/.codex/AGENTS.md`.

On first run sbx fills them from **`~/.config/sbx/AGENTS.md` on the host** (or
`$XDG_CONFIG_HOME/sbx/AGENTS.md`), if that file exists. Put your personal preferences there
once, e.g.:

```
Using Fish Konsole.
Prefer ls -1 over ls if applicable.
```

Without it, sbx writes a one-line default that names the shell and says only the project
directory is writable. A project-level `CLAUDE.md` / `AGENTS.md` in the project still layers
on top as usual.

## Telemetry: off by default

sbx turns off telemetry, error reporting and feedback prompts for every command it runs.
Auto-updates stay on, so per-project installs keep updating.

| Tool | How |
|---|---|
| Claude Code | env: `DISABLE_TELEMETRY`, `DISABLE_ERROR_REPORTING`, `DISABLE_FEEDBACK_COMMAND` (also `/bug`, `/share`), `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` |
| Codex | `.sbx-home/.codex/config.toml`: `analytics.enabled = false` (also stops its Statsig metrics exporter), `feedback.enabled = false` |
| pi | env: `PI_OFFLINE=1`, `PI_TELEMETRY=0`, `PI_SKIP_VERSION_CHECK=1`; settings.json: `enableInstallTelemetry: false` |
| Other tools | env: `DO_NOT_TRACK=1` (cross-tool convention), `HF_HUB_DISABLE_TELEMETRY=1`, `GRADIO_ANALYTICS_ENABLED=False`, `NEXT_TELEMETRY_DISABLED=1`, `DOTNET_CLI_TELEMETRY_OPTOUT=1` |

The environment variables are set on every run, so they also apply to existing projects. The
Codex `config.toml` is only written if absent, like every other generated file.

**Side effect in Claude Code:** `DISABLE_TELEMETRY` also turns off feature-flag fetching, so
features that depend on it, such as Remote Control, aren't available.

`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` isn't used, because it also turns off
auto-updates, release notes and status checks. Add it yourself in
`.sbx-home/.claude/settings.json` (`{ "env": { "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1" } }`)
if you want those gone too.

**To allow telemetry:** run `SBX_TELEMETRY=1 sbx -- …`. That skips all of the environment variables
above and won't write the Codex config. A Codex config that's already there stays as it is.
Removing single variables with `SBX_ENV` doesn't work: Claude Code's `DISABLE_*` variables opt out
whenever they're set, even to `0`.

## pi

```bash
sbx -- pi          # installs + configures + launches
```

What the first run does, only for whatever is missing:

1. `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` with the npm prefix set to
   `.sbx-home/.npm-global` (upstream uses `--ignore-scripts` for its own installs too).
2. Queries `http://127.0.0.1:8001/v1/models` and `/props` for the real model id and
   `n_ctx`, then writes `.sbx-home/.pi/agent/models.json` for the `llama-cpp` provider.
3. Writes `.sbx-home/.pi/agent/settings.json` with `defaultProvider` / `defaultModel`, so plain
   `pi` picks the local model with no flags.

Requirements: `nodejs` and `npm` on the host (`/usr` is shared read-only, so pi runs on the host
Node). Offline runs need the install to have happened once online; `sbx --offline -- pi` on a
fresh project exits with a hint rather than failing halfway.

Both modes present the model at the same address, so the config never changes:

```
OPENAI_BASE_URL=http://127.0.0.1:8001/v1
OPENAI_API_KEY=sbx
```

**Port:** default is `8001`. Override per run with `--port 8080`, or change `port=8001` near
the top of the script.

**Telemetry:** off by default ([see above](#telemetry-off-by-default)). Pi otherwise makes two
startup calls, a version check and an anonymous install ping to pi.dev. `PI_OFFLINE` is
unrelated to `sbx --offline`: it only stops pi phoning pi.dev. It also stops pi's update
notices, so run `sbx -- pi update --self` to update by hand.

### Generated config

```json
{
  "providers": {
    "llama-cpp": {
      "baseUrl": "http://127.0.0.1:8001/v1",
      "api": "openai-completions",
      "apiKey": "none",
      "compat": { "supportsDeveloperRole": false },
      "models": [
        {
          "id": "<detected from /v1/models>",
          "name": "local (llama.cpp)",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": "<detected from /props>",
          "maxTokens": "<n_ctx / 4, capped at 32768>",
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

- `apiKey` is a placeholder: pi hides models from `/model` unless the provider looks
  authenticated, so keyless local servers need a dummy value.
- `supportsDeveloperRole: false` is preset because some OpenAI-compatible servers reject the
  `developer` role pi uses for reasoning models; without it the system prompt can be dropped.
- `contextWindow` is detected rather than defaulted, because pi silently runs unlisted models at
  128K. A mismatch with your `llama-server -c` value causes truncation surprises mid-session.
- pi re-reads models.json every time you open `/model`, so edits apply without a restart.

`npm warn deprecated node-domexception@1.0.0` during install is harmless.

## Claude Code

```bash
sbx -- claude     # installs + configures + launches
```

The first run resolves `claude` in this order, stopping at the first hit:

1. `--host-claude` was passed: the host's binary is bound read-only at
   `/opt/claude/bin/claude`, with auto-update off (`DISABLE_AUTOUPDATER=1`).
2. The host has a system-wide install under `/usr`: it's already inside.
3. `.sbx-home/.local/bin/claude` exists: use it.
4. Otherwise run `curl -fsSL https://claude.ai/install.sh | bash` *inside* the sandbox,
   which lands in `.sbx-home/.local/`.

The native installer is used because it ships a self-contained binary (no Node, ripgrep
bundled) that auto-updates in place inside the project. It takes about 150 MB per project; with
many projects, `--host-claude` installs nothing. The npm package works too (Node 22+). Don't add
`--ignore-scripts` to it, since it links its binary in a postinstall step:

```bash
sbx -- bash -c 'npm config set prefix $HOME/.npm-global && npm install -g @anthropic-ai/claude-code'
```

### Login

A fresh project has no credentials, so `claude` starts its login flow. It prints a URL; open it
on the host and paste the code back. Two ways to skip that:

- `ANTHROPIC_API_KEY`: passed through with `SBX_ENV="ANTHROPIC_API_KEY" sbx -- claude`
  (Console billing, not a subscription). Like everything else in the environment, it is not
  passed by default.
- `--share-auth`: binds the host's `~/.claude.json` and `~/.claude/.credentials.json` read-write,
  so one subscription login covers every project. The agent can then read your token and
  **write `~/.claude.json`, which can define MCP servers that run outside the sandbox.** sbx
  prints a warning each time. Without the flag the token stays in `.sbx-home/.claude/`, which
  sbx keeps out of git with a `.sbx-home/.gitignore`.

### The inner sandbox

Claude Code sandboxes its Bash commands with bubblewrap, so under sbx that's bwrap inside bwrap.
It works because sbx mounts `/proc` without masking any of it. The kernel's "fully visible
procfs" rule is what nested unprivileged proc mounts hinge on, and Docker-style masking of
`/proc/acpi` and friends is what usually breaks them. The generated
`.sbx-home/.claude/settings.json` just turns it on:

```json
{
  "sandbox": {
    "enabled": true
  }
}
```

If a kernel or policy change ever breaks nesting, you'll see a `bwrap` error like
`Can't mount proc on /newroot/proc: Operation not permitted`, and Claude Code falls back to
unsandboxed commands with a warning. `"enableWeakerNestedSandbox": true` restores it by binding
sbx's `/proc` instead, which is acceptable because the outer boundary is still there. Or set
`"enabled": false` and rely on sbx alone, e.g. with `--dangerously-skip-permissions`.

### GPU and telemetry

`--gpu` does nothing for Claude Code itself, which runs on Anthropic's servers. It's for what the
agent runs: training scripts, CUDA builds, a local model.

Telemetry, error reporting and feedback surveys are off by default and auto-update stays on; see
[Telemetry](#telemetry-off-by-default).

### Network

Claude Code is an online agent, so sbx rejects `--offline` for it. It always runs with no network
boundary: internet, LAN, and anything on the host's loopback. Its own sandbox adds a domain
allowlist for Bash commands, but that's a policy inside the process, not a namespace. Because the
online mode shares the host netns, the proxy that enforces it listens on the host's loopback.

## Codex

```bash
sbx -- codex login --device-auth   # once per project: open the URL, enter the code
sbx -- codex
```

Installed into `.sbx-home/.npm-global` (needs npm on the host). Login, config and history live in
`.sbx-home/.codex`, per project.

- **API key instead of a ChatGPT login:** run `SBX_ENV="OPENAI_API_KEY" sbx -- codex`. Without
  that, sbx deliberately removes `OPENAI_API_KEY` and `OPENAI_BASE_URL` for Codex. They point
  pi at the local llama.cpp, and Codex would otherwise follow them there.
- **Inner sandbox:** Codex also nests bubblewrap. If it reports a sandbox error, run
  `sbx -- codex --sandbox danger-full-access`, and sbx remains the boundary.
- **No `--offline`:** Codex needs OpenAI's API.
- **Telemetry:** the first run writes `.sbx-home/.codex/config.toml` with analytics and feedback
  off ([see above](#telemetry-off-by-default)). Add your own Codex settings to that file.
