---
name: revdiff
description: "Launch revdiff in a floating Zellij pane so the user can annotate the current diff. Annotations arrive on their own as the user flushes them. Use when the user wants to review or annotate a diff."
argument-hint: "[ref] [ref2] [--staged] [--only=<file>]"
allowed-tools:
  - "Bash(${CLAUDE_SKILL_DIR}/scripts/launch.sh *)"
---

# revdiff review

Open the revdiff TUI over the current diff.

Run `${CLAUDE_SKILL_DIR}/scripts/launch.sh $ARGUMENTS` — exactly as written, since the path
is already absolute and matches this skill's `allowed-tools` rule verbatim, so rewriting it
costs a permission prompt. It returns as soon as the pane is open.

All arguments are optional and pass through to revdiff unmodified — a ref, two refs,
`--staged`, `--only=<file>`, or anything else it accepts. With no arguments, revdiff
auto-detects what to review (working-copy changes, last commit, or branch vs main; git, jj,
and hg all supported).

## After launching

Return control to the user. Don't wait on the pane or poll for annotations.

The pane is an independent process for as long as the user wants it. Each time they press
`O`, revdiff posts their annotations into this session as a message, arriving on its own
schedule — possibly interleaved with unrelated work, possibly never. Treat each one as the
user handing you review comments and respond to what it says.

After acting on a set of annotations, mention that pressing `R` in the pane reloads the diff
so they can see the changes. revdiff clears annotations on lines the reload changed and keeps
the rest, so anything they flush again is deliberately still standing.

## Annotation format

`## path/to/file:43 (+)` headers followed by the comment text, where `(+)` is an added line,
`(-)` a removed line, `( )` an unchanged context line, and no line number means a file-level
comment.
