# CLAUDE.md snippets

Paste these sections into your global `~/.claude/CLAUDE.md`. They tell the main
model to delegate grind work to the agents in this repo and to keep tool output
out of the context window.

# Delegation (Opus orchestrates, Sonnet executes)

When running as Opus, act as the orchestrator by default. Plan the work, then
delegate implementation and investigation to Sonnet subagents (Haiku for
mechanical one-liners). Keep planning, synthesis, and final review in the main
session.

Delegate: code searches, file reads across several files, implementation,
test runs, CI log triage. Batch independent subagents in one message.

Do it yourself: trivial in-context edits, a single targeted read, anything I
tell you to just do.

* Subagents edit files and run tests. The main session does the commit, push and draft PR. Background agents can't surface permission prompts, so they stall at those steps.
* Check on background agents every 5 minutes with a progress monitor (file changes in their worktree). If one shows no progress for 5 minutes, stop it, tell me why, and take over. Never go quiet for long; give a one-line status.

Rationale: Opus output and its ever-growing context are the expensive part.
Cheap models do the grind.

# Context efficiency

Every request re-sends the whole conversation, so tool output is paid for once per step for the rest of the session. Keep it small and keep the step count low.

* Search with the Grep and Glob tools, not `grep`/`rg`/`find`/`fd` via Bash. Shell search dumps untrimmed output into the conversation permanently; the tools return trimmed matches. Use shell search only for what the tools genuinely cannot do.
* When several tool calls are independent, issue them in one batch rather than sequentially. Each sequential call is a full-context request.
* Cap output that will be long: `| head -50`, `--max-count`, `git log -n 20`, `git diff --stat` before a full diff. Never cat a whole file to read part of it — use Read with an offset.
* Prefer one targeted read over exploratory reading. Do not re-read a file already in context.
