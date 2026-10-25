# shellcheck shell=bash
# Control checks outside sbx: they show the later checks mean something.

section "Preconditions (outside sbx)"

# Builds the pattern from pieces so this file doesn't match itself.
no_recursive_deletes() {
    local pat='r''m[[:space:]]+(-[[:alnum:]]*[rR]|--recursive)|r''mdir|-del''ete|unlink[[:space:]]+-r'
    ! grep -rnE --include='*.sh' --include=Containerfile -- "$pat" "$SUITE_DIR"
}
check "the suite contains no recursive delete or folder removal" no_recursive_deletes

for f in "${CANARIES[@]}"; do
    check "control: writable outside sbx: $f" test -w "$f"
done
for d in "${CANARY_DIRS[@]}"; do
    check "control: files can be created outside sbx in: $d" test -w "$d"
done

check "control: no_new_privs is off outside sbx" has_line '^NoNewPrivs:[[:space:]]+0$' "$(cat /proc/self/status)"

# The first run creates .sbx-home, so later output is free of setup messages.
expect_ok "sbx starts and runs a command" 'true'
