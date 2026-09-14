# Holt die SRC-Konstante benannter DUnitX-Tests aus einer Testunit und
# schreibt sie als echte .pas heraus - damit laesst sich eine Fixture
# gegen die GEBAUTE Exe messen, ohne den Testlauf abzuwarten.
#
# WOZU. Die Chargen dieses Projekts bauen genau einmal, am Ende. Jede
# Erwartung in einem neuen Test muss vorher an der bestehenden Exe
# gemessen werden, sonst ist sie geraten - und eine geratene Erwartung
# kostet einen roten Lauf. Der Weg dahin ist immer derselbe: Fixture aus
# dem Test herausloesen, als Datei ablegen, scannen:
#
#   python tools/fixture_extract.py <zielordner> <testunit.pas> <test> [...]
#   "Output\Win64 Release\StaticCodeAnalyser.d12.exe" --file <zielordner>\<test>.pas ^
#       --profile strict --min-severity hint
#
# Gezaehlt wird mit  awk '$3=="<RegelName>"'  - NICHT mit grep -c auf den
# Regelnamen: der zaehlt den DATEINAMEN mit, wenn die Sonde so heisst.
#
# ZWEI FALLEN, die diese Fassung kennt - beide haben je eine falsche
# Fixture erzeugt, bevor sie behoben waren:
#
# 1. NICHT EINFACH DIE LITERALE MIT '\n' VERBINDEN. Das stimmt nur,
#    solange jede Quellzeile genau EIN Literal traegt. Sobald eines ueber
#    die Verkettung geteilt ist -
#        '  f := ''xox' + 'b-1234...'';'#13#10 +
#    - entsteht mittendrin ein Umbruch, den es nie gab. Der Ausdruck wird
#    deshalb Zeichen fuer Zeichen gelesen.
# 2. '//'-KOMMENTARE IM SRC-BLOCK. Apostrophe darin wurden als Literale
#    gelesen und landeten in der Datei. Der Kommentar-Strip ist
#    zustandsbehaftet, damit ein '//' INNERHALB eines Literals stehen
#    bleibt.
import io
import os
import re
import sys

if len(sys.argv) < 4:
    raise SystemExit(__doc__ or
                     'Aufruf: fixture_extract.py <ordner> <unit.pas> <test> ...')

ZIELORDNER = sys.argv[1]
TESTDATEI = sys.argv[2]
TESTS = sys.argv[3:]

txt = io.open(TESTDATEI, encoding='utf-8-sig').read()
if not os.path.isdir(ZIELORDNER):
    os.makedirs(ZIELORDNER)


def ohne_kommentare(ausdruck):
    """'//'-Kommentare entfernen, Literalinhalte unangetastet lassen."""
    out = []
    instr = False
    i = 0
    n = len(ausdruck)
    while i < n:
        c = ausdruck[i]
        if c == "'":
            instr = not instr
            out.append(c)
            i += 1
            continue
        if (not instr) and c == '/' and i + 1 < n and ausdruck[i + 1] == '/':
            while i < n and ausdruck[i] != '\n':
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def rekonstruiere(ausdruck):
    """Pascal-Stringausdruck -> tatsaechlicher Wert.

    Literalinhalte woertlich (''-Escape aufgeloest), #13#10 zum Umbruch,
    alles andere (Plus, Leerraum, Quelltext-Umbrueche) ignoriert.
    """
    ausdruck = ohne_kommentare(ausdruck)
    out = []
    i = 0
    n = len(ausdruck)
    while i < n:
        c = ausdruck[i]
        if c == "'":
            i += 1
            while i < n:
                if ausdruck[i] == "'":
                    if i + 1 < n and ausdruck[i + 1] == "'":
                        out.append("'")
                        i += 2
                        continue
                    i += 1
                    break
                out.append(ausdruck[i])
                i += 1
            continue
        if c == '#':
            m = re.match(r'#(\d+)', ausdruck[i:])
            if m:
                code = int(m.group(1))
                # #13 unterdruecken, #10 als Umbruch - so entsteht genau
                # EIN '\n' je Zeilenende statt zweier Zeichen.
                if code == 10:
                    out.append('\n')
                elif code != 13:
                    out.append(chr(code))
                i += m.end()
                continue
        i += 1
    return ''.join(out)


for name in TESTS:
    a = txt.find('.' + name + ';')
    if a < 0:
        raise SystemExit('Test nicht gefunden: %s' % name)
    s = txt.find('const SRC =', a)
    if s < 0:
        raise SystemExit('kein "const SRC =" hinter %s' % name)
    s += len('const SRC =')
    i, instr = s, False
    while i < len(txt):
        c = txt[i]
        if c == "'":
            instr = not instr
        elif c == ';' and not instr:
            break
        i += 1
    quelle = rekonstruiere(txt[s:i])
    pfad = os.path.join(ZIELORDNER, name + '.pas')
    io.open(pfad, 'w', newline='\r\n').write(quelle.rstrip('\n') + '\n')
    print('%-58s %d Zeilen' % (name, quelle.rstrip('\n').count('\n') + 1))
