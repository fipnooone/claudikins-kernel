#!/bin/bash
# capture-research.sh - SubagentStop hook for claudikins-kernel
# Captures and validates taxonomy-extremist research output.

set -euo pipefail

trap 'echo "capture-research.sh failed at line $LINENO" >&2; exit 1' ERR

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
RESEARCH_DIR="$CLAUDE_DIR/agent-outputs/research"
PLAN_STATE="$CLAUDE_DIR/plan-state.json"

INPUT=$(cat)

AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // .subagent_type // .agentType // .agent // "unknown"' 2>/dev/null || echo "unknown")

if [[ "$AGENT_NAME" != *"taxonomy-extremist"* ]]; then
    exit 0
fi

mkdir -p "$RESEARCH_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RANDOM_SUFFIX=$(head -c 4 /dev/urandom | xxd -p)
OUTPUT_FILE="$RESEARCH_DIR/taxonomy-extremist-${TIMESTAMP}-${RANDOM_SUFFIX}.json"
RAW_FILE="${OUTPUT_FILE%.json}-raw.json"
CLASSIFIED_FILE="${OUTPUT_FILE%.json}-classified.json"

echo "$INPUT" > "$RAW_FILE"

AGENT_OUTPUT=$(echo "$INPUT" | jq -r '.agent_output // .result // .output // .response // empty' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty' 2>/dev/null || echo "")

write_failure() {
    local reason="$1"
    jq -n \
        --arg agent "$AGENT_NAME" \
        --arg status "failed" \
        --arg reason "$reason" \
        --arg raw_file "$RAW_FILE" \
        --arg usage_source "unavailable" \
        '{
            agent_name: $agent,
            status: $status,
            classification: $status,
            reasons: [$reason],
            output_file: null,
            raw_file: $raw_file,
            usage_source: $usage_source,
            tool_usage: null,
            budget: null,
            budget_exhausted: false,
            duplicate_calls: []
        }' > "$CLASSIFIED_FILE"
}

extract_json() {
    local text="$1"
    local parsed=""
    if parsed=$(printf '%s' "$text" | jq -c . 2>/dev/null) && [ -n "$parsed" ]; then
        printf '%s' "$parsed"
        return 0
    fi
    if parsed=$(printf '%s' "$text" | perl -0ne 'if (/```(?:json)?\s*(\{.*?\})\s*```/s) { print $1; exit }' | jq -c . 2>/dev/null) && [ -n "$parsed" ]; then
        printf '%s' "$parsed"
        return 0
    fi
    return 1
}

usage_source_from_payload() {
    if [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
        if grep -q 'tool_use\|tool_call\|WebSearch\|Grep\|Glob\|Read' "$TRANSCRIPT_PATH" 2>/dev/null; then
            echo "transcript_derived"
            return 0
        fi
    fi

    if echo "$INPUT" | jq -e 'has("tool_usage") or has("toolUsage") or has("usage")' >/dev/null 2>&1; then
        echo "self_reported"
        return 0
    fi

    echo "self_reported"
}

if [ -z "$AGENT_OUTPUT" ] || [ "$AGENT_OUTPUT" = "null" ]; then
    write_failure "no agent_output/result/output field in SubagentStop payload"
else
    if ! PARSED_OUTPUT=$(extract_json "$AGENT_OUTPUT"); then
        write_failure "agent output is not valid JSON"
    else
        echo "$PARSED_OUTPUT" > "$OUTPUT_FILE"

        USAGE_SOURCE=$(usage_source_from_payload)

        jq -c \
            --arg agent "$AGENT_NAME" \
            --arg output_file "$OUTPUT_FILE" \
            --arg raw_file "$RAW_FILE" \
            --arg usage_source "$USAGE_SOURCE" '
            def required:
              ["status", "findings", "search_exhausted", "tool_errors", "tool_usage", "budget", "budget_exhausted", "duplicate_calls", "usage_source", "recommendations"];
            def num($p): ($p | type == "number");
            def nonneg($p): (num($p) and $p >= 0);
            def add_reason($r): .reasons += [$r];
            def classify_duplicates:
              [(.tool_usage.calls // [])[]?]
              | group_by((.tool // "other") + ":" + (.args_fingerprint // ""))
              | map(select(length > 1) | {tool: (.[0].tool // "other"), args_fingerprint: (.[0].args_fingerprint // ""), count: length});

            . as $doc
            | {
                agent_name: $agent,
                status: ($doc.status // "failed"),
                classification: ($doc.status // "failed"),
                reasons: [],
                output_file: $output_file,
                raw_file: $raw_file,
                usage_source: $usage_source,
                tool_usage: ($doc.tool_usage // null),
                budget: ($doc.budget // null),
                budget_exhausted: ($doc.budget_exhausted // false),
                duplicate_calls: ((($doc.duplicate_calls // []) + ($doc | classify_duplicates)) | unique_by(.tool, .args_fingerprint)),
                search_exhausted: ($doc.search_exhausted // false),
                findings_count: (($doc.findings // []) | length)
              }
            | reduce required[] as $missing (. ; if ($doc | has($missing) | not) then add_reason("missing required field: " + $missing) else . end)
            | if (($doc.status // "") | IN("ok", "partial", "empty", "failed") | not) then add_reason("invalid status: " + ($doc.status // "missing" | tostring)) else . end
            | if (($doc.tool_usage // null) == null) then add_reason("missing tool_usage") else . end
            | if (($doc.budget // null) == null) then add_reason("missing budget") else . end
            | if (($doc.tool_usage // {}) as $u | (nonneg($u.total_tool_calls) and nonneg($u.search_calls) and nonneg($u.file_reads) and nonneg($u.mcp_calls)) | not) then add_reason("impossible or missing tool_usage counters") else . end
            | if (($doc.budget // {}) as $b | (nonneg($b.max_tool_calls) and nonneg($b.max_search_calls) and nonneg($b.max_file_reads) and nonneg($b.max_mcp_calls)) | not) then add_reason("impossible or missing budget counters") else . end
            | if (($doc.tool_usage.total_tool_calls // 0) > ($doc.budget.max_tool_calls // 0)) then add_reason("total_tool_calls exceeds max_tool_calls") else . end
            | if (($doc.tool_usage.search_calls // 0) > ($doc.budget.max_search_calls // 0)) then add_reason("search_calls exceeds max_search_calls") else . end
            | if (($doc.tool_usage.file_reads // 0) > ($doc.budget.max_file_reads // 0)) then add_reason("file_reads exceeds max_file_reads") else . end
            | if (($doc.tool_usage.mcp_calls // 0) > ($doc.budget.max_mcp_calls // 0)) then add_reason("mcp_calls exceeds max_mcp_calls") else . end
            | if ((.duplicate_calls | length) > 0 and (($doc.status // "") == "ok")) then add_reason("duplicate calls reported with ok status") else . end
            | if ($usage_source == "unavailable" and (($doc.status // "") == "ok")) then add_reason("usage_source unavailable cannot be ok") else . end
            | if ((.reasons | length) > 0) then .classification = "failed" else .classification = ($doc.status // "failed") end
            | if (.classification == "ok" and $usage_source != "transcript_derived") then .classification = "partial" | add_reason("usage is self-reported, not transcript-derived") else . end
        ' "$OUTPUT_FILE" > "$CLASSIFIED_FILE"
    fi
fi

CLASSIFICATION=$(jq -r '.classification // "failed"' "$CLASSIFIED_FILE" 2>/dev/null || echo "failed")

if [ -f "$PLAN_STATE" ]; then
    if jq --argjson result "$(cat "$CLASSIFIED_FILE")" '
        .research = (.research // {})
        | .research.agents = ((.research.agents // []) + [$result])
        | .research.agents_completed = ((.research.agents // []) | length)
        | .research.agents_failed = ((.research.agents // []) | map(select(.classification == "failed")) | length)
        | .research.agents_partial = ((.research.agents // []) | map(select(.classification == "partial")) | length)
        | .research.agents_ok = ((.research.agents // []) | map(select(.classification == "ok")) | length)
        | .research.overall_status = (if .research.agents_failed > 0 then "partial" elif .research.agents_partial > 0 then "partial" elif .research.agents_ok > 0 then "ok" else "failed" end)
        | .research_complete = (.research.overall_status == "ok")
    ' "$PLAN_STATE" > "${PLAN_STATE}.tmp" 2>/dev/null; then
        mv "${PLAN_STATE}.tmp" "$PLAN_STATE"
    else
        rm -f "${PLAN_STATE}.tmp"
        echo "capture-research.sh: WARNING - failed to update plan state" >&2
    fi
fi

if [ "$CLASSIFICATION" = "failed" ]; then
    echo "Captured taxonomy-extremist output as failed: $CLASSIFIED_FILE" >&2
else
    echo "Captured taxonomy-extremist output as $CLASSIFICATION: $CLASSIFIED_FILE"
fi

exit 0
