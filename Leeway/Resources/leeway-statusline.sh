#!/bin/sh
# Leeway bridge for the Claude Code statusLine hook.
#
# Claude Code pipes its status JSON — subscription limits included — into this
# script. It parks the JSON for the menu bar app, then hands stdin to the status
# line that was configured before Leeway took over, if there was one.

set -u

dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
state="$dir/leeway.json"
inherited="$dir/leeway-inner.sh"

input=$(cat)

tmp="$state.$$"
if printf '%s' "$input" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$state" 2>/dev/null || rm -f "$tmp"
fi

if [ -x "$inherited" ]; then
    printf '%s' "$input" | "$inherited"
    exit $?
fi

# Own status line, used when Leeway installed the hook on a session without one.
if command -v jq > /dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
        [ (.model.display_name // empty),
          (.workspace.current_dir // "" | split("/") | last),
          (if .rate_limits.five_hour then "5h \(.rate_limits.five_hour.used_percentage | round)%" else empty end),
          (if .rate_limits.seven_day then "7d \(.rate_limits.seven_day.used_percentage | round)%" else empty end)
        ] | map(select(. != "" and . != null)) | join(" · ")'
fi
