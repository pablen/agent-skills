---
name: frontend-code-quality-setup
description: Audit and apply a standard set of code quality configurations to a frontend project. Covers VSCode settings, packageManager pinning, scripts, exact dependency version policy, depcheck, optional audit-ci, git hooks, lint-staged, .gitignore hygiene, and agent files (AGENTS.md, CLAUDE.md, GEMINI.md). Supports web frontend, Next.js, Payload CMS, React Native, and Expo projects. Runs interactively — audits first, applies per section after confirmation.
---

# Frontend Code Quality Setup

Use this skill to bring a frontend project up to a standard baseline of code quality tooling. It audits the current state first and proposes changes section by section before applying anything.

## Trigger

User invokes `/frontend-code-quality-setup` or asks to "set up code quality" / "apply quality baseline" on a project.

## Core Rules

- Always audit before applying. Never modify files without showing what will change and getting confirmation.
- Detect project context automatically — do not assume package manager, framework, ESLint config style, or Prettier settings.
- Apply only what is missing or incorrect. Never overwrite correct existing configuration.
- Work section by section. After completing all audits, ask the user which sections to apply (all or specific ones).
- Sections are independent — applying one should never break another.
- Do not suggest framework-specific files, ignores, or checks unless the detected project type supports them.
- For Payload repos, distinguish framework-generated files from user-owned files before suggesting format, ignore, or dependency cleanup changes.
- Keep the baseline focused on code quality and repo hygiene. Do not fold app behavior, branding, or local DX tweaks into the baseline unless they are explicitly presented as optional suggestions.

## Context Detection

Before auditing, detect the following automatically:

- **Package manager**: check for `package-lock.json` (npm), `yarn.lock` (yarn), `pnpm-lock.yaml` (pnpm)
- **Package manager declaration**: read `package.json` `packageManager` when present; compare it with the detected lockfile/package manager and note the pinned tool/version
- **Project type**:
  - **Next.js**: `next` dependency, `next.config.*`, `app/`, `pages/`
  - **Payload CMS**: `payload` dependency, `@payloadcms/*` packages, `payload.config.*` or `src/payload.config.*`, `src/app/(payload)` or `app/(payload)`
  - **SPA React web**: `react` without React Native markers
  - **React Native**: `react-native` dependency, `ios/`, `android/`, `metro.config.*`, `react-native.config.*`
  - **Expo / Expo modules**: `expo` dependency, `app.json`, `app.config.*`
- **Prettier `printWidth`**: read `.prettierrc` / `prettier.config.*` — used for VSCode `editor.rulers`
- **Tailwind usage**: detect `tailwindcss` dependency and identify the main stylesheet path when possible — used for Prettier plugin suggestions
- **ESLint config style**: check for `eslint.config.*` (flat config) vs `.eslintrc.*` (legacy) — used for `eslint.useFlatConfig`
- **TypeScript project style**:
  - whether `tsconfig.json` uses `references`
  - whether `compilerOptions.composite` is set
  - whether React Native/Expo suggests a more pragmatic `skipLibCheck` flow
- **TypeScript path aliases**: read `tsconfig.json` `paths`
- **TypeScript `baseUrl` aliases**: if `baseUrl` is set without `paths`, treat top-level source folders as potential depcheck false positives when the repo imports through source-root aliases
- **Dependency version policy**: whether `package.json` uses exact versions or semver ranges
- **Package manager config files**: `.npmrc`, `.yarnrc`, `.yarnrc.yml`, `pnpm-workspace.yaml` — used to enforce exact versions by default
- **pnpm version**: when pnpm is detected, read `packageManager` or run `pnpm --version` to determine major version (v10 vs v11+) — affects where `save-exact` is configured
- **Prettier version**: detect via `prettier` dep in `package.json` — used to determine `--ignore-unknown` support (requires Prettier 3.0+)
- **Tailwind major version**: detect via `tailwindcss` dep version — used to adapt `@theme`/`@theme inline` suggestions (v4+) vs `@tailwind` directives (v3)
- **Next.js version**: detect via `next` dep version — used for ESLint flat config import style guidance (Next.js 16+ uses direct imports)
- **Yarn generation**: when Yarn is detected, check whether the repo is using or accidentally invoking Yarn Berry/modern Yarn; prefer Yarn Classic `1.22.22` unless the repo has clear intentional Berry/PnP setup
- **Lockfile name**: used for `search.exclude` in VSCode settings
- **Mobile toolchain markers**: `babel.config.*`, `metro.config.*`, `app.json`, `app.config.*`, `ios/Podfile`, `ios/Podfile.lock`, `android/`, Gradle files — used when evaluating depcheck and `.gitignore`
- **Payload markers**:
  - whether the repo uses `@payloadcms/next`
  - whether generated files exist such as `src/payload-types.ts`, `src/payload-generated-schema.ts`, and generated `src/app/(payload)` routes/layout files
  - whether admin custom components exist under `src/app/(payload)/_components` or similar, which affects `generate:importmap`
  - whether `next-env.d.ts` is stable or churns due to Next route type generation in a Payload + Next setup

## Sections

### 1. VSCode Settings (`.vscode/settings.json`)

Check for and add if missing:
- `"npm.packageManager"` — set to detected package manager
- `"search.exclude"` — exclude the lockfile (e.g. `package-lock.json`, `yarn.lock`)
- `"editor.formatOnSave": true`
- `"editor.defaultFormatter": "esbenp.prettier-vscode"`
- `"editor.codeActionsOnSave": { "source.fixAll.eslint": "explicit" }`
- `"editor.rulers"` — set to `[<printWidth>]` from Prettier config (default 80 if not found)
- `"eslint.validate"` — `["javascript", "javascriptreact", "typescript", "typescriptreact"]`
- `"eslint.useFlatConfig"` — only if flat config detected
- `"prettier.enable": true`
- `"prettier.requireConfig": true`
- `"js/ts.tsdk.path"` — set to the workspace TypeScript version when a project-specific version is detected (e.g. `"node_modules/typescript/lib"`), ensuring VSCode uses the same TS version and any compiler plugins (such as the Next.js TS plugin) are active
- `"tailwindCSS.lint.suggestCanonicalClasses"` — **only for Tailwind repos**, set to `"ignore"` if the team prefers arbitrary value classes (e.g. `w-[260px]`) over Tailwind's canonical shorthand equivalents (e.g. `w-65`). This silences IntelliSense lint warnings that some developers find noisy.

For React Native / Expo repos, also check whether these extra excludes are useful and add if missing when those files exist:
- `"**/Podfile.lock"`
- `"android/dependencies.txt"`
- `"**/*.bundle"`

### 2. VSCode Extensions (`.vscode/extensions.json`)

Create or update with recommendations:
- `"dbaeumer.vscode-eslint"`
- `"esbenp.prettier-vscode"`
- `"mikestead.dotenv"`

Optional, only if context supports it:
- `"msjsdiag.vscode-react-native"` for React Native repos

### 3. Scripts (`package.json`)

Add if missing:
- `"typecheck"`
  - use `tsc --build --noEmit` when the repo uses project references or `composite`
  - otherwise prefer `tsc --noEmit --skipLibCheck`
- `"check-dependencies": "depcheck"`
- for Payload repos, also suggest if missing:
  - `"generate:types"` — `payload generate:types` (preserve existing wrapper style such as `cross-env` if the repo already uses it)
  - `"generate:importmap"` — `payload generate:importmap` when the repo uses `@payloadcms/next` or custom admin components
- `"doctor"` — **optional**, only suggest for mobile repos:
  - Expo: `npx expo-doctor`
  - React Native CLI: `npx react-native doctor`
- `"audit:critical": "audit-ci --critical"` — **optional**, not baseline by default for pure frontend/mobile repos
- `"devsafe"` — **optional**, suggest for Next.js repos: `"rm -rf .next && next dev"` (useful when Turbopack cache becomes stale and causes unexplained errors)

When suggesting `devsafe`:
- only suggest if the repo is Next.js
- present as a manual troubleshooting convenience, not a baseline requirement

### 4. Package Manager Declaration (`package.json`)

Audit `package.json` for the `packageManager` field when the repo has a JavaScript package manifest.

Baseline:

- **All repos** should declare a pinned `packageManager` field. This prevents accidental use of the wrong package manager or version across environments (local, CI, Corepack).
- If the repo uses Yarn (`yarn.lock` detected), strongly recommend:
  - `"packageManager": "yarn@1.22.22"`
  - Reason: these repos expect Yarn Classic behavior; pinning prevents Corepack or local shells from accidentally invoking Yarn Berry/modern Yarn in installs, hooks, or CI.
- If the repo uses pnpm (`pnpm-lock.yaml` detected), require a pinned `packageManager` value such as:
  - `"packageManager": "pnpm@<detected-version>"`
  - Use the version already declared in the repo when present; otherwise detect local `pnpm --version` if available and present the exact value before applying.
- If the repo uses npm (`package-lock.json` detected) or has no clear package manager, **strongly recommend migrating to pnpm**:
  - Benefits: faster installs, disk-efficient (linked store), strict dependency resolution, built-in workspace support
  - Present the migration as a separate optional workflow (lockfile change, CI update, team coordination)
  - Do not automatically migrate — the user must opt in

When auditing:

- report whether `packageManager` is missing
- report mismatches between lockfile and `packageManager` such as `yarn.lock` with `packageManager: pnpm@...`
- report Yarn major mismatches, especially Yarn repos missing `packageManager` or declaring Yarn 2+
- if the repo has `.yarnrc.yml`, `.pnp.cjs`, `.yarn/releases`, or other clear Berry/PnP markers, treat Yarn Berry as intentional and ask before recommending a Yarn Classic change
- make the pnpm suggestion explicit but optional when migration would require lockfile and workflow changes

When applying:

- for Yarn Classic repos, add or update `packageManager` to `yarn@1.22.22` after confirmation
- for pnpm repos, add or update `packageManager` to the confirmed pnpm version after confirmation
- for npm or packageManager-less repos, require `packageManager` declaration after the pnpm migration decision (if user opts in, add as pnpm; if not, do not add npm packageManager as that would be misleading)
- after changing `packageManager`, run the repo's standard package-manager command/version check and any required verification commands

### 5. Exact Dependency Versions (`package.json`, `.npmrc`, `.yarnrc`, `.yarnrc.yml`)

Audit two things:

- whether dependency versions in `package.json` are exact
- whether the package manager is configured to save exact versions by default

Treat as exact:

- plain pinned versions such as `1.2.3`

Do not treat as exact:

- semver prefixes or ranges such as `^`, `~`, `>`, `>=`, `<`, `<=`, `*`, `x`

Do not flag as non-exact:

- `file:` / `link:` / `workspace:` / git URLs / other non-registry specs

Package-manager defaults:

- **npm**: `.npmrc` with `save-exact=true`
- **pnpm**: depends on pnpm major version:
  - **pnpm v10 and older**: `.npmrc` with `save-exact=true`
  - **pnpm v11+**: `pnpm-workspace.yaml` with `saveExact: true` and `savePrefix: ""` (`.npmrc` no longer accepts non-auth settings in v11)
- **Yarn Classic**: `.yarnrc` with `save-exact true`
- **Yarn Berry**: `.yarnrc.yml` with `defaultSemverRangePrefix: ""`

When auditing:

- report non-exact dependency specs separately for `dependencies` and `devDependencies`
- report whether the package manager default is configured correctly
- if the repo mixes exact and ranged versions, surface that explicitly instead of assuming it is accidental

When applying:

- add or update the package-manager config file needed to make exact versions the default
  - for pnpm v11+, write to `pnpm-workspace.yaml` instead of `.npmrc`
- do **not** rewrite all existing dependency specs automatically without explicit confirmation
- if the user wants normalization, propose the package changes separately from the config-file change

### 6. Dev Dependencies (`package.json`)

Add to `devDependencies` if missing:
- `"depcheck"` — latest stable
- `"audit-ci"` — latest stable, **only if the repo should opt into npm audit gating after agent evaluation**

**Import sort plugin** — strongly suggest adding if missing:
- `"@ianvs/prettier-plugin-sort-imports"` — latest stable (fork of `@trivago/...`)
- Justification: consistent import order across all developers, one less thing to think about in code reviews
- If the repo already uses `@trivago/prettier-plugin-sort-imports`, suggest migrating to `@ianvs/...` (maintained fork, same API, compatible with Prettier 3.x and TypeScript 5+)
- If accepted, add to `plugins` array in Prettier config and configure `importOrder`

For Tailwind repos, also evaluate and suggest if missing:
- `"prettier-plugin-tailwindcss"` — latest stable compatible with the repo's Prettier / Tailwind stack

When suggesting the Tailwind Prettier plugin:
- verify Tailwind is actually used in the repo, not just installed transitively
- if accepted, also audit Prettier config for:
  - `"plugins": ["prettier-plugin-tailwindcss"]` or correct composition with existing Prettier plugins
  - do **not** suggest `"tailwindStylesheet"` for Tailwind v4 — it is a v3-only option (Tailwind v4 uses CSS `@import` and `@theme`; there is no single stylesheet entrypoint to declare)
  - for Tailwind v3, suggest `"tailwindStylesheet"` when a clear entrypoint exists (e.g. `./src/app/globals.css`)
  - `"tailwindFunctions"` only if the repo actually uses helpers such as `twMerge` / `twJoin`
- do not add `tailwindFunctions` speculatively
- if another Prettier plugin is present, ensure `prettier-plugin-tailwindcss` is placed **last** in the `plugins` array

Run install after adding.

### Audit policy for `audit-ci`

`audit-ci` is **opt-in**, not mandatory baseline.

Default behavior:

- Do **not** add `audit-ci` automatically as part of the baseline.
- Do evaluate whether it is worth suggesting for this repo.
- In pure frontend/mobile repos, default to **not** adding it unless the signal is likely to be worth the noise.
- In repos where dependency audit gating is likely to be valuable, explicitly suggest it to the user as an optional addition.

Reason:

- npm advisories in frontend/mobile repos often include a high volume of tooling-only or non-runtime issues.
- Without a repo-specific triage policy, `audit-ci` often creates more noise than signal.

When deciding whether to suggest it, explain:

- vulnerabilities in npm packages can matter in React Native when the affected code is actually bundled into the app or exposed through native modules
- many advisories still affect only build/dev tooling or server-side scenarios and are not exploitable in the shipped mobile runtime
- therefore `audit-ci` should be suggested with judgment, not added as a default baseline

If recommending it, the audit should include a policy discussion:

- whether the repo wants audit gating in local hooks, CI, or both
- whether the repo should start with `--critical` only
- whether an ignore/allowlist policy is needed to avoid known noisy advisories
- whether the repo type makes npm audit signal strong enough to justify the maintenance cost

### 7. Depcheck Config (`.depcheckrc`)

Run `depcheck` and analyze output:
- Identify **true unused** deps: search the codebase for actual usage, check the lockfile for peer/optional dep chains, inspect scripts/config, and research what the npm package actually is
- Identify **false positives**: PostCSS plugins, ESLint configs, Prettier plugins referenced only from Prettier config, type definitions, path aliases, shebang runners (`tsx`), build/deploy script deps
- Generate `.depcheckrc` with `ignores` for confirmed false positives
- Report true unused deps separately for the user to decide — do not remove them automatically without explicit confirmation
- Add detected TypeScript path aliases to `ignores` in the config
- If `baseUrl` exists without `paths`, consider source-root aliases as likely false positives and verify them before reporting

For React Native / Expo repos, also inspect these before classifying a dependency as unused:
- `babel.config.*`
- `metro.config.*`
- `react-native.config.*`
- `app.json` / `app.config.*`
- `ios/Podfile`, `ios/Podfile.lock`
- `android/` Gradle files
- native-module autolinking behavior

Common React Native / Expo depcheck false positives to watch for:
- Expo packages referenced via app config or native module integration
- React Native packages used only through autolinking or native registration
- `@react-native-community/cli*`
- `@react-native/gradle-plugin`
- Babel plugins and Metro config dependencies
- env/config helpers such as `react-native-dotenv`
- build/release-only tooling deps

For Payload repos, also inspect these before classifying a dependency:
- `payload` and `@payloadcms/next` peer requirements, especially `graphql`
- `src/payload.config.*`
- generated admin and API files under `src/app/(payload)` / `app/(payload)`
- `src/app/(payload)/custom.scss` and related stylesheet imports
- CLI scripts such as `payload generate:types` and `payload generate:importmap`

Common Payload false positives / special cases:
- `graphql` may still be required as a direct dependency because `payload` and `@payloadcms/next` declare it as a peer dependency, even when GraphQL routes are disabled
- `sass` may be needed only through Payload admin styling such as `src/app/(payload)/custom.scss`
- PostCSS / Tailwind plugins follow the normal frontend false-positive rules
- Prettier plugins such as import-sorting or Tailwind plugins may be used only through `.prettierrc` / `prettier.config.*` and should not be reported as unused just because they are not imported from application code

Common Payload true-unused candidates:
- `@payloadcms/ui` is often removable if there are no direct imports from it in the repo, because Payload already brings it transitively where needed
- if `graphQL.disable` is enabled in Payload config, generated GraphQL route files may be removable cleanup candidates, but direct `graphql` dependency still requires peer-dependency verification before removal

### 8. Git Hooks (Husky)

Check `.husky/pre-commit` and `.husky/pre-push`. Apply the following structure if missing or weaker:

**pre-commit:**
```sh
#!/bin/sh

# On pre-commit, run lint-staged against staged files only.
# AI_MODE suppresses verbose output to avoid flooding agent context.
if [ -n "${AI_MODE:-}" ]; then
  exec npx lint-staged --quiet
else
  exec npx lint-staged --verbose
fi
```

**pre-push:**
```sh
#!/bin/sh

# Captures output and only prints it on failure.
run_quiet() {
  label="$1"; shift
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/<project>-pre-push.XXXXXX")" || exit 1
  if "$@" >"$tmp_file" 2>&1; then
    rm -f "$tmp_file"; printf 'OK %s\n' "$label"; return 0
  fi
  printf 'FAILED %s\n' "$label" >&2; cat "$tmp_file" >&2; rm -f "$tmp_file"; exit 1
}

if [ -n "${AI_MODE:-}" ]; then
  run_quiet "dependency check" <pm> run --silent check-dependencies
  run_quiet "typecheck" <pm> run --silent typecheck
  # Only add audit:critical here if the repo explicitly opted into audit-ci.
  exit 0
fi

<pm> run check-dependencies
echo "Running TypeScript type check..."
if <pm> run typecheck; then echo "Type check passed."; else echo "Type check failed."; exit 1; fi
# Only add audit:critical here if the repo explicitly opted into audit-ci.
```

Replace `<pm>` with the detected package manager. Replace `<project>` with the project name from `package.json`.

Note: if the project already has a `build` step in pre-push, preserve it at the end of the non-AI_MODE block.

For React Native / Expo repos:
- Do **not** add `pod install`, Gradle builds, native builds, or `expo prebuild` to hooks as part of the baseline.
- Do **not** add `doctor` to hooks by default.
- Keep mobile-specific health checks as optional manual or CI steps unless the repo explicitly wants them in hooks.

For Payload repos:
- Do **not** add `generate:types` or `generate:importmap` to hooks by default as part of the baseline; these are useful manual verification steps but often too noisy for every commit/push
- Do **not** add schema/codegen mutation steps to hooks unless the repo explicitly wants generated files enforced locally

### 9. lint-staged (`package.json`)

Check the `lint-staged` config.

**Prettier pattern:**
- If the repo uses Prettier 3.0+, prefer a single `"*"` pattern with `--ignore-unknown`:
  ```json
  "*": ["prettier --write --ignore-unknown"]
  ```
  This is simpler, covers all file types automatically, and does not require maintaining an extension list.
- If Prettier < 3.0 (no `--ignore-unknown` support), use the explicit glob approach and ensure it includes: `json`, `css`, `scss`, `md`, `html`, `yaml`, `yml`. Add missing extensions without changing the existing glob structure.

When migrating from explicit globs to `--ignore-unknown`:
- verify the repo is on Prettier 3.0+ before suggesting
- this also works with Prettier plugins (Tailwind, import sort) which only act on relevant file types internally

### 10. `.gitignore` Hygiene

Always check for and fix:
- **Duplicated entries** — remove duplicates
- **`tsconfig.tsbuildinfo`** — should be ignored (generated build cache). If already tracked in git, run `git rm --cached tsconfig.tsbuildinfo`
- **`.claude/settings.local.json`** — should be ignored (local agent settings)
- **`node_modules/`** — verify present

Framework-specific checks:

**Next.js only**
- **`next-env.d.ts`** — audit both approaches and present trade-offs to the user:
  - **Committed** (follows Next.js docs recommendation): guarantees identical file across environments, but adds a generated file to the repo
  - **Ignored** (default `create-next-app` behavior): keeps repo clean of generated output, `next dev` regenerates it automatically
  - Let the user decide — do not force either direction
- **`.next/`** — should be ignored

**Payload + Next.js**
- audit `next-env.d.ts` separately from plain Next.js repos:
  - if it is stable and intentionally tracked, keep it tracked
  - if it churns between `./.next/types/routes.d.ts` and `./.next/dev/types/routes.d.ts`, prefer ignoring and untracking it rather than committing unstable generated output
- if generated Payload files contain the automatic-generation banner, ensure they are not treated as normal editable source files
- if `.prettierignore` exists or should exist, add generated Payload files to it when appropriate:
  - `src/payload-types.ts`
  - `src/payload-generated-schema.ts`
  - generated files under `src/app/(payload)` / `app/(payload)` such as admin entrypoints, generated import maps, generated API routes, and generated layout wrappers
  - `next-env.d.ts` when the repo treats it as unstable generated output

**React Native / Expo only**
- verify common generated artifacts are ignored when relevant:
  - `.expo`
  - `web-build/`
  - `dist/`
  - `.metro-health-check*`
  - `*.jsbundle`
  - `DerivedData`
  - `.gradle`
  - `.cxx/`
  - `*.hprof`
  - `xcuserdata`
  - `**/Pods/`

Do not suggest Next.js-specific ignores in non-Next repos.

### 10b. `.prettierignore` Hygiene

Audit whether `.prettierignore` exists and whether the repo has generated files that should not participate in normal formatting flows.

Always evaluate:
- framework-generated files
- codegen outputs
- lockfiles only if the repo intentionally excludes them from formatting

Do not create a noisy `.prettierignore` by default. Only suggest entries when the file is generated, unstable, or explicitly not user-owned.

**Next.js only**
- evaluate `next-env.d.ts`
  - if the repo tracks it intentionally and it stays stable, do not ignore it
  - if it churns or is treated as generated output, suggest ignoring it in Prettier and, if appropriate, in Git as well

**Payload + Next.js**
- suggest ignoring generated Payload files when they exist, such as:
  - `src/payload-types.ts`
  - `src/payload-generated-schema.ts`
  - generated files under `src/app/(payload)` / `app/(payload)` including generated admin entrypoints, import maps, generated API routes, and generated layout wrappers
- do not suggest ignoring user-owned files such as custom admin components or editable stylesheets unless the repo explicitly treats them as generated
- if generated files contain an automatic-generation banner, treat that as strong evidence they belong in `.prettierignore`

### 11. Agent Files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`)

**If `AGENTS.md` does not exist**, generate a minimal one using context detected from the repo:
- Project name and framework (from `package.json` and config files)
- Package manager (already detected)
- Path aliases (from `tsconfig.json` `paths` or notable `baseUrl` usage)
- Styling approach (Tailwind, Sass, CSS-in-JS, React Native `StyleSheet`, etc. — inferred from deps)
- Data fetching and state management libraries (inferred from deps)
- Ask the user for:
  - Jira project key
  - any hard rules not derivable from code
- Include these sections at minimum:
  - **Repo Defaults**
  - **Hard Rules**
  - **Jira**
  - **Git**
  - **Verification**
  - **Skills**

For `Jira`, include repo-specific defaults:
- default project key
- number-only issue shorthand, e.g. `123 -> PROJECT-123`
- optional default ambiguous “my tasks” JQL when the user wants one

For `Git`, include baseline rules:
- when a commit has a Jira issue, append `[ISSUE-KEY]` to the subject
- if the user asks for a commit without a Jira key and does not explicitly say there is no task, ask before committing
- prefix AI-run `git commit`, `git push`, and repo hooks with `AI_MODE=1`
- if the repo already uses a commit-message skill, point to that skill instead of recreating commit-writing guidance in repo docs
- if the repo uses `AGENTS.md` as source of truth and needs `CLAUDE.md`/`GEMINI.md` synced, consider adding:
  - a `sync:agents` script: `cp AGENTS.md CLAUDE.md && cp AGENTS.md GEMINI.md`
  - a lint-staged entry for `AGENTS.md` to auto-sync on commit

For React Native / Expo repos, include only truly non-obvious mobile gotchas such as:
- native-sensitive auth/session areas
- Keychain / biometrics coupling
- important navigation or native-config constraints

For Payload repos, include only short operational notes that agents would not infer reliably from package names alone, such as:
- after schema changes, run the repo's `generate:types` script if it exists
- after admin custom-component wiring changes, run the repo's `generate:importmap` script if it exists
- do not hand-edit generated Payload files

Do not include sections that are fully derivable from reading the code (architecture, entry points, file structure). Keep `AGENTS.md` under 60 lines.

**If `AGENTS.md` already exists**, audit it against the required sections above and report what is missing or outdated. Do not overwrite — propose additions only.

**Optional cross-repo backend/service context**

This is optional and should only be added when the user wants it.

Purpose:
- helps agents verify frontend assumptions against the real backend instead of guessing
- helps agents validate response schemas and endpoint params against the API code
- helps agents check whether an endpoint exists for a requested frontend flow
- helps agents confirm backend behavior such as auth rules, permissions, business rules, and existing validations
- helps agents answer questions like:
  - "does the backend already return this field in the profile response?"
  - "what params does this endpoint accept?"
  - "is there already an endpoint for this action or filter?"
  - "does the backend validate this as required, optional, or nullable?"
  - "is the frontend correct to assume this side effect or status transition?"

Rules:
- Do **not** assume or guess the path to a backend or API repo.
- If the user explicitly provided a backend/service repo path in the prompt, you may use it in the audit.
- Otherwise, if no backend/service repo path is already documented in existing repo instructions, report this only as an optional improvement.
- In that case, suggest that `AGENTS.md` could include cross-repo context for backend contract checks, and ask the user to provide the path if they want that added.
- Make clear that the user can decline this addition and still apply the rest of the quality setup.
- Only after the user provides the path and confirms they want the addition, propose adding:
  - a brief `Load Extra Context Only When Needed` entry pointing to that backend/service repo
  - a `Frontend Ready Check Context` section pointing to that repo and the main backend evidence paths
- Do not add this section automatically as part of the baseline.

**`CLAUDE.md` and `GEMINI.md`** — two approaches:

**Approach A — Thin wrappers (reference):**
- Each file says "read AGENTS.md" — simple, no duplication, no sync needed
- Best for small repos where the agent can easily read another file

**Approach B — Sync copies (tracking-app style):**
- `CLAUDE.md` and `GEMINI.md` are literal copies of `AGENTS.md`
- Add `"sync:agents": "cp AGENTS.md CLAUDE.md && cp AGENTS.md GEMINI.md"` script
- Add lint-staged entry:
  ```json
  "AGENTS.md": ["pnpm sync:agents", "git add CLAUDE.md GEMINI.md"]
  ```
- Advantage: agents read one file and have all instructions; recommended for most projects

Always create both `CLAUDE.md` and `GEMINI.md` if they don't exist. Ask the user which approach they prefer, defaulting to Approach B (sync copies).

`CLAUDE.md`:
```md
# CLAUDE.md

This project uses a canonical agent instruction file.

👉 **Read and follow `AGENTS.md` in the repository root.**

If there is any conflict, `AGENTS.md` takes precedence.
```

`GEMINI.md`:
```md
# GEMINI.md

This repository defines project-wide rules for AI agents.

👉 Read and strictly follow `AGENTS.md`.

`AGENTS.md` is the source of truth.
```

## Output Format

After auditing, present findings as:

```text
## Audit Results

Detected context:
- package manager: yarn
- packageManager: missing
- project type: React Native + Expo modules
- ESLint: legacy config
- typecheck style: tsc --noEmit --skipLibCheck

### 1. VSCode Settings — X changes needed
- missing: editor.formatOnSave
- missing: editor.rulers (printWidth: 120 detected)
- ...

### 2. VSCode Extensions — file missing
### 3. Scripts — missing: typecheck, check-dependencies
### 4. Package Manager — missing `packageManager`; yarn repo should pin `yarn@1.22.22`
### 5. Exact Versions — 3 ranged specs found, `.yarnrc` missing `save-exact true`
### 6. Dev Dependencies — missing: depcheck
### 7. Depcheck — needs run after deps installed
### 8. Git Hooks — pre-push missing: run_quiet, AI_MODE, typecheck
### 9. lint-staged — missing extensions: html, yaml, yml
### 10. .gitignore — 2 issues found
  - duplicate: .next
  - missing: tsconfig.tsbuildinfo
### 11. Agent Files — AGENTS.md missing pieces in Jira/Git

Optional improvement:
- `AGENTS.md` could include cross-repo backend context for contract and readiness checks
- no backend/service repo path was provided, so this should not be added automatically
- if you want this, provide the path to the backend/service repo and confirm you want the addition

Optional suggestion:
- audit-ci could be added, but likely low signal for this repo unless the team wants explicit dependency audit gating

Apply all sections? Or specify which ones:
```

Then apply confirmed sections and report what was changed.

## Optional Payload DX Suggestions

These are **not** part of the baseline. Mention them only as optional follow-up ideas when the repo is Payload-based and the context suggests they may help.

- **Next.js local network DX**
  - if the repo is Next.js / Payload + Next and mobile or LAN testing is likely, suggest `DEV_ORIGIN` / `allowedDevOrigins` as an optional development convenience
  - do not present this as code quality baseline

- **Payload admin local DX**
  - if the repo has an auth-based admin and the user seems to want faster local login, suggest `admin.autoLogin` gated to `NODE_ENV === 'development'`
  - recommend using env vars such as `AUTOLOGIN_EMAIL` / `AUTOLOGIN_PASSWORD`
  - keep this clearly optional and local-development only

- **Payload admin branding**
  - if the repo has a clear branding asset and uses `@payloadcms/next`, suggest optional `admin.components.graphics.Logo` and `Icon`
  - recommend placing the asset in a sensible static location such as `public/` and wiring small wrapper components under `src/app/(payload)/_components`
  - do not present branding changes as part of code quality baseline

- **GraphQL cleanup**
  - if Payload GraphQL is disabled, suggest auditing whether scaffolded GraphQL route files are still present and removable
  - make clear that this is separate from whether the `graphql` package must remain installed for peer-dependency compatibility

## Optional Bitbucket Skill Enablement

Not part of the baseline. Only relevant when `git remote get-url origin` points to `bitbucket.org`.

- Check whether `./.bitbucket-token` exists in the repo root.
- If missing, mention that the `bitbucket` skill (PR listing, comments, approve, merge) needs a repo-local Repository Access Token to work in this repo, and offer to set it up now.
- If the user wants it, follow the `bitbucket` skill's own "Missing token: offer to create it" flow (read `~/.agents/skills/bitbucket/SKILL.md`) rather than duplicating the token template here.
- If `.bitbucket-token` already exists, verify it's ignored (`git check-ignore ./.bitbucket-token`). If it isn't, suggest the user add it to their personal global gitignore. **Do not add it to the repo's own `.gitignore`** — this is experimental, personal tooling, not a team-wide convention, and section 10 (`.gitignore` Hygiene) should not include it.
