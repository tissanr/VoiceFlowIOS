#!/usr/bin/env bash
# Claude Code adapter for scripts/agent-checks/run-all.sh.
# The rules themselves live in that script and docs/specs/agent-tooling.md; keep this file thin.
#
#   agent-checks-hook.sh post-edit   (PostToolUse on Edit|Write|MultiEdit)
#   agent-checks-hook.sh stop        (Stop)

set -uo pipefail

MODE="${1:-}"
INPUT="$(cat)"
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
CHECKS="$ROOT/scripts/agent-checks/run-all.sh"
[[ -x "$CHECKS" ]] || exit 0

json_field() {  # json_field <python expression on d>
  printf '%s' "$INPUT" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); v=$1
    print('' if v is None else v)
except Exception:
    print('')" 2>/dev/null
}

case "$MODE" in
  post-edit)
    FILE="$(json_field "d.get('tool_input',{}).get('file_path')")"
    [[ -z "$FILE" || ! -f "$FILE" ]] && exit 0
    case "$FILE" in "$ROOT"/*) ;; *) exit 0 ;; esac
    OUT="$(cd "$ROOT" && "$CHECKS" "$FILE" 2>&1)"; RC=$?
    if [[ $RC -ne 0 ]]; then
      { echo "Guardrail check failed for the file you just edited (see docs/specs/agent-tooling.md):"
        echo "$OUT" | grep '^ERROR'; } >&2
      exit 2
    fi
    if echo "$OUT" | grep -q 'App-Review-sensitive'; then
      python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' \
        "This file is App-Review-sensitive (permission strings, user-facing copy, entitlements, or privacy docs). Per AGENTS.md, flag the change for human review in the PR description and your final message; consider running the privacy-guard role."
    fi
    exit 0
    ;;
  stop)
    [[ "$(json_field "d.get('stop_hook_active')")" == "True" ]] && exit 0
    OUT="$(cd "$ROOT" && "$CHECKS" 2>&1)"; RC=$?
    if [[ $RC -ne 0 ]]; then
      { echo "Guardrail checks failed on this branch's changes. Fix the errors before finishing:"
        echo "$OUT" | grep -E '^(ERROR|WARNING)'; } >&2
      exit 2
    fi
    exit 0
    ;;
esac
exit 0
