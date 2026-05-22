#!/bin/bash
# merge-gate.sh - PreToolUse hook for Bash
# Blocks "git merge" unless session-scoped review verdicts exist with PASS status.
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

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/execute-state.json"
REVIEW_ROOT="$CLAUDE_DIR/reviews"
SESSION_ID=""
PLAN_SOURCE=""

if [ -f "$STATE_FILE" ]; then
    SESSION_ID=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
    PLAN_SOURCE=$(jq -r '.plan_source // ""' "$STATE_FILE" 2>/dev/null || echo "")
fi

review_artifact_matches() {
    local candidate="$1"
    local review_type="$2"
    local task_id="$3"

    [ -f "$candidate" ] || return 1

    local artifact_task artifact_session artifact_plan artifact_type
    artifact_task=$(jq -r '.task_id // ""' "$candidate" 2>/dev/null || echo "")
    artifact_session=$(jq -r '.session_id // ""' "$candidate" 2>/dev/null || echo "")
    artifact_plan=$(jq -r '.plan_source // ""' "$candidate" 2>/dev/null || echo "")
    artifact_type=$(jq -r '.review_type // ""' "$candidate" 2>/dev/null || echo "")

    [ "$artifact_task" = "$task_id" ] || return 1
    [ -z "$artifact_type" ] || [ "$artifact_type" = "$review_type" ] || return 1
    [ -z "$SESSION_ID" ] || [ "$artifact_session" = "$SESSION_ID" ] || return 1
    [ -z "$PLAN_SOURCE" ] || [ "$artifact_plan" = "$PLAN_SOURCE" ] || return 1

    return 0
}

find_review_file() {
    local review_type="$1"
    local task_id="$2"
    local candidate=""

    if [ -n "$SESSION_ID" ]; then
        candidate="$REVIEW_ROOT/$SESSION_ID/$review_type/${task_id}.json"
        if review_artifact_matches "$candidate" "$review_type" "$task_id"; then
            echo "$candidate"
            return 0
        fi
    fi

    # Fallback for manual recovery artifacts: accept any artifact only if its
    # embedded identity matches the active task and, when known, active session/plan.
    while IFS= read -r candidate; do
        [ -z "$candidate" ] && continue
        if review_artifact_matches "$candidate" "$review_type" "$task_id"; then
            echo "$candidate"
            return 0
        fi
    done < <(find "$REVIEW_ROOT" -path "*/$review_type/${task_id}.json" -type f 2>/dev/null | sort)

    return 1
}

SPEC_FILE=$(find_review_file "spec" "$TASK_ID" || true)
CODE_FILE=$(find_review_file "code" "$TASK_ID" || true)

if [ -z "$SPEC_FILE" ]; then
    echo "MERGE BLOCKED: No session-matching spec review verdict found for task ${TASK_ID}" >&2
    echo "" >&2
    if [ -n "$SESSION_ID" ]; then
        echo "Required: $REVIEW_ROOT/$SESSION_ID/spec/${TASK_ID}.json" >&2
    else
        echo "Required: $REVIEW_ROOT/<session_id>/spec/${TASK_ID}.json with matching task_id/session_id/plan_source" >&2
    fi
    echo "" >&2
    echo "You MUST run spec-reviewer before merging." >&2
    exit 2
fi

if [ -z "$CODE_FILE" ]; then
    echo "MERGE BLOCKED: No session-matching code review verdict found for task ${TASK_ID}" >&2
    echo "" >&2
    if [ -n "$SESSION_ID" ]; then
        echo "Required: $REVIEW_ROOT/$SESSION_ID/code/${TASK_ID}.json" >&2
    else
        echo "Required: $REVIEW_ROOT/<session_id>/code/${TASK_ID}.json with matching task_id/session_id/plan_source" >&2
    fi
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
    echo "Spec review file: $SPEC_FILE" >&2
    echo "Code review file: $CODE_FILE" >&2
    echo "Spec review status: $SPEC_STATUS" >&2
    echo "Code review status: $CODE_STATUS" >&2
    echo "" >&2
    echo "Fix the spec review issues before merging." >&2
    exit 2
fi

if [ "$CODE_STATUS" != "PASS" ] && [ "$CODE_STATUS" != "CONCERNS_ACCEPTED" ]; then
    echo "MERGE BLOCKED: Code review did not pass" >&2
    echo "" >&2
    echo "Spec review file: $SPEC_FILE" >&2
    echo "Code review file: $CODE_FILE" >&2
    echo "Spec review status: $SPEC_STATUS" >&2
    echo "Code review status: $CODE_STATUS" >&2
    echo "" >&2
    echo "Fix the code review issues or explicitly accept concerns before merging." >&2
    exit 2
fi

# Both reviews passed - allow merge
exit 0
