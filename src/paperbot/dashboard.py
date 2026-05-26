"""PaperBot web dashboard — single-page HTTP server."""

from __future__ import annotations

import json
import os
import sqlite3
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

from paperbot.audit import get_audit_logs, get_audit_stats
from paperbot.config import default_config_path, load_config
from paperbot.db import (
    get_paper_by_id_or_title,
    get_paper_note,
    get_paper_pdf,
    get_paper_translation,
    get_recent_reads,
    get_stats,
    get_unread_papers,
    init_db,
    list_papers,
    save_recommendation,
    set_paper_note,
    set_paper_pdf,
    set_paper_status,
    set_paper_translation,
    upsert_papers,
)
from paperbot.fetch import fetch_papers
from paperbot.pdf_resolver import PdfResolver
from paperbot.recommend import recommend_papers
from paperbot.translate import translate_paper

def _load_template() -> str:
    """Load the dashboard HTML template from package resources."""
    import importlib.resources

    return importlib.resources.files("paperbot").joinpath("templates/dashboard.html").read_text()


def _json_response(handler: BaseHTTPRequestHandler, data: Any, status: int = 200) -> None:
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Access-Control-Allow-Origin", "*")
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


def _parse_qs(path: str) -> dict[str, str]:
    parsed = urllib.parse.urlparse(path)
    return dict(urllib.parse.parse_qsl(parsed.query))


def _read_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length == 0:
        return {}
    body = handler.rfile.read(content_length).decode("utf-8")
    return json.loads(body)


def make_handler(db_path: Path):
    class DashboardHandler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            # suppress default access logs
            pass

        def do_OPTIONS(self) -> None:
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.end_headers()

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            qs = dict(urllib.parse.parse_qsl(parsed.query))

            try:
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
                    limit = int(qs.get("limit", "50"))
                    offset = int(qs.get("offset", "0"))
                    track = qs.get("track") or None
                    status = qs.get("status") or None
                    keyword = qs.get("keyword") or None
                    sort_by = qs.get("sort_by") or "score"
                    sort_order = qs.get("sort_order") or "desc"
                    data = list_papers(
                        db_path,
                        track=track,
                        status=status,
                        keyword=keyword,
                        sort_by=sort_by,
                        sort_order=sort_order,
                        limit=min(limit, 200),
                        offset=max(offset, 0),
                    )
                    _json_response(self, data)

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
                        _json_response(self, matches[0])
                    else:
                        _json_response(self, {"error": "Paper not found"}, 404)

                elif path == "/api/recommendations":
                    from paperbot.db import get_recommendation_history

                    days = int(qs.get("days", "7"))
                    rows = get_recommendation_history(db_path, days=min(days, 365))
                    _json_response(self, rows)

                elif path == "/api/recent-reads":
                    limit = int(qs.get("limit", "3"))
                    rows = get_recent_reads(db_path, limit=min(limit, 10))
                    _json_response(self, rows)

                elif path == "/api/audit":
                    action = qs.get("action") or None
                    limit = int(qs.get("limit", "50"))
                    offset = int(qs.get("offset", "0"))
                    rows = get_audit_logs(db_path, action=action, limit=limit, offset=offset)
                    _json_response(self, rows)

                elif path == "/api/audit/stats":
                    days = int(qs.get("days", "7"))
                    data = get_audit_stats(db_path, days=min(days, 365))
                    _json_response(self, data)

                else:
                    self.send_error(404, "Not Found")

            except Exception as e:
                _json_response(self, {"error": str(e)}, 500)

        def do_POST(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            try:
                if path.startswith("/api/paper/") and path.endswith("/note"):
                    paper_id = urllib.parse.unquote(
                        path[len("/api/paper/"):path.rfind("/note")]
                    )
                    body = _read_body(self)
                    note = body.get("note", "")
                    set_paper_note(db_path, paper_id, note)
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
                    set_paper_status(db_path, paper_id, status)
                    _json_response(self, {"success": True, "id": paper_id, "status": status})

                elif path == "/api/update":
                    cfg = load_config(default_config_path())
                    papers, stats = fetch_papers(cfg, days=40)
                    if papers:
                        inserted, updated = upsert_papers(db_path, papers)
                    else:
                        inserted, updated = 0, 0
                    _json_response(self, {
                        "success": True,
                        "inserted": inserted,
                        "updated": updated,
                        "total": len(papers),
                        "range": stats.get("range", ""),
                    })

                elif path == "/api/recommend":
                    from datetime import datetime

                    cfg = load_config(default_config_path())
                    papers = get_unread_papers(db_path)
                    if not papers:
                        _json_response(self, {"success": True, "count": 0, "message": "No unread papers"})
                        return

                    results = recommend_papers(papers, cfg)
                    if not results:
                        _json_response(self, {"success": True, "count": 0, "message": "No papers selected"})
                        return

                    today = datetime.now().strftime("%Y-%m-%d")
                    picks = [{"paper_id": r.paper_id, "slot_index": r.slot_index} for r in results]
                    save_recommendation(db_path, today, picks)
                    for r in results:
                        if r.paper_id:
                            set_paper_status(db_path, r.paper_id, "read")

                    _json_response(self, {
                        "success": True,
                        "count": len(results),
                        "date": today,
                    })

                elif path.startswith("/api/paper/") and path.endswith("/translate"):
                    paper_id = urllib.parse.unquote(
                        path[len("/api/paper/"):path.rfind("/translate")]
                    )
                    # Check cache first
                    cached = get_paper_translation(db_path, paper_id)
                    if cached.get("title_zh"):
                        _json_response(self, {
                            "success": True,
                            "paper_id": paper_id,
                            **cached,
                            "source": "cache",
                        })
                        return
                    # Fetch paper and translate
                    matches = get_paper_by_id_or_title(db_path, paper_id, limit=1)
                    if not matches:
                        _json_response(self, {"error": "Paper not found"}, 404)
                        return
                    paper = matches[0]
                    from paperbot.translate import translate_paper
                    result = translate_paper(
                        title=paper.get("title", ""),
                        abstract=paper.get("abstract"),
                    )
                    set_paper_translation(
                        db_path, paper_id, result.title_zh, result.abstract_zh
                    )
                    _json_response(self, {
                        "success": True,
                        "paper_id": paper_id,
                        "title_zh": result.title_zh,
                        "abstract_zh": result.abstract_zh,
                        "source": "api",
                    })

                elif path.startswith("/api/paper/") and path.endswith("/resolve-pdf"):
                    paper_id = urllib.parse.unquote(
                        path[len("/api/paper/"):path.rfind("/resolve-pdf")]
                    )
                    # Check cache first
                    cached = get_paper_pdf(db_path, paper_id)
                    if cached:
                        _json_response(self, {
                            "success": True,
                            "paper_id": paper_id,
                            **cached,
                            "source": "cache",
                        })
                        return
                    # Fetch paper and resolve PDF
                    matches = get_paper_by_id_or_title(db_path, paper_id, limit=1)
                    if not matches:
                        _json_response(self, {"error": "Paper not found"}, 404)
                        return
                    paper = matches[0]
                    doi = paper.get("doi", "")
                    if not doi:
                        _json_response(self, {"error": "No DOI available"}, 400)
                        return
                    resolver = PdfResolver()
                    result = resolver.resolve(doi, title=paper.get("title", ""))
                    if result:
                        set_paper_pdf(db_path, paper_id, result.url, result.source)
                        _json_response(self, {
                            "success": True,
                            "paper_id": paper_id,
                            "pdf_url": result.url,
                            "pdf_source": result.source,
                        })
                    else:
                        _json_response(self, {
                            "success": True,
                            "paper_id": paper_id,
                            "pdf_url": "",
                            "pdf_source": "",
                        })

                else:
                    self.send_error(404, "Not Found")

            except Exception as e:
                _json_response(self, {"error": str(e)}, 500)

    return DashboardHandler


def _pid_file(data_dir: Path) -> Path:
    return data_dir / "dashboard.pid"


def run_server(db_path: Path, host: str = "127.0.0.1", port: int = 8000) -> None:
    """Start the dashboard HTTP server."""
    handler = make_handler(db_path)
    server = HTTPServer((host, port), handler)

    # Write PID file
    pid_path = _pid_file(db_path.parent)
    pid_path.write_text(str(os.getpid()))

    print(f"Dashboard running at http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
    finally:
        server.shutdown()
        pid_path.unlink(missing_ok=True)


def stop_server(data_dir: Path) -> bool:
    """Stop the running dashboard server."""
    pid_path = _pid_file(data_dir)
    if not pid_path.exists():
        return False
    try:
        pid = int(pid_path.read_text().strip())
        os.kill(pid, 15)  # SIGTERM
        pid_path.unlink(missing_ok=True)
        return True
    except (ValueError, ProcessLookupError, PermissionError):
        pid_path.unlink(missing_ok=True)
        return False
