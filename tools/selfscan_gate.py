# -*- coding: utf-8 -*-
"""Dogfooding-Gate: der Analyser ueber den eigenen Quelltext.

WARUM NICHT --write-baseline: eine Baseline-JSON mit ueber dreitausend
Einzelfunden ist im Repo weder lesbar noch als Diff brauchbar - jede
Zeilenverschiebung im Quelltext bewegt sie. Dieses Gate arbeitet auf
REGEL-Ebene: je Regel eine Zahl. Das ist die Invariante, die tatsaechlich
etwas aussagt ("keine Regel wurde schlechter"), und sie ueberlebt
Umformatierungen.

EXIT-CODE
  0  keine Regel hat mehr Funde als in der Baseline
  1  mindestens eine Regel ist schlechter geworden
  2  Aufruf- oder Laufzeitfehler (Exe fehlt, Scan gescheitert)

Weniger Funde oder eine neue Regel lassen das Gate GRUEN - der Sinn ist,
Rueckschritte zu fangen, nicht Fortschritt zu verbieten. Wer die Baseline
nachziehen will: --update.

    python tools/selfscan_gate.py [--exe <pfad>] [--update]
"""
import argparse
import io
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(REPO, 'selfscan-baseline.txt')
DEFAULT_EXES = [
    os.path.join(REPO, 'Output', 'Win64 Release', 'StaticCodeAnalyser.d12.exe'),
    os.path.join(REPO, 'Output', 'Win32 Release', 'StaticCodeAnalyser.d12.exe'),
]
# 'Error  <pfad>:<zeile>  <Regel>  <text>'
LINE = re.compile(r'^(Error|Warning|Hint|Read Error)\s+\S+\s+(\w+)\s', re.M)
SUMMARY = re.compile(
    r'Summary:\s*(\d+)\s*Error\(s\),\s*(\d+)\s*Warning\(s\),\s*'
    r'(\d+)\s*Hint\(s\)')


def find_exe(explicit):
    if explicit:
        if not os.path.isfile(explicit):
            sys.exit('Exe nicht gefunden: %s' % explicit)
        return explicit
    for p in DEFAULT_EXES:
        if os.path.isfile(p):
            return p
    sys.exit('Keine gebaute Exe gefunden. Erst bauen, oder --exe angeben.\n'
             'Gesucht in:\n  ' + '\n  '.join(DEFAULT_EXES))


def scan(exe):
    """Self-Scan mit dem STRICT-Profil - das Gate soll alles sehen, auch
    was 'default' seit 2026-08-02 bewusst weglaesst."""
    out = subprocess.run(
        [exe, '--path', REPO, '--profile', 'strict', '--min-severity', 'hint'],
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    # NICHT am Exit-Code festmachen: der traegt die Fail-On-Politik der CLI
    # (Funde oberhalb einer Schwelle -> Exit <> 0) und sagt nichts darueber,
    # ob der Scan ueberhaupt durchlief. Die Summary-Zeile ist das
    # belastbare Signal.
    m = SUMMARY.search(out.stdout)
    if m is None:
        sys.exit('Scan lieferte keine Summary-Zeile (Exit %d):\n%s'
                 % (out.returncode, (out.stderr or out.stdout)[-2000:]))
    counts = {}
    for _sev, rule in LINE.findall(out.stdout):
        counts[rule] = counts.get(rule, 0) + 1
    return counts, tuple(int(x) for x in m.groups())


def load_baseline():
    if not os.path.isfile(BASELINE):
        return None, None
    counts, tiers = {}, None
    for raw in io.open(BASELINE, encoding='utf-8'):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('TIERS'):
            tiers = tuple(int(x) for x in line.split()[1:4])
            continue
        rule, n = line.split()
        counts[rule] = int(n)
    return counts, tiers


def write_baseline(counts, tiers):
    with io.open(BASELINE, 'w', encoding='utf-8', newline='\r\n') as fh:
        fh.write('# Dogfooding-Baseline - Funde je Regel im EIGENEN Quelltext.\n')
        fh.write('# Erzeugt von tools/selfscan_gate.py --update (Profil strict).\n')
        fh.write('# Das Gate schlaegt fehl, wenn eine Regel MEHR Funde hat als\n')
        fh.write('# hier. Weniger ist immer erlaubt.\n')
        fh.write('TIERS %d %d %d\n' % tiers)
        for rule in sorted(counts):
            fh.write('%s %d\n' % (rule, counts[rule]))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--exe')
    ap.add_argument('--update', action='store_true',
                    help='Baseline auf den aktuellen Stand schreiben')
    args = ap.parse_args()

    exe = find_exe(args.exe)
    counts, tiers = scan(exe)
    print('Self-Scan: %d Error, %d Warning, %d Hint ueber %d Regeln'
          % (tiers[0], tiers[1], tiers[2], len(counts)))

    if args.update:
        write_baseline(counts, tiers)
        print('Baseline geschrieben: %s' % os.path.relpath(BASELINE, REPO))
        return 0

    base, base_tiers = load_baseline()
    if base is None:
        print('Keine Baseline vorhanden - einmal mit --update erzeugen.')
        return 2

    worse = [(r, base.get(r, 0), n) for r, n in sorted(counts.items())
             if n > base.get(r, 0)]
    better = [(r, base[r], counts.get(r, 0)) for r in sorted(base)
              if counts.get(r, 0) < base[r]]

    if base_tiers and tiers[0] > base_tiers[0]:
        print('FEHLER: Fehler-Tier gestiegen: %d -> %d' % (base_tiers[0], tiers[0]))

    for r, was, now in better:
        print('  besser  %-26s %4d -> %4d' % (r, was, now))
    for r, was, now in worse:
        print('  SCHLECHTER %-23s %4d -> %4d' % (r, was, now))

    if worse or (base_tiers and tiers[0] > base_tiers[0]):
        print('\nGATE ROT: %d Regel(n) schlechter. Entweder beheben, oder die\n'
              'Verschlechterung begruenden und die Baseline mit --update\n'
              'nachziehen.' % len(worse))
        return 1
    print('\nGATE GRUEN: keine Regel schlechter als die Baseline.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
