"""CLI entry point."""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from paperbot.audit import AuditEntry, AuditStatus, format_audit_status, get_audit_logs, get_audit_stats, init_audit, log_audit, log_to_file
from paperbot.config import load_default_config
from paperbot.dashboard import run_server as run_dashboard, stop_server
from paperbot.db import (
    get_paper_by_id_or_title,
    get_recent_reads,
    get_stats,
    get_unread_papers,
    init_db,
    save_recommendation,
    set_paper_status,
    upsert_papers,
)
from paperbot.fetch import fetch_papers
from paperbot.mail import send_fetch_report_email, send_recommendation_email
from paperbot.models import Paper, PaperStatus
from paperbot.recommend import recommend_papers
from paperbot.translate import translate_paper_cached
from paperbot.utils import _abbr, format_date

app = typer.Typer(help="PaperBot — daily paper recommendation for SMT/SAT/CP researchers")
console = Console()


def _db_path() -> Path:
    cfg = load_default_config()
    db_path = cfg.data_dir / "paperbot.db"
    init_db(db_path)
    init_audit(db_path)
    return db_path


def _log_audit(db_path: Path, data_dir: Path, entry: AuditEntry, start_time: float) -> None:
    """Helper to write audit entry with duration."""
    entry.duration_ms = int((time.time() - start_time) * 1000)
    try:
        log_audit(db_path, entry)
        log_to_file(data_dir, entry)
    except Exception as exc:
        logging.getLogger(__name__).warning("Audit logging failed: %s", exc)


def _handle_email_result(sent: bool, audit_entry: AuditEntry, success_msg: str) -> None:
    """Update audit entry and console output after sending an email."""
    if sent:
        console.print(f"[green]{success_msg}[/green]")
    else:
        console.print("[yellow]Email not sent (check mail config).[/yellow]")
        audit_entry.status = AuditStatus.ERROR
        audit_entry.error_message = "email_failed"


@app.command()
def recommend(
    count: int = typer.Option(3, help="Number of papers to recommend"),
    json_output: bool = typer.Option(False, "--json", help="Output NDJSON"),
    dry_run: bool = typer.Option(False, help="Preview without saving"),
    email: bool = typer.Option(False, "--email", help="Send result via email (used by crontab)"),
    translate: bool = typer.Option(False, "--translate", help="Translate title and abstract (overrides config)"),
) -> None:
    """Generate today's paper recommendations."""
    start_time = time.time()
    cfg = load_default_config()
    db_path = _db_path()
    data_dir = cfg.data_dir
    audit_entry = AuditEntry(action="recommend")

    # Determine if translation is enabled
    do_translate = translate or cfg.translate.enabled

    # Fetch candidate pool
    papers = get_unread_papers(db_path)
    if not papers:
        console.print("[yellow]No unread papers available.[/yellow]")
        audit_entry.status = AuditStatus.SKIPPED
        audit_entry.details = {"reason": "no_unread_papers", "pending": 0}
        _log_audit(db_path, data_dir, audit_entry, start_time)
        raise typer.Exit(0)

    # Run recommendation engine
    results = recommend_papers(papers, cfg, count=count)
    if not results:
        console.print("[yellow]Could not select any papers.[/yellow]")
        audit_entry.status = AuditStatus.SKIPPED
        audit_entry.details = {"reason": "no_selection", "pending": len(papers)}
        _log_audit(db_path, data_dir, audit_entry, start_time)
        raise typer.Exit(0)

    today = format_date()

    # Translate if enabled
    translations: dict[str, dict[str, str]] = {}
    if do_translate:
        console.print("[blue]Translating recommendations...[/blue]")
        for r in results:
            pid = r.paper_id
            if not pid:
                continue
            try:
                trans = translate_paper_cached(db_path, r.paper)
                translations[pid] = {
                    "title_zh": trans["title_zh"],
                    "abstract_zh": trans["abstract_zh"],
                }
            except Exception as e:
                console.print(f"[dim]Translation failed for {pid}: {e}[/dim]")

    if json_output:
        for r in results:
            out = {
                "date": today,
                "slot": r.slot_index,
                "reason": r.reason,
                "paper": r.paper.to_dict(),
            }
            if r.paper_id in translations:
                out["translation"] = translations[r.paper_id]
            console.print(json.dumps(out, ensure_ascii=False))
    else:
        console.print(f"Daily Papers · {today}")
        for r in results:
            p = r.paper
            abbr = _abbr(p.venue or "OpenAlex")
            url = p.url
            trans = translations.get(r.paper_id, {})

            console.print("=====")
            if trans.get("title_zh"):
                console.print(f"[{abbr}] {p.title}")
                console.print(f"[cyan]翻译: {trans['title_zh']}[/cyan]")
            else:
                console.print(f"[{abbr}] {p.title}")
            if url:
                console.print(f"Link: {url}")
            console.print("-----")
            console.print(f"Authors: {p.author_str}")
            console.print("-----")
            console.print(f"Abstract: {p.abstract}")
            if trans.get("abstract_zh"):
                console.print(f"[cyan]摘要翻译: {trans['abstract_zh']}[/cyan]")

        console.print("=====")
        console.print(f"Pending: {len(papers)} | Selected: {len(results)}")

    if not dry_run:
        picks = [{"paper_id": r.paper_id, "slot_index": r.slot_index} for r in results]
        save_recommendation(db_path, today, picks)
        for r in results:
            if r.paper_id:
                set_paper_status(db_path, r.paper_id, "read")
        console.print(f"[green]Saved {len(results)} recommendations.[/green]")

        if email:
            # Include translations in email if configured
            email_papers = [r.paper for r in results]
            include_trans = do_translate and cfg.translate.include_in_email
            sent = send_recommendation_email(
                papers=email_papers,
                settings=cfg,
                date_str=today,
                translations=translations if include_trans else None,
            )
            audit_entry.details = {
                "date": today,
                "selected": len(results),
                "pending": len(papers),
                "email": email,
                "email_sent": sent,
                "translated": do_translate,
            }
            _handle_email_result(sent, audit_entry, "Email sent.")
        else:
            audit_entry.details = {
                "date": today,
                "selected": len(results),
                "pending": len(papers),
                "email": False,
                "translated": do_translate,
            }

        _log_audit(db_path, data_dir, audit_entry, start_time)
    else:
        console.print("[yellow]Dry run — not saved.[/yellow]")
        audit_entry.status = AuditStatus.SKIPPED
        audit_entry.details = {"reason": "dry_run", "pending": len(papers), "translated": do_translate}
        _log_audit(db_path, data_dir, audit_entry, start_time)


@app.command()
def fetch(
    days: int = typer.Option(45, help="How many days back to fetch"),
    dry_run: bool = typer.Option(False, help="Preview without saving"),
    email: bool = typer.Option(False, "--email", help="Send report via email (used by crontab)"),
) -> None:
    """Fetch papers from OpenAlex."""
    start_time = time.time()
    cfg = load_default_config()
    db_path = _db_path()
    data_dir = cfg.data_dir
    audit_entry = AuditEntry(action="fetch")

    console.print("[blue]Fetching from OpenAlex...[/blue]")
    papers, stats = fetch_papers(cfg, days=days)

    hl = "━" * 16
    console.print()
    console.print(hl)
    console.print(f"[bold]Fetch Report · {format_date()}[/bold]")
    console.print(hl)
    console.print(f"Range: {stats['range']} ({stats['days']} days)")
    console.print()
    console.print("[bold]By Track:[/bold]")
    for ts in stats["track_stats"]:
        console.print(f"  {ts['track']:<4}  raw {ts['raw']:>4}  →  kept {ts['filtered']:>4}")
    console.print()
    console.print(f"Total raw: {stats['total_raw']} | Filtered: {stats['total_filtered']}")

    if dry_run:
        console.print()
        console.print("[yellow]Dry run — not saved.[/yellow]")
        audit_entry.status = AuditStatus.SKIPPED
        audit_entry.details = {"reason": "dry_run", **stats}
        _log_audit(db_path, data_dir, audit_entry, start_time)
        raise typer.Exit(0)

    if not papers:
        console.print("[yellow]No papers to save.[/yellow]")
        audit_entry.status = AuditStatus.SKIPPED
        audit_entry.details = {"reason": "no_papers", **stats}
        _log_audit(db_path, data_dir, audit_entry, start_time)
        raise typer.Exit(0)

    inserted, updated = upsert_papers(db_path, papers)
    console.print()
    console.print(f"[green]Inserted: {inserted} | Updated: {updated}[/green]")

    audit_entry.details = {
        "inserted": inserted,
        "updated": updated,
        **stats,
    }

    if email:
        sent = send_fetch_report_email(
            stats=stats,
            papers_count=inserted + updated,
            settings=cfg,
            date_str=format_date(),
        )
        audit_entry.details["email"] = email
        audit_entry.details["email_sent"] = sent
        _handle_email_result(sent, audit_entry, "Email report sent.")
    else:
        audit_entry.details["email"] = False

    _log_audit(db_path, data_dir, audit_entry, start_time)


@app.command()
def init(
    days: int = typer.Option(365, help="How many days back to fetch"),
    dry_run: bool = typer.Option(False, help="Preview without saving"),
) -> None:
    """Initialize the database by fetching papers from the last year."""
    cfg = load_default_config()
    db_path = _db_path()

    console.print("[blue]Initializing database — fetching from OpenAlex...[/blue]")
    papers, stats = fetch_papers(cfg, days=days)

    hl = "━" * 16
    console.print()
    console.print(hl)
    console.print(f"[bold]Fetch Report · {format_date()}[/bold]")
    console.print(hl)
    console.print(f"Range: {stats['range']} ({stats['days']} days)")
    console.print()
    console.print("[bold]By Track:[/bold]")
    for ts in stats["track_stats"]:
        console.print(f"  {ts['track']:<4}  raw {ts['raw']:>4}  →  kept {ts['filtered']:>4}")
    console.print()
    console.print(f"Total raw: {stats['total_raw']} | Filtered: {stats['total_filtered']}")

    if dry_run:
        console.print()
        console.print("[yellow]Dry run — not saved.[/yellow]")
        raise typer.Exit(0)

    if not papers:
        console.print("[yellow]No papers to save.[/yellow]")
        raise typer.Exit(0)

    inserted, updated = upsert_papers(db_path, papers)
    console.print()
    console.print(f"[green]Inserted: {inserted} | Updated: {updated}[/green]")

    total = get_stats(db_path).get("total_papers", 0)
    console.print()
    console.print(f"[bold green]Init complete: {total} papers in database.[/bold green]")


@app.command()
def mark(
    paper_query: str = typer.Argument(help="Paper OpenAlex ID or title substring"),
    status: str = typer.Option(..., "--status", help="Status: read|starred|skip"),
) -> None:
    """Mark a paper with a status."""
    if status not in PaperStatus.ALL:
        console.print(f"[red]Invalid status '{status}'. Must be one of: {', '.join(sorted(PaperStatus.ALL))}[/red]")
        raise typer.Exit(1)

    db_path = _db_path()
    matches = get_paper_by_id_or_title(db_path, paper_query)

    if not matches:
        console.print(f"[red]No paper found matching '{paper_query}'.[/red]")
        raise typer.Exit(1)

    if len(matches) > 1:
        console.print(f"[yellow]Multiple matches found for '{paper_query}':[/yellow]")
        table = Table("#", "ID", "Title", "Track", "Score")
        for i, p in enumerate(matches, 1):
            pid = p.id
            title = p.title
            table.add_row(
                str(i),
                pid[:40] + "..." if len(pid) > 40 else pid,
                title[:50] + "..." if len(title) > 50 else title,
                p.track or "?",
                str(p.score),
            )
        console.print(table)
        console.print("[dim]Please use the exact paper ID.[/dim]")
        raise typer.Exit(1)

    paper = matches[0]
    paper_id = paper.id
    set_paper_status(db_path, paper_id, status)
    console.print(f"[green]Marked '{paper.title or paper_id}' as {status}.[/green]")


@app.command()
def stats() -> None:
    """Show statistics about the paper database."""
    db_path = _db_path()
    data = get_stats(db_path)

    sep = "-" * 10
    console.print(f"{sep} PaperBot Stats {sep}")
    console.print(f"Total Papers: {data.get('total_papers', 0)}")

    if data.get("by_track"):
        tracks = ", ".join(f"{t}={c}" for t, c in sorted(data["by_track"].items()))
        console.print(f"Tracks: {tracks}")

    states = " | ".join(f"{k.capitalize()}: {data.get(k, 0)}" for k in ["pending", "read", "starred", "skipped"])
    console.print(f"States: {states}")


@app.command()
def history(
    limit: int = typer.Option(10, help="Number of recent reads to show"),
) -> None:
    """Show recent read papers."""
    db_path = _db_path()
    rows = get_recent_reads(db_path, limit=limit)

    if not rows:
        console.print("[yellow]No recent reads.[/yellow]")
        raise typer.Exit(0)

    console.print("Recent Reads")

    for i, p in enumerate(rows, 1):
        abbr = _abbr(p.venue or "OpenAlex")
        url = p.url
        abstract = p.abstract
        mark_time = p.changed_at

        console.print("=====")
        console.print(f"[{abbr}] {p.title or 'No Title'}")
        if url:
            console.print(f"Link: {url}")
        console.print("-----")
        console.print(f"Authors: {p.author_str}")
        if mark_time:
            console.print(f"Marked: {mark_time}")
        console.print("-----")
        console.print(f"Abstract: {abstract}")

    console.print("=====")


@app.command()
def serve(
    host: str = typer.Option("127.0.0.1", help="Bind address"),
    port: int = typer.Option(8765, help="Port"),
    daemon: bool = typer.Option(False, help="Run in background (detach from terminal)"),
    log_file: str = typer.Option("", help="Log file path (default: ~/.paperbot/dashboard.log)"),
    stop: bool = typer.Option(False, help="Stop the running dashboard server"),
) -> None:
    """Start or stop the local web dashboard."""
    import os
    import sys

    cfg = load_default_config()
    db_path = cfg.data_dir / "paperbot.db"

    if stop:
        stopped = stop_server(cfg.data_dir, port=port)
        if stopped:
            console.print("[green]Dashboard stopped.[/green]")
        else:
            console.print("[yellow]Dashboard is not running.[/yellow]")
        raise typer.Exit(0)

    init_db(db_path)

    log_path = Path(log_file).expanduser() if log_file else cfg.data_dir / "dashboard.log"

    if daemon:
        # First fork
        pid = os.fork()
        if pid > 0:
            console.print(f"[green]Dashboard running in background (pid {pid}).[/green]")
            console.print(f"[dim]Log: {log_path}[/dim]")
            raise typer.Exit(0)

        os.setsid()

        # Second fork
        pid = os.fork()
        if pid > 0:
            sys.exit(0)

        # Redirect stdout/stderr to log file
        sys.stdout.flush()
        sys.stderr.flush()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a+") as f:
            os.dup2(f.fileno(), sys.stdout.fileno())
            os.dup2(f.fileno(), sys.stderr.fileno())

    run_dashboard(db_path=db_path, host=host, port=port)


@app.command()
def audit(
    action: str = typer.Option("", help="Filter by action type (recommend/fetch/mark)"),
    limit: int = typer.Option(20, help="Number of entries to show"),
    stats_only: bool = typer.Option(False, "--stats", help="Show summary statistics only"),
    days: int = typer.Option(7, help="Number of days to look back for stats"),
) -> None:
    """View audit log of system operations."""
    db_path = _db_path()

    if stats_only:
        data = get_audit_stats(db_path, days=days)
        console.print(f"[bold]Audit Stats (last {days} days)[/bold]")
        console.print(f"Total entries: {data['total']}")
        if data.get("by_action"):
            console.print("\n[bold]By Action:[/bold]")
            for action_name, statuses in sorted(data["by_action"].items()):
                status_str = " | ".join(f"{s}={c}" for s, c in sorted(statuses.items()))
                console.print(f"  {action_name}: {status_str}")
        return

    logs = get_audit_logs(db_path, action=action or None, limit=limit)
    if not logs:
        console.print("[yellow]No audit entries found.[/yellow]")
        return

    console.print(f"[bold]Audit Log (last {len(logs)} entries)[/bold]\n")
    for entry in logs:
        ts = entry.get("timestamp", "")
        status = entry.get("status", "")
        action_name = entry.get("action", "")
        duration = entry.get("duration_ms", 0)
        error = entry.get("error_message", "")

        icon, color = format_audit_status(status)

        line = f"[{ts}] {icon} [bold {color}]{action_name}[/bold {color}] ({duration}ms)"
        if error:
            line += f" — [red]{error}[/red]"
        console.print(line)

        details = entry.get("details", {})
        if isinstance(details, dict) and details:
            detail_str = " | ".join(f"{k}={v}" for k, v in details.items() if v is not None)
            if detail_str:
                console.print(f"  [dim]{detail_str}[/dim]")


if __name__ == "__main__":
    app()
