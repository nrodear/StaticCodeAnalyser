#!/usr/bin/env python
"""Stichprobenzieher fuer den zweistufigen Real-World-FP-Audit.

Stufe 1: zieht je Detektor 30 % der Funde (Cap fuer die Detailpruefung),
         schreibt je Regel eine Sample-JSON mit der EXAKTEN POSITION jedes
         Fundes (Datei + Zeile). Diese Position ist das Gedaechtnis des
         Audits - Stufe 2 erkennt daran, was schon geprueft wurde.

Stufe 2: liest die Stufe-1-Protokolle, waehlt die nachpruefungswuerdigen
         Detektoren (Quote ueber Schwelle, kein Note-Tier, genug Funde) und
         zieht je Detektor weitere Funde AUS DER NOCH UNGEPRUEFTEN MENGE.

Warum ein eigener Parser statt json.load: die Korpus-SARIFs sind ~700 MB;
sie komplett zu laden sprengt den Speicher. Gelesen wird streamend in
64-MB-Bloecken mit Uebertrag, ein globales Wasserzeichen verhindert
Doppelzaehlung an den Blockgrenzen (grep -o zaehlt auf diesen Dateien
nachweislich ~29 % zu wenig - siehe HowTo_RealWorldAudit.md).

Beispiele:
  python tools/rw_audit_sample.py --sarif sca-rw-audit20260815.sarif \
      --stage 1 --seed 20260815 --out .audit/20260815
  python tools/rw_audit_sample.py --sarif sca-rw-audit20260815.sarif \
      --stage 2 --seed 20260815 --out .audit/20260815 \
      --protocols "Todo_Funde_Detector_SCA*_2026-08-15.md"
"""
import argparse
import collections
import glob
import io
import json
import os
import random
import re

RESULT_RX = re.compile(
    rb'"ruleId":\s*"(SCA\d+)",\s*"level":\s*"(\w+)",\s*"message":\s*\{\s*'
    rb'"text":\s*"((?:[^"\\]|\\.){0,400}?)"\s*\},\s*"locations":\s*\[\s*\{\s*'
    rb'"physicalLocation":\s*\{\s*"artifactLocation":\s*\{\s*'
    rb'"uri":\s*"((?:[^"\\]|\\.)*)"\s*\},\s*"region":\s*\{\s*'
    rb'"startLine":\s*(\d+)', re.S)
CHUNK = 64 * 1024 * 1024
TAIL = 8192          # laenger als jeder erwartbare Treffer
PROTO_ROW_RX = re.compile(r'^\|\s*(FP|TP|unsicher)\s*\|\s*([^|]+?):(\d+)\s*\|', re.M)


def unescape(raw):
    return (raw.decode('utf-8', 'replace')
            .replace('\\/', '/').replace('\\"', '"').replace('\\\\', '\\'))


def read_findings(path):
    """Alle results des SARIF als {rule: [(level, file, line, message), ...]}."""
    per_rule = collections.defaultdict(list)
    watermark, pos, leftover = -1, 0, b''
    with io.open(path, 'rb') as f:
        while True:
            block = f.read(CHUNK)
            eof = not block
            buf = leftover + block
            limit = len(buf) if eof else max(len(buf) - TAIL, 0)
            for m in RESULT_RX.finditer(buf):
                if m.end() > limit:
                    break
                if pos + m.end() > watermark:
                    per_rule[m.group(1).decode()].append(
                        (m.group(2).decode(), unescape(m.group(4)),
                         int(m.group(5)), unescape(m.group(3))))
                    watermark = pos + m.end()
            if eof:
                break
            keep = max(len(buf) - 2 * TAIL, 0)
            leftover, pos = buf[keep:], pos + keep
    return per_rule


def rule_names(catalog):
    out = {}
    if catalog and os.path.exists(catalog):
        data = json.load(io.open(catalog, encoding='utf-8-sig'))
        for r in data.get('rules', []):
            out[r.get('id')] = r.get('kind', r.get('name', '?'))
    return out


def dominant_tier(levels):
    c = collections.Counter(levels)
    return max(('Error', c.get('error', 0)), ('Warning', c.get('warning', 0)),
               ('Note', c.get('note', 0)), key=lambda x: x[1])[0]


def keys(path, line):
    """Zwei Schluessel je Position: voller Pfad UND Dateiname.

    Auditoren kuerzen Pfade in ihren Protokollen gelegentlich
    ('mORMot2/src/...' statt 'mORMot2-2.4-stable/mORMot2-2.4-stable/src/...').
    Ein rein exakter Abgleich wuerde solche Zeilen nicht wiedererkennen und
    denselben Fund in Stufe 2 ein zweites Mal vorlegen. Der Dateiname-Schluessel
    faengt das ab. Die Richtung des Restrisikos ist bewusst gewaehlt: zwei
    gleichnamige Dateien in derselben Zeile schliessen einen Fund zu viel aus
    (harmlos, die Grundgesamtheit schrumpft minimal) - eine Doppelpruefung
    waere der teure Fehler.
    """
    p = path.replace('/', '\\').lower().lstrip('\\')
    return (p, int(line)), (p.rsplit('\\', 1)[-1], int(line))


def read_protocols(pattern):
    """{rule: {'quote': float, 'checked': set(schluessel)}} aus Stufe 1."""
    out = {}
    for p in sorted(glob.glob(pattern)):
        rid = re.search(r'SCA\d+', os.path.basename(p))
        if not rid:
            continue
        text = io.open(p, encoding='utf-8').read()
        rows = PROTO_ROW_RX.findall(text)
        tp = sum(1 for v, _, _ in rows if v == 'TP')
        fp = sum(1 for v, _, _ in rows if v == 'FP')
        checked = set()
        for _, f, l in rows:
            checked.update(keys(f.strip(), l))
        out[rid.group(0)] = {
            'quote': (100.0 * fp / (fp + tp)) if (fp + tp) else 0.0,
            'tp': tp, 'fp': fp, 'rows': len(rows), 'checked': checked,
        }
    return out


def write_samples(outdir, entries, manifest, extra=None):
    os.makedirs(outdir, exist_ok=True)
    for e in entries:
        io.open(os.path.join(outdir, e['rule'] + '.json'), 'w',
                encoding='utf-8').write(json.dumps(e, ensure_ascii=False, indent=1))
    io.open(os.path.join(outdir, '_manifest.json'), 'w',
            encoding='utf-8').write(json.dumps(manifest, ensure_ascii=False, indent=1))
    if extra is not None:
        io.open(os.path.join(outdir, '_skipped.json'), 'w',
                encoding='utf-8').write(json.dumps(extra, ensure_ascii=False, indent=1))


def make_jobs(outdir, manifest, max_verdicts, max_rules):
    """Bin-Packing der Regeln zu Auditor-Jobs (gleichmaessige Last)."""
    bins = []
    for m in sorted(manifest, key=lambda m: -m['detail']):
        for b in bins:
            if (sum(x['detail'] for x in b) + m['detail'] <= max_verdicts
                    and len(b) < max_rules):
                b.append(m)
                break
        else:
            bins.append([m])
    jobs = [{'job': i + 1, 'rules': [x['rule'] for x in b],
             'verdicts': sum(x['detail'] for x in b)}
            for i, b in enumerate(bins)]
    io.open(os.path.join(outdir, '_jobs.json'), 'w',
            encoding='utf-8').write(json.dumps(jobs, ensure_ascii=False, indent=1))
    return jobs


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--sarif', required=True)
    ap.add_argument('--stage', type=int, choices=(1, 2), required=True)
    ap.add_argument('--seed', type=int, required=True,
                    help='reproduzierbar: Datum als Zahl, z.B. 20260815')
    ap.add_argument('--out', required=True, help='Zielverzeichnis der Sample-JSONs')
    ap.add_argument('--rules-json', default='rules/sca-rules.json')
    ap.add_argument('--protocols', default='',
                    help='Stufe 2: Glob der Stufe-1-Protokolle')
    ap.add_argument('--fraction', type=float, default=0.30, help='Stufe 1')
    ap.add_argument('--cap', type=int, default=24, help='Stufe 1: Detail-Cap')
    ap.add_argument('--stage2-cap', type=int, default=50)
    ap.add_argument('--min-quote', type=float, default=33.0,
                    help='Stufe 2: nur Regeln oberhalb dieser Quote')
    ap.add_argument('--min-total', type=int, default=50,
                    help='Stufe 2: Regeln mit hoechstens so vielen Funden werden '
                         'nur gelistet, nicht erneut geprueft')
    ap.add_argument('--job-verdicts', type=int, default=75)
    ap.add_argument('--job-rules', type=int, default=5)
    args = ap.parse_args()

    per_rule = read_findings(args.sarif)
    names = rule_names(args.rules_json)
    total_findings = sum(len(v) for v in per_rule.values())
    print('SARIF: %d Regeln, %d Funde' % (len(per_rule), total_findings))

    entries, manifest, skipped = [], [], []

    if args.stage == 1:
        for rid in sorted(per_rule):
            items = per_rule[rid]
            rng = random.Random(args.seed + int(rid[3:]))
            n = max(1, int(round(len(items) * args.fraction)))
            drawn = rng.sample(items, n) if len(items) > 1 else list(items)
            detail = drawn[:args.cap]
            tiers = collections.Counter(lv for lv, _, _, _ in items)
            entries.append(dict(
                rule=rid, name=names.get(rid, '?'), stage=1, seed=args.seed,
                total=len(items), error=tiers.get('error', 0),
                warning=tiers.get('warning', 0), note=tiers.get('note', 0),
                drawn=len(drawn), detail=len(detail),
                sample=[dict(level=lv, file=u, line=ln, message=msg)
                        for lv, u, ln, msg in detail]))
            manifest.append(dict(rule=rid, name=names.get(rid, '?'),
                                 total=len(items), error=tiers.get('error', 0),
                                 warning=tiers.get('warning', 0),
                                 note=tiers.get('note', 0), detail=len(detail)))
    else:
        if not args.protocols:
            ap.error('--protocols wird fuer Stufe 2 gebraucht')
        proto = read_protocols(args.protocols)
        if not proto:
            ap.error('keine Stufe-1-Protokolle gefunden: ' + args.protocols)
        for rid in sorted(per_rule):
            items = per_rule[rid]
            info = proto.get(rid)
            if not info:
                continue
            tiers = collections.Counter(lv for lv, _, _, _ in items)
            tier = dominant_tier([lv for lv, _, _, _ in items])
            if tier == 'Note':
                continue                       # eigener Lauf, siehe HowTo
            if info['quote'] <= args.min_quote:
                continue
            if len(items) <= args.min_total:
                skipped.append(dict(rule=rid, name=names.get(rid, '?'), tier=tier,
                                    total=len(items), quote=round(info['quote'], 1),
                                    grund='Grundgesamtheit <= %d Funde - gescannt, '
                                          'keine zweite Fundpruefung' % args.min_total))
                continue
            rest = [it for it in items
                    if not (set(keys(it[1], it[2])) & info['checked'])]
            wieder = len(items) - len(rest)
            if wieder < info['rows']:
                print('  ! %s: nur %d von %d Stufe-1-Positionen wiedererkannt - '
                      'Protokoll-Pfade pruefen' % (rid, wieder, info['rows']))
            rng = random.Random(args.seed + 1000 + int(rid[3:]))
            detail = rng.sample(rest, min(args.stage2_cap, len(rest)))
            entries.append(dict(
                rule=rid, name=names.get(rid, '?'), stage=2, seed=args.seed,
                total=len(items), error=tiers.get('error', 0),
                warning=tiers.get('warning', 0), note=tiers.get('note', 0),
                stage1_quote=round(info['quote'], 1),
                stage1_checked=len(info['checked']), pool=len(rest),
                drawn=len(detail), detail=len(detail),
                sample=[dict(level=lv, file=u, line=ln, message=msg)
                        for lv, u, ln, msg in detail]))
            manifest.append(dict(rule=rid, name=names.get(rid, '?'), tier=tier,
                                 total=len(items), stage1_quote=round(info['quote'], 1),
                                 detail=len(detail)))

    write_samples(args.out, entries, manifest, skipped if args.stage == 2 else None)
    jobs = make_jobs(args.out, manifest, args.job_verdicts, args.job_rules)
    print('Stufe %d: %d Regeln, %d Verdikte, %d Jobs -> %s'
          % (args.stage, len(manifest), sum(m['detail'] for m in manifest),
             len(jobs), args.out))
    if skipped:
        print('nur gelistet (Grundgesamtheit <= %d): %s'
              % (args.min_total, ', '.join(s['rule'] for s in skipped)))


if __name__ == '__main__':
    main()
