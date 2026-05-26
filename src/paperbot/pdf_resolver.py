"""PDF resolver — find open-access PDF URLs for papers."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from paperbot.models import Paper

import requests

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PdfSource:
    url: str
    source: str  # e.g. "openalex", "unpaywall", "arxiv"
    version: str | None = None
    license: str | None = None


class PdfResolver:
    """Resolve PDF URLs via multiple open-access sources."""

    def __init__(self, email: str = "", semantic_scholar_key: str = "") -> None:
        self.email = email
        self.s2_key = semantic_scholar_key
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": f"PaperBot/1.0 (mailto:{email})" if email else "PaperBot/1.0",
        })

    def __enter__(self) -> PdfResolver:
        return self

    def __exit__(self, *_args: Any) -> None:
        self.session.close()

    # ── Layer 1: OpenAlex metadata (free) ─────────────────────────────

    def _from_openalex(self, doi: str) -> PdfSource | None:
        """Extract PDF URL from OpenAlex work metadata."""
        url = f"https://api.openalex.org/works/doi:{doi}"
        try:
            resp = self.session.get(url, timeout=15)
            resp.raise_for_status()
            data = resp.json()

            for loc_key in ("best_oa_location", "primary_location"):
                loc = data.get(loc_key)
                if loc and loc.get("pdf_url"):
                    return PdfSource(
                        url=loc["pdf_url"],
                        source=f"openalex:{loc_key}",
                        version=loc.get("version"),
                        license=loc.get("license"),
                    )

            for loc in data.get("locations", []):
                if loc.get("pdf_url"):
                    return PdfSource(
                        url=loc["pdf_url"],
                        source="openalex:location",
                        version=loc.get("version"),
                        license=loc.get("license"),
                    )

            oa_url = data.get("open_access", {}).get("oa_url")
            if oa_url:
                return PdfSource(url=oa_url, source="openalex:oa_url")

        except Exception:
            logger.debug("OpenAlex PDF lookup failed for %s", doi, exc_info=True)
        return None

    # ── Layer 2: Unpaywall ────────────────────────────────────────────

    def _from_unpaywall(self, doi: str) -> PdfSource | None:
        """Query Unpaywall API for OA PDF."""
        if not self.email:
            return None
        url = f"https://api.unpaywall.org/v2/{doi}"
        try:
            resp = self.session.get(url, params={"email": self.email}, timeout=15)
            resp.raise_for_status()
            data = resp.json()

            if not data.get("is_oa"):
                return None

            best = data.get("best_oa_location", {})
            pdf_url = best.get("url_for_pdf") or best.get("url")
            if pdf_url:
                return PdfSource(
                    url=pdf_url,
                    source=f"unpaywall:{best.get('host_type', 'unknown')}",
                    version=best.get("version"),
                    license=best.get("license"),
                )
        except Exception:
            logger.debug("Unpaywall PDF lookup failed for %s", doi, exc_info=True)
        return None

    # ── Layer 3: arXiv (by title search) ──────────────────────────────

    def _from_arxiv(self, title: str) -> PdfSource | None:
        """Search arXiv by title and return PDF URL."""
        if not title:
            return None
        search_url = "http://export.arxiv.org/api/query"
        params = {
            "search_query": f'ti:"{title}"',
            "max_results": 3,
            "sortBy": "relevance",
        }
        try:
            resp = self.session.get(search_url, params=params, timeout=15)
            resp.raise_for_status()

            import xml.etree.ElementTree as ET
            root = ET.fromstring(resp.content)
            ns = {"atom": "http://www.w3.org/2005/Atom"}

            for entry in root.findall("atom:entry", ns):
                id_elem = entry.find("atom:id", ns)
                if id_elem is not None and id_elem.text:
                    arxiv_id = id_elem.text.split("/abs/")[-1]
                    return PdfSource(
                        url=f"https://arxiv.org/pdf/{arxiv_id}.pdf",
                        source="arxiv",
                    )
        except Exception:
            logger.debug("arXiv PDF lookup failed for %r", title, exc_info=True)
        return None

    # ── Layer 4: Semantic Scholar ─────────────────────────────────────

    def _from_semantic_scholar(self, doi: str) -> PdfSource | None:
        """Query Semantic Scholar for open-access PDF."""
        url = f"https://api.semanticscholar.org/graph/v1/paper/DOI:{doi}"
        params = {"fields": "openAccessPdf"}
        headers = {}
        if self.s2_key:
            headers["x-api-key"] = self.s2_key
        try:
            resp = self.session.get(url, params=params, headers=headers, timeout=15)
            if resp.status_code != 200:
                return None
            data = resp.json()
            oa_pdf = data.get("openAccessPdf")
            if oa_pdf and oa_pdf.get("url"):
                return PdfSource(
                    url=oa_pdf["url"],
                    source=f"semantic_scholar:{oa_pdf.get('status', 'unknown')}",
                )
        except Exception:
            logger.debug("Semantic Scholar PDF lookup failed for %s", doi, exc_info=True)
        return None

    # ── Public API ────────────────────────────────────────────────────

    def resolve(self, doi: str, title: str = "") -> PdfSource | None:
        """Resolve PDF URL with layered fallback.

        Priority: OpenAlex → Unpaywall → arXiv → Semantic Scholar
        """
        # Layer 1: OpenAlex (free, already integrated)
        result = self._from_openalex(doi)
        if result:
            return result

        time.sleep(0.1)

        # Layer 2: Unpaywall
        result = self._from_unpaywall(doi)
        if result:
            return result

        time.sleep(0.1)

        # Layer 3: arXiv (if title provided)
        if title:
            result = self._from_arxiv(title)
            if result:
                return result

        time.sleep(0.5)

        # Layer 4: Semantic Scholar
        result = self._from_semantic_scholar(doi)
        if result:
            return result

        return None


def resolve_paper_pdf_cached(db_path: Path, paper: Paper) -> dict[str, str] | None:
    """Resolve a paper's PDF URL with DB caching.

    Checks the PDF cache first; on miss, uses PdfResolver to find the
    PDF and stores the result.  Returns a dict with pdf_url, pdf_source,
    and source, or None if no DOI is available.
    """
    from paperbot.db import get_paper_pdf, set_paper_pdf

    cached = get_paper_pdf(db_path, paper.id)
    if cached:
        return {**cached, "source": "cache"}

    doi = paper.doi or ""
    if not doi:
        return None

    with PdfResolver() as resolver:
        result = resolver.resolve(doi, title=paper.title)

    if result:
        set_paper_pdf(db_path, paper.id, result.url, result.source)
        return {
            "pdf_url": result.url,
            "pdf_source": result.source,
            "source": "api",
        }
    return {"pdf_url": "", "pdf_source": "", "source": "none"}
