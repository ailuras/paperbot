"""Shared utility helpers."""

from __future__ import annotations

import re
from datetime import datetime

DATE_FORMAT = "%Y-%m-%d"

# Venue name → acronym mapping for known conferences / journals.
VENUE_ABBR_MAP: dict[str, list[str]] = {
    "CAV": ["computer aided verification"],
    "ICSE": ["international conference on software engineering"],
    "FSE": ["foundations of software engineering", "esec/fse"],
    "ASE": ["automated software engineering"],
    "ISSTA": ["software testing and analysis"],
    "PLDI": ["programming language design"],
    "POPL": ["principles of programming languages"],
    "OOPSLA": ["object-oriented programming"],
    "NeurIPS": ["neural information processing", "neurips"],
    "ICML": ["international conference on machine learning"],
    "ICLR": ["learning representations"],
    "AAAI": ["advancement of artificial intelligence"],
    "IJCAI": ["joint conference on artificial intelligence"],
    "TACAS": ["tools and algorithms"],
    "CADE": ["automated deduction"],
    "IJCAR": ["joint conference on automated reasoning"],
    "LICS": ["logic in computer science"],
    "SAT": [
        "international conference on theory and applications of satisfiability testing",
        "satisfiability testing",
        "theory and applications of satisfiability",
    ],
    "CPAIOR": [
        "integration of constraint programming, artificial intelligence, and operations research",
        "integration of artificial intelligence and operations research techniques in constraint programming",
        "constraint programming, artificial intelligence",
    ],
    "CP": [
        "international conference on principles and practice of constraint programming",
        "principles and practice of constraint programming",
        "constraint programming",
    ],
    "FM": ["symposium on formal methods"],
    "JAIR": ["journal of artificial intelligence research"],
    "AIJ": ["artificial intelligence"],
    "TOSEM": ["acm transactions on software engineering"],
    "TSE": ["ieee transactions on software engineering"],
    "TOPLAS": ["programming languages and systems"],
    "USENIX": ["usenix security"],
    "CCS": ["computer and communications security"],
    "NDSS": ["network and distributed system security"],
    "S&P": ["security and privacy", "ieee symposium on security"],
    "OSDI": ["operating systems design"],
    "SOSP": ["operating systems principles"],
    "EuroSys": ["eurosys"],
    "SIGCOMM": ["sigcomm"],
    "SIGMOD": ["management of data"],
    "VLDB": ["very large data bases", "vldb"],
    "WWW": ["the web conference", "world wide web"],
    "ACL": ["association for computational linguistics"],
    "EMNLP": ["empirical methods in natural language"],
    "CVPR": ["computer vision and pattern recognition"],
    "ICCV": ["international conference on computer vision"],
    "ECCV": ["european conference on computer vision"],
    "SAS": ["static analysis symposium"],
    "ICLP": ["logic programming"],
    "FMCAD": ["formal methods in computer-aided design"],
    "VMCAI": [
        "verification, model checking, and abstract interpretation",
        "verification, model checking",
    ],
    "LPAR": [
        "logic for programming, artificial intelligence and reasoning",
        "logic for programming",
    ],
    "JAR": ["journal of automated reasoning"],
    "FMSD": ["formal methods in system design"],
    "ICSME": ["software maintenance"],
    "ISSRE": ["software reliability engineering"],
    "SANER": ["software analysis, evolution"],
    "COMPSAC": ["computer software and applications"],
    "MSR": ["mining software repositories"],
    "KR": ["knowledge representation and reasoning"],
    "SEFM": ["software engineering and formal methods"],
    "ICFEM": ["formal engineering methods"],
    "ICECCS": ["engineering of complex computer systems"],
    "QRS": ["software quality, reliability"],
    "AST": ["automation of software test", "automated software testing"],
    "ICTAI": ["tools with artificial intelligence"],
}


def format_date(dt: datetime | None = None) -> str:
    """Return a consistently formatted date string."""
    if dt is None:
        dt = datetime.now()
    return dt.strftime(DATE_FORMAT)


def _abbr(venue: str) -> str:
    """Extract an acronym from a venue string, or return a short prefix."""
    if not venue:
        return "?"
    m = re.search(r"\b[A-Z]{2,}\b", venue)
    return m.group(0) if m else venue[:10]


def compute_venue_abbr(venue: str) -> str:
    """Classify a venue into a display abbreviation.

    Rules:
      - arXiv  →  "arXiv"
      - Known conference / journal (matched by VENUE_ABBR_MAP) → acronym
      - Everything else  →  "Others"
    """
    if not venue:
        return "Others"

    venue_lower = venue.lower()

    # arXiv papers
    if "arxiv" in venue_lower:
        return "arXiv"

    # Known venues
    for abbr, keywords in VENUE_ABBR_MAP.items():
        for kw in keywords:
            if kw in venue_lower:
                return abbr

    return "Others"
