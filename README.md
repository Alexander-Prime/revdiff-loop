# revdiff-relay

A Claude Code plugin that wires [revdiff](https://github.com/umputun/revdiff) into a
floating [Zellij](https://zellij.dev) pane and pipes your diff annotations straight into
your Claude Code session.

`/revdiff` opens the revdiff TUI over the current diff and gets out of the way. Annotate,
press `O`, and the annotations appear in your session as a message — Claude answers
questions in conversation and implements change requests. Press `R` to reload the diff and
see what changed, annotate again, flush again. There is no round structure and no fixed
number of passes: the pane is yours for as long as you want it, and each flush is just a
message.

Nothing on the Claude Code side watches or waits. `/revdiff` stands up a process wired with
enough context to inject back into your session, and that is the extent of it.

## Requirements

- `revdiff` on PATH, with `--post-flush-command` and the `flush_output` action (`O`)
- `jq` and `socat` reachable from the shell Claude Code runs in. `launch.sh` resolves them to
  absolute paths and passes those to `flush.sh`, so they do **not** need to be on the Zellij
  server's PATH — which is a different environment, and commonly a barer one. A missing tool
  fails the launch immediately rather than the first flush
- Zellij with floating pane support, and Claude Code running inside a Zellij session
- Claude Code **v2.1.224 or later** on macOS or Linux, in a session that binds an inbox
  socket — check with `/status`, which shows a `Peer address` row when it has one

## Install

```
/plugin marketplace add <git-url-or-owner/repo-or-local-path>
/plugin install revdiff-relay@revdiff-relay
```

## Usage

```
/revdiff              auto-detect: working-copy changes, last commit, or branch vs main
/revdiff main         review against a branch
/revdiff @-           any ref syntax revdiff understands (git, jj, and hg supported)
/revdiff --staged     staged changes only
```

Arguments are passed through to revdiff unmodified.

In the pane:

| Key | Effect                                                   |
| --- | -------------------------------------------------------- |
| `O` | Flush annotations to Claude without closing the pane     |
| `R` | Reload the diff from the VCS, picking up Claude's edits  |
| `i` | Info popup                                               |

`O` and `R` are revdiff's own keys and are rebindable in its config.

## Configuration

### If you run with permission prompts bypassed

An inbox message is delivered without an approval dialog only when Claude Code can verify it
came from one of the session's own child processes. `flush.sh` is a child of the Zellij
server, not of Claude Code, so it can't be verified. That is fine in any session that
prompts for permissions — `auto`, `acceptEdits`, and `dontAsk` all count as prompting, and
unverified messages are delivered normally. In a session that **bypasses** permission
prompts, each flush is instead held for your approval, and a held message is dropped
silently after five minutes.

If you run that way, set `crossSessionInbound` to `accept` so flushes are delivered
unattended.

### Other

- `REVDIFF_POPUP_WIDTH` / `REVDIFF_POPUP_HEIGHT` — floating pane size (default `90%`)
- revdiff's own look and behavior (theme, line numbers, keybindings) belong in
  `~/.config/revdiff/config`, which applies to manual runs too

## How it works

- `skills/revdiff/scripts/launch.sh` opens the floating pane and returns. It points
  revdiff's `--output` at `/tmp/revdiff-<session-id>/annotations` and passes
  `--post-flush-command`, with the socket path, annotations path, session id, and the
  resolved `jq` and `socat` paths baked into the command string.
- All five are passed explicitly because they have to be. revdiff is spawned by the Zellij
  server, into an environment with no `CLAUDE_*` variables at all and a PATH that routinely
  lacks `jq` and `socat`.
- `skills/revdiff/scripts/flush.sh` runs once per successful flush. It exits silently on an
  empty annotation set, so clearing your comments costs Claude nothing, then builds a
  newline-delimited JSON message with `jq --rawfile` and writes it to the session's inbox
  socket with a one-way `socat`.
- The message carries `session_id`, so a stale socket path makes the receiver drop the
  message rather than deliver it into whichever session now owns that pid.
- The content is prefixed with `Annotations from revdiff:`, so a message arriving mid-task
  identifies its source.
- Annotation lifecycle is revdiff's, not the plugin's. `R` drops the annotations on lines the
  reload changed and keeps the others, so a comment that comes back around is one you left
  standing on purpose. The plugin does no diffing and keeps no snapshot, which is also why
  git, jj, and hg all behave identically.

### Debugging

revdiff reports a post-flush-command failure on its own stdout, not in the TUI — and the
pane runs with `--close-on-exit`, so that output dies with the pane. The socket discards
malformed writes without complaint too.

So `flush.sh` keeps its own log at `/tmp/revdiff-<session-id>/flush.log`, recording
every flush, every skip, and every failure with a reason. If flushes seem to vanish, read
that file first.
