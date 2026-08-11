# Browser capability preflight

Use this reference before running dynamic typing or latency probes.

## Required capabilities

Require a runtime that can:

- open the target application in a real browser;
- locate and focus the target and reference inputs;
- send sequential keyboard, paste, selection, delete, and backspace events;
- evaluate JavaScript in the page for `performance.now()` and `requestAnimationFrame()` sampling;
- observe or intercept requests when the field has remote behavior.

Accessibility snapshots and screenshots help locate a symptom but do not replace event or timing probes.

## Selection order

| Available capability | Action |
| --- | --- |
| Existing Playwright/Cypress/WebdriverIO suite | Reuse its server, authentication, fixtures, and browser lifecycle |
| Browser or Chrome control tool with keyboard and page evaluation | Use it without changing project dependencies |
| `playwright-cli` skill and command | Read that skill, open a session, and run probes through the same page |
| Local Playwright package only | Prefer the existing test runner; otherwise check whether `npx playwright cli` is available |
| jsdom/unit tests only | Test correctness but report render/paint latency as unavailable |
| No suitable runtime | Complete static analysis and ask before installing anything |

Do not require the `playwright-cli` skill when the repository already has an adequate runner. The skill supplies efficient operating instructions; the CLI or runner supplies the actual browser capability.

## Read-only checks

Inspect the current session's available skills/tools first, then inspect the repository:

```bash
rg -n '(@playwright/test|playwright|cypress|webdriverio)' package.json pnpm-lock.yaml yarn.lock package-lock.json 2>/dev/null
rg -n '(test:e2e|playwright|cypress|webdriver)' package.json 2>/dev/null
command -v playwright-cli
npx --no-install playwright --version
```

Adapt filenames to the package manager and workspace layout. `npx --no-install` must not download a package; a failure means only that this local path is unavailable.

Also inspect existing E2E configuration for its server command, base URL, authentication, fixtures, browser choice, and environmental prerequisites. Do not start services that require new authority.

## Using Playwright CLI

When the `playwright-cli` skill is available, read it and follow its current command syntax. Prefer one named session for the audit so setup, authentication, and probes share the same page. Use its page-code execution capability for the sampling code in [react-rhf.md](react-rhf.md).

If the command exists but its skill is missing, `playwright-cli --help` is an acceptable operating reference. Offer to install the official skill integration only when it would materially improve repeated use.

## Installation path

Ask for approval before network access, a global npm install, browser downloads, or skill-directory writes.

Prefer an already-local Playwright installation when it exposes the CLI:

```bash
npx playwright cli --help
```

Otherwise use Microsoft's official Playwright CLI installation for Node.js 18 or newer:

```bash
npm install -g @playwright/cli@latest
playwright-cli --help
playwright-cli install --skills
```

After installation:

1. verify `playwright-cli --help` succeeds;
2. verify the agent can discover the installed `playwright-cli` skill;
3. follow any explicit prompt for a browser binary rather than downloading one preemptively;
4. note that a new agent session may be required for skill discovery.

Do not add Playwright to the audited project's dependencies merely to satisfy this skill unless the user wants a project-owned E2E setup.

## Degraded audit

When no browser capability is available, still provide:

- the input data-flow and subscription map;
- likely fan-out, validation, formatter, mask, and query seams;
- existing unit/jsdom correctness coverage;
- an exact dynamic probe plan and the missing capability.

Label the result `partially confirmed` unless static evidence alone proves the requested issue. Never report user-perceived latency from test-runner wall time or jsdom.
