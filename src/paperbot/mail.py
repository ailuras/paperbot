"""Email notification module for PaperBot recommendations."""

from __future__ import annotations

import os
import shutil
import smtplib
import subprocess
from html import escape
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any
from urllib.parse import urlparse

from paperbot.config import Settings
from paperbot.models import Paper
from paperbot.utils import format_date


def _smtp_config(settings: Settings) -> dict[str, Any]:
    """Build SMTP configuration from settings and environment."""
    mail_cfg = getattr(settings, "mail", None)
    if mail_cfg is None:
        return {}

    def _env_or_config(env_name: str, value: Any) -> Any:
        return os.getenv(env_name) or value

    def _env_int_or_config(env_name: str, value: int) -> int:
        raw = os.getenv(env_name)
        if raw:
            try:
                return int(raw)
            except ValueError:
                return value
        return value

    return {
        "host": _env_or_config("SMTP_HOST", getattr(mail_cfg, "smtp_host", "")),
        "port": _env_int_or_config("SMTP_PORT", getattr(mail_cfg, "smtp_port", 587)),
        "user": _env_or_config("SMTP_USER", getattr(mail_cfg, "smtp_user", "")),
        "password": _env_or_config("SMTP_PASSWORD", getattr(mail_cfg, "smtp_password", "")),
        "from_addr": _env_or_config("SMTP_FROM", getattr(mail_cfg, "from_addr", "")),
        "from_name": getattr(mail_cfg, "from_name", "PaperBot"),
        "to_addrs": getattr(mail_cfg, "to_addrs", []),
        "use_tls": getattr(mail_cfg, "use_tls", True),
        "dashboard_url": getattr(mail_cfg, "dashboard_url", "http://localhost:8765"),
    }


def _has_local_sendmail() -> str | None:
    """Check if a local sendmail-compatible binary is available."""
    for candidate in ("/usr/sbin/sendmail", "/usr/lib/sendmail"):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    # Also check for ssmtp/msmtp wrappers
    for cmd in ("sendmail", "ssmtp", "msmtp"):
        path = shutil.which(cmd)
        if path:
            return path
    return None


def _format_from_header(from_addr: str, from_name: str) -> str:
    return f"{from_name} <{from_addr}>" if from_name else from_addr


def _html(value: Any) -> str:
    return escape("" if value is None else str(value), quote=True)


def _safe_http_url(value: str) -> str:
    value = value or ""
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return ""
    return _html(value)


def _paper_link(paper: Paper) -> str:
    for candidate in (paper.landing_page_url, paper.doi or "", paper.id):
        url = _safe_http_url(candidate)
        if url:
            return url
    return ""


def _send_via_local(
    to_addrs: list[str],
    subject: str,
    from_addr: str,
    from_name: str,
    body: str,
) -> bool:
    """Send email using local sendmail binary."""
    sendmail_path = _has_local_sendmail()
    if not sendmail_path:
        return False

    # Build raw email with headers
    display_from = _format_from_header(from_addr, from_name)
    headers = (
        f"From: {display_from}\r\n"
        f"To: {', '.join(to_addrs)}\r\n"
        f"Subject: {subject}\r\n"
        f"Content-Type: text/html; charset=utf-8\r\n"
        f"MIME-Version: 1.0\r\n"
        f"\r\n"
    )
    raw = headers + body

    try:
        proc = subprocess.run(
            [sendmail_path, "-t"],
            input=raw.encode("utf-8"),
            capture_output=True,
            timeout=30,
        )
        return proc.returncode == 0
    except Exception:
        return False


def _send_via_smtp(
    to_addrs: list[str],
    subject: str,
    from_addr: str,
    from_name: str,
    body: str,
    cfg: dict[str, Any],
) -> bool:
    """Send email using SMTP."""
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = _format_from_header(from_addr, from_name)
    msg["To"] = ", ".join(to_addrs)
    msg.attach(MIMEText(body, "html", "utf-8"))

    try:
        with smtplib.SMTP(cfg["host"], cfg["port"], timeout=30) as server:
            server.set_debuglevel(0)
            if cfg.get("use_tls", True):
                server.starttls()
            if cfg.get("user") and cfg.get("password"):
                server.login(cfg["user"], cfg["password"])
            server.sendmail(from_addr, to_addrs, msg.as_string())
        return True
    except smtplib.SMTPAuthenticationError as e:
        print(f"[SMTP Auth Error] {e.smtp_code}: {e.smtp_error}")
        return False
    except smtplib.SMTPException as e:
        print(f"[SMTP Error] {e}")
        return False
    except Exception as e:
        print(f"[Email Error] {type(e).__name__}: {e}")
        return False


def _paper_to_html(paper: Paper, index: int, translation: dict[str, str] | None = None) -> str:
    """Convert a Paper to HTML snippet."""
    author_str = _html(paper.author_str)

    venue = _html(paper.venue or "OpenAlex")
    url = _paper_link(paper)
    abstract = _html(paper.abstract)
    score = paper.score
    cited = paper.cited_by_count
    track = paper.track
    tier = paper.tier
    pub_date = _html(paper.year_or_date)

    tier_badge = f"<span style='background:#b45309;color:#fef3c7;padding:2px 6px;border-radius:4px;font-size:12px;'>T{tier}</span>" if tier else ""

    # Dynamic track color based on track name hash
    track_badge = ""
    if track:
        _h = hash(track) % 360
        track_bg = f"hsl({_h}, 55%, 35%)"
        track_fg = f"hsl({_h}, 70%, 90%)"
        track_badge = f"<span style='background:{track_bg};color:{track_fg};padding:2px 6px;border-radius:4px;font-size:12px;margin-left:4px;'>{_html(track)}</span>"

    trans_html = ""
    if translation and translation.get("title_zh"):
        trans_html += f'<div style="color:#b45309;font-size:15px;font-weight:600;margin:4px 0 8px 0;">{_html(translation["title_zh"])}</div>'
    if translation and translation.get("abstract_zh"):
        trans_html += f'<div style="color:#78716c;font-size:13px;line-height:1.6;margin-bottom:8px;border-left:3px solid #d6d3d1;padding-left:10px;">{_html(translation["abstract_zh"])}</div>'

    return f"""
    <div style="border-left:4px solid #2563eb;padding-left:16px;margin-bottom:24px;">
      <h3 style="margin:0 0 8px 0;color:#1e293b;">#{index} {_html(paper.title or 'No Title')}</h3>
      {trans_html}
      <div style="margin-bottom:8px;">
        {tier_badge}{track_badge}
        <span style="color:#64748b;font-size:14px;margin-left:8px;">{venue} · {pub_date} · Cited {cited} · Score {score:.1f}</span>
      </div>
      <div style="color:#475569;font-size:14px;margin-bottom:8px;"><strong>Authors:</strong> {author_str}</div>
      {f'<div style="color:#475569;font-size:14px;line-height:1.6;"><strong>Abstract:</strong> {abstract}</div>' if abstract else ''}
      {f'<div style="margin-top:8px;"><a href="{url}" style="color:#2563eb;text-decoration:none;">Read Paper →</a></div>' if url else ''}
    </div>
    """


def _build_email_body(
    papers: list[Paper],
    title: str,
    date_str: str,
    stats: dict[str, Any] | None = None,
    dashboard_url: str = "http://localhost:8765",
    translations: dict[str, dict[str, str]] | None = None,
) -> str:
    """Build full HTML email body."""
    translations = translations or {}
    papers_html = "\n".join(
        _paper_to_html(p, i + 1, translations.get(p.id))
        for i, p in enumerate(papers)
    )

    safe_dashboard_url = _safe_http_url(dashboard_url)
    stats_html = ""
    if stats:
        stats_html = f"""
        <div style="background:#f8fafc;border-radius:8px;padding:12px 16px;margin-bottom:24px;">
          <span style="color:#64748b;font-size:14px;">
            Total: {stats.get('total_papers', 0)} · Pending: {stats.get('pending', 0)} · Read: {stats.get('read', 0)} · Starred: {stats.get('starred', 0)}
          </span>
        </div>
        """

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #334155; max-width: 720px; margin: 0 auto; padding: 24px; }}
  h2 {{ color: #1e293b; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px; }}
</style>
</head>
<body>
  <h2>{_html(title)} · {_html(date_str)}</h2>
  {stats_html}
  {papers_html}
  <hr style="border:none;border-top:1px solid #e2e8f0;margin:24px 0;">
  <p style="color:#94a3b8;font-size:12px;text-align:center;">
    PaperBot — daily paper recommendation for SMT/SAT/CP researchers<br>
    {f'<a href="{safe_dashboard_url}" style="color:#64748b;">Open Dashboard</a>' if safe_dashboard_url else 'Open Dashboard'}
  </p>
</body>
</html>"""


def _send_email(
    to_addrs: list[str],
    subject: str,
    body: str,
    cfg: dict[str, Any],
) -> bool:
    """Send email using SMTP if configured, fallback to local sendmail."""
    from_addr = cfg.get("from_addr", "")
    from_name = cfg.get("from_name", "PaperBot")

    if not from_addr:
        return False
    if not to_addrs:
        return False

    # Prefer SMTP if configured (can send to external addresses)
    if cfg.get("host"):
        return _send_via_smtp(to_addrs, subject, from_addr, from_name, body, cfg)

    # Fallback to local sendmail (usually local-only delivery)
    if _has_local_sendmail():
        return _send_via_local(to_addrs, subject, from_addr, from_name, body)

    return False


def send_recommendation_email(
    papers: list[Paper],
    settings: Settings,
    date_str: str | None = None,
    stats: dict[str, Any] | None = None,
    translations: dict[str, dict[str, str]] | None = None,
) -> bool:
    """Send daily recommendation email.

    Returns True if email was sent successfully, False otherwise.
    Uses local sendmail if available, otherwise falls back to SMTP.
    """
    cfg = _smtp_config(settings)

    date_str = date_str or format_date()

    html_body = _build_email_body(
        papers, "Daily Recommendations", date_str, stats,
        dashboard_url=cfg.get("dashboard_url", "http://localhost:8765"),
        translations=translations,
    )
    return _send_email(
        cfg.get("to_addrs", []),
        f"PaperBot Daily · {date_str}",
        html_body,
        cfg,
    )

