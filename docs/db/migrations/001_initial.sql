CREATE TABLE IF NOT EXISTS library_import (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  source_kind TEXT NOT NULL CHECK (source_kind = 'apple_music'),
  library_key TEXT NOT NULL,
  source_sha256 TEXT NOT NULL,
  exported_at TEXT,
  imported_at TEXT NOT NULL,
  track_count INTEGER NOT NULL CHECK (track_count >= 0),
  playlist_count INTEGER NOT NULL CHECK (playlist_count >= 0)
);

CREATE TABLE IF NOT EXISTS tracks (
  track_key TEXT PRIMARY KEY,
  source_track_id INTEGER UNIQUE,
  persistent_id TEXT,
  title TEXT,
  artist TEXT,
  album TEXT,
  album_artist TEXT,
  genre TEXT,
  year INTEGER,
  duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
  rating_100 INTEGER CHECK (rating_100 IS NULL OR rating_100 BETWEEN 0 AND 100),
  rating_computed INTEGER CHECK (rating_computed IS NULL OR rating_computed IN (0, 1)),
  loved INTEGER CHECK (loved IS NULL OR loved IN (0, 1)),
  play_count INTEGER CHECK (play_count IS NULL OR play_count >= 0),
  skip_count INTEGER CHECK (skip_count IS NULL OR skip_count >= 0),
  date_added_at TEXT,
  last_played_at TEXT,
  compilation INTEGER CHECK (compilation IS NULL OR compilation IN (0, 1)),
  is_music INTEGER NOT NULL DEFAULT 1 CHECK (is_music IN (0, 1)),
  artist_normalized TEXT NOT NULL DEFAULT '',
  title_normalized TEXT NOT NULL DEFAULT '',
  album_normalized TEXT NOT NULL DEFAULT '',
  raw_fields_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS playlists (
  playlist_key TEXT PRIMARY KEY,
  source_playlist_id INTEGER,
  persistent_id TEXT,
  name TEXT,
  name_normalized TEXT NOT NULL DEFAULT '',
  parent_persistent_id TEXT,
  kind TEXT NOT NULL CHECK (kind IN ('manual', 'smart', 'system', 'folder')),
  raw_fields_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS playlist_tracks (
  playlist_key TEXT NOT NULL REFERENCES playlists(playlist_key) ON DELETE CASCADE,
  position INTEGER NOT NULL CHECK (position >= 1),
  track_key TEXT NOT NULL REFERENCES tracks(track_key) ON DELETE CASCADE,
  PRIMARY KEY (playlist_key, position)
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  request TEXT NOT NULL,
  context_key TEXT NOT NULL,
  context_json TEXT NOT NULL CHECK (json_valid(context_json) AND json_type(context_json) = 'object'),
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS recommendations (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id),
  position INTEGER NOT NULL CHECK (position >= 1),
  artist TEXT NOT NULL,
  title TEXT NOT NULL,
  album TEXT,
  version_label TEXT,
  library_track_key TEXT,
  artist_key TEXT NOT NULL,
  recording_key TEXT NOT NULL,
  reason TEXT NOT NULL,
  links_json TEXT NOT NULL CHECK (json_valid(links_json) AND json_type(links_json) = 'array'),
  created_at TEXT NOT NULL,
  UNIQUE (session_id, position)
);

CREATE TABLE IF NOT EXISTS feedback_events (
  id TEXT PRIMARY KEY,
  recommendation_id TEXT NOT NULL REFERENCES recommendations(id),
  event_type TEXT NOT NULL CHECK (event_type IN ('reaction', 'retraction')),
  reaction TEXT,
  scope TEXT NOT NULL CHECK (scope IN ('context', 'track', 'artist')),
  note TEXT,
  retracts_event_id TEXT REFERENCES feedback_events(id),
  created_at TEXT NOT NULL,
  CHECK (
    (event_type = 'reaction' AND reaction IN ('liked', 'disliked', 'already_known', 'wrong_fit', 'dont_recommend', 'note') AND retracts_event_id IS NULL)
    OR
    (event_type = 'retraction' AND reaction IS NULL AND retracts_event_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS tracks_artist_normalized_idx ON tracks(artist_normalized);
CREATE INDEX IF NOT EXISTS tracks_title_normalized_idx ON tracks(title_normalized);
CREATE INDEX IF NOT EXISTS tracks_last_played_at_idx ON tracks(last_played_at);
CREATE INDEX IF NOT EXISTS playlist_tracks_track_key_idx ON playlist_tracks(track_key);
CREATE INDEX IF NOT EXISTS recommendations_recording_created_idx ON recommendations(recording_key, created_at);
CREATE INDEX IF NOT EXISTS recommendations_artist_key_idx ON recommendations(artist_key);
CREATE UNIQUE INDEX IF NOT EXISTS recommendations_session_position_idx ON recommendations(session_id, position);
CREATE INDEX IF NOT EXISTS sessions_context_key_idx ON sessions(context_key);
CREATE INDEX IF NOT EXISTS feedback_events_recommendation_id_idx ON feedback_events(recommendation_id);
CREATE UNIQUE INDEX IF NOT EXISTS feedback_events_retraction_idx ON feedback_events(retracts_event_id) WHERE retracts_event_id IS NOT NULL;
