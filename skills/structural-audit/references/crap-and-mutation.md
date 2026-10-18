# CRAP and Mutation Testing as Evidence

Read this when you need to produce complexity × coverage (CRAP) numbers for
the target list (step 2) or run a dedicated mutation tool for the test
integrity pass (step 3). These tools are evidence, not verdicts: they tell
you *where* to read, never what to conclude.

## CRAP: complexity × coverage in one number

CRAP (Change Risk Anti-Patterns, Savoia & Evans 2007) combines cyclomatic
complexity and statement coverage per function:

```
CRAP = complexity² × (1 − coverage)³ + complexity
```

Bands used by crap4clj: 1–5 clean, 5–30 moderate (refactor or add tests),
30+ critical. A high score means "complex and under-tested" — a priority
target for the audit. It does **not** mean "badly tested": coverage measures
execution, and a function with 100% coverage and vacuous tests still scores
low. CRAP is a filter for step 2, never a pass for step 3.

### Producing CRAP for TypeScript/JS

Test runners (Vitest/Jest) do not compute CRAP; you need one extra step that
joins coverage with AST complexity:

1. Emit an Istanbul-format `coverage-final.json` (Vitest: add `'json'` to
   `coverage.reporter`; the v8 provider has been Istanbul-equivalent since
   Vitest 3.2).
2. Compute complexity and apply the formula. Options:
   - `crap-score` (npm): `npx crap coverage/coverage-final.json`; supports
     TS/TSX via `@typescript-eslint`.
   - `@sebassdc/crap4ts` and `crap4ts` (npm): TypeScript CRAP CLIs.
   - DIY: walk the AST with `@typescript-eslint/typescript-estree` (or the
     repo's TypeScript) and count decision points per function; ~50 lines.

Make sure coverage includes files that no test imports (`coverage.include`
covering `src`), otherwise 0%-covered functions never appear — and they are
the most interesting ones.

## Mutation testing: automating the step-3 mutation check

The manual mutation check in `references/test-integrity.md` is the
small-scale version of what StrykerJS does exhaustively. Prefer Stryker for
suspect tests on logic files when it is runnable in the audited repo
(installed, or `npx`-able), scoped to the lines those tests cover
(`--mutate <file>:<from>-<to>`).

Cost decides where to use it. Each mutant reruns every test that covers it;
on a page or component that means mounting the whole screen in jsdom, so a
single page-sized file can take 10-20 minutes and most of its mutants are
markup. Logic files run in a minute or two and nearly every mutant matters.
If the repo's config supports it, turn on incremental mode so before/after
runs reuse unchanged results.

Operational notes that matter when reading its output:

- **The score is not a gate.** Timeouts count as detected, so the headline
  number is noisy; the survivor list is the finding.
- **Triage survivors.** Kill mutants that touch business logic; expect and
  ignore mutants in styles (`sx`/CSS values), hover handlers, and other
  markup — auditing those is out of scope by design.
- **No related tests is itself a finding.** If Stryker reports that no test
  files are related to the mutated file, nothing imports it; don't force a
  run with `related: false` just to get a number.
- **Equivalent mutants** (mutations that do not change behavior) cannot be
  killed; handle them with ignore annotations rather than chasing them.
- **Run one at a time.** Parallel runs compete for CPU and memory and all
  of them slow down; in one audit, three concurrent runs on a 12-core
  machine kept the load near 13 and each took several times longer. If
  several agents must run Stryker anyway, each target must be a disjoint
  file (see the parallel mutation rule in SKILL.md).
