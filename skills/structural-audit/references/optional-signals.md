# Optional Signals by Repo Type

Read this when the audited repo has the matching surface: async-heavy UI
tests, a separate API repo, date-only business values, or a TypeScript
codebase whose strictness you want to probe. Each tool here is a **signal**:
it prioritizes what to read in steps 3-6. None of its output is a finding on
its own, and none of it replaces reading the code.

## Test async hygiene

Tools: `eslint-plugin-vitest` (`expect-expect`), `eslint-plugin-testing-library`
(`await-async-queries`, `no-wait-for-side-effects`, `prefer-find-by`) and
`@typescript-eslint/no-floating-promises`, run through a temporary config that
only reports.

- **Catches:** tests that never assert, async queries and interactions that
  are not awaited, promises nobody waits for.
- **Misses the worst case:** an expectation that is present, awaited and
  irrelevant. `expect(post).not.toHaveBeenCalled()` on a flow that never
  reaches the confirmation click passes every rule here and still proves
  nothing. Classification and the mutation check stay the authority.
- **False positives:** side-effect tests, controlled callbacks, promises
  discarded on purpose.
- **Use:** feed the hits into step 3 as tests to read first.

## Contract registry per endpoint and direction

Build an explicit registry, one row per endpoint and direction, before
comparing anything:

| Endpoint | Direction | Serializer | Frontend schema | API schema |
|---|---|---|---|---|
| `POST /x/drafts` | request | `serializeDraft` | `draftInputSchema` | `draftCreateSchema` |
| `GET /x/:id` | response | — | `detailResponseSchema` | response builder |

Start from OpenAPI when the API publishes it. Otherwise map it by hand from
the frontend API helpers and the API routes. Compare the schemas through a
machine-readable form (for Zod 4, `z.toJSONSchema()`) for required vs
optional, nullable, format, ranges, string lengths and array maximums.

- **The serializer is part of the contract.** It can omit, convert or null a
  field the schema allows, so read it for every row with a mismatch or a
  date, nullable or optional field.
- **Not expressible in the diff:** `refine`/`superRefine` and cross-field
  rules, transforms and defaults, omitted vs `undefined` vs `null` in real
  JSON, rules that differ by state transition, and date semantics (a `date`
  string carries no business calendar or timezone).
- **Legitimate differences:** form schemas, DTOs and request schemas can
  differ on purpose. Only the HTTP payload schemas belong in the registry.
- **Use:** a targeted reading list for step 4. It narrows the comparison of
  validations; it does not replace it.

## Date and timezone matrix, with properties

Run the tests of date helpers and date serializers under `TZ=UTC` and under
the business timezone. Start with that subset, not the whole suite: snapshots,
fixed-date mocks and libraries that read `TZ` at startup make a full-suite
matrix noisy.

Add property-based tests (`fast-check` with a fixed seed) for parse/format
round trips, month lengths 28-31, leap years and operational day boundaries.

- **The oracle must be independent.** A property that compares two
  implementations can pass while both share the bug. Derive it from a rule
  written in the spec, or check it against the API's real validator.
- **Real API validators go through a local audit adapter:** a script outside
  the app, never a frontend dependency. If the validator pulls in an ORM,
  config or environment variables, don't use it; the probe would be fragile.
  Label such a property as specific to that repo pair.
- **Use:** add a property only when its invariant is written in the spec or
  agreed with the API.

## Type strictness probe

Run `tsc` with a temporary tsconfig that adds `noUncheckedIndexedAccess` and
`exactOptionalPropertyTypes`, and `type-coverage` for `any` and casts.
Segment the output by `models/`, `auth/`, `api/` and pure utilities.

- **What the count means:** distance to a stricter configuration, not product
  risk. React components, fixtures and third-party boundaries inflate it.
- **Limit:** the compiler marks an unchecked index; it cannot tell whether the
  index points at the right entity. A reindexed row inheriting the wrong state
  is a semantic bug the probe only points near.
- **Read casts by place, not by percentage:** an `any` encapsulated in an
  adapter can be fine; an `as` over an API response is more dangerous even
  when the global number looks good.
- **Use:** a reading list. Never a gate, never a list of fixes.
