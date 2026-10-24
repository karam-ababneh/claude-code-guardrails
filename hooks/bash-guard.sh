#!/usr/bin/env bash
# PreToolUse hook for Claude Code (Bash tool).
# Turns "please be careful" into a deterministic rule: irreversible commands are
# blocked (exit 2), risky ones need confirmation ("ask"), everything else passes.
#
# Why exit 2 and not "ask": in auto mode an "ask" decision can be approved
# silently, so a guard that only asks is a logbook, not a guard.
set -u

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

LOG="${GUARD_LOG:-/dev/null}"

log() { printf '%s\t%s\t%.120s\n' "$(date +%F_%T)" "$1" "$cmd" >> "$LOG"; }

matches() { printf '%s' "$cmd" | grep -qiE "$1"; }

block() {
  log "BLOCK"
  {
    echo "BLOCKED: $1"
    echo "Before running this: state the criterion, record before-numbers, name the backup, check reversibility."
    echo "If it really has to happen, ask the human to run it themselves."
  } >&2
  exit 2
}

ask() {
  log "ASK"
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

# 1) Discarding a lockfile diff. After an install, a lockfile diff is a finding
#    (dependency drift), not noise — discarding it broke `npm ci` in a real project.
if matches 'git[[:space:]]+(checkout|restore)[[:space:]]+[^|;]*(package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?)'; then
  block "discarding a lockfile diff. Run 'npm ci' first: if it fails, the diff is the fix — commit it."
fi

# 2) SQL context: any standalone TRUNCATE is a command there, even without a semicolon.
#    Outside SQL only the narrow pattern below applies, so the CSS class `truncate` passes.
if matches '(psql|supabase|sqlite3|mysql|pgcli|\.sql([^a-z]|$))' && matches '(^|[^a-z-])truncate([^a-z-]|$)'; then
  block "irreversible SQL (TRUNCATE)"
fi

irreversible='git[[:space:]]+push[[:space:]]+[^|;]*(--force([[:space:]]|$)|-f([[:space:]]|$))|git[[:space:]]+reset[[:space:]]+--hard|drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+(table[[:space:]]+)?(only[[:space:]]+)?("[^"]+"|[a-z_][a-z0-9_.]*)[[:space:]]*(;|,|$|cascade|restart|continue)|(^|[;&|[:space:]])truncate[[:space:]]+-|mkfs|diskutil[[:space:]]+erase'
if matches "$irreversible"; then
  block "irreversible command (force push / reset --hard / DROP / TRUNCATE / mkfs / disk erase)"
fi

# 3) Recursive delete. Allowed without a prompt only in temp and build folders.
safe_rm='(/private)?/tmp/|/var/folders/|node_modules|__pycache__|\.next/|dist/|build/|coverage/'
if matches 'rm[[:space:]]+-[a-zA-Z]*[rR]'; then
  matches "$safe_rm" || block "recursive delete outside temp/build folders"
fi

# 4) `git remote -v` prints embedded access tokens (https://x-access-token:<PAT>@github.com).
#    Piping through a filter counts as deliberate.
if matches 'git[[:space:]]+remote[[:space:]]+(-v|--verbose|show([[:space:]]|$))' \
   && ! matches '\|[[:space:]]*(sed|cut|awk|grep|perl|python3?|tr)'; then
  ask "git remote -v may print an access token. Filter it: git remote -v | sed -E 's#//[^@]*@#//***@#'"
fi

# 5) Dev server against a remote backend: a dev server is harmless locally, but if
#    .env points at a hosted database it runs against real user data.
if matches '(npm|pnpm|bun|yarn)[[:space:]]+run[[:space:]]+dev|(npx[[:space:]]+)?vite[[:space:]]+dev|next[[:space:]]+dev|astro[[:space:]]+dev' \
   && grep -qsiE '^[A-Z_]*(SUPABASE_URL|DATABASE_URL|NEON|PGHOST|POSTGRES_URL)=' .env .env.local .env.production; then
  ask "dev server with a remote database in .env. Is this production data? Prefer headless verification."
fi

exit 0
