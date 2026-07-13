#!/usr/bin/env python3
"""Bettet Code-Kontext in die sca-sample/<SCAxxx>.json ein, damit die Verify-
Agenten self-contained urteilen koennen (kein Zugriff auf Korpus-Dateien
ausserhalb der Workspace noetig). Fenster: BEFORE Zeilen davor .. AFTER danach,
mit 1-basierten Zeilennummern; die Fundzeile ist mit '>>' markiert.
"""
import argparse, glob, json, os

BEFORE, AFTER = 45, 45


def read_lines(path):
    with open(path, "rb") as f:
        raw = f.read()
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(enc).splitlines()
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1", "replace").splitlines()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default=r"D:\git-demos\delphi")
    ap.add_argument("--dir", default="sca-sample")
    ap.add_argument("--before", type=int, default=BEFORE)
    ap.add_argument("--after", type=int, default=AFTER)
    args = ap.parse_args()

    cache = {}
    files = [f for f in glob.glob(os.path.join(args.dir, "*.json"))
             if not f.endswith("_manifest.json")]
    enriched = missing = 0
    for jf in files:
        rec = json.load(open(jf, encoding="utf-8"))
        for fd in rec["findings"]:
            rel = fd["file"]
            absp = os.path.join(args.corpus, rel)
            if absp not in cache:
                cache[absp] = read_lines(absp) if os.path.exists(absp) else None
            lines = cache[absp]
            ln = int(fd.get("line") or 0)
            if not lines or ln <= 0:
                fd["context"] = "(Quelle nicht lesbar / keine Zeile)"
                missing += 1
                continue
            lo = max(1, ln - args.before)
            hi = min(len(lines), ln + args.after)
            buf = []
            for i in range(lo, hi + 1):
                mark = ">>" if i == ln else "  "
                buf.append(f"{mark}{i:6}: {lines[i-1]}")
            fd["context"] = "\n".join(buf)
            enriched += 1
        json.dump(rec, open(jf, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"Kontext eingebettet: {enriched} Funde | ohne Quelle: {missing} | Files gecacht: {len(cache)}")


if __name__ == "__main__":
    main()
