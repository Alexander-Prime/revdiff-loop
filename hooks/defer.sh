#!/usr/bin/env bash
# Re-arm the review-loop flags so the Stop hook re-offers the review pass at a
# later stop. Run instead of launching when discussion topics from the
# annotations are still unresolved in conversation; the pane then opens once
# the discussion settles (and covers any further changes it produced).
set -euo pipefail

if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    echo "error: not inside a Claude Code session" >&2
    exit 1
fi

LOOP_FLAG="/tmp/revdiff-loop-${CLAUDE_CODE_SESSION_ID}"
touch "$LOOP_FLAG" "${LOOP_FLAG}.dirty"
