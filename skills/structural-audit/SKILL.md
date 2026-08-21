---
name: structural-audit
description: Run an adversarial structural audit of a codebase that has been mostly agent-generated with light human review — hunting for vacuous tests, oversized/duplicated files, misapplied abstractions, reinvented helpers that duplicate an existing util or dependency, architectural drift between analogous screens, and unjustified divergence from a reference architecture. Use only when explicitly invoked; do not auto-trigger from generic "review this" or "clean up" requests, and never run it as part of the same pass that generated the code under audit.
---

# Structural Audit

This skill exists for a specific failure mode: a codebase built with heavy
agent assistance and periodic-not-exhaustive human review looks clean on the
surface (build passes, lint passes, tests are green) while accumulating
invisible debt — tests that don't actually test anything, duplicated logic
copied instead of reused, files that grew past the point a human would ever
read them fully, and structure that was pattern-matched from a reference
project without understanding why the reference did it that way.

The point is not to catch bugs (that's `code-review`/`security-review`) and
it is explicitly **not** to chase naming, formatting, or folder-layout taste —
those are implementation details with no product impact and are out of scope
here. The point is to surface the handful of things a human reviewer would
never stumble onto by accident, so they can be reviewed and fixed
deliberately instead of discovered months later.

## Core Rules

- **Explicit invocation only.** Do not run this from a generic "review this"
  or "clean this up" request — it's expensive and disruptive by design.
- **Report first, fix never in the same breath.** This audit's entire value
  is a second, independent look. Never have the audit both find and silently
  fix an issue — always present findings and get confirmation before
  changing anything. Fix confirmed findings one at a time, re-verifying after
  each.
- **Be adversarial, not diplomatic.** Assume the code passing lint/build/CI
  proves nothing about the categories this audit cares about. Actively try
  to break the claims a green test suite makes, rather than taking green as
  evidence of correctness.
- **Prioritize by blast radius, not by ease of detection.** Order of
  attention: (1) tests that create false confidence, (2) correctness of
  business-critical logic (money, auth, permissions, external side effects),
  (3) duplication and misapplied structure, (4) everything else. Naming,
  formatting, and file/folder bikeshedding are explicitly not this skill's
  job — do not report them even if noticed in passing.
- **Sample deliberately, not randomly or exhaustively.** A full-repo line
  read defeats the purpose (nobody will read that report either). Use risk
  signals — see "Building the target list" — to choose what to look at.
- **Cap the report.** Aim for the 10-20 findings that matter most, not a
  complete inventory. If more exist, say so explicitly and name the
  categories left unexamined rather than padding the report or truncating
  silently.
- **Never let the same lens both build and audit a reference comparison.**
  If a reference/prior-art repo is used for comparison, read it for *intent*
  (why did that project do it this way, what constraint drove it) — not just
  shape (does the file/folder pattern match). Structural similarity without
  a matching reason is itself a finding, not a pass.
- **Re-verify a finding before turning it into a fix.** Findings that pass
  through a synthesis step — a sub-agent's summary, a cross-page comparison,
  a consolidated report — can misattribute or conflate details even when
  each sub-agent was individually careful (a category-change error test
  summarized as a status-change error test; an "optimistic update flicker"
  attributed to the wrong lifecycle moment). Before acting on a finding that
  will change code, re-read the actual lines it's about yourself. This costs
  little and has already caught two false findings that would otherwise have
  produced a wrong or unnecessary fix.
- **When running mutation checks in parallel across multiple agents, scope
  each agent's targets to disjoint files.** Two agents mutation-testing the
  same shared file at the same time can observe each other's in-flight
  mutation and misdiagnose it as a pre-existing bug. If you still see this
  happen, treat an unexplained mutation as a coordination artifact first —
  check `git diff`/`git status` against what you yourself changed before
  concluding it's a real finding, then revert it and let the owning agent's
  own check run cleanly.

## Workflow

### 1. Scope the audit

Ask (or infer from context) before starting:

- Which part of the repo — everything, a subsystem, or files changed since a
  given point (last release, a date, a commit range)? Default to "everything
  reachable by risk signals below" if unspecified, not literally every file.
- Is there a reference/prior-art repo to compare structural decisions
  against? Check `AGENTS.md`/`CLAUDE.md` first — many repos already document
  one (e.g. "follow the patterns validated in project X"). Don't ask if it's
  already documented.
- Is this the first audit or a repeat? If prior audit notes exist (e.g. in
  `.notes/` or wherever this repo keeps them), read them first so the report
  tracks delta instead of re-litigating accepted findings.

### 2. Build the target list

Do not sample randomly. Rank candidates using signals such as:

- **Git churn**: files touched by many commits/agent sessions accumulate the
  most unreviewed drift. `git log --format= --name-only | sort | uniq -c |
  sort -rn` (or the repo's equivalent) surfaces hot files fast.
- **Business-critical keywords**: money/pricing/quantity math, auth,
  permissions, external API side effects, anything touching data integrity.
  Grep for domain terms, not framework boilerplate.
- **Size outliers**: files well above the codebase's own median size for
  their kind (component, hook, route, model). A 600-line component in a
  codebase where most are 80 lines is a signal regardless of absolute
  threshold.
- **Near-duplicate candidates**: similarly-named files/components/hooks
  across different pages or modules — a strong hint of copy-instead-of-reuse.
- **Test-to-code ratio outliers**: files with suspiciously thin test
  coverage for their risk level, or suspiciously large test files for what
  they claim to cover (padding, not depth). When the repo has (or can get) a
  coverage tool, prefer its per-branch numbers over eyeballing file/test
  size — a business-critical file at 0-30% branch coverage is a priority-1
  target on its own, no mutation check needed to justify picking it (the
  absence of any test is the finding); reserve the mutation check in step 3
  for files that *do* have tests but you suspect are vacuous.
- **Screen-type cohorts**: pages that solve the same generic UI problem
  (entity list/table, create/edit drawer, detail page) — the set to compare
  in the cross-page consistency pass, not just individual files.

State the target list and the reasoning before diving in, so the human can
redirect ("skip that area, I already know it's rough" / "focus here
instead").

### 3. Test integrity pass (do this first — highest priority)

This is the single most valuable thing this skill does. A green test suite
is the main reason a human stops looking; a test that passes without
actually exercising the behavior it claims to cover is worse than no test,
because it actively suppresses further scrutiny.

For every test file touching a target from step 2:

1. Read the test body, not just its name/description.
2. Classify each test as:
   - **Meaningful** — asserts on real, specific outcomes tied to the logic
     under test.
   - **Suspect** — asserts on something trivially true (mock was called,
     component rendered without crashing, a snapshot with no reasoning
     about what changed it), or duplicates another test with no added
     value.
   - **Vacuous** — cannot fail given any plausible implementation change;
     asserts on constants, doesn't await async work it should, mocks away
     the exact thing it claims to verify.
3. For every **suspect** or **vacuous** test on a risk-ranked target, run the
   mutation check described in
   [references/test-integrity.md](references/test-integrity.md): temporarily
   break the logic the test claims to cover, rerun just that test, confirm
   it goes red, then revert. If it stays green, that's a confirmed finding —
   not a suspicion.

Do not extend this pass to the entire test suite indiscriminately — apply it
to risk-ranked targets, and note explicitly which areas were left
unchecked.

### 4. Business-logic correctness pass

For business-critical files identified in step 2 (money/quantity math, auth,
permissions, side effects), read the implementation directly against its
actual requirements (ticket, spec, or documented business rule) rather than
against what the tests claim. Tests validated as vacuous in step 3 provide
zero evidence here — treat that logic as unverified.

When a finding is really a data-contract question — is this field required
or optional, does this value need to be validated this strictly, should two
siblings agree — and the audited repo is a frontend (or otherwise has a
separate backend/API repo it talks to), the contract lives in that other
repo, not in frontend-internal consistency. Read the actual backend
validation/schema before concluding two frontend siblings should match each
other; they may already correctly reflect a real difference the backend
enforces, and forcing them to agree would be the wrong fix.

### 5. Structural pass

For the remaining target list:

- **Size**: files that grew past what a human would read in one sitting
  relative to their responsibility — flag with a concrete split suggestion,
  not just "this is big."
- **Duplication**: logic or markup repeated across files instead of
  extracted, especially across pages that clearly started from copy-paste.
- **Misapplied abstraction**: a generic wrapper/helper/hook created for a
  single call site, or premature genericization that made one concrete case
  harder to read.
- **Multiple components per file**: independent components sharing one
  file inflate blast radius per edit, mix unrelated components' `git
  log`/blame history together, and make it harder for an agent (or human)
  to scope an edit to exactly what it should touch. Flag it, unless the
  file is a genuine versioned "kit" of primitives that are imported and
  actually changed together in practice — check whether past commits touch
  them together, not just that they're semantically related. When in
  doubt, one component per file is the safer default.
- **Reinvented wheel**: a new local helper that duplicates something
  already exported from a shared location (`src/utils/`, `src/hooks/`, or
  this repo's equivalent), or hand-rolled logic where an already-installed
  dependency does the same job (e.g. manual date arithmetic when
  `date-fns`/`dayjs`/etc. is already a dependency). Before accepting a new
  helper as legitimate, grep the shared utility directories and check
  `package.json` for prior art it should have used instead.
- **Dead weight**: unused exports, unreachable branches, leftover
  scaffolding from an earlier approach.

### 6. Cross-page consistency pass (only if the repo has 2+ analogous screens)

Some drift is invisible from inside any single file: two pages that solve
the same generic problem — an entity list/table, a create/edit drawer, a
detail page — can each look fine in isolation while quietly diverging in
architecture, tooling, or thoroughness. Nobody notices because no single
diff crosses both files.

1. Identify cohorts: group pages by the generic problem they solve, not by
   feature area (e.g. "every entity list/table page" is one cohort,
   regardless of which entity).
2. For each cohort with 2+ members, compare:
   - table/list markup, pagination, filter UI, search, sort — same shared
     primitive/pattern, or independently reinvented per page?
   - data-fetching, caching, and revalidation strategy — consistent, or one
     page refetches aggressively while a sibling relies on stale data?
   - test coverage and approach — comparable depth across the cohort, or
     did one page get thorough tests while an identical-shape sibling got
     none?
   - feature set — does one page support something (bulk actions, export,
     saved filters, optimistic updates) that the others structurally could
     but don't, suggesting drift rather than a deliberate product decision?
3. Classify each divergence as:
   - **justified** — the pages are only superficially similar; the
     difference reflects a real requirement difference.
   - **drift** — same problem, no reason found for solving it differently.
     A candidate for consolidating on one shared pattern.

When a cohort member is missing something its siblings have (tests, a more
robust update pattern, a validation helper), check which one is older —
`git log --diff-filter=A -- <file>` or the surrounding feature's commit
history usually shows it plainly. Drift inside one cohort is often one
member built first, its siblings built later by copying and refining it,
and the refinements never backported to the original. When that's the
shape, the fix direction is backport-to-the-newer-pattern, not "make them
consistent" in the abstract — recommend bringing the older member forward,
not picking whichever pattern is more convenient to change.

This is the internal analogue of the reference-architecture pass below —
same reasoning, comparing the repo against itself instead of an external
reference.

### 7. Reference-architecture pass (only if a reference repo is in scope)

For each notable structural decision in the audited repo that mirrors the
reference:

- **Justified adaptation** — the pattern was intentionally adapted (e.g. for
  a different API contract) and the adaptation is sound. Not a finding.
- **Cargo-cult replication** — the shape was copied but the reasoning behind
  it wasn't, and it doesn't fit here (e.g. an abstraction that existed in
  the reference to solve a problem this repo doesn't have). Finding.
- **Unexplained divergence** — the audited repo deviates from the reference
  with no visible reason and no note explaining why. Worth asking about,
  not assuming either project is wrong.

### 8. Report

Use the format below. Do not apply any change yet.

### 9. Apply (only on request)

If the user wants fixes applied, go one finding or one category at a time:
apply, run the narrowest relevant check/test, confirm before moving to the
next. Never batch-apply the whole report — a second unreviewed pass over
unreviewed findings recreates the exact problem this skill exists to catch.

When fixes span multiple findings grouped into phases (e.g. a written fix
plan), run the full check/unit/e2e suite once before starting a phase and
again at its close — not only at the very end. A clean run before each
phase gives a baseline to attribute a break to that specific phase instead
of discovering it only after everything has been applied.

When a fix means reconciling two places that disagree — a fixture/generator
and a hardcoded expectation elsewhere, a shared constant and a copy of its
value — find which one is the actual source of truth before touching
either. Trace whether anything genuinely depends on the specific frozen
value (other call sites, documented contracts) or whether it's just an
incidental duplicate that drifted. Fix the duplicate to derive from the
source; don't bend the source with a special case to keep matching a
duplicate that has no real claim on that value. Bending the source is the
easier edit and can look like the fix, but it treats symptom as cause and
leaves the actual duplication in place for the next drift.

## Output Format

```text
## Structural Audit

Scope: <what was covered> | Reference repo: <path or "none">
Target list rationale: <churn / keywords / size / duplication signals used>
Left unexamined: <areas deliberately out of scope this run, if any>

### Test Integrity (priority 1)
| File | Test | Classification | Mutation check | Evidence |
| ...  | ...  | vacuous/suspect | stayed green / went red | ... |

### Business-Logic Correctness (priority 2)
- <file:line> — <what was checked against what requirement> — <verdict>

### Structure & Duplication (priority 3)
- <finding> — <files involved> — <concrete recommendation>

### Cross-Page Consistency (if applicable)
- <cohort> — <pages compared> — justified / drift — <reasoning>

### Reference-Architecture Divergence (if applicable)
- <pattern> — cargo-cult / unexplained / justified — <reasoning>

### Out of scope by design
Naming, formatting, and folder taste were not evaluated — see this skill's
rationale.

Apply any of these now? Specify which, or "all" to go one at a time.
```

Lead with Test Integrity even when it has zero findings — say so explicitly
("N tests checked on risk-ranked targets, 0 vacuous") so the absence reads
as evidence, not omission.
