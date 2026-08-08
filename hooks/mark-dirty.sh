#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit|NotebookEdit): while a revdiff pass
# awaits a response (loop flag set by the skill's scripts/launch.sh), record
# that files were modified so the Stop hook triggers another review pass.
set -euo pipefail

if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    exit 0
fi

LOOP_FLAG="/tmp/revdiff-loop-${CLAUDE_CODE_SESSION_ID}"
if [ -f "$LOOP_FLAG" ]; then
    touch "${LOOP_FLAG}.dirty"
fi
