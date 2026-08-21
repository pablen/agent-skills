# Test Integrity: Mutation Check

A test that passes is not evidence of anything by itself. The question that
matters is: **if the logic it claims to cover were broken, would this test
notice?** Reading the assertions is a good first filter, but for anything
classified as suspect or vacuous, verify it directly instead of guessing.

## The technique

1. Identify the smallest unit of logic the test claims to verify (a
   condition, a calculation, a branch, a call).
2. Make one small, temporary, obviously-wrong change to that logic —
   examples below.
3. Run only that test file/case (not the whole suite — keep the loop tight).
4. Expect it to fail. If it fails: the test is meaningful, revert the
   mutation, move on.
5. If it still passes: this is a confirmed finding, not a suspicion. Revert
   the mutation before doing anything else — never leave a mutation in
   place, even briefly, past the single check.

Treat step 5's revert as non-negotiable and verify it (`git diff` should be
empty for that file) before moving to the next test.

## Mutation examples by category

- **Conditionals**: invert `if (a > b)` to `if (a < b)`, or hardcode the
  branch that should not be taken.
- **Calculations**: change an operator (`+` to `-`, multiply by the wrong
  factor), or return a hardcoded wrong constant.
- **Return values**: return `null`/`undefined`/an empty array where real
  data is expected.
- **Async/side effects**: skip the `await`, or make the call a no-op stub
  that does nothing.
- **Validation/guards**: remove a `throw`/early-return so an invalid case
  falls through.
- **Permissions/auth checks**: flip a boolean (`isAllowed` /
  `!isAllowed`), or bypass the check entirely.

## What a stayed-green result actually means

Common root causes, worth naming in the finding so the fix is obvious:

- The test asserts on something unrelated to the mutated logic (e.g. checks
  that a function was called, not what it was called with or what it
  returned).
- The test mocks away the exact unit under test, so the mutation never
  executes.
- The test's setup makes the mutated branch unreachable (e.g. always hits
  the happy path regardless of the flag).
- The assertion is too loose (`toBeTruthy()` where a specific value matters,
  `expect(fn).toHaveBeenCalled()` where the arguments matter).
- The test doesn't await async work, so it finishes before the mutated code
  even runs.

## Scope discipline

This is a targeted technique, not a blanket mutation-testing pass over the
whole suite (that's what dedicated mutation-testing tools are for, and
running one is a separate, larger decision the user should opt into
explicitly). Apply it only to tests already flagged suspect/vacuous on
risk-ranked targets during the structural audit.
