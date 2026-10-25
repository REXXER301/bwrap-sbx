# Security policy

sbx is a namespace sandbox, not a VM, and it is not a security guarantee. The
[threat model](README.md#threat-model) lists what it does and does not protect against.

## Reporting a vulnerability

If you find a way out of the sandbox, a mount or path that is visible or writable when it
shouldn't be, or anything else that breaks a promise the README makes, please report it
privately through GitHub's
[private vulnerability reporting](https://github.com/REXXER301/bwrap-sbx/security/advisories/new)
rather than in a public issue.

Please include the sbx version or commit, your distro and kernel (`uname -r`), the
bubblewrap version (`bwrap --version`), and the steps to reproduce.

Issues that the threat model already lists as out of scope (for example kernel or
GPU-driver exploits, or code run outside `sbx`) are known limitations. Public issues are
fine for those.

This is a hobby project without a support commitment. I'll respond as soon as I can.
