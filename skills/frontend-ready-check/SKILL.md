---
name: frontend-ready-check
description: Checks if a frontend task/bug is ready to implement by comparing real frontend usage against backend/service support and related tracker work. Use to find concrete blockers (not guesses) or to separate what can proceed now from what needs backend/product decisions.
---

# Frontend Ready Check

Use this skill to answer questions such as:

- "Can I start this frontend task now?"
- "Is this blocked by backend?"
- "What exactly is missing?"
- "What can I build while backend catches up?"
- "Is there already a tracker issue for the missing capability?"

## Core Rules

- Prefer code and repo docs over tracker descriptions, generated clients, or API summaries.
- Base the verdict on evidence from the active frontend repo and the relevant backend or service repo.
- Read defaults from active context first: `AGENTS.md`, repo docs, workspace layout, or user-provided paths.
- Do not assume a specific tracker, backend repo name, sibling path, or project key unless the active context already provides it.
- Use a tracker skill only if one is available in the session, and usually after checking code and docs first.
- Use only three statuses: `READY`, `PARTIALLY READY`, or `BLOCKED`.
- Name blockers concretely: missing endpoint, missing field, missing validation, missing permission, missing side effect, missing business rule, or missing product decision.
- Always say what the frontend can still advance now.
- Distinguish proven facts from inference.

## Fast Path

1. Build the request snapshot.
   - Capture the user action, entity, screen, write/read path, and any known blocker.
   - If the user provided a tracker issue and a tracker skill is available, read it for context only.
2. Scan the frontend first.
   - Prefer app entry points such as `src/models`, generated API clients, feature hooks, and the target page tree.
   - Search with focused nouns and endpoint terms rather than vague UI wording.
3. Scan the backend or service layer next.
   - Prefer module docs first when they exist.
   - Then read routes, controllers, validations, permissions, policies, and model code.
4. Compare the requested UX against the real contract.
   - Confirm request shape, response shape, permissions, filters, side effects, and error cases.
5. Decide the status.
6. Search the tracker only if support is missing, ambiguous, or already suspected to exist elsewhere.

## Heuristics

- Strong evidence for `READY`:
  - A matching endpoint or service capability already exists.
  - Validation and request shape already support the flow.
  - The frontend already consumes the same or a very similar contract elsewhere.
- Strong evidence for `PARTIALLY READY`:
  - The main capability exists but a field, filter, action, permission, or side effect is still missing or unclear.
  - Read-only or shell UI work can move while write flows or edge cases wait.
- Strong evidence for `BLOCKED`:
  - No supporting route, service, or model path exists for the core capability.
  - The backend contract contradicts the requested UX.
  - A product or business-rule decision is required before choosing the correct contract.

## Search Discipline

- Start with explicit nouns and capability names from the request.
- Prefer 1 to 3 focused searches over one long fuzzy search.
- Search endpoint nouns before UI wording.
- Treat generated API code and generic CRUD scaffolding as hints, not proof of full support.
- When route files are noisy, open module docs or validations before reading the full implementation.

## Fixed Output

Use this shape in the final answer:

```text
Status: READY | PARTIALLY READY | BLOCKED
Summary: one sentence
Evidence:
- ...
Blockers:
- ...
Can advance now:
- ...
Claims / asks:
- ...
Tracker follow-up:
- ...
Files checked:
- ...
```
