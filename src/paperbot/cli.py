"""CLI entry point."""

from __future__ import annotations

import typer
from rich import print

app = typer.Typer(help="PaperBot — daily paper recommendation for SMT/SAT/CP researchers")


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
def migrate() -> None:
    """Run database migrations."""
    print("[yellow]migrate not implemented yet[/yellow]")


if __name__ == "__main__":
    app()
