---
name: revdiff
description: "Launch revdiff in a floating Zellij pane so the user can annotate the current diff, then address the captured annotations. Use when the user wants to review or annotate a diff."
argument-hint: "[ref] [ref2] [--staged] [--only=<file>]"
allowed-tools:
  - "Bash(${CLAUDE_SKILL_DIR}/scripts/launch.sh *)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/hooks/defer.sh *)"
---

# revdiff review

Launch the revdiff TUI for the user, wait for their annotations, then address them.

The launcher script is `${CLAUDE_SKILL_DIR}/scripts/launch.sh`. Run it exactly as written — the path is already absolute, and it matches this skill's `allowed-tools` rule verbatim, so rewriting it costs a permission prompt.

## Workflow

1. Run `${CLAUDE_SKILL_DIR}/scripts/launch.sh $ARGUMENTS` **in the background** (`run_in_background: true`). Then **stop and return control to the user** — they are reviewing in the floating pane and may take a while. Do NOT call `TaskOutput` to wait on the result; a `<task-notification>` arrives when they close revdiff. All arguments are optional and pass through to revdiff unmodified — a ref, two refs, `--staged`, `--only=<file>`, or anything else it accepts. With no arguments, revdiff auto-detects what to review (working-copy changes, last commit, or branch vs main; git, jj, and hg all supported).
2. When the notification arrives, read the task output:
   - **Nonzero exit** — launch or revdiff failure; report the error and stop.
   - **Empty stdout** — the user finished without leaving annotations; say so and stop.
   - **Otherwise** — stdout is the annotations as markdown: `## path/to/file:43 (+)` headers (`(+)` added line, `(-)` removed line, `( )` unchanged context line, no line number = file-level comment) followed by the comment text.
3. Work through the annotations in order. For each one, quote it briefly so the response maps back to what was written, then classify it:
   - **Question or discussion** (asks why, how, whether): answer it in conversation. Do not change code unless the answer implies a change and the user confirms.
   - **Change directive** (points out a bug, requests an edit): implement it, following the project's usual standards — for behavior changes covered by tests, failing test first.
4. Do not relaunch revdiff on your own initiative. The Stop hook drives the loop: when files were changed in response to annotations, it blocks the stop with a terse `revdiff loop:` message naming a launch and a defer command. That message is only a trigger — the procedure below is the whole instruction, so follow it from here rather than expecting the hook to repeat it.

   Pick one outcome by the state of the conversation:
   - **Launch** — when the discussion topics from the annotations are settled, or there were none. Run the launch command from the hook message in the background (`run_in_background: true`), verbatim including any trailing baseline commit ID (jj only; it scopes the pane to changes since the user's last pass), and append `--description=<text>` summarizing briefly what you changed in response to the annotations — revdiff shows it in the pane's info popup (`i`). Tell the user the pane is open, and stop. The annotations arrive later as a task notification.
   - **Defer** — while any discussion topic from the annotations is still open. Run the defer command instead of launching, tell the user the re-review is pending until the discussion settles, and stop.
   - **End the loop** — if the conversation has moved on to unrelated work without resolving those topics. Mention that `/revdiff` starts a fresh review, and stop.

   If the hook message says the history changed, the baseline was dropped and the pane will show the full diff as a fresh session — relay that when you report the launch.

   The loop ends on its own when a pass closes without annotations, or when a pass's annotations lead to no file changes. A manual `/revdiff` always starts a fresh session over the full diff.
