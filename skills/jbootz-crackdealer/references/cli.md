# Crackdealer CLI reference

Run commands from the skill package root (`skills/jbootz-crackdealer/` in this repository). Install dependencies with `bundle install`; use Ruby 3.4.7. If the parent repository's `mise.toml` selects another version, prefix commands with `mise exec ruby@3.4.7 --`. The canonical form is:

```sh
bundle exec ruby bin/crackdealer [--db PATH] COMMAND [OPTIONS]
```

To run from elsewhere, resolve the absolute app root and set `BUNDLE_GEMFILE`:

```sh
BUNDLE_GEMFILE="$PROJECT_ROOT/Gemfile" mise exec ruby@3.4.7 -- bundle exec ruby "$PROJECT_ROOT/bin/crackdealer" --db "$DATABASE_PATH" status
```

If `mise` reports the parent config as untrusted, review it and run `mise trust ../../mise.toml` once from the app root before retrying.

The default database is `data/crackdealer.sqlite3` under the app root. `--db PATH` takes precedence over `CRACKDEALER_DB`. `import XML_PATH` initializes the database as needed and replaces the library snapshot while preserving history. Check `status` before importing; preserve existing snapshots unless a refresh is authorized. `CRACKDEALER_XML_PATH` can supply the explicit path to pass to `import`. Read commands never create or migrate a database. All successful non-help commands emit `{"data": ..., "meta": {"schema_version": 1, "imported_at": ...}}`. Errors go to stderr as `{"error":{"code":...,"message":...}}`; usage/input errors exit 2 and operational errors exit 1.

## Commands

| Command | Purpose |
|---|---|
| `init` | Create the database and schema; safe to repeat. |
| `status` | Show snapshot freshness, library counts, and durable-history counts. |
| `schema` | Describe tables, columns, and definitions. |
| `import XML_PATH [--allow-empty]` | Atomically replace the Apple Music XML snapshot while preserving history. |
| `tracks [--search TEXT] [--artist TEXT] [--playlist KEY] [--signal positive\|negative\|unexplored\|rediscover] [--frequent-play-count N] [--low-play-count N] [--stale-days N] [--include-nonmusic] [--limit N] [--offset N]` | Search tracks with separate evidence flags. |
| `playlists [--search TEXT] [--limit N] [--offset N]` | Search playlists. Duplicate names remain separate. |
| `playlist KEY [--limit N] [--offset N]` | Return ordered membership rows, preserving repeated tracks. |
| `sql (--query SQL OR --file PATH) [--limit N] [--offset N] [--timeout-ms N]` | Run one read-only SQL statement; `--file -` reads stdin. |
| `session add --file PATH` | Create a recommendation session from JSON; `-` reads stdin. |
| `recommendation add --file PATH` | Append a nonempty recommendation batch atomically; `-` reads stdin. |
| `history [filters]` | List newest recommendations, request/context, and their active feedback. |
| `feedback add --file PATH` | Add an explicit reaction; `-` reads stdin. |
| `feedback retract EVENT_ID` | Append a retraction for a reaction event. |
| `feedback list [selector] [filters]` | List effective reactions for a recorded or prospective candidate. |
| `history export` | Export all sessions, recommendations, reactions, and retractions as portable JSON. |

Paged commands default to 50 rows, except SQL which defaults to 100. `--offset` starts at zero. A positive limit fetches one extra row to set `truncated`; `--limit 0` requests all matching rows. Negative limits and offsets are rejected.

## Runnable example

This sequence uses the checked-in synthetic Apple Music fixture, a temporary database, and IDs returned by earlier commands. It exercises every command family, including schema discovery, SQL across library and history, feedback correction, and export. Run it from the app root with `jq` installed.

```sh
set -euo pipefail
APP_ROOT="$PWD"
EXAMPLE_TMP="$(mktemp -d)"
DATABASE_PATH="$EXAMPLE_TMP/example.sqlite3"
CLI=(bundle exec ruby "$APP_ROOT/bin/crackdealer" --db "$DATABASE_PATH")
trap 'rm -rf "$EXAMPLE_TMP"' EXIT

"${CLI[@]}" init
"${CLI[@]}" import "$APP_ROOT/test/fixtures/library.xml"
"${CLI[@]}" status
"${CLI[@]}" schema
"${CLI[@]}" tracks --signal unexplored --limit 0
"${CLI[@]}" tracks --artist Aurora --search "Old Favorite" --limit 5

PLAYLIST_KEY="$("${CLI[@]}" playlists --search 'Shared & Name' --limit 0 | jq -er '.data.rows[] | select(.source_playlist_id == 1) | .playlist_key')"
TRACK_KEY="$("${CLI[@]}" tracks --search 'Old Favorite' --limit 0 | jq -er '.data.rows[] | select(.source_track_id == 1) | .track_key')"
"${CLI[@]}" playlist "$PLAYLIST_KEY" --limit 10

"${CLI[@]}" sql --file - --limit 10 <<'SQL'
SELECT t.title AS library_title, p.name AS playlist_name,
       r.title AS recommended_title, s.request, f.event_type, f.reaction
FROM playlist_tracks pt
JOIN tracks t ON t.track_key = pt.track_key
JOIN playlists p ON p.playlist_key = pt.playlist_key
LEFT JOIN recommendations r ON r.library_track_key = t.track_key
LEFT JOIN sessions s ON s.id = r.session_id
LEFT JOIN feedback_events f ON f.recommendation_id = r.id
ORDER BY p.name, pt.position, r.position, f.created_at
SQL

SESSION_JSON="$EXAMPLE_TMP/session.json"
jq -n --arg playlist_key "$PLAYLIST_KEY" \
  '{request:"Rediscover a favorite for this playlist",context_key:("playlist:"+$playlist_key),context:{playlist_key:$playlist_key,seed_artist:"Aurora"}}' \
  > "$SESSION_JSON"
SESSION_ID="$("${CLI[@]}" session add --file "$SESSION_JSON" | jq -er '.data.id')"
CONTEXT_KEY="playlist:$PLAYLIST_KEY"

RECOMMENDATION_JSON="$EXAMPLE_TMP/recommendation.json"
jq -n --arg session_id "$SESSION_ID" --arg track_key "$TRACK_KEY" \
  '{session_id:$session_id,recommendations:[{artist:"Aurora",title:"Old Favorite",library_track_key:$track_key,reason:"Highly rated and a rediscovery candidate",links:[]}]}' \
  > "$RECOMMENDATION_JSON"
RECOMMENDATION_ID="$("${CLI[@]}" recommendation add --file "$RECOMMENDATION_JSON" | jq -er '.data.recommendations[0].id')"

FEEDBACK_JSON="$EXAMPLE_TMP/feedback.json"
jq -n --arg recommendation_id "$RECOMMENDATION_ID" \
  '{recommendation_id:$recommendation_id,reaction:"already_known"}' > "$FEEDBACK_JSON"
"${CLI[@]}" feedback add --file "$FEEDBACK_JSON"
jq -n --arg recommendation_id "$RECOMMENDATION_ID" \
  '{recommendation_id:$recommendation_id,reaction:"liked",scope:"context"}' > "$FEEDBACK_JSON"
"${CLI[@]}" feedback add --file "$FEEDBACK_JSON"
jq -n --arg recommendation_id "$RECOMMENDATION_ID" \
  '{recommendation_id:$recommendation_id,reaction:"wrong_fit",note:"I meant a more atmospheric mix"}' \
  > "$FEEDBACK_JSON"
WRONG_FIT_ID="$("${CLI[@]}" feedback add --file "$FEEDBACK_JSON" | jq -er '.data.id')"
"${CLI[@]}" feedback list --recommendation-id "$RECOMMENDATION_ID" --limit 0
"${CLI[@]}" feedback list --artist Aurora --title "Old Favorite" --context-key "$CONTEXT_KEY" --limit 0
"${CLI[@]}" feedback retract "$WRONG_FIT_ID"

"${CLI[@]}" history --session-id "$SESSION_ID" --limit 0
"${CLI[@]}" history --recording-key "$("${CLI[@]}" history --session-id "$SESSION_ID" --limit 1 | jq -er '.data.rows[0].recording_key')"
"${CLI[@]}" history export
```

`feedback list --recommendation-id ID` uses the recommendation's context by default. A prospective `--artist`/`--title` lookup without `--context-key` returns only global track and artist reactions. Supply a context key to include matching context reactions. If `truncated` is true, continue with the next `--offset` before making an exclusion decision.

## JSON payloads

Create a session:

```json
{"request":"Find new-to-me folk","context_key":"playlist:example-key","context":{"seed_artists":["Aurora"],"playlist_keys":["example-key"],"notes":"quiet, nocturnal"}}
```

Add final selections in displayed order. The batch must be nonempty; each artist, title, and reason must be nonblank. `links` defaults to `[]`; each supplied link has exactly `service` and `url`, where service is `apple_music`, `spotify`, `youtube`, or `other`, and URL is HTTP(S). The CLI validates link shape, not whether the link actually plays the track.

```json
{"session_id":"<returned session id>","recommendations":[{"artist":"Artist","title":"Song","album":"Album","version_label":"Live","library_track_key":null,"reason":"Fits the seed artist's acoustic side","links":[{"service":"other","url":"https://example.com/song"}]}]}
```

Add feedback; `scope` defaults to `context`. Supported reactions are `liked`, `disliked`, `already_known`, `wrong_fit`, `dont_recommend`, and `note`. `note` requires nonblank text. Several reactions may coexist; corrections use retraction plus a new reaction.

```json
{"recommendation_id":"<returned recommendation id>","reaction":"dont_recommend","scope":"artist","note":"Avoid this artist in future recommendations"}
```

## Schema and evidence

Use `schema` to inspect the live table/column definitions. Principal tables are `library_import`, `tracks`, `playlists`, `playlist_tracks`, `sessions`, `recommendations`, and `feedback_events`. All table relationships and constraints are available from schema output. JSON fields are `tracks.raw_fields_json`, `playlists.raw_fields_json`, `sessions.context_json`, and `recommendations.links_json`.

`tracks` returns concise imported metadata plus evidence flags. Ratings use Apple's 0–100 `rating_100`; computed ratings are not explicit preference. Manual playlist evidence counts distinct manual playlists. `unexplored` uses low/unknown plays, no explicit nonzero rating, no Loved flag, and no manual placement; `rediscover` combines positive evidence with a stale non-null play date. These are adjustable heuristics, not familiarity claims. Missing play dates are unknown, not stale.

`history` includes each recommendation's own active feedback only. `feedback list` can match feedback across recommendations by scope. `history export` includes raw reactions and retractions in creation order; it has no automatic restore command.

## Read-only SQL

SQL accepts one prepared statement. Ordinary reads, joins, aggregates, CTEs, recursive CTEs, windows, JSON functions, and read-only schema PRAGMAs are available. Writes, attachment, mutable PRAGMAs, extension loading, and multiple statements are denied. A final semicolon followed by whitespace is allowed; a trailing comment after that semicolon may be rejected. The default timeout is 5 seconds and `--timeout-ms` must be positive. The default output limit is 100 rows; `--limit 0` removes the output cap.

The runnable example above joins library tracks and playlists to linked recommendations, sessions, and raw feedback events. For schema introspection:

```sh
bundle exec ruby bin/crackdealer --db data/crackdealer.sqlite3 sql --query 'PRAGMA table_info(recommendations)'
```

If the same SQL query becomes a repeated workflow, promote it by adding a parameterized method to `lib/crackdealer/queries.rb`, adding a CLI route, writing a focused behavior test, and documenting that route here. Keep the SQL reader for one-off analysis.
