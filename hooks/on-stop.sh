#!/usr/bin/env bash
# Stop hook: continue, defer, or end the revdiff review loop. The loop flag
# means the last pass produced annotations; the dirty flag means files were
# modified in response. Both flags are consumed here; hooks/defer.sh re-arms
# them when the re-review is deferred because discussion topics from the
# annotations are still unresolved. launch.sh re-arms the loop flag when a
# launched pass closes with annotations.
set -euo pipefail

if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    exit 0
fi

LOOP_FLAG="/tmp/revdiff-loop-${CLAUDE_CODE_SESSION_ID}"
if [ ! -f "$LOOP_FLAG" ]; then
    exit 0
fi

rm -f "$LOOP_FLAG"

if [ ! -f "${LOOP_FLAG}.dirty" ]; then
    exit 0
fi
rm -f "${LOOP_FLAG}.dirty"

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCH_SCRIPT="${PLUGIN_ROOT}/skills/revdiff/scripts/launch.sh"
DEFER_SCRIPT="${PLUGIN_ROOT}/hooks/defer.sh"

# the pin written by launch.sh at the last pass's close: line 1 the baseline
# commit id, line 2 the identity (change id + parent commit ids) used to
# detect history restructuring. Read without deleting — a deferred re-review
# needs the pin again at a later stop, and every pass close overwrites it
# anyway. The baseline is only trusted when the live identity still matches;
# --ignore-working-copy keeps this read-only (plain jj log would snapshot the
# working copy as a side effect). Baseline is sanitized to hex so nothing
# else can ride into the launch command.
BASELINE=""
HISTORY_CHANGED=""
if [ -f "${LOOP_FLAG}.baseline" ]; then
    { IFS= read -r PIN_COMMIT || true; IFS= read -r PIN_IDENTITY || true; } < "${LOOP_FLAG}.baseline"
    LIVE_IDENTITY=$(jj log -r @ --no-graph --ignore-working-copy \
        -T 'change_id ++ " " ++ parents.map(|c| c.commit_id()).join(",")' 2>/dev/null || true)
    BASELINE=$(printf '%s' "${PIN_COMMIT:-}" | tr -cd '0-9a-f')
    if [ -z "$BASELINE" ] || [ -z "$LIVE_IDENTITY" ] || [ "$LIVE_IDENTITY" != "${PIN_IDENTITY:-}" ]; then
        BASELINE=""
        HISTORY_CHANGED="1"
    fi
fi

if [ -n "$HISTORY_CHANGED" ]; then
    printf '{"decision": "block", "reason": "Files were changed in response to revdiff annotations, but the commit history has changed since the last review pass, so the review baseline was discarded and the next pass covers the full diff as a fresh session. If discussion topics from those annotations are still unresolved in the conversation, do not launch: run %s to keep the re-review pending, tell the user the re-review is deferred until the discussion settles, and stop. If the conversation has moved on to unrelated work without resolving them, tell the user the re-review is available via /revdiff, and stop. Otherwise launch another review pass: run %s in the background (run_in_background: true), appending --description=<text> where <text> is a brief summary of the changes you made in response to the annotations (it is shown in the pane info popup). Tell the user that a history change was detected and the pane shows the full diff as a fresh session, and stop. The annotations arrive later as a task notification."}\n' "$DEFER_SCRIPT" "$LAUNCH_SCRIPT"
else
    printf '{"decision": "block", "reason": "Files were changed in response to revdiff annotations. If discussion topics from those annotations are still unresolved in the conversation, do not launch: run %s to keep the re-review pending, tell the user the re-review is deferred until the discussion settles, and stop. If the conversation has moved on to unrelated work without resolving them, tell the user the re-review is available via /revdiff, and stop. Otherwise launch another review pass: run %s%s in the background (run_in_background: true), appending --description=<text> where <text> is a brief summary of the changes you made in response to the annotations (it is shown in the pane info popup). Tell the user the pane is open, and stop. The annotations arrive later as a task notification."}\n' "$DEFER_SCRIPT" "$LAUNCH_SCRIPT" "${BASELINE:+ $BASELINE}"
fi
