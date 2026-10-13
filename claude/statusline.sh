#!/bin/bash
# Claude Code status line:
# 🤖 model effort 🧠 ctx% cache 📁 repo-link 🌿 branch +staged ~modified 💰 rate limits
input=$(cat)

eval "$(echo "$input" | jq -r '@sh "
MODEL=\(.model.display_name // "")
EFFORT=\(.effort.level // "")
CTX=\(.context_window.used_percentage // 0)
CACHE_WARM=\(.prompt_cache.warm | if . == null then "" else tostring end)
HIT_RATIO=\(.prompt_cache.hit_ratio // "")
DIR=\(.workspace.current_dir // .cwd // "")
SESSION_ID=\(.session_id // "default")
FIVE_H=\(.rate_limits.five_hour.used_percentage // "")
WEEK=\(.rate_limits.seven_day.used_percentage // "")
SPEND_PCT=\(.rate_limits.spend_limit.used_percentage // "")
SPEND_USD=\(.rate_limits.spend_limit | if .used_usd? != null then "$\(.used_usd) / $\(.limit_usd)" else "" end)
"')"

GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# Cache git info per session; refresh every 5s or when the directory changes
CACHE_FILE="/tmp/statusline-git-cache-$SESSION_ID"
CACHE_MAX_AGE=5  # seconds
SEP=$'\x1f'

cache_is_stale() {
    [ ! -f "$CACHE_FILE" ] || \
    [ "$(head -n1 "$CACHE_FILE")" != "$DIR" ] || \
    [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale; then
    if git -C "$DIR" --no-optional-locks rev-parse --git-dir > /dev/null 2>&1; then
        IN_REPO=1
        BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
        [ -z "$BRANCH" ] && BRANCH=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null)
        STAGED=$(git -C "$DIR" --no-optional-locks diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        MODIFIED=$(git -C "$DIR" --no-optional-locks diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        # Convert git SSH URL to HTTPS
        REMOTE=$(git -C "$DIR" remote get-url origin 2>/dev/null | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
        TOPLEVEL=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
    else
        IN_REPO=0
    fi
    printf '%s\n%s\n' "$DIR" "$IN_REPO$SEP$BRANCH$SEP$STAGED$SEP$MODIFIED$SEP$REMOTE$SEP$TOPLEVEL" > "$CACHE_FILE"
fi

IFS="$SEP" read -r IN_REPO BRANCH STAGED MODIFIED REMOTE TOPLEVEL < <(sed -n 2p "$CACHE_FILE")

# 🤖 model + effort
case "$EFFORT" in
  medium) EFFORT=med ;;
  low) EFFORT=lo ;;
  high) EFFORT=hi ;;
  xhigh) EFFORT=xhi ;;
esac
OUT="🤖 $MODEL${EFFORT:+ 💪 $EFFORT}"

# 🧠 context + prompt cache
OUT="$OUT 🧠 $(printf '%.0f' "$CTX")%"
if [ -n "$CACHE_WARM" ]; then
    if [ "$CACHE_WARM" = "true" ]; then CACHE="🔥"; else CACHE="🧊"; fi
    [ -n "$HIT_RATIO" ] && CACHE="$CACHE $(awk -v r="$HIT_RATIO" 'BEGIN { printf "%.0f", r * 100 }')% hit"
    OUT="$OUT $CACHE"
fi

# 📁 repo link + 🌿 git status
if [ "$IN_REPO" = "1" ]; then
    if [ -n "$REMOTE" ]; then
        # OSC 8 format: \e]8;;URL\a then TEXT then \e]8;;\a
        OUT="$OUT 📁 \e]8;;${REMOTE}\a$(basename "$REMOTE")\e]8;;\a"
    else
        OUT="$OUT 📁 $(basename "$TOPLEVEL")"
    fi
    GIT_STATUS=""
    [ "${STAGED:-0}" -gt 0 ] && GIT_STATUS="${GREEN}+${STAGED}${RESET}"
    [ "${MODIFIED:-0}" -gt 0 ] && GIT_STATUS="${GIT_STATUS}${YELLOW}~${MODIFIED}${RESET}"
    OUT="$OUT 🌿 $BRANCH${GIT_STATUS:+ $GIT_STATUS}"
else
    OUT="$OUT 📁 no repo"
fi

# 💰 rate limits (5h/7d shown as quota remaining)
remaining() { awk -v u="$1" 'BEGIN { r = 100 - u; if (r < 0) r = 0; printf "%.0f", r }'; }
LIMITS=""
[ -n "$FIVE_H" ] && LIMITS="5h: $(remaining "$FIVE_H")%"
[ -n "$WEEK" ] && LIMITS="${LIMITS:+$LIMITS }7d: $(remaining "$WEEK")%"
[ -n "$SPEND_PCT" ] && LIMITS="${LIMITS:+$LIMITS }spend: ${SPEND_USD:-$(printf '%.0f' "$SPEND_PCT")%}"
[ -n "$LIMITS" ] && OUT="$OUT 📈 $LIMITS"

printf '%b\n' "$OUT"
