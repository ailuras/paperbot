"""Background scheduler for PaperBot periodic tasks."""

from __future__ import annotations

import json
import os
import signal
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

from paperbot.config import Settings, load_config
from paperbot.db import (
    get_unread_papers,
    init_db,
    save_recommendation,
    set_paper_status,
    upsert_papers,
)
from paperbot.fetch import fetch_papers
from paperbot.mail import send_fetch_report_email, send_recommendation_email
from paperbot.recommend import recommend_papers


class CronExpr:
    """Simple 5-field cron expression parser: minute hour day month dow."""

    def __init__(self, expr: str):
        parts = expr.strip().split()
        if len(parts) != 5:
            raise ValueError(f"Invalid cron expression: {expr}")
        self.minute = self._parse_field(parts[0], 0, 59)
        self.hour = self._parse_field(parts[1], 0, 23)
        self.day = self._parse_field(parts[2], 1, 31)
        self.month = self._parse_field(parts[3], 1, 12)
        self.dow = self._parse_field(parts[4], 0, 6)

    @staticmethod
    def _parse_field(field: str, min_val: int, max_val: int) -> set[int]:
        if field == "*":
            return set(range(min_val, max_val + 1))
        if "/" in field:
            base, step = field.split("/")
            if base == "*":
                start = min_val
            else:
                start = int(base)
            return set(range(start, max_val + 1, int(step)))
        if "-" in field:
            start, end = field.split("-")
            return set(range(int(start), int(end) + 1))
        if "," in field:
            return {int(x) for x in field.split(",")}
        return {int(field)}

    def match(self, dt: datetime) -> bool:
        return (
            dt.minute in self.minute
            and dt.hour in self.hour
            and dt.day in self.day
            and dt.month in self.month
            and dt.weekday() in self.dow
        )


class Scheduler:
    """Background task scheduler for PaperBot."""

    def __init__(self, settings: Settings, db_path: Path):
        self.settings = settings
        self.db_path = db_path
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._last_run: dict[str, str] = {}
        self._load_state()

    def _state_file(self) -> Path:
        return self.db_path.parent / "scheduler_state.json"

    def _load_state(self) -> None:
        path = self._state_file()
        if path.exists():
            try:
                with open(path) as f:
                    self._last_run = json.load(f)
            except Exception:
                self._last_run = {}

    def _save_state(self) -> None:
        try:
            with open(self._state_file(), "w") as f:
                json.dump(self._last_run, f)
        except Exception:
            pass

    def _run_recommend(self) -> None:
        """Run daily recommendation and send email."""
        cfg = self.settings
        db_path = self.db_path

        papers = get_unread_papers(db_path)
        if not papers:
            return

        results = recommend_papers(papers, cfg)
        if not results:
            return

        today = datetime.now().strftime("%Y-%m-%d")
        picks = [{"paper_id": r.paper_id, "slot_index": r.slot_index} for r in results]
        save_recommendation(db_path, today, picks)
        for r in results:
            if r.paper_id:
                set_paper_status(db_path, r.paper_id, "read")

        # Only send email from scheduler (not CLI/dashboard)
        send_recommendation_email(
            papers=[r.paper for r in results],
            settings=cfg,
            date_str=today,
        )

    def _run_fetch(self) -> None:
        """Run monthly fetch and send report email."""
        cfg = self.settings
        db_path = self.db_path

        papers, stats = fetch_papers(cfg, days=45)
        if papers:
            inserted, updated = upsert_papers(db_path, papers)
        else:
            inserted, updated = 0, 0

        # Only send email from scheduler
        send_fetch_report_email(
            stats=stats,
            papers_count=inserted + updated,
            settings=cfg,
            date_str=datetime.now().strftime("%Y-%m-%d"),
        )

    def _tick(self) -> None:
        now = datetime.now()
        now_key = now.strftime("%Y-%m-%d %H:%M")

        sched = self.settings.scheduler
        if not sched.enabled:
            return

        # Recommend task
        try:
            rec_cron = CronExpr(sched.recommend_cron)
            if rec_cron.match(now):
                task_key = f"recommend_{now.strftime('%Y-%m-%d')}"
                if self._last_run.get("recommend") != task_key:
                    self._run_recommend()
                    self._last_run["recommend"] = task_key
                    self._save_state()
        except Exception:
            pass

        # Fetch task
        try:
            fetch_cron = CronExpr(sched.fetch_cron)
            if fetch_cron.match(now):
                task_key = f"fetch_{now.strftime('%Y-%m-%d')}"
                if self._last_run.get("fetch") != task_key:
                    self._run_fetch()
                    self._last_run["fetch"] = task_key
                    self._save_state()
        except Exception:
            pass

    def start(self) -> None:
        """Start scheduler in background thread."""
        if self._thread is not None and self._thread.is_alive():
            return

        self._stop.clear()

        def _loop():
            while not self._stop.is_set():
                self._tick()
                # Sleep until next minute boundary
                now = datetime.now()
                sleep_sec = 60 - now.second - now.microsecond / 1e6
                if self._stop.wait(timeout=sleep_sec):
                    break

        self._thread = threading.Thread(target=_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        """Stop the scheduler."""
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)
            self._thread = None

    def is_running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()


def run_scheduler_daemon(
    config_path: Path,
    db_path: Path,
    pid_path: Path,
) -> None:
    """Run scheduler as a daemon process."""
    # Write PID file
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.write_text(str(os.getpid()))

    # Setup signal handlers
    def _signal_handler(signum, _frame):
        pid_path.unlink(missing_ok=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    cfg = load_config(config_path)
    init_db(db_path)

    scheduler = Scheduler(cfg, db_path)
    scheduler.start()

    # Keep main thread alive
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        pass
    finally:
        scheduler.stop()
        pid_path.unlink(missing_ok=True)
