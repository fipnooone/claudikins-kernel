---
name: brain-jam-plan
description: Use when running claudikins-kernel:outline, brainstorming implementation approaches, gathering requirements iteratively, structuring complex technical plans, or facing analysis paralysis with too many options — provides iterative human-in-the-loop planning with explicit checkpoints and trade-off presentation
allowed-tools:
  - Read
  - Grep
  - Glob
  - TodoWrite
  - WebSearch
  - Skill
  - mcp__plugin_claudikins-tool-executor_tool-executor__search_tools
  - mcp__plugin_claudikins-tool-executor_tool-executor__get_tool_schema
  - mcp__plugin_claudikins-tool-executor_tool-executor__execute_code
---

# Brain-Jam Planning Methodology

## Overview

Planning is an iterative conversation, not a production line. The human stays in the loop at every phase.

> "Go back and forth with Claude until I like its plan. A good plan is really important." — Boris

**Core principle:** Understand before solving. Ask before assuming. Recommend but let user decide.

## Trigger Symptoms

Use this skill when:

- Running the `claudikins-kernel:outline` command
- Requirements are unclear or keep changing
- Multiple valid approaches exist and you can't choose
- User wants involvement in decisions (not just receive a plan)
- Previous plans failed due to missed requirements
- Scope creep is a concern
- You're tempted to just start coding without a plan

## The Brain-Jam Process

### Phase 1: Requirements Gathering

**One question at a time. Wait for the answer.**

Key questions to answer:

1. What problem are we solving?
2. What does success look like?
3. What constraints exist?
4. What's explicitly OUT of scope?

Use `AskUserQuestion` with specific options — never open-ended unless necessary.

### Phase 2: Context Building

Before proposing solutions, understand the landscape:

- What exists already in the codebase?
- What patterns should we follow?
- What dependencies apply?
- What has been tried before?

### Phase 3: Approach Generation

Generate 2-3 distinct approaches. Each must include:

| Element | Purpose               |
| ------- | --------------------- |
| Summary | 1-2 sentence overview |
| Pros    | Clear benefits        |
| Cons    | Honest trade-offs     |
| Effort  | low / medium / high   |
| Risk    | low / medium / high   |

**Always recommend one with reasoning.** See [approach-template.md](references/approach-template.md).

### Phase 4: Section-by-Section Drafting

Draft one section at a time. Get approval before moving on.

**Never batch approvals** — each checkpoint is a chance to course-correct.

## Delegation Failure Rules

When delegating research/review, require structured output and stop after repeated tool validation errors. Treat malformed tool calls, invalid JSON, empty findings, and off-scope responses as failed or partial results; do not wait indefinitely or fabricate findings.

## Non-Negotiables

These rules have no exceptions:

**One question at a time.**

- Not "let me ask a few things"
- Not "quick questions"
- One question. Wait. Process answer. Next question.

**Always present 2-3 approaches.**

- Not "here's what I recommend"
- Not "the obvious choice is..."
- Present options. Recommend one. User decides.

**Checkpoint before proceeding.**

- Not "I'll assume that's fine"
- Not "continuing unless you object"
- Explicit approval. "Does this look right?" Wait for yes.

**Never fabricate research.**

- Not "based on my understanding"
- Not "typically in codebases like this"
- If you don't know, research or ask. Don't invent.

**Cite specific technical claims.**

- Not "install version X.Y.Z" without a verified source
- Not "call the `.method()` function" without checking docs
- Any specific claim (version, method, flag, URL, compatibility) → `[Source: URL]` or mark `[UNVERIFIED]`
- `[UNVERIFIED]` blocks plan finalisation — resolve against docs or get explicit user sign-off.

See [citation-rules.md](references/citation-rules.md) for examples of specific vs. general claims.

## Plan Quality Criteria

A good plan has:

- [ ] Clear problem statement
- [ ] Explicit scope boundaries (IN and OUT)
- [ ] Measurable success criteria
- [ ] Task breakdown with dependencies
- [ ] Risk identification and mitigations
- [ ] Verification checklist

See [plan-checklist.md](references/plan-checklist.md) for full verification.

## Output Format

Plans must include machine-readable task markers for `claudikins-kernel:execute` compatibility:

```markdown
<!-- EXECUTION_TASKS_START -->

| #   | Task          | Files                | Deps | Batch |
| --- | ------------- | -------------------- | ---- | ----- |
| 1   | Create schema | prisma/schema.prisma | -    | 1     |
| 2   | Add service   | src/services/user.ts | 1    | 1     |

<!-- EXECUTION_TASKS_END -->
```

See [plan-format.md](references/plan-format.md) for complete structure.

## Anti-Patterns

Stop and reassess when planning shortcuts would weaken user involvement or evidence. Common failure modes:

- Batching questions or approvals.
- Proposing only one approach or solving before requirements are clear.
- Continuing without explicit checkpoints.
- Fabricating research, relying on stale memory, or leaving specific API/library claims unverified.
- Waiting indefinitely on malformed/empty research outputs.

Canonical delegation and artifact-failure rules live in `../shared-prompt-invariants.md`.

## Edge Case Handling

| Situation                        | Reference                                                                     |
| -------------------------------- | ----------------------------------------------------------------------------- |
| Context collapse mid-plan        | [session-collapse-recovery.md](references/session-collapse-recovery.md)       |
| Endless iteration loop           | [iteration-limits.md](references/iteration-limits.md)                         |
| Research taking too long         | [research-timeouts.md](references/research-timeouts.md)                       |
| Approaches contradict each other | [approach-conflict-resolution.md](references/approach-conflict-resolution.md) |
| User abandons plan               | [plan-abandonment-cleanup.md](references/plan-abandonment-cleanup.md)         |
| Requirements keep changing       | [requirement-stability.md](references/requirement-stability.md)               |

## References

- [plan-checklist.md](references/plan-checklist.md) — Verification checklist
- [approach-template.md](references/approach-template.md) — How to present options
- [plan-format.md](references/plan-format.md) — Output structure for claudikins-kernel:execute
- [iteration-limits.md](references/iteration-limits.md) — When to stop iterating
- [requirement-stability.md](references/requirement-stability.md) — Scope creep detection
- [approach-conflict-resolution.md](references/approach-conflict-resolution.md) — Conflicting approaches
- [session-collapse-recovery.md](references/session-collapse-recovery.md) — Context collapse handling
- [research-timeouts.md](references/research-timeouts.md) — Timeout handling
- [plan-abandonment-cleanup.md](references/plan-abandonment-cleanup.md) — Cleanup procedures
