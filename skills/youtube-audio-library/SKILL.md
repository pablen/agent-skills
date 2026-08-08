---
name: youtube-audio-library
description: Use when the user wants to search YouTube for songs, download audio from them, convert formats, organize a personal music library by artist, or check what's already downloaded against a catalog. Global skill — operates on originals/, converted/, catalog.csv and files.csv relative to the current working directory, not tied to any repo.
---

# YouTube audio library

Helps build and maintain a personal audio library sourced from YouTube: search,
download best-quality audio, organize into `Artist/Song - Artist.ext`, optionally
convert to a compatible format, and track everything in a CSV catalog.

For the full design rationale (why CSV over markdown, why Python, error-handling
rules, etc.), see `references/rationale.md` — read it only when you need to
understand *why* a rule exists or when changing this skill.

## Core principle

Scripts in `scripts/` do only narrow, deterministic things (search, download,
organize, convert, read/write catalog, scan a directory). **All orchestration,
judgment, and sequencing is the agent's job**, following the defaults and rules
below — not hardcoded end-to-end automation. This means the user can ask to alter
the workflow slightly in any given session (skip a step, change an order, apply a
one-off criterion) and the skill should accommodate it rather than resist it.

## Presenting choices

Whenever you present the user a decision with a fixed set of options — which
search results to download, which format to convert to, what to do about a
failed download — number the options (`1) ... 2) ... 3) ...`) so the user can
reply with a bare number (or a few, e.g. "1 3 5") instead of retyping choices
back at you. This applies throughout the workflow below, not just at the steps
that call it out explicitly.

## Library location

The library lives in the **current working directory** of the session:
`./originals/`, `./converted/`, `./catalog.csv`, `./files.csv`. Never assume a
fixed path and never write relative to the skill's own installation directory.

If those don't exist yet in the cwd, **ask the user for confirmation** before
running `catalog.py init` to create them — don't assume an empty directory means
"initialize a library here" without checking first.

## Catalog schema

- `catalog.csv` — one row per song (identity): `video_id, song, artist,
  duration_sec, source_url, download_date, notes`
- `files.csv` — one row per physical file, original or converted: `video_id,
  kind, format, bitrate, size_bytes, path, created_date`

Read these directly (they're small, plain CSV) when you need to reason about
what's in the library — there is no "dedup script"; matching search results
against the catalog (by `video_id`, or by song+artist if the same song might have
a different upload/video_id) is your judgment call, not a script's.

## Workflow

1. **Search.** Run `scripts/search.py --query "..." --count 20 [--min-duration N]
   [--max-duration N]` (seconds). This only returns metadata (title, channel,
   duration, view count, url) — it does not filter for "correct" versions.
2. **Curate.** Read the results yourself: does the channel look official? Does
   the title suggest a plain studio/official version vs. a reaction, cover, full
   album, lyric video, or long intro/outro cut? Cross-reference against
   `catalog.csv` (by `video_id` first, then by normalized song+artist for
   possible re-uploads) to separate "already have" from "candidates."
3. **Propose and confirm.** Present the candidates as a numbered markdown table —
   columns `#`, Song, Channel, Duration (mm:ss), Views — so the metadata backing
   your reasoning is visible at a glance and the user can reply with bare numbers
   (see "Presenting choices" below) instead of retyping titles. Add a Notes
   column, or a line below the table, when something needs flagging (fan upload,
   duplicate of an existing catalog entry, unusually long/short for the song).
   Let the user refine (narrow the search, drop specific numbers, ask for more
   options) before anything gets downloaded. Do not download automatically just
   because results look plausible.
4. **Download** each confirmed video: `scripts/download.py --url <url>
   --library-root .`. This always grabs the best available audio in its native
   codec/container — no forced re-encode. One automatic retry on failure; if it
   fails twice, note it and move on to the rest of the batch (don't abort the
   whole batch for one failure).
5. **Organize and catalog** each successful download in one step:
   `scripts/ingest.py --src <staged_path> --library-root . --artist "..."
   --song "..." --video-id <id> --source-url <url>`. Normalize the artist/song
   name yourself from the video title (strip channel branding, "(Official
   Video)", etc.) before passing them in. Collaborations go in the song name,
   e.g. `Song (feat. Other Artist)` — never a compound artist folder.
   `ingest.py` moves the file into `originals/<Artist>/`, then adds it to both
   `catalog.csv` and `files.csv` by reading its real format/bitrate/duration off
   the organized file — nothing gets hand-typed, which is what you want (a
   wrong number here silently corrupts the catalog). If you need the two steps
   separately (e.g. re-cataloging a file that's already organized), use
   `organize.py` and `catalog.py add-song`/`add-file --from-json` directly.
6. If any step in `ingest.py`'s response carries a `warning` field, the
   `video_id` already had a row in the catalog — surface that to the user
   instead of silently accepting a duplicate.
7. **Report results** to the user: what got downloaded, with format/bitrate/
   duration, and what failed and why.
8. **Offer conversion** as a separate, optional step — never automatic. Present
   it as numbered options, e.g. `1) Convert to MP3 192kbps (recommended)  2)
   Another format/bitrate  3) Skip conversion`, so the user can answer with a
   bare number.
9. If accepted, **convert** each file: `scripts/convert.py --src <original_path>
   --library-root . --artist "..." --song "..." [--target-format mp3]
   [--target-bitrate 192]`. The script itself decides whether conversion is
   actually needed (skips if the source is already the target format at or below
   the target bitrate; a different container always gets converted regardless of
   its bitrate). Continue through failures and report a summary at the end. For
   each success, update `files.csv` by piping convert.py's own JSON output into
   `catalog.py add-file --kind converted --from-json -` — again, no re-typed
   numbers.

## Importing a pre-existing library

If the user wants to bring in audio files that don't follow this skill's naming
convention (e.g. an old folder of downloads), use `scripts/scan.py --dir <path>`
to inventory them (path, codec, bitrate, duration, size) without touching
anything. Propose a rename/reorganize plan and **get explicit confirmation**
before moving or renaming anything in bulk.

## Script reference

All scripts print a single JSON object/array to stdout and never prompt
interactively.

- `search.py --query Q [--count 20] [--min-duration S] [--max-duration S]`
- `download.py --url URL --library-root DIR`
- `ingest.py --src PATH --library-root DIR --artist A --song S --video-id ID --source-url URL [--notes N]`
  (organize.py + catalog.py add-song + add-file(original) in one call)
- `organize.py --src PATH --library-root DIR --artist A --song S`
- `convert.py --src PATH --library-root DIR --artist A --song S [--target-format mp3] [--target-bitrate 192]`
- `catalog.py --library-root DIR init|add-song|add-file|list [...]`
  - `add-file --video-id ID --kind original|converted [--format F --bitrate B --size-bytes N --path P] [--from-json PATH|-]`
  - `list [--artist A] [--video-id ID]`
- `scan.py --dir DIR [--ext mp3 --ext ogg ...]`

Requires `yt-dlp`, `ffmpeg`/`ffprobe`, and the `mutagen` Python package on PATH.

## Troubleshooting

If a bare command (`python3`, `ffmpeg`, `stat`, etc.) fails with "command not
found" even though it's normally available, the shell invocation likely has a
trimmed `PATH`. Run `which <tool>` once to resolve its absolute path, then reuse
that absolute path for the rest of the session instead of retrying the bare
command repeatedly.
