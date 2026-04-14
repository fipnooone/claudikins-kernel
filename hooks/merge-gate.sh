#!/bin/bash
# merge-gate.sh - PreToolUse hook for Bash
# Blocks "git merge" unless review verdict exists with PASS status.
# This is the HARD GATE that prevents skipping reviews even under context drift.
#
# Matcher: Bash
# Exit codes:
#   0 - Merge allowed (review passed) or not a merge command
#   2 - Merge blocked (no review or review failed)

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract the command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Check if this is a git merge command
if ! echo "$COMMAND" | grep -qE '(^git\s+merge|[|;&]\s*git\s+merge)'; then
    # Not a merge command - allow
    exit 0
fi

# Extract branch name being merged (if present)
# Patterns: "git merge branch-name", "git merge origin/branch"
MERGE_BRANCH=$(echo "$COMMAND" | sed -nE 's/.*git[[:space:]]+merge[[:space:]]+([^[:space:];|&]+).*/\1/p')

if [ -z "$MERGE_BRANCH" ]; then
    echo "Cannot determine branch being merged. Merge blocked for safety." >&2
    exit 2
fi

# Extract task ID from branch name
# Format: execute/task-{id}-{slug}-{uuid}
TASK_ID=$(echo "$MERGE_BRANCH" | sed -nE 's/.*task-([^-]+).*/\1/p')

if [ -z "$TASK_ID" ]; then
    # Not a task branch - might be a regular merge, allow it
    # (Only task branches require review)
    exit 0
fi

# Check for review verdicts (two separate files per SKILL.md contract)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
REVIEW_DIR="$PROJECT_DIR/.claude/reviews"
SPEC_FILE="$REVIEW_DIR/spec/${TASK_ID}.json"
CODE_FILE="$REVIEW_DIR/code/${TASK_ID}.json"

if [ ! -f "$SPEC_FILE" ]; then
    echo "MERGE BLOCKED: No spec review verdict found for task ${TASK_ID}" >&2
    echo "" >&2
    echo "Required: $SPEC_FILE" >&2
    echo "" >&2
    echo "You MUST run spec-reviewer before merging." >&2
    exit 2
fi

if [ ! -f "$CODE_FILE" ]; then
    echo "MERGE BLOCKED: No code review verdict found for task ${TASK_ID}" >&2
    echo "" >&2
    echo "Required: $CODE_FILE" >&2
    echo "" >&2
    echo "You MUST run code-reviewer before merging." >&2
    exit 2
fi

# Check verdict status from separate files
SPEC_STATUS=$(jq -r '.verdict // "MISSING"' "$SPEC_FILE")
CODE_STATUS=$(jq -r '.verdict // "MISSING"' "$CODE_FILE")

if [ "$SPEC_STATUS" != "PASS" ]; then
    echo "MERGE BLOCKED: Spec review did not pass" >&2
    echo "" >&2
    echo "Spec review status: $SPEC_STATUS" >&2
    echo "Code review status: $CODE_STATUS" >&2
    echo "" >&2
    echo "Fix the spec review issues before merging." >&2
    exit 2
fi

if [ "$CODE_STATUS" != "PASS" ] && [ "$CODE_STATUS" != "CONCERNS_ACCEPTED" ]; then
    echo "MERGE BLOCKED: Code review did not pass" >&2
    echo "" >&2
    echo "Spec review status: $SPEC_STATUS" >&2
    echo "Code review status: $CODE_STATUS" >&2
    echo "" >&2
    echo "Fix the code review issues or explicitly accept concerns before merging." >&2
    exit 2
fi

# Both reviews passed - allow merge
exit 0
