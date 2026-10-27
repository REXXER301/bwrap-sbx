# sbx quick start for Windows. Sets up a separate WSL distro (default name "sbx")
# with bubblewrap, socat, git, Node and the sbx script, then checks that the
# sandbox works. Existing distros are left alone. Safe to re-run: it updates
# the packages and the sbx script.
#
#   quickstart.cmd                         double-click, or run from a terminal
#   quickstart.ps1 [-Distro sbx] [-Image Ubuntu-24.04]

param(
    [string]$Distro = 'sbx',
    [string]$Image = 'Ubuntu-24.04'
)

$env:WSL_UTF8 = '1'                                  # wsl.exe prints UTF-16 otherwise
[Console]::OutputEncoding = [Text.Encoding]::UTF8
# sbx sits next to this script in a release zip, one folder up in a git checkout.
$repoSbx = @((Join-Path $PSScriptRoot 'sbx'), (Join-Path (Split-Path $PSScriptRoot -Parent) 'sbx')) |
    Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
$rawSbx = 'https://raw.githubusercontent.com/REXXER301/bwrap-sbx/main/sbx'

function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Warn([string]$msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Fail([string]$msg) { Write-Host "`nsbx quickstart: $msg" -ForegroundColor Red; exit 1 }

# Runs a bash script inside the distro and passes its stdout through. Base64
# keeps PowerShell's and wsl.exe's quoting out of the way; process substitution
# leaves stdin alone for the commands in the script.
function Invoke-Bash([string]$script, [switch]$AsRoot) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($script -replace "`r", '')))
    $as = @()
    if ($AsRoot) { $as = @('-u', 'root') }
    & wsl.exe -d $Distro @as --cd '~' -e bash -c "bash <(echo $b64 | base64 -d)"
}

# --- 1. WSL itself -----------------------------------------------------------

Step 'Checking WSL'
if ([Environment]::OSVersion.Version.Build -lt 19041) {
    Fail 'WSL2 needs Windows 10 version 2004 (build 19041) or later, or Windows 11.'
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail 'wsl.exe not found. Update Windows, then run this script again.'
}

# The inbox wsl.exe of a system without WSL doesn't know --version.
& wsl.exe --version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'WSL is not installed yet. Installing it; Windows will ask for admin rights.'
    # --no-distribution: only WSL itself, no default Ubuntu. The only distro this
    # script installs is its own, by name, in step 2. The admin window stays
    # open if the install fails, so its error can be read.
    try {
        Start-Process cmd.exe -ArgumentList '/c', 'wsl.exe --install --no-distribution || pause' -Verb RunAs -Wait
    } catch {
        Fail 'WSL install was cancelled.'
    }
    & wsl.exe --version *> $null
    if ($LASTEXITCODE -ne 0) {
        Warn 'WSL is installed but needs a restart. Restart Windows, then run quickstart.cmd again.'
        Warn 'If you see this again after restarting, run "wsl --install --no-distribution"'
        Warn '  in an admin terminal to see why the WSL install fails.'
        exit 0
    }
} else {
    # All distros share one WSL kernel, and bubblewrap relies on it.
    & wsl.exe --update
}

# --- 2. The distro -----------------------------------------------------------

$installed = & wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim() }
if ($installed -contains $Distro) {
    Step "Distro '$Distro' already exists, updating it"
} else {
    Step "Installing $Image as a new WSL distro named '$Distro'"
    & wsl.exe --install $Image --name $Distro --no-launch
    if ($LASTEXITCODE -ne 0) { Fail "could not install $Image. Run 'wsl --update' and try again." }
}

# --- 3. Packages, sbx, user --------------------------------------------------

# The Linux user is named after the Windows user, if that makes a valid name.
$user = $env:USERNAME.ToLower() -replace '[^a-z0-9_-]', ''
if ($user -notmatch '^[a-z_][a-z0-9_-]{0,30}$' -or $user -eq 'root') { $user = 'sbx' }

$src = ''
if ($repoSbx) {
    $src = (& wsl.exe -d $Distro -e wslpath -a ($repoSbx -replace '\\', '/')) -join ''
}

Step 'Installing packages and sbx (this takes a few minutes the first time)'
$provision = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
u='@USER@'
src='@SRC@'

# nodejs and npm are in universe, which some images leave out.
f=/etc/apt/sources.list.d/ubuntu.sources
[ -f "$f" ] && sed -i -E '/^Components:/{/universe/!s/$/ universe/}' "$f"

apt-get update
apt-get install -y --no-install-recommends bubblewrap socat curl git ca-certificates nodejs npm
apt-get upgrade -y

# A Windows checkout may have CRLF line endings, which bash can't run.
if [ -n "$src" ] && [ -f "$src" ]; then
    tr -d '\r' < "$src" > /usr/local/bin/sbx
else
    curl -fsSL '@URL@' -o /usr/local/bin/sbx
fi
chmod 755 /usr/local/bin/sbx

# Fall back to "sbx" if the name belongs to a system account (games, news, ...).
if id "$u" >/dev/null 2>&1 && [ "$(id -u "$u")" -lt 1000 ]; then u=sbx; fi
# No password and no sudo: admin work goes through 'wsl -d <distro> -u root'.
id "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
touch /etc/wsl.conf
grep -q '^\[user\]' /etc/wsl.conf || printf '\n[user]\ndefault=%s\n' "$u" >> /etc/wsl.conf
echo "USER=$(sed -n '/^\[user\]/,/^\[/s/^default=//p' /etc/wsl.conf)"
'@
$provision = $provision.Replace('@USER@', $user).Replace('@SRC@', ($src -replace "'", "'\''")).Replace('@URL@', $rawSbx)
Invoke-Bash $provision -AsRoot | Tee-Object -Variable lines | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'package or sbx installation failed, see the output above.' }
$userLine = $lines | Where-Object { $_ -like 'USER=*' } | Select-Object -Last 1
if ($userLine) { $user = $userLine.Substring(5) }
& wsl.exe --terminate $Distro | Out-Null          # apply /etc/wsl.conf

# --- 4. Check the sandbox ----------------------------------------------------

# Runs as the normal user. WSL starts Windows .exe files through a kernel-wide
# handler; the sandbox should block that, but this checks it.
$verify = @'
mkdir -p ~/projects/hello && cd ~/projects/hello || exit 1
sbx -- true || { echo SBX_BROKEN; exit 0; }
cp /mnt/c/Windows/System32/whoami.exe . 2>/dev/null || { echo INTEROP_UNKNOWN; exit 0; }
if sbx -- ./whoami.exe >/dev/null 2>&1; then echo INTEROP_OPEN; else echo INTEROP_BLOCKED; fi
rm -f whoami.exe
'@

Step 'Checking that the sandbox works'
$result = Invoke-Bash $verify
$interopDisabled = $false
if ($result -contains 'SBX_BROKEN') {
    Fail "sbx doesn't start in this distro. Open it with 'wsl -d $Distro', run 'cd ~/projects/hello; sbx -- true' and see docs/wsl2.md."
}
if ($result -contains 'INTEROP_OPEN') {
    Warn 'Code inside the sandbox could start Windows programs. Turning off WSL interop for this distro.'
    Invoke-Bash "grep -q '^\[interop\]' /etc/wsl.conf || printf '\n[interop]\nenabled=false\n' >> /etc/wsl.conf" -AsRoot | Out-Host
    & wsl.exe --terminate $Distro | Out-Null
    $interopDisabled = $true
    $result = Invoke-Bash $verify
}

# --- 5. Done -----------------------------------------------------------------

Write-Host "`nDone. Open the sandbox distro with:" -ForegroundColor Green
Write-Host "    wsl -d $Distro              (or pick '$Distro' in Windows Terminal)"
Write-Host 'Then, inside it:'
Write-Host '    cd ~/projects/hello'
Write-Host '    sbx -- claude              (or: sbx for a sandboxed shell, sbx --help)'

Write-Host "`nRead before use:" -ForegroundColor Yellow
if ($result -contains 'INTEROP_OPEN') {
    Write-Host '  ! Code inside the sandbox can still start Windows programs. Do not use it' -ForegroundColor Red
    Write-Host '    until this is fixed; see "Windows interop test" in docs/wsl2.md.' -ForegroundColor Red
} elseif ($result -contains 'INTEROP_UNKNOWN') {
    Warn 'Could not test whether the sandbox can start Windows programs. See "Windows interop test" in docs/wsl2.md.'
}
Warn 'sbx is a sandbox, not a VM, and comes with no guarantee. See SECURITY.md and'
Warn '  "What this does not protect against" in the README.'
Warn 'Only commands started with "sbx" are sandboxed. Everything else in this distro,'
Warn "  including a plain 'claude', can read and write all of C: through /mnt/c."
Warn 'Keep projects inside Linux (~/projects/...). Under /mnt/c they work, but slowly.'
Warn "The Linux user '$user' has no password (login is locked) and no sudo."
Warn "  For admin tasks: wsl -d $Distro -u root"
Warn 'Run this script again to update packages and sbx. The WSL kernel updates with: wsl --update'
if ($interopDisabled) {
    Warn "WSL interop is off in '$Distro', so 'code .' and 'explorer.exe' don't work from inside it."
}
if (-not $src) {
    Warn 'sbx was downloaded from the main branch on GitHub, not from a release zip.'
}
Warn "Ubuntu's Node may be too old for pi; Claude Code doesn't need Node. See docs/wsl2.md."
