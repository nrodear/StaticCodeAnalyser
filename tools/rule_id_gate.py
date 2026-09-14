# Prueft, ob die SCA-ID im Betreff eines Commits zu den Detektor-Units
# passt, die der Commit beruehrt.
#
#   python tools/rule_id_gate.py <basis>..<zweig>
#   python tools/rule_id_gate.py --unit uDigitGrouping
#
# WARUM ES DAS GIBT. In Charge 3 trugen 37 von 52 Commit-Betreffen eine
# Regel-ID, die nicht zur geaenderten Unit gehoert. Die Ursache ist eine
# alte Bekannte dieses Projekts, nur in neuer Gestalt: die ID wurde mit
#
#     grep -n "<Regelname>" DETECTORS.md | head -1
#
# geholt. Der erste Treffer steht aber oft in einer ANDEREN Tabelle
# (Roadmap, Phasenliste) mit einer fremden ID - dieselbe Gattung wie
# "grep -c zaehlt den Dateinamen mit". Der Betreff ist die Zeile, an der
# eine A/B-Auswertung eine bewegte Regel ihrem Commit zuordnet; eine
# falsche ID schickt den Leser ins Leere.
#
# Die AUTORITATIVE Quelle ist die letzte Spalte der Katalogtabellen in
# DETECTORS.md: dort steht je Regel die emittierende Unit. Genau die
# wird hier gelesen - nicht der Regelname irgendwo im Text.
#
# Testunits werden auf ihre Detektor-Unit zurueckgerechnet
# (uTestFoo.pas -> uFoo); Units, die der Katalog nicht fuehrt
# (Infrastruktur, geteilte Helfer), gelten als neutral und loesen keinen
# Befund aus.
import os
import re
import subprocess
import sys


def katalog(pfad='DETECTORS.md'):
    """Unit -> Menge ihrer SCA-IDs, und ID -> Regelname."""
    unit2, id2name = {}, {}
    with open(pfad, encoding='utf-8') as f:
        for z in f:
            m = re.match(
                # Der Regelname steht fett; in einer der Tabellen folgt
                # ihm noch eine Kurzbeschreibung im selben Fettdruck
                # ("**FreeWithoutNil - Free without nil-out**") - deshalb
                # nur das erste Wort binden und den Rest schlucken.
                r'\|\s*(?:\d+\s*\|\s*)?(SCA\d+)\s*\|\s*\*\*([A-Za-z0-9]+)[^*]*\*\*'
                r'.*\|\s*`(u[A-Za-z0-9]+)`\s*\|\s*$', z.rstrip())
            if m:
                unit2.setdefault(m.group(3), set()).add(m.group(1))
                id2name[m.group(1)] = m.group(2)
    return unit2, id2name


def units_des_commits(sha):
    aus = subprocess.run(['git', 'show', '--name-only', '--format=', sha],
                         capture_output=True, text=True).stdout
    units = set()
    for f in aus.split():
        b = os.path.basename(f)
        if not b.endswith('.pas'):
            continue
        b = b[:-4]
        if b.startswith('uTest'):
            b = 'u' + b[5:]
        units.add(b)
    return units


def main():
    if len(sys.argv) < 2:
        raise SystemExit('Aufruf: rule_id_gate.py <basis>..<zweig>'
                         '  |  --unit <uName>')
    unit2, id2name = katalog()

    if sys.argv[1] == '--unit':
        u = sys.argv[2]
        ids = sorted(unit2.get(u, []))
        if not ids:
            print('%s fuehrt der Katalog nicht (Infrastruktur oder Helfer?)' % u)
        for i in ids:
            print('%s  %s' % (i, id2name[i]))
        return 0

    spanne = sys.argv[1]
    log = subprocess.run(['git', 'log', '--format=%h%x1f%s%x1e', spanne],
                         capture_output=True, text=True,
                         errors='replace').stdout
    fehler, ok, ohne, neutral = [], 0, 0, 0
    for eintrag in log.split('\x1e'):
        if not eintrag.strip():
            continue
        sha, betreff = eintrag.strip().split('\x1f')
        m = re.search(r'\((SCA\d+)\)', betreff)
        if not m:
            ohne += 1
            continue
        rid = m.group(1)
        erlaubt = set()
        for u in units_des_commits(sha):
            erlaubt |= unit2.get(u, set())
        if not erlaubt:
            neutral += 1
        elif rid in erlaubt:
            ok += 1
        else:
            fehler.append((sha, rid, betreff, sorted(erlaubt)))

    print('%s: %d passend, %d fraglich, %d ohne Katalog-Unit, %d ohne ID'
          % (spanne, ok, len(fehler), neutral, ohne))
    for sha, rid, betreff, erlaubt in fehler:
        print('  %s  %-8s %s' % (sha, rid, betreff[:66]))
        print('           passend waere: %s'
              % ', '.join('%s %s' % (i, id2name[i]) for i in erlaubt))
    return 1 if fehler else 0


if __name__ == '__main__':
    sys.exit(main())
