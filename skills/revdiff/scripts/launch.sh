#!/usr/bin/env bash
# Open revdiff in a floating Zellij pane, wired to inject each annotation flush
# back into this Claude Code session, and return immediately.
#
# usage: launch.sh [revdiff args...]
# exit: 0 once the pane is open, nonzero if it could not be opened
#
# Nothing watches the pane after this. revdiff drives the whole review: the
# reviewer annotates, flushes with `O`, reloads with `R`, and each flush runs
# scripts/flush.sh, which posts the annotations to this session's inbox socket.
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

if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    echo "error: not inside a Claude Code session" >&2
    exit 1
fi

# The socket is how annotations get back here, so its absence is fatal rather
# than degraded. A session binds one only with cross-session messaging enabled
# (Claude Code v2.1.224+, macOS/Linux), and binding can fail for reasons not
# visible from inside the session, so say what to check.
SOCKET="${CLAUDE_CODE_MESSAGING_SOCKET:-}"
if [ -z "$SOCKET" ]; then
    cat >&2 <<'EOF'
error: this session has no inbox socket, so revdiff has nowhere to send annotations.
       CLAUDE_CODE_MESSAGING_SOCKET is unset. Check with /status — a session with an
       inbox shows a "Peer address" row. Requires Claude Code v2.1.224 or later on
       macOS or Linux. Starting a fresh session usually binds one.
EOF
    exit 1
fi
SOCKET="${SOCKET#uds:}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUSH_SCRIPT="$SCRIPT_DIR/flush.sh"

# Checked here because a flush.sh that can't run is the one failure that leaves
# no trace: it never starts, so it never writes its log, and revdiff's own error
# dies with the pane.
if [ ! -x "$FLUSH_SCRIPT" ]; then
    printf 'error: %s is missing or not executable\n' "$FLUSH_SCRIPT" >&2
    exit 1
fi

STATE_DIR="/tmp/revdiff-${CLAUDE_CODE_SESSION_ID}"
mkdir -p "$STATE_DIR"
ANNOTATIONS="$STATE_DIR/annotations"

# revdiff only writes this on flush; clear whatever a previous review left so a
# stale set can't be injected by the first flush of this one.
rm -f "$ANNOTATIONS"

# flush.sh needs jq and socat, but it runs in the zellij server's environment,
# whose PATH is whatever zellij was started with — routinely not the PATH this
# script sees. Resolve them here, where the environment is known, and pass
# absolute paths. Failing now is much better than failing at flush time, after
# the reviewer has already written their annotations.
JQ_BIN=$(command -v jq || true)
SOCAT_BIN=$(command -v socat || true)
MISSING=""
[ -n "$JQ_BIN" ] || MISSING="jq"
[ -n "$SOCAT_BIN" ] || MISSING="${MISSING:+$MISSING and }socat"
if [ -n "$MISSING" ]; then
    printf 'error: %s not found in PATH; flush.sh needs it to encode and deliver annotations\n' \
        "$MISSING" >&2
    exit 1
fi

# revdiff hands --post-flush-command to a shell, so the arguments are quoted
# here. Every value is passed explicitly: revdiff is spawned by the zellij
# server, whose environment has none of the CLAUDE_* variables.
POST_FLUSH=$(printf '%s --socket-path %q --annotations %q --session-id %q --jq %q --socat %q' \
    "$FLUSH_SCRIPT" "$SOCKET" "$ANNOTATIONS" "$CLAUDE_CODE_SESSION_ID" "$JQ_BIN" "$SOCAT_BIN")

CMD=("$REVDIFF_BIN" --output="$ANNOTATIONS" --post-flush-command="$POST_FLUSH" "$@")

# the zellij server spawns pane commands with its own environment, which
# predates shell rc exports; carry the caller's editor through so revdiff's
# multi-line annotation flow opens the right one
ENV_ARGS=()
if [ -n "${EDITOR:-}" ]; then ENV_ARGS+=("EDITOR=$EDITOR"); fi
if [ -n "${VISUAL:-}" ]; then ENV_ARGS+=("VISUAL=$VISUAL"); fi
if [ ${#ENV_ARGS[@]} -gt 0 ]; then
    CMD=(/usr/bin/env "${ENV_ARGS[@]}" "${CMD[@]}")
fi

# No --block-until-exit: the pane outlives this script. Bad revdiff arguments
# therefore surface as a pane that closes immediately rather than as a nonzero
# exit here.
zellij run --floating --close-on-exit \
    --width "${REVDIFF_POPUP_WIDTH:-90%}" --height "${REVDIFF_POPUP_HEIGHT:-90%}" \
    --x 5% --y 5% \
    --name "revdiff: $(basename "$PWD")" --cwd "$PWD" \
    -- "${CMD[@]}"

echo "revdiff pane open. Annotations will arrive here on each flush (\`O\`)."
