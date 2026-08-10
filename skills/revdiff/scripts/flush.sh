#!/usr/bin/env bash
# Inject the reviewer's annotations into a Claude Code session's inbox socket.
# Invoked by revdiff itself as --post-flush-command, once per successful `O`
# flush.
#
# usage: flush.sh --socket-path <uds> --annotations <file> --session-id <id>
#                 --jq <path> --socat <path>
#
# Every value is passed explicitly because revdiff is spawned by the zellij
# server, into an environment that has none of the CLAUDE_* variables and a PATH
# that routinely lacks jq and socat. launch.sh resolves all five and bakes them
# into the command string.
#
# revdiff waits for this script before restoring the TUI, so it must stay fast:
# no reply is read from the socket, and every failure path exits promptly.
#
# Failures are also logged next to the annotations. revdiff does report an error
# here, but to its own stdout rather than the TUI — and the pane runs with
# --close-on-exit, so that output is destroyed with the pane. Since the socket
# discards malformed writes silently too, this log is the only durable record.
# If flushes seem to vanish, read it.
set -euo pipefail

SOCKET=""
ANNOTATIONS=""
SESSION_ID=""
JQ=""
SOCAT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --socket-path) SOCKET="${2:-}"; shift 2 ;;
        --annotations) ANNOTATIONS="${2:-}"; shift 2 ;;
        --session-id)  SESSION_ID="${2:-}"; shift 2 ;;
        --jq)          JQ="${2:-}"; shift 2 ;;
        --socat)       SOCAT="${2:-}"; shift 2 ;;
        *) printf 'flush.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

if [ -z "$SOCKET" ] || [ -z "$ANNOTATIONS" ] || [ -z "$SESSION_ID" ] \
   || [ -z "$JQ" ] || [ -z "$SOCAT" ]; then
    echo "flush.sh: --socket-path, --annotations, --session-id, --jq and --socat are all required" >&2
    exit 2
fi

LOG="$(dirname "$ANNOTATIONS")/flush.log"
log() { printf '%s flush.sh: %s\n' "$(date -Is)" "$1" >> "$LOG" 2>/dev/null || true; }

# Nothing to say: the reviewer flushed an empty set, or cleared every
# annotation. Staying silent here is the point — it spares the session a turn
# that would have nothing to act on.
if [ ! -s "$ANNOTATIONS" ] || [ -z "$(tr -d '[:space:]' < "$ANNOTATIONS")" ]; then
    log "empty annotation set; nothing sent"
    exit 0
fi

# Absolute paths, resolved by launch.sh from an environment that has them. This
# script's own PATH is the zellij server's and routinely lacks both.
for dep in "$JQ" "$SOCAT"; do
    if [ ! -x "$dep" ]; then
        log "dependency not executable: $dep"
        exit 1
    fi
done

if [ ! -S "$SOCKET" ]; then
    log "socket is gone: $SOCKET (session ended or restarted?)"
    exit 1
fi

# The transport is newline-delimited JSON, so the annotations have to be a
# properly escaped JSON string; --rawfile does that without the content ever
# passing through the shell. session_id is included so a stale socket path
# makes the receiver drop the message rather than deliver it into whatever
# session now owns that pid.
#
# The lead-in only has to name the source. Claude Code wraps an inbox message in
# its own framing about the sender acting on the user's behalf, so anything more
# said here just repeats it.
LEAD_IN="Annotations from revdiff:"

# shellcheck disable=SC2016  # the jq program is single-quoted deliberately:
# $sid, $lead and $annotations are jq variables, not shell expansions.
if ! payload=$("$JQ" -cn \
    --arg sid "$SESSION_ID" \
    --arg lead "$LEAD_IN" \
    --rawfile annotations "$ANNOTATIONS" \
    '{
        type: "user",
        session_id: $sid,
        from: "revdiff",
        message: {
            role: "user",
            content: ($lead + "\n\n" + $annotations)
        }
    }' 2>>"$LOG"); then
    log "failed to build payload from $ANNOTATIONS"
    exit 1
fi

# The receiver reads a line at a time and drops the connection outright once one
# exceeds 1 MiB, reporting nothing. Measured in bytes rather than characters,
# since multibyte annotations are longer than their character count suggests.
PAYLOAD_BYTES=$(printf '%s\n' "$payload" | wc -c)
if [ "$PAYLOAD_BYTES" -ge 1048576 ]; then
    log "payload is $PAYLOAD_BYTES bytes; receiver drops lines at 1 MiB, so this would vanish. Annotation set too large."
    exit 1
fi

# -u is one-way: send and close without waiting on a reply the server never
# sends. Anything else would stall the TUI for the socat timeout on every flush.
if printf '%s\n' "$payload" | timeout 5 "$SOCAT" -u - "UNIX-CONNECT:$SOCKET" 2>>"$LOG"; then
    log "sent $(wc -c < "$ANNOTATIONS") bytes of annotations to $SOCKET"
else
    log "socat write failed to $SOCKET"
    exit 1
fi
