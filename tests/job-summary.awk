# Turns run-tests.sh output into Markdown for the GitHub Actions job summary.
#   awk -v rc=EXIT_CODE -f job-summary.awk LOG

function cell(s) { gsub(/\|/, "\\|", s); return s }

BEGIN { icon["PASS"] = "✅"; icon["FAIL"] = "❌"; icon["KNOWN"] = "⚠️" }

{ gsub(/\033\[[0-9;]*m/, "") }

/^== / { sec = substr($0, 4); next }

/^  (PASS|FAIL|KNOWN) / {
    st = $1
    name = $0
    sub(/^  [A-Z]+ +/, "", name)
    n[st]++
    rows = rows "| " cell(sec) " | " icon[st] " | " cell(name) " |\n"
    if (st != "PASS") listed[st] = listed[st] "- " sec ": " name "\n"
}

END {
    print "## sbx isolation tests"
    print ""
    if (n["PASS"] + n["FAIL"] + n["KNOWN"] == 0) {
        printf "The suite produced no results (exit code %s), see the job log.\n", rc
        exit
    }
    printf "**%d passed, %d failed, %d known/documented**", n["PASS"], n["FAIL"], n["KNOWN"]
    if (rc != 0 && n["FAIL"] == 0) printf " (exit code %s without a failed check, see the job log)", rc
    print "\n"
    if (n["FAIL"]) printf "### Failed\n\n%s\n", listed["FAIL"]
    if (n["KNOWN"]) printf "### Known / documented\n\n%s\n", listed["KNOWN"]
    printf "<details><summary>All checks</summary>\n\n| Section | Result | Check |\n|---|---|---|\n%s\n</details>\n", rows
}
