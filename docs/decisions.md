# Decisions

Short notes on choices that aren't obvious from the code.

## Auth and re

## Install

- **No installer script for Linux distros.** The dependencies are a few stable packages; a
  copy-paste block in the docs shows exactly what gets installed and needs no per-distro
  code. `sbx` checks for what it needs at runtime and says what's missing.
- **Windows gets a quick start script** (`windows/`), because it targets people new to
  WSL and Linux.

## Windows quick start

- **Own distro named `sbx`.** WSL is installed with `--no-distribution`, so there's no
  default Ubuntu. Ubuntu is only installed under that name, and existing distros are left
  alone.
- **No auto-start after a restart.** If WSL needs a restart, the script says so and the
  user runs it again. An autostart entry can show up at an unexpected login and looks
  like malware to antivirus software.
- **Linux user without password or sudo.** The login is locked, not empty. A WSL password
  wouldn't protect anything: the Windows user can always run `wsl -u root`, and `sudo`
  doesn't work inside the sandbox. Without sudo, programs running outside the sandbox
  can't become root through a guessed password.
- **Interop is turned off if the sandbox can start Windows programs.** The script tests
  this with `whoami.exe`. The distro exists only for sbx, so losing `code .` there is
  acceptable.
- **Re-running the script updates everything.** Each step checks what's already done.

## Claude Code login

- **One login per project, no shared host login.** The session lives in `.sbx-home` and
  refreshes itself, so it's one browser login per project, once. Sharing the host login
  would make `~/.claude.json` writable from inside, and the host's `claude` runs the MCP
  servers listed there outside the sandbox.
- **No partial copy of the host config.** Binding only the token file still shows the
  login screen. Skipping it means copying fields or setting undocumented flags, which can
  break with any update.
- **No sandbox home shared between projects.** One login would cover all projects, but a
  project could plant an MCP server that runs in every other project's sandbox.
- **API keys stay opt-in.** `SBX_ENV="ANTHROPIC_API_KEY"` avoids the login, but it's
  billed per token and every sandbox sees the same key.