---
name: input-perf-audit
description: Run an explicitly requested web form input performance audit with reproducible typing bursts, render-scope measurements, input-to-frame latency, and controlled isolation experiments. Use only when the user explicitly invokes `$input-perf-audit` or names `input-perf-audit`; do not activate automatically from reports of slow fields, dropped characters, caret problems, excessive rerenders, validation, or masked-input issues.
---

# Input Performance Audit

Run this workflow only after explicit invocation. Diagnose typing problems with comparable evidence before changing production behavior. Treat the audit as read-only diagnosis unless the user also asks for a fix.

## Core rules

- Read repository instructions and testing conventions first.
- Preserve unrelated and uncommitted work. Record every temporary instrumentation edit and remove only those exact edits.
- Prefer the project's existing browser and test tooling. Do not add a benchmark dependency unless existing tools cannot answer the question.
- Compare the target field with a simple field in the same form whenever possible. An isolated absolute timing has little diagnostic value.
- Do not call a rerender a bug by itself. Identify its scope, cost, frequency, and observable effect.
- Separate correctness from speed: check the final value, caret/selection behavior, formatting, paste, and request count as well as latency.
- Do not leave render counters, forced errors, disabled side effects, debug globals, or performance-only test routes behind.
- Do not commit timing thresholds that are sensitive to machine load. Prefer correctness assertions, render-scope invariants, or broad relative comparisons.
- Do not install browser tooling, download browsers, or modify project dependencies without the user's approval.

## Capability preflight

Treat browser automation as optional for static analysis but required for typing bursts, request observation, and input-to-frame latency.

1. Inspect the skills and browser tools available in the current session. Look for Playwright CLI, an in-app browser, Chrome control, or another tool that can send real keyboard events and evaluate page JavaScript.
2. Inspect the repository for an existing Playwright, Cypress, WebdriverIO, or equivalent test setup before looking for another tool.
3. Prefer, in order:
   - the project's existing browser test runner;
   - an already-available browser skill/tool;
   - an installed `playwright-cli` command;
   - a new installation, only after user approval.
4. Verify that the chosen path can navigate, locate the input, send sequential key events, evaluate JavaScript in the page, and observe requests. A screenshot-only tool is insufficient for a full audit.
5. If no suitable runtime exists, continue with static tracing and correctness tests that the repository supports. Mark render and latency measurements as unavailable rather than inventing them.

Read [references/browser-tools.md](references/browser-tools.md) for concrete checks, adapters, fallbacks, and the approved installation path. Do not declare Playwright as an `agents/openai.yaml` dependency: skill metadata currently supports MCP tool dependencies, while this workflow accepts several interchangeable browser runtimes.

## Audit workflow

### 1. Define the symptom and comparison

Capture:

- route, form, field, and a stable locator;
- exact input sequence and expected displayed/canonical value;
- whether the symptom is dropped characters, visible delay, caret movement, form-wide updates, or request churn;
- a nearby reference field that feels correct;
- what the target field does that the reference does not: mask, async validation, formatting, query enhancement, paste interception, etc.;
- browser, dev/production mode, and any CPU throttling.

Use the same browser session, string length, focus setup, and run count for target and reference. Warm both fields before recording results.

### 2. Trace the input path statically

Follow the event from the DOM input through formatting, form state, validation, subscriptions, queries, and adornments. Look for:

- controlled value feedback loops;
- form-level `watch`/subscriptions;
- parent reads of field-specific state;
- formatting or masks that rewrite value or selection;
- synchronous schema work on every change;
- `trigger`, `setValue`, `setError`, or `clearErrors` calls per key;
- debounce/query state owned by a large parent;
- unstable props or expensive siblings rerendered by field state.

For React or React Hook Form, read [references/react-rhf.md](references/react-rhf.md) before instrumenting.

### 3. Reproduce with realistic input operations

Exercise at least:

1. a zero-delay keyboard burst long enough to expose races;
2. normal typing with a small per-key delay;
3. formatted and unformatted paste when the field accepts both;
4. selection replacement in the middle;
5. delete/backspace near separators;
6. composition/IME when the input or audience makes it relevant.

Assert the final visible and canonical values. Count remote requests when validation or enhancement calls an API.

### 4. Measure render scope

Measure the target field, nearest form container, page/drawer, and any expensive sibling. Distinguish:

- component body renders;
- subtree commits from a profiler;
- DOM updates highlighted by browser or React tooling.

Use DevTools highlighting only to locate suspicious scope, then turn it off before timing. Account for development Strict Mode and remounts.

### 5. Measure latency

Collect input-event-to-next-frame samples in the page, not only wall-clock duration around a test runner command. Run at least ten comparable bursts after warm-up and report median plus p95.

Treat frame timing as a user-perceived scheduling proxy, not a laboratory paint measurement. Record the final value and dropped/mismatched events beside timing results.

### 6. Isolate one cause at a time

Make small, temporary experiments and rerun the same probe after each one. Typical isolation order:

1. localize or disable a parent field subscription;
2. disable remote checking while preserving local input behavior;
3. bypass mask/formatter with a plain input;
4. bypass synchronous validation or derived adornment work;
5. replace controlled feedback with the framework's recommended integration seam;
6. profile expensive siblings only if the form container still rerenders.

Do not combine experiments. Run every applicable experiment even when an earlier one already reduces the gap — input slowdowns often have more than one contributor. After the full isolation round, attribute the gap proportionally: "X contributed ~60% of the slowdown and Y the remaining ~40%." The goal is complete attribution, not the first plausible culprit.

### 7. Classify the result

Use one or more concrete categories:

- subscription fan-out;
- controlled-input feedback loop;
- mask/caret race;
- synchronous validation cost;
- async query/request churn;
- expensive render subtree;
- unstable props or derived state;
- development/tooling artifact;
- no reproducible performance defect.

State the smallest seam that owns the problem and whether a change is warranted. If the user asked for a fix, implement it only after establishing a baseline, then repeat the same measurements.

### 8. Clean up and verify

Remove all temporary probes through precise edits. Search for their labels/debug globals, inspect the working tree, and run the smallest relevant correctness suite. Run broader repository checks when production code changed.

## Report format

Return a compact evidence-based report:

```text
Result: confirmed | partially confirmed | not reproduced
Symptom: ...
Environment: ...
Browser capability: existing project runner | browser tool | playwright-cli | unavailable

Measurements:
| Scenario | Final value | Field renders | Form/page renders | Median input→frame | p95 | Requests |
| ...      | ...         | ...           | ...               | ...                | ... | ...      |

Complexity gap: ...
Cause: ...
Evidence: ...
Recommendation or change: ...
Correctness checks: ...
Temporary instrumentation removed: yes | no, with reason
Limitations: ...
```

Include raw measurements only when they help reproduce or challenge the conclusion. Lead with the observed outcome, not a narration of commands.
