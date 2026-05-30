#!/bin/bash
set -euo pipefail

DB_PATH="${1:-$HOME/Documents/VellumX/vellumx.db}"

if [ ! -f "$DB_PATH" ]; then
  echo "Database not found: $DB_PATH" >&2
  exit 1
fi

backup="$DB_PATH.backup.$(date +%Y%m%d%H%M%S)"
cp "$DB_PATH" "$backup"

sqlite3 "$DB_PATH" <<'SQL'
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;

DROP INDEX IF EXISTS idx_audit_action;
DROP INDEX IF EXISTS idx_audit_timestamp;
DROP TABLE IF EXISTS recommendations;
DROP TABLE IF EXISTS audit_logs;

CREATE TABLE IF NOT EXISTS paper_translations (
    paper_id TEXT PRIMARY KEY,
    abstract_zh TEXT,
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS paper_translations_clean (
    paper_id TEXT PRIMARY KEY,
    abstract_zh TEXT,
    updated_at TEXT DEFAULT (datetime('now'))
);

INSERT OR REPLACE INTO paper_translations_clean (paper_id, abstract_zh, updated_at)
SELECT paper_id, abstract_zh, COALESCE(updated_at, datetime('now'))
FROM paper_translations;

DROP TABLE IF EXISTS paper_translations;
ALTER TABLE paper_translations_clean RENAME TO paper_translations;

COMMIT;
PRAGMA foreign_keys = ON;
VACUUM;
SQL

echo "Cleaned deprecated DB fields: $DB_PATH"
echo "Backup: $backup"
