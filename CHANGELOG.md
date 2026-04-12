# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-04-12

### Added

- **Grounding enforcement** in brain-jam-plan: specific technical claims about APIs/libraries (versions, methods, install flags, URLs, compatibility) must include `[Source: URL]` or be marked `[UNVERIFIED]`
- `citation-rules.md` reference with examples of specific vs general claims and `[UNVERIFIED]` tag rules
- Required checklist item in `plan-checklist.md` for sourced technical claims
- API/Library research requirement in `outline.md` Phase 2 — taxonomy-extremist in docs/external mode required for API-specific tasks
- `--skip-research` warning now explicitly requires `[UNVERIFIED]` tags on all API/library claims
- New Red Flags and Rationalizations-to-Resist entries for knowledge-based API claims

## [1.3.1] - 2026-04-02

### Fixed

- Sequential pipeline enforcement: each command now explicitly guides to the next step (outline → execute → verify → ship) via frontmatter descriptions, Pipeline Position blocks, and PROHIBITED option lists in Next Stage sections
- Added pipeline step anchors to all 4 command frontmatter descriptions (survives context compression)
- Added "verify — never commit" anchor to git-workflow SKILL.md description
- Prevents Claude from suggesting "commit changes" after /execute instead of /verify

## [1.3.0] - 2026-04-02

### Changed

- Static model routing for all agents — each agent now declares its model in frontmatter based on task complexity:
  - **opus**: babyclaude (code generation), code-reviewer (quality judgement), cynic (senior engineer polish)
  - **sonnet**: spec-reviewer (checklist compliance), taxonomy-extremist (research), catastrophiser (output verification), conflict-resolver (merge analysis), git-perfectionist (documentation)
- Removed hardcoded `model: "opus"` overrides from `execute.md` Task() calls — agents now own their model declarations

## [1.2.1] - 2026-03-27

### Fixed

- Hook JSON output schema violations across 12 hook scripts — `hookSpecificOutput` is only valid for `PreToolUse`, `UserPromptSubmit`, and `PostToolUse` events; all other event types (`Stop`, `SessionStart`, `PreCompact`, `SubagentStart`, `SubagentStop`) now use the correct top-level fields (`stopReason`, `systemMessage`) instead, fixing the recurring `Hook JSON output validation failed: - : Invalid input` error
- `sanitize-bash.sh`: `updatedInput` moved inside `hookSpecificOutput` where it belongs; `decision: "allow"` corrected to `permissionDecision: "allow"` inside `hookSpecificOutput`
- `ship-init.sh` and `ship-complete.sh`: `echo` statements moved to stderr so stdout carries only JSON
- All dynamic hook output values now use `printf | jq -Rs '.'` for consistent, safe JSON escaping

## [1.2.0] - 2026-01-21

### Added

- **Review Enforcement** in git-workflow skill and execute.md - reviewer agents (spec-reviewer, code-reviewer) MUST be spawned; inline reviews are now violations
- Pre-merge checklist requiring `.claude/reviews/spec/` and `.claude/reviews/code/` files to exist
- Test task detection and implementation source injection in execute.md - prevents test agents from hallucinating interfaces
- Defensive "For Test Tasks" section in babyclaude.md - blocks if implementation sources not provided
- Worktree path injection in babyclaude spawn with `cwd: worktreePath` for proper isolation

### Changed

- `git-branch-guard.sh` switched from blocklist to **allowlist** approach - only permits safe git commands (add, status, diff, log, show, ls-files, check-ignore, rev-parse, symbolic-ref, config --get/--list, commit)
- Rationalizations table updated with "I'll do the review myself" violation
- Red flags updated with inline review warnings

### Fixed

- Branch collision bug - parallel babyclaude agents now operate in isolated worktrees instead of shared working directory
- `preserve-state.sh` PreCompact hook now always outputs valid JSON (even for no-op cases)
- Phase-aware resume commands in preserve-state.sh (outline/execute/verify/ship)

## [1.1.3] - 2026-01-20

### Changed

- `batch-checkpoint-gate.sh`: improved checkpoint message formatting with proper newline handling via jq

---

## [1.1.2] - 2026-01-19

### Fixed

- babyclaude Stop prompt hook: use `{"ok": true/false}` response format instead of `{"decision": "allow/block"}` (Claude Code expects the former)

## [1.1.1] - 2026-01-19

### Fixed

- `sanitize-bash.sh`: use `"decision": "approve"` instead of invalid `"decision": "allow"`
- `verify-gate.sh`: output to stderr instead of invalid `hookSpecificOutput` JSON (Stop hooks don't support it)

## [1.1.0] - 2026-01-20

### Added

- `homepage`, `repository`, `license`, and `keywords` fields to plugin.json
- `permissionMode` to all 8 agents for proper permission handling
- `once: true` to session-startup hook (prevents duplicate execution)
- `pre-task-gate.sh` hook implementing constraint C-4 (review verdict gate)
- PreToolUse/Task matcher in hooks.json for pre-task validation
- Permission deny rules in settings.local.json for dangerous git operations
- "Next Stage" sections to all 4 commands for workflow continuity
- Frontmatter `hooks.Stop` to 5 agents (babyclaude, catastrophiser, cynic, git-perfectionist, taxonomy-extremist)
- LLM-based Stop hook (`type: "prompt"`) for babyclaude completion evaluation
- `sanitize-bash.sh` PreToolUse hook with `updatedInput` pattern for command sanitization
- `output-schema` to all 4 commands for structured JSON output
- `skill-rules.json` for skill auto-activation with intent/path pattern matching
- `skill-activation-hook.sh` UserPromptSubmit hook for auto-suggesting relevant skills
- Execution tracing with `trace-start.sh` and `trace-end.sh` (SubagentStart/SubagentStop)
- `.claude/traces/` directory for span-based execution timing
- `allowed-tools` to all 4 skills with appropriate tool restrictions

### Changed

- Commands restructured: `flags`, `merge_strategy`, `color` moved from frontmatter to body documentation
- Plugin version bumped from 1.0.0 to 1.1.0
- Author name updated to full name in plugin.json
- Agent-specific SubagentStop hooks moved from hooks.json to agent frontmatter

### Removed

- Invalid `context: fork` field from all agents (skill-only field)
- `color` field from command frontmatter (not a valid field)
- SubagentStop section from hooks.json (replaced by frontmatter hooks + global tracing)

### Fixed

- Agent frontmatter now uses only valid fields per Claude Code spec

## [1.0.0] - 2026-01-18

### Added

- Initial release
- 4 commands: outline, execute, verify, ship
- 8 agents: babyclaude, catastrophiser, cynic, spec-reviewer, code-reviewer, taxonomy-extremist, conflict-resolver, git-perfectionist
- 4 skills: brain-jam-plan, git-workflow, strict-enforcement, shipping-methodology
- Hook infrastructure with hooks.json and shell scripts
