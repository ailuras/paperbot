"""Tests for PDF resolver layered fallback strategy."""

from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

from paperbot.pdf_resolver import PdfResolver


def test_resolve_openalex_layer():
    """Layer 1: OpenAlex metadata returns PDF URL."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "best_oa_location": {
            "pdf_url": "https://example.com/best.pdf",
            "version": "publishedVersion",
            "license": "cc-by",
        },
    }
    mock_response.raise_for_status = MagicMock()

    resolver = PdfResolver()
    with patch.object(resolver.session, "get", return_value=mock_response):
        result = resolver.resolve("10.1000/test.123")

    assert result is not None
    assert result.url == "https://example.com/best.pdf"
    assert result.source == "openalex:best_oa_location"
    assert result.version == "publishedVersion"


def test_resolve_openalex_fallback_locations():
    """OpenAlex falls back to locations array if best_oa_location has no pdf_url."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "best_oa_location": {"url": "https://example.com/page"},
        "locations": [
            {"pdf_url": "https://example.com/loc1.pdf"},
            {"pdf_url": "https://example.com/loc2.pdf"},
        ],
    }
    mock_response.raise_for_status = MagicMock()

    resolver = PdfResolver()
    with patch.object(resolver.session, "get", return_value=mock_response):
        result = resolver.resolve("10.1000/test.123")

    assert result is not None
    assert result.url == "https://example.com/loc1.pdf"
    assert result.source == "openalex:location"


def test_resolve_openalex_oa_url_fallback():
    """OpenAlex falls back to open_access.oa_url as last resort."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "best_oa_location": None,
        "primary_location": None,
        "locations": [],
        "open_access": {"oa_url": "https://example.com/oa"},
    }
    mock_response.raise_for_status = MagicMock()

    resolver = PdfResolver()
    with patch.object(resolver.session, "get", return_value=mock_response):
        result = resolver.resolve("10.1000/test.123")

    assert result is not None
    assert result.url == "https://example.com/oa"
    assert result.source == "openalex:oa_url"


def test_resolve_unpaywall_layer():
    """Layer 2: Unpaywall returns PDF URL when OpenAlex fails."""
    # OpenAlex returns nothing
    openalex_resp = MagicMock()
    openalex_resp.json.return_value = {}
    openalex_resp.raise_for_status = MagicMock()

    # Unpaywall returns PDF
    unpaywall_resp = MagicMock()
    unpaywall_resp.json.return_value = {
        "is_oa": True,
        "best_oa_location": {
            "url_for_pdf": "https://unpaywall.org/pdf.pdf",
            "host_type": "publisher",
            "version": "publishedVersion",
        },
    }
    unpaywall_resp.raise_for_status = MagicMock()

    resolver = PdfResolver(email="test@example.com")

    def mock_get(url, **kwargs):
        if "openalex" in url:
            return openalex_resp
        if "unpaywall" in url:
            return unpaywall_resp
        return MagicMock()

    with patch.object(resolver.session, "get", side_effect=mock_get):
        result = resolver.resolve("10.1000/test.123")

    assert result is not None
    assert result.url == "https://unpaywall.org/pdf.pdf"
    assert "unpaywall" in result.source


def test_resolve_arxiv_layer():
    """Layer 3: arXiv search returns PDF URL when previous layers fail."""
    xml_content = b"""<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
            <id>http://arxiv.org/abs/2301.12345</id>
        </entry>
    </feed>"""

    openalex_resp = MagicMock()
    openalex_resp.json.return_value = {}
    openalex_resp.raise_for_status = MagicMock()

    unpaywall_resp = MagicMock()
    unpaywall_resp.json.return_value = {"is_oa": False}
    unpaywall_resp.raise_for_status = MagicMock()

    arxiv_resp = MagicMock()
    arxiv_resp.content = xml_content
    arxiv_resp.raise_for_status = MagicMock()

    resolver = PdfResolver(email="test@example.com")

    def mock_get(url, **kwargs):
        if "openalex" in url:
            return openalex_resp
        if "unpaywall" in url:
            return unpaywall_resp
        if "arxiv" in url:
            return arxiv_resp
        return MagicMock()

    with patch.object(resolver.session, "get", side_effect=mock_get):
        result = resolver.resolve("10.1000/test.123", title="Test Paper")

    assert result is not None
    assert result.url == "https://arxiv.org/pdf/2301.12345.pdf"
    assert result.source == "arxiv"


def test_resolve_no_pdf_found():
    """All layers fail — return None."""
    empty_resp = MagicMock()
    empty_resp.json.return_value = {}
    empty_resp.raise_for_status = MagicMock()

    resolver = PdfResolver()
    with patch.object(resolver.session, "get", return_value=empty_resp):
        result = resolver.resolve("10.1000/test.123")

    assert result is None


def test_resolve_unpaywall_requires_email():
    """Unpaywall layer skipped if no email provided."""
    resolver = PdfResolver(email="")
    # Should skip Unpaywall and go straight to arXiv/Semantic Scholar
    with patch.object(resolver.session, "get") as mock_get:
        mock_get.return_value = MagicMock(
            json=MagicMock(return_value={}),
            raise_for_status=MagicMock(),
        )
        resolver.resolve("10.1000/test.123")

    # Verify no Unpaywall calls were made (only OpenAlex)
    calls = [call for call in mock_get.call_args_list if "unpaywall" in str(call)]
    assert len(calls) == 0
