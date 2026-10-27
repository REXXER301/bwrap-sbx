# `sbx` on Windows: quick start

Double-click `quickstart.cmd`, or run `.\quickstart.cmd` in a terminal. It:

1. Installs or updates WSL, without a default Ubuntu. This needs one admin prompt. If
   Windows then needs a restart, the script says so: restart and run it again.
2. Creates a separate WSL distro named `sbx` (Ubuntu 24.04). Your other distros are left
   alone.
3. Installs bubblewrap, socat, git, Node and `sbx`, and creates a Linux user without a password.
4. Checks that the sandbox works and can't start Windows programs. If it can, the script turns
   off WSL interop for this distro.

Then:

```powershell
wsl -d sbx
```
```bash
cd ~/projects/hello
sbx -- claude
```

The script ends with warnings about what the sandbox does and doesn't protect against. Read
them.

- **Update:** run the script again.
- **Remove:** `wsl --unregister sbx`. This deletes everything inside the distro, including
  your projects in it.
- **Options:** `quickstart.cmd -Distro <name> -Image <wsl distro>`

For manual setup and verification steps, see [docs/wsl2.md](../docs/wsl2.md).
