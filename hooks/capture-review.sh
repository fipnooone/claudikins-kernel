#!/bin/bash
# capture-review.sh - SubagentStop hook for /execute
# Captures spec-reviewer and code-reviewer output and writes session-scoped verdict files.
# These files are checked by merge-gate.sh before allowing integration.
#
# Matcher: spec-reviewer|code-reviewer
# Exit codes:
#   0 - Always (capture only, never blocks)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/execute-state.json"

# Read input JSON from stdin
INPUT=$(cat)

# Extract agent info
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // ""')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // ""')

# Only act on reviewer completions (handle both short and qualified names)
case "$AGENT_NAME" in
    spec-reviewer|claudikins-kernel:spec-reviewer)
        REVIEW_TYPE="spec"
        ;;
    code-reviewer|claudikins-kernel:code-reviewer)
        REVIEW_TYPE="code"
        ;;
    *)
        exit 0
        ;;
esac

# Get current task/session identity from execution state
if [ ! -f "$STATE_FILE" ]; then
    echo "Warning: SubagentStop for ${AGENT_NAME} but no execute-state.json" >&2
    exit 0
fi

SESSION_ID=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
SESSION_ID="${SESSION_ID:-unknown-session}"
PLAN_SOURCE=$(jq -r '.plan_source // ""' "$STATE_FILE" 2>/dev/null || echo "")
TASK_ID=$(jq -r '.current_task // ""' "$STATE_FILE" 2>/dev/null || echo "")
if [ -z "$TASK_ID" ]; then
    echo "Warning: No current_task in execute-state.json for ${AGENT_NAME}" >&2
    exit 0
fi

TASK_BRANCH=$(jq -r --arg taskId "$TASK_ID" '(.tasks // [])[] | select((.id | tostring) == $taskId) | .branch // ""' "$STATE_FILE" 2>/dev/null | head -1)
TASK_WORKTREE=$(jq -r --arg taskId "$TASK_ID" '(.tasks // [])[] | select((.id | tostring) == $taskId) | .worktree_path // ""' "$STATE_FILE" 2>/dev/null | head -1)

# Create session-scoped review directory. Bare task-id paths are unsafe because
# task IDs repeat across execute sessions and can collide with stale artifacts.
REVIEW_DIR="$CLAUDE_DIR/reviews/${SESSION_ID}/${REVIEW_TYPE}"
mkdir -p "$REVIEW_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Try to extract verdict JSON from transcript
VERDICT_OUTPUT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Look for JSON with "verdict" field (PASS/FAIL/CONCERNS)
    VERDICT_OUTPUT=$(tail -100 "$TRANSCRIPT_PATH" | \
        grep -o '{[^{}]*"verdict"[^{}]*}' | \
        tail -1 || echo "")
fi

# If no structured output found, create a minimal record
if [ -z "$VERDICT_OUTPUT" ]; then
    VERDICT_OUTPUT=$(cat <<EOF
{
  "task_id": "${TASK_ID}",
  "verdict": "UNKNOWN",
  "review_type": "${REVIEW_TYPE}",
  "note": "Verdict not captured from transcript - check manually",
  "transcript_path": "${TRANSCRIPT_PATH}",
  "captured_at": "${TIMESTAMP}"
}
EOF
)
fi

# Enrich with session/plan/task metadata so orchestrators can reject stale artifacts.
VERDICT_OUTPUT=$(echo "$VERDICT_OUTPUT" | jq \
    --arg taskId "$TASK_ID" \
    --arg sessionId "$SESSION_ID" \
    --arg planSource "$PLAN_SOURCE" \
    --arg branch "$TASK_BRANCH" \
    --arg worktree "$TASK_WORKTREE" \
    --arg agentId "$AGENT_ID" \
    --arg capturedAt "$TIMESTAMP" \
    --arg reviewType "$REVIEW_TYPE" \
    '. + {
      task_id: $taskId,
      session_id: $sessionId,
      plan_source: $planSource,
      task_branch: $branch,
      worktree_path: $worktree,
      agent_id: $agentId,
      review_type: $reviewType,
      captured_at: $capturedAt
    }' \
    2>/dev/null || echo "$VERDICT_OUTPUT")

# Backup first, then write primary (per A-6 pattern)
BACKUP_FILE="$REVIEW_DIR/.backup-${TASK_ID}-$(date +%s).json"
echo "$VERDICT_OUTPUT" > "$BACKUP_FILE"

VERDICT_FILE="$REVIEW_DIR/${TASK_ID}.json"
echo "$VERDICT_OUTPUT" > "$VERDICT_FILE"

# Extract verdict for status message
VERDICT_STATUS=$(echo "$VERDICT_OUTPUT" | jq -r '.verdict // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

# Output context for orchestrator
MSG=$(printf '%s review for task %s in session %s: %s\nVerdict saved to: %s' \
  "$REVIEW_TYPE" "$TASK_ID" "$SESSION_ID" "$VERDICT_STATUS" "$VERDICT_FILE")
MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.')
cat <<EOF
{
  "systemMessage": $MSG_ESCAPED
}
EOF

exit 0
