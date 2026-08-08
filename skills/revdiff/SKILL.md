---
name: revdiff
description: "Launch revdiff in a floating Zellij pane so the user can annotate the current diff, then address the captured annotations. Use when the user wants to review or annotate a diff."
arguments: "[optional revdiff args: a ref, two refs, --staged, --only=<file>, ...]"
---

# revdiff review

Launch the revdiff TUI for the user, wait for their annotations, then address them.

The launcher script is `scripts/launch.sh` under this skill's base directory (stated as "Base directory for this skill" at the top of this invocation). Resolve it to an absolute path before running.

## Workflow

1. Run `<base-dir>/scripts/launch.sh $ARGUMENTS` **in the background** (`run_in_background: true`). Then **stop and return control to the user** — they are reviewing in the floating pane and may take a while. Do NOT call `TaskOutput` to wait on the result; a `<task-notification>` arrives when they close revdiff. With no arguments, revdiff auto-detects what to review (working-copy changes, last commit, or branch vs main; git, jj, and hg all supported).
2. When the notification arrives, read the task output:
   - **Nonzero exit** — launch or revdiff failure; report the error and stop.
   - **Empty stdout** — the user finished without leaving annotations; say so and stop.
   - **Otherwise** — stdout is the annotations as markdown: `## path/to/file:43 (+)` headers (`(+)` added line, `(-)` removed line, `( )` unchanged context line, no line number = file-level comment) followed by the comment text.
3. Work through the annotations in order. For each one, quote it briefly so the response maps back to what was written, then classify it:
   - **Question or discussion** (asks why, how, whether): answer it in conversation. Do not change code unless the answer implies a change and the user confirms.
   - **Change directive** (points out a bug, requests an edit): implement it, following the project's usual standards — for behavior changes covered by tests, failing test first.
4. Do not relaunch revdiff on your own initiative. This plugin's Stop hook watches the review loop: when files were changed in response to annotations, it blocks the stop and instructs you to launch another pass (step 1). In jj repos that instruction includes a baseline commit ID as the launch argument, scoping the follow-up pane to changes made since the user's last pass — pass it through verbatim. Follow-up launches also append `--description=<text>`: a brief summary of the changes made in response to the annotations, shown in the pane's info popup. The instruction offers three outcomes — pick by the state of the conversation: **launch** when the discussion topics from the annotations are settled (or there were none); **defer** (run the defer script it names, tell the user the re-review is pending) while any remain open; **end the loop** (mention `/revdiff` and stop) if the conversation has moved on to unrelated work without resolving them. If the instruction instead reports that the commit history changed, relay that to the user: the baseline was discarded and the pane shows the full diff as a fresh review session. The loop ends when a pass closes without annotations, or when a pass's annotations lead to no file changes. A manual `/revdiff` invocation always starts a fresh review session over the full diff.
