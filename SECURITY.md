# Security policy

sbx is a namespace sandbox, not a VM, and it is not a security guarantee. The
[threat model](README.md#threat-model) lists what it does and does not protect against.

## Reporting a vulnerability

If you find a way out of the sandbox, a mount or path that is visible or writable when it
shouldn't be, or anything else that breaks a promise the README makes, please report it
privately through GitHub's [private vulnerability reporting](https://github.com/REXXER301/bwrap-sbx/security/advisories/new) rather than in a public issue.

Please include the sbx version or commit, your distro and kernel (`uname -r`), the
bubblewrap version (`bwrap --version`), and the steps to reproduce.

Issues that the threat model already lists as out of scope (for example kernel or
GPU-driver exploits, or code run outside `sbx`) are known limitations. Public issues are
fine for those.

This is a hobby project without a support commitment. I'll respond as soon as I can.


## Not sure where it belongs?

sbx is a wrapper around [bubblewrap](https://github.com/containers/bubblewrap) and the kernel's namespaces. 
If you're not sure whether an issue is in sbx, bubblewrap or the kernel, 
report it here and I'll forward it upstream if needed. If you know it's a bug in
bubblewrap itself (it also affects plain `bwrap` without sbx), report it through
[bubblewrap's security policy](https://github.com/containers/bubblewrap/security/policy).