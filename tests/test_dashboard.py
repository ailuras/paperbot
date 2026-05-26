"""Tests for the dashboard HTTP handler."""

from __future__ import annotations

import json
from pathlib import Path

from paperbot.dashboard import make_handler
from paperbot.db import upsert_papers


def _make_handler(db_path: Path):
    """Helper to create handler class for testing."""
    handler_cls = make_handler(db_path)
    return handler_cls


def _request(handler_cls, method: str, path: str, body: bytes | None = None) -> tuple[int, dict | str]:
    """Simulate an HTTP request and return (status, body)."""
    from io import BytesIO

    # Build request bytes
    request_line = f"{method} {path} HTTP/1.1\r\n"
    headers = "Host: localhost\r\n"
    if body:
        headers += f"Content-Length: {len(body)}\r\n"
    headers += "\r\n"
    raw = (request_line + headers).encode("utf-8")
    if body:
        raw += body

    class MockSocket:
        pass

    # Create handler without running the full __init__ handle() loop
    handler = handler_cls.__new__(handler_cls)
    handler.request = MockSocket()
    handler.client_address = ("127.0.0.1", 8765)
    handler.server = None
    handler.rfile = BytesIO(raw)
    handler.wfile = BytesIO()
    handler.raw_requestline = b""
    handler.error_code = None
    handler.error_message = None

    # Parse request line
    handler.raw_requestline = handler.rfile.readline(65537)
    if not handler.raw_requestline:
        return 400, ""

    if not handler.parse_request():
        return handler.error_code or 400, ""

    # Route to handler method
    do_method = getattr(handler, f"do_{handler.command}", None)
    if do_method is None:
        handler.send_error(405)
    else:
        try:
            do_method()
        except Exception:
            handler.send_error(500)

    handler.wfile.flush()

    # Parse response
    wfile = handler.wfile
    wfile.seek(0)
    response = wfile.read().decode("utf-8")
    lines = response.split("\r\n")
    status_code = int(lines[0].split()[1])

    blank_idx = next(i for i, line in enumerate(lines) if line == "")
    body_str = "\r\n".join(lines[blank_idx + 1 :])

    try:
        data = json.loads(body_str) if body_str else {}
    except json.JSONDecodeError:
        data = body_str

    return status_code, data


def test_dashboard_index(tmp_db_path: Path):
    """GET / returns the HTML dashboard."""
    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/")
    assert status == 200
    assert "PaperBot Dashboard" in str(data)


def test_api_stats(tmp_db_path: Path):
    """GET /api/stats returns statistics."""
    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/api/stats")
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("total_papers") == 0


def test_api_papers_empty(tmp_db_path: Path):
    """GET /api/papers returns empty list."""
    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/api/papers")
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("total") == 0
    assert data.get("papers") == []


def test_api_papers_with_data(tmp_db_path: Path, sample_papers):
    """GET /api/papers returns inserted papers."""
    upsert_papers(tmp_db_path, sample_papers)
    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/api/papers")
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("total") == 3
    assert len(data.get("papers", [])) == 3


def test_api_mark_paper(tmp_db_path: Path, sample_paper):
    """POST /api/mark updates paper status."""
    upsert_papers(tmp_db_path, [sample_paper])
    handler_cls = _make_handler(tmp_db_path)
    body = json.dumps({"id": sample_paper.id, "status": "read"}).encode("utf-8")
    status, data = _request(handler_cls, "POST", "/api/mark", body)
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("success") is True

    # Verify via stats
    _, stats = _request(handler_cls, "GET", "/api/stats")
    assert isinstance(stats, dict)
    assert stats.get("read") == 1
    assert stats.get("pending") == 0


def test_api_paper_detail(tmp_db_path: Path, sample_paper):
    """GET /api/paper/:id returns paper details."""
    upsert_papers(tmp_db_path, [sample_paper])
    handler_cls = _make_handler(tmp_db_path)
    encoded_id = sample_paper.id.replace("https://", "https%3A%2F%2F")
    status, data = _request(handler_cls, "GET", f"/api/paper/{encoded_id}")
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("title") == sample_paper.title


def test_api_paper_note(tmp_db_path: Path, sample_paper):
    """GET/POST /api/paper/:id/note works."""
    upsert_papers(tmp_db_path, [sample_paper])
    handler_cls = _make_handler(tmp_db_path)
    encoded_id = sample_paper.id.replace("https://", "https%3A%2F%2F")

    # GET empty note
    status, data = _request(handler_cls, "GET", f"/api/paper/{encoded_id}/note")
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("note") == ""

    # POST note
    body = json.dumps({"note": "Test note"}).encode("utf-8")
    status, data = _request(handler_cls, "POST", f"/api/paper/{encoded_id}/note", body)
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("success") is True

    # GET updated note
    status, data = _request(handler_cls, "GET", f"/api/paper/{encoded_id}/note")
    assert status == 200
    assert isinstance(data, dict)
    assert data.get("note") == "Test note"


def test_api_404(tmp_db_path: Path):
    """Unknown routes return 404."""
    handler_cls = _make_handler(tmp_db_path)
    status, _ = _request(handler_cls, "GET", "/api/unknown")
    assert status == 404


def test_api_paper_translation_get(tmp_db_path: Path, sample_paper):
    """GET /api/paper/:id/translation returns cached translation."""
    from paperbot.db import set_paper_translation, upsert_papers

    upsert_papers(tmp_db_path, [sample_paper])
    set_paper_translation(tmp_db_path, sample_paper.id, "测试标题", "测试摘要")

    handler_cls = _make_handler(tmp_db_path)
    encoded_id = sample_paper.id.replace("https://", "https%3A%2F%2F")
    status, data = _request(handler_cls, "GET", f"/api/paper/{encoded_id}/translation")

    assert status == 200
    assert isinstance(data, dict)
    assert data.get("title_zh") == "测试标题"
    assert data.get("abstract_zh") == "测试摘要"


def test_api_paper_translation_post_cached(tmp_db_path: Path, sample_paper):
    """POST /api/paper/:id/translate returns cache if available."""
    from paperbot.db import set_paper_translation, upsert_papers

    upsert_papers(tmp_db_path, [sample_paper])
    set_paper_translation(tmp_db_path, sample_paper.id, "缓存标题", "缓存摘要")

    handler_cls = _make_handler(tmp_db_path)
    encoded_id = sample_paper.id.replace("https://", "https%3A%2F%2F")
    status, data = _request(handler_cls, "POST", f"/api/paper/{encoded_id}/translate")

    assert status == 200
    assert data.get("title_zh") == "缓存标题"
    assert data.get("source") == "cache"


def test_api_paper_pdf_get(tmp_db_path: Path, sample_paper):
    """GET /api/paper/:id/pdf returns cached PDF URL."""
    from paperbot.db import set_paper_pdf, upsert_papers

    upsert_papers(tmp_db_path, [sample_paper])
    set_paper_pdf(tmp_db_path, sample_paper.id, "https://example.com/paper.pdf", "openalex")

    handler_cls = _make_handler(tmp_db_path)
    encoded_id = sample_paper.id.replace("https://", "https%3A%2F%2F")
    status, data = _request(handler_cls, "GET", f"/api/paper/{encoded_id}/pdf")

    assert status == 200
    assert isinstance(data, dict)
    assert data.get("pdf_url") == "https://example.com/paper.pdf"
    assert data.get("pdf_source") == "openalex"


def test_api_paper_pdf_get_empty(tmp_db_path: Path, sample_paper):
    """GET /api/paper/:id/pdf returns empty when no cache."""
    from paperbot.db import upsert_papers

    upsert_papers(tmp_db_path, [sample_paper])

    handler_cls = _make_handler(tmp_db_path)
    encoded_id = sample_paper.id.replace("https://", "https%3A%2F%2F")
    status, data = _request(handler_cls, "GET", f"/api/paper/{encoded_id}/pdf")

    assert status == 200
    assert data.get("pdf_url") == ""
    assert data.get("pdf_source") == ""


def test_api_paper_translate_missing_paper(tmp_db_path: Path):
    """POST translate returns 404 for non-existent paper."""
    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "POST", "/api/paper/nonexistent/translate")

    assert status == 404
    assert "error" in data


def test_api_paper_pdf_missing_paper(tmp_db_path: Path):
    """POST resolve-pdf returns 404 for non-existent paper."""
    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "POST", "/api/paper/nonexistent/resolve-pdf")

    assert status == 404
    assert "error" in data


def test_api_paper_pdf_no_doi(tmp_db_path: Path, sample_paper):
    """POST resolve-pdf returns 400 if paper has no DOI."""
    from paperbot.db import upsert_papers
    from paperbot.models import Paper

    paper_no_doi = Paper(**{**sample_paper.to_dict(), "doi": None})
    upsert_papers(tmp_db_path, [paper_no_doi])

    handler_cls = _make_handler(tmp_db_path)
    encoded_id = sample_paper.id.replace("https://", "https%3A%2F%2F")
    status, data = _request(handler_cls, "POST", f"/api/paper/{encoded_id}/resolve-pdf")

    assert status == 400
    assert "error" in data


def test_api_config(tmp_db_path: Path):
    """GET /api/config returns track configuration."""
    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/api/config")
    assert status == 200
    assert isinstance(data, dict)
    assert "tracks" in data
    assert "dashboard_url" in data


def test_api_audit_logs(tmp_db_path: Path):
    """GET /api/audit returns audit log entries."""
    from paperbot.audit import init_audit, log_audit, AuditEntry

    init_audit(tmp_db_path)
    log_audit(tmp_db_path, AuditEntry(action="fetch", status="success"))

    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/api/audit")
    assert status == 200
    assert isinstance(data, list)
    assert len(data) == 1
    assert data[0]["action"] == "fetch"


def test_api_audit_stats(tmp_db_path: Path):
    """GET /api/audit/stats returns aggregated stats."""
    from paperbot.audit import init_audit, log_audit, AuditEntry

    init_audit(tmp_db_path)
    log_audit(tmp_db_path, AuditEntry(action="fetch", status="success"))

    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/api/audit/stats")
    assert status == 200
    assert isinstance(data, dict)
    assert data["total"] == 1


def test_api_recent_reads(tmp_db_path: Path, sample_papers):
    """GET /api/recent-reads returns recently read papers."""
    from paperbot.db import upsert_papers, set_paper_status

    upsert_papers(tmp_db_path, sample_papers)
    set_paper_status(tmp_db_path, sample_papers[0].id, "read")

    handler_cls = _make_handler(tmp_db_path)
    status, data = _request(handler_cls, "GET", "/api/recent-reads")
    assert status == 200
    assert isinstance(data, list)
    assert len(data) == 1
    assert data[0]["title"] == sample_papers[0].title
