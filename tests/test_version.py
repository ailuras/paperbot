"""Tests for package metadata."""

from __future__ import annotations

from importlib.metadata import version

import paperbot


def test_package_version_matches_installed_metadata():
    """The public package version stays in sync with pyproject metadata."""
    assert paperbot.__version__ == version("paperbot")
