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
DEFAULT_SCHEMA_JSON = REPO_ROOT / "rules" / "sca-rules.schema.json"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "docs" / "rules"


def validate_against_schema(catalog: dict[str, Any], schema_path: Path) -> int:
    """Validate the catalog against its own schema.

    Runs only when `jsonschema` is installed - the generator must stay usable
    on a bare Python. Silence here is not a pass; the summary line says which
    of the two happened.

    Why this sits in the generator at all: the schema existed but nothing ever
    ran it, and a 208-character `shortDescription` (SCA153, limit 200) sat in
    the catalog undetected. Every rule edit passes through this script, so
    this is the one place the check is guaranteed to be seen.
    """
    try:
        import jsonschema  # noqa: PLC0415 - optional dependency by design
    except ImportError:
        print("NOTE: jsonschema not installed - schema validation skipped "
              "(pip install jsonschema)", file=sys.stderr)
        return 0

    if not schema_path.exists():
        print(f"NOTE: schema not found: {schema_path} - validation skipped",
              file=sys.stderr)
        return 0

    with schema_path.open(encoding="utf-8-sig") as f:
        schema = json.load(f)

    validator = jsonschema.Draft7Validator(schema)
    errors = sorted(validator.iter_errors(catalog),
                    key=lambda e: list(e.absolute_path))
    for err in errors:
        path = list(err.absolute_path)
        rule_id = "?"
        if len(path) > 1 and path[0] == "rules":
            rule_id = catalog["rules"][path[1]].get("id", "?")
        field = ".".join(str(p) for p in path[2:]) or "(rule)"
        print(f"SCHEMA: {rule_id} {field}: {err.message}", file=sys.stderr)
    if errors:
        print(f"\n{len(errors)} schema violation(s) in "
              f"{DEFAULT_RULES_JSON.name}.", file=sys.stderr)
    return len(errors)


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


# Ueberschriften und feste Saetze je Sprache. Die englischen Werte MUESSEN
# zeichengleich mit der bisherigen Ausgabe bleiben: die englischen Seiten
# sind das Ziel des SARIF-helpUri jedes bereits ausgelieferten Berichts.
LABELS = {
    "en": {
        "meta": "Metadata", "field": "Field", "value": "Value",
        "ruleid": "Rule ID", "kind": "Kind",
        "severity": "Default severity", "type": "Type",
        "unit": "Detector unit", "config": "Config key",
        "tags": "Tags", "desc": "Description", "examples": "Examples",
        "bad": "Bad (triggers the rule)", "good": "Good (idiomatic fix)",
        "notrep": "Not reported (by design)",
        "notrep_intro": (
            "The detector deliberately stays silent on the constructs "
            "below. Each is a false-positive class that was measured on "
            "the real-world corpus, not a guess."),
        "index_title": "StaticCodeAnalyser — Rule Catalog",
        "index_lead": "All {n} detector rules. Click an ID for full details.",
        "col_id": "ID", "col_name": "Name", "col_sev": "Severity",
        "col_type": "Type", "col_det": "Detector",
        "untranslated": "",
    },
    "de": {
        "meta": "Metadaten", "field": "Feld", "value": "Wert",
        "ruleid": "Regel-ID", "kind": "Kind",
        "severity": "Standard-Schweregrad", "type": "Typ",
        "unit": "Detektor-Unit", "config": "Konfigurationsschlüssel",
        "tags": "Schlagworte", "desc": "Beschreibung",
        "examples": "Beispiele",
        "bad": "Schlecht (löst die Regel aus)",
        "good": "Gut (idiomatische Korrektur)",
        "notrep": "Absichtlich nicht gemeldet",
        "notrep_intro": (
            "Bei den folgenden Konstrukten schweigt der Detektor "
            "absichtlich. Jedes davon ist eine False-Positive-Klasse, die "
            "am Realwelt-Korpus gemessen wurde — keine Vermutung."),
        "index_title": "StaticCodeAnalyser — Regelkatalog",
        "index_lead": ("Alle {n} Detektor-Regeln. Eine ID anklicken führt "
                       "zur vollständigen Beschreibung."),
        "col_id": "ID", "col_name": "Name", "col_sev": "Schweregrad",
        "col_type": "Typ", "col_det": "Detektor",
        "untranslated": ("> Dieser Abschnitt liegt nur auf Englisch vor. "
                         "Übersetzt sind Name und Kurzbeschreibung; die "
                         "Volltexte folgen der englischen Fassung."),
    },
    "fr": {
        "meta": "Métadonnées", "field": "Champ", "value": "Valeur",
        "ruleid": "Identifiant de règle", "kind": "Kind",
        "severity": "Sévérité par défaut", "type": "Type",
        "unit": "Unité du détecteur", "config": "Clé de configuration",
        "tags": "Étiquettes", "desc": "Description",
        "examples": "Exemples",
        "bad": "Mauvais (déclenche la règle)",
        "good": "Bon (correction idiomatique)",
        "notrep": "Volontairement non signalé",
        "notrep_intro": (
            "Le détecteur garde volontairement le silence sur les "
            "constructions ci-dessous. Chacune est une classe de faux "
            "positifs mesurée sur le corpus réel — ce n'est pas une "
            "supposition."),
        "index_title": "StaticCodeAnalyser — Catalogue de règles",
        "index_lead": ("Les {n} règles de détection. Cliquez sur un "
                       "identifiant pour le détail complet."),
        "col_id": "ID", "col_name": "Nom", "col_sev": "Sévérité",
        "col_type": "Type", "col_det": "Détecteur",
        "untranslated": ("> Cette section n'existe qu'en anglais. Le nom et "
                         "la description courte sont traduits ; les textes "
                         "complets suivent la version anglaise."),
    },
}


def load_overlay(lang: str, rules_json: Path) -> dict[str, dict[str, str]]:
    """Rule ID -> uebersetzte Felder, aus rules/sca-rules.<lang>.json.

    Fehlt die Datei oder eine Regel darin, bleibt Englisch stehen. Das ist
    der dokumentierte Rueckfall des Overlay-Schemas, kein Fehler - sonst
    koennte eine Uebersetzung nicht regelweise entstehen.
    """
    if lang == "en":
        return {}
    p = rules_json.with_suffix("")
    p = p.parent / (p.name + f".{lang}.json")
    if not p.exists():
        return {}
    with p.open(encoding="utf-8-sig") as f:
        return json.load(f).get("rules", {})


def render_rule(rule: dict[str, Any], lang: str = "en",
                depth: str = "../..") -> str:
    """Render a single rule as a Markdown page.

    lang steuert nur Ueberschriften und feste Saetze; die Regeltexte
    selbst kommen bereits uebersetzt herein (der Aufrufer legt das Overlay
    darueber). depth ist der relative Weg zur Repo-Wurzel - eine
    Sprachfassung liegt eine Ebene tiefer als die englische.
    """
    L = LABELS.get(lang, LABELS["en"])
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
    parts.append(f"## {L['meta']}")
    parts.append("")
    parts.append(f"| {L['field']} | {L['value']} |")
    parts.append("|---|---|")
    parts.append(f"| **{L['ruleid']}** | `{rule['id']}` |")
    parts.append(f"| **{L['kind']}** | `{rule['kind']}` |")
    parts.append(f"| **{L['severity']}** | {rule['defaultSeverity']} |")
    parts.append(f"| **{L['type']}** | {rule['type']} |")
    parts.append(f"| **{L['unit']}** | `{rule['detectorUnit']}` |")
    if rule.get("configKey"):
        parts.append(f"| **{L['config']}** | `{rule['configKey']}` |")
    if rule.get("tags"):
        parts.append(f"| **{L['tags']}** | {', '.join(f'`{t}`' for t in rule['tags'])} |")
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
        parts.append(f"## {L['desc']}")
        parts.append("")
        # Volltexte sind bewusst nicht uebersetzt (Umfang, Alterung).
        # Das steht sichtbar da, statt den Leser raten zu lassen,
        # warum mitten in seiner Sprache Englisch beginnt.
        if L["untranslated"]:
            parts.append(L["untranslated"])
            parts.append("")
        parts.append(rule["fullDescription"])
        parts.append("")

    # Examples
    if rule.get("examples"):
        parts.append(f"## {L['examples']}")
        parts.append("")
        parts.append(f"### {L['bad']}")
        parts.append("")
        parts.append("```pascal")
        parts.append(rule["examples"]["bad"])
        parts.append("```")
        parts.append("")
        parts.append(f"### {L['good']}")
        parts.append("")
        parts.append("```pascal")
        parts.append(rule["examples"]["good"])
        parts.append("```")
        parts.append("")

    # Exceptions - what the detector deliberately does NOT report.
    # Without this section a user cannot tell "the rule found nothing" from
    # "the rule has a gate for exactly this case", which is the single most
    # common support question after an FP campaign.
    if rule.get("exceptions"):
        parts.append(f"## {L['notrep']}")
        parts.append("")
        parts.append(L["notrep_intro"])
        parts.append("")
        for exc in rule["exceptions"]:
            parts.append(f"### {exc['case']}")
            parts.append("")
            parts.append(exc["why"])
            parts.append("")
            if exc.get("example"):
                parts.append("```pascal")
                parts.append(exc["example"])
                parts.append("```")
                parts.append("")

    # Footer
    parts.append("---")
    parts.append("")
    parts.append(
        f"_Generated from "
        f"[`rules/sca-rules.json`]({depth}/rules/sca-rules.json) by "
        f"[`tools/gen-rules-docs.py`]({depth}/tools/gen-rules-docs.py). "
        f"Do not edit by hand — re-run the generator instead._"
    )
    parts.append("")

    return "\n".join(parts)


def render_index(rules: list[dict[str, Any]], lang: str = "en",
                 depth: str = "../..") -> str:
    """Render the overview index page."""
    L = LABELS.get(lang, LABELS["en"])
    parts: list[str] = []
    parts.append(f"# {L['index_title']}")
    parts.append("")
    parts.append(L["index_lead"].format(n=len(rules)))
    parts.append("")
    parts.append(f"| {L['col_id']} | {L['col_name']} | {L['col_sev']} | "
                 f"{L['col_type']} | {L['col_det']} |")
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
        f"_Generated from "
        f"[`rules/sca-rules.json`]({depth}/rules/sca-rules.json) by "
        f"[`tools/gen-rules-docs.py`]({depth}/tools/gen-rules-docs.py)._"
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
    ap.add_argument(
        "--schema", type=Path, default=DEFAULT_SCHEMA_JSON,
        help=f"Path to the rule schema (default: "
             f"{DEFAULT_SCHEMA_JSON.relative_to(REPO_ROOT)})"
    )
    ap.add_argument(
        "--no-schema-check", action="store_true",
        help="Skip validating the catalog against its schema."
    )
    ap.add_argument(
        "--no-langs", action="store_true",
        help="English only - ignore the rules/sca-rules.<lang>.json overlays."
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

    if not args.no_schema_check:
        if validate_against_schema(catalog, args.schema) > 0:
            return 2

    # Sprachen: Englisch immer, dazu jedes vorhandene Overlay. Die
    # ENGLISCHEN Ausgabepfade bleiben unveraendert (docs/rules/SCA###.md) -
    # daran haengt der SARIF-helpUri jedes bereits ausgelieferten Berichts.
    # Uebersetzungen liegen eine Ebene tiefer unter docs/rules/<lang>/.
    langs = ["en"]
    if not args.no_langs:
        for cand in sorted(LABELS):
            if cand != "en" and load_overlay(cand, args.rules):
                langs.append(cand)

    diff_count = 0
    erzeugt = []

    for lang in langs:
        ziel = args.out if lang == "en" else args.out / lang
        depth = "../.." if lang == "en" else "../../.."
        overlay = load_overlay(lang, args.rules)
        ziel.mkdir(parents=True, exist_ok=True)

        # Overlay ueber die kanonische Regel legen. Was das Overlay nicht
        # fuehrt, bleibt englisch - der dokumentierte Rueckfall.
        lokal = [{**r, **overlay.get(r["id"], {})} for r in rules]

        for r in lokal:
            out_file = ziel / f"{r['id']}.md"
            new_content = render_rule(r, lang, depth)
            if args.check:
                existing = (out_file.read_text(encoding="utf-8")
                            if out_file.exists() else "")
                if existing != new_content:
                    print(f"DIFF: {out_file.relative_to(REPO_ROOT)}",
                          file=sys.stderr)
                    diff_count += 1
            else:
                out_file.write_text(new_content, encoding="utf-8")

        index_file = ziel / "index.md"
        new_index = render_index(lokal, lang, depth)
        if args.check:
            existing = (index_file.read_text(encoding="utf-8")
                        if index_file.exists() else "")
            if existing != new_index:
                print(f"DIFF: {index_file.relative_to(REPO_ROOT)}",
                      file=sys.stderr)
                diff_count += 1
        else:
            index_file.write_text(new_index, encoding="utf-8")
        erzeugt.append(lang)

    if args.check:
        if diff_count > 0:
            print(
                f"\n{diff_count} file(s) out of date. "
                f"Run: python tools/gen-rules-docs.py",
                file=sys.stderr,
            )
            return 1
        print(f"OK: all {len(rules)} rule docs + index in sync "
              f"({', '.join(erzeugt)}).")
        return 0

    print(f"Generated {len(rules)} rule pages + index.md per language "
          f"({', '.join(erzeugt)}) in {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
