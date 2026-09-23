#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""compile_sanity_gate - faengt Fehler, die sonst erst der Compiler sieht.

WARUM ES DIESES GATE GIBT
=========================
Am 2026-09-12 ist die Umsetzung des Detector-Voll-Reviews (99 Commits)
VIER MAL am Bau gescheitert - jedes Mal an einer anderen Fehlerklasse,
und KEIN bestehendes Gate hat eine davon gesehen:

  E2003  msInstanceMethod statt msInstance
         (Enum-Wert nach Gefuehl geschrieben statt nachgeschlagen)
  E2029  'var' ohne Variablendeklaration vor einer nested routine
         (Rest einer Extraktion - die Variablen wanderten mit)
  E2003/E2065  Test in der FALSCHEN Fixture-Klasse implementiert
         (die Unit fuehrt zwei Klassen, der Anker stand in der zweiten)
  E2052  Deklaration in eine Fixture-ZEICHENKETTE gepatcht
         (der Patch-Anker kam auch im String-Literal vor)

pascal_struct_gate prueft Struktur (begin/end, Sektionsreihenfolge),
encoding_gate prueft Bytes. Bezeichner-Aufloesung und Grammatik
INNERHALB eines Deklarationsblocks prueft bisher nur der Compiler - und
der laeuft in diesem Projekt nur bei Nico. Dieses Gate schliesst die
Luecke fuer genau die vier gemessenen Klassen.

Jede Pruefung ist gegen den KAPUTTEN Stand gegengeprueft worden: sie
meldet dort die Zeilen, die auch dcc32 nennt.

AUFRUF
======
  python tools/compile_sanity_gate.py                 # geaenderte Dateien (main..HEAD + Arbeitsbaum)
  python tools/compile_sanity_gate.py <datei> [...]   # gezielt
  python tools/compile_sanity_gate.py --all           # ganzer Baum

Exit 0 = gruen, 1 = Befunde.
"""
import io
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KONST = os.path.join(REPO, 'SCA.Engine', 'sources', 'Common', 'uSCAConsts.pas')
REGISTRY = os.path.join(REPO, 'SCA.Engine', 'sources', 'Infrastructure',
                        'uStaticAnalyzer2.pas')
HARNESS = os.path.join(REPO, 'StaticCodeAnalyserForm', 'tests',
                       'uTestFindingHelper.pas')


def lies(pfad):
    return io.open(pfad, encoding='utf-8', errors='replace').read()


def zeilen(pfad):
    return lies(pfad).replace('\r\n', '\n').split('\n')


# --------------------------------------------------------------------------
# 1) Offene String-Literale
# --------------------------------------------------------------------------
def pruefe_apostrophe(pfad, befunde):
    """Pascal-Strings gehen nie ueber Zeilen - jede Code-Zeile hat also
    eine GERADE Zahl Apostrophe. Faengt E2052; genau so ist eine
    Deklaration in einer Fixture-Zeichenkette gelandet."""
    inbrace = inparen = False
    for nr, ln in enumerate(zeilen(pfad), 1):
        code = []
        i = 0
        instr = False
        while i < len(ln):
            c = ln[i]
            nxt = ln[i + 1] if i + 1 < len(ln) else ''
            if inbrace:
                if c == '}':
                    inbrace = False
                i += 1
                continue
            if inparen:
                if c == '*' and nxt == ')':
                    inparen = False
                    i += 2
                    continue
                i += 1
                continue
            if not instr and c == '/' and nxt == '/':
                break
            if not instr and c == '{':
                inbrace = True
                i += 1
                continue
            if not instr and c == '(' and nxt == '*':
                inparen = True
                i += 2
                continue
            if c == chr(39):
                instr = not instr
                code.append(c)
                i += 1
                continue
            code.append(c)
            i += 1
        if ''.join(code).count(chr(39)) % 2 == 1:
            befunde.append('%s:%d  offener String (E2052): %s'
                           % (os.path.basename(pfad), nr, ln.strip()[:60]))


# --------------------------------------------------------------------------
# 2) Deklarationsblock ohne Eintrag
# --------------------------------------------------------------------------
def pruefe_leere_deklarationsbloecke(pfad, befunde):
    """'var'/'const'/'type', dessen erster echter Eintrag eine nested
    routine oder direkt 'begin' ist. Faengt E2029."""
    L = zeilen(pfad)
    for i, ln in enumerate(L):
        if not re.match(r'^\s*(var|const|type)\s*$', ln, re.I):
            continue
        for j in range(i + 1, min(i + 15, len(L))):
            s = L[j].strip()
            if not s or s.startswith('//'):
                continue
            if re.match(r'^(function|procedure)\b', s, re.I):
                befunde.append('%s:%d  %s ohne Eintrag vor nested routine '
                               '(E2029)' % (os.path.basename(pfad), i + 1,
                                            ln.strip()))
            elif re.match(r'^begin\b', s, re.I):
                befunde.append('%s:%d  %s ohne Eintrag vor begin (E2029)'
                               % (os.path.basename(pfad), i + 1, ln.strip()))
            break



def pruefe_doppeltes_routinenende(pfad, befunde):
    """Zwei 'end;' in Spalte 0 direkt hintereinander.

    In diesem Projekt schliesst ein 'end;' in Spalte 0 immer eine
    Routine - nested routines sind eingerueckt. Zwei davon in Folge
    heisst also: eine Routine wurde zweimal beendet, und der Compiler
    liest das zweite als Unit-Ende ohne Punkt (E2029 "'.' erwartet, aber
    ';' gefunden").

    Entstanden 2026-09-13 an uTestCanBeClassMethod: ein Patch-Skript
    schnitt den alten Testrumpf am 'end;' von 'finally F.Free; end;' ab
    und liess das Routinen-'end;' stehen. Weder struct_gate noch dieses
    Gate sahen es - der Bau brach.

    Gegen den Bestand geprueft: NULL Vorkommen ueber alle .pas des
    Projekts, die Regel ist also nicht laut.
    """
    L = zeilen(pfad)
    vorher = None
    vorher_nr = 0
    for i, ln in enumerate(L, 1):
        s = ln.rstrip()
        if not s.strip() or s.lstrip().startswith('//'):
            continue
        if s == 'end;' and vorher == 'end;':
            befunde.append('%s:%d  zweites "end;" in Spalte 0 direkt nach '
                           'Zeile %d - eine Routine wird doppelt beendet '
                           '(E2029)'
                           % (os.path.basename(pfad), i, vorher_nr))
        vorher = s
        vorher_nr = i

# --------------------------------------------------------------------------
# 3) Enum-Werte, die es nicht gibt
# --------------------------------------------------------------------------
def sammle_deklarierte_enums():
    alle = ''
    for root, _dirs, fn in os.walk(os.path.join(REPO, 'SCA.Engine')):
        for f in fn:
            if f.endswith('.pas'):
                alle += lies(os.path.join(root, f)) + '\n'
    werte = set()
    for prefix in ('fk', 'nk', 'fc', 'ls', 'ms'):
        pat = prefix + r'[A-Z][A-Za-z0-9_]*'
        werte |= set(re.findall(r'^\s*(' + pat + r')\s*[,)]', alle, re.M))
        # LOOKAHEAD statt verbrauchendem Trennzeichen. Die alte Fassung
        # frass das nachfolgende Komma, und bei mehreren Werten auf EINER
        # Zeile fand sie nur jeden zweiten:
        #     nkIndex, nkDot, nkDeref,
        # -> nkIndex (Muster 1), nkDot (Muster 2), nkDeref FEHLT, weil
        # sein fuehrendes Komma schon zu nkDot gehoerte. Ergebnis war ein
        # Fehlalarm "unbekannter Enum-Wert nkDeref" auf einer Datei, die
        # ihn korrekt deklariert - er lief zwei Chargen mit, weil er nur
        # im --all-Lauf auftaucht.
        werte |= set(re.findall(r'[(,]\s*(' + pat + r')\s*(?=[,)])', alle))
    return werte


def _codeteil(zeile):
    """'//'-Kommentar abschneiden, aber nur AUSSERHALB eines Literals.

    Die naive Variante (ohne_kommentar) reicht hier nicht: Fixture-Zeilen
    tragen '//' regelmaessig INNERHALB des Literals, und ein Abschnitt an
    der falschen Stelle macht aus einer korrekten Zeile einen Fehlalarm.
    """
    out = []
    instr = False
    i = 0
    while i < len(zeile):
        c = zeile[i]
        if c == "'":
            if instr and i + 1 < len(zeile) and zeile[i + 1] == "'":
                out.append("''")
                i += 2
                continue
            instr = not instr
        if (not instr) and c == '/' and i + 1 < len(zeile) \
           and zeile[i + 1] == '/':
            break
        out.append(c)
        i += 1
    return ''.join(out).rstrip()


def pruefe_uses_zuerst(pfad, befunde):
    """uses steht NICHT als erste Klausel nach interface/implementation.

    Pascal erlaubt die uses-Klausel nur UNMITTELBAR nach
    "interface" bzw. "implementation". Steht vorher irgendeine andere
    Deklaration - ein const-Block, ein type, eine forward-Routine -,
    meldet dcc32 E2029 "Deklaration erwartet, aber 'USES' gefunden"
    und danach jeden einzelnen Bezeichner der ueberlesenen
    uses-Klausel als undeklariert. Aus EINEM verrutschten Block
    werden so 50+ Folgefehler, und die eigentliche Ursache steht
    ganz oben in einer langen Liste.

    Genau so ist der M1-Bau am 2026-09-20 gescheitert: eine neue
    Konstante MAX_HINT_CHARS wurde direkt hinter "implementation"
    eingefuegt statt in den const-Block dahinter.

    Geprueft wird nur die SPALTE 0 - eine uses-Klausel und die
    Klauseln, die sie verdraengen koennen, stehen immer dort. Ein
    eingeruecktes "function" im Rumpf einer Klasse bleibt so
    ausserhalb der Betrachtung.
    """
    # Was eine uses-Klausel verdraengt. "label"/"threadvar" sind der
    # Vollstaendigkeit halber dabei, im Projekt kommen sie nicht vor.
    KLAUSELN = ('const', 'type', 'var', 'resourcestring',
                'threadvar', 'label', 'function', 'procedure',
                'constructor', 'destructor', 'operator')
    ENDE = ('initialization', 'finalization', 'end.')
    sektion = None      # Name der offenen Sektion, None = keine
    sperre = None       # (Zeilennr, Wort) der ersten anderen Klausel
    imblock = False     # in einem { }- oder (* *)-Kommentar
    for i, roh in enumerate(zeilen(pfad)):
        z = _codeteil(roh)
        # Blockkommentare grob ueberspringen. Genauer muss es nicht
        # sein: die Pruefung sieht ohnehin nur Spalte 0 an.
        if imblock:
            if '}' in z or '*)' in z:
                imblock = False
            continue
        if (z.lstrip().startswith('{')
                or z.lstrip().startswith('(*')) \
           and not ('}' in z or '*)' in z):
            imblock = True
            continue
        if z[:1].isspace() or not z.strip():
            continue
        wort = z.strip().split()[0].rstrip(';').lower()
        if wort in ('interface', 'implementation'):
            sektion, sperre = wort, None
            continue
        if sektion is None:
            continue
        if wort in ENDE:
            sektion, sperre = None, None
            continue
        if wort == 'uses' and sperre is not None:
            befunde.append(
                '%s:%d  uses steht nach %s (Zeile %d) statt '
                'direkt hinter %s (E2029)'
                % (os.path.basename(pfad), i + 1, sperre[1], sperre[0],
                   sektion))
            sektion, sperre = None, None
            continue
        if wort in KLAUSELN and sperre is None:
            sperre = (i + 1, wort)

def pruefe_unbeendete_konstante(pfad, befunde):
    """Fixture-Konstante, die nicht mit ';' abgeschlossen wird.

    Eine 'const SRC = ...'-Deklaration endet entweder mit '+' (ein
    weiteres Literal folgt) oder mit ';'. Fehlt beides und danach beginnt
    der var-Block oder der Rumpf, laeuft die Deklaration in den Code
    hinein und der Bau bricht.

    Entstanden 2026-09-13 an uTestDuplicate: ein Patch-Skript baute die
    letzte Fixture-Zeile als "  'end;'" statt "  'end;';". Weder
    struct_gate noch die Selbstpruefung von insert_test.py sahen es -
    Nico musste den Bau von Hand reparieren.

    ENG GEFASST, und das ist Absicht. Die erste Fassung pruefte jede
    Literal-Zeile vor einem 'var'/'begin' und lieferte 52 Fehlalarme im
    Produktivcode - allesamt case-Labels der Form "'>': if ... then" mit
    'begin' auf der Folgezeile. Deshalb gilt die Pruefung nur in
    Testdateien und nur INNERHALB einer offenen const-Deklaration.
    """
    L = zeilen(pfad)
    im_const = False
    for i, ln in enumerate(L[:-1]):
        s = _codeteil(ln).strip()
        low = s.lower()
        if low == 'const' or low.startswith('const '):
            im_const = True
            if s.endswith(';'):
                im_const = False
            continue
        if not im_const:
            continue
        if not s:
            continue
        if s.endswith(';'):
            im_const = False
            continue
        if not s.startswith("'"):
            continue
        if s.endswith('+'):
            continue
        nxt = _codeteil(L[i + 1]).strip()
        if nxt == 'begin' or nxt == 'var' or nxt.startswith('var '):
            befunde.append(
                '%s:%d  const-Deklaration endet weder auf "+" noch auf '
                '";", danach folgt "%s" - der Bau bricht'
                % (os.path.basename(pfad), i + 1, nxt.split()[0]))
            im_const = False


def ohne_kommentar(text):
    out = []
    for ln in text.split('\n'):
        i = ln.find('//')
        out.append(ln[:i] if i >= 0 else ln)
    return '\n'.join(out)


# --------------------------------------------------------------------------
# 3b) Token-Vokabular je Parser (G-Charge 2026-09-19)
# --------------------------------------------------------------------------
# Das 'tk'-Praefix laeuft BEWUSST nicht ueber sammle_deklarierte_enums:
# eine projektweite Werteliste taugt hier nicht. Im Repo gibt es ZWEI
# Token-Enums mit ueberlappenden Namen (uLexer.TTokenKind fuer Pascal,
# uDfmLexer.TDfmTokenKind fuer DFM - letzteres fuehrt tkString,
# tkInteger, tkFloat, tkSet), und darueber liegt System.TTypeKind aus
# System.pas, das OHNE uses-Klausel in jeder Unit sichtbar ist und 22
# weitere tk-Namen mitbringt (tkArray, tkClass, tkRecord, tkMethod,
# tkPointer, tkString, ...). Ein projektweiter Namenstopf wuerde also
# genau den Fehler durchlassen, der diese Pruefung ausgeloest hat:
# 'tkString' in uParser2 (Bau 1 der G-Charge, E2010 'Inkompatible
# Typen: TTokenKind und TTypeKind') ist projektweit bekannt - nur eben
# aus dem FALSCHEN Enum. Deshalb je Konsument-Unit gegen GENAU ihr
# Token-Enum pruefen.
TOKEN_VOKABULAR = {
    'uparser2.pas': ('SCA.Engine/sources/Parsing/uLexer.pas', 'TTokenKind'),
    'udfmparser.pas': ('SCA.Engine/sources/Parsing/uDfmLexer.pas',
                       'TDfmTokenKind'),
}


def _enum_werte(pfad, typname):
    """Werteliste einer Enum-Deklaration 'TName = (a, b, c);'."""
    t = lies(pfad)
    m = re.search(re.escape(typname) + r'\s*=\s*\((.*?)\)\s*;', t, re.S)
    if not m:
        return set()
    rumpf = re.sub(r'//[^\n]*', '', m.group(1))
    rumpf = re.sub(r'\{.*?\}', '', rumpf, flags=re.S)
    return set(x.strip() for x in rumpf.replace('\n', ' ').split(',')
               if x.strip())


RE_INCLUDE_DIREKTIVE = re.compile(r'\{\$(?:I|INCLUDE)[ \t]', re.I)


def pruefe_include_in_fixture(pfad, befunde):
    """'{$I datei}' AUSSERHALB eines Stringliterals in einer Testunit.

    Faengt F1026 ('Datei nicht gefunden'). Fixtures fuehren das
    Include-Muster als TESTDATEN - dann gehoert es in ein Literal. Ohne
    Hochkommata fuehrt der COMPILER die Direktive aus und sucht die
    Datei. Genau so verloren gegangen (H-Charge, 2026-09-20): ein
    Einfuege-Skript liess die Hochkommata weg, weil Python benachbarte
    String-Literale verkettet - aus "  '...''{$I x}''...'" wurde
    "  ...{$I x}...".

    Nur tests/: im Produktivcode sind Include-Direktiven normal. Die
    Paritaetszaehlung der Hochkommata bis zur Fundstelle reicht, weil
    ein Pascal-Literal nie ueber das Zeilenende geht.
    """
    if os.sep + 'tests' + os.sep not in pfad.replace('/', os.sep):
        return
    for i, ln in enumerate(zeilen(pfad), 1):
        code = _codeteil(ln)
        for m in RE_INCLUDE_DIREKTIVE.finditer(code):
            if code[:m.start()].count("'") % 2 == 0:
                befunde.append(
                    '%s:%d  Include-Direktive ausserhalb eines Literals '
                    '(F1026) - in Fixtures gehoert sie in Hochkommata: %s'
                    % (os.path.basename(pfad), i, ln.strip()[:60]))


def pruefe_token_vokabular(pfad, befunde):
    """tk-Bezeichner eines Parsers gegen SEIN Token-Enum. Faengt E2010
    (Wert aus System.TTypeKind oder dem anderen Lexer)."""
    eintrag = TOKEN_VOKABULAR.get(os.path.basename(pfad).lower())
    if not eintrag:
        return
    quelle, typ = eintrag
    erlaubt = _enum_werte(os.path.join(REPO, quelle), typ)
    if not erlaubt:
        befunde.append('%s  Token-Enum %s in %s nicht lesbar - Pruefung '
                       'haette still gepasst'
                       % (os.path.basename(pfad), typ, quelle))
        return
    t = ohne_kommentar(lies(pfad))
    for sym in sorted(set(re.findall(r'\b(tk[A-Z][A-Za-z0-9_]*)\b', t))):
        if sym not in erlaubt:
            befunde.append('%s  Token-Wert nicht in %s.%s (E2010): %s'
                           % (os.path.basename(pfad), os.path.basename(quelle),
                              typ, sym))


# --------------------------------------------------------------------
# 3c) RTL-Typ ohne seine uses-Unit (N-Charge 2026-09-21)
# --------------------------------------------------------------------
# Delphi loest Bezeichner NICHT transitiv auf: eine Unit sieht nur,
# was in ihren EIGENEN uses-Klauseln steht. Wer TStringList benutzt,
# ohne System.Classes einzubinden, bekommt E2003 - und danach eine
# lange Folgekaskade, weil der Parser an der ersten unbekannten
# Deklaration aus dem Tritt geraet (gemessen am 2026-09-21: EIN
# fehlendes System.Classes in uFixHint = 36 Fehlerzeilen).
#
# Die Tabelle ist bewusst kurz und enthaelt nur EINDEUTIGE Namen -
# "TList" steht z.B. NICHT drin: den Namen gibt es
# sowohl in System.Classes als auch (generisch) in
# System.Generics.Collections.
RTL_TYPEN = {
    'TStringList': 'System.Classes',
    'TStringBuilder': 'System.SysUtils',
    'TDictionary<': 'System.Generics.Collections',
    'TObjectList<': 'System.Generics.Collections',
    'TObjectDictionary<': 'System.Generics.Collections',
    'TStopwatch': 'System.Diagnostics',
    'TRegEx': 'System.RegularExpressions',
}

# Dasselbe fuer FUNKTIONEN - die Luecke, durch die am 2026-09-21 der
# ZWEITE rote Bau ging: Trim/LowerCase in einer Testunit ohne
# System.SysUtils. Die Typtabelle oben konnte das nicht sehen.
#
# Nur als freier Aufruf gezaehlt, also NICHT nach einem Punkt: 's.Trim'
# ist der String-Helper und braucht kein uses.
RTL_FUNKTIONEN = {
    'Trim': 'System.SysUtils',
    'LowerCase': 'System.SysUtils',
    'UpperCase': 'System.SysUtils',
    'SameText': 'System.SysUtils',
    'StringReplace': 'System.SysUtils',
    'IntToStr': 'System.SysUtils',
    'StrToIntDef': 'System.SysUtils',
    'FreeAndNil': 'System.SysUtils',
    'Max': 'System.Math',
    'Min': 'System.Math',
}


def pruefe_rtl_uses(pfad, befunde):
    """Benutzter RTL-Typ, dessen Unit in keiner uses-Klausel steht."""
    t = lies(pfad)
    # Kommentare UND Zeichenketten weg: Fixture-Literale in den
    # Testunits enthalten massenhaft Pascal-Code, der hier nicht
    # zaehlt - er wird ja nicht von DIESER Unit compiliert.
    code = []
    for z in t.split('\n'):
        code.append(_codeteil(z))
    code = '\n'.join(code)
    code = re.sub(r"'(?:[^']|'')*'", '', code)
    code = re.sub(r"\{[^}]*\}", ' ', code, flags=re.S)
    # Alle uses-Klauseln der Datei (interface UND implementation).
    benutzt = ' '.join(
        m.group(1) for m in re.finditer(
            r"\buses\b(.*?);", code, re.S | re.I))
    for typ, unit in RTL_TYPEN.items():
        if typ.endswith('<'):
            muster = r"\b" + re.escape(typ)
        else:
            muster = r"\b" + re.escape(typ) + r"\b"
        if not re.search(muster, code):
            continue
        # Voll qualifiziert (System.Classes.TStringList) braucht kein
        # uses - dann steht der Unitname direkt davor.
        if re.search(re.escape(unit) + r"\s*\." + re.escape(
                     typ.rstrip('<')), code):
            continue
        kurz = unit.split('.')[-1]
        if re.search(r"\b" + re.escape(unit) + r"\b", benutzt) or \
           re.search(r"\b" + re.escape(kurz) + r"\b", benutzt):
            continue
        befunde.append(
            '%s  %s benutzt, aber %s steht in keiner '
            'uses-Klausel (E2003)'
            % (os.path.basename(pfad), typ.rstrip('<'), unit))

    for fn, unit in RTL_FUNKTIONEN.items():
        # (?<![.&\w]) schliesst den String-Helper 's.Trim' aus und
        # verhindert Teiltreffer in laengeren Bezeichnern.
        if not re.search(r'(?<![.&\w])' + fn + r'\s*\(', code):
            continue
        kurz = unit.split('.')[-1]
        if re.search(r'\b' + re.escape(unit) + r'\b', benutzt) or \
           re.search(r'\b' + re.escape(kurz) + r'\b', benutzt):
            continue
        # Eine Unit, die selbst so eine Routine deklariert, meint ihre
        # eigene - kein Befund.
        if re.search(r'\b(?:function|procedure)\s+' + fn + r'\b',
                     code, re.I):
            continue
        befunde.append(
            '%s  %s() benutzt, aber %s steht in keiner '
            'uses-Klausel (E2003)'
            % (os.path.basename(pfad), fn, unit))

def pruefe_enums(pfad, deklariert, befunde):
    """Benutzte fk/nk/fc/ls/ms-Werte gegen die Deklarationen. Faengt
    E2003 ('msInstanceMethod' statt 'msInstance')."""
    t = ohne_kommentar(lies(pfad))
    for prefix in ('fk', 'nk', 'fc', 'ls', 'ms'):
        for sym in sorted(set(re.findall(r'\b(' + prefix +
                                         r'[A-Z][A-Za-z0-9_]*)\b', t))):
            if sym not in deklariert:
                befunde.append('%s  unbekannter Enum-Wert (E2003): %s'
                               % (os.path.basename(pfad), sym))


# --------------------------------------------------------------------------
# 4) Test in der falschen Fixture-Klasse
# --------------------------------------------------------------------------
RE_CLASS = re.compile(r'^\s{0,4}(T[A-Za-z0-9_]+)\s*=\s*class\b', re.I)
RE_DECL = re.compile(
    r'^\s*(?:\[[A-Za-z]\w*(?:\([^)]*\))?\]\s*)*'
    r'(?:class\s+)?(?:procedure|function)\s+([A-Za-z0-9_]+)'
    r'\s*(?:\([^)]*\))?\s*(?::\s*[A-Za-z0-9_<>., ]+)?\s*;'
    r'\s*(?://.*)?$', re.I)
RE_IMPL = re.compile(r'^\s*(?:class\s+)?(?:procedure|function)\s+'
                     r'(T[A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\b', re.I)


def pruefe_fixture_klassen(pfad, befunde):
    """Deklarations-Klasse gegen Implementierungs-Praefix. Faengt
    E2003/E2065, wenn eine Unit mehrere Fixtures fuehrt."""
    L = zeilen(pfad)
    decl, impl, cur, inimpl = {}, {}, None, False
    for nr, ln in enumerate(L, 1):
        if re.match(r'^implementation\b', ln, re.I):
            inimpl = True
        if not inimpl:
            m = RE_CLASS.match(ln)
            if m:
                cur = m.group(1)
            m = RE_DECL.match(ln)
            if m and cur:
                # Doppelte Deklaration desselben Namens in derselben
                # Klasse - der Compiler meldet sie ZUERST (E2252/E2254),
                # noch vor der doppelten Implementierung. Passiert beim
                # Nachruesten von Tests, wenn der Name schon existiert
                # (2026-09-13: StrictPrivateTwice_Reported).
                if decl.get(m.group(1).lower()) == cur:
                    befunde.append('%s:%d  %s ist in %s DOPPELT deklariert '
                                   '(E2252/E2254)'
                                   % (os.path.basename(pfad), nr,
                                      m.group(1), cur))
                decl[m.group(1).lower()] = cur
        else:
            m = RE_IMPL.match(ln)
            if m:
                key = m.group(2).lower()
                if key in impl and impl[key][0].lower() == m.group(1).lower():
                    befunde.append('%s:%d  %s.%s ist DOPPELT implementiert '
                                   '(E2004)'
                                   % (os.path.basename(pfad), nr,
                                      m.group(1), m.group(2)))
                impl[key] = (m.group(1), nr)
    for name, (kls, nr) in impl.items():
        if name in decl and decl[name].lower() != kls.lower():
            befunde.append('%s:%d  %s ist in %s deklariert, aber als %s '
                           'implementiert (E2065)'
                           % (os.path.basename(pfad), nr, name, decl[name], kls))


# --------------------------------------------------------------------------
# 5) Harness kennt den Detektor nicht
# --------------------------------------------------------------------------
def lade_harness_wissen():
    # AddD, AddD2, AddD3 - die Registry hat mehrere Ueberladungen, und
    # die Ziffer entscheidet nur ueber Vorfilter/Kontext, nicht ueber
    # die Zuordnung Kind -> Detektor. Die alte Fassung band nur 'AddD('
    # und uebersah damit JEDEN AddD3-Detektor: kind2cls hatte keinen
    # Eintrag, pruefe_harness sprang still ueber ihn hinweg, und vier
    # Tests standen im falschen Helfer, ohne dass das Gate etwas sagte
    # (Bau vom 2026-09-14: sieben rote Tests, vier davon aus dieser
    # Luecke).
    kind2cls = {}
    for m in re.finditer(r"AddD\d?\(\s*'[^']*'\s*,\s*(fk[A-Za-z0-9_]+)\s*,\s*"
                         r"(T[A-Za-z0-9_]+)\.", lies(REGISTRY)):
        kind2cls.setdefault(m.group(1).lower(), set()).add(m.group(2).lower())
    HL = lies(HARNESS).replace('\r\n', '\n').split('\n')
    grenzen = []
    for i, ln in enumerate(HL):
        m = re.match(r'^class function TFindingHelper\.(FindingsOf\w*)', ln)
        if m:
            grenzen.append((m.group(1), i))
    grenzen.append(('__ende__', len(HL)))
    helfer = {}
    for k in range(len(grenzen) - 1):
        name, start = grenzen[k]
        dets = set()
        for ln in HL[start:grenzen[k + 1][1]]:
            m = re.search(r'\b(T[A-Za-z0-9_]+)\.Analyze(?:Unit|Method)\b', ln)
            if m:
                dets.add(m.group(1).lower())
        helfer[name] = dets
    return kind2cls, helfer


def pruefe_harness(pfad, kind2cls, helfer, befunde, warnungen):
    """Ein Test prueft auf ein fkXxx, dessen Detektor im gewaehlten
    Helfer nicht laeuft. Kein Compiler-Fehler, aber ein Test, der
    NICHTS misst - und genau so sind drei Tests rot geworden."""
    L = zeilen(pfad)
    start = None
    name = None
    for i, ln in enumerate(L):
        m = re.match(r'^procedure\s+T[A-Za-z0-9_]+\.([A-Za-z0-9_]+)\s*;', ln)
        if m:
            start, name = i, m.group(1)
            continue
        if start is None:
            continue
        if re.match(r'^end;\s*$', ln):
            block = '\n'.join(L[start:i + 1])
            hs = set(re.findall(r'TFindingHelper\.(FindingsOf\w*)\(', block))
            ks = set(k.lower() for k in re.findall(r'\b(fk[A-Za-z0-9_]+)\b', block))
            for h in hs:
                if h not in helfer:
                    continue
                for kd in ks:
                    dets = kind2cls.get(kd)
                    if not dets:
                        continue
                    if not (dets & helfer[h]):
                        befunde.append('%s:%d  %s prueft %s ueber %s - dort '
                                       'laeuft KEIN Detektor dafuer'
                                       % (os.path.basename(pfad), start + 1,
                                          name, kd, h))
                    elif dets - helfer[h]:
                        warnungen.append('%s:%d  %s prueft %s ueber %s - nicht '
                                         'im Helfer: %s'
                                         % (os.path.basename(pfad), start + 1,
                                            name, kd, h,
                                            ', '.join(sorted(dets - helfer[h]))))
            start = None


# --------------------------------------------------------------------------
def dateien_bestimmen(argv):
    if argv and argv[0] == '--all':
        out = []
        for teil in ('SCA.Engine', 'SCA.SharedUI', 'StaticCodeAnalyserForm',
                     'StaticCodeAnalyserIDE'):
            for root, _d, fn in os.walk(os.path.join(REPO, teil)):
                out += [os.path.join(root, f) for f in fn if f.endswith('.pas')]
        return out
    if argv:
        return [a for a in argv if a.endswith('.pas')]
    r = subprocess.run(['git', 'diff', '--name-only', 'main...HEAD', '--', '*.pas'],
                       capture_output=True, text=True, cwd=REPO)
    aus = set(r.stdout.split())
    r = subprocess.run(['git', 'diff', '--name-only', '--', '*.pas'],
                       capture_output=True, text=True, cwd=REPO)
    aus |= set(r.stdout.split())
    return [os.path.join(REPO, p) for p in sorted(aus)]


def main():
    dateien = [d for d in dateien_bestimmen(sys.argv[1:]) if os.path.exists(d)]
    if not dateien:
        print('compile_sanity_gate: keine .pas-Dateien zu pruefen.')
        return 0
    deklariert = sammle_deklarierte_enums()
    kind2cls, helfer = lade_harness_wissen()
    befunde, warnungen = [], []
    for d in dateien:
        pruefe_apostrophe(d, befunde)
        pruefe_leere_deklarationsbloecke(d, befunde)
        pruefe_doppeltes_routinenende(d, befunde)
        pruefe_enums(d, deklariert, befunde)
        pruefe_token_vokabular(d, befunde)
        pruefe_include_in_fixture(d, befunde)
        pruefe_uses_zuerst(d, befunde)
        pruefe_rtl_uses(d, befunde)
        if os.sep + 'tests' + os.sep in d.replace('/', os.sep):
            pruefe_unbeendete_konstante(d, befunde)
            pruefe_fixture_klassen(d, befunde)
            pruefe_harness(d, kind2cls, helfer, befunde, warnungen)
    for w in warnungen:
        print('WARNUNG  ' + w)
    for b in befunde:
        print('BEFUND   ' + b)
    print()
    if befunde:
        print('GATE ROT: %d Datei(en) geprueft, %d Befund(e), %d Warnung(en).'
              % (len(dateien), len(befunde), len(warnungen)))
        return 1
    print('GATE GRUEN: %d Datei(en) geprueft, keine Befunde, %d Warnung(en).'
          % (len(dateien), len(warnungen)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
