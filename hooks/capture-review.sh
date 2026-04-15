#!/bin/bash
# capture-review.sh - SubagentStop hook for /execute
# Captures spec-reviewer and code-reviewer output and writes verdict files.
# These files are checked by merge-gate.sh before allowing git merge.
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

# Get current task ID from execution state
if [ ! -f "$STATE_FILE" ]; then
    echo "Warning: SubagentStop for ${AGENT_NAME} but no execute-state.json" >&2
    exit 0
fi

TASK_ID=$(jq -r '.current_task // ""' "$STATE_FILE" 2>/dev/null || echo "")
if [ -z "$TASK_ID" ]; then
    echo "Warning: No current_task in execute-state.json for ${AGENT_NAME}" >&2
    exit 0
fi

# Create review directory
REVIEW_DIR="$CLAUDE_DIR/reviews/${REVIEW_TYPE}"
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

# Enrich with metadata (add task_id and captured_at if not present)
VERDICT_OUTPUT=$(echo "$VERDICT_OUTPUT" | jq \
    --arg taskId "$TASK_ID" \
    --arg agentId "$AGENT_ID" \
    --arg capturedAt "$TIMESTAMP" \
    --arg reviewType "$REVIEW_TYPE" \
    '. + {task_id: $taskId, agent_id: $agentId, review_type: $reviewType, captured_at: $capturedAt}' \
    2>/dev/null || echo "$VERDICT_OUTPUT")

# Write verdict file
VERDICT_FILE="$REVIEW_DIR/${TASK_ID}.json"
echo "$VERDICT_OUTPUT" > "$VERDICT_FILE"

# Backup in case of failure (per A-6 pattern)
BACKUP_FILE="$REVIEW_DIR/.backup-${TASK_ID}-$(date +%s).json"
echo "$VERDICT_OUTPUT" > "$BACKUP_FILE"

# Extract verdict for status message
VERDICT_STATUS=$(echo "$VERDICT_OUTPUT" | jq -r '.verdict // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

# Output context for orchestrator
MSG=$(printf '%s review for task %s: %s\nVerdict saved to: %s' \
  "$REVIEW_TYPE" "$TASK_ID" "$VERDICT_STATUS" "$VERDICT_FILE")
MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.')
cat <<EOF
{
  "systemMessage": $MSG_ESCAPED
}
EOF

exit 0
