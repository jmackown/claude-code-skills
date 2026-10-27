#!/usr/bin/env bash
# List a repo's git worktrees and remove the ones that are finished.
#
# Usage: tidy.sh [--apply] [repo-path ...]   (default: the current repo)
#
# A worktree can go when it has no uncommitted or untracked files and its HEAD
# is already saved elsewhere: in its PR (any state; works with squash merges and
# deleted remote branches) or, with no PR, on a remote branch.
# Without --apply it only reports. With --apply it runs `git worktree remove`
# (never --force) on finished worktrees and `git worktree prune` for folders
# that no longer exist. Branches are left alone.
set -uo pipefail

APPLY=0
REPOS=()
for arg in "$@"; do
  case $arg in
    --apply) APPLY=1 ;;
    -h | --help) sed -n '2,10p' "$0"; exit 0 ;;
    *) REPOS+=("$arg") ;;
  esac
done
[[ ${#REPOS[@]} -gt 0 ]] || REPOS=(".")

tidy_repo() {
  local repo main
  repo=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo: $1"; return; }
  # The main worktree is always first in the list
  main=$(git -C "$repo" worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')
  echo "== $(basename "$main")"
  git -C "$main" fetch -q --prune origin 2>/dev/null

  local removed=0 kept=0 missing=0 freed_kb=0 kb path branch
  while IFS=$'\t' read -r path branch; do
    [[ $path == "$main" ]] && continue
    local short=${path/#$HOME/\~}

    if [[ ! -e $path/.git ]]; then
      printf "  %-8s %-45s %s\n" "missing" "$branch" "$short"
      missing=$((missing + 1))
      continue
    fi

    local state="-" pr="" head_oid="" changes after
    if [[ $branch != "(detached)" ]]; then
      read -r state pr head_oid < <(cd "$main" && gh pr list --head "$branch" --state all \
        --json state,number,headRefOid -q 'if length == 0 then "noPR" else .[0] | "\(.state) \(.number) \(.headRefOid)" end' 2>/dev/null)
      state=${state:-noPR}
    fi
    changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ -n $head_oid ]]; then
      # Fetch the PR's head commit if the deleted branch took it out of the local repo
      git -C "$main" cat-file -e "$head_oid^{commit}" 2>/dev/null \
        || git -C "$main" fetch -q origin "pull/$pr/head" 2>/dev/null
      after=$(git -C "$path" rev-list --count "$head_oid..HEAD" 2>/dev/null || echo "?")
    else
      # No PR: count commits that aren't on any remote branch
      after=$(git -C "$path" rev-list --count HEAD --not --remotes 2>/dev/null || echo "?")
    fi

    local action="keep"
    if [[ $changes == 0 && $after == 0 ]]; then
      action="remove"
    fi

    if [[ $action == remove ]]; then
      kb=$(du -sk "$path" 2>/dev/null | cut -f1)
      freed_kb=$((freed_kb + ${kb:-0}))
    fi

    if [[ $action == remove && $APPLY == 1 ]]; then
      if git -C "$main" worktree remove "$path" 2>/dev/null; then
        action="removed"
        removed=$((removed + 1))
      else
        action="FAILED"
        kept=$((kept + 1))
      fi
    elif [[ $action == keep ]]; then
      kept=$((kept + 1))
    else
      removed=$((removed + 1))
    fi

    printf "  %-8s %-7s changes=%-3s extra=%-3s %-45s %s\n" \
      "$action" "$state" "$changes" "$after" "$branch" "$short"
  done < <(git -C "$main" worktree list --porcelain | awk '
    /^worktree /{w=substr($0,10)}
    /^branch /{b=$2; sub("refs/heads/","",b); print w"\t"b}
    /^detached/{print w"\t(detached)"}')

  if [[ $APPLY == 1 ]]; then
    git -C "$main" worktree prune
    echo "  removed $removed ($((freed_kb / 1048576)) GB), pruned $missing missing, kept $kept"
  else
    echo "  would remove $removed ($((freed_kb / 1048576)) GB), would prune $missing missing, keeping $kept (run with --apply)"
  fi
}

for r in "${REPOS[@]}"; do tidy_repo "$r"; done
