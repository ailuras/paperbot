"""Tests for shared utility helpers."""

from __future__ import annotations

from datetime import datetime

from paperbot.audit import AuditStatus, format_audit_status
from paperbot.utils import _abbr, format_date


def test_format_date_default():
    """format_date returns today's date by default."""
    result = format_date()
    assert result == datetime.now().strftime("%Y-%m-%d")


def test_format_date_with_argument():
    """format_date formats a given datetime."""
    dt = datetime(2024, 3, 15, 10, 30, 0)
    assert format_date(dt) == "2024-03-15"


def test_abbr_finds_acronym():
    """_abbr extracts an uppercase acronym."""
    assert _abbr("Proceedings of CAV 2023") == "CAV"
    assert _abbr("IEEE S&P") == "IEEE"


def test_abbr_fallback():
    """_abbr returns short prefix when no acronym found."""
    assert _abbr("Journal of Logic") == "Journal of"
    assert _abbr("") == "?"


def test_format_audit_status_success():
    """format_audit_status maps success correctly."""
    icon, color = format_audit_status(AuditStatus.SUCCESS)
    assert icon == "✓"
    assert color == "green"


def test_format_audit_status_skipped():
    """format_audit_status maps skipped correctly."""
    icon, color = format_audit_status(AuditStatus.SKIPPED)
    assert icon == "→"
    assert color == "yellow"


def test_format_audit_status_error():
    """format_audit_status maps error and unknown correctly."""
    icon, color = format_audit_status(AuditStatus.ERROR)
    assert icon == "✗"
    assert color == "red"

    icon2, color2 = format_audit_status("unknown")
    assert icon2 == "✗"
    assert color2 == "red"
