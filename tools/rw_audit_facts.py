#!/usr/bin/env python
"""Erzeugt Todo_FactsDetector_<datum>.md aus den Audit-Protokollen.

Liest ausschliesslich die Verdikt-Tabellen der
Todo_Funde_Detector_<SCAxxx>_<datum>.md und das _manifest.json der
Stichprobe - keine Modell-Schaetzung, keine Interpretation. Ergebnis sind
drei Sichten auf dieselben Zahlen: nach Fundzahl, nach FP-Quote und nach
hochgerechneter FP-Masse (Quote x Fundzahl = Arbeits-Reihenfolge).

Beispiel:
  python tools/rw_audit_facts.py --samples .audit/20260815 \
      --protocols "Todo_Funde_Detector_SCA*_2026-08-15.md" \
      --date 2026-08-16 --sarif sca-rw-audit20260815.sarif \
      --compare "Todo_Funde_Detector_SCA*_2026-07-31.md"
"""
import argparse
import glob
import io
import json
import os
import re

ROW_RX = re.compile(r'^\|\s*(FP|TP|unsicher)\s*\|', re.M)


def verdicts(pattern):
    out = {}
    for p in sorted(glob.glob(pattern)):
        rid = re.search(r'SCA\d+', os.path.basename(p))
        if not rid:
            continue
        rows = ROW_RX.findall(io.open(p, encoding='utf-8').read())
        tp = rows.count('TP')
        fp = rows.count('FP')
        un = rows.count('unsicher')
        if tp + fp + un:
            out[rid.group(0)] = (tp, fp, un)
    return out


def de(n):
    return format(n, ',d').replace(',', '.')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--samples', required=True, help='Verzeichnis mit _manifest.json')
    ap.add_argument('--protocols', required=True)
    ap.add_argument('--date', required=True, help='Datum im Dateinamen, z.B. 2026-08-16')
    ap.add_argument('--sarif', default='')
    ap.add_argument('--compare', default='', help='Glob eines Vor-Audits')
    ap.add_argument('--stage2', default='',
                    help='Glob der Stufe-2-Protokolle. Die Stichproben beider '
                         'Stufen sind zufaellig und disjunkt, ihre Verdikte '
                         'werden daher schlicht addiert.')
    ap.add_argument('--out', default='')
    args = ap.parse_args()

    man = {m['rule']: m for m in
           json.load(io.open(os.path.join(args.samples, '_manifest.json'),
                             encoding='utf-8'))}
    neu = verdicts(args.protocols)
    alt = verdicts(args.compare) if args.compare else {}
    s2 = verdicts(args.stage2) if args.stage2 else {}

    rows = []
    for rid, (tp, fp, un) in neu.items():
        m = man.get(rid)
        if not m:
            continue
        sample = json.load(io.open(os.path.join(args.samples, rid + '.json'),
                                   encoding='utf-8'))
        tier = max(('Error', m.get('error', 0)), ('Warning', m.get('warning', 0)),
                   ('Note', m.get('note', 0)), key=lambda x: x[1])[0]
        q = 100.0 * fp / (fp + tp) if (fp + tp) else 0.0
        aq = None
        if rid in alt and sum(alt[rid][:2]):
            aq = 100.0 * alt[rid][1] / (alt[rid][0] + alt[rid][1])
        t2, f2, u2 = s2.get(rid, (0, 0, 0))
        ges_tp, ges_fp = tp + t2, fp + f2
        gq = 100.0 * ges_fp / (ges_fp + ges_tp) if (ges_fp + ges_tp) else 0.0
        rows.append(dict(rule=rid, name=m.get('name', '?'), tier=tier,
                         total=m['total'], drawn=sample.get('drawn', 0),
                         pruef=tp + fp + un, tp=tp, fp=fp, un=un, q=q, alt=aq,
                         s2pruef=t2 + f2 + u2, s2fp=f2,
                         s2q=(100.0 * f2 / (f2 + t2)) if (f2 + t2) else None,
                         gesq=gq, gespruef=tp + fp + un + t2 + f2 + u2,
                         masse=gq / 100.0 * m['total']))

    rows.sort(key=lambda r: -r['total'])
    T = sum(r['total'] for r in rows)
    P = sum(r['pruef'] for r in rows)
    TP = sum(r['tp'] for r in rows)
    FP = sum(r['fp'] for r in rows)
    UN = sum(r['un'] for r in rows)
    D = sum(r['drawn'] for r in rows)
    masse = sum(r['masse'] for r in rows)
    S2P = sum(r['s2pruef'] for r in rows)
    S2F = sum(r['s2fp'] for r in rows)
    GTP = sum(r['tp'] for r in rows) + sum(r['s2pruef'] - r['s2fp'] for r in rows)
    GFP = FP + S2F

    L = ['# Todo FactsDetector - Fundzahlen und FP-Quoten je Detektor (%s)' % args.date, '']
    if args.sarif:
        L += ['> Datenbasis: `%s`' % args.sarif]
    L += ['> Stichprobe und Verdikte: siehe HowTo_RealWorldAudit.md.',
          '> **Quote = FP / (FP + TP) der GEPRUEFTEN Funde.** Bei kleiner',
          '> Stichprobe ist eine einzelne Regelquote eine Groessenordnung -',
          '> belastbar ist die Summenzeile.', '',
          '## Gesamtbild', '', '| Kennzahl | Wert |', '|---|---|',
          '| Detektoren mit Funden | %d |' % len(rows),
          '| Funde im Korpus | %s |' % de(T),
          '| Stichprobe gezogen | %s |' % de(D),
          '| Im Detail geprueft | %d |' % P,
          '| davon TP / FP / unsicher | %d / %d / %d |' % (TP, FP, UN),
          '| **FP-Quote Stufe 1 (geprueft)** | **%.1f %%** |' % (100.0 * FP / (FP + TP)),
          '| FP-Quote auf den Korpus hochgerechnet | %.1f %% (~%s von %s) |'
          % (100.0 * masse / T, de(int(masse)), de(T)), '']
    if S2P:
        L[-1:-1] = ['| Stufe 2: zusaetzlich geprueft | %d (in %d Detektoren) |'
                    % (S2P, sum(1 for r in rows if r['s2pruef'])),
                    '| **FP-Quote Stufe 1 + 2 zusammen** | **%.1f %%** (%d FP / %d) |'
                    % (100.0 * GFP / (GFP + GTP), GFP, GFP + GTP)]
    for t in ('Error', 'Warning', 'Note'):
        sub = [r for r in rows if r['tier'] == t]
        f = sum(r['fp'] for r in sub)
        v = f + sum(r['tp'] for r in sub)
        if sub:
            L.append('* **%s-Tier**: %d Regeln, %s Funde, %d geprueft, FP %.1f %%'
                     % (t, len(sub), de(sum(r['total'] for r in sub)),
                        sum(r['pruef'] for r in sub), 100.0 * f / v if v else 0))
    clean = [r for r in rows if r['q'] == 0]
    L.append('* **Ohne FP im Sample**: %d von %d Regeln, %s Funde (%.0f %% der Masse)'
             % (len(clean), len(rows), de(sum(r['total'] for r in clean)),
                100.0 * sum(r['total'] for r in clean) / T))
    gem = [r for r in rows if r['alt'] is not None]
    if gem:
        af = sum(alt[r['rule']][1] for r in gem)
        av = af + sum(alt[r['rule']][0] for r in gem)
        nf = sum(r['fp'] for r in gem)
        nv = nf + sum(r['tp'] for r in gem)
        L.append('* **Gleiche Regelbasis wie Vor-Audit** (%d Regeln): %.1f %% -> %.1f %%'
                 % (len(gem), 100.0 * af / av, 100.0 * nf / nv))

    if S2P:
        L += ['', '## Stufe 2 - die vertieften Detektoren', '',
              '| Regel | Detektor | Tier | Funde | S1 geprueft | S1-Quote | S2 geprueft | S2-Quote | zusammen | Gesamt-Quote |',
              '|---|---|---|---:|---:|---:|---:|---:|---:|---:|']
        for r in sorted([x for x in rows if x['s2pruef']], key=lambda x: -x['gesq']):
            L.append('| %s | %s | %s | %s | %d | %.0f %% | %d | %.0f %% | %d | **%.0f %%** |'
                     % (r['rule'], r['name'], r['tier'], de(r['total']), r['pruef'],
                        r['q'], r['s2pruef'], r['s2q'] if r['s2q'] is not None else 0,
                        r['gespruef'], r['gesq']))

    L += ['', '## Alle Detektoren, nach Fundzahl', '',
          '| Regel | Detektor | Tier | Funde | gezogen | geprueft | TP | FP | unsicher | FP-Quote | Vor-Audit |',
          '|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for r in rows:
        L.append('| %s | %s | %s | %s | %d | %d | %d | %d | %d | %.0f %% | %s |'
                 % (r['rule'], r['name'], r['tier'], de(r['total']), r['drawn'],
                    r['pruef'], r['tp'], r['fp'], r['un'], r['q'],
                    ('%.0f %%' % r['alt']) if r['alt'] is not None else '-'))
    L.append('| **Summe** | **%d Detektoren** | | **%s** | **%d** | **%d** | **%d** | **%d** | **%d** | **%.1f %%** | |'
             % (len(rows), de(T), D, P, TP, FP, UN, 100.0 * FP / (FP + TP)))

    L += ['', '## Dieselben Daten, nach FP-Quote', '',
          '| Regel | Detektor | Tier | Funde | geprueft | FP | Quote | ~FP-Masse |',
          '|---|---|---|---:|---:|---:|---:|---:|']
    for r in sorted(rows, key=lambda r: (-r['q'], -r['total'])):
        L.append('| %s | %s | %s | %s | %d | %d | %.0f %% | ~%s |'
                 % (r['rule'], r['name'], r['tier'], de(r['total']), r['pruef'],
                    r['fp'], r['q'], de(int(r['masse']))))

    L += ['', '## Nach hochgerechneter FP-Masse (Arbeits-Reihenfolge)', '',
          '| Regel | Detektor | Tier | Funde | Quote | ~FP im Korpus |',
          '|---|---|---|---:|---:|---:|']
    for r in sorted(rows, key=lambda r: -r['masse'])[:25]:
        if r['masse'] < 1:
            break
        L.append('| %s | %s | %s | %s | %.0f %% | ~%s |'
                 % (r['rule'], r['name'], r['tier'], de(r['total']), r['q'],
                    de(int(r['masse']))))

    out = args.out or ('Todo_FactsDetector_%s.md' % args.date)
    io.open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(L) + '\n')
    print('geschrieben: %s (%d Regeln, %d Funde, %d geprueft, FP %.1f %%)'
          % (out, len(rows), T, P, 100.0 * FP / (FP + TP)))


if __name__ == '__main__':
    main()
