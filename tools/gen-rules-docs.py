#!/usr/bin/env python3
"""
Generate per-rule Markdown documentation from rules/sca-rules.json.

Output: docs/rules/SCA001.md ... SCA022.md (one file per rule) and
        docs/rules/index.md (overview table).

Usage:
  python tools/gen-rules-docs.py                # Default paths
  python tools/gen-rules-docs.py --check        # Verify docs are up-to-date
                                                # (CI-friendly, exits non-zero
                                                #  on diff)

The generated Markdown files are referenced by SARIF results.[].helpUri,
so GitHub Code-Scanning's "more info" link in the PR annotation lands on
the rule's full description + examples. Keep them committed to the repo.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_RULES_JSON = REPO_ROOT / "rules" / "sca-rules.json"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "docs" / "rules"


SEVERITY_BADGE = {
    "Error":   "![Severity](https://img.shields.io/badge/severity-Error-red)",
    "Warning": "![Severity](https://img.shields.io/badge/severity-Warning-orange)",
    "Hint":    "![Severity](https://img.shields.io/badge/severity-Hint-blue)",
}

TYPE_BADGE = {
    "Bug":              "![Type](https://img.shields.io/badge/type-Bug-red)",
    "Code Smell":       "![Type](https://img.shields.io/badge/type-Code%20Smell-yellow)",
    "Vulnerability":    "![Type](https://img.shields.io/badge/type-Vulnerability-darkred)",
    "Security Hotspot": "![Type](https://img.shields.io/badge/type-Security%20Hotspot-orange)",
    "Code Duplication": "![Type](https://img.shields.io/badge/type-Code%20Duplication-blueviolet)",
    "File Error":       "![Type](https://img.shields.io/badge/type-File%20Error-grey)",
}


def render_rule(rule: dict[str, Any]) -> str:
    """Render a single rule as a Markdown page."""
    parts: list[str] = []

    parts.append(f"# {rule['id']} — {rule['name']}")
    parts.append("")

    # Badge row
    badges: list[str] = []
    if rule["defaultSeverity"] in SEVERITY_BADGE:
        badges.append(SEVERITY_BADGE[rule["defaultSeverity"]])
    if rule["type"] in TYPE_BADGE:
        badges.append(TYPE_BADGE[rule["type"]])
    if badges:
        parts.append(" ".join(badges))
        parts.append("")

    # Short description
    parts.append(f"> {rule['shortDescription']}")
    parts.append("")

    # Metadata table
    parts.append("## Metadata")
    parts.append("")
    parts.append("| Field | Value |")
    parts.append("|---|---|")
    parts.append(f"| **Rule ID** | `{rule['id']}` |")
    parts.append(f"| **Kind** | `{rule['kind']}` |")
    parts.append(f"| **Default severity** | {rule['defaultSeverity']} |")
    parts.append(f"| **Type** | {rule['type']} |")
    parts.append(f"| **Detector unit** | `{rule['detectorUnit']}` |")
    if rule.get("configKey"):
        parts.append(f"| **Config key** | `{rule['configKey']}` |")
    if rule.get("tags"):
        parts.append(f"| **Tags** | {', '.join(f'`{t}`' for t in rule['tags'])} |")
    if rule.get("cwe"):
        cwes = ", ".join(
            f"[{c}](https://cwe.mitre.org/data/definitions/{c.split('-')[-1]}.html)"
            for c in rule["cwe"]
        )
        parts.append(f"| **CWE** | {cwes} |")
    if rule.get("owasp"):
        parts.append(f"| **OWASP** | {', '.join(rule['owasp'])} |")
    parts.append("")

    # Full description
    if rule.get("fullDescription"):
        parts.append("## Description")
        parts.append("")
        parts.append(rule["fullDescription"])
        parts.append("")

    # Examples
    if rule.get("examples"):
        parts.append("## Examples")
        parts.append("")
        parts.append("### Bad (triggers the rule)")
        parts.append("")
        parts.append("```pascal")
        parts.append(rule["examples"]["bad"])
        parts.append("```")
        parts.append("")
        parts.append("### Good (idiomatic fix)")
        parts.append("")
        parts.append("```pascal")
        parts.append(rule["examples"]["good"])
        parts.append("```")
        parts.append("")

    # Footer
    parts.append("---")
    parts.append("")
    parts.append(
        "_Generated from "
        "[`rules/sca-rules.json`](../../rules/sca-rules.json) by "
        "[`tools/gen-rules-docs.py`](../../tools/gen-rules-docs.py). "
        "Do not edit by hand — re-run the generator instead._"
    )
    parts.append("")

    return "\n".join(parts)


def render_index(rules: list[dict[str, Any]]) -> str:
    """Render the overview index page."""
    parts: list[str] = []
    parts.append("# StaticCodeAnalyser — Rule Catalog")
    parts.append("")
    parts.append(f"All {len(rules)} detector rules. Click an ID for full details.")
    parts.append("")
    parts.append("| ID | Name | Severity | Type | Detector |")
    parts.append("|---|---|---|---|---|")
    for r in rules:
        parts.append(
            f"| [{r['id']}]({r['id']}.md) | {r['name']} | "
            f"{r['defaultSeverity']} | {r['type']} | "
            f"`{r['detectorUnit']}` |"
        )
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append(
        "_Generated from "
        "[`rules/sca-rules.json`](../../rules/sca-rules.json) by "
        "[`tools/gen-rules-docs.py`](../../tools/gen-rules-docs.py)._"
    )
    parts.append("")
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--rules", type=Path, default=DEFAULT_RULES_JSON,
        help=f"Path to rules JSON (default: {DEFAULT_RULES_JSON.relative_to(REPO_ROOT)})"
    )
    ap.add_argument(
        "--out", type=Path, default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUTPUT_DIR.relative_to(REPO_ROOT)})"
    )
    ap.add_argument(
        "--check", action="store_true",
        help="Verify docs match the JSON without writing. Exit 1 on diff."
    )
    args = ap.parse_args()

    if not args.rules.exists():
        print(f"ERROR: rules file not found: {args.rules}", file=sys.stderr)
        return 2

    with args.rules.open(encoding="utf-8-sig") as f:  # BOM-tolerant (Fix 2026-07-24)
        catalog = json.load(f)

    rules: list[dict[str, Any]] = catalog.get("rules", [])
    if not rules:
        print("ERROR: no rules found in catalog", file=sys.stderr)
        return 2

    args.out.mkdir(parents=True, exist_ok=True)

    diff_count = 0

    # Per-rule pages
    for r in rules:
        out_file = args.out / f"{r['id']}.md"
        new_content = render_rule(r)
        if args.check:
            existing = out_file.read_text(encoding="utf-8") if out_file.exists() else ""
            if existing != new_content:
                print(f"DIFF: {out_file.relative_to(REPO_ROOT)}", file=sys.stderr)
                diff_count += 1
        else:
            out_file.write_text(new_content, encoding="utf-8")

    # Index page
    index_file = args.out / "index.md"
    new_index = render_index(rules)
    if args.check:
        existing = index_file.read_text(encoding="utf-8") if index_file.exists() else ""
        if existing != new_index:
            print(f"DIFF: {index_file.relative_to(REPO_ROOT)}", file=sys.stderr)
            diff_count += 1
    else:
        index_file.write_text(new_index, encoding="utf-8")

    if args.check:
        if diff_count > 0:
            print(
                f"\n{diff_count} file(s) out of date. "
                f"Run: python tools/gen-rules-docs.py",
                file=sys.stderr,
            )
            return 1
        print(f"OK: all {len(rules)} rule docs + index in sync.")
        return 0

    print(f"Generated {len(rules)} rule pages + index.md in {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
