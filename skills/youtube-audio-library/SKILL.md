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
3. **Propose and confirm.** Present a short list of candidates to the user with
   your reasoning, including the metadata that supports it — at minimum source
   duration (formatted mm:ss) and channel name; view count too when it helps
   distinguish an official upload from a fan upload. Let them refine (narrow the
   search, drop specific results, ask for more options) before anything gets
   downloaded. Do not download automatically just because results look
   plausible.
4. **Download** each confirmed video: `scripts/download.py --url <url>
   --library-root .`. This always grabs the best available audio in its native
   codec/container — no forced re-encode. One automatic retry on failure; if it
   fails twice, note it and move on to the rest of the batch (don't abort the
   whole batch for one failure).
5. **Organize** each successful download: `scripts/organize.py --src <staged_path>
   --library-root . --artist "..." --song "..."`. Normalize the artist/song name
   yourself from the video title (strip channel branding, "(Official Video)",
   etc.) before passing them in. Collaborations go in the song name, e.g. `Song
   (feat. Other Artist)` — never a compound artist folder.
6. **Update the catalog** for each organized file: `scripts/catalog.py
   --library-root . add-song ...` and `add-file --kind original ...`.
7. **Report results** to the user: what got downloaded, with format/bitrate/
   duration, and what failed and why.
8. **Offer conversion** as a separate, optional step — never automatic. Suggest
   the default (MP3 192kbps) but let the user pick another format/bitrate or
   decline entirely.
9. If accepted, **convert** each file: `scripts/convert.py --src <original_path>
   --library-root . --artist "..." --song "..." [--target-format mp3]
   [--target-bitrate 192]`. The script itself decides whether conversion is
   actually needed (skips if the source is already the target format at or below
   the target bitrate; a different container always gets converted regardless of
   its bitrate). Continue through failures and report a summary at the end.
   Update `files.csv` with `add-file --kind converted ...` for each success.

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
- `catalog.py --library-root DIR init|add-song|add-file|list [...]`
- `scan.py --dir DIR [--ext mp3 --ext ogg ...]`
- `download.py --url URL --library-root DIR`
- `organize.py --src PATH --library-root DIR --artist A --song S`
- `convert.py --src PATH --library-root DIR --artist A --song S [--target-format mp3] [--target-bitrate 192]`

Requires `yt-dlp`, `ffmpeg`/`ffprobe`, and the `mutagen` Python package on PATH.

## Troubleshooting

If a bare command (`python3`, `ffmpeg`, `stat`, etc.) fails with "command not
found" even though it's normally available, the shell invocation likely has a
trimmed `PATH`. Run `which <tool>` once to resolve its absolute path, then reuse
that absolute path for the rest of the session instead of retrying the bare
command repeatedly.
