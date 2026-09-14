# Fuegt Tests in eine DUnitX-Testunit ein - Bibliothek, kein Skript.
#
#   from fixture_insert import einfuegen
#   einfuegen(pfad, klasse, deklarationen, rumpf, anker)
#
# deklarationen: Zeilen fuer die Klassendeklaration ('    [Test] procedure X;')
# rumpf:         Zeilen der Implementierungen
# anker:         eindeutiger Text, VOR dem der Rumpf eingefuegt wird
#
# WOZU EIN WERKZEUG STATT EINES EDITS. Drei Fallen haben in diesem
# Projekt je einen roten Bau gekostet, und alle drei sind mechanisch:
#
# 1. E2065 - "hinter die letzte [Test]-Zeile" trifft in Dateien mit
#    MEHREREN Fixture-Klassen die falsche. Hier wird die letzte
#    [Test]-Zeile DER GENANNTEN KLASSE gesucht.
# 2. E2029 - ein Index-Schnitt auf 'end;' trifft auch das 'end;' von
#    'finally F.Free; end;'. Hier wird ueberhaupt nicht geschnitten, nur
#    VOR einem eindeutigen Anker eingefuegt.
# 3. ZEILENENDEN. .gitattributes verlangt CRLF, im Arbeitsbaum liegen
#    aber Dateien mit reinem LF (git normalisiert erst beim naechsten
#    Checkout). Eine festverdrahtete CRLF-Annahme laesst die Ankersuche
#    ins Leere laufen - die Konvention wird deshalb je Datei ERMITTELT.
#
# Nach dem Schreiben laeuft eine Selbstpruefung: je Deklaration genau
# eine Implementierung IN DER GENANNTEN KLASSE, und keine zwei 'end;' in
# Spalte 0 hintereinander.
#
# Danach IMMER:
#   python tools/pascal_struct_gate.py <testdatei>
#   python tools/compile_sanity_gate.py <testdatei>
#   python tools/fixture_extract.py ... und die Erwartungen an der Exe
#   nachmessen (s. Kopf von fixture_extract.py)
import io
import re

CR = '\r\n'


def _lies(pfad):
    roh = io.open(pfad, 'rb').read()
    bom = roh[:3] == b'\xef\xbb\xbf'
    return io.open(pfad, encoding='utf-8-sig', newline='').read(), bom


def _schreib(pfad, text, bom):
    io.open(pfad, 'w', encoding='utf-8-sig' if bom else 'utf-8',
            newline='').write(text)


def letzter_test_der_klasse(text, klasse):
    """Letzte '[Test]'-Zeile INNERHALB der Deklaration von <klasse>."""
    start = text.index('  ' + klasse + ' = class')
    # Die Klassendeklaration endet am ersten 'end;' in Spalte 2.
    ende = text.index(CR + '  end;', start)
    block = text[start:ende]
    treffer = [z for z in block.split(CR) if z.strip().startswith('[Test]')]
    if not treffer:
        raise SystemExit('keine [Test]-Zeile in %s' % klasse)
    return treffer[-1]


def pruefe(text, klasse, namen):
    fehler = []
    for n in namen:
        d = text.count('    [Test] procedure %s;' % n)
        i = text.count('procedure %s.%s;' % (klasse, n))
        if d != 1:
            fehler.append('%s: %d Deklarationen (erwartet 1)' % (n, d))
        if i != 1:
            fehler.append('%s: %d Implementierungen als %s.* (erwartet 1)'
                          % (n, i, klasse))
    vorher = None
    for nr, z in enumerate(text.split(CR), 1):
        s = z.rstrip()
        if not s.strip() or s.lstrip().startswith('//'):
            continue
        if s == 'end;' and vorher == 'end;':
            fehler.append('Zeile %d: zwei "end;" in Spalte 0 (E2029)' % nr)
        vorher = s
    return fehler


def einfuegen(pfad, klasse, deklarationen, rumpf, anker):
    global CR
    text, bom = _lies(pfad)
    CR = '\r\n' if '\r\n' in text else '\n'

    letzte = letzter_test_der_klasse(text, klasse)
    if text.count(letzte + CR) != 1:
        raise SystemExit('Deklarations-Anker nicht eindeutig: %r' % letzte)
    text = text.replace(letzte + CR,
                        letzte + CR + CR.join(deklarationen) + CR, 1)

    if text.count(anker) != 1:
        raise SystemExit('Rumpf-Anker %d mal gefunden: %r'
                         % (text.count(anker), anker[:60]))
    text = text.replace(anker, CR.join(rumpf) + CR + CR + anker, 1)

    namen = [re.search(r'procedure (\w+);', d).group(1)
             for d in deklarationen if '[Test]' in d]
    fehler = pruefe(text, klasse, namen)
    if fehler:
        raise SystemExit('SELBSTPRUEFUNG ROT:\n  ' + '\n  '.join(fehler))

    _schreib(pfad, text, bom)
    print('%s: %d Test(s) in %s eingefuegt, Selbstpruefung gruen'
          % (pfad.replace('\\', '/').split('/')[-1], len(namen), klasse))


if __name__ == '__main__':
    print('Bibliothek, kein Skript. Aufruf aus einem Patch-Skript:')
    print('    import sys; sys.path.insert(0, "tools")')
    print('    from fixture_insert import einfuegen')
    print('    einfuegen(pfad, klasse, deklarationen, rumpf, anker)')
    print('Begruendung und die drei Fallen: s. Kopfkommentar dieser Datei.')
