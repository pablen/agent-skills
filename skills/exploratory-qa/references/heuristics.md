# Heuristics

Read this when building fixtures (step 3) and running the tour (step 4). Use
the parts that apply to the screen's fields and type; skip the rest with a
reason in the report.

## Data that breaks things

- **Dates and times:** midnight UTC exactly as the API stores it; the last
  hours of the day in the business timezone; days 29, 30 and 31 against shorter
  months; leap days; month-only values such as `12/2026`; a date-only value next
  to a timestamp of the same day.
- **Numbers:** 0, 1 and the API's maximum; one past the maximum; thousands and
  decimal separators in the user's locale; singular and plural units.
- **Collections:** empty; exactly one; one more than the page size; one more
  than any `limit` the client hardcodes; an API limit on items per request.
- **Text:** the maximum length; one past it; whitespace only; very long words
  with no spaces.
- **References:** an inactive or deleted item the record still points to; a
  reference with only the minimum fields; two items with the same display name.
- **Responses:** 400 with a field error, 401, 403, 404, 409 with details, 500,
  a network error, and a slow response (hold it until the test releases it,
  rather than a timer).

## Tours by screen type

### List

- Sort by each column; filter; combine filters; clear them.
- Paginate, change page size, then go back and reload: the URL restores the
  same view.
- Empty result, no-results-for-filters, error, and slow load.
- Edit the URL by hand: garbage values, malformed dates, unknown enum values,
  negative pages.

### Detail

- Open from the list, then reload on the detail URL.
- Not-found id and an id of the wrong shape.
- Related data loading slower than the main record.

### Create or edit form

- Save with no changes.
- Double-click save at human speed: two separate clicks about 100 ms apart.
  Playwright's `dblclick` and two `fireEvent` calls in one tick fire both
  clicks within a millisecond, faster than any person; a duplicate request
  counts as a bug only when it reproduces at human speed.
- Cancel with unsaved changes, then cancel again without changes.
- Each field at its limits (see "Data that breaks things").
- A server rejection for each field the API validates.

### Draft editor with a confirm step

- Save a draft, leave, come back: everything restores.
- Remove a row from a restored draft, then check every remaining row.
- Confirm while some data is still loading (hold the response).
- Open the same draft in two tabs, save in one, confirm in the other.
- A conflict response (409) on confirm, then fix and confirm again.
- Navigate away and use the browser back button mid-edit.

### Report or search screen

- Type in a search box, then use the browser back button: one history step,
  not one per keystroke.
- Change the main selection and check that dependent filters reset.
- Totals and units against the rows on screen.
