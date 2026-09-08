#!/usr/bin/env python3
"""Prueft, ob CLI_SCHALTER_OHNE_WERT den Parser-Baum noch vollstaendig abbildet.

HINTERGRUND
Die '='-Zerlegung in TConsoleRunner.ParseArgs laeuft ueber ALLE Argumente,
auch ueber reine Boolean-Schalter. '--full=false' wurde dadurch zu '--full'
plus einem verworfenen 'false' - der Schalter ging auf TRUE, der Aufrufer
bekam das Gegenteil dessen, was er geschrieben hat. Seit dem 08.09. faengt
das eine Liste ab.

Eine handgepflegte Liste altert. Dieses Gate leitet dieselbe Menge ein
zweites Mal aus dem Quelltext ab - jeder Zweig 'A = ...' ohne GetValue im
Rumpf ist ein Schalter ohne Wert - und vergleicht sie mit der Konstanten.
Wer einen neuen Boolean-Schalter einbaut und den Eintrag vergisst, faellt
hier auf, nicht erst beim Anwender.

Exit 0 = gruen, Exit 1 = Abweichung.
"""
import io
import re
import sys
from pathlib import Path

WURZEL = Path(__file__).resolve().parent.parent
QUELLE = (WURZEL / 'StaticCodeAnalyserForm' / 'sources' / 'Console'
          / 'uConsoleRunner.pas')


def lies(pfad):
    return io.open(pfad, encoding='utf-8-sig').read().split('\n')


def konstante(zeilen):
    """Die Namen aus dem CLI_SCHALTER_OHNE_WERT-Array."""
    text = '\n'.join(zeilen)
    m = re.search(r'CLI_SCHALTER_OHNE_WERT\s*:\s*array\[[^\]]*\]\s*of\s+'
                  r'string\s*=\s*\((.*?)\);', text, re.S)
    if not m:
        return None
    return set(re.findall(r"'([^']+)'", m.group(1)))


def aus_dem_baum(zeilen):
    """Die Schalter, deren Zweig KEIN GetValue ruft."""
    try:
        start = next(i for i, z in enumerate(zeilen)
                     if 'class function TConsoleRunner.ParseArgs' in z)
    except StopIteration:
        return None
    ende = next(i for i in range(start + 1, len(zeilen))
                if zeilen[i].rstrip() == 'end;')
    block = zeilen[start:ende]

    ohne = set()
    for i, z in enumerate(block):
        if 'else if' not in z and not re.match(r'\s*if\s', z):
            continue
        namen = re.findall(r"A\s*=\s*'([^']+)'", z)
        if not namen:
            continue
        rumpf = []
        for j in range(i + 1, len(block)):
            if 'else if' in block[j] or re.match(r'\s*else\b', block[j]):
                break
            rumpf.append(block[j])
        if 'GetValue' not in '\n'.join(rumpf):
            ohne.update(namen)
    return ohne


def main():
    if not QUELLE.exists():
        print('GATE ROT: %s nicht gefunden' % QUELLE)
        return 1

    zeilen = lies(QUELLE)
    ist = konstante(zeilen)
    if ist is None:
        print('GATE ROT: CLI_SCHALTER_OHNE_WERT nicht gefunden - wurde die '
              'Konstante umbenannt oder entfernt?')
        return 1

    soll = aus_dem_baum(zeilen)
    if soll is None:
        print('GATE ROT: TConsoleRunner.ParseArgs nicht gefunden')
        return 1

    fehlt = sorted(soll - ist)
    zuviel = sorted(ist - soll)

    if not fehlt and not zuviel:
        print('GATE GRUEN: %d Schalter ohne Wert, Liste und Parser-Baum '
              'stimmen ueberein.' % len(ist))
        return 0

    print('GATE ROT: CLI_SCHALTER_OHNE_WERT passt nicht zum Parser-Baum.')
    if fehlt:
        print()
        print('  Im Baum ohne GetValue, aber NICHT in der Liste')
        print('  (ein Wert an diesem Schalter wird still verschluckt):')
        for n in fehlt:
            print('    %s' % n)
    if zuviel:
        print()
        print('  In der Liste, aber im Baum nicht (mehr) wertlos')
        print('  (der Schalter nimmt jetzt einen Wert und wuerde faelschlich')
        print('   abgelehnt):')
        for n in zuviel:
            print('    %s' % n)
    print()
    print('  Die Liste steht in %s, direkt vor ParseArgs.' % QUELLE.name)
    return 1


if __name__ == '__main__':
    sys.exit(main())
