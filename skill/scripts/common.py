#!/usr/bin/env python3
"""Shared helpers for PaperDaily scripts."""

from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, Optional


SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_ROOT = SCRIPT_DIR.parent
_REPO_CONFIG_DIR = SKILL_ROOT.parent / "data"
_WORKSPACE_CONFIG_DIR = Path("~/.openclaw/workspace/paperdaily").expanduser()
DEFAULT_CONFIG_DIR = _REPO_CONFIG_DIR if _REPO_CONFIG_DIR.is_dir() else _WORKSPACE_CONFIG_DIR


DEFAULT_CONFIG: Dict[str, Any] = {
    "data_file": "papers.json",
    "openalex": {
        "base_url": "https://api.openalex.org/works",
        "mailto": "",
        "api_key_env": "OPENALEX_API_KEY",
        "timeout_seconds": 20,
        "per_page": 100,
        "default_days": 45,
        "default_max_results": 1000,
        "topic_filter": "topics.field.id:17",
    },
    "tracks": {
        "SMT": {
            "query": "\"SMT solver\" OR \"satisfiability modulo theories\" OR \"SMT-based\" OR \"string constraint solving\" OR \"optimization modulo theories\"",
            "keywords": [
                "smt solver",
                "smt solvers",
                "smt solving",
                "satisfiability modulo",
                "smt-based",
                "smt encoding",
                "smt formula",
                "smt formulas",
                "optimization modulo",
                "string constraint solving",
                "bit-vector",
                "uninterpreted functions",
                "quantified smt",
                "z3",
                "cvc4",
                "cvc5",
                "mathsat",
                "boolector",
                "yices",
                "bitwuzla",
            ],
        },
        "SAT": {
            "query": "\"SAT solving\" OR \"SAT solver\" OR \"Boolean satisfiability\" OR \"SAT-based\" OR \"CDCL\" OR \"conflict-driven clause learning\"",
            "keywords": [
                "sat solver",
                "sat solvers",
                "sat solving",
                "boolean satisfiability",
                "sat-based",
                "sat encoding",
                "sat formula",
                "sat instances",
                "cdcl",
                "conflict-driven clause learning",
                "maxsat",
                "max-sat",
                "qbf",
                "quantified boolean formula",
                "unsat core",
                "model counting",
                "minisat",
                "glucose",
                "cadical",
                "cryptominisat",
                "kissat",
                "lingeling",
            ],
        },
        "CP": {
            "query": "\"constraint programming\" OR \"constraint solving\" OR \"constraint satisfaction\" OR \"constraint optimization\"",
            "keywords": [
                "constraint programming",
                "constraint solving",
                "constraint satisfaction",
                "constraint optimization",
                "csp",
                "csps",
                "cop",
                "cops",
                "constraint propagation",
                "arc consistency",
                "global constraint",
                "global constraints",
                "minizinc",
                "choco solver",
                "gecode",
                "or-tools",
            ],
        },
    },
    "filters": {
        "title_blacklist": [
            "artifact for",
            "supplementary material",
            "supplemental material",
            "correction to",
            "erratum",
            "retracted:",
            "comment on",
        ],
        "source_blacklist": ["zenodo", "figshare"],
        "venue_blacklist": ["satellite", "satellites", "cpanel", "combat", "compatible"],
    },
    "scoring": {
        "tiers": {
            "1": {
                "points": 20,
                "acronyms": [
                    "CAV",
                    "ICSE",
                    "FSE",
                    "ESEC",
                    "ASE",
                    "ISSTA",
                    "PLDI",
                    "POPL",
                    "OOPSLA",
                    "NeurIPS",
                    "NIPS",
                    "ICML",
                    "ICLR",
                    "AAAI",
                    "IJCAI",
                    "TACAS",
                    "CADE",
                    "IJCAR",
                    "LICS",
                    "NDSS",
                ],
                "phrases": [
                    "Computer Aided Verification",
                    "International Conference on Software Engineering",
                    "Foundations of Software Engineering",
                    "Automated Software Engineering",
                    "Software Testing and Analysis",
                    "Programming Language Design",
                    "Principles of Programming Languages",
                    "Object-Oriented Programming",
                    "Neural Information Processing Systems",
                    "Machine Learning",
                    "Learning Representations",
                    "Advancement of Artificial Intelligence",
                    "Joint Conference on Artificial Intelligence",
                    "Tools and Algorithms for the Construction",
                    "Automated Deduction",
                    "Joint Conference on Automated Reasoning",
                    "Logic in Computer Science",
                    "Security and Privacy",
                    "USENIX Security",
                    "Computer and Communications Security",
                    "IEEE Transactions on Software Engineering",
                    "ACM Transactions on Software Engineering",
                    "Satisfiability Testing",
                    "Constraint Programming",
                    "Symposium on Formal Methods",
                    "Journal of Artificial Intelligence Research",
                    "Artificial Intelligence",
                ],
            },
            "2": {
                "points": 10,
                "acronyms": ["SAS", "ICLP", "FMCAD", "VMCAI", "CPAIOR", "LPAR", "JAR", "FMSD", "ICSME", "ISSRE", "SANER", "COMPSAC", "MSR", "KR"],
                "phrases": [
                    "Static Analysis",
                    "Logic Programming",
                    "Formal Methods in Computer-Aided Design",
                    "Verification, Model Checking",
                    "Constraint Programming, Artificial Intelligence",
                    "Logic for Programming",
                    "Journal of Automated Reasoning",
                    "Formal Methods in System Design",
                    "Software Maintenance",
                    "Software Reliability Engineering",
                    "Software Analysis, Evolution",
                    "Computer Software and Applications",
                    "Mining Software Repositories",
                    "Knowledge Representation and Reasoning",
                ],
            },
            "3": {
                "points": 5,
                "acronyms": ["SEFM", "ICFEM", "ICECCS", "QRS", "QSIC", "AST", "ICTAI"],
                "phrases": [
                    "Software Engineering and Formal Methods",
                    "Formal Engineering Methods",
                    "Engineering of Complex Computer Systems",
                    "Software Quality, Reliability",
                    "Automated Software Testing",
                    "Tools with Artificial Intelligence",
                ],
            },
        },
        "citation_breakpoints": [
            {"up_to": 10, "points_per_citation": 1.0},
            {"up_to": 50, "points_per_citation": 0.5},
            {"up_to": None, "points_per_citation": 0.2},
        ],
        "max_citation_points": 40,
    },
    "recommendation": {
        "daily_count": 3,
        "quality_slots": 1,
        "high_score_threshold": 5,
        "recent_days": 30,
        "include_ai_reading_placeholder": True,
    },
}


def merge_config(defaults: Dict[str, Any], overrides: Dict[str, Any]) -> Dict[str, Any]:
    merged = deepcopy(defaults)
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_config(merged[key], value)
        else:
            merged[key] = value
    return merged


def load_config(config_path: Optional[str] = None) -> Dict[str, Any]:
    path = Path(config_path).expanduser() if config_path else (DEFAULT_CONFIG_DIR / "config.json")
    try:
        with path.open() as f:
            user_config = json.load(f)
    except FileNotFoundError:
        raise SystemExit(f"Config file not found: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Failed to parse config: {exc}")

    if not isinstance(user_config, dict):
        raise SystemExit("Invalid config format, expected a JSON object.")

    config = merge_config(DEFAULT_CONFIG, user_config)
    data_file = Path(config["data_file"]).expanduser()
    if not data_file.is_absolute():
        data_file = (path.parent / data_file).resolve()
    config["_data_dir"] = str(path.parent)
    config["_data_file"] = str(data_file)
    return config


def atomic_write_json(path: Path | str, data: Any) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_name(f".{path.name}.tmp")
    with tmp_path.open("w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    tmp_path.replace(path)
