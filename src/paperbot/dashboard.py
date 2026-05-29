"""PaperBot web dashboard — single-page HTTP server."""

from __future__ import annotations

import json
import logging
import os
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

from paperbot.audit import AuditEntry, AuditStatus, get_audit_logs, get_audit_stats, log_audit
from paperbot.config import default_config_path, load_config
from paperbot.db import (
    get_paper_by_id_or_title,
    get_paper_note,
    get_paper_pdf,
    get_paper_translation,
    get_recent_reads,
    get_recommendation_history,
    get_stats,
    get_unread_papers,
    list_papers,
    save_recommendation,
    set_paper_note,
    set_paper_status,
    upsert_papers,
)
from paperbot.fetch import fetch_papers
from paperbot.models import PaperStatus
from paperbot.pdf_resolver import resolve_paper_pdf_cached
from paperbot.recommend import recommend_papers
from paperbot.translate import translate_paper_cached
from paperbot.utils import format_date

# ── Query-parameter limits ────────────────────────────────────────────

_DEFAULT_PAGE_SIZE = 50
_MAX_PAGE_SIZE = 200
_MAX_AUDIT_DAYS = 365
_MAX_RECENT_READS = 10
_DEFAULT_FETCH_DAYS = 40

def _load_template() -> str:
    """Load the dashboard HTML template from package resources."""
    import importlib.resources

    return importlib.resources.files("paperbot").joinpath("templates/dashboard.html").read_text()


def _json_response(handler: BaseHTTPRequestHandler, data: Any, status: int = 200) -> None:
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _html_response(handler: BaseHTTPRequestHandler, html: str, status: int = 200) -> None:
    body = html.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length == 0:
        return {}
    body = handler.rfile.read(content_length).decode("utf-8")
    return json.loads(body)


def _is_same_origin_post(handler: BaseHTTPRequestHandler) -> bool:
    origin = handler.headers.get("Origin")
    if not origin:
        return True

    host = handler.headers.get("Host", "")
    if not host:
        return False

    parsed = urllib.parse.urlparse(origin)
    return parsed.scheme == "http" and parsed.netloc == host


def make_handler(db_path: Path):
    class DashboardHandler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            # suppress default access logs
            pass

        def do_OPTIONS(self) -> None:
            self.send_response(204)
            self.end_headers()

        def _audit(self, action: str, status: str = AuditStatus.SUCCESS, details: dict[str, Any] | None = None, error_message: str = "") -> None:
            """Write an audit entry for a dashboard operation."""
            try:
                log_audit(db_path, AuditEntry(
                    action=action,
                    status=status,
                    details=details or {},
                    error_message=error_message,
                ))
            except Exception:
                logging.getLogger(__name__).exception("Audit logging failed for %s", action)

        def _handle_request(self, method: str) -> None:
            """Unified request handler with exception wrapping and audit support."""
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            try:
                if method == "GET":
                    self._do_get(path, parsed)
                elif method == "POST":
                    if not _is_same_origin_post(self):
                        _json_response(self, {"error": "Forbidden"}, 403)
                        return
                    self._do_post(path)
            except Exception as e:
                logging.getLogger(__name__).exception("Dashboard %s %s failed", method, path)
                _json_response(self, {"error": str(e)}, 500)

        def do_GET(self) -> None:
            self._handle_request("GET")

        def do_POST(self) -> None:
            self._handle_request("POST")

        def _do_get(self, path: str, parsed) -> None:
            qs = dict(urllib.parse.parse_qsl(parsed.query))

            if path == "/":
                _html_response(self, _load_template())

            elif path == "/api/stats":
                data = get_stats(db_path)
                _json_response(self, data)

            elif path == "/api/config":
                cfg = load_config(default_config_path())
                tracks = {}
                for name, tcfg in cfg.tracks.items():
                    tracks[name] = {
                        "query": tcfg.query,
                        "color": tcfg.color or "",
                    }
                _json_response(self, {"tracks": tracks, "dashboard_url": cfg.mail.dashboard_url})

            elif path == "/api/papers":
                limit = int(qs.get("limit", str(_DEFAULT_PAGE_SIZE)))
                offset = int(qs.get("offset", "0"))
                track = qs.get("track") or None
                status = qs.get("status") or None
                keyword = qs.get("keyword") or None
                sort_by = qs.get("sort_by") or "score"
                sort_order = qs.get("sort_order") or "desc"
                result = list_papers(
                    db_path,
                    track=track,
                    status=status,
                    keyword=keyword,
                    sort_by=sort_by,
                    sort_order=sort_order,
                    limit=min(limit, _MAX_PAGE_SIZE),
                    offset=max(offset, 0),
                )
                result["papers"] = [p.to_dict() for p in result["papers"]]
                _json_response(self, result)

            elif path.startswith("/api/paper/") and path.endswith("/note"):
                paper_id = urllib.parse.unquote(path[len("/api/paper/"):path.rfind("/note")])
                note = get_paper_note(db_path, paper_id)
                _json_response(self, {"paper_id": paper_id, "note": note})

            elif path.startswith("/api/paper/") and path.endswith("/translation"):
                paper_id = urllib.parse.unquote(path[len("/api/paper/"):path.rfind("/translation")])
                trans = get_paper_translation(db_path, paper_id)
                _json_response(self, {"paper_id": paper_id, **trans})

            elif path.startswith("/api/paper/") and path.endswith("/pdf"):
                paper_id = urllib.parse.unquote(path[len("/api/paper/"):path.rfind("/pdf")])
                pdf = get_paper_pdf(db_path, paper_id)
                if pdf:
                    _json_response(self, {"paper_id": paper_id, **pdf})
                else:
                    _json_response(self, {"paper_id": paper_id, "pdf_url": "", "pdf_source": ""})

            elif path.startswith("/api/paper/"):
                paper_id = urllib.parse.unquote(path[len("/api/paper/"):])
                matches = get_paper_by_id_or_title(db_path, paper_id, limit=1)
                if matches:
                    _json_response(self, matches[0].to_dict())
                else:
                    _json_response(self, {"error": "Paper not found"}, 404)

            elif path == "/api/recommendations":
                days = int(qs.get("days", "7"))
                rows = get_recommendation_history(db_path, days=min(days, _MAX_AUDIT_DAYS))
                _json_response(self, rows)

            elif path == "/api/recent-reads":
                limit = int(qs.get("limit", "3"))
                rows = get_recent_reads(db_path, limit=min(limit, _MAX_RECENT_READS))
                _json_response(self, [p.to_dict() for p in rows])

            elif path == "/api/audit":
                action = qs.get("action") or None
                limit = int(qs.get("limit", str(_DEFAULT_PAGE_SIZE)))
                offset = int(qs.get("offset", "0"))
                rows = get_audit_logs(db_path, action=action, limit=limit, offset=offset)
                _json_response(self, rows)

            elif path == "/api/audit/stats":
                days = int(qs.get("days", "7"))
                data = get_audit_stats(db_path, days=min(days, _MAX_AUDIT_DAYS))
                _json_response(self, data)

            else:
                self.send_error(404, "Not Found")

        def _do_post(self, path: str) -> None:
            if path.startswith("/api/paper/") and path.endswith("/note"):
                paper_id = urllib.parse.unquote(
                    path[len("/api/paper/"):path.rfind("/note")]
                )
                body = _read_body(self)
                note = body.get("note", "")
                set_paper_note(db_path, paper_id, note)
                self._audit("note", details={"paper_id": paper_id})
                _json_response(self, {
                    "success": True,
                    "paper_id": paper_id,
                })

            elif path == "/api/mark":
                body = _read_body(self)
                paper_id = body.get("id")
                status = body.get("status")
                if not paper_id or not status:
                    _json_response(self, {"error": "Missing id or status"}, 400)
                    return
                if status not in PaperStatus.ALL:
                    _json_response(self, {"error": "Invalid status"}, 400)
                    return
                set_paper_status(db_path, paper_id, status)
                self._audit("mark", details={"paper_id": paper_id, "status": status})
                _json_response(self, {"success": True, "id": paper_id, "status": status})

            elif path == "/api/update":
                cfg = load_config(default_config_path())
                papers, stats = fetch_papers(cfg, days=_DEFAULT_FETCH_DAYS)
                if papers:
                    inserted, updated = upsert_papers(db_path, papers)
                else:
                    inserted, updated = 0, 0
                self._audit("fetch", details={"inserted": inserted, "updated": updated, **stats})
                _json_response(self, {
                    "success": True,
                    "inserted": inserted,
                    "updated": updated,
                    "total": len(papers),
                    "range": stats.get("range", ""),
                })

            elif path == "/api/recommend":
                cfg = load_config(default_config_path())
                papers = get_unread_papers(db_path)
                if not papers:
                    _json_response(self, {"success": True, "count": 0, "message": "No unread papers"})
                    return

                results = recommend_papers(papers, cfg)
                if not results:
                    _json_response(self, {"success": True, "count": 0, "message": "No papers selected"})
                    return

                today = format_date()
                picks = [{"paper_id": r.paper_id, "slot_index": r.slot_index} for r in results]
                save_recommendation(db_path, today, picks)
                for r in results:
                    if r.paper_id:
                        set_paper_status(db_path, r.paper_id, PaperStatus.RECOMMENDED)

                self._audit("recommend", details={"count": len(results), "date": today})
                _json_response(self, {
                    "success": True,
                    "count": len(results),
                    "date": today,
                })

            elif path.startswith("/api/paper/") and path.endswith("/translate"):
                paper_id = urllib.parse.unquote(
                    path[len("/api/paper/"):path.rfind("/translate")]
                )
                matches = get_paper_by_id_or_title(db_path, paper_id, limit=1)
                if not matches:
                    _json_response(self, {"error": "Paper not found"}, 404)
                    return
                result = translate_paper_cached(db_path, matches[0])
                self._audit("translate", details={"paper_id": paper_id, "source": result["source"]})
                _json_response(self, {
                    "success": True,
                    "paper_id": paper_id,
                    "title_zh": result["title_zh"],
                    "abstract_zh": result["abstract_zh"],
                    "source": result["source"],
                })

            elif path.startswith("/api/paper/") and path.endswith("/resolve-pdf"):
                paper_id = urllib.parse.unquote(
                    path[len("/api/paper/"):path.rfind("/resolve-pdf")]
                )
                matches = get_paper_by_id_or_title(db_path, paper_id, limit=1)
                if not matches:
                    _json_response(self, {"error": "Paper not found"}, 404)
                    return
                result = resolve_paper_pdf_cached(db_path, matches[0])
                if result is None:
                    _json_response(self, {"error": "No DOI available"}, 400)
                    return
                self._audit("resolve_pdf", details={"paper_id": paper_id, "source": result.get("source", "")})
                _json_response(self, {
                    "success": True,
                    "paper_id": paper_id,
                    "pdf_url": result.get("pdf_url", ""),
                    "pdf_source": result.get("pdf_source", ""),
                    "source": result.get("source", "api"),
                })

            else:
                self.send_error(404, "Not Found")

    return DashboardHandler


def _pid_file(data_dir: Path) -> Path:
    return data_dir / "dashboard.pid"


def run_server(db_path: Path, host: str = "127.0.0.1", port: int = 8000) -> None:
    """Start the dashboard HTTP server."""
    import signal
    import sys

    handler = make_handler(db_path)
    server = HTTPServer((host, port), handler)

    # Write PID file
    pid_path = _pid_file(db_path.parent)
    pid_path.write_text(str(os.getpid()))

    def _handle_sigterm(signum, frame):
        pid_path.unlink(missing_ok=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, _handle_sigterm)
    signal.signal(signal.SIGINT, _handle_sigterm)

    print(f"Dashboard running at http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        pid_path.unlink(missing_ok=True)


def _kill_by_port(port: int) -> bool:
    """Try to find and kill a process listening on *port* via lsof."""
    import subprocess

    try:
        result = subprocess.run(
            ["lsof", "-ti", f":{port}"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0 and result.stdout.strip():
            killed = False
            for pid_str in result.stdout.strip().split():
                try:
                    os.kill(int(pid_str.strip()), 15)
                    killed = True
                except (ValueError, ProcessLookupError, PermissionError):
                    continue
            return killed
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return False


def stop_server(data_dir: Path, port: int = 8765) -> bool:
    """Stop the running dashboard server.

    First tries the PID file; if that is missing falls back to
    port-based process discovery (lsof / fuser).
    """
    pid_path = _pid_file(data_dir)
    if pid_path.exists():
        try:
            pid = int(pid_path.read_text().strip())
            os.kill(pid, 15)  # SIGTERM
            pid_path.unlink(missing_ok=True)
            return True
        except (ValueError, ProcessLookupError, PermissionError):
            pid_path.unlink(missing_ok=True)

    return _kill_by_port(port)
