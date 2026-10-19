---
name: exploratory-qa
description: Run an exploratory QA pass on a web frontend by driving its screens in a real browser with API-shaped mock data, and checking concrete oracles (rendered values against the data, sent payloads against what the user reviewed, no crashes). Use when the user asks for a QA pass, exploratory testing or a smoke test of screens, or when the project's instructions ask for one before handing off a UI change.
---

# Exploratory QA

Code review and structural audits read code. A whole class of bugs only shows
up when someone **uses** the screen with data shaped like the real API: a date
rendered one day off, a crash on a hand-edited URL, a draft that executes a
different quantity than the one on screen, a list that drops an item while
something is still loading. A human QA finds these in minutes; reading code
mostly doesn't. This skill is that QA pass, run by an agent: cheap enough to do
on every UI change, and a full sweep before a release.

## Rules

- **Report, never fix.** The output is a list of candidate bugs with evidence.
  Don't touch application code. Temporary specs and scripts live outside the
  test suite and are deleted at the end, unless the user keeps them.
- **The mock is the oracle, so it must be honest.** Every value a fixture
  returns has the exact shape the real API returns: an API that stores a
  midnight-UTC timestamp returns that, not a convenient `T12:00Z` that hides
  the timezone bug. A candidate bug caused by an unrealistic fixture is a
  fixture bug, not an app bug.
- **Mocked API by default.** Run the app against a fully mocked API in a
  dedicated dev server, with a catch-all route so nothing reaches a real
  backend. Real data only in the user's own browser session, with the user
  logged in; never type credentials.
- **Oracles over impressions.** "Looks fine" is not a result. Every check
  compares something observable against something known: the fixture value,
  the payload the user reviewed, the URL that was loaded.
- **Budget.** Per change: the screens it touched, about 5-15 minutes each. Per
  release: every screen. Stop and report rather than going deeper on one screen.

## Workflow

### 1. Scope

Pick the mode and list the screens:

- **Per change** (default): map the changed files (`git diff` against the base
  branch) to the routes and screens that render them.
- **Sweep**: every route in the router.

For each screen, note its type (list, detail, create/edit form, draft editor
with a confirm step, report) and the flows the spec or tests describe for it.
Done when every screen in scope has a type and a flow list.

### 2. Environment

Reuse the project's E2E setup when it has one (Playwright with mocked routes is
the usual case): its fixtures, its fake session, its free-port dev server.
Otherwise start a dedicated dev server pointed at a mocked API base and seed a
fake session. Add the catch-all route before anything else.

Done when the app loads in scope screens with no request leaving the mock.

### 3. Fixtures with the real shape

For each endpoint the screens call, build fixtures from what the API actually
returns: read the API's response schema and serializer, or sanitize a captured
real response. Then add the breaking data from
[references/heuristics.md](references/heuristics.md) ("Data that breaks
things") that applies to those fields.

Done when every field the screens render comes from a fixture whose format
matches the API's real output, and each applicable breaking-data case exists.

### 4. Tour

For each screen, run the tour for its type in
[references/heuristics.md](references/heuristics.md). Take a screenshot at
each state worth seeing (loaded, empty, error, dialog open, after save) and
record every request the screen sends.

Done when every applicable tour item for every screen in scope has run, or is
listed as skipped with a reason.

### 5. Oracles

Check each recorded state and request against
[references/oracles.md](references/oracles.md). Every mismatch is a candidate
bug: steps to reproduce, expected, actual, the oracle that caught it, and a
screenshot.

### 6. Confirm

Re-run each candidate once on its own to rule out a flake, and re-check the
fixture behind it against the API's real output. Drop the candidates that turn
out to be fixture artifacts, and say so in the report.

Done when every remaining candidate reproduced twice on a fixture that matches
the API.

### 7. Report

Use the format below. Offer two follow-ups and wait for the user:

- Record the confirmed candidates in the project's bug tracker or audit notes.
- Keep a check as a permanent E2E test when it guards a stable invariant, such
  as "every rendered date matches its fixture in the business timezone". This
  is a proposal; adding it to the suite is a later task the user approves.

## Report format

```text
## Exploratory QA

Mode: per change | sweep — Screens: <list> — Fixtures: <source: API schemas / captured responses>
Skipped: <screens or tour items not run, with reason>

### Confirmed candidates
| # | Screen | Steps | Expected | Actual | Oracle | Evidence |
| 1 | ...    | ...   | ...      | ...    | ...    | screenshot path |

### Dropped
- <candidate> — fixture artifact / flake — <why>

### Checks worth keeping (proposal)
- <invariant> — <screen(s)> — <why it is stable>
```

Lead with confirmed candidates even when there are none, and say how many
tour items ran, so "nothing found" reads as evidence and not as omission.
