#!/usr/bin/env bash
set -euo pipefail

db_path="${1:-$HOME/Library/Application Support/VellumX/vellumx.db}"

if [[ ! -f "$db_path" ]]; then
  echo "Database not found: $db_path" >&2
  exit 1
fi

backup_path="$db_path.backup.$(date +%Y%m%d%H%M%S)"
cp "$db_path" "$backup_path"
echo "Backup: $backup_path"

sqlite3 "$db_path" "CREATE TABLE IF NOT EXISTS paper_recommendations (paper_id TEXT PRIMARY KEY, recommended_at TEXT NOT NULL DEFAULT (datetime('now')), is_active INTEGER NOT NULL DEFAULT 1, recommendation_reason TEXT);"
sqlite3 "$db_path" "ALTER TABLE paper_recommendations ADD COLUMN recommendation_reason TEXT;" >/dev/null 2>&1 || true

sqlite3 "$db_path" <<'SQL'
.bail on
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE TRANSACTION;

CREATE TABLE IF NOT EXISTS paper_topics (
    paper_id TEXT NOT NULL,
    topic_name TEXT NOT NULL,
    PRIMARY KEY (paper_id, topic_name)
);

INSERT OR IGNORE INTO paper_topics (paper_id, topic_name)
SELECT papers.id, trim(value)
FROM papers,
     json_each('["' || replace(replace(COALESCE(track, ''), '"', '\"'), ',', '","') || '"]')
WHERE COALESCE(track, '') != '' AND trim(value) != '';

DROP TABLE IF EXISTS legacy_recommended;
CREATE TEMP TABLE legacy_recommended AS
SELECT paper_id, COALESCE(changed_at, datetime('now')) AS changed_at
FROM paper_states
WHERE status = 'recommended';

CREATE TABLE paper_cache_new (
    paper_id TEXT PRIMARY KEY,
    venue_abbr TEXT NOT NULL DEFAULT 'Others',
    score REAL NOT NULL DEFAULT 0,
    tier INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT DEFAULT (datetime('now'))
);

INSERT OR REPLACE INTO paper_cache_new (paper_id, venue_abbr, score, tier, updated_at)
SELECT id,
       COALESCE(NULLIF(venue_abbr, ''), 'Others'),
       COALESCE(score, 0),
       COALESCE(CAST(tier AS INTEGER), 0),
       COALESCE(updated_at, datetime('now'))
FROM papers;

DROP TABLE IF EXISTS paper_cache;
ALTER TABLE paper_cache_new RENAME TO paper_cache;

CREATE TABLE IF NOT EXISTS paper_pdfs (
    paper_id TEXT PRIMARY KEY,
    pdf_url TEXT NOT NULL,
    pdf_source TEXT,
    resolved_at TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO paper_pdfs (paper_id, pdf_url, pdf_source, resolved_at)
SELECT id, pdf_url, 'OpenAlex', COALESCE(updated_at, datetime('now'))
FROM papers
WHERE COALESCE(pdf_url, '') != '';

CREATE TABLE papers_new (
    id TEXT PRIMARY KEY,
    doi TEXT,
    title TEXT NOT NULL,
    authors TEXT,
    publication_date TEXT,
    venue TEXT,
    cited_by_count INTEGER DEFAULT 0,
    abstract TEXT,
    landing_page_url TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

INSERT OR REPLACE INTO papers_new (
    id, doi, title, authors, publication_date, venue, cited_by_count,
    abstract, landing_page_url, created_at, updated_at
)
SELECT id, doi, title, authors, publication_date, venue, cited_by_count,
       abstract, landing_page_url, created_at, updated_at
FROM papers;

DROP TABLE papers;
ALTER TABLE papers_new RENAME TO papers;

CREATE TABLE paper_states_new (
    paper_id TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'pending',
    changed_at TEXT DEFAULT (datetime('now'))
);

INSERT OR REPLACE INTO paper_states_new (paper_id, status, changed_at)
SELECT paper_id,
       CASE WHEN status = 'recommended' THEN 'pending' ELSE status END,
       COALESCE(changed_at, datetime('now'))
FROM paper_states;

DROP TABLE IF EXISTS paper_states;
ALTER TABLE paper_states_new RENAME TO paper_states;

CREATE TABLE paper_recommendations_new (
    paper_id TEXT PRIMARY KEY,
    recommended_at TEXT NOT NULL DEFAULT (datetime('now')),
    is_active INTEGER NOT NULL DEFAULT 1,
    recommendation_reason TEXT
);

INSERT OR REPLACE INTO paper_recommendations_new (paper_id, recommended_at, is_active, recommendation_reason)
SELECT paper_id, COALESCE(recommended_at, datetime('now')), COALESCE(is_active, 1), recommendation_reason
FROM paper_recommendations;

INSERT OR IGNORE INTO paper_recommendations_new (paper_id, recommended_at, is_active, recommendation_reason)
SELECT paper_id, changed_at, 1, NULL
FROM legacy_recommended;

DROP TABLE IF EXISTS paper_recommendations;
ALTER TABLE paper_recommendations_new RENAME TO paper_recommendations;

COMMIT;
VACUUM;
PRAGMA foreign_keys = ON;
SQL

echo "Refreshed: $db_path"
