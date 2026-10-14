#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen-rtl-types.py - erzeugt reDelphix/source/uRdxRtlTypes.inc: die Namen
aller Klassen und Interfaces aus den mitgelieferten Delphi-Quellen.

WARUM (Entscheid E27, Nico 2026-10-14)
======================================
Die Editorhilfen SCA126 ('X = nil' -> 'not Assigned(X)') und SCA084
('Assigned(X) and (X <> nil)' -> 'Assigned(X)') duerfen nur umschreiben,
wenn der Typ von X POSITIV als Klasse, Interface oder Zeiger bewiesen ist:
bei einem Funktionstyp ruft '= nil' die Funktion auf, Assigned() nicht -
der Sinn kippte. Bis Charge R8 galt als Beweis nur die Deklaration in
DERSELBEN Unit (TRdxExprFixes.PointerLikeType). Das kostete im Realwelt-
Korpus 58,8 % der SCA126-Angebote (Messung R9): 'FList: TStringList',
'Form: TForm' aus einer anderen Unit sind nicht bewiesen - obwohl jeder
weiss, dass das Klassen sind.

Diese Liste ist der zweite Beweisweg: ein Typname, der in den Delphi-
Quellen als Klasse oder Interface deklariert ist, gilt als bewiesen.
Kundentypen ('TObjFactory', 'TChromium') bleiben ohne Hilfe - streng.

REGEL (was in die Liste kommt)
==============================
Aus allen .pas/.inc unter <Studio>\\source von Delphi 12 (23.0) UND
Delphi 13 (37.0), Vereinigung beider Staende, jeder Name in
Kleinschreibung, der so deklariert ist:
  TFoo = class            TFoo = class(TBar)      TFoo = class abstract
  TFoo = class sealed     TFoo = class;           (Vorwaertsdeklaration)
  TFoo<T> = class         (generisch: Name ohne Parameter -> 'tfoo')
  IFoo = interface        IFoo = interface(IBar)  IFoo = interface;
  IFoo = dispinterface    auch 'packed class'
NICHT in die Liste:
  * 'class helper for'    - ein Helper ist kein Objekt, mit ihm wird
                            nichts verglichen;
  * 'class of TFoo'       - Metaklassen (TClass): kein Beweis gegen den
                            Funktionstyp-Fall, den die Hilfe fuerchtet;
  * Records, 'object'     - nicht nil-vergleichbar;
  * procedure/function/   - genau die Typen, vor denen die Hilfe schuetzt;
    'reference to'
  * Zeigertypen '^T'      - PChar & Co. sind kein Klassen-/Interface-Beweis
                            (sie waeren zwar nil-vergleichbar, aber die
                            Regel heisst 'Klasse oder Interface');
  * Aliasse '= TFoo',     - ein Alias beweist nichts ueber das Ziel; die
    '= type TFoo'           Hilfe loest Aliasse der EIGENEN Unit selbst auf.
Kommentare und Strings sind sicher entfernt; $IFDEF-Zweige werden NICHT
ausgewertet - jeder Zweig zaehlt (Vereinigung).

BEWUSST IN KAUF GENOMMEN: die Zuordnung geht ueber den NAMEN. Nennt ein
Kunde seine Klasse 'TList' oder 'TNode', zaehlt sie als bewiesen - mit
hoher Wahrscheinlichkeit IST sie eine Klasse. Nennt ein Kunde einen
Funktionstyp wie eine RTL-Klasse ('TStringList = function: TObject'), faengt
das der Unit-Beweis vorher ab, sobald die Deklaration in derselben Unit
steht (TRdxExprFixes.ProceduralType laeuft vor PointerLikeType); steht sie
in einer anderen Unit, geht die Hilfe durch - das Restrisiko ist gewollt
(E27).

DETERMINISMUS
=============
Ohne Netz, sortiert, byte-genau reproduzierbar. Der Kopf traegt das Datum
der letzten LISTENAENDERUNG: beim Schreiben bleibt das Datum der Datei,
wenn die Liste gleich bleibt, sonst kommt das heutige (oder --date). Mit
--check wird die Datei mit ihrem eigenen Datum neu erzeugt und byte-genau
verglichen (Gate) - Exit 1 bei Drift, Exit 2, wenn eine Quelle fehlt.

AUFRUF
======
  python tools/gen-rtl-types.py                 # schreibt die .inc
  python tools/gen-rtl-types.py --check         # vergleicht byte-genau
  python tools/gen-rtl-types.py --date 2026-10-14
  python tools/gen-rtl-types.py --source 23.0=D:\\pfad\\source ...
                                                # andere Quellpfade
"""
import datetime
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(ROOT, 'reDelphix', 'source', 'uRdxRtlTypes.inc')
DEFAULT_SOURCES = (
    ('23.0', r'C:\Program Files (x86)\Embarcadero\Studio\23.0\source'),
    ('37.0', r'C:\Program Files (x86)\Embarcadero\Studio\37.0\source'),
)
MAX_LINE = 100
CONST_NAME = 'RDX_RTL_TYPES'

# 'TName = class ...' / 'TName<T> = interface ...'; die Generik-Klammer
# traegt weder '=' noch ';' noch Klammern (haelt den Lauf in der Zeile).
DECL = re.compile(
    r'(?<![\w.])([A-Za-z_]\w*)\s*(?:<[^=;()]{0,200}?>)?\s*=\s*(?:packed\s+)?'
    r'(class\b|interface\b|dispinterface\b|record\b|object\b|procedure\b|'
    r'function\b|reference\b|type\b|\^)\s*([A-Za-z_]\w*)?')
# Woerter, die nie ein Klassenname sein koennen - als Gegenprobe
# (TYPE_KIND_WORDS und die Prozedurtyp-Woerter aus uRdxSimpleFixes).
NEVER = {'class', 'record', 'object', 'interface', 'dispinterface',
         'reference', 'set', 'array', 'string', 'file', 'procedure',
         'function', 'type', 'packed'}


# Kommentare {..}, (*..*), //.. und Strings '..' (mit '' im String; ein
# Zeilenende beendet einen String) - dieselben Regeln wie pasmask der
# Gegenrechnungen, als EIN Regex (ein Zeichenlauf je Datei waere zu langsam).
MASK = re.compile(
    r"\{[^}]*(?:\}|\Z)|\(\*.*?(?:\*\)|\Z)|//[^\r\n]*|'(?:[^'\r\n]|'')*'?",
    re.S)
NON_EOL = re.compile(r'[^\r\n]')


def code_only(text):
    """Kommentare und Strings durch Leerzeichen ersetzt, Zeilenenden bleiben."""
    return MASK.sub(lambda m: NON_EOL.sub(' ', m.group(0)), text)


def read_text(path):
    raw = io.open(path, 'rb').read()
    try:
        return raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        return raw.decode('cp1252', errors='replace')


def classify(kind, follower):
    """Art der Deklaration -> Schluessel der Zaehlung."""
    if kind == 'class':
        if follower == 'helper':
            return 'class helper'
        if follower == 'of':
            return 'class of (Metaklasse)'
        return 'class'
    if kind in ('interface', 'dispinterface'):
        return 'interface'
    if kind in ('record', 'object'):
        return 'record/object'
    if kind in ('procedure', 'function', 'reference'):
        return 'Prozedurtyp'
    if kind == '^':
        return 'Zeigertyp'
    return "'= type' Alias"


def collect(label, base, names, counts, per_folder):
    """Alle Deklarationen unter base: names[name] -> set(label),
    counts[(label, art)] -> Zahl, per_folder[(label, ordner)] -> Zahl."""
    files = 0
    # onerror: os.walk ueberspringt ein Verzeichnis, das sich gerade nicht
    # auflisten laesst, sonst STILL - die Liste waere kuerzer und --check
    # meldete DRIFT ohne Grund (einmal beobachtet, 2026-10-14). Laut abbrechen.
    def walk_error(err):
        raise SystemExit('Quellordner nicht lesbar: %s' % err)
    for dp, dn, fn in os.walk(base, onerror=walk_error):
        dn.sort()
        for f in sorted(fn):
            if not f.lower().endswith(('.pas', '.inc')):
                continue
            files += 1
            rel = os.path.relpath(os.path.join(dp, f), base)
            folder = rel.split(os.sep)[0]
            code = code_only(read_text(os.path.join(dp, f)))
            for m in DECL.finditer(code):
                art = classify(m.group(2), (m.group(3) or '').lower())
                counts[(label, art)] = counts.get((label, art), 0) + 1
                if art not in ('class', 'interface'):
                    continue
                name = m.group(1).lower()
                if name in NEVER or not name.isascii():
                    raise SystemExit('unerwarteter Name %r in %s' % (name, rel))
                per_folder[(label, folder)] = per_folder.get((label, folder), 0) + 1
                names.setdefault(name, set()).add(label)
    return files


def pack(names):
    """Sortierte Namen als Pascal-Literale, so viele je Zeile wie in
    MAX_LINE Zeichen passen. Ein Name, der allein nicht in eine Zeile
    passt (WinRT-Handler), wird als 'teil' + 'teil' ueber Zeilen verteilt -
    eine Verkettung von Literalen ist im konstanten Array erlaubt."""
    lines, cur = [], '   '
    total = len(names)
    chunk = MAX_LINE - 10   # Platz fuer Einzug, Quotes, ' +' bzw. ','
    for i, n in enumerate(names):
        tail = ',' if i < total - 1 else ''
        if len(n) > chunk:
            if cur.strip():
                lines.append(cur)
                cur = '   '
            parts = [n[k:k + chunk] for k in range(0, len(n), chunk)]
            for j, p in enumerate(parts):
                lines.append("    '%s'%s" % (p, ' +' if j < len(parts) - 1 else tail))
            continue
        lit = " '%s'%s" % (n, tail)
        if len(cur) + len(lit) > MAX_LINE:
            lines.append(cur)
            cur = '   '
        cur += lit
    if cur.strip():
        lines.append(cur)
    return lines


def wrap(prefix, items):
    """Kommentarzeilen aus prefix und items, je Zeile hoechstens MAX_LINE;
    Folgezeilen eingerueckt."""
    lines, cur = [], prefix
    for k, it in enumerate(items):
        piece = (' ' if k == 0 else ', ') + it
        if len(cur) + len(piece) + 1 > MAX_LINE:
            lines.append(cur + ',')
            cur = '//     ' + it
        else:
            cur += piece
    lines.append(cur)
    return lines


def render(names, sources, counts, per_folder, stand):
    both = sorted(names)
    only = {lab: sum(1 for n in both if names[n] == {lab}) for lab, _ in sources}
    per = {lab: sum(1 for n in both if lab in names[n]) for lab, _ in sources}
    out = []
    w = out.append
    w('// ' + '=' * 74)
    w('// GENERIERT von tools/gen-rtl-types.py - NICHT VON HAND EDITIEREN.')
    w('// Quellen: Embarcadero Studio ' + ' und '.join(lab for lab, _ in sources)
      + ' (<Studio>\\source\\**, .pas und .inc),')
    w('//   Vereinigung beider Staende; Kommentare und Strings entfernt, $IFDEF-')
    w('//   Zweige nicht ausgewertet (jeder Zweig zaehlt).')
    w('// Regel: ein Name steht hier, wenn er dort als class, class(..), class')
    w('//   abstract/sealed, class; (Vorwaertsdeklaration), interface,')
    w('//   interface(..), dispinterface deklariert ist - generisch ohne')
    w('//   Parameter (TList<T> -> tlist), alles klein, sortiert (Binaersuche).')
    w('//   NICHT: class helper, class of (Metaklassen), Records, Prozedurtypen')
    w('//   (procedure/function/reference to), Zeigertypen (^T), Aliasse')
    w('//   (= TFoo, = type TFoo) - keiner davon beweist "Klasse oder Interface".')
    w('// Zweck (Entscheid E27, Nico 2026-10-14): zweiter Beweisweg fuer die')
    w('//   Hilfen SCA084/SCA126 (TRdxExprFixes.PointerLikeType): ein Typ aus')
    w('//   einer anderen Unit gilt als Klasse/Interface, wenn sein Name hier')
    w('//   steht. Die Zuordnung geht ueber den NAMEN - eine Kundenklasse, die')
    w('//   wie eine RTL-Klasse heisst (TList, TNode), zaehlt mit; sie ist mit')
    w('//   hoher Wahrscheinlichkeit auch eine Klasse. Ein Kunden-Funktionstyp')
    w('//   mit RTL-Namen in derselben Unit faengt ProceduralType vorher ab.')
    w('// Stand: %s - %d Namen (%s)' % (
        stand, len(both),
        ', '.join('%s: %d, nur %s: %d' % (lab, per[lab], lab, only[lab])
                  for lab, _ in sources)))
    for lab, _ in sources:
        folders = sorted((f, c) for (l, f), c in per_folder.items() if l == lab)
        out.extend(wrap('//   %s je Ordner (Deklarationen, vor Vereinigung):' % lab,
                        ['%s %d' % fc for fc in folders]))
    for lab, _ in sources:
        arts = sorted((a, c) for (l, a), c in counts.items()
                      if l == lab and a not in ('class', 'interface'))
        out.extend(wrap('//   %s ausgeschlossen:' % lab,
                        ['%s %d' % ac for ac in arts]))
    w('// ' + '=' * 74)
    w('')
    w('const')
    w('  %s: array[0..%d] of string = (' % (CONST_NAME, len(both) - 1))
    out.extend(pack(both))
    w('  );')
    text = '\r\n'.join(out) + '\r\n'
    for ln in out:
        if len(ln) > MAX_LINE:
            raise SystemExit('Zeile laenger als %d: %r' % (MAX_LINE, ln[:60]))
    if not text.isascii():
        raise SystemExit('Ausgabe nicht ASCII')
    return text


STAND_RE = re.compile(r'^// Stand: (\d{4}-\d{2}-\d{2}) - ', re.M)


def existing():
    if not os.path.isfile(DST):
        return None
    return io.open(DST, 'rb').read().decode('ascii', errors='replace')


def list_part(text):
    """Der Teil ab 'const' - die Liste ohne Kopf (fuer den Datumsvergleich)."""
    p = text.find('\r\nconst\r\n')
    return text[p:] if p >= 0 else text


def main(argv):
    check = '--check' in argv
    date = None
    sources = list(DEFAULT_SOURCES)
    custom = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '--date':
            i += 1
            date = argv[i]
        elif a == '--source':
            i += 1
            lab, _, path = argv[i].partition('=')
            custom.append((lab, path))
        elif a != '--check':
            raise SystemExit('unbekanntes Argument: ' + a)
        i += 1
    if custom:
        sources = custom
    for lab, base in sources:
        if not os.path.isdir(base):
            print('Quelle fehlt: %s (%s)' % (base, lab))
            return 2
    names, counts, per_folder = {}, {}, {}
    for lab, base in sources:
        n = collect(lab, base, names, counts, per_folder)
        print('%s: %d Dateien unter %s' % (lab, n, base))
    old = existing()
    old_date = None
    if old:
        m = STAND_RE.search(old)
        old_date = m.group(1) if m else None
    today = datetime.date.today().isoformat()
    if check:
        stand = old_date or today
    else:
        stand = date or old_date or today
    text = render(names, sources, counts, per_folder, stand)
    if not check and date is None and old is not None \
            and list_part(old) != list_part(text):
        # die Liste hat sich geaendert: das Datum der Aenderung
        text = render(names, sources, counts, per_folder, today)
    print('%d Namen' % len(names))
    if check:
        if old is None:
            print('FEHLT: ' + DST)
            return 1
        if old != text:
            print('DRIFT: %s weicht vom Generat ab - tools/gen-rtl-types.py laufen lassen'
                  % os.path.relpath(DST, ROOT))
            # Erste abweichende Zeile mitgeben: ohne sie war ein einmaliges
            # DRIFT (2026-10-14) nicht mehr zu erklaeren.
            for nr, (a, b) in enumerate(zip(old.splitlines(), text.splitlines()), 1):
                if a != b:
                    print('  Zeile %d Datei: %s' % (nr, a[:120]))
                    print('  Zeile %d neu  : %s' % (nr, b[:120]))
                    break
            return 1
        print('OK: ' + os.path.relpath(DST, ROOT))
        return 0
    if old == text:
        print('unveraendert: ' + os.path.relpath(DST, ROOT))
        return 0
    io.open(DST, 'wb').write(text.encode('ascii'))
    print('geschrieben: ' + os.path.relpath(DST, ROOT))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
