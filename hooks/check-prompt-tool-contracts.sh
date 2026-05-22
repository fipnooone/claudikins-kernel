#!/bin/bash
# check-prompt-tool-contracts.sh - regression checks for prompt tool-call contracts

set -euo pipefail

ROOT="${1:-$(pwd)}"
TAXONOMY="$ROOT/agents/taxonomy-extremist.md"
OUTLINE="$ROOT/commands/outline.md"
EXECUTE="$ROOT/commands/execute.md"
CAPTURE_REVIEW="$ROOT/hooks/capture-review.sh"
CREATE_TASK_BRANCH="$ROOT/hooks/create-task-branch.sh"
MERGE_GATE="$ROOT/hooks/merge-gate.sh"
VERIFY_GATE="$ROOT/hooks/verify-gate.sh"
HOOKS_JSON="$ROOT/hooks/hooks.json"

fail() {
  echo "prompt contract check failed: $*" >&2
  exit 1
}

[ -f "$TAXONOMY" ] || fail "missing $TAXONOMY"
[ -f "$OUTLINE" ] || fail "missing $OUTLINE"
[ -f "$EXECUTE" ] || fail "missing $EXECUTE"
[ -f "$CAPTURE_REVIEW" ] || fail "missing $CAPTURE_REVIEW"
[ -f "$CREATE_TASK_BRANCH" ] || fail "missing $CREATE_TASK_BRANCH"
[ -f "$MERGE_GATE" ] || fail "missing $MERGE_GATE"
[ -f "$VERIFY_GATE" ] || fail "missing $VERIFY_GATE"
[ -f "$HOOKS_JSON" ] || fail "missing $HOOKS_JSON"

FORBIDDEN='(Glob|Grep|WebSearch)\(\{\}\)|input:[[:space:]]*\{\}'
if grep -En "$FORBIDDEN" "$TAXONOMY" "$OUTLINE"; then
  fail "found malformed empty tool-call example"
fi

grep -q 'Required fields must be non-empty before every tool call' "$TAXONOMY" || fail "taxonomy missing non-empty required-fields contract"
grep -q 'Codebase mode: start with native tools using concrete parameters' "$TAXONOMY" || fail "taxonomy missing codebase first-call guidance"
grep -q 'Glob({"path":"/repo/or/specified/root","pattern":"\*\*/\*.md"})' "$TAXONOMY" || fail "taxonomy missing valid Glob example"
grep -q 'WebSearch({"query":"Prisma migration guide 2026"})' "$TAXONOMY" || fail "taxonomy missing valid WebSearch example"
grep -q 'search_tools("specific capability")' "$TAXONOMY" || fail "taxonomy missing MCP discovery workflow"

grep -q 'Required seed inputs (fill these before spawning; do not leave blank)' "$OUTLINE" || fail "outline missing required seed inputs"
grep -q 'codebase glob patterns' "$OUTLINE" || fail "outline missing glob seed guidance"
grep -q 'docs/external web queries' "$OUTLINE" || fail "outline missing web query seed guidance"
grep -q 'Do not spawn a research agent with vague instructions only' "$OUTLINE" || fail "outline missing vague prompt ban"

grep -q 'ask exactly one interactive next-step question' "$OUTLINE" || fail "outline missing single final checkpoint contract"
grep -q 'Do not create any second next-step prompt' "$OUTLINE" || fail "outline missing duplicate next-step ban"
FINAL_NEXT_ASK_COUNT=$(grep -F -c 'question: "Plan ready. What next?"' "$OUTLINE" || true)
[ "$FINAL_NEXT_ASK_COUNT" -eq 1 ] || fail "outline should contain exactly one final next-step AskUserQuestion example, found $FINAL_NEXT_ASK_COUNT"

grep -q '../skills/shared-prompt-invariants.md' "$ROOT"/commands/*.md "$ROOT"/agents/*.md || fail "commands/agents missing shared invariant references"
if grep -R 'skills/shared-prompt-invariants.md' "$ROOT/commands" "$ROOT/agents" "$ROOT/skills" | grep -Ev '../skills/shared-prompt-invariants.md|../shared-prompt-invariants.md'; then
  fail "found non-resolving shared invariant reference"
fi

grep -q '.claude/reviews/${session_id}/spec/{task_id}.json' "$EXECUTE" || fail "execute missing session-scoped spec review artifact guidance"
grep -q 'Artifact identity matches the active execute session and plan source' "$EXECUTE" || fail "execute missing review identity check"
grep -q 'reviews/${SESSION_ID}/${REVIEW_TYPE}' "$CAPTURE_REVIEW" || fail "capture-review does not write session-scoped artifacts"
grep -q 'session_id: $sessionId' "$CAPTURE_REVIEW" || fail "capture-review missing session_id metadata"
grep -q 'plan_source: $planSource' "$CAPTURE_REVIEW" || fail "capture-review missing plan_source metadata"
grep -q 'review_artifact_matches "$candidate"' "$MERGE_GATE" || fail "merge-gate direct session path does not validate embedded artifact identity"
grep -q 'artifact_task' "$MERGE_GATE" || fail "merge-gate missing embedded task validation"
grep -q 'artifact_session' "$MERGE_GATE" || fail "merge-gate missing embedded session validation"
grep -q 'artifact_plan' "$MERGE_GATE" || fail "merge-gate missing plan identity validation"

grep -q 'missing expected task files' "$CREATE_TASK_BRANCH" || fail "create-task-branch missing expected-file validation"
grep -q 'target project files are untracked' "$CREATE_TASK_BRANCH" || fail "create-task-branch missing nested/untracked layout diagnosis"

grep -F -q '^(/verify|(/)?claudikins-kernel:verify)(\\s|$)' "$HOOKS_JSON" || fail "hooks.json missing anchored verify matcher"
grep -F -q '^(/ship|(/)?claudikins-kernel:ship)(\\s|$)' "$HOOKS_JSON" || fail "hooks.json missing anchored ship matcher"
grep -F -q '^(/outline|(/)?claudikins-kernel:outline)(\\s|$)' "$HOOKS_JSON" || fail "hooks.json missing anchored outline matcher"
grep -q '.claude/worktrees' "$VERIFY_GATE" || fail "verify-gate manifest does not exclude .claude/worktrees"
grep -q 'stale completed/pass verify state' "$VERIFY_GATE" || fail "verify-gate missing stale completed state early exit"

echo "prompt contract checks passed"
