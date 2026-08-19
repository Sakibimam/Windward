#!/bin/bash
# Exercises .claude/hooks/guard-bash.sh with crafted PreToolUse payloads.
# Each case asserts the hook's exit code: 0 = allow, 2 = block.
HOOK="$1"
pass=0; fail=0

run() {
  local expect="$1"; shift
  local desc="$1"; shift
  local cmd="$1"
  local payload out code
  payload=$(jq -nc --arg c "$cmd" '{session_id:"test",cwd:".",permission_mode:"default",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},tool_use_id:"t1"}')
  out=$(printf '%s' "$payload" | "$HOOK" 2>&1); code=$?
  local got="ALLOW"; [ "$code" = 2 ] && got="BLOCK"
  local mark="ok  "
  if [ "$got" != "$expect" ]; then mark="FAIL"; fail=$((fail+1)); else pass=$((pass+1)); fi
  printf '%s  expect=%-5s got=%-5s exit=%s  %s\n' "$mark" "$expect" "$got" "$code" "$desc"
  printf '        $ %s\n' "$cmd"
  if [ -n "$out" ]; then printf '        > %s\n' "$(printf '%s' "$out" | head -1)"; fi
}

D="-rf"; DR="-r"; DF="-f"

echo "### Check 1 - rm recursive+force"
run BLOCK "rm -rf"                          "rm $D out"
run BLOCK "rm -fr (flag order swapped)"     "rm -fr out"
run BLOCK "rm -r -f (split flags)"          "rm $DR $DF out"
run BLOCK "rm -Rf (capital R)"              "rm -Rf out"
run BLOCK "rm --recursive --force"          "rm --recursive --force out"
run BLOCK "hidden after &&"                 "forge build && rm $D out"
run BLOCK "hidden after ;"                  "echo hi ; rm $D /tmp/x"
run BLOCK "behind nohup wrapper"            "nohup rm $D out"
run BLOCK "absolute path target"            "rm $D /"
run ALLOW "rm -r without force"             "rm $DR out"
run ALLOW "rm -f single file"               "rm $DF notes.txt"
run ALLOW "plain rm"                        "rm cache/x"
run ALLOW "unrelated --force flag"          "forge build --force"

echo
echo "### Check 2 - force git push"
run BLOCK "git push --force"                "git push --force origin main"
run BLOCK "git push -f"                     "git push $DF origin main"
run BLOCK "git push --force-with-lease"     "git push --force-with-lease"
run BLOCK "git push --force-with-lease=ref" "git push --force-with-lease=main origin"
run BLOCK "git push --mirror"               "git push --mirror origin"
run BLOCK "git push --delete"               "git push --delete origin main"
run BLOCK "force push after &&"             "forge test && git push $DF"
run ALLOW "ordinary git push"               "git push origin main"
run ALLOW "git push -u (not force)"         "git push -u origin main"
run ALLOW "git log with %f format"          "git log --format=%f"

echo
echo "### Check 3 - staging .env"
run BLOCK "git add .env"                    "git add .env"
run BLOCK "git add .env.local"              "git add .env.local"
run BLOCK "git add nested .env"             "git add config/.env"
run BLOCK "git add .env among other paths"  "git add src/Foo.sol .env"
run ALLOW "git add .env.example"            "git add .env.example"
run ALLOW "git add -A"                      "git add -A"
run ALLOW "git add a source file"           "git add src/Keel.sol"

echo
echo "### Non-interference - ordinary development must pass untouched"
run ALLOW "forge build"                     "forge build"
run ALLOW "forge test verbose"              "forge test -vvv"
run ALLOW "chained build+test"              "forge build && forge test"
run ALLOW "git commit"                      "git commit -m 'feat: add guard'"
run ALLOW "cast call"                       "cast call 0x1f98400000000000000000000000000000000004 'owner()(address)'"
run ALLOW "grep pipeline"                   "grep -r BEFORE_SWAP lib/v4-core/src | head -5"
run ALLOW "forge snapshot"                  "forge snapshot"
run ALLOW "empty command field"             ""

echo
printf 'TOTAL: %d passed, %d failed\n' "$pass" "$fail"
exit "$fail"
