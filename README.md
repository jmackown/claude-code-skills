# claude-code-skills

This repo is the delegation kit from the Substack post [Four ways I make my Claude budget last](https://theotherjenai.substack.com/p/four-ways-i-make-my-claude-budget), plus a few standalone skills, agents, and a command I use alongside it. The kit lets an expensive main model plan and review while cheaper subagents do the searching, coding, and test running.

Everything here is plain Markdown, JSON, and one shell script. Copy what you want into your Claude Code config.

## What's in the repo

### Delegation kit

| Name | Type | What it does |
|---|---|---|
| `haiku-worker` | Agent (Haiku) | Runs simple, unambiguous, low-stakes tasks such as typos, renames, and single-file mechanical edits. |
| `sonnet-worker` | Agent (Sonnet) | Implements well-scoped tasks with a clear spec, such as tests, small features, and boilerplate. |
| `code-locator` | Agent (Sonnet) | Read-only sweep that returns a file:line map of where things live. It never edits or proposes fixes. |
| `test-runner` | Agent (Sonnet) | Runs tests, lint, typecheck, or build commands and reports pass or fail with a triaged failure summary. It does not fix anything. |
| `basic-tasks` | Agent (Sonnet) | Handles bounded, well-specified mechanical work such as file lookups, single-file edits, test runs, and focused research. It stops and says so if the task needs cross-file judgement. |
| `CLAUDE.snippets.md` | Config snippet | Two sections for your global `CLAUDE.md`: delegate grind work to subagents, and keep tool output out of the context window. |
| `settings.example.json` | Config example | Example `settings.json` entries: prompt caching environment variables, a default subagent model, and the status line command. |
| `statusline/context-bar.sh` | Script | Status line showing model, directory, git branch, a context bar, estimated session cost, and per-turn cache hit rate. |

### Standalone skills and agents

| Name | Type | What it does |
|---|---|---|
| `handover` | Skill | Writes or refreshes an agent-facing `HANDOVER.md` so a future session can resume in-progress work. |
| `pre-flight` | Command | Runs ruff lint and format checks, a safety scan, and the matching tests on changed Python files only. |
| `adversarial-reviewer` | Agent (Haiku) | Wraps the OpenAI `codex review` CLI to get an independent critique of a diff, branch, or commit, then summarises it. |
| `senior-dev-reviewer` | Agent (Sonnet) | Reviews code for production readiness, scalability, security, and maintainability. |
| `codebase-overview` | Skill | Inspects a repo and writes a grounded `CODEBASE_OVERVIEW.md` for humans and future agents. |
| `claudit` | Skill | Runs a read-only audit of your machine and Claude Code setup (tools, MCP servers, hooks, permissions, skills, `CLAUDE.md`, memory), ranks what to fix, and compares each run with the last one. |
| `vuln-scan` | Skill | Scans a uv project's Python dependencies (pip-audit) and Docker image (Trivy), cross-checks open Dependabot alerts, and reports which findings are actually reachable. |
| `worktree-tidy` | Skill | Lists a repo's git worktrees with their PR state and removes the ones whose work is already saved in a PR or on a remote branch. |

The cost and cache figures in `context-bar.sh` are estimates and exclude subagent usage.

## Install

You can install into your user config (`~/.claude/`) or into a single project (`.claude/` at the project root). The paths below use the user config. For a project install, swap `~/.claude` for `<project>/.claude`.

1. Copy the skills to `~/.claude/skills/`.
2. Copy the agents to `~/.claude/agents/`.
3. Copy the command to `~/.claude/commands/`.
4. Copy `statusline/context-bar.sh` to `~/.claude/scripts/` and make it executable.
5. Merge `settings.example.json` into `~/.claude/settings.json`. Merge the keys. Do not overwrite your existing file.
6. Paste the sections of `CLAUDE.snippets.md` into `~/.claude/CLAUDE.md`.

```sh
mkdir -p ~/.claude/skills ~/.claude/agents ~/.claude/commands ~/.claude/scripts
cp -R skills/* ~/.claude/skills/
cp agents/*.md ~/.claude/agents/
cp commands/*.md ~/.claude/commands/
cp statusline/context-bar.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/context-bar.sh
```

Steps 5 and 6 are manual so that you keep your existing settings and instructions. Skip any part you don't want. For example, skip step 5 if you don't want the status line.

## How to use

### Delegation

With `CLAUDE.snippets.md` in place, the main model acts as the orchestrator. It plans the work, then sends searches, implementation, and test runs to subagents. Independent subagents run in one batch. The main model keeps planning, synthesis, and final review.

Delegation works best when each subagent gets a self-contained brief: the goal, the files in scope, what to return, and when to stop. Ask for compact results (findings, changed files, commands run) and have the main model review them rather than pass them on unread.

The workers follow an escalation convention. If a task turns out to be above a worker's level, the worker stops and replies starting with `ABOVE MY LEVEL:` and one paragraph on why. Treat that as a success condition, not a failure. The orchestrator then hands the task to the next tier up or does it itself.

Pick the agent by task:

- `code-locator` to find where something lives before a change.
- `test-runner` to run a verification command and read the output.
- `haiku-worker` for mechanical single-file edits.
- `sonnet-worker` for well-scoped implementation.
- `basic-tasks` for bounded lookups, single-file edits, test runs, and focused research.

### Standalone skills and commands

- `handover`: say "write a handover" when you pause multi-session work. At the start of a later session, ask Claude to read the existing `HANDOVER.md`.
- `pre-flight`: run `/pre-flight` before committing. It checks changed files only.
- `adversarial-reviewer`: ask for a review with an explicit scope, such as "review the unstaged changes" or "review main...HEAD".
- `senior-dev-reviewer`: ask for a review after a significant change.
- `codebase-overview`: ask Claude to create or update the repo's codebase overview.
- `claudit`: run `/claudit` or say "audit my setup". The first run asks where to save reports. Later runs compare against the previous report, so rerun it every few weeks to catch drift.

## Requirements

- Claude Code.
- `jq`, `git`, and `awk` for `statusline/context-bar.sh`.
- The OpenAI Codex CLI (`codex`) for `adversarial-reviewer`. If `codex` is missing, the agent returns the error and does not attempt a review itself.
- `uv` and `ruff` for `pre-flight`, which runs `uv run ruff` and `uv run pytest`.

## Credits

`claudit` was inspired by [Claude Code told me what tools it needs to work faster](https://sderosiaux.substack.com/p/claude-code-told-me-what-tools-it) by Stéphane Derosiaux.

## Licence

MIT. See [LICENSE](LICENSE).
