# Jira Skill Rationale

## Goals

- Minimize token usage in the common case
- Reduce latency for frequent Jira reads
- Keep behavior predictable across turns
- Preserve safety only where it changes Jira state

## Main Decisions

### Happy path first

The skill should run the one command that is most likely to answer the request immediately. It should not do preflight checks for credentials, working directory, or repo context on read-only requests.

Why:
- Most requests succeed on the first try
- Preflight commands cost tokens and latency even when they add no value
- `jira-api.sh` already validates credentials and surfaces transport or HTTP errors

Tradeoff:
- Errors are diagnosed after the failing request instead of before it
- This is acceptable for read flows and cheaper in the steady state

### Low freedom for common requests

Frequent asks such as "mis tasks", "mis in progress", "issue <KEY>", and "transitions de <KEY>" use dedicated scripts instead of free-form command construction.

Why:
- Repeated shell and JQL generation wastes tokens
- Small wrappers are deterministic and easier to verify
- The model has fewer chances to add irrelevant steps

Tradeoff:
- More files exist under `scripts/`
- This is acceptable because scripts are cheaper than re-deriving command shapes every turn

### Cache stable transition ids with safe fallback

Common transition requests should use a wrapper that fast-paths stable workflow ids and falls back to live transition lookup only when the cached id is missing or rejected.

Why:
- Re-reading transitions before every write burns latency and tokens in the common case
- Stable project workflows such as `OPTICELL` benefit from deterministic shortcuts
- A fallback preserves correctness when Jira admins change a workflow or when the issue type differs

Tradeoff:
- Cached ids can drift over time
- The fallback path adds a little implementation complexity
- This is acceptable because correctness still comes from the live fallback, while the steady state gets cheaper

### Cache stable identity data, not just transition ids

Resolvers for users, fields, and some sprint lookups should use local cache files and refresh live only on miss, ambiguity, or staleness.

Why:
- Re-resolving the same assignee account ids and custom field ids burns tokens and latency
- These identifiers are stable enough to benefit from cache
- The write wrappers can stay short because they delegate entity resolution

Tradeoff:
- Caches can become stale
- Sprint caches are more volatile than user and field caches
- This is acceptable when caches either have a TTL or fall back to live lookup

### Prefer wrappers for common create flows

Issue creation that needs assignee resolution, sprint inheritance, and custom field ids should use purpose-built wrappers instead of reassembling REST payloads in each turn.

Why:
- Repeated payload construction costs tokens and invites mistakes
- The same supporting reads recur in similar create flows
- Dry-run support makes wrappers safe to reuse for new write shapes

Tradeoff:
- More helper scripts need maintenance
- This is acceptable when each wrapper removes repeated reasoning and repeated intermediate reads

### Keep write text brief and operational

Issue descriptions and comments should be written in Spanish by default and should stay concise, direct, and useful for execution.

Why:
- Long or ceremonial writeups waste tokens and make Jira harder to scan
- Most issue and comment payloads are operational, not narrative
- A short mention of the likely failing route, file, or code path can help debugging without turning the ticket into an essay

Tradeoff:
- Some context is omitted unless it changes triage or implementation
- This is acceptable because the ticket can link to code, issues, or follow-up comments when deeper context is needed

### Browser links should be first-class output

When the user can act on an issue or a comment, plain text identifiers are weaker than clickable links. The skill should prefer Markdown links in final answers and use a helper script to derive the browser URL from `JIRA_URL`.

Why:
- The user can jump directly from the answer to Jira
- It avoids repeating ad hoc URL construction rules in every turn
- It does not require extra Jira API reads

Tradeoff:
- There may be one extra local helper invocation when the base browser URL is not already known
- This is acceptable because it is cheaper than an extra Jira call and improves usability

### The skill is global and project defaults are contextual

The skill itself should not assume a Jira project. Project scoping belongs to the active working context, such as a repository `AGENTS.md` that specifies a default Jira project for requests made in that repo.

Why:
- The same skill must work across repositories and also outside any repository
- A hidden global default would make "mis tasks" incomplete in contexts with multiple Jira projects
- Repo-local instructions can still provide a deterministic default when that is the intended behavior

Tradeoff:
- The caller must pass the project explicitly when context requires project scoping
- This is acceptable because the agent already has the active context in memory

### Keep `SKILL.md` short

`SKILL.md` contains only invocation rules, fast paths, and response expectations. Explanatory material stays out of the main file unless it directly changes runtime behavior.

Why:
- The skill body is loaded into context when triggered
- Long instructions are paid for every time the skill is used

Tradeoff:
- Some maintainers may want more narrative in the main file
- That content belongs in `references/` and should be loaded only when needed

### No repo-context exploration for Jira-only requests

The skill should not inspect the filesystem or repo just to answer a Jira read. It may still use already-active context, such as a loaded `AGENTS.md`, when that context defines a default Jira project.

Why:
- Those steps do not improve Jira answers
- They add tool calls and tokens with no payoff

Tradeoff:
- None for Jira-only flows

### Reads are optimized, writes remain cautious

Read operations should be single-step whenever possible. Write operations can still justify an extra read when it confirms transitions, issue state, or target shape.

Why:
- Writes have side effects
- A small amount of extra validation is worth it when state can change

Tradeoff:
- Write flows are intentionally less minimal than read flows

## Maintenance Rules

- Add a wrapper script only for requests that recur often and have a stable shape
- Prefer TSV or compact key-value output because it is cheap to parse and summarize
- Avoid introducing README-style documentation into the skill root; keep optional rationale in `references/`
- If a new wrapper does not remove meaningful reasoning or command construction, do not add it
