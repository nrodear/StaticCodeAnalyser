#!/usr/bin/env python3
"""Recall-Messung Schritt 1: Mutations-Korpus erzeugen (Mutation Testing).

WARUM: Die A/B-Set-Diffs messen nur PRECISION-Aenderungen (wurden Funde weniger?).
RECALL - "von den Bugs die es gibt, wie viele findet SCA?" - ist damit NICHT messbar,
weil der Real-World-Korpus kein Ground-Truth-Label hat. Mutation Testing liefert das
Label: wir injizieren einen BEKANNTEN Bug in echten Korpus-Code und pruefen, ob der
Scanner ihn findet. Recall = gefundene / injizierte.

PRINZIP
  * Wir mutieren nur Stellen, an denen der Ziel-Detektor VORHER NICHT feuert - sonst
    ist nicht unterscheidbar, ob der Fund von der Mutation kommt.
  * EINE Mutation pro Mutanten-Datei -> eindeutige Zuordnung Fund <-> Mutation.
  * Jeder Mutant liegt in einem eigenen Unterordner (gleiche Unit-Namen kollidieren
    sonst in der Cross-Unit-Analyse).
  * Gescored wird pro DATEI, nicht pro Zeile: die Mutation verschiebt Zeilen, und
    Detektoren melden mal am Header, mal am Statement. Bei 1 Mutation/Datei ist
    "hat Regel R in dieser Datei gefeuert?" das robuste Kriterium.
  * Kontroll-Kopie je Mutant: gescored wird die DIFFERENZ Mutant-vs-Kontrolle, damit
    bereits vorhandene Funde derselben Regel nicht als Treffer fehlzaehlen.

ZWEI MODI - WELCHER WANN (wichtig, sonst misst man Artefakte)
  DEFAULT (isolierte Mutanten-Ordner): je Mutant nur die mutierte Datei + eine
    Kontroll-Kopie. Nur gueltig fuer DATEI-LOKALE Detektoren (M097/M096: "ruft
    dieser Ctor/Dtor 'inherited'?" braucht keinen Cross-Unit-Kontext).
  --in-corpus (Korpus-Spiegel): Mutationen in einer Kopie des ganzen Korpus
    (.pas/.dfm, ~16k Dateien). PFLICHT fuer Detektoren mit CROSS-UNIT-Wissen -
    z.B. SCA001, das nur Klassen aus `LeakyClasses` flaggt (Liste + AutoDiscovery
    aus dem Scan-Context): fehlt die deklarierende Unit im Scan, kann die Klasse
    nicht entdeckt werden und der Recall waere kuenstlich zu niedrig.
    Gescored wird gegen die unmutierte Baseline-SARIF (gleiche rel. Pfade).
    Selbst-Validierung: Baseline vs Mutanten-Scan darf sich AUSSCHLIESSLICH in den
    mutierten Dateien unterscheiden (2026-07-15 verifiziert: 30/30, 0 Fremd-Diffs).
  Hinweis: {$I}/{$INCLUDE} loest der Lexer NICHT auf (uLexer: "Andere Direktiven
  ignorieren") -> .inc-Dateien muessen nicht gespiegelt werden.

ERGEBNIS DER ERSTMESSUNG (2026-07-15, 50 Mutanten je Klasse)
  M097 SCA097  47/50 = 94 %
  M096 SCA096  39/50 = 78 %   (Misses haeufen sich bei nested classes TFoo.TBar.Create)
  M001 SCA001   9/50 = 18 %   <- MIT vollem Cross-Unit-Kontext bestaetigt, KEIN Artefakt.
     URSACHE: `DEF_AUTO_DISCOVER_CLASSES = False` - die Custom-Class-AutoDiscovery
     ist per DEFAULT AUS (Aktivierung: [Detectors]/AutoDiscoverClasses=1 in
     analyser.ini). Ohne sie kennt SCA001 nur die hartcodierte RTL/VCL-Baseline:
     die 9 Treffer sind ausnahmslos RTL/VCL (TBitmap/TFileStream/TStringList/
     TIniFile), die 41 Misses ausnahmslos Bibliotheks-Klassen (TAL*).
     Das ist kein Detektor-Bug, sondern der bisher UNSICHTBARE Preis einer
     precision-first-Voreinstellung - jetzt beziffert. Naechstes Experiment:
     mit AutoDiscoverClasses=1 erneut messen (Recall-Gewinn) UND den normalen
     Korpus scannen (FP-Kosten) -> der Trade-off wird zweiseitig messbar.

Usage:
  python tools/recall_mutate.py --corpus D:\\git-sca-realworld --out mutants --per-kind 50
"""
import argparse, json, os, re, shutil, sys

# ---------------------------------------------------------------- Mutationen
# Jede Mutation: (id, expected_rule, finder(lines) -> [(mut_lines, detail)])
# finder liefert fuer eine Datei ALLE moeglichen Mutationsstellen.

RE_DTOR = re.compile(r'^\s*destructor\s+([\w.]+)\s*(;|\()', re.I)
RE_CTOR = re.compile(r'^\s*constructor\s+([\w.]+)\s*(;|\()', re.I)
RE_INHERITED = re.compile(r'^\s*inherited\s*(destroy|create)?\s*(\([^)]*\))?\s*;\s*$', re.I)
RE_BEGIN = re.compile(r'^\s*begin\s*$', re.I)
RE_END = re.compile(r'^\s*end\s*;\s*$', re.I)


def _routine_body(lines, hdr_idx, max_scan=90):
    """(begin_idx, end_idx) des Routinen-Bodys ab Header-Index, sonst None."""
    b = None
    for j in range(hdr_idx, min(len(lines), hdr_idx + 20)):
        if RE_BEGIN.match(lines[j]):
            b = j
            break
    if b is None:
        return None
    depth = 1
    for j in range(b + 1, min(len(lines), b + max_scan)):
        s = re.sub(r'//.*$', '', lines[j]).strip()
        if re.match(r'^(begin|try|case)\b', s, re.I):
            depth += 1
        elif re.match(r'^end\b', s, re.I):
            depth -= 1
            if depth == 0:
                return (b, j)
    return None


def _drop_inherited(lines, hdr_re, kind):
    """Entfernt das 'inherited;' aus einem Ctor/Dtor-Body -> Bug ist injiziert."""
    out = []
    for i, ln in enumerate(lines):
        m = hdr_re.match(ln)
        if not m:
            continue
        if ln.strip().endswith('abstract;') or ' external ' in ln.lower():
            continue
        body = _routine_body(lines, i)
        if not body:
            continue
        b, e = body
        inh = [j for j in range(b + 1, e) if RE_INHERITED.match(lines[j])]
        if len(inh) != 1:      # 0 -> Bug existiert schon; >1 -> mehrdeutig
            continue
        j = inh[0]
        mut = lines[:j] + lines[j + 1:]
        out.append((mut, f"{kind} {m.group(1)}: 'inherited' (Zeile {j+1}) entfernt"))
    return out


def mut_097(lines):
    return _drop_inherited(lines, RE_DTOR, 'destructor')


def mut_096(lines):
    return _drop_inherited(lines, RE_CTOR, 'constructor')


RE_CREATE = re.compile(r'^\s*([A-Za-z_]\w*)\s*:=\s*T[\w.]*\.Create\b', re.I)


def mut_001(lines):
    """Kanonisches 'X := TFoo.Create; try ... finally X.Free; end;' zu einem
    ungeschuetzten Create entkleiden -> echtes Leak-Risiko (SCA001-Ziel)."""
    out = []
    for i, ln in enumerate(lines):
        m = RE_CREATE.match(ln)
        if not m:
            continue
        var = m.group(1)
        if i + 1 >= len(lines) or not re.match(r'^\s*try\s*$', lines[i + 1], re.I):
            continue
        # passendes 'finally <var>.Free' + 'end;' suchen
        fin = None
        for j in range(i + 2, min(len(lines), i + 60)):
            if re.match(r'^\s*finally\s*$', lines[j], re.I):
                fin = j
                break
            if re.match(r'^\s*(try|except)\b', lines[j].strip(), re.I):
                break
        if fin is None or fin + 2 >= len(lines):
            continue
        if not re.match(r'^\s*(FreeAndNil\(\s*%s\s*\)|%s\.Free)\s*;\s*$' % (re.escape(var), re.escape(var)),
                        lines[fin + 1], re.I):
            continue
        if not RE_END.match(lines[fin + 2]):
            continue
        # try (i+1), finally (fin), Free (fin+1), end; (fin+2) entfernen ->
        # der Body bleibt, das Objekt wird nie freigegeben.
        mut = (lines[:i + 1] + lines[i + 2:fin] + lines[fin + 3:])
        out.append((mut, f"try/finally um '{var} := T....Create' entfernt (Free weg)"))
    return out


MUTATIONS = [
    ('M097', 'SCA097', mut_097, 'Destructor without inherited call'),
    ('M096', 'SCA096', mut_096, 'Constructor without inherited call'),
    ('M001', 'SCA001', mut_001, 'Object created without try/finally'),
]


# ---------------------------------------------------------------- Korpus-IO
def read_lines(path):
    raw = open(path, 'rb').read()
    for enc in ('utf-8-sig', 'utf-8', 'cp1252', 'latin-1'):
        try:
            return raw.decode(enc).splitlines(), enc
        except Exception:
            continue
    return None, None


def iter_pas(corpus, limit_files=None):
    skip = re.compile(r'[\\/](\.git|__history|__recovery)[\\/]', re.I)
    n = 0
    for root, dirs, files in os.walk(corpus):
        if skip.search(root + os.sep):
            continue
        for f in files:
            if f.lower().endswith('.pas'):
                yield os.path.join(root, f)
                n += 1
                if limit_files and n >= limit_files:
                    return


def mirror_sources(corpus, out):
    """Spiegelt NUR .pas/.dfm des Korpus nach out (Baum-erhaltend).

    Fuer den --in-corpus-Modus: der Scan braucht die Abhaengigkeiten (sonst kann
    z.B. SCA001's LeakyClasses-AutoDiscovery die deklarierende Unit nicht sehen).
    Andere Dateitypen (Bilder, .dcu, Doku) sind fuer den Scan irrelevant -> 13k
    statt 73k Dateien.
    """
    skip = re.compile(r'[\\/](\.git|__history|__recovery)[\\/]', re.I)
    n = 0
    for root, dirs, files in os.walk(corpus):
        if skip.search(root + os.sep):
            continue
        for f in files:
            if not f.lower().endswith(('.pas', '.dfm')):
                continue
            src = os.path.join(root, f)
            rel = os.path.relpath(src, corpus)
            dst = os.path.join(out, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            n += 1
            if n % 2000 == 0:
                print(f"  ... {n} Dateien gespiegelt", flush=True)
    return n


def run_in_corpus(args):
    """Mutationen in einer KORPUS-KOPIE anwenden -> Cross-Unit-Kontext bleibt.

    Gescored wird spaeter gegen die unmutierte Baseline-SARIF des ECHTEN Korpus
    (gleiche relative Pfade, weil Spiegel). Kontroll-Kopien sind hier unnoetig -
    die Baseline IST die Kontrolle.
    """
    print(f"Spiegle {args.corpus} -> {args.out} (nur .pas/.dfm) ...", flush=True)
    n = mirror_sources(args.corpus, args.out)
    print(f"  {n} Dateien gespiegelt.\n")

    only = set(x.strip().upper() for x in args.only.split(',')) if args.only else None
    want = {mid: args.per_kind for mid, _, _, _ in MUTATIONS
            if (only is None or mid in only)}
    manifest = []
    seq = 0
    for path in iter_pas(args.out, None):     # ueber die KOPIE laufen
        if all(v <= 0 for v in want.values()):
            break
        lines, enc = read_lines(path)
        if not lines or len(lines) > 6000:
            continue
        for mid, rule, fn, desc in MUTATIONS:
            if want.get(mid, 0) <= 0:
                continue
            try:
                cands = fn(lines)
            except Exception:
                continue
            if not cands:
                continue
            mut_lines, detail = cands[0]
            seq += 1
            with open(path, 'w', encoding='utf-8') as fh:   # IN-PLACE in der Kopie
                fh.write("\n".join(mut_lines) + "\n")
            rel = os.path.relpath(path, args.out).replace('\\', '/')
            manifest.append({
                'id': f"m{seq:04d}_{mid}",
                'mutation': mid,
                'expected_rule': rule,
                'what': desc,
                'rel': rel,                 # gleiche rel. Pfade wie in der Baseline
                'basename': os.path.basename(path),
                'detail': detail,
            })
            want[mid] -= 1
            break        # nur EINE Mutation pro Datei

    with open(os.path.join(args.out, '_manifest.json'), 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=1)
    print(f"Mutanten (in-corpus): {len(manifest)}")
    for mid in want:
        print(f"  {mid}: {sum(1 for m in manifest if m['mutation'] == mid)}")
    print(f"\nNaechste Schritte:")
    print(f"  1) scannen:  --path {args.out} --full --profile strict --report-sarif sca-mutant-corpus.sarif")
    print(f"  2) scoren :  tools/recall_score.py --sarif sca-mutant-corpus.sarif "
          f"--baseline <baseline.sarif> --manifest {args.out}/_manifest.json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--corpus', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--per-kind', type=int, default=50)
    ap.add_argument('--scan-limit', type=int, default=4000, help='max. Korpus-Files absuchen')
    ap.add_argument('--in-corpus', action='store_true',
                    help='Mutationen in einer Korpus-KOPIE anwenden (noetig fuer Detektoren '
                         'mit Cross-Unit-Wissen, z.B. SCA001/LeakyClasses)')
    ap.add_argument('--only', default=None, help='nur diese Mutationen, z.B. M001')
    args = ap.parse_args()

    if args.in_corpus:
        if os.path.exists(args.out):
            shutil.rmtree(args.out)
        os.makedirs(args.out)
        run_in_corpus(args)
        return

    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    os.makedirs(args.out)

    want = {mid: args.per_kind for mid, _, _, _ in MUTATIONS}
    manifest = []
    seq = 0
    scanned = 0

    for path in iter_pas(args.corpus, args.scan_limit):
        if all(v <= 0 for v in want.values()):
            break
        lines, enc = read_lines(path)
        if not lines or len(lines) > 6000:
            continue
        scanned += 1
        for mid, rule, fn, desc in MUTATIONS:
            if want[mid] <= 0:
                continue
            try:
                cands = fn(lines)
            except Exception:
                continue
            if not cands:
                continue
            mut_lines, detail = cands[0]      # nur die ERSTE Stelle je Datei+Mutation
            seq += 1
            mid_str = f"m{seq:04d}_{mid}"

            # Mutant UND unveraenderte Kontroll-Kopie schreiben. Gescored wird die
            # DIFFERENZ (Mutant vs Kontrolle): so zaehlen bereits vorhandene Funde
            # derselben Regel in dieser Datei nicht faelschlich als "erkannt".
            sub = os.path.join(args.out, mid_str)
            ctl = os.path.join(args.out, 'ctrl_' + mid_str)
            os.makedirs(sub, exist_ok=True)
            os.makedirs(ctl, exist_ok=True)
            dst = os.path.join(sub, os.path.basename(path))
            dctl = os.path.join(ctl, os.path.basename(path))
            with open(dst, 'w', encoding='utf-8') as fh:
                fh.write("\n".join(mut_lines) + "\n")
            with open(dctl, 'w', encoding='utf-8') as fh:
                fh.write("\n".join(lines) + "\n")

            manifest.append({
                'id': mid_str,
                'mutation': mid,
                'expected_rule': rule,
                'what': desc,
                'mutant': os.path.relpath(dst, args.out).replace('\\', '/'),
                'control': os.path.relpath(dctl, args.out).replace('\\', '/'),
                'basename': os.path.basename(path),
                'source': os.path.relpath(path, args.corpus).replace('\\', '/'),
                'detail': detail,
            })
            want[mid] -= 1

    with open(os.path.join(args.out, '_manifest.json'), 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=1)

    print(f"Korpus-Dateien betrachtet: {scanned}")
    print(f"Mutanten erzeugt: {len(manifest)}  ->  {args.out}")
    for mid, rule, _, desc in MUTATIONS:
        n = sum(1 for m in manifest if m['mutation'] == mid)
        print(f"  {mid} ({rule}): {n:>3}   {desc}")
    print("\nNaechster Schritt: Mutanten-Ordner scannen, dann tools/recall_score.py")


if __name__ == '__main__':
    main()
