"""Email notification module for PaperBot recommendations."""

from __future__ import annotations

import os
import shutil
import smtplib
import subprocess
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from typing import Any

from paperbot.config import Settings
from paperbot.utils import format_authors


def _smtp_config(settings: Settings) -> dict[str, Any]:
    """Build SMTP configuration from settings and environment."""
    mail_cfg = getattr(settings, "mail", None)
    if mail_cfg is None:
        return {}

    return {
        "host": getattr(mail_cfg, "smtp_host", os.getenv("SMTP_HOST", "")),
        "port": getattr(mail_cfg, "smtp_port", int(os.getenv("SMTP_PORT", "587"))),
        "user": getattr(mail_cfg, "smtp_user", os.getenv("SMTP_USER", "")),
        "password": getattr(mail_cfg, "smtp_password", os.getenv("SMTP_PASSWORD", "")),
        "from_addr": getattr(mail_cfg, "from_addr", os.getenv("SMTP_FROM", "")),
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
    display_from = f"{from_name} <{from_addr}>" if from_name else from_addr
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
    msg["From"] = f"{from_name} <{from_addr}>" if from_name else from_addr
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


def _paper_to_html(paper: dict[str, Any], index: int, translation: dict[str, str] | None = None) -> str:
    """Convert a paper dict to HTML snippet."""
    author_str = format_authors(paper)

    venue = paper.get("venue") or "OpenAlex"
    url = paper.get("landing_page_url") or paper.get("doi") or paper.get("id") or ""
    abstract = paper.get("abstract", "")
    score = paper.get("score", 0)
    cited = paper.get("cited_by_count", 0)
    track = paper.get("track", "")
    tier = paper.get("tier", 0)
    pub_date = paper.get("publication_date") or paper.get("publication_year") or "?"

    tier_badge = f"<span style='background:#b45309;color:#fef3c7;padding:2px 6px;border-radius:4px;font-size:12px;'>T{tier}</span>" if tier else ""

    # Dynamic track color based on track name hash
    track_badge = ""
    if track:
        _h = hash(track) % 360
        track_bg = f"hsl({_h}, 55%, 35%)"
        track_fg = f"hsl({_h}, 70%, 90%)"
        track_badge = f"<span style='background:{track_bg};color:{track_fg};padding:2px 6px;border-radius:4px;font-size:12px;margin-left:4px;'>{track}</span>"

    trans_html = ""
    if translation and translation.get("title_zh"):
        trans_html += f'<div style="color:#b45309;font-size:15px;font-weight:600;margin:4px 0 8px 0;">{translation["title_zh"]}</div>'
    if translation and translation.get("abstract_zh"):
        trans_html += f'<div style="color:#78716c;font-size:13px;line-height:1.6;margin-bottom:8px;border-left:3px solid #d6d3d1;padding-left:10px;">{translation["abstract_zh"]}</div>'

    return f"""
    <div style="border-left:4px solid #2563eb;padding-left:16px;margin-bottom:24px;">
      <h3 style="margin:0 0 8px 0;color:#1e293b;">#{index} {paper.get('title', 'No Title')}</h3>
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
    papers: list[dict[str, Any]],
    title: str,
    date_str: str,
    stats: dict[str, Any] | None = None,
    dashboard_url: str = "http://localhost:8765",
    translations: dict[str, dict[str, str]] | None = None,
) -> str:
    """Build full HTML email body."""
    translations = translations or {}
    papers_html = "\n".join(
        _paper_to_html(p, i + 1, translations.get(p.get("id", "")))
        for i, p in enumerate(papers)
    )

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
  <h2>{title} · {date_str}</h2>
  {stats_html}
  {papers_html}
  <hr style="border:none;border-top:1px solid #e2e8f0;margin:24px 0;">
  <p style="color:#94a3b8;font-size:12px;text-align:center;">
    PaperBot — daily paper recommendation for SMT/SAT/CP researchers<br>
    <a href="{dashboard_url}" style="color:#64748b;">Open Dashboard</a>
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
    papers: list[dict[str, Any]],
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

    if date_str is None:
        from paperbot.utils import format_date

        date_str = format_date()

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


def send_fetch_report_email(
    stats: dict[str, Any],
    papers_count: int,
    settings: Settings,
    date_str: str | None = None,
) -> bool:
    """Send fetch report email after updating paper database.

    Returns True if email was sent successfully, False otherwise.
    """
    cfg = _smtp_config(settings)

    if date_str is None:
        from paperbot.utils import format_date

        date_str = format_date()

    track_rows = "\n".join(
        f"<tr><td style='padding:6px 12px;border-bottom:1px solid #e2e8f0;'>{ts['track']}</td><td style='padding:6px 12px;border-bottom:1px solid #e2e8f0;text-align:right;'>{ts['raw']}</td><td style='padding:6px 12px;border-bottom:1px solid #e2e8f0;text-align:right;'>{ts['filtered']}</td></tr>"
        for ts in stats.get("track_stats", [])
    )

    html_body = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;line-height:1.6;color:#334155;max-width:600px;margin:0 auto;padding:24px;">
  <h2 style="color:#1e293b;border-bottom:2px solid #e2e8f0;padding-bottom:8px;">Fetch Report · {date_str}</h2>

  <div style="background:#f8fafc;border-radius:8px;padding:16px;margin-bottom:20px;">
    <p style="margin:0;color:#64748b;"><strong>Range:</strong> {stats.get('range', '')}</p>
    <p style="margin:8px 0 0 0;color:#64748b;"><strong>Days:</strong> {stats.get('days', 0)}</p>
  </div>

  <table style="width:100%;border-collapse:collapse;margin-bottom:20px;font-size:14px;">
    <thead><tr style="background:#f1f5f9;">
      <th style="padding:8px 12px;text-align:left;">Track</th>
      <th style="padding:8px 12px;text-align:right;">Raw</th>
      <th style="padding:8px 12px;text-align:right;">Filtered</th>
    </tr></thead>
    <tbody>{track_rows}</tbody>
  </table>

  <div style="background:#ecfdf5;border-radius:8px;padding:16px;">
    <p style="margin:0;color:#059669;font-weight:600;">
      Total Raw: {stats.get('total_raw', 0)} | Filtered: {stats.get('total_filtered', 0)} | Saved: {papers_count}
    </p>
  </div>

  <hr style="border:none;border-top:1px solid #e2e8f0;margin:24px 0;">
  <p style="color:#94a3b8;font-size:12px;text-align:center;">
    PaperBot — daily paper recommendation for SMT/SAT/CP researchers<br>
    <a href="{cfg.get('dashboard_url', 'http://localhost:8765')}" style="color:#64748b;">Open Dashboard</a>
  </p>
</body>
</html>"""

    return _send_email(
        cfg.get("to_addrs", []),
        f"PaperBot Fetch · {date_str}",
        html_body,
        cfg,
    )
