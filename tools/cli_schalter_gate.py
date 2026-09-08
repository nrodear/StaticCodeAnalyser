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

DREI FALLEN, die der Chargen-Review am 08.09. in der ersten Fassung
gefunden hat und die diese Fassung vermeidet:

1. ZEILENWEISE Bedingungsanalyse war FALSCH-GRUEN. Bei
       else if (A = '--neu-a') or
               (A = '--neu-b') then
   sah die erste Fassung nur '--neu-a'. Wer brav eintraegt, was das Gate
   nennt, bekommt beim naechsten Lauf GRUEN - waehrend '--neu-b=false'
   weiter still verschluckt wird. Gruen nach dem Befolgen der eigenen
   Anweisung ist der gefaehrlichste Zustand, den ein Gate haben kann.
   Deshalb wird die Bedingung jetzt bis zum 'then' zusammengeklebt.

2. Die Rumpfsuche brach bei JEDER Zeile mit 'else' ab. Ein Wert-Schalter
   mit einer inneren if/else-Kaskade VOR dem GetValue galt damit als
   wertlos - FALSCH-ROT, und der Meldetext forderte auch noch dazu auf,
   ihn in die Sperrliste zu setzen, womit ein legitimes '--x=wert'
   kuenftig abgelehnt worden waere. Der Rumpf wird jetzt ueber die
   Einrueckungstiefe des Zweigs abgegrenzt.

3. Das Gate prueft jetzt auch, dass der Waechter in ParseArgs UEBERHAUPT
   GERUFEN wird. Loescht jemand den Aufruf und laesst die Liste stehen,
   war die erste Fassung gruen.

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


def einrueckung(zeile):
    return len(zeile) - len(zeile.lstrip())


def zweige(block):
    """Alle Schalter-Zweige als (namen, rumpftext).

    Klebt mehrzeilige Bedingungen bis zum 'then' zusammen (Falle 1) und
    grenzt den Rumpf ueber die Einrueckungstiefe ab (Falle 2).
    """
    aus = []
    i = 0
    while i < len(block):
        z = block[i]
        if 'else if' not in z and not re.match(r'\s*if\s', z):
            i += 1
            continue

        tiefe = einrueckung(z)

        # Bedingung bis zum 'then' einsammeln - sie darf ueber mehrere
        # Zeilen laufen.
        bedingung = z
        j = i
        while 'then' not in bedingung and j + 1 < len(block):
            j += 1
            bedingung += ' ' + block[j].strip()

        namen = re.findall(r"A\s*=\s*'([^']+)'", bedingung)
        if not namen:
            i = j + 1
            continue

        # Rumpf: alles bis zum naechsten Zweig AUF DERSELBEN Tiefe. Ein
        # 'else' tiefer drin gehoert noch zum Rumpf.
        rumpf = []
        k = j + 1
        while k < len(block):
            zk = block[k]
            if zk.strip() and einrueckung(zk) <= tiefe:
                if re.match(r'\s*(else|end\b)', zk):
                    break
            rumpf.append(zk)
            k += 1

        aus.append((namen, '\n'.join(rumpf)))
        i = j + 1
    return aus


def parse_args_block(zeilen):
    try:
        start = next(i for i, z in enumerate(zeilen)
                     if 'class function TConsoleRunner.ParseArgs' in z)
    except StopIteration:
        return None
    ende = next((i for i in range(start + 1, len(zeilen))
                 if zeilen[i].rstrip() == 'end;'), None)
    if ende is None:
        return None
    return zeilen[start:ende]


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

    block = parse_args_block(zeilen)
    if block is None:
        print('GATE ROT: TConsoleRunner.ParseArgs nicht gefunden oder ohne '
              'abschliessendes "end;" auf Spalte 0')
        return 1

    # Falle 3: der Waechter muss auch tatsaechlich gerufen werden.
    if 'IstSchalterOhneWert(' not in '\n'.join(block):
        print('GATE ROT: die Liste CLI_SCHALTER_OHNE_WERT existiert, aber')
        print('  IstSchalterOhneWert wird in ParseArgs nirgends gerufen.')
        print('  Ein Wert an einem Boolean-Schalter wird damit wieder still')
        print('  verschluckt - "--full=false" schaltet --full EIN.')
        return 1

    soll = set()
    for namen, rumpf in zweige(block):
        if 'GetValue' not in rumpf:
            soll.update(namen)

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
        print('  In der Liste, aber im Baum nicht (mehr) wertlos.')
        print('  ACHTUNG: pruefe erst am Zweig, ob der Schalter WIRKLICH')
        print('  einen Wert nimmt - dann gehoert er aus der Liste heraus.')
        print('  Traegst du einen Wert-Schalter faelschlich ein, wird ein')
        print('  legitimes "--schalter=wert" kuenftig abgelehnt:')
        for n in zuviel:
            print('    %s' % n)
    print()
    print('  Die Liste steht in %s, direkt vor ParseArgs.' % QUELLE.name)
    return 1


if __name__ == '__main__':
    sys.exit(main())
