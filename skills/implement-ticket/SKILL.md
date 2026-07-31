---
name: implement-ticket
description: Prepare a copy-paste handoff prompt for another agent session, or implement a Jira ticket directly using the same preflight. Use when the user asks for a prompt to implement a Jira ticket, asks to implement a Jira ticket or substantial spec, or needs to preserve existing work while continuing a multi-ticket feature.
---

# Implement Ticket

Use the same evidence-based preparation whether producing a handoff prompt or implementing the ticket in this session. Do not rely on a generic ticket title alone.

## Select the mode

- **Handoff mode:** use when the user asks for a prompt, brief, or instructions to paste into another agent session. Read the context, then return only the tailored prompt. Do not edit code, Jira, or git state.
- **Execution mode:** use when the user asks to implement a ticket. Perform the same preflight, state a compact plan, then implement. Continue without waiting unless a real contradiction, missing authority, or unsafe choice blocks progress.

If the user gives only an issue key, use the configured Jira skill to read the ticket. Use it for any ticket mutation too; never call Jira directly.

## Preflight

1. Read repository instructions (`AGENTS.md`, `CONTEXT.md`, and relevant ADRs) before exploring code.
2. Read the ticket, its acceptance criteria, dependencies, and the canonical spec or documents it references. Treat the spec as the functional source of truth when it is more detailed.
3. Inspect the actual working tree, recent commits, and the code/tests nearest to the requested behavior. Preserve unrelated or uncommitted work.
4. Check dependency tickets only when their completed behavior, unresolved state, or implementation boundary affects this ticket. Never assume a dependency is implemented from its title alone.
5. Identify:
   - the exact requested outcome;
   - existing behavior that must be preserved;
   - explicit non-goals and adjacent-ticket boundaries;
   - the smallest useful validation plan and its environmental prerequisites.

Do not claim a fact, a commit, a route, a field, or a test seam without verifying it locally or in Jira.

## Produce an agent-ready brief

In handoff mode, write a Spanish, copy-paste-ready prompt. Tailor it to the ticket; do not dump or duplicate the full spec. Include these sections when relevant:

```text
Implementá <KEY> (“<summary>”).

Fuentes de verdad, en este orden:
- ticket, spec e instrucciones del repositorio
- código y tests actuales relevantes

Contexto:
- trabajo adyacente verificado, ya completado o en curso
- restricciones del working tree que se deben preservar

Antes de editar:
1. inspeccioná los seams concretos
2. presentá un plan corto
3. continuá salvo contradicción real

Objetivo funcional:
- resultados precisos y transiciones de estado importantes

Límites:
- no objetivos explícitos y límites con legacy/tickets adyacentes
- no modificar Jira, commitear ni pushear salvo pedido explícito

Tests y validación:
- casos de prueba, comandos, prerequisitos y chequeos manuales relevantes

Al finalizar:
- informar cambios, validación y limitaciones restantes
```

Use direct, testable language. Describe real domain rules, security constraints, and state transitions rather than vague goals such as “make it work.” State which existing implementation must be reused instead of duplicated. Mention a concrete migration/compatibility constraint only if the repository or ticket proves it.

For UI work, include a visual/manual check when repo instructions require it. For browser or integration tests, state whether they are manual-only and whether they require a running server, database, credentials, or other external services. Never instruct the next agent to start Docker or a development server automatically unless the user explicitly authorizes it.

## Execute safely

In execution mode, follow the prepared brief and keep the user informed concisely. Prefer tests at existing seams; add tests for new externally observable behavior and important regressions. Run focused validation during the work and broader checks in proportion to risk and available environment.

Do not make Jira changes, create commits, amend commits, or push unless the user explicitly asks. When a commit is requested, defer to repository-local commit rules and any applicable commit-message skill.

Finish with the changed outcome, files or components that matter, validation actually run, and any validation that could not run with its concrete reason.
