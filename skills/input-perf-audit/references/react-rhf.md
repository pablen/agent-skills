# React and React Hook Form probes

Read this reference for React forms, React Hook Form (RHF), controlled inputs, masks, or React Query-backed field enhancements.

## Contents

- Static inspection checklist
- Browser burst probe
- Input-to-frame sampling
- Render counters
- Request counting
- Interpretation matrix
- Measurement hazards

## Static inspection checklist

- Locate `useForm`, `FormProvider`, `Controller`, `useController`, `watch`, `useWatch`, and `useFormState`.
- Check where subscriptions live. A field-specific subscription in a drawer/page component can rerender the whole component body even when only one adornment consumes it.
- Check `formState` reads. RHF uses a proxy and subscribes consumers to the properties they access.
- Do not assume `Controller` is slow. Compare ownership and subscription scope; `useController` is useful when a smart field encapsulates formatting, validation, and server enhancement, but is not inherently faster.
- Check whether a mask or formatter receives both `value` and `onChange`, rewrites the value asynchronously, restores selection, or schedules timers.
- Check per-key calls to `trigger`, `setValue`, `setError`, `clearErrors`, or schema parsing.
- Keep async availability state local to the field when no other form consumer needs it. Let form validation own blocking errors and the query own non-blocking enhancement state.
- Check query keys, `enabled`, debounce ownership, retries, and whether request state is lifted into the form container.
- Check whether adornments or helper text are derived in a parent and passed back into the field.
- Treat React Strict Mode's development-only extra work separately from input-triggered renders.

## Browser burst probe

Use the project's Playwright setup when available. `pressSequentially` emits keyboard and input events for every character; `fill` is useful for setup but does not stress the same path.

```ts
const field = page.getByLabel('CUIT')

await field.fill('')
await field.pressSequentially('30700000008', { delay: 0 })
await expect(field).toHaveValue('30-70000000-8')
```

Repeat with the reference field using a comparable number of characters. Add selection and paste cases for masks:

```ts
await field.evaluate((input: HTMLInputElement) => input.setSelectionRange(3, 11))
await page.keyboard.insertText('71230001')
await expect(field).toHaveValue('30-71230001-8')
```

Use clipboard APIs only when clipboard permissions are already part of the test setup. Otherwise use `insertText` to exercise replacement without adding unrelated permission setup.

## Input-to-frame sampling

Install the listener before typing, keep DevTools update highlighting off, and sample inside the page:

```ts
await field.evaluate((input: HTMLInputElement) => {
  const samples: Array<{ delayMs: number; eventValue: string; frameValue: string }> = []

  const onInput = () => {
    const startedAt = performance.now()
    const eventValue = input.value

    requestAnimationFrame(() => {
      samples.push({
        delayMs: performance.now() - startedAt,
        eventValue,
        frameValue: input.value,
      })
    })
  }

  input.addEventListener('input', onInput, true)
  ;(window as typeof window & { __inputPerfProbe?: unknown }).__inputPerfProbe = {
    samples,
    dispose: () => input.removeEventListener('input', onInput, true),
  }
})

await field.pressSequentially('30700000008', { delay: 0 })
await page.waitForFunction(
  (expected) =>
    (
      window as typeof window & {
        __inputPerfProbe?: { samples: unknown[] }
      }
    ).__inputPerfProbe?.samples.length === expected,
  11,
)

const samples = await page.evaluate(
  () =>
    (
      window as typeof window & {
        __inputPerfProbe?: {
          samples: Array<{ delayMs: number; eventValue: string; frameValue: string }>
        }
      }
    ).__inputPerfProbe?.samples ?? [],
)
```

Dispose the probe when finished:

```ts
await page.evaluate(() => {
  const probe = (
    window as typeof window & {
      __inputPerfProbe?: { dispose: () => void }
    }
  ).__inputPerfProbe
  probe?.dispose()
  delete (window as typeof window & { __inputPerfProbe?: unknown }).__inputPerfProbe
})
```

Calculate percentiles from the sorted `delayMs` values. Use median for the typical case and p95 for spikes. Compare target and reference under the same conditions; do not present the result as exact browser paint time.

## Render counters

Use source instrumentation only when visual highlighting cannot identify component scope. Prefer an in-memory counter over `console.count`, because console output can distort timings.

For component-body renders:

```ts
const renders = (globalThis as typeof globalThis & {
  __inputPerfRenders?: Record<string, number>
}).__inputPerfRenders ??= {}
renders.CreateSupplierDrawer = (renders.CreateSupplierDrawer ?? 0) + 1
```

Place counters at the target field and form container. Reset after warm-up and read them after each burst. This measures function-body executions, not DOM mutations.

For subtree commit scope, wrap only the suspected subtree with React's `Profiler` and increment an in-memory counter in `onRender`. Remember that a profiler callback fires when any part of its subtree commits; it does not prove the wrapper component body rerendered.

Remove the import, wrapper/counter, debug global, and any temporary test before finishing. Search for `__inputPerf` across the repository.

## Request counting

Use the existing API mock or browser request observer. Record requests before the burst, type, wait beyond the debounce, then calculate the delta. Verify:

- incomplete or locally invalid input makes no request;
- valid complete input makes the expected number of requests;
- editing invalidates stale feedback without causing form-wide work;
- aborts, stale responses, and retries do not overwrite the newest value.

## Interpretation matrix

| Experiment | Meaning when target improves |
| --- | --- |
| Localize parent `watch`/`useWatch` | Subscription fan-out was rerendering the container |
| Disable remote query only | Query lifecycle or lifted request state contributed |
| Replace mask with plain input | Mask/value/selection feedback path contributed |
| Disable schema/derived work | Per-key synchronous work contributed |
| Keep state but replace expensive subtree | Render cost, not field integration, dominated |

Require repeated evidence. A single faster run can be scheduler noise.

## Measurement hazards

- React DevTools highlighting and open console logging add overhead.
- Development builds and Strict Mode differ from production; state which mode was measured.
- First-run module loading, query warm-up, animations, autofocus, password managers, and browser extensions can skew results.
- Headless/background tabs can throttle animation frames. Keep target and reference in the same mode.
- Test-runner action duration includes protocol and auto-wait overhead. Do not label it input latency.
- A correct final value does not prove caret, selection, paste, or IME behavior is correct.
- Avoid tight millisecond assertions in CI. Protect the behavioral cause when possible, such as zero form-container renders during field typing or one debounced request.
