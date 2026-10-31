#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Identitaets-Vergleich der Ergebnisse zweier oder mehr rdxperf-Laeufe.

Aufruf (von run_rdxperf.sh bei mehreren Modi, auch von Hand):

    python -I compare_res.py <a.csv.res> <b.csv.res> [...]

Je Fundstelle schreibt rdxperf eine Zeile (Datei, Zeile, Regel, dann
LineMarker, FileMarker, jeder Map-Planer, Kontext-Laeufer, Plattenblick).
Die Modi (file/provide/old) muessen dieselben Zeilen liefern - einzige
erlaubte Abweichung ist die GUID, die der SCA197-Planer (InterfaceGuid,
CreateGUID) je Aufruf neu erzeugt; sie wird vor dem Vergleich zu
{GUID} normalisiert. Exit 0 = alle gleich, 1 = Abweichung (die ersten
Unterschiede werden gezeigt), 2 = Aufruffehler.
"""
import hashlib
import re
import sys

GUID = re.compile(r'\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
                  r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}')
SHOW = 5


def normalized(path):
    with open(path, encoding='utf-8-sig', errors='replace') as f:
        return [GUID.sub('{GUID}', line.rstrip('\r\n')) for line in f]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    ref_path = sys.argv[1]
    ref = normalized(ref_path)
    guids = sum(1 for line in ref if '{GUID}' in line)
    digest = hashlib.md5('\n'.join(ref).encode('utf-8')).hexdigest()
    print('Referenz %s: %d Fundstellen, %d mit GUID, md5 %s'
          % (ref_path, len(ref), guids, digest))
    bad = 0
    for path in sys.argv[2:]:
        other = normalized(path)
        diffs = [i for i in range(max(len(ref), len(other)))
                 if i >= len(ref) or i >= len(other) or ref[i] != other[i]]
        if not diffs:
            print('  gleich: %s' % path)
            continue
        bad += 1
        print('  ABWEICHUNG: %s - %d Zeilen (Referenz %d, hier %d)'
              % (path, len(diffs), len(ref), len(other)))
        for i in diffs[:SHOW]:
            print('    Zeile %d' % (i + 1))
            print('      ref : %s' % (ref[i][:400] if i < len(ref) else '<fehlt>'))
            print('      hier: %s' % (other[i][:400] if i < len(other) else '<fehlt>'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
