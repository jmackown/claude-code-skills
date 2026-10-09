---
name: claudit
description: Run a read-only health audit of this machine and the Claude Code setup (command-line tools, MCP servers, hooks, permissions, skills, CLAUDE.md, memory), compare it with the previous audit, and save a dated report. Use when the user says "claudit", "/claudit", "audit my setup", "audit my machine", "what tools are you missing", or asks whether their Claude Code setup is in good shape.
---

# claudit

Audit the machine and the Claude Code setup, compare the result with the last audit, and save a dated report. Make no changes to anything except the new report file.

## Rules

- Read-only: no installs, no config edits, no auth flows, no git writes.
- Never print a secret. If a credential sits in plain text, report its file and key, and redact the value.
- Delegate the scanning. Run the two subagents in step 2 in parallel on a cheaper model, for example a Sonnet worker agent. Keep combining and ranking the results in the main session.
- Follow the writing style in the user's `CLAUDE.md`, if they have one.

## Where reports live

Use the folder the user has chosen for audit reports. If they haven't chosen one, ask once and suggest `~/claudit-reports/`.

- Each run writes `YYYY-MM-DD claudit results.md`. If that date already exists, add `-2`.
- Never edit or delete earlier reports.

## Steps

### 1. Load the baseline

Find the most recent `* claudit results.md` in the reports folder and read it. Note every unchecked `- [ ]` item, every item marked as a decision to keep something as it is, and every tool in the missing-tools table. If there is no previous report, say so and skip the comparison in step 4.

### 2. Scan in parallel

Send both subagents in one message. Tell each one: read-only, keep command output small (`| head`, `--version`), redact secrets, and finish with MISSING, BROKEN and REDUNDANT lists.

**Subagent A: command-line tooling.** Check:

- **Core tools:** `git`, `gh` (`gh auth status`), `rg`, `fd`, `fzf`, `jq`, `yq`, `ast-grep`, `semgrep`, `shellcheck`, `shfmt`, database clients, and `docker` (is the daemon up?).
- **Languages:** every `python3` and `node` on `PATH` and which one wins, version managers (`uv`, `pyenv`, `volta`, `nvm`, `fnm`), and linters and type checkers with versions. Flag anything more than a year old, and global installs that bypass per-project environments.
- **Language servers** that Claude Code's LSP support can use, such as `pyright`, `typescript-language-server`, `gopls` and `rust-analyzer`.
- **Cloud CLIs** the user relies on, and whether they're logged in, without printing tokens.
- **Package manager health,** for example `brew doctor 2>&1 | head -40` and the number of outdated packages.
- **`PATH`:**
  - Duplicates, missing directories, literal `~` entries, and files instead of directories.
  - Suspicious lines in the shell startup files.
  - Secrets exported in plain text. Report the variable name and file, never the value.
- **Redundancy:** the same tool installed by several package managers.

**Subagent B: Claude Code configuration.** Check:

- **Version:** `claude --version`.
- **MCP servers:**
  - Inspect `~/.claude.json` (`.mcpServers` and the project-level `mcpServers`) with `jq`. Never `cat` the file.
  - Check any `.mcp.json` files in the user's main code folders.
  - For each server, give the transport and target. Check that each stdio command exists.
  - Flag literal credentials in headers or env, as opposed to `${VAR}` references.
  - Report which servers this session shows as failed or needing authentication. The main session passes that list in from its system context.
- **Hooks** in `~/.claude/settings.json`, plus the hooks of enabled plugins:
  - The event, matcher and command for each one.
  - Whether each script exists, and how many processes start per tool call.
  - Any network calls.
- **Permissions:**
  - `defaultMode`, and the sizes of the allow, deny and ask lists.
  - Allow rules that are too broad (for example `gh *`).
  - Deny rules that are easy to bypass.
  - Read-only commands and MCP tools that still prompt.
  - Rules that contradict the user's `CLAUDE.md`.
- **Plugins and marketplaces:**
  - Enabled plugins, disabled-but-installed plugins, and marketplaces with nothing installed.
  - Whether each marketplace can refresh.
- **Skills, agents and commands:**
  - List what is in `~/.claude/skills`, `~/.claude/agents` and `~/.claude/commands`.
  - Flag duplicates of plugin skills or agents.
  - Check every path or command referenced in a `SKILL.md` or command file, and report the ones that are missing.
- **`CLAUDE.md` files:** `~/.claude/CLAUDE.md` and anything it imports.
  - Their size in bytes.
  - Instructions that name tools absent from this session. Compare them with the session's real tool list, which the main session passes in.
  - Rules that contradict a skill or another rule.
- **Auto-memory:** check `~/.claude/projects/*/memory/`, and flag memories that point at dead commands or paths.
- **Settings env vars:** names only, and whether any conflict.
- **Disk:** `du -sh` of `~/.claude/projects` and `~/.claude/plugins`, and the number of backup files in `~/.claude`.

### 3. Rank

Merge both reports into four priorities:

1. **Blocks Claude or carries risk:** exposed secrets, failing servers, unauthenticated connectors that skills depend on, instructions that point at missing tools, and broken skill dependencies.
2. **Costs time on every task:** permission friction, outdated type checkers or language servers, and hook overhead.
3. **Missing tools:** a table of each tool and why it helps Claude.
4. **Redundancy and cleanup.**

Also give a short "What works" list.

### 4. Compare with the baseline

Classify each item from the previous report:

- **Fixed:** now absent or working. Say how you confirmed it.
- **Still open:** carry it forward as `- [ ]`, with the date it was first seen.
- **New:** not in the previous report.
- **Accepted as is:** the user decided to keep something as it is. List it with the date of the decision. Don't raise it as a problem again unless it has got materially worse, for example a new security issue.

### 5. Write the report

Save it to the reports folder with this structure:

- Frontmatter: `date`, `type: audit`, `previous: <filename>`.
- A one-line headline.
- A "Changes since last audit" section with counts and items for Fixed, Still open, New and Accepted as is.
- Priorities 1 to 4, using `- [ ]` checkboxes.
- What works.

### 6. Report in chat

Give the user, briefly:

- The headline.
- The Fixed, Still open and New counts.
- The top three actions.
- The report's path.

Don't paste the full report.

## Fixing things

The audit itself changes nothing. When the user wants to work through the results, take one item at a time:

1. Investigate the item and propose a fix.
2. Wait for approval.
3. Make the change, verify it, and tick the item in the report with the date and what was done.

Prefer reversible changes. For example, move files to the system Trash instead of deleting them, and check what depends on a package before removing it.
