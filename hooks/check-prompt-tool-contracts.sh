#!/bin/bash
# check-prompt-tool-contracts.sh - regression checks for prompt tool-call contracts

set -euo pipefail

ROOT="${1:-$(pwd)}"
TAXONOMY="$ROOT/agents/taxonomy-extremist.md"
OUTLINE="$ROOT/commands/outline.md"

fail() {
  echo "prompt contract check failed: $*" >&2
  exit 1
}

[ -f "$TAXONOMY" ] || fail "missing $TAXONOMY"
[ -f "$OUTLINE" ] || fail "missing $OUTLINE"

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

echo "prompt contract checks passed"
