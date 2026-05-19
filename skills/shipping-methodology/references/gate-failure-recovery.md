# Gate Failure Recovery (S-19)

Recovering when ship-init.sh gate check fails.

## Gate Check Failures

The gate can fail for several reasons:

| Failure           | Error Message                                               | Recovery                           |
| ----------------- | ----------------------------------------------------------- | ---------------------------------- |
| No verify state   | "claudikins-kernel:verify has not been run"                 | Run claudikins-kernel:verify first |
| Not unlocked      | "claudikins-kernel:verify did not pass or was not approved" | Complete claudikins-kernel:verify  |
| Commit mismatch   | "Code changed since verification"                           | Re-run claudikins-kernel:verify    |
| Manifest mismatch | "Source files changed after verification"                   | Re-run claudikins-kernel:verify    |
| Corrupted state   | "verify-state.json corrupted"                               | Re-run claudikins-kernel:verify    |

## Recovery Flows

### Verify State Missing

```
ERROR: claudikins-kernel:verify has not been run

Run claudikins-kernel:verify before claudikins-kernel:ship

[Run claudikins-kernel:verify now] [Abort]
```

**Recovery:**

```bash
# Run verification
claudikins-kernel:verify

# Then retry ship
claudikins-kernel:ship
```

### Unlock Flag Not Set

```
ERROR: claudikins-kernel:verify did not pass or was not approved

Human must approve verification before shipping.

Current verify state:
  all_checks_passed: true
  human_checkpoint.decision: null

[Resume claudikins-kernel:verify for human checkpoint] [Abort]
```

**Recovery:**

```bash
# Resume verification for approval
claudikins-kernel:verify --resume

# Approve at human checkpoint
# Then retry ship
claudikins-kernel:ship
```

### Commit Hash Mismatch (C-5)

```
ERROR: Code changed since verification

Verified commit: abc123def
Current commit:  789xyz456

Changes since verification:
- 2 commits added
- 5 files modified

[View changes] [Re-run claudikins-kernel:verify] [Abort]
```

**This happens when:**

- Additional commits made after claudikins-kernel:verify
- Branch rebased after claudikins-kernel:verify
- Merge from main pulled in changes

**Recovery:**

```bash
# Option 1: Re-verify current state
claudikins-kernel:verify

# Option 2: View what changed
git log abc123def..HEAD --oneline
git diff abc123def HEAD

# Then decide: re-verify or revert
```

### Manifest Hash Mismatch (C-7)

```
ERROR: Source files changed after verification

Verified manifest: sha256:abc123...
Current manifest:  sha256:def456...

Modified files:
- src/auth/middleware.ts
- src/api/routes.ts

[View changes] [Re-run claudikins-kernel:verify] [Abort]
```

**This happens when:**

- Files edited after claudikins-kernel:verify
- Auto-formatter ran after claudikins-kernel:verify
- IDE modified files

**Recovery:**

```bash
# Check what changed
git status
git diff

# Recovery requires re-verification
# Option 1: Keep changes, then re-run verification before shipping
claudikins-kernel:verify

# Option 2: Manually revert only the known post-verify edits, then restart ship
# Do not use broad checkout/reset in the shipping workflow.
claudikins-kernel:ship
```

### Corrupted State File

```
ERROR: verify-state.json corrupted

The verification state file is not valid JSON.

[Re-run claudikins-kernel:verify] [View raw file] [Abort]
```

**This happens when:**

- Disk write interrupted
- Manual editing broke JSON
- Concurrent modification

**Recovery:**

```bash
# Option 1: Re-run verification from scratch
rm .claude/verify-state.json
claudikins-kernel:verify

# Option 2: Check for backup
ls .claude/verify-state.json.bak

# Option 3: View and fix manually
cat .claude/verify-state.json
# Fix JSON syntax
jq . .claude/verify-state.json  # Validate
```

## Diagnostic Commands

### Check Verify State

```bash
# View verify state
cat .claude/verify-state.json | jq .

# Check specific fields
jq '.unlock_ship' .claude/verify-state.json
jq '.human_checkpoint.decision' .claude/verify-state.json
jq '.verified_commit_sha' .claude/verify-state.json
```

### Check Code Integrity

```bash
sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

VERIFY_MANIFEST=$(jq -r '.verified_manifest' .claude/verify-state.json)
CURRENT_MANIFEST=$(sha256_cmd .claude/verify-manifest.txt | cut -d' ' -f1)
echo "Verified: $VERIFY_MANIFEST"
echo "Current:  $CURRENT_MANIFEST"
```

### Regenerate Manifest

```bash
sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}
find . \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
  -o -name '*.py' -o -name '*.rs' -o -name '*.go' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' \
  | sort | while IFS= read -r file; do sha256_cmd "$file"; done > .claude/verify-manifest.txt
```

## Prevention

### Avoid Post-Verify Changes

After claudikins-kernel:verify passes:

1. Don't make code changes
2. Don't run formatters
3. Don't pull/merge
4. Run claudikins-kernel:ship immediately

### Lock Working Directory

```bash
# After verify, immediately ship
claudikins-kernel:verify && claudikins-kernel:ship
```

### Use Atomic Ship Flow

The ideal flow is:

```
claudikins-kernel:verify
  └── Human approves
      └── claudikins-kernel:ship (immediately)
          └── Merge
```

Don't:

```
claudikins-kernel:verify
  └── Human approves
      └── "Let me just fix this one thing..."  # NO!
          └── claudikins-kernel:ship fails
```

## Manual Override

There is no manual state-patching override. If ship gate state is missing, corrupt, mismatched, skipped, failed, or caveated without explicit human approval, re-run `claudikins-kernel:verify` or abort. Do not edit `.claude/verify-state.json` or manifest hashes to make shipping pass.

**Never:**

- Skip actual verification
- Ship untested code
- Bypass human checkpoint
- Patch state files to force `unlock_ship`
