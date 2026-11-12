#!/usr/bin/env bash
# Agent guardrail checks for VoiceFlow iOS.
#
# Agent-neutral: any coding agent, a human, or CI can run this.
# See docs/specs/agent-tooling.md for what each check enforces and why.
#
# Usage:
#   scripts/agent-checks/run-all.sh                # files changed vs. merge-base with main (+ uncommitted, untracked)
#   scripts/agent-checks/run-all.sh --base <ref>   # files changed vs. merge-base with <ref>
#   scripts/agent-checks/run-all.sh --all          # every tracked file (CI mode)
#   scripts/agent-checks/run-all.sh <file>...      # only the given files
#
# Exit codes: 0 = clean (warnings may be printed), 1 = at least one error.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "agent-checks: not inside a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

CANONICAL_APP_GROUP="group.me.tissanr.VoiceFlow.shared"
ERRORS=0
WARNINGS=0

err()  { echo "ERROR   $*"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARNING $*"; WARNINGS=$((WARNINGS + 1)); }

# ---------------------------------------------------------------------------
# Collect files
# ---------------------------------------------------------------------------
MODE="diff"
BASE_REF=""
FILES=()

if [[ $# -gt 0 ]]; then
  case "$1" in
    --all)  MODE="all" ;;
    --base) MODE="diff"; BASE_REF="${2:-}"; [[ -z "$BASE_REF" ]] && { echo "--base needs a ref" >&2; exit 1; } ;;
    -h|--help) sed -n 2,15p "$0"; exit 0 ;;
    *)      MODE="files"; FILES=("$@") ;;
  esac
fi

if [[ "$MODE" == "all" ]]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(git ls-files)
elif [[ "$MODE" == "diff" ]]; then
  if [[ -z "$BASE_REF" ]]; then
    for candidate in origin/main main; do
      git rev-parse --verify --quiet "$candidate" >/dev/null && { BASE_REF="$candidate"; break; }
    done
  fi
  MERGE_BASE="$(git merge-base HEAD "${BASE_REF:-HEAD}" 2>/dev/null || git rev-parse HEAD)"
  while IFS= read -r f; do FILES+=("$f"); done < <(
    { git diff --name-only --diff-filter=ACMR "$MERGE_BASE"
      git ls-files --others --exclude-standard; } | sort -u
  )
fi

# Keep only files that exist (deleted files have nothing to check), relative to the repo root.
EXISTING=()
for f in ${FILES[@]+"${FILES[@]}"}; do
  f="${f#"$ROOT"/}"
  [[ -f "$f" ]] && EXISTING+=("$f")
done

# ---------------------------------------------------------------------------
# Check 1: merge-conflict markers (AGENTS.md: "do not commit <<<<<<< markers")
# ---------------------------------------------------------------------------
check_conflict_markers() {
  local f="$1"
  case "$f" in *.png|*.jpg|*.jpeg|*.pdf|*.xcassets/*) return ;; esac
  if grep -nE '^(<<<<<<<|>>>>>>>)( |$)' "$f" >/dev/null 2>&1; then
    err "$f: merge-conflict marker(s) at line(s) $(grep -nE '^(<<<<<<<|>>>>>>>)( |$)' "$f" | cut -d: -f1 | paste -sd, -)"
  fi
}

# ---------------------------------------------------------------------------
# Check 2: App Group ID must be the single canonical one
# ---------------------------------------------------------------------------
check_app_group() {
  local f="$1" ids id
  case "$f" in scripts/agent-checks/*) return ;; esac
  ids="$(grep -oE 'group\.[a-z0-9-]+\.[A-Za-z0-9-]+\.[A-Za-z0-9.-]*[A-Za-z0-9]' "$f" 2>/dev/null | sort -u)" || return
  while IFS= read -r id; do
    [[ -z "$id" || "$id" == "$CANONICAL_APP_GROUP" ]] && continue
    err "$f: unexpected App Group ID '$id' (only '$CANONICAL_APP_GROUP' is allowed)"
  done <<< "$ids"
}

# ---------------------------------------------------------------------------
# Check 3: private-API / runtime-trick patterns in Swift / ObjC sources
# ---------------------------------------------------------------------------
PRIVATE_API_PATTERN='\bdlopen\(|\bdlsym\(|NSClassFromString\(|NSSelectorFromString\(|UIKeyboardImpl|UIKeyboardInputMode|_UIRemoteKeyboard|(value|setValue)\([^)]*forKey(Path)?: *"_|perform\(Selector\(\("_'
check_private_api() {
  local f="$1" hits
  case "$f" in *.swift|*.m|*.mm|*.h) ;; *) return ;; esac
  hits="$(grep -nE "$PRIVATE_API_PATTERN" "$f" 2>/dev/null | grep -v 'agent-check: allow' || true)"
  [[ -z "$hits" ]] && return
  while IFS= read -r line; do
    err "$f:${line%%:*}: possible private API / runtime trick: $(echo "${line#*:}" | sed 's/^[[:space:]]*//' | cut -c1-120)"
  done <<< "$hits"
}

# ---------------------------------------------------------------------------
# Check 4: App-Review-sensitive files -> human review flag (warning only)
# ---------------------------------------------------------------------------
is_review_sensitive() {
  case "$1" in
    */Info.plist|*.xcstrings|*.strings|*.stringsdict|*.entitlements) return 0 ;;
    docs/specs/privacy-and-app-review.md|docs/spikes/privacy-app-review-onboarding-draft.md) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Check 5: spec headers + ROADMAP registration (checks the whole docs tree)
# ---------------------------------------------------------------------------
check_specs() {
  local spec name
  for spec in docs/specs/*.md; do
    [[ -f "$spec" ]] || continue
    name="$(basename "$spec")"
    grep -qE '^> \*\*Spec status:\*\* ' "$spec"           || err "$spec: missing '> **Spec status:**' header line"
    grep -qE '^> \*\*Implementation status:\*\* ' "$spec" || err "$spec: missing '> **Implementation status:**' header line"
    grep -qE '^> \*\*Last updated:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}' "$spec" || err "$spec: missing '> **Last updated:** YYYY-MM-DD' header line"
    grep -qF "](docs/specs/$name)" ROADMAP.md || err "$spec: not registered in the ROADMAP.md Specifications table"
  done
}

# Spec changed in this diff but its 'Last updated' line did not -> warning.
check_spec_touched() {
  local f="$1"
  [[ "$MODE" == "diff" && -n "${MERGE_BASE:-}" ]] || return
  case "$f" in docs/specs/*.md) ;; *) return ;; esac
  git cat-file -e "$MERGE_BASE:$f" 2>/dev/null || return   # new spec, nothing to compare
  git diff --quiet "$MERGE_BASE" -- "$f" && return          # unchanged vs. base
  if ! git diff "$MERGE_BASE" -- "$f" | grep -qE '^\+> \*\*Last updated:\*\*'; then
    warn "$f: spec changed but '> **Last updated:**' was not bumped (also check the ROADMAP.md row)"
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
SENSITIVE=()
for f in ${EXISTING[@]+"${EXISTING[@]}"}; do
  check_conflict_markers "$f"
  check_app_group "$f"
  check_private_api "$f"
  check_spec_touched "$f"
  is_review_sensitive "$f" && SENSITIVE+=("$f")
  case "$f" in docs/specs/*.md|ROADMAP.md) DOCS_TOUCHED=1 ;; esac
done
# Explicit-file mode (used by per-edit hooks) only runs the repo-wide spec check when docs were touched.
[[ "$MODE" != "files" || -n "${DOCS_TOUCHED:-}" ]] && check_specs

if [[ ${#SENSITIVE[@]} -gt 0 && "$MODE" != "all" ]]; then
  for f in "${SENSITIVE[@]}"; do
    warn "$f: App-Review-sensitive file changed -> flag for human review in the PR description (AGENTS.md 'Do not')"
  done
fi

echo "agent-checks: ${#EXISTING[@]} file(s) checked, $ERRORS error(s), $WARNINGS warning(s)"
[[ $ERRORS -eq 0 ]]
