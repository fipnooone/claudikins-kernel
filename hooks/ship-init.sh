#!/bin/bash
# ship-init.sh - SessionStart hook for /ship command
# Validates /verify gate passed and code integrity before shipping

set -euo pipefail

trap 'echo "ship-init.sh failed at line $LINENO" >&2; exit 1' ERR

# Get project directory (consistent with other hooks)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
VERIFY_STATE="$CLAUDE_DIR/verify-state.json"
SHIP_STATE="$CLAUDE_DIR/ship-state.json"
MANIFEST_FILE="$CLAUDE_DIR/verify-manifest.txt"

# Create claude dir if needed
mkdir -p "$CLAUDE_DIR"

# ============================================
# Gate Check: /verify must have passed
# ============================================

if [ ! -f "$VERIFY_STATE" ]; then
  echo "ERROR: claudikins-kernel:verify has not been run" >&2
  echo "" >&2
  echo "You must run claudikins-kernel:verify before claudikins-kernel:ship." >&2
  echo "Run: claudikins-kernel:verify" >&2
  exit 2
fi

# Check verification state and unlock flag. Clean pass is the normal shipping path.
VERIFICATION_STATE=$(jq -r '.verification_state // .status // "unknown"' "$VERIFY_STATE" 2>/dev/null || echo "unknown")
UNLOCK=$(jq -r '.unlock_ship // false' "$VERIFY_STATE" 2>/dev/null || echo "false")
DECISION=$(jq -r '.human_checkpoint.decision // "unknown"' "$VERIFY_STATE" 2>/dev/null || echo "unknown")
CAVEAT_COUNT=$(jq -r '(.verification_caveats // .human_checkpoint.caveats // []) | length' "$VERIFY_STATE" 2>/dev/null || echo "0")
CAVEATED_OVERRIDE="${CLAUDIKINS_CAVEATED_SHIP_OVERRIDE:-false}"

if [ "$VERIFICATION_STATE" = "caveated" ]; then
  if [ "$CAVEATED_OVERRIDE" = "true" ] && [ "$DECISION" = "approved_caveated_ship_override" ] && [ "$CAVEAT_COUNT" -gt 0 ]; then
    echo "WARNING: Using explicit caveated ship override" >&2
  else
    echo "ERROR: claudikins-kernel:verify completed with caveats" >&2
    echo "" >&2
    echo "Caveated verification is not the normal ship path." >&2
    echo "Use the documented caveated override path only after explicit human approval and visible caveat propagation." >&2
    exit 2
  fi
elif [ "$VERIFICATION_STATE" != "pass" ]; then
  echo "ERROR: claudikins-kernel:verify did not produce a clean pass" >&2
  echo "" >&2
  echo "Verification state: $VERIFICATION_STATE" >&2
  echo "Human checkpoint decision: $DECISION" >&2
  echo "" >&2
  echo "Re-run claudikins-kernel:verify and resolve failures before shipping." >&2
  exit 2
elif [ "$UNLOCK" != "true" ]; then
  echo "ERROR: claudikins-kernel:verify passed but shipping was not unlocked" >&2
  echo "" >&2
  echo "Human checkpoint decision: $DECISION" >&2
  echo "" >&2
  echo "Re-run claudikins-kernel:verify and ensure human approves." >&2
  exit 2
fi

# ============================================
# Code Integrity: C-5 Commit Hash Validation
# ============================================

VERIFY_COMMIT=$(jq -r '.verified_commit_sha // ""' "$VERIFY_STATE" 2>/dev/null || echo "")
CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")

if [ -n "$VERIFY_COMMIT" ] && [ -n "$CURRENT_COMMIT" ]; then
  if [ "$VERIFY_COMMIT" != "$CURRENT_COMMIT" ]; then
    echo "ERROR: Code has changed since verification (C-5)" >&2
    echo "" >&2
    echo "Verified commit: $VERIFY_COMMIT" >&2
    echo "Current commit:  $CURRENT_COMMIT" >&2
    echo "" >&2
    echo "Re-run claudikins-kernel:verify to validate current code." >&2
    exit 2
  fi
fi

if command -v sha256sum &>/dev/null; then sha256_cmd() { sha256sum "$@"; }; else sha256_cmd() { shasum -a 256 "$@"; }; fi

# ============================================
# Code Integrity: C-7 File Manifest Validation
# ============================================

VERIFIED_MANIFEST=$(jq -r '.verified_manifest // ""' "$VERIFY_STATE" 2>/dev/null || echo "")

if [ -n "$VERIFIED_MANIFEST" ]; then
  if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: Verification manifest missing (C-7)" >&2
    echo "" >&2
    echo "Verified manifest: $VERIFIED_MANIFEST" >&2
    echo "Manifest file:     $MANIFEST_FILE" >&2
    echo "" >&2
    echo "Re-run claudikins-kernel:verify to regenerate the manifest." >&2
    exit 2
  fi

  CURRENT_MANIFEST=$(sha256_cmd "$MANIFEST_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")

  if [ -z "$CURRENT_MANIFEST" ] || [ "$VERIFIED_MANIFEST" != "$CURRENT_MANIFEST" ]; then
    echo "ERROR: Source files changed after verification (C-7)" >&2
    echo "" >&2
    echo "Verified manifest: $VERIFIED_MANIFEST" >&2
    echo "Current manifest:  ${CURRENT_MANIFEST:-unavailable}" >&2
    echo "" >&2
    echo "Re-run claudikins-kernel:verify to validate current code." >&2
    exit 2
  fi
fi

# ============================================
# Initialize Ship State
# ============================================

SESSION_ID="ship-$(date +%Y-%m-%d-%H%M)"
VERIFY_SESSION=$(jq -r '.session_id // "unknown"' "$VERIFY_STATE" 2>/dev/null || echo "unknown")
VERIFY_CAVEATS_JSON=$(jq -c '.verification_caveats // .human_checkpoint.caveats // []' "$VERIFY_STATE" 2>/dev/null || echo "[]")

cat > "$SHIP_STATE" << EOF
{
  "session_id": "$SESSION_ID",
  "verify_session_id": "$VERIFY_SESSION",
  "verification_state": "$VERIFICATION_STATE",
  "verification_caveats": $VERIFY_CAVEATS_JSON,
  "caveated_override": $([ "$VERIFICATION_STATE" = "caveated" ] && echo "true" || echo "false"),
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "verified_commit": "$VERIFY_COMMIT",
  "target": "main",
  "phases": {
    "pre_ship_review": { "status": "pending" },
    "commit_strategy": { "status": "pending" },
    "documentation": { "status": "pending" },
    "pr_creation": { "status": "pending" },
    "merge": { "status": "pending" }
  },
  "unlock_merge": false
}
EOF

echo "Ship session initialized: $SESSION_ID" >&2
echo "Verified commit: ${VERIFY_COMMIT:-"(not tracked)"}" >&2
echo "" >&2
echo "Gate check: PASSED" >&2
echo "Code integrity: VERIFIED" >&2

# Output JSON for Claude
SHIP_INIT_MSG="Ship session initialized: ${SESSION_ID}. Verified commit: ${VERIFY_COMMIT:-not tracked}. Verification state: ${VERIFICATION_STATE}. Gate check: PASSED. Code integrity: VERIFIED."
SHIP_INIT_MSG_ESCAPED=$(printf '%s' "$SHIP_INIT_MSG" | jq -Rs '.')
cat <<EOF
{
  "systemMessage": $SHIP_INIT_MSG_ESCAPED
}
EOF

exit 0
