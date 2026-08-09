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

# The reason is deliberately terse: the full launch/defer/end procedure lives in
# the skill's step 4, which stays in context for the whole session, and restating
# it on every trigger floods the conversation.
if [ -n "$HISTORY_CHANGED" ]; then
    printf '{"decision": "block", "reason": "revdiff loop: files changed since the last pass; history changed, so the baseline was dropped and the next pass is a fresh full-diff session. Apply skill step 4. Launch: %s | Defer: %s"}\n' "$LAUNCH_SCRIPT" "$DEFER_SCRIPT"
else
    printf '{"decision": "block", "reason": "revdiff loop: files changed since the last pass. Apply skill step 4. Launch: %s%s | Defer: %s"}\n' "$LAUNCH_SCRIPT" "${BASELINE:+ $BASELINE}" "$DEFER_SCRIPT"
fi
