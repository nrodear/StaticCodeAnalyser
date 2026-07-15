#!/usr/bin/env python3
"""Recall-Messung Schritt 2: Mutations-SARIF auswerten.

Fuer jeden Mutanten: hat die erwartete Regel im MUTANTEN oefter gefeuert als in der
unveraenderten KONTROLL-Kopie? Nur dann ist der injizierte Bug tatsaechlich erkannt.
Die Differenz-Bildung ist wichtig - eine Datei kann dieselbe Regel schon vorher
ausgeloest haben; ohne Kontrolle wuerde man das als Treffer fehlzaehlen.

  Recall(Detektor) = erkannte Mutationen / injizierte Mutationen

Usage:
  python tools/recall_score.py --sarif sca-mutants.sarif --manifest mutants/_manifest.json
"""
import argparse, json, collections, re

RID = re.compile(r'"ruleId":\s*"(SCA\d+)"')
URI = re.compile(r'"uri":\s*"([^"]+)"')
LNR = re.compile(r'"startLine":\s*(\d+)')


def norm(p):
    return p.replace("\\/", "/").replace("\\", "/")


def load_sarif(path, key='folder'):
    """-> {(ruleId, key): count}.

    key='folder' : Ordnername (isolierter Mutanten-Modus, 1 Datei je Ordner)
    key='rel'    : voller relativer Pfad (--in-corpus-Modus; Mutanten-Kopie und
                   Baseline haben identische rel. Pfade, weil Spiegel)
    """
    counts = collections.Counter()
    cur = uri = None
    for ln in open(path, encoding='utf-8-sig', errors='replace'):
        m = RID.search(ln)
        if m:
            cur = m.group(1); uri = None; continue
        if cur is None:
            continue
        mu = URI.search(ln)
        if mu and uri is None:
            uri = norm(mu.group(1)); continue
        if LNR.search(ln):
            if uri:
                if key == 'rel':
                    counts[(cur, uri.lstrip('./'))] += 1
                else:
                    parts = uri.split('/')
                    counts[(cur, parts[-2] if len(parts) >= 2 else '')] += 1
            cur = None
    return counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sarif', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--baseline', default=None,
                    help='--in-corpus-Modus: SARIF des UNMUTIERTEN Korpus. Dann wird pro '
                         'relativem Pfad Mutant-vs-Baseline verglichen (statt Kontroll-Kopie).')
    ap.add_argument('--show-missed', type=int, default=6)
    args = ap.parse_args()

    in_corpus = args.baseline is not None
    counts = load_sarif(args.sarif, 'rel' if in_corpus else 'folder')
    base = load_sarif(args.baseline, 'rel') if in_corpus else None
    man = json.load(open(args.manifest, encoding='utf-8'))

    per = collections.defaultdict(lambda: {'n': 0, 'hit': 0, 'missed': []})
    for e in man:
        rule = e['expected_rule']
        if in_corpus:
            rel = e['rel'].lstrip('./')
            cm = counts[(rule, rel)]
            cc = base[(rule, rel)]
            src = rel
        else:
            cm = counts[(rule, e['mutant'].split('/')[0])]
            cc = counts[(rule, e['control'].split('/')[0])]
            src = e['source']
        rec = per[e['mutation']]
        rec['n'] += 1
        rec['rule'] = rule
        rec['what'] = e['what']
        if cm > cc:
            rec['hit'] += 1
        else:
            rec['missed'].append((e['id'], src, e['detail'], cm, cc))

    print("=" * 82)
    print("RECALL (Mutation Testing) - injizierte Bugs, die der Scanner findet")
    print("=" * 82)
    tot_n = tot_h = 0
    for mid in sorted(per):
        r = per[mid]
        tot_n += r['n']; tot_h += r['hit']
        pct = 100.0 * r['hit'] / r['n'] if r['n'] else 0.0
        bar = '#' * int(pct / 5)
        print(f"\n{mid}  {r['rule']}  {r['what']}")
        print(f"  Recall: {r['hit']:>3}/{r['n']:<3} = {pct:5.1f} %  {bar}")
        if r['missed'] and args.show_missed:
            print(f"  NICHT erkannt (Stichprobe):")
            for i, (mid2, src, detail, cm, cc) in enumerate(r['missed'][:args.show_missed]):
                print(f"    - {src.split('/')[-1]:<32} {detail[:52]}  [mut={cm} ctrl={cc}]")
    pct = 100.0 * tot_h / tot_n if tot_n else 0.0
    print("\n" + "-" * 82)
    print(f"GESAMT: {tot_h}/{tot_n} = {pct:.1f} % der injizierten Bugs erkannt")


if __name__ == '__main__':
    main()
