#!/usr/bin/env python3
"""Phase 2 des Real-World-FP-Audits (Konzept_RealWorldFpAudit_2026-07-10.md).

SARIF laden -> Funde auf level in {error,warning} filtern -> optional Pfade
ausschliessen -> nach ruleId (Detektor) gruppieren -> byDetector.json schreiben
+ Zusammenfassungstabelle drucken.

Usage:
  python tools/fp_audit_group.py sca-realworld.sarif \
    --levels error,warning --exclude StaticCodeAnalyser \
    --out sca-realworld-byDetector.json
"""
import argparse, json, os, sys, collections


def load_sarif(path):
    with open(path, "r", encoding="utf-8-sig") as f:
        # strict=False: SARIF-Messages enthalten rohe Steuerzeichen (Code-Snippets)
        return json.load(f, strict=False)


def rule_name_map(run):
    """ruleId/index -> lesbarer Detektor-Name aus tool.driver.rules."""
    names = {}
    driver = run.get("tool", {}).get("driver", {})
    for i, r in enumerate(driver.get("rules", []) or []):
        rid = r.get("id") or r.get("name") or str(i)
        nm = r.get("name") or r.get("id") or str(i)
        names[rid] = nm
        names[str(i)] = nm  # falls results nur ruleIndex tragen
    return names, driver.get("rules", []) or []


def rule_level_map(rules):
    """ruleId -> defaultConfiguration.level (Fallback wenn result.level fehlt)."""
    lv = {}
    for r in rules:
        rid = r.get("id") or r.get("name")
        cfg = (r.get("defaultConfiguration") or {}).get("level")
        if rid and cfg:
            lv[rid] = cfg
    return lv


def norm_uri(uri):
    if not uri:
        return ""
    if uri.startswith("file:///"):
        uri = uri[8:]
    elif uri.startswith("file://"):
        uri = uri[7:]
    return uri.replace("/", os.sep)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sarif")
    ap.add_argument("--levels", default="error,warning")
    ap.add_argument("--exclude", action="append", default=[],
                    help="Substring; Funde in passenden Pfaden verwerfen (mehrfach)")
    ap.add_argument("--out", default="sca-realworld-byDetector.json")
    args = ap.parse_args()

    want = {x.strip().lower() for x in args.levels.split(",") if x.strip()}
    doc = load_sarif(args.sarif)

    by = collections.defaultdict(list)
    total = kept = excluded = 0
    dropped_level = collections.Counter()

    for run in doc.get("runs", []):
        names, rules = rule_name_map(run)
        lvlmap = rule_level_map(rules)
        for res in run.get("results", []):
            total += 1
            rid = res.get("ruleId")
            if rid is None and "ruleIndex" in res:
                rid = str(res["ruleIndex"])
            rid = rid or "?"
            level = (res.get("level") or lvlmap.get(rid) or "warning").lower()
            if level not in want:
                dropped_level[level] += 1
                continue
            loc = (res.get("locations") or [{}])[0]
            phys = loc.get("physicalLocation", {})
            uri = norm_uri(phys.get("artifactLocation", {}).get("uri", ""))
            line = phys.get("region", {}).get("startLine", 0)
            if any(ex.lower() in uri.lower() for ex in args.exclude):
                excluded += 1
                continue
            msg = (res.get("message") or {}).get("text", "")
            by[rid].append({
                "ruleId": rid,
                "detector": names.get(rid, rid),
                "file": uri,
                "line": line,
                "level": level,
                "message": msg,
            })
            kept += 1

    out = {rid: sorted(v, key=lambda d: (d["file"], d["line"]))
           for rid, v in by.items()}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)

    # Zusammenfassung, sortiert nach Fundzahl (groesster Hebel zuerst)
    rows = sorted(((rid, out[rid][0]["detector"], len(out[rid]))
                   for rid in out), key=lambda r: -r[2])
    print(f"SARIF results total : {total}")
    print(f"nach level-Filter  : {kept} (behalten {sorted(want)})")
    print(f"self-excluded      : {excluded}  ({', '.join(args.exclude) or '-'})")
    print(f"verworfen (level)  : {dict(dropped_level)}")
    print(f"Detektoren mit error/warn : {len(rows)}")
    print(f"-> {args.out}\n")
    print(f"{'Detektor':<28}{'ruleId':<10}{'Funde':>7}")
    print("-" * 45)
    for rid, name, n in rows:
        print(f"{name[:27]:<28}{rid:<10}{n:>7}")


if __name__ == "__main__":
    main()
