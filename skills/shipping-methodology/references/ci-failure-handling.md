# CI Failure Handling (S-20)

Handling CI pipeline failures during claudikins-kernel:ship.

## CI Check Flow

```
PR Created
    │
    └── CI Triggered
        │
        ├── Running...
        │   └── Poll status every 30s
        │
        ├── All checks pass
        │   └── Proceed to merge
        │
        └── Some checks fail
            └── Handle failure
```

## CI Status Display

```
CI Status
---------
✓ lint (2m 30s)
✓ test (5m 12s)
✗ build (failed after 3m 45s)
⏳ deploy-preview (running)

[View logs] [Re-run failed] [Request explicit failed-CI override] [Abort]
```

## Failure Types

### Test Failures

```
CI Failed: test

Failed tests:
- src/auth/__tests__/middleware.test.ts
  ✗ should reject expired token
  ✗ should handle malformed JWT

[View test output] [Fix locally] [Re-run tests] [Request explicit CI caveat override]
```

**Recovery:**

1. View test output to understand failure
2. Fix locally and push
3. Re-run CI
4. If CI is flaky or blocked by infrastructure, use the explicit caveated ship override path; do not treat it as a clean merge

### Lint Failures

```
CI Failed: lint

Lint errors:
- src/auth/middleware.ts:45 - Unexpected console statement
- src/api/routes.ts:12 - Missing semicolon

[View lint output] [Auto-fix] [Fix locally] [Abort - lint must be fixed]
```

**Recovery:**

```bash
# Auto-fix lint issues
npm run lint -- --fix
git add .
git commit -m "style: fix lint errors"
git push
```

### Build Failures

```
CI Failed: build

Build error:
error TS2345: Argument of type 'string' is not assignable to parameter of type 'number'.
  --> src/utils/parse.ts:23:15

[View build output] [Fix locally] [Abort]
```

**Recovery:**

1. Fix type error locally
2. Run build locally to verify
3. Push fix
4. Re-run CI

### Timeout Failures

```
CI Failed: test (timeout)

The test job exceeded the maximum time limit (30 minutes).

Possible causes:
- Infinite loop in test
- Missing mock causing real network calls
- Database connection hanging

[View logs] [Re-run] [Increase timeout] [Abort]
```

**Recovery:**

1. Check for infinite loops
2. Ensure mocks are in place
3. Check database connectivity
4. Re-run (might be transient)

### Infrastructure Failures

```
CI Failed: build (infrastructure)

Error: Runner ran out of disk space

This is not a code issue.

[Re-run] [Contact admin] [Request explicit infrastructure-CI override]
```

**Recovery:**

- Re-run job (usually transient)
- If persistent, contact CI admin
- If release must proceed despite an infrastructure-only CI failure, use the explicit caveated ship override path with human approval and visible caveat propagation

## Polling CI Status

### Using GitHub CLI

```bash
# Check PR status
gh pr checks 42

# Watch for changes
gh pr checks 42 --watch

# Get specific check
gh pr checks 42 --json name,state,conclusion
```

### Polling Pattern

```bash
while true; do
  STATUS=$(gh pr checks 42 --json conclusion -q '.[].conclusion' | sort -u)

  if echo "$STATUS" | grep -q "failure"; then
    echo "CI Failed"
    break
  elif echo "$STATUS" | grep -q "pending"; then
    echo "Still running..."
    sleep 30
  else
    echo "All passed"
    break
  fi
done
```

## Explicit Caveated CI Override Options

### When an Override May Be Considered

| Scenario         | Override OK? | Reason                                              |
| ---------------- | ------------ | --------------------------------------------------- |
| Known flaky test | Maybe        | Only with rerun evidence and caveated approval      |
| Timeout          | Maybe        | Only if transient infrastructure issue is evidenced |
| Lint error       | No           | Should be fixable                                   |
| Test failure     | No           | Code might be broken                                |
| Build failure    | No           | Code definitely broken                              |
| Infrastructure   | Maybe        | Only if clearly not code-related and propagated     |

### How to Request an Override

```
CI failed but appears infrastructure-only or known flaky.

WARNING: This is not a clean PASS. Normal shipping remains blocked unless the caveated ship override is explicitly approved.

Are you sure?

[Approve Caveated CI Override] [Wait for fix] [Abort]
```

If approved, record caveat and route through the caveated ship override path. Do not use admin merge commands as a default example.

Record caveat:

```json
{
  "shipped_with_caveats": true,
  "caveats": ["CI skipped due to infrastructure timeout"]
}
```

## Re-Running CI

### Re-Run Failed Jobs

```bash
# Re-run all failed checks
gh run rerun --failed

# Re-run specific workflow
gh run rerun <run-id>
```

### Re-Run with Debug

```bash
# Enable debug logging
gh run rerun <run-id> --debug
```

## Flaky Test Handling

If test fails then passes on re-run:

```
Test passed on retry.

This test appears to be flaky:
- src/auth/__tests__/middleware.test.ts
  "should handle concurrent requests"

[Record flaky-test caveat - ship remains locked] [Fix test] [Abort]
```

**Recording flaky tests:**

```json
{
  "flaky_tests": [
    {
      "file": "src/auth/__tests__/middleware.test.ts",
      "test": "should handle concurrent requests",
      "failure_rate": "1/3 runs"
    }
  ]
}
```

## CI Timeout Configuration

If jobs consistently timeout:

```yaml
# .github/workflows/ci.yml
jobs:
  test:
    timeout-minutes: 60 # Increase from default
```

```
CI job timed out at 30 minutes.

Options:
1. Increase timeout in CI config
2. Optimise slow tests
3. Split test suite into parallel jobs

[View slow tests] [Abort]
```

## Notification on CI Completion

```
CI completed: All checks passed ✓

Ready to merge PR #42

[Merge now] [Request review] [Wait]
```

Or:

```
CI completed: 2 checks failed ✗

Failed:
- test: 3 failures
- build: type error

[View details] [Fix] [Abort]
```

## Best Practices

1. **Don't skip CI for code failures** - Fix the code
2. **OK to skip for infrastructure** - Not your fault
3. **Record skipped CI** - Caveat in ship state
4. **Fix flaky tests** - Don't just keep re-running
5. **Increase timeouts carefully** - Might hide real issues
