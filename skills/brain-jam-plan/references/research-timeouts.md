# Research Timeouts (S-3)

How to handle taxonomy-extremist agent timeouts gracefully.

## Default Timeouts

| Mode          | Default Timeout | Fast Mode (--fast-mode) |
| ------------- | --------------- | ----------------------- |
| Codebase      | 60 seconds      | 30 seconds              |
| Docs          | 90 seconds      | 45 seconds              |
| External      | 120 seconds     | 60 seconds              |
| Dual Research | 180 seconds     | 90 seconds              |

These timeouts apply to each individual agent spawn, not the total research phase.

## Budget Exhaustion vs Timeout

Research agents have bounded tool budgets in their prompt contract, but those prompt budgets are not true pre-tool hard guards unless the runtime exposes supported pre-tool interception. Treat budget handling as post-run/stop-time validation by default.

| Condition                               | Meaning                                                    | Valid recovery                                                          |
| --------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------- |
| Budget exhausted with valid final JSON  | Agent stopped deliberately after reaching tool/read limits | Accept as `status: "partial"` evidence or retry with a narrower prompt  |
| Wall-clock timeout with partial capture | Harness stopped an agent that did not finish in time       | Offer retry, partial continuation, skip, or different mode              |
| Budget or timeout with no valid JSON    | Agent did not satisfy the research contract                | Treat as failed research; do not silently use it as successful research |
| Missing usage fields                    | Budget compliance cannot be assessed                       | Treat as failed or `partial` at best; never mark as full success        |

A bounded partial JSON result is acceptable only when it includes `status`, `findings`, `search_exhausted`, `tool_errors`, `tool_usage`, `budget`, `budget_exhausted`, `duplicate_calls`, `usage_source`, and `recommendations`. Missing JSON after budget exhaustion or timeout is a failed research result and must trigger recovery handling.

## Research Result Classification

| Status    | Required interpretation                                                                                                                                                                        |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ok`      | Valid JSON, required fields present, budget not exceeded, no blocking duplicate loop, findings sufficient for the requested mode.                                                              |
| `partial` | Valid JSON with useful findings but budget exhausted, timeout caveat, unavailable usage source, or incomplete coverage.                                                                        |
| `empty`   | Valid JSON, no findings, and the search space was exhausted or produced no relevant hits.                                                                                                      |
| `failed`  | Invalid JSON, missing required fields, missing `tool_usage`, impossible counters, over-budget without `budget_exhausted=true`, duplicate loop without explanation, or no output after timeout. |

Budget violation rules:

- If `tool_usage.total_tool_calls > budget.max_tool_calls`, classify as `failed` unless transcript parsing proves the excess came from harness overhead rather than agent tools.
- If `tool_usage.search_calls > budget.max_search_calls`, classify as `failed`.
- If `tool_usage.file_reads > budget.max_file_reads`, classify as `failed`.
- If `tool_usage.mcp_calls > budget.max_mcp_calls`, classify as `failed`.
- If `usage_source=unavailable`, classify as `partial` at best.

Duplicate rules:

- Duplicate call fingerprint: `tool + stable_json(normalized_args)`.
- Duplicate search fingerprint: lowercase, whitespace-collapsed query text with volatile year/date terms preserved only when semantically required.
- Repeated calls are allowed only when their `purpose` names a new explicit question or changed scope. Otherwise classify as `partial` or `failed` depending on whether useful findings exist.

## Telemetry Source Hierarchy

1. Prefer transcript-derived usage if `SubagentStop` exposes a readable `transcript_path` containing tool calls.
2. Otherwise use hook payload fields if they include structured tool-call counts or result metadata.
3. Otherwise use self-reported `tool_usage` from the agent JSON and mark `usage_source="self_reported"`.
4. If none is available, mark `usage_source="unavailable"` and never report research as fully `ok`.

## Timeout Detection

The command monitors agent execution time:

```bash
AGENT_START=$(date +%s)
# ... agent runs ...
AGENT_END=$(date +%s)
DURATION=$((AGENT_END - AGENT_START))

if [ "$DURATION" -ge "$TIMEOUT" ]; then
  # Handle timeout
fi
```

## Timeout Handling Flow

### Step 1: Capture Partial Results

Even on timeout, attempt to capture what the agent found:

```json
{
  "status": "timeout",
  "partial": true,
  "findings": [
    // whatever was found before timeout
  ],
  "search_exhausted": false,
  "timed_out_at": "2026-01-16T14:30:00Z",
  "timeout_duration_seconds": 60
}
```

### Step 2: Present Options

```
Research agent timed out after 60 seconds.
Partial results captured: 3 findings (normally expect 8-12)

[Retry with extended timeout] [Continue with partial results] [Skip research] [Different mode]
```

### Step 3: Process User Choice

| Choice                      | Action                                             |
| --------------------------- | -------------------------------------------------- |
| Retry with extended timeout | Double the timeout, re-spawn agent                 |
| Continue with partial       | Mark research as incomplete, proceed               |
| Skip research               | Set `research_complete: false`, jump to approaches |
| Different mode              | Ask for new mode, spawn fresh agent                |

## Retry Logic

### Retry Limits

| Retry     | Timeout Multiplier | Notes                     |
| --------- | ------------------ | ------------------------- |
| 1st retry | 2x                 | Double original timeout   |
| 2nd retry | 3x                 | Triple original timeout   |
| 3rd retry | N/A                | No more retries, escalate |

### Backoff Strategy

Wait before retrying to allow external services to recover:

```
Retry 1: Wait 5 seconds, then retry with 2x timeout
Retry 2: Wait 15 seconds, then retry with 3x timeout
Retry 3: No retry, escalate to user
```

### Retry with Different Parameters

If retrying, consider modifying the search:

```
Research timed out. This might help:
- Narrow the search scope
- Use different keywords
- Try a different mode

Retry with: [Same query] [Narrower scope] [Different mode] [Give up]
```

## Mode-Specific Timeout Causes

### Codebase Mode

**Common causes:**

- Very large codebase (>100k files)
- Serena indexing slow
- Complex regex patterns in Grep

**Mitigations:**

- Narrow file patterns (specific directories)
- Simpler search terms
- Use Glob before Grep to reduce file set

### Docs Mode

**Common causes:**

- Context7 library fetch slow
- WebFetch hitting rate limits
- Large documentation sites

**Mitigations:**

- Target specific docs sections
- Use cached results if available
- Skip WebFetch, use only Context7

### External Mode

**Common causes:**

- Gemini API latency
- WebSearch rate limits
- Large response processing

**Mitigations:**

- Reduce Gemini prompt complexity
- Fewer WebSearch queries
- Process results in batches

## Fast Mode Behaviour

With `--fast-mode`:

1. All timeouts halved
2. Retry limit reduced to 1
3. Backoff shortened (2 seconds, 5 seconds)
4. Partial results accepted more readily

Warning shown when using fast mode:

```
Fast mode: Research timeouts reduced by 50%
Research quality may be lower. For thorough research, omit --fast-mode.
```

## Tracking Timeout State

Store timeout information in state:

```json
{
  "research": {
    "agents_spawned": 3,
    "agents_completed": 2,
    "agents_timed_out": 1,
    "timeout_details": [
      {
        "mode": "external",
        "timeout_at": 120,
        "retries": 2,
        "final_status": "partial"
      }
    ],
    "overall_status": "partial"
  }
}
```

## Escalation Path

If all retries exhausted:

```
Research agent failed after 3 attempts.
Mode: External | Total time spent: 6 minutes

Options:
[Continue without external research]
[Manual research input]
[Abandon planning session]
```

## Testing Timeout Handling

Verify these scenarios:

1. Agent times out, partial results captured correctly
2. Retry with extended timeout succeeds
3. All retries fail, escalation message shown
4. Fast mode reduces timeouts appropriately
5. Partial results correctly marked in state
6. User can continue with incomplete research
