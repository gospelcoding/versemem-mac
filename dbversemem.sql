CREATE TABLE verses(
  v_id INTEGER PRIMARY KEY,
  reference TEXT,
  body TEXT,
  prompt TEXT
);

CREATE TABLE verse_records(
  vr_id INTEGER PRIMARY KEY,
  verse_id INTEGER,
  user_id INTEGER,
  status TEXT,
  right INTEGER,
  wrong INTEGER,
  streak INTEGER,
  streak_type TEXT,
  last_attempt TEXT
);

CREATE TABLE users(
  u_id INTEGER PRIMARY KEY,
  name TEXT UNIQUE
);