# revdiff-loop

A Claude Code plugin that wires [revdiff](https://github.com/umputun/revdiff) into an
annotate → fix → re-review loop, using a floating [Zellij](https://zellij.dev) pane.

`/revdiff` opens the revdiff TUI over the current diff in a floating pane. Annotate the
diff and close the pane; the annotations flow back to Claude, which answers questions in
conversation and implements change requests. Whenever Claude modifies files in response
to annotations, a Stop hook automatically reopens revdiff so you can review the fixes.
The loop ends when you close a pass without annotations, or when a pass leads to no file
changes.

## Requirements

- `revdiff` on PATH
- Zellij ≥ 0.44 (`zellij run --block-until-exit`), with Claude Code running inside a
  Zellij session

## Install

```
/plugin marketplace add <git-url-or-owner/repo-or-local-path>
/plugin install revdiff-loop@revdiff-loop
```

## Usage

```
/revdiff              auto-detect: working-copy changes, last commit, or branch vs main
/revdiff main         review against a branch
/revdiff @-           any ref syntax revdiff understands (git, jj, and hg supported)
/revdiff --staged     staged changes only
```

Arguments are passed through to revdiff unmodified.

## Configuration

### Permission prompts

The skill's `allowed-tools` frontmatter pre-approves the two bundled scripts Claude runs
(`scripts/launch.sh` and `hooks/defer.sh`), so typing `/revdiff` opens the pane without a
prompt. That grant only covers the turn you invoke the skill in — it clears as soon as you
send your next message. The loop is built to span your messages, so hook-triggered
follow-up passes will still prompt.

For a prompt-free loop, add session-wide allow rules to `~/.claude/settings.json`. Bash
rules match the literal command string, so these need your real absolute home path —
`~/` is not expanded here. The wildcard covers the version directory so the rules survive
plugin updates:

```json
{
  "permissions": {
    "allow": [
      "Bash(/home/you/.claude/plugins/cache/revdiff-loop/revdiff-loop/*/skills/revdiff/scripts/launch.sh *)",
      "Bash(/home/you/.claude/plugins/cache/revdiff-loop/revdiff-loop/*/hooks/defer.sh *)"
    ]
  }
}
```

Both scripts are inert without a review in flight: `launch.sh` only opens a pane and
prints what you typed into it, and `defer.sh` only touches two flag files in `/tmp`.

### Other

- `REVDIFF_POPUP_WIDTH` / `REVDIFF_POPUP_HEIGHT` — floating pane size (default `90%`)
- revdiff's own look and behavior (theme, line numbers, keybindings) belong in
  `~/.config/revdiff/config`, which applies to manual runs too

## How the loop works

- `skills/revdiff/scripts/launch.sh` runs revdiff in a floating pane, blocks until the
  pane closes, and prints the captured annotations. A pass that produces annotations
  arms a loop flag in `/tmp`, keyed by the Claude Code session ID (inherited by tool
  shells and hooks alike); a clean pass clears it.
- `hooks/mark-dirty.sh` (PostToolUse on file-editing tools) marks a dirty flag, but only
  while the loop flag is armed — ordinary edits outside a review never trigger the loop.
- `hooks/on-stop.sh` (Stop) consumes both flags: if files changed in response to a pass,
  it blocks the stop and has Claude launch the next pass.
- In jj repos, each pass pins the just-reviewed working-copy commit ID (jj snapshots
  the working copy automatically, so that state stays resolvable). Hook-triggered
  follow-up passes diff from the pin, so the pane shows only what changed since you
  last reviewed — unchanged files and unchanged hunks don't reappear. A manual
  `/revdiff` ignores the pin and reviews the full diff, starting a fresh session. In
  git repos there is no commit ID for uncommitted work-tree state, so follow-up passes
  fall back to the full diff.
- Restructuring history mid-loop (`jj new`, `jj edit`, rebase, squash, abandon) is
  detected before the pin is trusted: the pin records `@`'s change ID and parent commit
  IDs, and the Stop hook compares them against the live values. On mismatch the
  baseline is discarded, the follow-up pass covers the full diff, and Claude explains
  that a new review session was started.
- Follow-up passes carry `--description` with Claude's summary of what changed in
  response to the annotations — press `i` in revdiff to see it in the info popup.
- When a pass mixes change requests with discussion topics, the requested fixes land
  immediately, but the re-review is deferred (`hooks/defer.sh` re-arms the loop) until
  the discussion settles — the pane then opens once, covering everything accumulated
  since the last close, including changes the discussion produced. If the conversation
  moves on without resolving, the loop ends and `/revdiff` starts the next session.
