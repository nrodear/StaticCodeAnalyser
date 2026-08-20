#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Encoding-Gate: jede getrackte Textdatei mit Nicht-ASCII-Zeichen traegt
ein UTF-8-BOM - und ist damit selbstbeschreibend.

WARUM (Befund 2026-08-20): 749 Dateien des Repos trugen Umlaute, Akzente
und Kastengrafik als gueltiges UTF-8, aber ohne BOM. Wer sie liest, kann
das nicht wissen und faellt auf die ANSI-Codepage zurueck:

  * Delphi (Compiler UND IDE-Editor) liest eine BOM-lose .pas als ANSI -
    aus 'ue' wird 'Ã¼', aus '=' der Bannerlinie wird 'â•'. Schlimmer:
    speichert die IDE die Datei danach, ist die Verstuemmelung dauerhaft.
  * Inno Setup liest eine BOM-lose .iss als ANSI.
  * PowerShell 5.1 liest ein BOM-loses .ps1 als ANSI.
  * Ein ANSI-Editor zeigt Markdown-Umlaute als Mojibake (GitHub selbst
    raet richtig, der lokale Editor nicht).

Der eigene Detektor SCA190 (SourceUtf8NoBom) faengt genau das - aber nur
fuer die .pas-Dateien im Self-Scan. Dieses Gate zieht die Invariante
ueber ALLE Textarten.

REINES ASCII bleibt bewusst BOM-frei: dort sind UTF-8 und ANSI
byte-gleich, ein BOM waere nur Rauschen im Diff.

AUSNAHMEN (jede mit Grund, s. AUSNAHMEN unten).

Exit 0 = gruen, 1 = Verstoss. Lokal: `python tools/encoding_gate.py`
"""
import io
import os
import subprocess
import sys

# Ein Gate darf nie an der Kodierung der Konsole sterben: der Bericht
# zeigt Beispielzeichen, und eine cp1252-Konsole kann die nicht alle.
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOM = b'\xef\xbb\xbf'

# Endungen, deren Leser BOM-empfindlich sind (s. Modul-Kopf).
GEPRUEFT = ('.pas', '.dpr', '.dpk', '.dfm', '.fmx', '.inc', '.iss',
            '.ps1', '.md')

# Bewusst NICHT geprueft - je Endung der Grund:
AUSNAHMEN = {
    '.po':   'charset steht im Header; unser Leser ist explizit UTF-8 '
             '(uLocalization, TStringStream mit TEncoding.UTF8), und die '
             'gettext-Werkzeugkette vertraegt kein BOM',
    '.pot':  'wie .po',
    '.py':   'PEP 3120: UTF-8 ist die Default-Quellkodierung',
    '.yml':  'die YAML-Spezifikation schreibt UTF-8 vor',
    '.yaml': 'wie .yml',
    '.json': 'die drei sprachtragenden rules/*.json haben BOM (der '
             'Katalog-Leser liest ohne explizites Encoding und haengt '
             'daran); Overlays werden explizit als UTF-8 gelesen',
    '.sh':   'Shell-Skripte: ein BOM landet als Zeichen in der ersten '
             'Zeile und bricht die Shebang',
}


def getrackte_dateien():
    aus = subprocess.run(['git', 'ls-files'], cwd=REPO, capture_output=True,
                         text=True, encoding='utf-8').stdout
    return [z.strip() for z in aus.split('\n') if z.strip()]


def main():
    verstoesse = []
    kaputt = []
    geprueft = 0
    for rel in getrackte_dateien():
        if os.path.splitext(rel)[1].lower() not in GEPRUEFT:
            continue
        pfad = os.path.join(REPO, rel)
        if not os.path.isfile(pfad):
            continue
        roh = io.open(pfad, 'rb').read()
        geprueft += 1
        if roh.startswith(BOM):
            continue
        try:
            txt = roh.decode('utf-8')
        except UnicodeDecodeError as e:
            # Weder BOM noch gueltiges UTF-8: die Datei ist bereits in
            # einer Byte-Kodierung gespeichert, die niemand raten kann.
            kaputt.append((rel, 'Byte 0x%02x an Position %d ist kein '
                                'gueltiges UTF-8' % (roh[e.start], e.start)))
            continue
        if any(ord(c) > 127 for c in txt):
            beispiel = next(c for c in txt if ord(c) > 127)
            anzahl = sum(1 for c in txt if ord(c) > 127)
            verstoesse.append((rel, anzahl, beispiel))

    if not verstoesse and not kaputt:
        print('GATE GRUEN: %d Dateien geprueft, jede mit Nicht-ASCII traegt '
              'ein BOM.' % geprueft)
        return 0

    if kaputt:
        print('NICHT UTF-8 (%d):' % len(kaputt))
        for rel, warum in kaputt:
            print('  %s - %s' % (rel, warum))
    if verstoesse:
        print('NICHT-ASCII OHNE BOM (%d):' % len(verstoesse))
        for rel, n, c in sorted(verstoesse, key=lambda x: -x[1]):
            print('  %-58s %5d Zeichen, z.B. U+%04X %s'
                  % (rel[:58], n, ord(c), c))
    print('')
    print('Diese Dateien sind gueltiges UTF-8, sagen es aber nicht - ein')
    print('ANSI-Leser (Delphi-IDE, Inno, PowerShell 5.1) verstuemmelt sie.')
    print('Beheben: UTF-8-BOM voranstellen (Inhalt NICHT anfassen), oder')
    print('die Zeichen ASCII-transkribieren, wo das Projekt es ohnehin')
    print('vorsieht (Quelltext-Kommentare: ue/oe/ae/ss).')
    return 1


if __name__ == '__main__':
    sys.exit(main())
