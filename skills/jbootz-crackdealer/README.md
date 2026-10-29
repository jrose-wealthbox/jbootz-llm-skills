# Crackdealer

Crackdealer is a local Ruby CLI and repository-owned skill for using an Apple Music library as evidence in music discovery, playlist planning, and feedback. The CLI imports XML metadata to SQLite and keeps recommendation history separately so library refreshes do not erase it. It does not export from Apple Music, research the web, or write to a streaming service.

## Start

Use Ruby 3.4.7 and the locked bundle. If the parent repository's `mise.toml` selects another Ruby, select this subproject's version explicitly. From this skill package directory:

```sh
mise exec ruby@3.4.7 -- bundle config set --local path vendor/bundle
mise exec ruby@3.4.7 -- bundle install
mise exec ruby@3.4.7 -- bundle exec ruby bin/crackdealer --db data/crackdealer.sqlite3 init
mise exec ruby@3.4.7 -- bundle exec ruby bin/crackdealer --db data/crackdealer.sqlite3 import /path/to/AppleMusic-Library.xml
mise exec ruby@3.4.7 -- bundle exec ruby bin/crackdealer --db data/crackdealer.sqlite3 status
```

If `mise` reports the parent `mise.toml` as untrusted, review that file and run `mise trust ../../mise.toml` once from this skill package directory, then rerun the command.

The default database path is `data/crackdealer.sqlite3` under this directory. `--db PATH` overrides `CRACKDEALER_DB`, which overrides the default. Commands that read data require an initialized database and never migrate it. `import` initializes if needed, then atomically replaces the library snapshot. The `data/` directory and SQLite files are ignored by Git.

To invoke it from another working directory, resolve this directory as `PROJECT_ROOT`, then use its Gemfile and absolute executable path:

```sh
BUNDLE_GEMFILE="$PROJECT_ROOT/Gemfile" mise exec ruby@3.4.7 -- bundle exec ruby "$PROJECT_ROOT/bin/crackdealer" --db "$DATABASE_PATH" status
```

The skill instructions are in [`SKILL.md`](SKILL.md). The runnable command and JSON reference are in [`references/cli.md`](references/cli.md); the concise command/schema reference is in [`docs/cli.md`](docs/cli.md).

## Keep the library current

Export an XML library file from Music, then pass its path to `import`. Imports require the same Apple Music Library Persistent ID and replace only library snapshot tables. Recommendations, feedback, and their links to old snapshot keys remain in history if a track disappears. `status` shows the snapshot timestamp; re-import a fresh XML export when the stored snapshot is no longer current. Binary plist exports are not supported.

Matching is intentionally conservative. The duplicate hint normalizes Unicode compatibility forms, case, and whitespace; it preserves punctuation, accents, and version labels. An identical artist/title match is useful evidence, not proof of the same recording. Album is not part of a recommendation's recording key, so live/version labels matter. Library ratings, Loved, playlist placement, and play counts stay separate signals.

## Storage and backup

The database is local and may contain imported raw metadata, user requests, recommendations, and explicit feedback. Choose a private path and do not share the database casually. The CLI has no automatic JSON restore or history merge.

For a full backup, stop CLI writers and copy the closed SQLite database file. Restore it to a new path, then verify it with `--db NEW_PATH status`. `history export` is a separate portable JSON export of sessions, recommendations, feedback events, and retractions; it does not contain imported tracks and cannot be restored automatically in v1.

## Synthetic 40,000-track benchmark

The benchmark script generates temporary XML with 40,000 tracks, four manual playlists, and 4,000 memberships, imports it twice, checks history survival, then runs a filtered query and aggregate SQL. One run on the current macOS environment (Ruby 3.4.7, sqlite3 2.10.1, Nokogiri 1.19.4) measured:

| Measurement | Result |
|---|---:|
| XML source size | 89,550,646 bytes |
| SQLite size after repeat import | 171,216,896 bytes |
| First import | 3.49 s |
| Repeat import | 4.31 s |
| Filtered query (100 returned rows) | 0.039 s |
| Aggregate SQL query | 0.039 s |
| Peak resident set size from `/usr/bin/time -l` | 915,243,008 bytes (about 873 MiB) |

These are measurements from one environment, not performance guarantees. The script removes its generated XML and database when it exits. No hardware-independent latency threshold is set.

## Limits

Library analysis and SQL are local. External candidate research and link verification use the host's available tools. Familiarity, recommendations, and exact identity are approximate. No audio-feature analysis, automatic Apple export, Spotify/YouTube history import, playlist publishing, or streaming-service mutations are implemented.

For command options, event scopes, SQL limits, schema discovery, and executable examples, see [`docs/cli.md`](docs/cli.md) and the linked runnable reference.
