#!/usr/bin/env bash
# Table-driven tests for hooks/bash-guard.sh.
# Lives in a file because the guard would otherwise block the test command itself.
set -u
cd "$(dirname "$0")/.." || exit 1
GUARD="hooks/bash-guard.sh"
FAILED=0

check() {
  local name="$1" cmd="$2" expected="$3" out rc actual
  out=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$GUARD" 2>&1)
  rc=$?
  actual="pass"
  [ "$rc" -eq 2 ] && actual="block"
  printf '%s' "$out" | grep -q '"ask"' && actual="ask"
  if [ "$actual" = "$expected" ]; then
    printf '  ok    %-40s -> %s\n' "$name" "$actual"
  else
    printf '  FAIL  %-40s -> %s (expected %s)\n' "$name" "$actual" "$expected"
    FAILED=$((FAILED + 1))
  fi
}

echo "== must block =="
check "recursive delete in home"        'rm -rf ~/projects'                   block
check "hard reset"                      'git reset --hard origin/main'        block
check "force push"                      'git push --force origin main'        block
check "force push short flag"           'git push -f origin main'             block
check "drop table"                      'psql -c "drop table users"'          block
check "truncate in SQL, no semicolon"   'psql -c "truncate leads"'            block
check "disk erase"                      'diskutil erase disk2'                block
check "discard lockfile diff"           'git checkout -- package-lock.json'   block

echo "== must ask =="
check "remote -v unfiltered"            'git remote -v'                       ask

echo "== must pass =="
check "recursive delete in /tmp"        'rm -rf /tmp/test-dir'                pass
check "remove node_modules"             'rm -rf node_modules'                 pass
check "remove build output"             'rm -rf dist/'                        pass
check "remote -v filtered"              "git remote -v | sed -E 's#//[^@]*@#//***@#'" pass
check "tailwind class truncate"         'echo "<p class=\"truncate mt-1\">"'  pass
check "normal push"                     'git push origin main'                pass
check "list files"                      'ls -la'                              pass
check "delete single file"              'rm /tmp/file.txt'                    pass

echo "== dev server against remote DB =="
TMP=$(mktemp -d)
trap 'rm -r "$TMP"' EXIT
( cd "$TMP" && printf 'DATABASE_URL=postgres://db.example.com/app\n' > .env )
GUARD="$PWD/$GUARD"
pushd "$TMP" >/dev/null || exit 1
check "dev server, remote DB in .env"   'npm run dev'                         ask
popd >/dev/null || exit 1
check "dev server, no .env"             'npm run dev'                         pass

echo
if [ "$FAILED" -eq 0 ]; then echo "RESULT: all cases correct"; else echo "RESULT: $FAILED failed"; fi
exit "$FAILED"
