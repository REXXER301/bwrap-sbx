#!/usr/bin/env bash
# Build the test image and run the sbx isolation suite in a rootless podman
# container. Nothing from the host is mounted into the container and it has no
# network, so the suite can only touch the container's own files.
#
#   tests/run.sh            build the image and run every suite
#   tests/run.sh 20 50      only suites whose file name contains 20 or 50
#   SBX_TEST_IMAGE=NAME     image tag (default localhost/sbx-tests:latest)

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(dirname "$here")
image=${SBX_TEST_IMAGE:-localhost/sbx-tests:latest}

command -v podman >/dev/null || { echo "run.sh: podman is not installed" >&2; exit 1; }
if ((EUID == 0)); then
    echo "run.sh: run this as your normal user (rootless podman), not as root" >&2
    exit 1
fi

podman build --pull=newer -f "$here/Containerfile" --ignorefile "$here/containerignore" \
    -t "$image" "$repo"

# No volumes, no network, no capabilities, bounded processes and memory.
base=(run --rm --network none --cap-drop ALL --pids-limit 1024 --memory 1g)

# bwrap mounts a fresh /proc for the sandbox, which the kernel only allows
# when the container's own /proc has nothing masked over it. Try the narrowest
# option first; the fallback also drops seccomp, SELinux labels and the AppArmor
# profile (Ubuntu's denies mounts), which some hosts need for nested namespaces.
# Both stay inside the rootless user namespace.
profiles=(
    "--security-opt unmask=/proc/*"
    "--security-opt unmask=ALL --security-opt seccomp=unconfined --security-opt label=disable --security-opt apparmor=unconfined"
)
sec=()
for p in "${profiles[@]}"; do
    read -ra opts <<<"$p"
    if out=$(podman "${base[@]}" "${opts[@]}" "$image" /opt/sbx-tests/preflight.sh 2>&1); then
        sec=("${opts[@]}")
        break
    fi
    echo "run.sh: bwrap does not start with: $p" >&2
    echo "$out" | sed 's/^/        /' >&2
done
((${#sec[@]})) || { echo "run.sh: bwrap cannot run in the container on this host" >&2; exit 1; }
echo "run.sh: podman security options: ${sec[*]}"

[[ -t 1 ]] && base+=(-t)
cmd=(podman "${base[@]}" "${sec[@]}" "$image" /opt/sbx-tests/run-tests.sh "$@")

[[ -n ${GITHUB_STEP_SUMMARY-} ]] || exec "${cmd[@]}"

# On GitHub Actions, also write the results to the job summary page.
log=$(mktemp)
rc=0
"${cmd[@]}" | tee "$log" || rc=$?
awk -v rc="$rc" -f "$here/job-summary.awk" "$log" >>"$GITHUB_STEP_SUMMARY"
rm -f -- "$log"
exit "$rc"
