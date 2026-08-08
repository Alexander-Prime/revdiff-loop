#!/usr/bin/env bash
# Launch revdiff in a floating Zellij pane and print captured annotations to stdout.
# usage: launch.sh [revdiff args...]
# exit: 0 with annotations on stdout (empty if reviewer left none), nonzero on failure
set -euo pipefail

if [ -z "${ZELLIJ:-}" ]; then
    echo "error: not inside a Zellij session" >&2
    exit 1
fi

REVDIFF_BIN=$(command -v revdiff || true)
if [ -z "$REVDIFF_BIN" ]; then
    echo "error: revdiff not found in PATH" >&2
    exit 1
fi

OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/revdiff-annotations-XXXXXX")
trap 'rm -f "$OUTPUT_FILE"' EXIT

CMD=("$REVDIFF_BIN" --output="$OUTPUT_FILE" "$@")

# the zellij server spawns pane commands with its own environment, which
# predates shell rc exports; carry the caller's editor through so revdiff's
# multi-line annotation flow opens the right one
ENV_ARGS=()
if [ -n "${EDITOR:-}" ]; then ENV_ARGS+=("EDITOR=$EDITOR"); fi
if [ -n "${VISUAL:-}" ]; then ENV_ARGS+=("VISUAL=$VISUAL"); fi
if [ ${#ENV_ARGS[@]} -gt 0 ]; then
    CMD=(/usr/bin/env "${ENV_ARGS[@]}" "${CMD[@]}")
fi

rc=0
zellij run --floating --close-on-exit --block-until-exit \
    --width "${REVDIFF_POPUP_WIDTH:-90%}" --height "${REVDIFF_POPUP_HEIGHT:-90%}" \
    --x 5% --y 5% \
    --name "revdiff: $(basename "$PWD")" --cwd "$PWD" \
    -- "${CMD[@]}" || rc=$?

if [ "$rc" -ne 0 ]; then
    echo "error: revdiff exited with code $rc (bad arguments, or the pane was killed)" >&2
    exit "$rc"
fi

# review-loop contract shared with the plugin's hooks/mark-dirty.sh and
# hooks/on-stop.sh: the loop flag exists while a pass's annotations await a
# response; the dirty flag marks file edits made during that window. Keyed by
# the Claude Code session id, which tool shells and hook processes both
# inherit; skipped entirely when run outside a Claude session. Hardcoded /tmp
# because hooks run in Claude Code's process env, whose TMPDIR can differ
# from this shell's.
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    LOOP_FLAG="/tmp/revdiff-loop-${CLAUDE_CODE_SESSION_ID}"
    rm -f "${LOOP_FLAG}.dirty"
    if [ -s "$OUTPUT_FILE" ]; then
        touch "$LOOP_FLAG"
    else
        rm -f "$LOOP_FLAG"
    fi

    # pin the just-reviewed working-copy state so a hook-triggered follow-up
    # pass can diff from it (revdiff <id> -> jj diff --from <id> --to @),
    # showing only changes made since this review. jj-only: git has no commit
    # id for uncommitted work-tree state, so there the follow-up falls back to
    # the full diff. Every pass pins — a manual pass overwrites the pin,
    # resetting the review session.
    #
    # Line 1 is the baseline commit id. Line 2 is the identity the Stop hook
    # uses to detect history restructuring before trusting the pin: @'s change
    # id (differs after jj new/edit, even onto the same parent) plus parent
    # commit ids (differ after rebase/squash/abandon anywhere in the ancestry,
    # since commit ids hash their ancestry transitively).
    BASELINE_FILE="${LOOP_FLAG}.baseline"
    if jj root >/dev/null 2>&1; then
        jj log -r @ --no-graph \
            -T 'commit_id ++ "\n" ++ change_id ++ " " ++ parents.map(|c| c.commit_id()).join(",")' \
            > "$BASELINE_FILE" 2>/dev/null || rm -f "$BASELINE_FILE"
    else
        rm -f "$BASELINE_FILE"
    fi
fi

cat "$OUTPUT_FILE"
