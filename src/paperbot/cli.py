"""CLI entry point."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

import typer
from rich import box
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from paperbot.config import default_config_path, load_config
from paperbot.dashboard import run_server as run_dashboard
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
from paperbot.recommend import recommend_papers

app = typer.Typer(help="PaperBot — daily paper recommendation for SMT/SAT/CP researchers")
console = Console()


def _db_path() -> Path:
    cfg = load_config(default_config_path())
    db_path = cfg.data_dir / "paperbot.db"
    init_db(db_path)
    return db_path


@app.command()
def recommend(
    count: int = typer.Option(3, help="Number of papers to recommend"),
    json_output: bool = typer.Option(False, "--json", help="Output NDJSON"),
    dry_run: bool = typer.Option(False, help="Preview without saving"),
) -> None:
    """Generate today's paper recommendations."""
    cfg = load_config(default_config_path())
    db_path = _db_path()

    # Fetch candidate pool
    papers = get_unread_papers(db_path)
    if not papers:
        console.print("[yellow]No unread papers available.[/yellow]")
        raise typer.Exit(0)

    # Run recommendation engine
    results = recommend_papers(papers, cfg, count=count)
    if not results:
        console.print("[yellow]Could not select any papers.[/yellow]")
        raise typer.Exit(0)

    today = datetime.now().strftime("%Y-%m-%d")

    if json_output:
        for r in results:
            console.print(json.dumps({
                "date": today,
                "slot": r.slot_index,
                "reason": r.reason,
                "paper": r.paper,
            }, ensure_ascii=False))
    else:
        console.print()
        console.print(Text("━" * 20, style="bold cyan"))
        console.print(Text(f"Daily Papers · {today}", style="bold cyan"))
        console.print(Text("━" * 20, style="bold cyan"))

        for r in results:
            p = r.paper
            authors = p.get("authors", [])
            if isinstance(authors, str):
                try:
                    authors = json.loads(authors)
                except json.JSONDecodeError:
                    authors = [authors]
            author_str = ", ".join(authors[:5])
            if len(authors) > 5:
                author_str += ", et al."

            venue = p.get("venue") or "OpenAlex"
            year = p.get("publication_year") or "?"
            citations = p.get("cited_by_count", 0) or 0
            score = p.get("score", 0) or 0
            tier = p.get("tier", 0) or 0
            track = p.get("track") or "?"

            meta_parts = [f"{venue} {year}", f"Cited {citations}", f"Score {score:.1f}"]
            if tier:
                meta_parts.append(f"Tier {tier}")
            meta_line = "  ·  ".join(meta_parts)

            panel_content = f"[bold]{p.get('title', 'No Title')}[/bold]\n"
            panel_content += f"[dim]{author_str}[/dim]\n"
            panel_content += f"[blue]{meta_line}[/blue]"
            if p.get("abstract"):
                abstract = p["abstract"]
                if len(abstract) > 400:
                    abstract = abstract[:400] + "..."
                panel_content += f"\n\n{abstract}"
            if p.get("landing_page_url"):
                panel_content += f"\n\n[link={p['landing_page_url']}]🔗 {p['landing_page_url']}[/link]"

            console.print()
            console.print(Panel(
                panel_content,
                title=f"[yellow]#{r.slot_index + 1}[/yellow]  {r.reason}  [{track}]",
                border_style="green",
                box=box.ROUNDED,
            ))

        pending = sum(1 for p in papers if True)
        console.print()
        console.print(f"[dim]Pending: {pending} | Selected: {len(results)}[/dim]")

    if not dry_run:
        picks = [
            {
                "paper_id": r.paper_id,
                "slot_index": r.slot_index,
            }
            for r in results
        ]
        save_recommendation(db_path, today, picks)
        for r in results:
            if r.paper_id:
                set_paper_status(db_path, r.paper_id, "read")
        console.print(f"[green]Saved {len(results)} recommendations.[/green]")
    else:
        console.print("[yellow]Dry run — not saved.[/yellow]")


@app.command()
def fetch(
    days: int = typer.Option(45, help="How many days back to fetch"),
    dry_run: bool = typer.Option(False, help="Preview without saving"),
) -> None:
    """Fetch papers from OpenAlex."""
    cfg = load_config(default_config_path())
    db_path = _db_path()

    console.print(f"[blue]Fetching from OpenAlex...[/blue]")
    papers, stats = fetch_papers(cfg, days=days)

    hl = "━" * 16
    console.print()
    console.print(hl)
    console.print(f"[bold]Fetch Report · {datetime.now().strftime('%Y-%m-%d')}[/bold]")
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


@app.command()
def mark(
    paper_query: str = typer.Argument(help="Paper OpenAlex ID or title substring"),
    status: str = typer.Option(..., "--status", help="Status: read|starred|skip"),
) -> None:
    """Mark a paper with a status."""
    valid_statuses = {"read", "starred", "skip", "pending"}
    if status not in valid_statuses:
        console.print(f"[red]Invalid status '{status}'. Must be one of: {', '.join(sorted(valid_statuses))}[/red]")
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
            table.add_row(
                str(i),
                p.get("id", "")[:40] + "..." if len(p.get("id", "")) > 40 else p.get("id", ""),
                p.get("title", "")[:50] + "..." if len(p.get("title", "")) > 50 else p.get("title", ""),
                p.get("track", "?"),
                str(p.get("score", 0)),
            )
        console.print(table)
        console.print("[dim]Please use the exact paper ID.[/dim]")
        raise typer.Exit(1)

    paper = matches[0]
    paper_id = paper["id"]
    set_paper_status(db_path, paper_id, status)
    console.print(f"[green]Marked '{paper.get('title', paper_id)}' as {status}.[/green]")


@app.command()
def stats() -> None:
    """Show statistics about the paper database."""
    db_path = _db_path()
    data = get_stats(db_path)

    console.print()
    console.print(Text("━" * 20, style="bold cyan"))
    console.print(Text("PaperBot Stats", style="bold cyan"))
    console.print(Text("━" * 20, style="bold cyan"))
    console.print()

    table = Table(show_header=False, box=None)
    table.add_column("Key", style="bold")
    table.add_column("Value")
    table.add_row("Total Papers", str(data.get("total_papers", 0)))
    console.print(table)
    console.print()

    if data.get("by_track"):
        console.print("[bold]By Track:[/bold]")
        track_table = Table("Track", "Count", box=None)
        for track, count in sorted(data["by_track"].items()):
            track_table.add_row(track, str(count))
        console.print(track_table)
        console.print()

    console.print("[bold]States:[/bold]")
    state_table = Table("Status", "Count", box=None)
    for label, key in [("Pending", "pending"), ("Read", "read"), ("Starred", "starred"), ("Skipped", "skipped")]:
        state_table.add_row(label, str(data.get(key, 0)))
    console.print(state_table)


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

    console.print()
    console.print(Text("━" * 20, style="bold cyan"))
    console.print(Text("Recent Reads", style="bold cyan"))
    console.print(Text("━" * 20, style="bold cyan"))

    for i, p in enumerate(rows, 1):
        authors = p.get("authors", [])
        if isinstance(authors, str):
            try:
                authors = json.loads(authors)
            except json.JSONDecodeError:
                authors = [authors]
        author_str = ", ".join(authors[:3])
        if len(authors) > 3:
            author_str += ", et al."

        date_str = p.get("publication_date") or p.get("publication_year") or "?"
        venue = p.get("venue") or "Unknown"
        track = p.get("track") or "?"
        score = p.get("score", 0) or 0
        tier = p.get("tier", "") or ""

        tier_tag = f" [T{tier}]" if tier else ""
        meta = f"{date_str} · {venue} · Cited {p.get('cited_by_count', 0)} · Score {score:.1f}{tier_tag} · [{track}]"

        console.print()
        console.print(f"[bold]#{i}[/bold] {p.get('title', 'No Title')}")
        console.print(f"[dim]{author_str}[/dim]")
        console.print(f"[blue]{meta}[/blue]")

        abstract = p.get("abstract", "")
        if abstract:
            if len(abstract) > 400:
                abstract = abstract[:400] + "..."
            console.print(f"\n{abstract}")

        url = p.get("landing_page_url") or p.get("doi") or ""
        if url:
            console.print(f"\n[link={url}]🔗 {url}[/link]")


@app.command()
def serve(
    host: str = typer.Option("127.0.0.1", help="Bind address"),
    port: int = typer.Option(8765, help="Port"),
    daemon: bool = typer.Option(False, help="Run in background (detach from terminal)"),
    log_file: str = typer.Option("", help="Log file path (default: ~/.paperbot/dashboard.log)"),
) -> None:
    """Start the local web dashboard."""
    cfg = load_config(default_config_path())
    db_path = cfg.data_dir / "paperbot.db"
    init_db(db_path)

    log_path = Path(log_file).expanduser() if log_file else cfg.data_dir / "dashboard.log"

    if daemon:
        import os
        import sys

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


if __name__ == "__main__":
    app()
