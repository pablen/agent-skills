# Findings Ledger

Read this when an audit starts (to find the ledger and decide when to read it)
and when it reports (to update it). An audit is a sample, never an inventory:
different runs, agents and models find different subsets. The ledger is what
makes runs add up instead of starting from zero each time, and what keeps
decided findings from being reported again.

## Where it lives

One ledger per repo, cumulative across runs, **versioned with the code**, so
worktree sessions, other machines and other agents see it. Default path
`docs/audit/findings.md`, unless the repo already keeps audit notes elsewhere;
then use that and say so. A gitignored notes folder works for a single
machine but hides the ledger from worktrees.

## When to read it

1. Build your own target list first (steps 1-2), without the ledger, so prior
   runs don't anchor where you look.
2. Then read the ledger and use it three ways:
   - **Dedupe**: a finding whose fingerprint matches an entry is that entry,
     not a new one. Update its evidence instead of re-reporting it.
   - **Respect decisions**: `accepted` and `wontfix` entries are not findings.
     Re-raise one only if its revisit condition is met or the code it
     describes changed materially; say which.
   - **Steer**: add areas the coverage map shows as never or shallowly
     examined to your target list.
3. Re-check `fixed` entries cheaply on risk-ranked targets (re-run the
   mutant or the probe that confirmed them). A fix that regressed reopens the
   same ID.

For a blind run (the user wants to measure the audit itself), skip the ledger
until the report is written, then reconcile.

## Entry format

One table per category, matching the report sections. IDs are stable and
never reused, with a prefix per category: `T` tests, `B` business logic, `S`
structure, `C` cross-page, `R` reference architecture, `A` follow-ups in
another repo.

| Field | Content |
|---|---|
| ID | `B12`. Never renumbered, never reused. |
| Status | See the lifecycle below. |
| Fingerprint | `category · file · symbol · rule`, e.g. `business · src/models/transfers.ts · cacheTransfer · stock cache not invalidated after execute`. The dedupe key: two runs describing the same defect in different words share it. |
| Finding | One or two sentences: what is wrong and its effect. |
| Evidence | `CONFIRMED` (red mutant, failing test or reproducible probe) or `PLAUSIBLE` (read, not reproduced), with file:line. |
| Origin | Run date and audited commit, e.g. `2026-10-18 @ 757c774`. Add a line per run that sees it again. |
| Decision | For `accepted`/`wontfix`/`deferred`: who decided, where it is documented (a spec line, an ADR), and the revisit condition. |

## Status lifecycle

- `open`: reported, no decision yet.
- `fixed <commit>`: fixed and verified; re-checked in later runs.
- `accepted`: a real trade-off the team keeps on purpose.
- `wontfix`: not worth fixing. Needs a rationale and a revisit condition, for
  example "the API enforces the 200-item cap; revisit if transfers over 50
  items appear".
- `deferred`: will be handled later, usually in another repo or after a
  product decision.
- `duplicate-of <ID>`: the same defect as another entry.

A product decision behind `accepted` or `wontfix` belongs in the project's
spec or decision log too, so implementers see it, not only auditors. The
ledger entry points at that line.

## Coverage map

A table of what each run examined, so the next run can target the rest:

| Area | Last examined | Depth | By |
|---|---|---|---|
| `src/pages/transfers/` | 2026-10-18 @ 757c774 | tests read + mutation on suspects + logic vs API | run 2 |
| `src/pages/login/` | never | — | — |

Depth is one of: `signals only`, `tests read`, `mutation on suspects`, `logic
vs spec/API`, `cross-page compared`. Every "Left unexamined" area of a report
appears here with its real depth, including `never`.
