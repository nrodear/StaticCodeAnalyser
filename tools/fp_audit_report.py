#!/usr/bin/env python3
"""Phase 4+5: aus den Agenten-Verdicts pro Detektor die FP-TODO-Dateien
(nur FPs) + das Aggregat schreiben.

Input:
  sca-sample/verdicts.json  = [ {detector, fp_summary, verdicts:[{file,line,
                                  verdict,reason,fpClass,confidence}]}, ... ]
  sca-sample/_manifest.json = Detektor-Metadaten (total/errors/sampled/name)
Output:
  Todo_FP_<id>_<name>.md   (nur je Detektor mit >=1 FP; nur FPs gelistet)
  Audit_RealWorld_FP_<datum>.md  (Aggregat-Tabelle)
"""
import argparse, json, os, re, collections


def safe(name):
    return re.sub(r"[^A-Za-z0-9]+", "", name.title())[:40]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verdicts", default="sca-sample/verdicts.json")
    ap.add_argument("--manifest", default="sca-sample/_manifest.json")
    ap.add_argument("--date", default="2026-07-10")
    ap.add_argument("--corpus", default=r"D:\git-demos\delphi")
    args = ap.parse_args()

    man = {m["id"]: m for m in json.load(open(args.manifest, encoding="utf-8"))}
    vd = json.load(open(args.verdicts, encoding="utf-8"))

    rows = []
    for rec in vd:
        rid = rec.get("detector") or rec.get("id")
        if rid not in man:
            # Agent kann 'detector' als Name statt id geliefert haben -> best effort
            hit = [k for k, m in man.items() if m["name"] == rid]
            rid = hit[0] if hit else rid
        m = man.get(rid, {"name": rid, "total": 0, "errors": 0, "sampled": 0})
        vs = rec.get("verdicts", []) or []
        fp = [v for v in vs if v.get("verdict") == "FP"]
        tp = [v for v in vs if v.get("verdict") == "TP"]
        un = [v for v in vs if v.get("verdict") == "UNSURE"]
        exam = len(vs) or 1
        fp_rate = len(fp) / exam
        est = round(fp_rate * m["total"])
        rows.append({
            "id": rid, "name": m["name"], "total": m["total"], "errors": m["errors"],
            "sampled": m["sampled"], "examined": len(vs), "fp": len(fp),
            "tp": len(tp), "unsure": len(un), "fp_rate": fp_rate, "est_fp": est,
            "fp_summary": rec.get("fp_summary", ""), "fps": fp,
        })

        if fp:
            fn = f"Todo_FP_{rid}_{safe(m['name'])}.md"
            classes = collections.Counter(v.get("fpClass", "?") or "?" for v in fp)
            with open(fn, "w", encoding="utf-8") as f:
                f.write(f"# FP-Backlog {rid} {m['name']}\n\n")
                f.write(f"Scan: sca-realworld.sarif ({args.date}, Korpus {args.corpus})\n\n")
                f.write(f"- Gesamt error+warn: **{m['total']}** (davon error: {m['errors']})\n")
                f.write(f"- Stichprobe geprueft: {len(vs)} | FP: **{len(fp)}** | TP: {len(tp)} | UNSURE: {len(un)}\n")
                f.write(f"- FP-Rate (Stichprobe): **{fp_rate:.0%}** -> Hochrechnung Gesamt-FP ~**{est}**\n\n")
                if rec.get("fp_summary"):
                    f.write(f"**Agent-Zusammenfassung:** {rec['fp_summary']}\n\n")
                f.write("## FP-Klassen\n")
                for c, n in classes.most_common():
                    f.write(f"- `{c}` x{n}\n")
                f.write("\n## Einzelne FPs\n")
                for v in fp:
                    f.write(f"- [ ] {v.get('file')}:{v.get('line')} "
                            f"— {v.get('reason','')} "
                            f"_(class: {v.get('fpClass','?')}, conf: {v.get('confidence','?')})_\n")

    rows.sort(key=lambda r: (-r["fp"], -r["est_fp"]))
    agg = f"Audit_RealWorld_FP_{args.date}.md"
    with open(agg, "w", encoding="utf-8") as f:
        f.write(f"# Real-World FP-Audit — Aggregat ({args.date})\n\n")
        f.write(f"Korpus: `{args.corpus}` | Scan: sca-realworld.sarif | "
                f"Filter: error+warn | Stichprobe cap 25/Detektor\n\n")
        tot_fp = sum(r["fp"] for r in rows)
        tot_ex = sum(r["examined"] for r in rows)
        f.write(f"Detektoren: {len(rows)} | geprueft: {tot_ex} | FP: **{tot_fp}** "
                f"({tot_fp/(tot_ex or 1):.0%} der Stichprobe)\n\n")
        f.write("| Detektor | Name | error+warn | err | geprueft | FP | TP | UNS | FP-Rate | ~Gesamt-FP | TODO |\n")
        f.write("|---|---|--:|--:|--:|--:|--:|--:|--:|--:|---|\n")
        for r in rows:
            todo = f"Todo_FP_{r['id']}_{safe(r['name'])}.md" if r["fp"] else "-"
            f.write(f"| {r['id']} | {r['name'][:32]} | {r['total']} | {r['errors']} | "
                    f"{r['examined']} | {r['fp']} | {r['tp']} | {r['unsure']} | "
                    f"{r['fp_rate']:.0%} | {r['est_fp']} | {todo} |\n")

    print(f"Aggregat: {agg}")
    print(f"FP-TODO-Dateien: {sum(1 for r in rows if r['fp'])}")
    print(f"Gesamt-FP (Stichprobe): {sum(r['fp'] for r in rows)} / geprueft {sum(r['examined'] for r in rows)}")
    print("\nTop-10 nach FP-Zahl:")
    for r in rows[:10]:
        print(f"  {r['id']:<8}{r['name'][:34]:<35}FP {r['fp']:>3}/{r['examined']:<3}  ~ges {r['est_fp']}")


if __name__ == "__main__":
    main()
