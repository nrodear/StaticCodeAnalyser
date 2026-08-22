# -*- coding: utf-8 -*-
"""Welche Paket-Artefakte sind aelter als ihre Quelle?

WOZU: Ein Paket, das ein anderes 'requires', zieht dessen Units aus dem
DCP - NICHT aus der Quelle. Ist das DCP aelter als die Quelle, meldet
der Compiler Fehler, die im Quelltext laengst behoben sind. Am
2026-08-22 genau so: 'E2003 Undeklarierter Bezeichner EncodeLineSnapshot'
gegen ein SCA.SharedUI.dcp von 11 Stunden vor der Funktion.

Diese Fehlerklasse ist in diesem Projekt wiederkehrend (F2613,
CLI-Detector-Dropout, TEditSource-Crash - alle drei waren Stale-Builds).
Die Meldung des Compilers zeigt dabei immer auf den FALSCHEN Ort: auf
die Aufrufstelle, nicht auf das veraltete Artefakt.

    python tools/stale_artifacts_check.py

EXIT  0 alles aktueller als die Quelle | 1 veraltete Artefakte | 2 Fehler
"""
import io
import os
import re
import sys
import time

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBLIC = os.path.join(os.environ.get('PUBLIC', 'C:' + os.sep + 'Users' + os.sep + 'Public'),
                      'Documents', 'Embarcadero', 'Studio')

# Studio-Nummer -> Anzeigename. Die Nummer ist ein Sprung, nie eine
# Rechnung: D12 ist 23.0, D13 ist 37.0.
STUDIOS = (('23.0', 'D12'), ('37.0', 'D13'))

PACKAGES = (
    ('SCA.Engine',                    'SCA.Engine/SCA.Engine.dpk'),
    ('SCA.SharedUI',                  'SCA.SharedUI/SCA.SharedUI.dpk'),
    ('StaticCodeAnalyser.IDE.d12',
     'StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dpk'),
    ('StaticCodeAnalyser.Plugin.d12',
     'StaticCodeAnalyserIDE/StaticCodeAnalyser.Plugin.d12.dpk'),
)


def when(ts):
    return time.strftime('%Y-%m-%d %H:%M', time.localtime(ts))


def newest_source(dpk_rel):
    """Juengste Quelldatei eines Pakets: die .dpk selbst plus alles aus
    ihrer contains-Klausel."""
    base = os.path.dirname(os.path.join(REPO, dpk_rel))
    text = io.open(os.path.join(REPO, dpk_rel), encoding='utf-8-sig').read()
    newest, who = os.path.getmtime(os.path.join(REPO, dpk_rel)), dpk_rel
    for rel in re.findall(r"in\s+'([^']+\.pas)'", text):
        f = os.path.join(base, rel.replace(chr(92), os.sep))
        if os.path.isfile(f):
            t = os.path.getmtime(f)
            if t > newest:
                newest, who = t, os.path.relpath(f, REPO)
    return newest, who


def main():
    rows, stale = [], 0
    for name, dpk in PACKAGES:
        if not os.path.isfile(os.path.join(REPO, dpk)):
            continue
        src_ts, src_who = newest_source(dpk)
        for ver, label in STUDIOS:
            root = os.path.join(PUBLIC, ver)
            if not os.path.isdir(root):
                continue
            for plat in ('', 'Win32', 'Win64'):
                dcp = os.path.join(root, 'Dcp', plat, name + '.dcp')
                if not os.path.isfile(dcp):
                    continue
                art = os.path.getmtime(dcp)
                bad = art < src_ts
                stale += bad
                rows.append((label, plat or '(Win32-alt)', name, art,
                             src_ts, src_who, bad))

    if not rows:
        print('Keine gebauten Paket-Artefakte gefunden - nichts zu pruefen.')
        return 0

    print('%-4s %-11s %-30s %-16s %-16s' %
          ('IDE', 'Plattform', 'Paket', 'DCP gebaut', 'Quelle zuletzt'))
    for label, plat, name, art, src, who, bad in rows:
        print('%-4s %-11s %-30s %-16s %-16s %s'
              % (label, plat, name, when(art), when(src),
                 'VERALTET' if bad else 'ok'))

    if not stale:
        print('\nGRUEN: jedes DCP ist juenger als seine Quelle.')
        return 0

    print('\nROT: %d Artefakt(e) sind aelter als ihre Quelle.' % stale)
    print('Ein Paket, das darauf "requires", compiliert gegen den ALTEN')
    print('Stand - der Compiler meldet dann Fehler an der Aufrufstelle,')
    print('nicht am veralteten DCP. Betroffene Pakete neu bauen, in der')
    print('Reihenfolge SCA.Engine -> SCA.SharedUI -> IDE/Plugin.')
    for label, plat, name, art, src, who, bad in rows:
        if bad:
            print('  %s %s %s: juengste Quelle ist %s (%s)'
                  % (label, plat, name, who, when(src)))
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:      # noqa: BLE001 - Werkzeug darf nie haengen
        print('Fehler: %s' % exc)
        sys.exit(2)
