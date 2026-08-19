#!/bin/bash
# Keel PreToolUse guard for the Bash tool.
#
# Blocks exactly three destructive things and nothing else. Deliberately small: a hook that
# fires on normal development gets disabled wholesale, and then it protects nothing
# (THREAT_MODEL.md V19).
#
#   1. `rm` with BOTH recursive and force flags        -> blocked (plain `rm -r` still works)
#   2. `git push` with any force flag                  -> blocked
#   3. `git add` of a .env file (.env.example is fine) -> blocked
#
# Protocol (verified 2026-08-28, code.claude.com/docs/en/hooks; docs/RECON.md §1.5):
#   stdin  = JSON with .tool_name, .tool_input, .cwd, ...
#   exit 0 = allow, exit 2 = BLOCK the tool call, stderr is shown to the model.
# A hook exiting 2 blocks before permission rules are evaluated, so this is a hard stop that
# an `allow` rule cannot override. It is a second line of defence, not a replacement for the
# deny list in settings.json.
#
# NOTE: `timeout(1)` does not exist on this machine (docs/RECON.md §1.7), so it is not used here.

set -uo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && exit 0

block() {
  printf 'BLOCKED by Keel guard-bash hook: %s\n' "$1" >&2
  printf 'If this is genuinely required, ask the product owner to run it manually.\n' >&2
  exit 2
}

# Split the command line into subcommands on shell separators, so that a dangerous call
# hidden after `&&` or `;` is still inspected.
SUBS=$(printf '%s' "$CMD" | sed -E 's/(\|\||&&|;|\||&)/\n/g')

while IFS= read -r sub; do
  [ -z "${sub// }" ] && continue
  read -ra TOKENS <<< "$sub"
  [ ${#TOKENS[@]} -eq 0 ] && continue

  # Identify the real command, stepping over env-var assignments and harmless wrappers.
  cmd=""
  args=()
  for tok in "${TOKENS[@]}"; do
    if [ -z "$cmd" ]; then
      case "$tok" in
        env|time|nice|nohup|stdbuf|command|builtin|noglob) continue ;;
        *=*) continue ;;
        *) cmd="${tok##*/}" ;;
      esac
    else
      args+=("$tok")
    fi
  done
  [ -z "$cmd" ] && continue

  # --- 1. rm -rf ----------------------------------------------------------------------
  if [ "$cmd" = "rm" ]; then
    has_r=0; has_f=0
    for a in ${args[@]+"${args[@]}"}; do
      case "$a" in
        --recursive) has_r=1 ;;
        --force)     has_f=1 ;;
        --*)         ;;
        -*)
          [[ "$a" == *r* || "$a" == *R* ]] && has_r=1
          [[ "$a" == *f* ]] && has_f=1
          ;;
      esac
    done
    if [ "$has_r" = 1 ] && [ "$has_f" = 1 ]; then
      block "recursive+force delete (\`$sub\`). Plain \`rm -r\` is still permitted."
    fi
  fi

  # --- 2 & 3. git ---------------------------------------------------------------------
  if [ "$cmd" = "git" ]; then
    sub1="${args[0]:-}"

    if [ "$sub1" = "push" ]; then
      for a in ${args[@]+"${args[@]}"}; do
        case "$a" in
          --force|--force-with-lease|--force-if-includes|--force-with-lease=*|--mirror|--delete)
            block "force/destructive git push (\`$sub\`)." ;;
          --*) ;;
          -f)  block "force git push (\`$sub\`)." ;;
          -*f*) block "force git push (\`$sub\`)." ;;
        esac
      done
    fi

    if [ "$sub1" = "add" ]; then
      for a in ${args[@]+"${args[@]}"}; do
        case "$a" in
          .env.example|*/.env.example) continue ;;
          .env|.env.*|*/.env|*/.env.*)
            block "staging a .env file (\`$sub\`). Only .env.example may be committed." ;;
        esac
      done
    fi
  fi
done <<< "$SUBS"

exit 0
