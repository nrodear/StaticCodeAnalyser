# -*- coding: utf-8 -*-
"""Gate gegen stillen Projektdatei-Drift.

Delphi schreibt .dproj-Dateien bei jedem Oeffnen zurueck und aendert
dabei Dinge, die niemand angefasst hat. Zwei davon sind nicht kosmetisch:

  <ProjectVersion>          Die IDE-Version schreibt ihre eigene Nummer.
                            D12 setzt 20.1, D13 setzt 20.3. Wer zwischen
                            beiden wechselt, erzeugt bei JEDEM Oeffnen
                            einen Diff - und das dauerhaft, weil die
                            jeweils andere IDE ihn zurueckdreht.

  <Platform Condition>      Die Standard-Plattform. Kippt sie unbemerkt,
                            baut die IDE eine andere Plattform als
                            erwartet. In diesem Repo hat genau das
                            wiederholt zu F2613 und zu Stale-Build-
                            Fehldiagnosen gefuehrt (Memory: 'Plattform-
                            Drift bei JEDEM IDE-Build').

Das Gate erfindet keine Politik - es macht den Drift nur sichtbar und
haelt ihn gegen eine bewusst gepflegte Erwartung. Wer eine Aenderung
WILL, zieht die Erwartung mit '--update' nach; dann steht sie als
eigener Diff im Commit statt sich unter einer Funktionsaenderung zu
verstecken.

  python tools/dproj_gate.py            prueft
  python tools/dproj_gate.py --update   uebernimmt den Ist-Stand
"""
import io
import json
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(REPO, 'tools', 'dproj_baseline.json')

PLAT = re.compile(r"<Platform Condition=\"'\$\(Platform\)'==''\">(\w+)</Platform>")
VER = re.compile(r"<ProjectVersion>([\d.]+)</ProjectVersion>")


def dprojs():
    out = subprocess.run(['git', '-C', REPO, 'ls-files', '*.dproj'],
                         capture_output=True, text=True).stdout
    return sorted(p for p in out.split(chr(10)) if p.strip())


def ist_stand():
    stand = {}
    for p in dprojs():
        voll = os.path.join(REPO, p)
        try:
            t = io.open(voll, encoding='utf-8-sig', errors='replace').read()
        except Exception:
            continue
        m, v = PLAT.search(t), VER.search(t)
        stand[p] = {'platform': m.group(1) if m else None,
                    'projectVersion': v.group(1) if v else None}
    return stand


def pruefe_suffix_paarung(befunde):
    """{$LIBSUFFIX} in der .dpk und <DllSuffix> in der .dproj muessen
    BEIDE da sein oder BEIDE fehlen.

    Der Paketname entsteht an drei unabhaengigen Stellen (Konzept
    MultiVersionRelease, Abschnitt 23): die .dpk-Direktive bestimmt den
    Namen, den der COMPILER schreibt, das .dproj-Element den, den
    MSBuild und die IDE ERWARTEN. Fehlt eines von beiden, laeuft der
    Compilerlauf GRUEN durch und die IDE meldet erst beim Laden
    "Package kann nicht geladen werden" - eine Fehlersuche, die
    zuverlaessig in die falsche Richtung fuehrt, weil der Bau ja
    funktioniert hat.

    Am 2026-08-23 hat genau diese Luecke einen ganzen Tag gekostet.

    Die dritte Stelle (<OutputName>) braucht es nur, wenn .dproj- und
    .dpk-Name auseinandergehen; hier heissen sie paarweise gleich, und
    das prueft die Schleife mit.
    """
    for dproj in dprojs():
        dpk = dproj[:-len('.dproj')] + '.dpk'
        if not os.path.exists(dpk):
            continue                      # .dpr-Projekte haben keine .dpk
        rel = os.path.relpath(dproj, REPO).replace(chr(92), '/')
        d_txt = io.open(dproj, encoding='utf-8', errors='replace').read()
        k_txt = io.open(dpk, encoding='utf-8', errors='replace').read()
        hat_dproj = '<DllSuffix>' in d_txt
        hat_dpk = 'LIBSUFFIX' in k_txt
        if hat_dpk and not hat_dproj:
            befunde.append(
                '  %s  .dpk traegt {$LIBSUFFIX}, .dproj hat kein '
                '<DllSuffix> - die IDE sucht den unsuffixierten Namen'
                % rel)
        elif hat_dproj and not hat_dpk:
            befunde.append(
                '  %s  .dproj traegt <DllSuffix>, .dpk hat kein '
                '{$LIBSUFFIX} - der Compiler schreibt den '
                'unsuffixierten Namen' % rel)


def main():
    ist = ist_stand()
    if '--update' in sys.argv:
        io.open(BASELINE, 'w', encoding='utf-8').write(
            json.dumps(ist, indent=2, sort_keys=True) + chr(10))
        print('Erwartung aktualisiert: %d Projektdateien' % len(ist))
        return 0

    if not os.path.exists(BASELINE):
        print('Keine Erwartung hinterlegt. Einmalig anlegen mit:')
        print('  python tools/dproj_gate.py --update')
        return 1

    soll = json.loads(io.open(BASELINE, encoding='utf-8').read())
    abweichungen = []
    # Q7 (2026-09-21): unabhaengig von der Baseline - die Paarung muss
    # immer stimmen, auch bei einem frisch aufgenommenen Projekt.
    pruefe_suffix_paarung(abweichungen)
    for p in sorted(set(soll) | set(ist)):
        if p not in ist:
            abweichungen.append('  %s  ENTFERNT oder nicht mehr versioniert' % p)
            continue
        if p not in soll:
            abweichungen.append('  %s  NEU - mit --update aufnehmen' % p)
            continue
        for feld in ('platform', 'projectVersion'):
            a, b = soll[p].get(feld), ist[p].get(feld)
            if a != b:
                abweichungen.append('  %-52s %s: %s -> %s' % (p, feld, a, b))

    if not abweichungen:
        print('GATE GRUEN: %d Projektdateien, kein Drift in Plattform oder '
              'ProjectVersion.' % len(ist))
        return 0

    print('PROJEKTDATEI-DRIFT (%d):' % len(abweichungen))
    for a in abweichungen:
        print(a)
    print()
    print('Eine IDE hat das geschrieben, nicht ein Mensch. Entweder')
    print('zuruecknehmen, oder - wenn die Aenderung gewollt ist - die')
    print('Erwartung mit "--update" nachziehen, damit sie als eigener')
    print('Diff sichtbar bleibt.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
