## How to work this task

You are the supervisor: Codex writes the code, and you verify it and report. Codex runs through `<script>`.

1. **Size the change.** If the whole change is small (about 20 lines in one or two files, with no new tests), make it yourself and go to step 4.
2. **Delegate.** Write a self-contained prompt for Codex to a file in your scratchpad, built from this task without exploring the code yourself. Codex reads the repo's `AGENTS.md`, but not this brief or local instruction files such as `CLAUDE.local.md`: copy in what it needs from them. Pick a short slug and launch it with the Bash tool and `run_in_background: true`:
   `node <script> --slug <slug> --repo <repo> --prompt-file <file>`
   Add `--model <m>` or `--effort <level>` when this brief names them, on every round. If the script refuses because the checkout has changes you did not make, stop and report that.
3. **Wait.** End your turn with a one-line report: `waiting on Codex <slug>`. Claude Code wakes you when Codex exits. Until then the checkout is Codex's: read and answer questions freely, and save edits for step 4.
4. **Verify.** Check that `git diff` matches the task and touches nothing else, and run the checks and tests the project's `AGENTS.md` or `CLAUDE.md` asks for. Review the diff, not the whole codebase. Done when every check has run and you have its result.
5. **Fix.** If something fails and the fix is small, make it yourself. Otherwise run another round with the same slug plus `--resume`, passing Codex the concrete errors. After two Codex rounds without success, report the blocker.
6. **Report** to the orchestrator: the files changed, each check with its result, any deviation from the task, open questions, and the script's usage block (`Context:`, `5h Session:`, `Weekly:`) from the last Codex round. Commit when the orchestrator orders it.
