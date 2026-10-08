---
name: handover
description: Write or refresh an agent-facing HANDOVER.md in the repo so a future AI session can resume in-progress work cold — current step, agreed decisions with rationale, code map, next actions, blockers, risks and constraints. Use when the user says "write a handover", "handover doc", "so I know where I was", "so I can pick this up later", "write it up for future me/agents", or is pausing multi-session work. Optimised for agents, not humans. Also use at the start of a session when a HANDOVER.md exists for the work being resumed.
---

# handover

Write a dense, verified, agent-facing handover doc into the repo, next to the work. The user does not read it. A future agent reads it, then summarises it for the user.

This is not a knowledge base. Durable knowledge for humans belongs in your own notes or docs. A handover is working state that belongs to the branch and ships with the code.

## Where it goes

- Put it next to the work: `<package-or-feature-dir>/HANDOVER.md`. Use the repo root only if the work spans the whole repo.
- If a `HANDOVER.md` already exists for this work, update it in place.
  - Rewrite the state sections: the TL;DR, next actions and the commit log.
  - Keep the decisions, adding new ones and marking superseded ones.
  - Never append a second dated copy.
- Add one line to the nearest README: `AI agents resuming this work: read HANDOVER.md first.` Skip it if a pointer already exists.
- If the work has a plan doc, link it and treat the plan as the source of truth for step order. The handover records where you are in the plan; it doesn't duplicate the plan.

## Before writing: gather and verify

Delegate the gathering to a cheap subagent when it spans several files. Collect:

- Branch, worktree path, HEAD SHA, and whether the branch is pushed (`git rev-list --left-right --count <branch>...origin/<branch>`).
- `git log --oneline` for the branch's own commits.
- Uncommitted files.
- Test, typecheck and build status. Run them; don't assume.
- File paths and line references for every code claim.

**Verify every factual claim, or mark it unverified.** A wrong handover is worse than none, because the next agent trusts it. Where you couldn't check something, write `UNVERIFIED:` and say how to check it.

## Structure

Use these sections, in this order. Drop a section only if it's genuinely empty.

```markdown
# HANDOVER: <work name> (agent-facing)

Audience: AI agents resuming this work. Dense by design. Last updated YYYY-MM-DD at <short SHA>.
The user will not read this file; summarise from it when they return.

## TL;DR state
- Goal (one line), branch, worktree path, pushed or not.
- Plan doc path, if any.
- Done: <steps>. Current step: <step>, **bold the blocker** and who it's blocked on.
- What has and hasn't been verified end to end.

## Next actions, in order
Numbered, concrete, with commands. Include expected failure risks for the next run.

## Agreed decisions (do not re-litigate)
One bullet per decision, giving the decision, the reason, and the user's own words where they were telling. Mark any that are still proposed.

## Code map
Table: file | role (with line refs) | fate (keep, replace or drop). Include dependency gotchas.

## Source of truth for <remaining work>
Table mapping each outstanding feature or task to where it's defined now (file:line) and which step does it.
Related docs, with paths and tracked or untracked status.

## Why (motivation)
Short, so a future agent doesn't undo the point of the work.

## Implementation notes for upcoming steps
Non-obvious gotchas, open questions, and things to confirm before building.

## Constraints and preferences
Git rules, commit style, things the user said not to do. Only what applies to this work.

## Commit log on this branch (newest first)
SHA plus a one-line summary.
```

## Writing rules

- Agent-optimised:
  - Dense bullets and tables.
  - Absolute paths, SHAs, line refs and exact commands.
  - No narrative and no pleasantries.
- Record decisions with their rationale. A bare decision gets re-litigated.
- Separate what is decided, what is proposed, and what is open.
- Name what is blocked on the user, as opposed to what an agent can do alone.
- Convert relative dates to absolute ones.
- Never include secrets, tokens or private keys. Env var names and placeholder values are fine.

## Committing

- A handover is a Git write, so ask before committing unless the user already asked for the commit in this request.
- Commit it on its own (`docs(<scope>): add/refresh handover notes`), not bundled with code changes.
- Never push without asking.

## When resuming from a handover

1. Read `HANDOVER.md` and the plan it links.
2. Check that it's still current: compare its SHA and commit log with `git log`, and check for new uncommitted files.
3. Tell the user in a few lines where things stand and what's next. Flag anything that has drifted from the doc.
4. Refresh the doc at the end of the session.
