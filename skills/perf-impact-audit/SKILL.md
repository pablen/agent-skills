---
name: perf-impact-audit
description: Decide whether a proposed React/frontend performance fix is worth implementing, before writing it into the real branch, by prototyping it in isolation and measuring its actual effect against a realistic scenario. Use only when explicitly invoked; do not activate automatically from a generic "improve performance" request or from a best-practices review that merely lists candidate fixes.
---

# Performance Impact Audit

Run this workflow only after explicit invocation, on one candidate fix at a time. It answers "is this worth doing?" before any code lands on the real branch — not "did this already-shipped change help?" (that is a smaller, retrospective use of the same techniques; this skill is written for the pre-implementation decision). Treat it as read-only with respect to the working tree: the candidate fix is implemented and measured in an isolated worktree, and only promoted to the real branch if the evidence earns it.

## Core rules

- One candidate per run. A caller with several candidates (e.g. a best-practices review's punch list) invokes this once per candidate; do not silently batch them.
- Never prototype on the working tree. Implement the candidate fix in a git worktree (`EnterWorktree` and `ExitWorktree`, or the project's equivalent isolation mechanism) so the real branch stays untouched until a verdict is reached.
- Measure at realistic data volumes and realistic interaction patterns for this app, not a synthetic worst case, unless the user explicitly asks about a worst-case/future-scale scenario. A loop over 5 items that could theoretically hold 5,000 is not the same question as one that already holds hundreds.
- Spend cheaply first. Always run the mechanical check (Tier 1). Only pay for the browser wall-clock check (Tier 2) when Tier 1 shows a real effect and it is unclear whether that effect is perceptible.
- Record every temporary instrumentation edit — in both the current tree and the worktree — and remove exactly those edits once done. Never leave render counters, profiler wrappers, debug globals, or perf-only test files behind.
- Prefer the project's existing test runner and browser tooling (Vitest/Testing Library, Playwright, etc.) over installing a benchmarking dependency. Reach for a microbenchmark library only when the question is pure-JS algorithmic cost with no React/DOM involvement and the project has no runner that already answers it.
- Do not commit timing thresholds sensitive to machine load. Report concrete numbers from this run as evidence, not as a gate for future runs.
- A candidate that turns out to have no measurable effect is a valid, useful outcome. Say so plainly instead of reaching for a reason to recommend the change.

## Workflow

### 1. Define the candidate

Capture, before touching any code:

- the exact claim (e.g. "recomputes derived state on every keystroke instead of once per data change");
- the file/component/hook where it lives;
- the realistic scenario that would trigger the wasteful path in this app (which screen, what data size, what user action) — ask the user or check the domain model/fixtures if it is not obvious;
- what the fix would concretely change (memoize, hoist, virtualize, dedupe, parallelize, etc.).

If the claim came from a best-practices review or linter-style finding, restate it in terms of this app's actual usage, not the rule's generic wording.

### 2. Establish the mechanical baseline (Tier 1)

Work against the current, unmodified code first:

- Find or write the smallest test that exercises the realistic interaction through the project's existing component/unit test harness (reuse fixtures and render helpers already in the test suite for that page/component when they exist).
- Temporarily instrument the suspect computation with a counter (a simple exported `{ count: 0 }` object incremented at the top of the block is usually enough) — no need for a mocking library.
- Drive the realistic interaction (e.g. N keystrokes in a field that actually feeds the suspect computation — verify it does; a field the component doesn't watch will show zero effect and prove nothing) and record the count.
- Remove the instrumentation from the current tree immediately after recording the number; do not leave it in while working on the prototype.

### 3. Prototype the fix in isolation

- Enter a fresh worktree for this candidate.
- Implement the actual proposed fix there — not a mock-up of it. The measurement is only honest if the code being measured is the code that would really ship.
- Apply the same temporary counter instrumentation (same location, same interaction) and record the count in the prototype.

### 4. Decide: stop or escalate

Compare the two counts.

- If the "before" count already shows no meaningful waste at realistic volumes (e.g. the block only reruns once or twice regardless, or the data size makes the difference trivial), stop here. Verdict: not worth it. Exit and discard the worktree.
- If "before" shows real, repeated waste that the prototype eliminates or reduces, proceed to Tier 2 only if it is genuinely unclear whether that waste is perceptible (a tight, cheap loop over a handful of items rarely needs Tier 2; a computation that touches many DOM nodes, triggers a request, or runs inside a large subtree usually does).
- If Tier 1 alone already makes the answer obvious either way, skip Tier 2 and report the mechanical evidence as sufficient.

### 5. Measure wall-clock impact (Tier 2, only when warranted)

- Wrap the relevant subtree in React's `Profiler` (`onRender`), pushing `actualDuration` samples to a place the browser tool can read back (e.g. a `window` array read via `page.evaluate`).
- Drive the same realistic interaction through the project's existing e2e/browser tool (e.g. Playwright), once against the current tree and once against the worktree's prototype, capturing and summing `actualDuration` across commits both times.
- If the numbers move meaningfully, that is the evidence for "worth it." If they do not, look at what dominates each commit's `actualDuration` (usually a sibling subtree, a table re-render, a query) and name it — the honest conclusion is often "correct fix, but this isn't the bottleneck; that is."
- Remove the `Profiler` wrapper and any window-global sample collection from both trees before finishing.

### 6. Report and act

State a verdict, not just numbers:

- **Implement**: evidence shows a real, perceptible effect at realistic scale. Promote the worktree's diff to the real branch (respecting the repo's normal commit/PR conventions) and proceed as a normal change.
- **Discard**: no meaningful effect at Tier 1, or Tier 1 showed an effect but Tier 2 showed it doesn't move the real number. Exit and discard the worktree; do not implement the change. Say what (if anything) actually dominates the cost instead, if Tier 2 revealed one.
- **Discard, but note X**: the candidate isn't worth it, but the investigation surfaced a bigger, unrelated cost worth a separate look.

### 7. Clean up and verify

Confirm the working tree has no leftover instrumentation (search for the counter/profiler labels you introduced), the worktree is removed unless its diff was promoted, and the project's normal checks (lint/typecheck/unit, and e2e if the promoted change touches a covered flow) pass.

## Report format

```text
Candidate: ...
Claim: ...
Realistic scenario: route/component, data size, interaction

Tier 1 — mechanical:
| Variant   | Recomputations/renders/requests for N interactions |
| Before    | ...                                                |
| Prototype | ...                                                |

Tier 2 — wall-clock (only if run):
| Variant   | Commits | Sum actualDuration |
| Before    | ...     | ...                 |
| Prototype | ...     | ...                 |

Verdict: implement | discard | discard, but note ...
Evidence: ...
Dominant cost (if the fix didn't move it): ...
Temporary instrumentation removed: yes | no, with reason
Action taken: promoted to branch | worktree discarded
```
