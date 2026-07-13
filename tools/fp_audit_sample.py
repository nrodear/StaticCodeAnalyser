#!/usr/bin/env python3
"""Phase 3-Vorbereitung: pro Detektor eine diverse Stichprobe ziehen + Rubrik
aus docs/rules.md anhaengen. Schreibt sca-sample/<SCAxxx>.json (Funde+Meta) und
sca-sample/_manifest.json (Liste fuer den Workflow).

Diversitaet: Errors zuerst, dann Warnings; innerhalb jeder Gruppe Round-Robin
ueber distinkte Dateien, damit die Stichprobe moeglichst viele Files trifft.
"""
import argparse, json, os, re, collections

CAP = 25


def rule_descriptions(rules_md):
    """{'SCA005': '<verdichtete Sektion, <=600 Zeichen>'}."""
    if not os.path.exists(rules_md):
        return {}
    txt = open(rules_md, encoding="utf-8-sig").read()
    out = {}
    # Sektionen '## SCAxxx' bis zur naechsten '## '
    parts = re.split(r"\n##\s+", "\n" + txt)
    for p in parts:
        m = re.match(r"(SCA\d+)\b(.*)", p, re.S)
        if not m:
            continue
        rid = m.group(1)
        body = re.sub(r"\s+", " ", m.group(2)).strip()
        out[rid] = body[:600]
    return out


def diverse(findings, cap):
    """Errors zuerst, dann Warnings; je Gruppe Round-Robin ueber Dateien."""
    def rr(group):
        byfile = collections.OrderedDict()
        for f in group:
            byfile.setdefault(f["file"], []).append(f)
        picked = []
        while any(byfile.values()):
            for k in list(byfile.keys()):
                if byfile[k]:
                    picked.append(byfile[k].pop(0))
        return picked

    errs = rr([f for f in findings if f["level"] == "error"])
    warns = rr([f for f in findings if f["level"] != "error"])
    return (errs + warns)[:cap]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bydetector", nargs="?", default="sca-realworld-byDetector.json")
    ap.add_argument("--rules", default="docs/rules.md")
    ap.add_argument("--outdir", default="sca-sample")
    ap.add_argument("--cap", type=int, default=CAP)
    args = ap.parse_args()

    data = json.load(open(args.bydetector, encoding="utf-8"))
    desc = rule_descriptions(args.rules)
    os.makedirs(args.outdir, exist_ok=True)

    manifest = []
    for rid, fs in sorted(data.items()):
        ec = sum(1 for f in fs if f["level"] == "error")
        name = fs[0]["detector"]
        sample = diverse(fs, args.cap)
        # msg auf handliche Laenge kuerzen (Agent liest ohnehin die reale Quelle)
        for f in sample:
            f["message"] = (f.get("message") or "").replace("\r", " ").replace("\n", " ")[:200]
        rec = {
            "id": rid, "name": name, "total": len(fs),
            "errors": ec, "warnings": len(fs) - ec,
            "sampled": len(sample),
            "rule_desc": desc.get(rid, ""),
            "findings": sample,
        }
        path = os.path.join(args.outdir, f"{rid}.json")
        json.dump(rec, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        manifest.append({
            "id": rid, "name": name, "total": len(fs), "errors": ec,
            "sampled": len(sample), "desc": desc.get(rid, "")[:300],
            "file": path.replace("\\", "/"),
        })

    json.dump(manifest, open(os.path.join(args.outdir, "_manifest.json"),
              "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    tot_s = sum(m["sampled"] for m in manifest)
    print(f"Detektoren: {len(manifest)}  gesamt gesampelt: {tot_s}  cap={args.cap}")
    print(f"Manifest: {args.outdir}/_manifest.json")


if __name__ == "__main__":
    main()
