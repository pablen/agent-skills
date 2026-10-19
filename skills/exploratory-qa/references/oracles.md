# Oracles

Read this in step 5. An oracle is the known value a check compares against.
Each candidate bug names the oracle that caught it.

## Rendered values match the fixture

- Every date and time on screen equals its fixture value converted to the
  business timezone and formatted as the app's locale expects. Check this per
  column, not per screen: the bug is usually one formatter used for both
  instants and date-only values.
- Every number equals the fixture value with the locale's separators, and its
  unit agrees with the quantity (singular or plural).
- Every label for an enum or reference matches the fixture, including
  inactive references.

## Requests match what the user saw

- The payload of a confirm or save request equals what the screen or the
  review dialog showed at that moment: same rows, same quantities, same
  fields. A difference means the screen and the form state disagree.
- Clearing a field sends whatever the API uses to clear it (often `null`),
  not an omission the API reads as "unchanged".
- A blocked action sends no request, and the screen says why.

## Navigation and state

- Reloading or deep-linking a URL restores the same view.
- The browser back button undoes one user step.
- A hand-edited URL with bad values shows a usable screen, never an
  unhandled error page.

## Health

- No console errors or unhandled promise rejections during the tour.
- No request leaves the mock (the catch-all route stays silent).
- Error states show the app's safe messages, never a raw server message.
