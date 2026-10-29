# Crackdealer Library CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task. Target executor: **Luna, medium reasoning effort**. Work sequentially; this plan does not require parallel implementation or a model upgrade. Steps use checkboxes for tracking.

**Goal:** Give a conversational music assistant efficient access to an Apple Music library and persistent, contextual recommendation feedback through a Ruby CLI backed by SQLite.

**Architecture:** Deterministic Ruby code imports and queries library metadata, records recommendations and feedback, and provides read-only SQL. A repository-owned skill uses those operations alongside its host's research tools to recommend music. Library snapshots and durable conversational history share one database but have separate lifecycles.

**Tech stack:** Ruby 3.4.x, Bundler, `sqlite3` 2.10.x, Nokogiri 1.x, Minitest, Rake, Ruby's `OptionParser` and JSON libraries. No Rails, ORM, application server, embeddings, or streaming-service SDKs.

**Spec:** [Original proposal](crackdealer-ideas.txt), supplemented and superseded where necessary by the accepted decisions below. This document includes the conversation decisions so the implementer does not need the original chat.

## Repository baseline and prerequisites

At planning time, only the original proposal existed and implementation had not begun. No actual library XML was present. `rg`, `jq`, `ast-grep`, `bundle`, and the SQLite shell are available. The selected Ruby is `/usr/bin/ruby`, version **2.6.10**, which is unsuitable for this plan.

Before implementation, locate an already-installed Ruby 3.4.x through the user's existing version manager. If none exists, report the missing runtime and obtain direction for its installation; do not install gems into system Ruby or silently switch languages. Once available, pin that exact patch in `.ruby-version`, use `ruby "~> 3.4.0"` in `Gemfile`, and generate `Gemfile.lock`. Runtime dependencies: `sqlite3 "~> 2.10.0"`, `nokogiri ">= 1.18", "< 2"`; development dependencies: Minitest and Rake. Verify current compatibility with Context7 and lock the resolved versions.

The absence of a real export does **not** block implementation or synthetic acceptance testing. It does prevent claiming real-library validation. Do not search unrelated user directories for private music data.

## Accepted design and scope

- The interface is a **skill plus a small CLI backed by SQLite**. Common queries live in the CLI; read-only SQL remains available for unusual queries. Promote repeated SQL workflows later, after observing actual use.
- Recommendations are approximate judgments. Familiarity, duplicate detection, and metadata quality are useful heuristics, not reasons to block recommendations or build a comprehensive music identity service.
- “New music” means **new to the user**, unless the request explicitly specifies new releases.
- Support external discovery, overlooked library tracks, playlist creation/extension, and alternate live performances through the skill. Playlist publishing and automatic exports are deferred.
- Use request-specific taste neighborhoods: seed artists/tracks and relevant playlists. No global taste score, fixed genre partition, or automatic clustering algorithm in this version. A track can belong to many neighborhoods.
- Explicit 4–5 star ratings, Loved, placement in a user-curated playlist, and frequent listening are positive evidence. Poor ratings are negative evidence. Unrated tracks with few plays are weak/unknown evidence. Preserve conflicting signals instead of choosing a winner invisibly.
- Favorites not played recently are useful playlist/rediscovery candidates, not automatically unfamiliar music.
- Favor original albums over greatest-hits releases when practical. Compilation appearances can also provide positive evidence. Do not discard all compilations: soundtracks, singles collections, and compilation-only tracks may be valuable.
- Feedback and recommendation history are must-haves. Feedback can express liking, familiarity, contextual fit, exclusion, and free-text nuance independently.
- The CLI performs **no network research**. The skill uses available host tools to research artists, reviews, live performances, and listening links. Do not invent service URLs or critical acclaim.
- Future adapters may add Spotify/YouTube evidence; preserve source identifiers and original metadata now, without implementing a generic integration framework.

## Global constraints

- All executable code, tests, and skill documentation live under `skills/jbootz-crackdealer/`. Do not install the skill globally during implementation.
- Default database: `data/crackdealer.sqlite3` relative to the skill package root, independent of the caller's working directory. Precedence: `--db PATH`, `CRACKDEALER_DB`, default. Expand `~`; treat values as filesystem paths, not SQLite URIs.
- Ignore `/data/`, `/tmp/`, `/.bundle/`, `/vendor/bundle/`, and all `*.sqlite3`, `*.sqlite3-wal`, `*.sqlite3-shm`, `*.sqlite3-journal` files. Commit only synthetic fixtures, never real exports/history. Do not ignore every XML file: tests need fixtures.
- Named queries use bound parameters. SQL passthrough uses a dedicated read-only connection and authorization rules; detecting a `SELECT` prefix is insufficient.
- Imports are atomic and never recreate the entire database file. A failed import leaves the previous library snapshot and all history usable.
- Imported fields remain separate from feedback. Feedback never changes Apple ratings, Loved, or play counts.
- Store times as UTC ISO 8601 strings using `Time#iso8601(6)`; use integer `duration_ms`, `play_count`, and `skip_count`. Preserve missing measurements as `NULL`, distinct from zero. Use explicit units in durations, thresholds, and timing identifiers.
- JSON goes to stdout; diagnostics go to stderr. Never print SQL bindings, entire exports, or raw track metadata in error messages.
- Do not commit or push merely because a task ends. Make task-scoped commits only if authorized by the implementation session; pushes require destination authorization. Preserve the proposal and unrelated files.

## Review focus

Each item has an owning task and a concrete test below:

1. Missing, false, and zero XML values; auto-generated ratings; non-ASCII names — preserve distinctions and avoid inventing preference evidence (Tasks 2–3).
2. Re-import after history exists, changed export-local track IDs, and malformed replacement XML — preserve feedback and roll back failed refreshes (Tasks 2, 5–6, 8).
3. Manual playlists, smart playlists, system playlists, duplicate names, and repeated tracks in one playlist — preserve order and avoid inflated curation signals (Tasks 2–3).
4. SQL writes disguised by comments/CTEs, database attachment, PRAGMAs, extension functions, multiple statements, and long queries — enforce read-only access without breaking ordinary analytical SQL (Task 4).
5. “Already know and love it,” contextual dislike, later corrections, and recommendations absent from the library — keep independent feedback dimensions and durable identity (Tasks 5–6).

## File map

Paths are relative to the `skills/jbootz-crackdealer/` package root.

| Path | Responsibility |
|---|---|
| `Gemfile`, `Gemfile.lock`, `.ruby-version`, `.gitignore`, `Rakefile` | Runtime, dependencies, data exclusions, test entry point |
| `bin/crackdealer` | Minimal executable; delegate to CLI |
| `bin/crackdealer-bootstrap` | Initialize the local database and import an explicitly supplied XML export when no snapshot exists |
| `lib/crackdealer.rb` | Requires, version, shared error classes |
| `lib/crackdealer/cli.rb` | Argument parsing, command routing, JSON output, exit codes |
| `lib/crackdealer/database.rb` | Path resolution, writer/read connections, migrations |
| `db/migrations/001_initial.sql` | Initial schema and indexes |
| `lib/crackdealer/apple_library.rb` | XML plist decoding and source-field mapping |
| `lib/crackdealer/importer.rb` | Transactional snapshot replacement and import report |
| `lib/crackdealer/identity.rb` | Conservative text normalization and recommendation keys |
| `lib/crackdealer/queries.rb` | Named library queries and evidence flags |
| `lib/crackdealer/sql_reader.rb` | Restricted arbitrary SQL execution and result limits |
| `lib/crackdealer/history.rb` | Sessions, recommendation batches, history reads/export |
| `lib/crackdealer/feedback.rb` | Feedback events, retractions, effective feedback reads |
| `SKILL.md` | Conversational workflow and interpretation rules |
| `references/cli.md` | Exact CLI examples and JSON payloads |
| `README.md` | Setup, import, use, privacy, backup/restore, limitations |
| `docs/cli.md` | Command and schema reference; promoting queries |
| `test/*_test.rb`, `test/test_helper.rb`, `test/fixtures/` | Behavioral tests and synthetic exports |
| `script/benchmark_import.rb` | Temporary synthetic 40,000-track acceptance run |

Keep Ruby classes under `Crackdealer`. Avoid a class per CLI subcommand. Separate CLI methods internally by command family; split files only if the resulting size genuinely impedes readability.

## Data contract

Use SQLite foreign keys on writer connections. Initial schema version is 1, recorded using `PRAGMA user_version`. Only `init` and `import` may initialize or migrate a database. Other commands require an existing compatible database and never migrate as a side effect. Reject newer schema versions clearly.

### Replaceable library snapshot

| Table | Required columns / constraints |
|---|---|
| `library_import` | Single row `id = 1`; `source_kind = 'apple_music'`, `library_key`, `source_sha256`, nullable `exported_at`, `imported_at`, `track_count`, `playlist_count` |
| `tracks` | `track_key TEXT PRIMARY KEY`, `source_track_id INTEGER UNIQUE`, nullable `persistent_id`, `title`, `artist`, `album`, `album_artist`, `genre`, `year`, `duration_ms`, `rating_100`, `rating_computed`, `loved`, `play_count`, `skip_count`, `date_added_at`, `last_played_at`, `compilation`, `is_music`, `artist_normalized`, `title_normalized`, `album_normalized`, `raw_fields_json` |
| `playlists` | `playlist_key TEXT PRIMARY KEY`, `source_playlist_id`, nullable `persistent_id`, `name`, `name_normalized`, nullable `parent_persistent_id`, `kind` in `manual/smart/system/folder`, `raw_fields_json` |
| `playlist_tracks` | `playlist_key` FK, `position` integer starting at 1, `track_key` FK; primary key `(playlist_key, position)`; **no** uniqueness constraint on track membership |

`library_key` comes from `Library Persistent ID`; require it rather than guessing a library from a filename. A later export with a different library key is rejected; use a different database for another Apple library. A track key is `apple_music:<library_key>:<Persistent ID>`. If a track lacks Persistent ID, use `apple_music:<library_key>:local:<Track ID>` and report a count of unstable keys. Use the equivalent playlist scheme. Do not treat export-local numeric IDs as durable when a Persistent ID exists.

Keep `rating_100` in Apple's original 0–100 units. Missing and 0 are both unrated for evidence queries, but remain distinguishable in storage. `rating_computed = 1` makes the rating ineligible as explicit user preference. Preserve nullable boolean source values as `NULL/0/1`; absence of a computation flag means no affirmative evidence it was computed. Do not substitute Album Rating for Rating.

### Durable history

Use `SecureRandom.uuid` text primary keys and UTC `created_at` for the following three tables. They have no foreign keys pointing into replaceable library tables.

| Table | Required columns / constraints |
|---|---|
| `sessions` | `id`, `request`, `context_key`, `context_json`, `created_at` |
| `recommendations` | `id`, `session_id` FK, `position`, `artist`, `title`, nullable `album`, `version_label`, `library_track_key`, `artist_key`, `recording_key`, `reason`, `links_json`, `created_at`; unique `(session_id, position)` |
| `feedback_events` | `id`, `recommendation_id` FK, `event_type` in `reaction/retraction`, nullable `reaction`, `scope` in `context/track/artist`, nullable `note`, nullable `retracts_event_id` FK to this table, `created_at` |

`context_key` defaults to `session:<session UUID>`. For an ongoing playlist, pass `playlist:<playlist_key>` so later sessions can reuse its contextual feedback. `context_json` holds request-specific seed artists, track keys, playlist keys, and notes; require an object, but do not build a taxonomy.

Normalize strings with Unicode NFKC, lowercase, trim, and collapse whitespace; normalize a missing value to the empty string while retaining NULL in the original column. Do not strip accents, punctuation, or version qualifiers. `artist_key` is normalized artist text. `recording_key` is SHA-256 of JSON encoding `[artist_key, normalized title, normalized version_label-or-empty]`; album is deliberately excluded. This is a conservative heuristic, not an authoritative recording identifier. Raw labels remain intact. A live version with different title/version remains distinct. Equivalent names formatted differently may not match; acceptable in v1.

`library_track_key` is an optional association. It is validated on creation if supplied, but may become unmatched after refresh; never delete history or automatically reattach it by numeric ID. The recommendation snapshot remains readable regardless.

Supported reactions: `liked`, `disliked`, `already_known`, `wrong_fit`, `dont_recommend`, `note`. `note` requires nonblank note text; other reactions allow a note. Multiple reactions may coexist, including apparently conflicting ones. Retractions point to an existing reaction event for the same recommendation, copy its scope, and cannot themselves be retracted. Reject a second retraction of the same event. To correct a retraction, add a new reaction. Effective feedback excludes retracted reactions, while raw events remain queryable.

Indexes: `tracks(artist_normalized)`, `tracks(title_normalized)`, `tracks(last_played_at)`, `playlist_tracks(track_key)`, `recommendations(recording_key, created_at)`, `recommendations(artist_key)`, `recommendations(session_id, position)`, `sessions(context_key)`, `feedback_events(recommendation_id)`, and a unique partial index on non-null `retracts_event_id`.

## CLI contract

Canonical invocation: `bundle exec ruby bin/crackdealer [--db PATH] COMMAND ...`. Global options precede the command. `--help` is available globally and per command; help/version use plain text. All other successes return one JSON object: `{"data": ..., "meta": {...}}`.

Metadata includes `schema_version` and nullable `imported_at`. List responses add `limit`, `offset`, `returned_count`, and `truncated` (whether another row exists). Default limit: 50 for named lists, 100 for SQL; offset: 0. Positive limits use a one-row lookahead. `--limit 0` explicitly allows unlimited results. Reject negative limits/offsets. Never silently dump the whole library.

Errors produce `{"error":{"code":"...","message":"..."}}` on stderr, empty stdout, and exit status 2 for input/usage errors or 1 for database/file/operational errors. Successful empty searches return status 0. Use stable codes: `invalid_input`, `not_found`, `database_error`, `import_error`, `sql_denied`, `query_timeout`, `io_error`. Do not rescue programmer bugs into empty success results.

| Command | Interface / result |
|---|---|
| `init` | Create parent directory/database/schema if absent; idempotent; return schema version |
| `status` | Snapshot timestamps/hash, counts, schema version, history counts; no raw source path |
| `schema` | Tables/views with columns/types and definitions, including history; supports ad hoc SQL discovery |
| `import XML_PATH [--allow-empty]` | Import complete snapshot; return counts, field-presence counts, warnings, elapsed_s; require opt-in for an empty Tracks dictionary |
| `tracks [--search TEXT] [--artist TEXT] [--playlist KEY] [--signal SIGNAL] [--frequent-play-count N] [--low-play-count N] [--stale-days N] [--include-nonmusic] [--limit N] [--offset N]` | Matching track metadata plus evidence flags; filters intersect; rules below |
| `playlists [--search TEXT] [--limit N] [--offset N]` | Playlist keys/names/kinds/parent identifiers and membership counts; duplicate names remain separate |
| `playlist KEY [--limit N] [--offset N]` | Ordered membership including `position`; duplicates preserved; missing key is `not_found` |
| `sql (--query SQL OR --file PATH) [--limit N] [--offset N] [--timeout-ms N]` | One read-only statement; `--file -` reads stdin; `data` contains `columns` and row arrays so duplicate column names survive |
| `session add --file PATH` | JSON `{request, context_key?, context?}`; `-` reads stdin; return created session |
| `recommendation add --file PATH` | JSON `{session_id, recommendations:[{artist,title,album?,version_label?,library_track_key?,reason,links?}]}`; append in array order, atomically; return created records |
| `history [--session-id ID] [--recording-key KEY] [--artist TEXT] [--context-key KEY] [--limit N] [--offset N]` | Newest recommendation records, request/context, and their own active feedback events; filters intersect |
| `feedback add --file PATH` | JSON `{recommendation_id,reaction,scope?,note?}`; scope defaults to `context`; return created reaction event |
| `feedback retract EVENT_ID` | Append retraction event; return it |
| `feedback list (--recommendation-id ID OR --artist TEXT --title TEXT [--version-label TEXT]) [--context-key KEY] [--limit N] [--offset N]` | Effective feedback applicable to a recorded or prospective candidate: same recording for track scope, same artist for artist scope, same recording AND matching context for context scope. Recorded candidates default to their session's context; prospective candidates without a context receive global track/artist feedback only |
| `history export` | Emit all durable tables, including retractions, under `data`, plus `export_format_version: 1`; explicit unbounded command for portable backup, no imported tracks |

JSON writes reject unknown top-level/payload keys and wrong types, require nonblank request/artist/title/reason, and reject empty recommendation batches. `links` defaults to `[]`, each element `{service,url}` with service `apple_music/spotify/youtube/other` and an HTTP(S) URL. Link existence is verified by the skill, not the CLI. Store JSON content with bound parameters; never interpolate it into shell commands. The CLI converts recognized payload keys to the keyword arguments documented below; arbitrary `context` contents remain ordinary JSON.

Named track search is literal substring matching over normalized title, artist, and album; artist filter is literal substring over normalized artist. Playlist search uses normalized playlist name. Escape SQL `%` and `_` in these filters. Stable track ordering is normalized artist/title/track key; playlist-list ordering is normalized name/key. Neither is an invented taste score. History ordering is created_at descending, then session_id and position descending, then id as a final tie-breaker. Return concise track metadata plus separate flags `explicit_positive`, `explicit_negative`, `loved_positive`, `manual_playlist_count`, `frequent_play`, `low_or_unknown_play`, `stale_play`, `unexplored_candidate`, `rediscovery_candidate`. Evidence flags are JSON booleans except `manual_playlist_count`, which is an integer. Convert SQLite 0/1 explicitly: Ruby considers 0 truthy. Original nullable source columns remain NULL/0/1. Do not include raw JSON unless SQL explicitly requests it.

Evidence defaults (adjustable heuristics, not claims about actual familiarity):

- Explicit positive: rating >= 80 and not computed; negative: rating > 0 and <= 40 and not computed.
- Positive evidence: explicit positive OR loved OR at least one distinct manual playlist OR play count >= `frequent_play_count` (default 10).
- Low/unknown play: missing play count OR play count <= `low_play_count` (default 2).
- Stale play: a non-null last-played time strictly earlier than `now - stale_days * 86_400`, default 730 days. Missing last-played time is unknown, not stale.
- `unexplored`: low/unknown plays, unrated (rating missing/zero or computed), not Loved, and no manual playlist placement. Any explicit nonzero rating, including three stars, excludes it. An empty result is fine; SQL supports broader interpretations.
- `rediscover`: positive evidence AND stale play. Preserve negative flags too if evidence conflicts.
- `--signal positive|negative|unexplored|rediscover` selects these sets; no signal returns all matching music tracks. Negative signals do not silently erase tracks from explicit searches.
- Manual membership counts distinct playlists, not duplicate appearances. Folder/system/smart playlists supply context but no inferred manual-curation signal.

## Tasks

### Shared test conventions and fixture truth

Use Minitest and real temporary SQLite files. Internal result envelopes use symbol keys; database row hashes use string keys. The assertions below assume local instances named `database`, `importer`, `queries`, `sql_reader`, `history`, and `feedback`, constructed using each task's documented interface. Do not add a global mutable test database. Inject a fixed clock returning `Time.iso8601('2026-10-23T12:00:00Z')` for date-sensitive tests.

Use library Persistent ID `AAAAAAAAAAAAAAAA`. Track Persistent IDs are their numeric fixture IDs zero-padded to 16 hexadecimal digits. Artist is `Aurora` unless noted; all unspecified flags/fields are absent. Set every track's album to `First Album` and duration to 180,000 ms.

| Track ID / title | Rating / computed / Loved | Plays / last played | Purpose |
|---|---|---|---|
| 1 / Old Favorite | 100 / absent / absent | 42 / 2020-01-01T00:00:00Z | Positive, stale, repeated manual memberships |
| 2 / Unheard | absent / absent / false | 0 / absent | Zero distinct from missing, unexplored |
| 3 / Explicit Reject | 20 / absent / false | 1 / absent | Negative, never unexplored |
| 4 / Conflict | 20 / absent / true | 15 / 2026-10-01T00:00:00Z | Both positive and negative |
| 5 / Computed, artist Björk | 100 / true / absent | absent / absent | Computed rating is not explicit preference |
| 6 / At Cutoff | 80 / false / absent | 10 / 2024-10-23T12:00:00Z | Exactly 730 days old; not strictly stale |
| 7 / Missing Date | 0 / absent / false | 12 / absent | Frequent but not provably stale |
| 8 / Video | 100 / absent / true | 20 / absent | Music Video true; excluded by default |
| 9 / Two Plays | absent / absent / absent | 2 / 2020-01-01T00:00:00Z | Inclusive low-play boundary |
| 10 / Neutral Three | 60 / false / absent | 0 / absent | Explicit neutral rating implies some familiarity |

Manual playlist P1 has source memberships `[1, 1, 999, 6]`; source track 999 does not exist. Manual P2 contains `[1]` and has the same name as P1. Smart playlist S1 contains `[5]`. Add an empty folder and a system playlist containing every track. Give all playlists distinct Persistent IDs. Import preserves P1 positions `[1, 2, 4]`; track 1's manual playlist count is 2. With defaults, unexplored IDs are `[2, 5, 9]`, rediscovery IDs `[1]`, and negative IDs `[3, 4]`. Add XML escaping and unusual names in isolated test variants without changing these baseline sets.

When a task lists several files to run, execute the full `bundle exec ruby -Itest test/<name>_test.rb` command for **each** file. Passing extra filenames to one Ruby invocation does not run them as separate test files.

### Task 1: Establish the runnable CLI and database lifecycle

**Files:** Create project/dependency files, `bin/crackdealer`, `lib/crackdealer.rb`, `cli.rb`, `database.rb`, `db/migrations/001_initial.sql`, `test/test_helper.rb`, `test/database_test.rb`, `test/cli_test.rb`.

**Interfaces:** `CLI.run(argv, out: $stdout, err: $stderr, input: $stdin) -> Integer`; `Database.new(path:)`; `Database#initialize! -> nil`; `Database#with_read { |db| ... }`; `Database#with_write { |db| ... }`; both yield a `SQLite3::Database` and close it in ensure. `Database#schema_version -> Integer`. Read mode never initializes/migrates. `Crackdealer::Error` carries `code` and `exit_status`.

- [ ] Verify the runtime prerequisite, then add Gemfile, lockfile, `.ruby-version`, Rake test task, and temporary-directory test helpers. `bundle exec rake test` discovers `test/**/*_test.rb`; helpers never touch the default database.
- [ ] Write failing tests: `test_init_is_idempotent` creates all contracted tables at version 1; `test_read_missing_database_does_not_create_file`; `test_newer_schema_is_rejected`; `test_foreign_keys_are_enforced`; `test_database_override_wins_over_environment`; `test_default_path_is_independent_of_cwd`; `test_cli_json_errors_and_exit_codes`.

  Core assertion:
  ```ruby
  2.times { database.initialize! }
  assert_equal 1, database.schema_version
  ```
- [ ] Run `bundle exec ruby -Itest test/database_test.rb` and `bundle exec ruby -Itest test/cli_test.rb`; confirm failures are missing behavior, not environment failures.
- [ ] Implement schema, connections, migrations, CLI envelope/error handling, `init`, `status`, `schema`, help, and version. Use a 5,000 ms busy timeout, default rollback journaling, and close every connection. Do not create history records for read commands.
- [ ] Re-run both files and `bundle exec rake test`; expect zero failures/errors. Verify init twice leaves counts unchanged, and `schema` describes feedback tables before any history exists.

### Task 2: Import an Apple Music snapshot without losing history

**Files:** Create `apple_library.rb`, `importer.rb`, `identity.rb`, `test/apple_library_test.rb`, `test/importer_test.rb`, `test/identity_test.rb`, `test/fixtures/library.xml`, `test/fixtures/library_updated.xml`; modify `cli.rb` and loader.

**Interfaces:** `Identity.normalize(text) -> String`; `Identity.recording_key(artist:, title:, version_label: nil) -> String`; `AppleLibrary.read(path) -> Hash` with symbol keys `library_key`, `exported_at`, `tracks`, `playlists`, `playlist_tracks`, `warnings`, `field_counts`; `Importer.new(database:, clock: -> { Time.now.utc })`; `Importer#import(path:, allow_empty: false) -> Hash` report.

- [ ] Build synthetic XML fixtures with ordinary Apple plist DOCTYPE, library/track/playlist Persistent IDs, Unicode and escaped text, 0/missing/false values, computed ratings, Loved true/false, timestamps, duration, a smart playlist, a folder, a system playlist, two manual playlists sharing a name, and a repeated membership. Include a nonmusic track and a playlist item referring to an absent track. The updated fixture changes numeric IDs while keeping Persistent IDs, removes a track, and changes ratings/order.
- [ ] Write failing tests: `test_maps_plist_types_and_preserves_raw_fields`; `test_missing_zero_and_false_remain_distinct`; `test_computed_and_album_ratings_are_not_explicit_track_ratings`; `test_normalization_preserves_version_and_accents`; `test_keys_survive_changed_numeric_ids`; `test_playlist_classification_and_duplicate_positions`; `test_dangling_playlist_items_are_reported`; `test_reimport_replaces_snapshot_without_duplicate_rows`; `test_invalid_import_rolls_back`; `test_empty_import_requires_opt_in`; `test_different_library_is_rejected`; `test_missing_persistent_ids_report_unstable_keys`.

  Core assertions after reading the fixture into `snapshot`:
  ```ruby
  assert_equal 'AAAAAAAAAAAAAAAA', snapshot.fetch(:library_key)
  assert_equal 10, snapshot.fetch(:tracks).length
  assert_equal 'björk', Crackdealer::Identity.normalize('  Björk  ')
  refute_equal Crackdealer::Identity.normalize('Song'), Crackdealer::Identity.normalize('Song (Live)')
  ```
- [ ] Run `bundle exec ruby -Itest test/apple_library_test.rb`, `test/identity_test.rb`, and `test/importer_test.rb` separately; confirm intended failures.
- [ ] Decode plist dict/array/string/integer/real/date/true/false/data nodes using strict Nokogiri XML parsing with NONET. Do not enable NOENT, DTDLOAD, or HUGE. Accept the normal Apple DOCTYPE without fetching it; reject custom entity declarations. Preserve data nodes as base64 strings. Reject invalid dict pairings, duplicate keys, malformed dates/numbers, and absent root Library Persistent ID/Tracks. Start with a DOM parser; no SAX implementation before measuring need.
- [ ] Map `Track ID`, `Persistent ID`, `Name`, `Artist`, `Album`, `Album Artist`, `Genre`, `Year`, `Total Time`, `Rating`, `Rating Computed`, `Loved`, `Play Count`, `Skip Count`, `Date Added`, `Play Date UTC`, and `Compilation`. Prefer `Play Date UTC`; do not guess a timestamp from the legacy numeric Play Date. Preserve other fields in raw JSON. Define `is_music = 0` for Podcast/Movie/TV Show/Music Video flags, otherwise 1; SQL can inspect everything.
- [ ] Classify playlists in precedence order: Folder true -> folder; Master true or Distinguished Kind present -> system; Smart Info or Smart Criteria present -> smart; otherwise manual. Report this as an approximation of manual curation, not proof the user individually added every track. Preserve original positions when skipping dangling memberships.
- [ ] Validate the full mapped snapshot before deleting rows, then replace only the four library tables in one transaction (memberships before parents), with `library_import` updated last. Stream the source SHA-256 calculation; report missing-field counts and warning counts with at most 10 examples. Preserve all durable tables. Add a failure test that triggers a constraint failure during replacement, proving transaction rollback after writes begin.
- [ ] Run the three test files and full suite. Confirm normal XML entities such as `&amp;` decode correctly and malicious custom entity fixtures neither fetch URLs nor read a local sentinel file.

### Task 3: Add reusable evidence and playlist queries

**Files:** Create `queries.rb`, `test/queries_test.rb`; modify CLI/loader and CLI tests.

**Interfaces:** `Queries.new(database:, clock: -> { Time.now.utc })`; `#tracks(search: nil, artist: nil, playlist_key: nil, signal: nil, frequent_play_count: 10, low_play_count: 2, stale_days: 730, include_nonmusic: false, limit: 50, offset: 0)`; `#playlists(search: nil, limit: 50, offset: 0)`; `#playlist(playlist_key:, limit: 50, offset: 0)`. Each returns `{rows:, truncated:}`. Use the contract's column names and evidence rules.

- [ ] Write failing tests with a fixed UTC clock: `test_positive_and_negative_evidence_can_coexist`; `test_computed_rating_is_not_explicit_preference`; `test_manual_membership_counts_distinct_playlists`; `test_smart_and_system_playlists_do_not_imply_manual_curation`; `test_unexplored_is_weak_evidence`; `test_stale_boundary_and_missing_time`; `test_filters_intersect`; `test_search_handles_unicode_quotes_and_literal_wildcards`; `test_playlist_preserves_repeated_tracks_and_order`; `test_pagination_is_stable_and_reports_truncation`; `test_nonmusic_is_available_only_when_requested`.

  Core assertions:
  ```ruby
  assert_equal [2, 5, 9], queries.tracks(signal: 'unexplored').fetch(:rows).map { |r| r.fetch('source_track_id') }.sort
  assert_equal [1], queries.tracks(signal: 'rediscover').fetch(:rows).map { |r| r.fetch('source_track_id') }
  ```
- [ ] Run `bundle exec ruby -Itest test/queries_test.rb`; expect intended failures.
- [ ] Implement shared SQL projections for evidence flags and parameterized filters. Counts must not multiply rows when a track occurs in several playlists. Fetch only requested result pages plus lookahead; do not load all tracks and filter in Ruby. Validate integer thresholds as nonnegative, with frequent-play-count >= 1. Use the same logic for filtering and returned evidence.
- [ ] Wire CLI options exactly as in the contract. The `playlist` command returns membership rows, while `tracks --playlist` returns distinct track candidates. Reject nonexistent playlist keys instead of reporting a misleading empty result.
- [ ] Run query and CLI tests, then full suite. Verify `--limit 0` deliberately returns the complete small fixture and default output omits raw metadata.

### Task 4: Provide genuinely read-only arbitrary SQL

**Files:** Create `sql_reader.rb`, `test/sql_reader_test.rb`; modify CLI/loader and CLI tests.

**Interfaces:** `SqlReader.new(database:)`; `#query(sql:, limit: 100, offset: 0, timeout_ms: 5_000) -> {columns:, rows:, truncated:}`. Keep ordinary SQL joins, aggregates, subqueries, CTEs, recursive CTEs, window functions, and JSON functions available.

- [ ] Write failing tests for allowed queries: joins across library/history, a CTE, a bounded recursive CTE, a window function, JSON extraction, `sqlite_schema`, duplicate output column names, a string containing a semicolon, limits/offsets, and `--file -`. Use actual SQLite, not a mocked connection.
- [ ] Write denial tests for INSERT/UPDATE/DELETE/DROP, writes with leading comments or WITH, temp-table creation, ATTACH of both an existing and nonexistent file, DETACH, VACUUM INTO, mutable PRAGMAs, `load_extension`, and `SELECT 1; DELETE ...`. Assert database rows remain unchanged and no destination file appears. Add a large recursive-query timeout test and assert the next read still works.

  Core assertions:
  ```ruby
  assert_equal [[10]], sql_reader.query(sql: 'SELECT COUNT(*) FROM tracks').fetch(:rows)
  error = assert_raises(Crackdealer::Error) { sql_reader.query(sql: 'DELETE FROM tracks') }
  assert_equal 'sql_denied', error.code
  assert_equal [[10]], sql_reader.query(sql: 'SELECT COUNT(*) FROM tracks').fetch(:rows)
  ```
- [ ] Run `bundle exec ruby -Itest test/sql_reader_test.rb`; expect intended failures.
- [ ] Use `Database#with_read`, which opens a fresh `SQLite3::Database.new(path, readonly: true)` connection, and set `results_as_hash = false` for SQL row arrays. Disable extension loading; register no functions with side effects. Set `statement_timeout` in milliseconds (`0` explicitly disables it). Install the SQLite authorizer **before preparing user SQL**. Allow only READ, SELECT, RECURSIVE, FUNCTION, and the read-only introspection PRAGMAs `table_info`, `table_xinfo`, `index_list`, `index_info`, `foreign_key_list`. Deny `load_extension`, `readfile`, and `writefile` function names, and deny all other authorization actions. Use explicit SQLite OK/DENY integer return values, not truthiness or IGNORE. Resolve the binding's action constants from the installed gem and cite them in a short code comment.
- [ ] Prepare exactly one statement; reject non-whitespace `Statement#remainder` before execution. Do not split on semicolons. A final semicolon followed by whitespace is allowed; a trailing comment after that semicolon may be rejected in v1 and should be documented. Reject empty SQL. Never use `execute_batch` here.
- [ ] Iterate rows rather than eagerly materializing an unlimited result; apply output offset/limit without rewriting the user's SQL, and stop at lookahead. Encode SQLite blobs as `{"base64":"..."}` if encountered. Ensure statements/results/connections close on success, denial, timeout, and output errors. Map authorization/read-only failures to `sql_denied`, interruption to `query_timeout`.
- [ ] Run SQL and CLI tests, then full suite. The raw SQL route must never call initialization/migrations or borrow a writer connection.

### Task 5: Persist recommendation sessions independently of the library

**Files:** Create `history.rb`, `test/history_test.rb`; modify CLI/loader and CLI tests.

**Interfaces:** `History.new(database:, clock: -> { Time.now.utc })`; `#create_session(request:, context_key: nil, context: {}) -> Hash`; `#add_recommendations(session_id:, recommendations:) -> Array<Hash>`; `#list(session_id: nil, recording_key: nil, artist: nil, context_key: nil, limit: 50, offset: 0) -> {rows:, truncated:}`; `#export -> Hash`. Reuse Task 2's identity methods.

- [ ] Write failing tests: `test_records_external_track_without_library_row`; `test_context_defaults_to_session_but_accepts_playlist_context`; `test_batch_is_atomic_and_positions_append`; `test_recording_key_ignores_album_but_preserves_live_version`; `test_reimport_and_track_removal_preserve_history`; `test_optional_library_association_is_validated`; `test_history_filters_and_pagination`; `test_bad_payload_does_not_write_partial_history`; `test_export_contains_all_durable_rows_including_empty_tables`.

  Core assertions:
  ```ruby
  session = history.create_session(request: 'Find more spooky folk')
  records = history.add_recommendations(session_id: session.fetch('id'), recommendations: [
    { artist: 'New Artist', title: 'New Song', reason: 'Fits the requested atmosphere' }
  ])
  assert_nil records.first.fetch('library_track_key')
  assert_equal 1, records.first.fetch('position')
  ```
- [ ] Run `bundle exec ruby -Itest test/history_test.rb`; expect intended failures.
- [ ] Implement payload validation and persistence. An external recommendation needs artist/title/reason, not a catalog ID. Store suggested links as supplied; do not make network calls. Use a transaction for each recommendation batch and monotonic positions within its session. Explicitly return IDs needed for subsequent feedback. Add recommendation history to status counts.
- [ ] Implement history JSON export with a consistent read transaction across durable tables and deterministic row ordering. `History#export` returns `{export_format_version: 1, sessions: [...], recommendations: [...], feedback_events: [...]}`; the CLI puts this under `data`. This is portable data export, not a replacement for database backup; automatic JSON restoration is deferred.
- [ ] Run history, importer, and CLI tests, then full suite. Verify history can be recorded after `init` even before the first library import.

### Task 6: Record and apply contextual feedback

**Files:** Create `feedback.rb`, `test/feedback_test.rb`; modify history reads, CLI/loader and CLI tests.

**Interfaces:** `Feedback.new(database:, clock: -> { Time.now.utc })`; `#add(recommendation_id:, reaction:, scope: 'context', note: nil) -> Hash`; `#retract(event_id:) -> Hash`; `#effective_for(recommendation_id: nil, artist: nil, title: nil, version_label: nil, context_key: nil, limit: 50, offset: 0) -> {rows:, truncated:}`. Require either recommendation_id or artist/title, never both. Return origin context, scope, timestamp, and note with each event so the assistant can interpret conflicts. Order events by created_at and id for stable pagination.

- [ ] Write failing tests: `test_known_liked_and_wrong_fit_can_coexist`; `test_default_feedback_does_not_leak_into_other_contexts`; `test_playlist_context_is_reused_across_sessions`; `test_track_scope_applies_to_same_recording_in_other_sessions`; `test_artist_scope_applies_to_other_tracks_by_artist`; `test_prospective_candidate_lookup_does_not_create_history`; `test_retraction_keeps_audit_history_but_removes_effect`; `test_duplicate_retraction_and_retracting_a_retraction_are_rejected`; `test_note_requires_text`; `test_unimported_recommendation_accepts_feedback`; `test_import_cannot_erase_feedback`; `test_reading_and_recommending_do_not_infer_feedback`.

  Core assertions, using a newly created recommendation's `recommendation_id`:
  ```ruby
  event = feedback.add(recommendation_id: recommendation_id, reaction: 'dont_recommend', scope: 'track')
  assert_equal ['dont_recommend'], feedback.effective_for(recommendation_id: recommendation_id).fetch(:rows).map { |r| r.fetch('reaction') }
  feedback.retract(event_id: event.fetch('id'))
  assert_empty feedback.effective_for(recommendation_id: recommendation_id).fetch(:rows)
  ```
- [ ] Run `bundle exec ruby -Itest test/feedback_test.rb`; expect intended failures.
- [ ] Implement append-only events and retractions with the data-contract validation. Do not convert coexistence into a single rating, apply automatic last-write-wins, or treat absent feedback as dislike. Corrections are explicit retraction plus a new reaction. `dont_recommend` remains scoped; track/artist-wide exclusion requires that explicit scope.
- [ ] Make `feedback list` perform cross-recommendation matching by scope, with retracted events excluded. Make history rows include only their own active feedback events; document this distinction. The skill uses the prospective-candidate lookup to check exclusions before recording its final selections. Raw events remain available through SQL and export.
- [ ] Run feedback, history, importer, and CLI tests, then full suite. Specifically verify a globally scoped exclusion survives import of `library_updated.xml` even when its original track disappears.

### Task 7: Package the skill and user-facing documentation

**Files:** Create `SKILL.md`, `references/cli.md`, `README.md`, `docs/cli.md`.

**Interfaces:** Skill only invokes documented CLI commands and available host research tools. CLI reference examples use temporary JSON files or stdin, not shell-interpolated prose. Consult the skill-creator instructions when authoring the actual skill; do not install it or edit global agent configuration.

- [ ] Write the skill with valid `name`/`description` frontmatter and a clear trigger for library-informed music discovery, playlists, and feedback. Resolve the executable relative to the skill's repository location; include setup instructions for invoking the repository CLI from any working directory.
- [ ] Specify the workflow: check status/freshness; interpret discovery vs playlist vs rediscovery/live request; inspect relevant seeds/playlists and scoped feedback/history; research candidates using available tools; use conservative identity/library matching; check applicable feedback using prospective-candidate lookups (page through truncated results); record the session and final selections; present those tracks with short library-grounded reasons and verified links. Do not record rejected research candidates as recommendations. Appearance in recommendation history does not prove the user listened; prior suggestions are a repeat-avoidance hint, not a permanent exclusion or negative preference. If recording fails, disclose that history was not saved rather than claiming persistence.
- [ ] Prefer exact normalized artist/title matches as a duplicate hint, allow SQL for broader checks, and tolerate imperfect matches. Favor original albums without treating the Compilation flag as synonymous with greatest hits. Alternate live performances remain eligible when requested. Provide links to all three services when verified and practical; one verified listening link is sufficient to present a recommendation.
- [ ] Require the skill to capture explicit user feedback through CLI commands, including several reactions where warranted. Default ambiguous scope to context. Never infer dislike from silence, a low play count, or a skipped recommendation. A request to avoid an artist warrants artist scope; ordinary playlist feedback does not. Honor effective `dont_recommend` events in the matching scope even when positive evidence also exists; exclusion does not erase the liking evidence.
- [ ] Explain taste neighborhoods as request-specific retrieval, not a global ranking. Preserve strong/weak/negative signals and their conflicts. Ask theme-vs-mixtape only when the request leaves it unclear. For mixtapes, sequence the final suggestions intentionally; for thematic lists, explain thematic fit. No promises of audio-feature analysis.
- [ ] Include runnable examples for every command, JSON schemas/examples, schema discovery, feedback correction, and a read-only SQL join across tracks/playlists/history. Explain how to promote a repeated SQL query: add a parameterized Queries method, a CLI route, a focused behavior test, and a reference example; preserve the SQL escape hatch.
- [ ] Document startup, imports, stale snapshots, approximate matching, unsupported binary plists, and manual export. For a full backup, stop CLI writers and copy the closed database; restore to a new path and verify using `--db` and `status`. Document `history export` separately as portable JSON with no restore command in v1.
- [ ] Execute every CLI example against synthetic data, substituting returned IDs rather than invented ones. Verify frontmatter parses using Ruby YAML. Review skill behavior against all ten original sample asks; indicate which steps use CLI data and which need host research tools. Do not claim an actual model quality evaluation from a textual review.

### Task 8: End-to-end acceptance and a realistic-size import check

**Files:** Create `test/acceptance_test.rb`, `script/benchmark_import.rb`; update README with measured results only if useful.

**Interfaces:** Acceptance tests execute the real CLI in subprocesses against temporary paths. Benchmark script accepts `--track-count N` (default 40,000) and produces a temporary synthetic XML export/database, emits JSON measurements, then cleans up. No real user data is needed.

- [ ] Add an end-to-end scenario: init -> import -> find positive/underplayed tracks -> inspect ordered playlist -> create session -> record an external recommendation -> add `liked` and `already_known` -> create another context -> verify contextual isolation -> add track-scoped `dont_recommend` -> reimport updated library -> verify exclusion/history survive -> retract exclusion -> run cross-table read-only SQL -> export history -> reject a write attempt. Check stdout JSON, exit codes, and persisted results at each transition.
- [ ] Run `bundle exec ruby -Itest test/acceptance_test.rb`; implement only integration fixes exposed by failures, then run `bundle exec rake test` with zero failures/errors.
- [ ] Generate 40,000 unique tracks with deterministic IDs, ratings, counts, and approximately 2 KB of harmless metadata per track so XML size is comparable to the proposed ~88 MB export. Include manual playlists with several thousand ordered memberships. Benchmark import, repeat import, filtered reads, and an aggregate SQL query. Assert exact imported counts and unchanged history; report source_size_bytes, database_size_bytes, elapsed_s, and query elapsed_s. Use `/usr/bin/time -l bundle exec ruby script/benchmark_import.rb --track-count 40000` on macOS to record peak resident memory separately. Do not invent a hardware-independent performance threshold.
- [ ] If memory/latency is unacceptable on the actual machine, document measurements before changing architecture. A DOM-to-streaming parser is a follow-up based on evidence, not an automatic addition to this plan.
- [ ] If the user supplies their export, import it into a **separate** private database, verify counts and field-presence summaries, inspect a few known ratings/playlists with the user, and report unsupported/missing fields. If no export is available, mark this check **not run**; do not block otherwise-complete synthetic acceptance.
- [ ] Inspect `git status --short` and the full diff. Confirm no private data, database artifacts, global configuration changes, or source changes outside this plan. Report completed tasks, test commands/results, benchmark figures, and any real-data validation gap. Do not implement future scope while waiting for feedback.

## Definition of done

- [ ] The CLI can import and refresh a synthetic Apple library, query evidence and ordered playlists, and perform arbitrary read-only analysis with joins/CTEs.
- [ ] Recommendations and contextual feedback persist independently of library presence and survive refreshes; corrections retain an audit trail.
- [ ] Tests demonstrate actual write denial, import rollback, feedback scope, duplicate playlist preservation, and explicit vs computed rating semantics.
- [ ] The skill has enough instructions and examples to use the CLI without rediscovering the schema or common queries every session.
- [ ] A synthetic 40,000-track import has measured time/memory evidence; real-export validation is accurately marked done or not run.
- [ ] No automatic streaming-service writes, global skill installation, automated export, global taste score, or sophisticated identity/clustering system has slipped into scope.

## Follow-ups deliberately deferred

Automatic Apple export; Spotify/YouTube history import; catalog API adapters and playlist publishing; MCP transport; audio embeddings/features; persistent inferred clusters; automatic recording-identity enrichment; popularity metrics; a web UI; and JSON history restore/merge. These can build on the CLI after the basic experience proves useful.

Recommendation quality still needs a human trial: use several of the original asks, compare against ordinary LLM suggestions, and collect real feedback. Automated database tests do not establish musical quality.

## Implementation references

These were checked during planning; consult current docs and the locked gem source when implementing an API-sensitive detail.

- [SQLite appropriate uses](https://www.sqlite.org/whentouse.html): local embedded storage fits this architecture.
- [SQLite authorizer](https://www.sqlite.org/c3ref/set_authorizer.html): authorization acts when statements are prepared; read-only opening alone does not define all allowed SQL actions.
- [sqlite3 Ruby database API](https://rubydoc.info/gems/sqlite3/SQLite3/Database): read-only construction, authorizer, statement timeout, and extension settings. This documentation may lag the newest gem; verify against the lockfile.
- [sqlite3 Ruby statement API](https://rubydoc.info/gems/sqlite3/SQLite3/Statement): remainder and column metadata.
- [sqlite3 Ruby parameter binding](https://github.com/sparklemotion/sqlite3-ruby/blob/main/FAQ.md): parameterized named queries.
- [Nokogiri parsing options](https://nokogiri.org/tutorials/parsing_an_html_xml_document.html): strict parsing, NONET, and entity/DTD defaults.
- [Apple XML export](https://support.apple.com/en-ie/guide/music/-mus27cd5060f/mac): exported library metadata is distinct from audio; actual field coverage still needs the user's export.
