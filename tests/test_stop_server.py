"""Tests for dashboard stop_server fallback logic."""

from __future__ import annotations

import os
from pathlib import Path
from unittest.mock import MagicMock, patch

from paperbot.dashboard import _kill_by_port, stop_server


def test_stop_server_via_pid_file(tmp_path: Path):
    """stop_server kills the process when PID file exists and is valid."""
    pid_path = tmp_path / "dashboard.pid"
    pid_path.write_text(str(os.getpid()))

    with patch("paperbot.dashboard._pid_file", return_value=pid_path):
        with patch("os.kill") as mock_kill:
            result = stop_server(tmp_path, port=9999)

    assert result is True
    mock_kill.assert_called_once_with(os.getpid(), 15)
    assert not pid_path.exists()


def test_stop_server_stale_pid_file(tmp_path: Path):
    """stop_server cleans up stale PID file and falls back to port."""
    pid_path = tmp_path / "dashboard.pid"
    pid_path.write_text("99999999")

    with patch("paperbot.dashboard._pid_file", return_value=pid_path):
        with patch("paperbot.dashboard._kill_by_port", return_value=True) as mock_kill_port:
            result = stop_server(tmp_path, port=8888)

    assert result is True
    mock_kill_port.assert_called_once_with(8888)
    assert not pid_path.exists()


def test_stop_server_no_pid_file_fallback_success(tmp_path: Path):
    """stop_server falls back to port-based kill when PID file is missing."""
    with patch("paperbot.dashboard._pid_file", return_value=tmp_path / "nonexistent.pid"):
        with patch("paperbot.dashboard._kill_by_port", return_value=True) as mock_kill_port:
            result = stop_server(tmp_path, port=7777)

    assert result is True
    mock_kill_port.assert_called_once_with(7777)


def test_stop_server_no_pid_file_fallback_failure(tmp_path: Path):
    """stop_server returns False when both PID file and port fallback fail."""
    with patch("paperbot.dashboard._pid_file", return_value=tmp_path / "nonexistent.pid"):
        with patch("paperbot.dashboard._kill_by_port", return_value=False) as mock_kill_port:
            result = stop_server(tmp_path, port=6666)

    assert result is False
    mock_kill_port.assert_called_once_with(6666)


def test_kill_by_port_lsof_success():
    """_kill_by_port uses lsof when available."""
    mock_result = MagicMock()
    mock_result.returncode = 0
    mock_result.stdout = "12345\n"

    with patch("subprocess.run", return_value=mock_result) as mock_run:
        with patch("os.kill") as mock_kill:
            result = _kill_by_port(8765)

    assert result is True
    mock_run.assert_called_once_with(
        ["lsof", "-ti", ":8765"],
        capture_output=True, text=True, timeout=2,
    )
    mock_kill.assert_called_once_with(12345, 15)


def test_kill_by_port_no_lsof():
    """_kill_by_port returns False when lsof is not available."""
    with patch("subprocess.run", side_effect=FileNotFoundError):
        result = _kill_by_port(8765)

    assert result is False


def test_kill_by_port_nothing_found():
    """_kill_by_port returns False when no tools find a process."""
    with patch("subprocess.run", side_effect=FileNotFoundError):
        result = _kill_by_port(8765)

    assert result is False
