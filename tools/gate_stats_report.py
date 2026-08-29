# -*- coding: utf-8 -*-
"""Gleicht die Ausgabe von --gate-stats gegen die Gate-Namen im Quelltext ab.

WOZU: --gate-stats nennt nur die Gates, die GEGRIFFEN haben. Die
interessante Menge ist die andere - Gates mit null Treffern ueber einen
grossen Korpus sind belegbare Loeschkandidaten. Dafuer muss man wissen,
welche Gates es ueberhaupt gibt, und das steht nur im Quelltext.

AUFRUF:
    <Scan mit --gate-stats>  > lauf.txt
    python tools/gate_stats_report.py lauf.txt

WAS DIE AUSGABE NICHT SAGT: dass ein Gate mit null Treffern weg KANN.
Sie sagt nur, dass es auf DIESEM Korpus nichts gefangen hat. Ein Gate
gegen ein Muster, das hier zufaellig nicht vorkommt, ist trotzdem
richtig - die Zahl ist der Anfang der Pruefung, nicht ihr Ende.

ZWEITE EINSCHRAENKUNG, wichtiger als sie aussieht: mehrere AUFRUFSTELLEN
duerfen denselben Namen tragen (in uLeakDetector2 tun das fuenf
Praedikate, die in zwei verschiedenen Pfaden geprueft werden). Der
Zaehler summiert dann ueber alle Stellen. Greift Stelle A und Stelle B
nie, sieht man das hier NICHT. Fuer die erste Frage - "welches Praedikat
greift ueberhaupt nirgends" - reicht das; wer eine einzelne Stelle
verdaechtigt, muss ihr einen eigenen Namen geben.
"""
import io
import os
import re
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUELLE = os.path.join(WURZEL, 'SCA.Engine', 'sources')

# Gate('<Name>', ...) - der Name ist immer ein Literal, damit er hier
# statisch auffindbar bleibt. Wer ihn zur Laufzeit zusammensetzt, macht
# dieses Werkzeug blind.
GATE_AUFRUF = re.compile(r"\bGate\(\s*'([^']+)'")
# Berichtszeile: "    1234  SCA001.IsFoo"
BERICHT = re.compile(r'^\s*(\d+)\s+(\S+)\s*$')


def gates_im_quelltext():
    gefunden = {}
    for dp, dn, fn in os.walk(QUELLE):
        for f in fn:
            if not f.endswith('.pas'):
                continue
            p = os.path.join(dp, f)
            try:
                t = io.open(p, encoding='utf-8-sig', errors='replace').read()
            except Exception:
                continue
            for m in GATE_AUFRUF.finditer(t):
                gefunden.setdefault(m.group(1), f)
    return gefunden


def treffer_aus_bericht(pfad):
    treffer = {}
    imbereich = False
    for z in io.open(pfad, encoding='utf-8', errors='replace'):
        if z.startswith('Gate hits'):
            imbereich = True
            continue
        if not imbereich:
            continue
        if z.strip().startswith('none -'):
            return {}
        m = BERICHT.match(z)
        if m:
            treffer[m.group(2)] = int(m.group(1))
        elif z.strip() == '':
            continue
        else:
            break
    return treffer


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    quelle = gates_im_quelltext()
    treffer = treffer_aus_bericht(sys.argv[1])
    if not treffer:
        print('Kein Gate-Bericht in %s gefunden.' % sys.argv[1])
        print('Lief der Scan mit --gate-stats?')
        return 2

    print('Gates im Quelltext : %d' % len(quelle))
    print('davon getroffen    : %d' % len(treffer))
    print()

    nuller = sorted(n for n in quelle if n not in treffer)
    print('NULL TREFFER (%d) - Pruefkandidaten:' % len(nuller))
    for n in nuller:
        print('   %-44s %s' % (n, quelle[n]))
    if not nuller:
        print('   keine - jedes instrumentierte Gate hat gegriffen')
    print()

    print('GETROFFEN, absteigend:')
    for n, c in sorted(treffer.items(), key=lambda x: -x[1]):
        wo = quelle.get(n, '(nicht im Quelltext gefunden!)')
        print('   %10d  %-42s %s' % (c, n, wo))

    # Ein Name im Bericht, den es im Quelltext nicht gibt, heisst: der
    # Bericht stammt aus einem anderen Stand. Das ist ein Fehler, kein
    # Detail - die Auswertung waere sonst stillschweigend falsch.
    fremd = [n for n in treffer if n not in quelle]
    if fremd:
        print()
        print('WARNUNG: %d Name(n) im Bericht ohne Entsprechung im '
              'Quelltext - stammt der Bericht von diesem Stand?' % len(fremd))
        for n in fremd:
            print('   %s' % n)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
