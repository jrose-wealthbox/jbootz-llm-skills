# CLI and schema reference

Crackdealer is a local Ruby 3.4.7 application. Run commands from the skill package root (`skills/jbootz-crackdealer/` in this repository):

```sh
bundle exec ruby bin/crackdealer [--db PATH] COMMAND [OPTIONS]
```

When running from another directory, set `BUNDLE_GEMFILE` to the app's absolute `Gemfile` path and pass the absolute path to `bin/crackdealer`. If the parent repository's `mise.toml` selects another Ruby, prefix the invocation with `mise exec ruby@3.4.7 --`. If `mise` reports that config as untrusted, review it and run `mise trust ../../mise.toml` once from the app root before retrying. The default database lives at `data/crackdealer.sqlite3` under the app root. Path precedence is `--db`, `CRACKDEALER_DB`, then default. `init` creates the schema; `import` can initialize before replacing a snapshot. Other commands require an existing compatible database and do not migrate it.

## Commands and result shapes

| Command | Result in `data` |
|---|---|
| `init` | `{schema_version}` |
| `status` | `{snapshot, track_count, playlist_count, playlist_membership_count, history_counts}` |
| `schema` | `{tables:[{name,definition,columns:[...]}]}` |
| `import XML_PATH [--allow-empty]` | Source hash, snapshot counts, field-presence counts, warnings, and `elapsed_s`. |
| `tracks ...` | `{rows,limit,offset,returned_count,truncated}` with evidence flags. |
| `playlists ...` | `{rows,limit,offset,returned_count,truncated}`. |
| `playlist KEY ...` | Ordered membership list with positions; repeated track membership is retained. |
| `sql ...` | `{columns,rows,limit,offset,returned_count,truncated}`; rows are arrays so duplicate output names survive. |
| `session add --file PATH` | The created session including its returned ID. |
| `recommendation add --file PATH` | `{recommendations:[...]}` with IDs and append positions. |
| `history ...` | `{rows,limit,offset,returned_count,truncated}`; each row includes request/context and its own active feedback. |
| `feedback add --file PATH` | The created reaction event. |
| `feedback retract EVENT_ID` | The appended retraction event. |
| `feedback list ...` | Effective reaction events plus their origin request/context. |
| `history export` | `{export_format_version:1,sessions,recommendations,feedback_events}`. |

Success output is one JSON object with `data` and `meta` (`schema_version` and nullable `imported_at`). Errors are JSON on stderr; stdout is empty. Input/usage errors exit 2; database, file, and timeout errors exit 1. `--help` and `--version` are plain text.

Named list commands default to 50 rows; SQL defaults to 100. Offset defaults to zero. Positive limits use one-row lookahead to report `truncated`; `--limit 0` is an explicit unlimited result. Continue with `--offset` while `truncated` is true, especially when checking all applicable exclusions.

## Database tables

Use `schema` for the live definitions, columns, types, constraints, and indexes. The migration is [001_initial.sql](../db/migrations/001_initial.sql).

| Table | Contents and lifecycle |
|---|---|
| `library_import` | Current Apple Music library identifier, source hash, export/import timestamps, and snapshot counts; one row. |
| `tracks` | Current library snapshot. `track_key` uses library ID and Persistent ID when present; source IDs and Apple fields remain nullable where missing. `duration_ms` is milliseconds; `rating_100` is Apple's 0–100 value. `raw_fields_json` preserves source metadata. |
| `playlists` | Current snapshot playlist names, persistent keys, parent IDs, and approximate kind (`manual`, `smart`, `system`, `folder`). |
| `playlist_tracks` | Current ordered membership. Position starts at 1; repeated track appearances are allowed. |
| `sessions` | Durable request/context snapshots with UUID, `context_key`, object-valued `context_json`, and UTC `created_at`. Default context key is `session:<id>`. |
| `recommendations` | Durable assistant selections, append position, artist/title/album/version, optional library key, normalized identity keys, reason, `links_json`, and UTC timestamp. Album does not distinguish recording keys. |
| `feedback_events` | Append-only reactions and retractions. Retractions point to the original reaction and preserve its scope. |

The four library tables are replaced atomically on import. No durable history table has a foreign key to a replaceable library table. A recommendation's optional `library_track_key` is validated when added, but remains readable if a later import removes that track.

## Evidence flags

`tracks` returns separate booleans: `explicit_positive`, `explicit_negative`, `loved_positive`, `frequent_play`, `low_or_unknown_play`, `stale_play`, `unexplored_candidate`, and `rediscovery_candidate`, plus integer `manual_playlist_count`. SQLite integer flags are converted explicitly to JSON booleans. A computed rating is not explicit preference; a missing play date is unknown rather than stale. Manual playlist counts are distinct playlist counts, not membership counts. Signals are heuristics and do not override one another.

Search filters are parameterized literal substrings. `%` and `_` are escaped. Result ordering is stable by normalized fields and keys. Default track queries omit raw JSON and nonmusic items; `--include-nonmusic` opts in.

## Session, recommendation, and feedback contracts

`session add --file PATH` accepts `{"request":"...","context_key":"optional","context":{}}`; `--file -` reads stdin. Context must be a JSON object. For an existing playlist, use `playlist:<playlist_key>` when separate sessions should share contextual feedback.

`recommendation add --file PATH` accepts `{"session_id":"<session id>","recommendations":[...]}` with a nonempty array of final selected recommendations. Each row requires nonblank `artist`, `title`, and `reason`; accepts optional `album`, `version_label`, and `library_track_key`; and has `links:[]` by default. Link objects have exactly `{service,url}` with service `apple_music`, `spotify`, `youtube`, or `other` and an HTTP(S) URL. The CLI does not verify that the URL plays that recording. Each batch appends positions atomically; its returned IDs are used for feedback.

Reactions are `liked`, `disliked`, `already_known`, `wrong_fit`, `dont_recommend`, and `note`. `note` requires nonblank note text. Scope is `context` by default and can be `track` or `artist`. Reactions coexist. Silence and low play counts do not create negative feedback. Corrections append a retraction and a new reaction; they do not edit or erase the audit row.

`feedback list` accepts either `--recommendation-id ID` or a prospective `--artist TEXT --title TEXT [--version-label TEXT]`, never both. It returns active events that match by scope: same recording for `track`, normalized artist for `artist`, and same recording plus matching context for `context`. A recorded target defaults to its session's context. A prospective target with no `--context-key` sees global track and artist reactions only. `history` shows only the selected recommendation's own active feedback; `feedback list` performs cross-recommendation matching. `history export` includes all raw events and retractions in deterministic JSON; there is no restore command in v1.

Runnable payloads and a sequence that exercises every command are in [the skill CLI reference](../references/cli.md).

## SQL access and query promotion

`sql` opens an existing database with a read-only connection and an authorization policy. It accepts one prepared statement, rejects additional statements, and permits ordinary analytical reads, joins, CTEs, windows, JSON functions, and approved introspection PRAGMAs. It denies writes, attach/detach, mutable PRAGMAs, extension loading, and other authorization actions. Default timeout is 5,000 ms; `--timeout-ms` must be positive. Default output limit is 100 rows; offset defaults to zero. BLOB results are returned as `{ "base64": "..." }`.

Example schema discovery:

```sh
bundle exec ruby bin/crackdealer --db data/crackdealer.sqlite3 schema
bundle exec ruby bin/crackdealer --db data/crackdealer.sqlite3 sql --query 'PRAGMA table_info(recommendations)'
```

For a query used repeatedly, add a parameterized method in `lib/crackdealer/queries.rb`, expose it through a CLI route, add a focused behavior test, and document its output. Keep the read-only SQL escape hatch for one-off questions.

## Original request coverage

The source proposal contains nine quoted sample asks (the implementation plan says ten). The skill has been reviewed against each source ask; this is a textual coverage review, not a recommendation-quality evaluation.

| Request type | CLI evidence | Host research/tools |
|---|---|---|
| Similar to one artist | Artist tracks, evidence flags, playlists, and feedback. | Find comparable artists and verify candidates/listening links. |
| Similar to several artists | Inspect each seed independently and combine request-specific signals. | Research overlap and new candidate artists. |
| Halloween party playlist | Search relevant library tracks/playlists and familiar seeds. | Research theme fit; sequence as a theme list or mixtape based on user's intent. |
| Extend an existing playlist | Resolve the playlist key, inspect ordered membership, and reuse `playlist:<key>` feedback context. | Research additions and verify links. |
| Uptempo glam party mix | Inspect similar artists and positive evidence; preserve mixed tastes. | Verify tempo/genre descriptions and sequence the mixtape. |
| Unrated or rarely played library tracks | `tracks --signal unexplored` and, separately, `--signal rediscover`. | Judge whether the user may enjoy the candidates; evidence is not a guarantee. |
| Deep cuts like the Beatles | Inspect Beatles-related library neighborhoods and exclusions. | Verify obscurity/deep-cut claims and source links. |
| Second-wave British ska | Search library seeds and feedback; no automatic genre clustering. | Research era/subgenre candidates and confirm dates. |
| Live versions of loved tracks | Find strong library evidence such as high ratings or Loved. | Search KEXP, BBC sessions, and YouTube; verify the exact performance. |
