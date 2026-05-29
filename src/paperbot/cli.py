"""CLI entry point."""

from __future__ import annotations

import json
import logging
import os
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
from paperbot.models import PaperStatus
from paperbot.recommend import recommend_papers
from paperbot.translate import translate_paper_cached
from paperbot.update import refresh_existing_papers, reset_paper_states
from paperbot.utils import _abbr, format_date

app = typer.Typer(help="PaperBot — daily paper recommendation for SMT/SAT/CP researchers")
papers_app = typer.Typer(help="Manage paper records.")
dashboard_app = typer.Typer(help="Manage the local dashboard.")
logs_app = typer.Typer(help="View operation logs.", invoke_without_command=True)
console = Console()

app.add_typer(papers_app, name="papers")
app.add_typer(dashboard_app, name="dashboard")
app.add_typer(logs_app, name="logs")


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


_HISTORY_LABELS = {
    PaperStatus.RECOMMENDED: (
        "Recent Recommendations",
        "No recent recommendations.",
        "Recommended",
    ),
    PaperStatus.READ: ("Recent Reads", "No recent reads.", "Read"),
    PaperStatus.STARRED: ("Recent Starred Papers", "No recent starred papers.", "Marked"),
    PaperStatus.SKIP: ("Recent Skipped Papers", "No recent skipped papers.", "Marked"),
    PaperStatus.PENDING: ("Recent Pending Papers", "No recent pending papers.", "Marked"),
}


def _print_fetch_report(stats: dict[str, object]) -> None:
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
                set_paper_status(db_path, r.paper_id, PaperStatus.RECOMMENDED)
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
def update(
    fetch_source: bool = typer.Option(
        False,
        "--fetch",
        help="Fetch from OpenAlex before refreshing local metadata",
    ),
    reset_status: bool = typer.Option(
        False,
        "--reset-status",
        help="Reset all paper states to pending after updating",
    ),
    days: int = typer.Option(
        45,
        "--days",
        help="How many days back to fetch when --fetch is used",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Preview without saving",
    ),
    email: bool = typer.Option(
        False,
        "--email",
        help="Send fetch report via email when --fetch is used",
    ),
) -> None:
    """Update stored papers without generating recommendations."""
    start_time = time.time()
    cfg = load_default_config()
    db_path = _db_path()
    data_dir = cfg.data_dir
    audit_entry = AuditEntry(action="update")
    details: dict[str, object] = {
        "fetch": fetch_source,
        "reset_status": reset_status,
        "dry_run": dry_run,
    }

    if fetch_source:
        console.print("[blue]Fetching from OpenAlex...[/blue]")
        papers, stats = fetch_papers(cfg, days=days)
        _print_fetch_report(stats)
        if dry_run:
            inserted, updated = (0, 0)
            console.print()
            console.print("[yellow]Dry run — fetched source data but did not save it.[/yellow]")
        else:
            inserted, updated = upsert_papers(db_path, papers) if papers else (0, 0)
            console.print()
            console.print(f"[green]Source refresh: inserted {inserted} | updated {updated}[/green]")
        details.update(
            {
                "inserted": inserted,
                "source_updated": updated,
                **stats,
            }
        )

        if email and not dry_run:
            sent = send_fetch_report_email(
                stats=stats,
                papers_count=inserted + updated,
                settings=cfg,
                date_str=format_date(),
            )
            details["email"] = email
            details["email_sent"] = sent
            _handle_email_result(sent, audit_entry, "Email report sent.")
        elif email:
            console.print("[yellow]Email not sent during dry run.[/yellow]")
            details["email"] = False
    elif email:
        console.print("[yellow]Email report is only sent when --fetch is used.[/yellow]")
        details["email"] = False

    refresh = refresh_existing_papers(db_path, cfg, dry_run=dry_run)
    action_label = "would update" if dry_run else "updated"
    console.print(
        "[green]Local refresh: "
        f"checked {refresh['total']} | {action_label} {refresh['updated']}[/green]"
    )
    details.update(
        {
            "local_total": refresh["total"],
            "local_updated": refresh["updated"],
        }
    )

    if reset_status:
        reset_count = reset_paper_states(db_path, dry_run=dry_run)
        if dry_run:
            console.print(f"[yellow]Reset preview: {reset_count} papers would be marked pending.[/yellow]")
        else:
            console.print(f"[yellow]Reset states: {reset_count} papers marked pending.[/yellow]")
        details["reset_count"] = reset_count

    if dry_run:
        console.print("[yellow]Dry run — local changes not saved.[/yellow]")
        audit_entry.status = AuditStatus.SKIPPED

    audit_entry.details = details
    _log_audit(db_path, data_dir, audit_entry, start_time)


@papers_app.command("mark")
def mark(
    paper_query: str = typer.Argument(help="Paper OpenAlex ID or title substring"),
    status: str = typer.Option(..., "--status", help="Status: pending|recommended|read|starred|skip"),
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


@papers_app.command("stats")
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

    states = " | ".join(
        f"{label}: {data.get(key, 0)}"
        for key, label in [
            ("pending", "Pending"),
            ("recommended", "Recommended"),
            ("read", "Read"),
            ("starred", "Starred"),
            ("skipped", "Skipped"),
        ]
    )
    console.print(f"States: {states}")


@papers_app.command("history")
def history(
    limit: int = typer.Option(10, help="Number of recent papers to show"),
    status: str = typer.Option(
        "read",
        help="Filter by status: recommended / read / starred / skip / pending",
    ),
) -> None:
    """Show recent papers by status."""
    if status not in PaperStatus.ALL:
        allowed = ", ".join(sorted(PaperStatus.ALL))
        console.print(f"[red]Invalid status '{status}'. Must be one of: {allowed}[/red]")
        raise typer.Exit(1)

    db_path = _db_path()
    rows = get_recent_reads(db_path, limit=limit, status=status)
    title, empty_message, time_label = _HISTORY_LABELS[status]

    if not rows:
        console.print(f"[yellow]{empty_message}[/yellow]")
        raise typer.Exit(0)

    console.print(title)

    for p in rows:
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
            console.print(f"{time_label}: {mark_time}")
        console.print("-----")
        console.print(f"Abstract: {abstract}")

    console.print("=====")


def _start_dashboard(
    host: str,
    port: int,
    daemon: bool,
    log_file: str,
) -> None:
    import sys

    cfg = load_default_config()
    db_path = cfg.data_dir / "paperbot.db"

    init_db(db_path)
    init_audit(db_path)

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


@dashboard_app.command("start")
def dashboard_start(
    host: str = typer.Option("127.0.0.1", help="Bind address"),
    port: int = typer.Option(8765, help="Port"),
    daemon: bool = typer.Option(False, help="Run in background (detach from terminal)"),
    log_file: str = typer.Option("", help="Log file path (default: data dir dashboard.log)"),
) -> None:
    """Start the local web dashboard."""
    _start_dashboard(host=host, port=port, daemon=daemon, log_file=log_file)


@dashboard_app.command("stop")
def dashboard_stop(
    port: int = typer.Option(8765, help="Port"),
) -> None:
    """Stop the local web dashboard."""
    cfg = load_default_config()
    if stop_server(cfg.data_dir, port=port):
        console.print("[green]Dashboard stopped.[/green]")
    else:
        console.print("[yellow]Dashboard is not running.[/yellow]")


@dashboard_app.command("restart")
def dashboard_restart(
    host: str = typer.Option("127.0.0.1", help="Bind address"),
    port: int = typer.Option(8765, help="Port"),
    daemon: bool = typer.Option(False, help="Run in background (detach from terminal)"),
    log_file: str = typer.Option("", help="Log file path (default: data dir dashboard.log)"),
) -> None:
    """Restart the local web dashboard."""
    cfg = load_default_config()
    if stop_server(cfg.data_dir, port=port):
        console.print("[green]Dashboard stopped.[/green]")
    console.print("[dim]Restarting...[/dim]")
    _start_dashboard(host=host, port=port, daemon=daemon, log_file=log_file)


@dashboard_app.command("status")
def status() -> None:
    """Show PaperBot dashboard status."""
    cfg = load_default_config()
    pid_path = cfg.data_dir / "dashboard.pid"
    running = False
    if pid_path.exists():
        try:
            pid = int(pid_path.read_text().strip())
            os.kill(pid, 0)
            running = True
        except (ValueError, ProcessLookupError, PermissionError):
            pass

    if running:
        console.print("[green]PaperBot: RUNNING[/green]")
    else:
        console.print("[yellow]PaperBot: STOPPED[/yellow]")


def _show_log_entries(
    db_path: Path,
    action: str,
    limit: int,
) -> None:
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


def _show_log_stats(db_path: Path, days: int) -> None:
    data = get_audit_stats(db_path, days=days)
    console.print(f"[bold]Audit Stats (last {days} days)[/bold]")
    console.print(f"Total entries: {data['total']}")
    if data.get("by_action"):
        console.print("\n[bold]By Action:[/bold]")
        for action_name, statuses in sorted(data["by_action"].items()):
            status_str = " | ".join(f"{s}={c}" for s, c in sorted(statuses.items()))
            console.print(f"  {action_name}: {status_str}")


@logs_app.callback(invoke_without_command=True)
def logs(
    ctx: typer.Context,
    action: str = typer.Option("", help="Filter by action type (recommend/update/fetch/mark/translate/resolve_pdf/note)"),
    limit: int = typer.Option(20, help="Number of entries to show"),
) -> None:
    """View operation log entries."""
    if ctx.invoked_subcommand is not None:
        return
    _show_log_entries(_db_path(), action=action, limit=limit)


@logs_app.command("stats")
def logs_stats(
    days: int = typer.Option(7, help="Number of days to look back"),
) -> None:
    """Show operation log statistics."""
    _show_log_stats(_db_path(), days=days)


if __name__ == "__main__":
    app()
