#!/bin/bash
#
# Claude Code status line: model, directory, git branch, context bar,
# estimated session cost, and per-turn cache hit rate.
#
# Requires: jq, git, awk (bash 3.2+; macOS and Linux).
#
# The cost and cache figures are ESTIMATES. They are computed from the main
# session transcript only, so they exclude subagent usage. The cost uses
# hard-coded per-token prices (see the session_cost block); edit them to match
# your model.

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;238m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [[ ${#branch} -gt 10 ]] && branch="${branch:0:9}…"
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream (terse: synced / Na / Nb / Na Nb / no-up)
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                sync_status="sync"
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead}a"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind}b"
            else
                sync_status="${ahead}a${behind}b"
            fi
        else
            sync_status="no-up"
        fi

        # Build terse git status string: N✎ sync
        git_status="${file_count}✎ ${sync_status}"
    fi
fi

# Get transcript path for context calculation and last message feature
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Get context window size from JSON (accurate), but calculate tokens from transcript
# (more accurate than total_input_tokens which excludes system prompt/tools/memory)
# See: github.com/anthropics/claude-code/issues/13652
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
max_k=$((max_context / 1000))

# Per-turn cache hit rate: % of this turn's input tokens that came from
# cache (cheap) vs fresh input/cache-creation (full/near-full rate).
# green = healthy, amber = partial, red = cratered (prefix rebuilt —
# model switch, TTL expiry, MCP churn...), grey = no usage data yet.
turn_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
turn_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
turn_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
turn_total=$((turn_read + turn_create + turn_input))
C_GOOD='\033[32m'
C_WARN='\033[33m'
C_BAD='\033[31m'
if [[ "$turn_total" -gt 0 ]]; then
    cache_ratio=$(awk "BEGIN{printf \"%d\", $turn_read*100/$turn_total}")
    if [[ "$cache_ratio" -ge 80 ]]; then
        cache_col="$C_GOOD"
    elif [[ "$cache_ratio" -ge 40 ]]; then
        cache_col="$C_WARN"
    else
        cache_col="$C_BAD"
    fi
else
    cache_ratio="-"
    cache_col=""
fi

# Calculate context bar from transcript
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_length=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript_path")

    # Session cost estimate (example prices: $5/MTok input, $25/MTok output, $0.50/MTok cache read,
    # $6.25/MTok cache write; adjust for your model)
    session_cost=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        map(.message.usage) |
        {
            input: (map(.input_tokens // 0) | add // 0),
            output: (map(.output_tokens // 0) | add // 0),
            cache_read: (map(.cache_read_input_tokens // 0) | add // 0),
            cache_create: (map(.cache_creation_input_tokens // 0) | add // 0)
        } |
        ((.input * 5 + .output * 25 + .cache_read * 0.5 + .cache_create * 6.25) / 1000000 * 100 | round) / 100
    ' < "$transcript_path" 2>/dev/null)
    [[ -z "$session_cost" || "$session_cost" == "null" ]] && session_cost="0"

    # 20k baseline: includes system prompt (~3k), tools (~15k), memory (~300),
    # plus ~2k for git status, env block, XML framing, and other dynamic context
    baseline=20000
    bar_width=10

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
        pct_prefix=""
    else
        # At conversation start, ~20k baseline is already loaded
        pct=$((baseline * 100 / max_context))
        pct_prefix="~"
    fi

    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}${pct_prefix}${pct}% ${max_k}k"
else
    # Transcript not available yet - show baseline estimate
    baseline=20000
    bar_width=10
    pct=$((baseline * 100 / max_context))
    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}~${pct}% ${max_k}k"
fi

# Build output: Model | Dir | Branch (uncommitted) | Context | Cost | Cache
output="${C_ACCENT}${model}${C_GRAY} | ${dir}"
[[ -n "$branch" ]] && output+=" | ${branch} ${git_status}"
output+=" | ${ctx}"
[[ -n "$session_cost" && "$session_cost" != "0" ]] && output+=" | ${C_ACCENT}\$${session_cost}${C_GRAY}"
[[ -n "$cache_ratio" && "$cache_ratio" != "-" ]] && output+=" | ${cache_col}c${cache_ratio}%${C_RESET}${C_GRAY}"
output+="${C_RESET}"

printf '%b\n' "$output"

# Get user's last message (text only, not tool results, skip unhelpful messages)
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # Calculate visible length (without ANSI codes) - 10 chars for bar + content
    plain_output="${model} | ${dir}"
    [[ -n "$branch" ]] && plain_output+=" | ${branch} ${git_status}"
    plain_output+=" | xxxxxxxxxx ${pct}% ${max_k}k"
    max_len=${#plain_output}
    last_user_msg=$(jq -rs '
        # Messages to skip (not useful as context)
        def is_unhelpful:
            startswith("[Request interrupted") or
            startswith("[Request cancelled") or
            . == "";

        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or
                (type == "array" and any(.[]; .type == "text")))] |
        reverse |
        map(.message.content |
            if type == "string" then .
            else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("\n"; " ") | gsub("  +"; " ")) |
        map(select(is_unhelpful | not)) |
        first // ""
    ' < "$transcript_path" 2>/dev/null)

    if [[ -n "$last_user_msg" ]]; then
        if [[ ${#last_user_msg} -gt $max_len ]]; then
            echo "💬 ${last_user_msg:0:$((max_len - 3))}..."
        else
            echo "💬 ${last_user_msg}"
        fi
    fi
fi