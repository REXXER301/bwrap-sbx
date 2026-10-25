# shellcheck shell=bash
# sbx must refuse to expose too much. Each refusal happens before bwrap starts.

section "sbx refuses unsafe invocations"

check_exit "refuses to run in /" 1 "refusing to run" bash -c 'cd / && exec sbx -- true'
check_exit "refuses to run in /tmp" 1 "refusing to run" bash -c 'cd /tmp && exec sbx -- true'
check_exit "refuses to run in \$HOME" 1 "refusing to run" bash -c 'cd ~ && exec sbx -- true'

check_exit "--ro / is refused" 1 "refusing to expose" sbx_cli --ro / -- true
check_exit "--ro /home (holds \$HOME) is refused" 1 "refusing to expose" sbx_cli --ro /home -- true
check_exit "--ro \$HOME is refused" 1 "refusing to expose" sbx_cli --ro /home/tester -- true
check_exit "--ro of a folder containing the project is refused" 1 "contains the project" sbx_cli --ro /home/tester/work -- true
check_exit "--ro of a missing path is refused" 1 "does not exist" sbx_cli --ro "/sbx-missing-$RAND" -- true

check_exit "--port abc is refused" 2 "not a port number" sbx_cli --port abc -- true
check_exit "--port 70000 is refused" 2 "not a port number" sbx_cli --port 70000 -- true
check_exit "--allow with a comma (socat option injection) is refused" 2 "not an address" \
    sbx_cli --allow '127.0.0.1,fork' -- true
check_exit "--publish without --offline is refused" 1 "only works with --offline" sbx_cli --publish 18888 -- true
check_exit "unknown options are refused" 2 "unknown option" sbx_cli --bogus -- true
check_exit "invalid SBX_ENV names are skipped" 0 "not a variable name" env 'SBX_ENV=BAD-NAME' bash -c "cd '$PROJ' && exec sbx -- true"
