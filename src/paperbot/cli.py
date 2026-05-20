"""CLI entry point."""

from __future__ import annotations

import json
from pathlib import Path

import typer
from rich import print
from rich.console import Console
from rich.table import Table

from paperbot.config import default_config_path, load_config
from paperbot.db import get_stats, init_db, set_paper_status, upsert_papers

app = typer.Typer(help="PaperBot — daily paper recommendation for SMT/SAT/CP researchers")
console = Console()


@app.command()
def recommend() -> None:
    """Generate today's paper recommendations."""
    print("[yellow]recommend not implemented yet[/yellow]")


@app.command()
def fetch(
    days: int = typer.Option(45, help="How many days back to fetch"),
    dry_run: bool = typer.Option(False, help="Preview without saving"),
) -> None:
    """Fetch papers from OpenAlex."""
    print("[yellow]fetch not implemented yet[/yellow]")


@app.command()
def mark(
    paper_id: str = typer.Argument(help="Paper OpenAlex ID or title"),
    status: str = typer.Argument(help="Status: read|skip|later"),
) -> None:
    """Mark a paper with a status."""
    print("[yellow]mark not implemented yet[/yellow]")


@app.command()
def stats() -> None:
    """Show statistics about the paper database."""
    print("[yellow]stats not implemented yet[/yellow]")


@app.command()
def history() -> None:
    """Show recommendation history."""
    print("[yellow]history not implemented yet[/yellow]")


@app.command()
def serve(
    host: str = typer.Option("127.0.0.1", help="Bind address"),
    port: int = typer.Option(8000, help="Port"),
) -> None:
    """Start the local web dashboard."""
    print("[yellow]serve not implemented yet[/yellow]")


@app.command()
def migrate(
    source: str = typer.Option(
        "/Users/macbookpro/Documents/06-文献/papers.json",
        help="Path to the JSON file containing papers",
    ),
    config_path: str | None = typer.Option(
        None,
        "--config",
        help="Path to config file (defaults to data/config.json)",
    ),
) -> None:
    """Migrate papers from JSON into the SQLite database."""
    cfg = load_config(config_path or default_config_path())
    db_path = cfg.data_dir / "paperbot.db"

    print(f"[blue]Database:[/blue] {db_path}")
    print(f"[blue]Source:[/blue]   {source}")

    init_db(db_path)

    source_path = Path(source).expanduser()
    with source_path.open(encoding="utf-8") as f:
        papers: list[dict] = json.load(f)

    if not papers:
        print("[red]No papers found in source file.[/red]")
        raise typer.Exit(1)

    inserted, updated = upsert_papers(db_path, papers)

    recommended_count = 0
    for paper in papers:
        if paper.get("recommended_at") or paper.get("status") == "recommended":
            set_paper_status(db_path, paper["id"], "recommended")
            recommended_count += 1

    # Summary
    print(f"\n[green]Migration complete.[/green]")
    print(f"  Total papers: {len(papers)}")
    print(f"  Inserted:     {inserted}")
    print(f"  Updated:      {updated}")
    print(f"  Recommended:  {recommended_count}")

    # Track breakdown
    from collections import Counter

    track_counts = Counter(str(p.get("track", "unknown")) for p in papers)
    print("\n[bold]By track:[/bold]")
    for track, count in sorted(track_counts.items()):
        print(f"  {track}: {count}")


if __name__ == "__main__":
    app()
