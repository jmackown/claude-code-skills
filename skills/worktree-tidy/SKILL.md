---
name: worktree-tidy
description: List a repo's git worktrees with their PR state and remove the ones whose work is saved elsewhere (no uncommitted files, and HEAD is in its PR or on a remote branch). Use when the user says "worktree tidy", "/worktree-tidy", "clean up worktrees", "too many worktrees", or at the end of a piece of work that used worktrees.
---

# worktree-tidy

Find finished git worktrees and remove them safely. Works on the current repo, or on repo paths given as arguments.

## Rules

- Always show the dry run first. Run `--apply` only after the user has seen the list and said go.
- Never use `git worktree remove --force`, `rm -rf` on a worktree, or `git branch -D`. Anything the script keeps is the user's call.

## Steps

1. Dry run, from inside the repo or with paths:

   ```bash
   ~/.claude/skills/worktree-tidy/tidy.sh                       # current repo
   ~/.claude/skills/worktree-tidy/tidy.sh ~/code/repo-a ~/code/repo-b
   ```

   Each row shows the action, PR state, uncommitted file count (including untracked), `extra` commits, branch and path. With a PR, `extra` counts commits after the PR's last commit, so a squash-merged branch whose remote was deleted still shows 0. Without a PR, it counts commits that aren't on any remote branch.

   | Action | Meaning |
   |---|---|
   | `remove` | No uncommitted files, and HEAD is in its PR (any state) or, with no PR, on a remote branch |
   | `missing` | Registered with git, but the folder or its `.git` file is gone. `git worktree prune` clears it. |
   | `keep` | Has uncommitted files, or commits that are in neither its PR nor a remote branch, or is detached |

2. Show the user a short summary: how many would go and the space freed, how many are missing, and the `keep` rows that look stale (for example no PR and months old). Don't list every `remove` row unless asked.
3. On go, run the same command with `--apply`. A `FAILED` row means `git worktree remove` refused, usually because of a file the status check missed. Report it and leave it.
4. For `keep` rows the user wants gone, remove them one at a time with plain `git worktree remove <path>` after they confirm each.

## Notes

- The script removes worktrees only. Local branches stay, so nothing committed is lost. The `extra` check keeps any worktree with commits the PR doesn't contain.
- Ignored files (`.venv`, caches) don't count as changes, and `git worktree remove` deletes them with the folder.
- PR state comes from `gh pr list --head <branch> --state all`. A branch reused for several PRs reports the latest one.
- New worktrees go in `<repo>.worktrees/<branch>`. Claude Code agent worktrees land in `<repo>/.claude/worktrees/` and are only cleaned up automatically when the agent changed nothing, so they need this tidy too.
