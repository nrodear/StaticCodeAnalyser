# -*- coding: utf-8 -*-
"""Gate: der Plugin-Monolith enthaelt genau die Units des Dev-Satzes.

WOZU: Das IDE-Plugin gibt es in ZWEI Bauformen.

  Dev-Satz  SCA.Engine + SCA.SharedUI + StaticCodeAnalyser.IDE.d12  (3 BPLs)
  Monolith  StaticCodeAnalyser.Plugin.d12                           (1 BPL)

Gebaut, getestet und taeglich benutzt wird der Dev-Satz. AUSGELIEFERT wird
der Monolith - der Loader sucht 'requires'-Pakete ueber bds.exe-Dir,
System32 und PATH, und drei private BPLs liegen in keinem dieser Pfade.

Damit ist die ausgelieferte Form die einzige, die hier NIE laeuft. Ihre
contains-Liste ist eine zweite, von Hand gepflegte Kopie von 269 Eintraegen.
Wer eine Unit nur in SCA.Engine.dpk eintraegt, merkt davon nichts: Dev-Bau
gruen, alle Tests gruen - und im ausgelieferten Plugin fehlt der Detektor.

Am 2026-08-22 stimmte die Paritaet exakt (269 zu 269, Differenz null in
beide Richtungen). Sie hielt bis dahin durch Disziplin, nicht durch
Mechanik. Dieses Gate macht daraus Mechanik.

    python tools/monolith_parity_gate.py

EXIT  0 deckungsgleich | 1 Abweichung | 2 Aufruffehler
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEV = (
    ('SCA.Engine',   'SCA.Engine/SCA.Engine.dpk'),
    ('SCA.SharedUI', 'SCA.SharedUI/SCA.SharedUI.dpk'),
    ('IDE-Paket',    'StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dpk'),
)
MONOLITH = ('Monolith', 'StaticCodeAnalyserIDE/StaticCodeAnalyser.Plugin.d12.dpk')


def contains_units(rel):
    """{Unitname: Quellpfad} aus der contains-Klausel einer .dpk."""
    path = os.path.join(REPO, rel)
    text = io.open(path, encoding='utf-8-sig').read()
    m = re.search(r'^contains(.*?);\s*$', text, re.S | re.M | re.I)
    if not m:
        raise SystemExit('keine contains-Klausel in ' + rel)
    body = m.group(1)
    out = {}
    for name, src in re.findall(r"^\s*([A-Za-z_]\w*)\s+in\s+'([^']+)'", body,
                                re.M):
        out[name] = src
    return out


def main():
    dev, herkunft = {}, {}
    for label, rel in DEV:
        for u, src in contains_units(rel).items():
            if u in dev:
                print('%s steht in %s UND in %s - eine Unit gehoert in '
                      'GENAU ein Paket.' % (u, herkunft[u], label))
                return 1
            dev[u], herkunft[u] = src, label
    mono = contains_units(MONOLITH[1])

    fehlt = sorted(set(dev) - set(mono))
    zuviel = sorted(set(mono) - set(dev))

    print('Dev-Satz: %s = %d Units'
          % (' + '.join('%s %d' % (l, len(contains_units(r))) for l, r in DEV),
             len(dev)))
    print('Monolith: %d Units' % len(mono))

    if not fehlt and not zuviel:
        print('GATE GRUEN: beide Bauformen enthalten dieselben Units.')
        return 0

    print()
    for u in fehlt:
        print('  FEHLT im Monolith: %-38s (aus %s)' % (u, herkunft[u]))
        print('      %s in \'%s\',' % (u, dev[u].replace('/', chr(92))))
    for u in zuviel:
        print('  NUR im Monolith:   %-38s' % u)
    print('\nGATE ROT: %d Unterschied(e). Der Dev-Bau bleibt davon gruen - '
          'die Luecke faellt erst im ausgelieferten Plugin auf.'
          % (len(fehlt) + len(zuviel)))
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:      # noqa: BLE001 - ein Gate darf nie haengen
        print('Gate-Fehler: %s' % exc)
        sys.exit(2)
