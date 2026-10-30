---
name: jbootz-crackdealer
description: Use for music discovery, playlists, rediscovery, and explicit feedback when the user's Apple Music library should inform the result. Combine local CLI evidence with available host research tools; do not use for streaming-service writes. Use only when explicitly invoked.
disable-model-invocation: true
---

# Crackdealer

Use this skill when a music request can benefit from the user's Apple Music library, playlist history, or explicit recommendation feedback. Read [the CLI reference](references/cli.md) for commands and payload examples.

## Run the repository CLI

The app root is `skills/jbootz-crackdealer/` in this repository. The repository root is two levels above this skill directory; set `PROJECT_ROOT` to that repository root's `skills/jbootz-crackdealer` directory. Use it for `Gemfile`, `bin/crackdealer`, and the default `data/crackdealer.sqlite3`. The database stays on the user's machine. Use Ruby 4.0.9; if the parent repository's `mise.toml` selects another version, run through `mise exec ruby@4.0.9`. From any working directory, set `BUNDLE_GEMFILE` and pass the absolute executable and database paths:

```sh
BUNDLE_GEMFILE="$PROJECT_ROOT/Gemfile" mise exec ruby@4.0.9 -- bundle exec ruby "$PROJECT_ROOT/bin/crackdealer" --db "$DATABASE_PATH" status
```

If `mise` reports the parent config as untrusted, review it and run `mise trust ../../mise.toml` once from the app root before retrying.

Use Ruby 4.0.9 and install the locked dependencies from the app root if needed with `mise exec ruby@4.0.9 -- bundle config set --local path vendor/bundle`, then `mise exec ruby@4.0.9 -- bundle install`. If `status` reports a missing database or no imported snapshot, use `import` when an XML export path was explicitly supplied by the user or is configured in `CRACKDEALER_XML_PATH`. If no explicit path is available, ask for one rather than guessing. Import initializes the database as needed; run it only after confirming no snapshot exists, or after the user authorizes a refresh. Ask before refreshing a stale snapshot. This skill does not export from Apple Music.

When the XML path is known and an import is needed, run:

```sh
BUNDLE_GEMFILE="$PROJECT_ROOT/Gemfile" mise exec ruby@4.0.9 -- bundle exec ruby "$PROJECT_ROOT/bin/crackdealer" --db "$DATABASE_PATH" import "$XML_PATH"
```

If `CRACKDEALER_XML_PATH` is configured, use its value as `XML_PATH`.

## Recommendation workflow

1. Check `status`. If the database or imported snapshot is missing, run `import` with an explicit XML export path when one is available; otherwise ask for the path. Preserve existing snapshots unless a refresh is authorized. Inspect `imported_at`; if the snapshot is stale, ask whether the user wants to refresh it.
2. Decide whether the request is music discovery, playlist building, library rediscovery, a live-performance search, or a new-release request. “New music” means new to the user unless they ask for releases. Ask whether they want a coherent theme or a mixtape only when the request leaves that unclear.
3. Build a request-specific taste neighborhood. Inspect named `tracks` results, relevant playlists and ordered members, and applicable history. Treat ratings, Loved, curated placement, and play counts as separate evidence. Preserve conflicts. Low play counts and missing ratings are weak or unknown signals, never proof of dislike.
4. Create a session before candidate research so its context is available for feedback checks. Reuse `playlist:<playlist_key>` for an existing playlist; otherwise use the default `session:<id>` context or a meaningful shared context. Include seed artists, track keys, playlist keys, and short notes in the context object.
5. Research candidates with tools available in the host. Use reliable artist, publication, live-performance, and listening sources as appropriate. The CLI does no network research. Verify every link before recording it; provide Apple Music, Spotify, and YouTube links when verified and practical, while one verified listening link is enough to present a recommendation. Do not claim audio-feature analysis.
6. Before selecting a candidate, compare its normalized artist/title with library results as a duplicate hint and call `feedback list --artist ... --title ...` with the candidate's version and intended context. Page through results while `truncated` is true. Honor matching `dont_recommend` feedback even if a separate positive reaction also exists. For a live version, preserve the live/version label and allow it when requested.
7. Record only the final selected tracks with `recommendation add`; do not store rejected research candidates. Include a `library_track_key` only for a clear current-snapshot match. History is a repeat-avoidance hint: appearing in history does not prove the user listened or disliked the track.
8. Present the selected tracks with concise reasons grounded in the library evidence and request. Sequence a mixtape intentionally; explain thematic fit for a theme-based list. If history persistence fails, say it was not saved.
9. Capture explicit feedback when the user provides it. Use separate reactions when they both know and like a track. Default ambiguous scope to `context`; ordinary playlist feedback is contextual, while an explicit request to avoid an artist warrants `artist` scope. To correct feedback, retract the old event and add a new reaction. Never infer dislike from silence, skips, or low play counts.

## Interpretation rules

- Treat normalized artist/title matches as approximate identity hints. The key preserves punctuation, accents, and version labels; albums do not distinguish recordings. Do not block a recommendation on a fuzzy match.
- Prefer original albums when practical, but do not treat every Compilation flag as a greatest-hits signal. Soundtracks, singles, and compilation-only tracks can still matter.
- Use taste neighborhoods for this request, not a permanent global ranking. Consider both strong and weak evidence, including conflicts.
- Deep-cut claims and live-performance claims need host research. Verify source and listening links rather than constructing URLs.
- Review the request examples and data shapes in [the CLI reference](references/cli.md). Use `schema` or read-only SQL for questions the named commands do not cover.
