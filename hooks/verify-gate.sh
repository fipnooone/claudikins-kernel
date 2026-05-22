#!/bin/bash
# verify-gate.sh - Stop hook for /verify
# Enforces verification gate with exit code 2 pattern.
# Generates file manifest for /ship integrity checking (C-6).
#
# Matcher: /verify
# Exit codes:
#   0 - Verification complete and approved, /ship unlocked
#   2 - Verification incomplete or not approved, /ship blocked

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
VERIFY_STATE="$CLAUDE_DIR/verify-state.json"
MANIFEST_FILE="$CLAUDE_DIR/verify-manifest.txt"

# === Dependency Check (H-3) ===
for cmd in jq git find; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: $cmd not installed" >&2
        exit 127
    fi
done
if ! command -v sha256sum &>/dev/null && ! command -v shasum &>/dev/null; then
    echo "ERROR: sha256sum or shasum not installed" >&2
    exit 127
fi

if command -v sha256sum &>/dev/null; then sha256_cmd() { sha256sum "$@"; }; else sha256_cmd() { shasum -a 256 "$@"; }; fi

# === Error handling (H-1) ===
trap 'echo "Hook crashed: $?" >&2; exit 1' ERR

# === ENV validation (H-2) ===
if [ "$PROJECT_DIR" = "." ]; then
    echo "WARNING: Using current directory (CLAUDE_PROJECT_DIR unset)" >&2
fi

# Read input JSON from stdin
INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "unknown"')

# Check if verify state exists
if [ ! -f "$VERIFY_STATE" ]; then
    # No verify session - silently exit (command wasn't run)
    exit 0
fi

# If a stale completed/pass verify state is encountered by a non-verify Stop
# event, do not reacquire the lock or rewrite state. This prevents hook feedback
# loops when OpenClaude replays Stop hooks after ordinary assistant turns.
VERIFY_COMMAND=$(echo "$INPUT" | jq -r '.prompt // .command // .user_prompt // ""' 2>/dev/null || echo "")
if jq -e '(.status == "completed") and ((.verification_state // .status) == "pass") and (.unlock_ship == true)' "$VERIFY_STATE" >/dev/null 2>&1; then
    if ! printf '%s' "$VERIFY_COMMAND" | grep -qE '^(/verify|(/)?claudikins-kernel:verify)([[:space:]]|$)'; then
        exit 0
    fi
fi

# === File Locking (C-8) — portable (works on macOS + Linux) ===
LOCK_DIR="${VERIFY_STATE}.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "ERROR: Another process is modifying verify state" >&2
    exit 2
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# === State File Corruption Check (H-4) ===
if ! jq empty "$VERIFY_STATE" 2>/dev/null; then
    echo "ERROR: verify-state.json corrupted" >&2
    exit 2
fi

# Check verification status
ALL_PASSED=$(jq -r '.all_checks_passed // false' "$VERIFY_STATE")
VERIFICATION_STATE=$(jq -r '.verification_state // .status // "unknown"' "$VERIFY_STATE")
HUMAN_APPROVED=$(jq -r '.human_checkpoint.decision // ""' "$VERIFY_STATE")
SESSION_ID=$(jq -r '.session_id // "unknown"' "$VERIFY_STATE")

# Get phase statuses for reporting
TEST_STATUS=$(jq -r '.phases.test_suite.status // "pending"' "$VERIFY_STATE")
LINT_STATUS=$(jq -r '.phases.lint.status // "pending"' "$VERIFY_STATE")
TYPE_STATUS=$(jq -r '.phases.type_check.status // "pending"' "$VERIFY_STATE")
OUTPUT_STATUS=$(jq -r '.phases.output_verification.status // "pending"' "$VERIFY_STATE")

# Check if all automated checks passed and the state is a clean pass
if [ "$VERIFICATION_STATE" != "pass" ]; then
    cat <<EOF >&2
Verification did not produce a clean pass.

Session: ${SESSION_ID}
Verification state: ${VERIFICATION_STATE}
Tests:   ${TEST_STATUS}
Lint:    ${LINT_STATUS}
Types:   ${TYPE_STATUS}
Output:  ${OUTPUT_STATUS}

Caveated, skipped, failed, missing, or unknown verification states do not unlock normal shipping.
EOF
    exit 2
fi

if [ "$ALL_PASSED" != "true" ]; then
    cat <<EOF >&2
Verification checks not all passed.

Session: ${SESSION_ID}
Tests:   ${TEST_STATUS}
Lint:    ${LINT_STATUS}
Types:   ${TYPE_STATUS}
Output:  ${OUTPUT_STATUS}

Complete all verification phases before shipping.
EOF
    exit 2
fi

# Check human approval
if [ "$HUMAN_APPROVED" != "ready_to_ship" ]; then
    cat <<EOF >&2
Human has not approved for shipping.

Session: ${SESSION_ID}
Decision: ${HUMAN_APPROVED:-"none"}

Use the human checkpoint to approve:
  [Ready to Ship] - Approve clean pass for normal shipping
  [Needs Work] - Return for fixes
  [Record Caveats - Ship Locked] - Record issues without unlocking normal shipping
EOF
    exit 2
fi

# === Generate File Hash Manifest (C-6) ===
# Captures SHA256 of all source files for integrity checking in /ship
echo "Generating file manifest for integrity checking..." >&2

find "$PROJECT_DIR" \( \
    -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
    -o -name '*.py' -o -name '*.rs' -o -name '*.go' -o -name '*.java' \
    -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \
    -o -name '*.rb' -o -name '*.php' -o -name '*.swift' -o -name '*.kt' \
    \) \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/.claude/worktrees/*' \
    -not -path '*/target/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.venv/*' \
    -not -path '*/venv/*' \
    -type f \
    2>/dev/null | sort | while IFS= read -r f; do sha256_cmd "$f"; done > "$MANIFEST_FILE" 2>/dev/null || true

# Generate manifest hash
if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_SHA=$(sha256_cmd "$MANIFEST_FILE" | cut -d' ' -f1)
    FILE_COUNT=$(wc -l < "$MANIFEST_FILE")
else
    MANIFEST_SHA="missing"
    FILE_COUNT=0
fi

# Get current commit SHA
COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

# === Atomic Write Pattern (C-9) ===
TEMP_FILE=$(mktemp "${VERIFY_STATE}.XXXXXX")
trap "rm -f '$TEMP_FILE'; rmdir '$LOCK_DIR' 2>/dev/null" EXIT

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Set unlock flag and manifest hash
if ! jq --arg manifest "$MANIFEST_SHA" \
       --arg commit "$COMMIT_SHA" \
       --arg timestamp "$TIMESTAMP" \
       --argjson fileCount "$FILE_COUNT" \
       '. + {
          "verification_state": "pass",
          "unlock_ship": true,
          "verified_at": $timestamp,
          "verified_manifest": $manifest,
          "verified_commit_sha": $commit,
          "verified_file_count": $fileCount,
          "status": "completed"
        }' \
       "$VERIFY_STATE" > "$TEMP_FILE"; then
    echo "ERROR: Failed to update state (disk full?)" >&2
    exit 2
fi

# Validate JSON before committing
if ! jq empty "$TEMP_FILE" 2>/dev/null; then
    echo "ERROR: State file write incomplete" >&2
    exit 2
fi

mv "$TEMP_FILE" "$VERIFY_STATE"

# Output success message to stderr (Stop hooks don't support hookSpecificOutput)
cat <<EOF >&2
VERIFICATION COMPLETE

Session: ${SESSION_ID}
Commit: ${COMMIT_SHA}
Files verified: ${FILE_COUNT}
Manifest: ${MANIFEST_SHA}

Ship unlocked. Run claudikins-kernel:ship when ready.
EOF

exit 0
