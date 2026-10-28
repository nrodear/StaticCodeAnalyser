#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen-quickfix-doc.py - erzeugt reDelphix/QUICKFIXES.md: alle Quick-Fixes
(Code-Aktionen) des Moduls reDelphix mit Regel, Menuetext en/de/fr, Wirkung,
Sperren, Kennzeichnung und Beispiel (Entscheid E30, Nico 2026-10-15).

WOHER WAS KOMMT - je Angabe EINE Quelle:

  welche Hilfen es gibt,     reDelphix/source/uRdxFixTable.pas: FIX_ROWS,
  ihre Menuetexte (msgids)   FIX_CAPTIONS und FIX_ALT_CAPTIONS (parallele
  und die Kennzeichnung (E2) Arrays, Index fuer Index; dazu FIX_HINTS, die
                             festen Hinweise - nur fuer die Konsistenz,
                             nicht in der Doku) und die Planer;
                             reDelphix/source/uRdxFixRunner.pas (Rumpf-
                             Routinen, die die Kennzeichnung setzen; bis
                             Charge B2S-b in uRdxRecipeRunner.pas);
                             reDelphix/source/uRdxActionCore.pas: die Rezepte
                             des Anbieters (Konstruktor des Kerns, seit E3
                             2026-10-28; bis dahin uRdxProvider.pas), ihre
                             Menuetexte (CAP_*, _('..')), Art (fakFix ...)
                             und Regel-Bindung (fixMode, Fundart)
  Regel-ID, Name, editorHelp rules/sca-rules.json
  Menuetexte de/fr           i18n/de.po, i18n/fr.po - gelesen wie
                             uLocalization.ParsePo (leeres msgstr = keine
                             Uebersetzung, erster Treffer gewinnt)
  Titel, Wirkung, Sperren,   reDelphix/data/quickfixes-doc.json (von Hand
  Beispiele, Hinweise        gepflegt; die Beispiele stammen aus den Tests
                             reDelphix/tests/uTestRdx*.pas)

AUFRUF (Repo-Wurzel):
  python tools/gen-quickfix-doc.py              # QUICKFIXES.md schreiben
  python tools/gen-quickfix-doc.py --check      # nur pruefen (CI)
  python tools/gen-quickfix-doc.py --list       # Inventar zeigen
  python tools/gen-quickfix-doc.py --selftest   # das Gate an Mutanten pruefen

--check prueft zweierlei, beides Exit 1:
  KONSISTENZ  jede Art in FIX_ROWS und jedes Rezept hat einen Eintrag in
              quickfixes-doc.json, jeder Eintrag dort gehoert zu einer Art
              bzw. einem Rezept; jede Art mit editorHelp im Katalog hat eine
              Zeile in FIX_ROWS oder ein Rezept, das sie bindet, und jede
              Zeile traegt editorHelp, ebenso jede Regel, die ein
              Quick-Fix-Rezept (fakFix) bindet; die vier Arrays (FIX_ROWS,
              FIX_CAPTIONS, FIX_ALT_CAPTIONS, FIX_HINTS) sind gleich lang,
              ein fester Hinweis steht in FIX_HINTS genau bei HintByPlanner =
              False (wie uTestRdxFixTable, das nur der IDE-Bau laeuft); die
              Pflichtfelder sind da (Platzhalter erklaert, Kennzeichnung "je
              nach Fund" erklaert, zweiter Eintrag beschrieben); jede Art
              mit Hilfe steht im Profil code-aktionen
              (reDelphix/data/profile-code-aktionen.json), keine ohne Hilfe
              ausser PROFILE_EXTRA. Quellfehler (Exit 2) ist eine Unit in
              reDelphix/source, die 'ChangesBehavior :=' setzt, ohne dass
              der Generator sie liest (Tabelle, Laeufer, Kern des
              Anbieters) und ohne Grund in NOT_DOCUMENTED.
  DRIFT       QUICKFIXES.md ist byte-gleich mit dem, was der Generator jetzt
              schreiben wuerde (UTF-8 mit BOM, CRLF - so liegt jede .md im
              Checkout, .gitattributes: *.md eol=crlf); gemeldet wird die
              erste abweichende Zeile.
Der Generator schreibt nichts, solange die Konsistenz verletzt ist. Eine
fehlende Uebersetzung ist KEIN Fehler (die IDE zeigt dann die englische
msgid): sie steht sichtbar als '(fehlt)' in der Datei, --check nennt sie
als Hinweis.

Neue Hilfe: Zeile in FIX_ROWS (bzw. Rezept im Konstruktor des Kerns)
-> Eintrag in quickfixes-doc.json -> Art ins Profil code-aktionen
-> python tools/gen-quickfix-doc.py.

EXIT: 0 gruen, 1 Konsistenz oder Drift (Selbsttest: ein Mutant blieb
unentdeckt), 2 Aufruf- oder Quellfehler (Datei fehlt, Quelltext in einer
Form, die der Generator nicht kennt - lieber laut abbrechen als still
falsch dokumentieren).
"""
import argparse
import copy
import glob
import json
import os
import re
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RDX = os.path.join(REPO, 'reDelphix')
SRC_TABLE = os.path.join(RDX, 'source', 'uRdxFixTable.pas')
SRC_RUNNER = os.path.join(RDX, 'source', 'uRdxFixRunner.pas')
# Die Rezepte des Anbieters stehen seit Entscheid E3 (2026-10-28) im Kern
# uRdxActionCore (TRdxActionCore, ohne ToolsAPI - die Probe RdxActionProbe
# fragt denselben Kern); uRdxProvider reicht seine Eintraege nur ins Menue.
SRC_CORE = os.path.join(RDX, 'source', 'uRdxActionCore.pas')
CORE_CLASS = 'TRdxActionCore'
# Alle Planer der Tabelle (TRdxFixPlanner) stehen in uRdxFixTable - seit der
# Folgewelle des Wochen-Reviews 2026-10-21 (G09-07) auch die der Chargen Q
# und R; bis dahin trug jede Planer-Unit uRdx*Fix.pas ihren Adapter selbst,
# und der Generator las sie mit (SRC_PLANNER_UNITS, G10-25). Dass keine
# ANDERE Unit 'ChangesBehavior :=' setzt, prueft unmarked_units().
SRC_DIR = os.path.join(RDX, 'source')
# Units, die 'ChangesBehavior :=' setzen, deren Aktionen aber NICHT in
# QUICKFIXES.md gehoeren - je mit Grund (unmarked_units laesst sie aus):
NOT_DOCUMENTED = {
    'uRdxContextRunner.pas':
        'Code-Aktionen ohne Fund (Charge B, fakContext): weder Fund-Hilfe '
        'noch Rezept, QUICKFIXES.md fuehrt sie nicht. Menuetext und '
        'Kennzeichnung sind die der Fund-Hilfen SCA014/SCA009/SCA044 '
        '(uRdxFixTable.ContextCaption, Test uTestRdxContextRunner); Doku: '
        'reDelphix/README.md, "Code-Aktionen ohne Fund".',
    'uRdxProvider.pas':
        'reicht die Kennzeichnung nur durch: die der Eintraege des Kerns '
        '(AddEntry, gesetzt in uRdxActionCore, das der Generator liest) und '
        'die der Code-Aktionen ohne Fund (ProvideContext, aus '
        'uRdxContextRunner, s. dort). Seit Entscheid E3 (2026-10-28).',
}
# Profil code-aktionen (README 'Code-Aktionen in der IDE ausprobieren'): jede
# Art mit Hilfe steht darin, sonst gibt es nach dem Import keinen Fund und
# keine Gluehbirne (Review Woche 2026-10-21, G10-05). Arten im Profil OHNE
# Hilfe nur mit Grund:
PROFILE = os.path.join(RDX, 'data', 'profile-code-aktionen.json')
PROFILE_NAME = 'code-aktionen'
PROFILE_EXTRA = {
    'FileReadError': 'Lesefehler bleiben sichtbar (README)',
    'UnsortedUses': "ihr Fund auf der uses-Zeile traegt das Refactoring "
                    "'uses: Eintraege qualifizieren' (README-Tabelle); das "
                    "Rezept bindet keine Fundart",
}
CATALOG = os.path.join(REPO, 'rules', 'sca-rules.json')
PO_FILES = (('de', os.path.join(REPO, 'i18n', 'de.po')),
            ('fr', os.path.join(REPO, 'i18n', 'fr.po')))
LANGS = ('en',) + tuple(lang for lang, _ in PO_FILES)
DATA = os.path.join(RDX, 'data', 'quickfixes-doc.json')
OUT = os.path.join(RDX, 'QUICKFIXES.md')

BOM = b'\xef\xbb\xbf'
FEHLT = '(fehlt)'
# Wie tief die Suche nach der Kennzeichnung (ChangesBehavior :=) von einem
# Planer aus in gerufene Routinen der Tabelle und des Laeufers geht: der
# zweite Eintrag (SCA168, SCA020) setzt sie eine Ebene tiefer
# (PlanCaseRaise -> TRdxFixRunner.CaseRaiseFix).
CALL_DEPTH = 2

# Art einer Aktion (uFindingActions, TFindingActionKind) -> Name in der Doku.
ART_NAMES = {
    'fakFix': 'Quick-Fix',
    'fakNavigate': 'Navigation',
    'fakRefactor': 'Refactoring',
    'fakSuppress': 'Unterdrücken',
    # Code-Aktion ohne Fund (Charge B): setzt die Registry
    # (ContextActionsFor), kein Rezept der Fund-Tabelle.
    'fakContext': 'Code-Aktion',
}
# Wo eine gekennzeichnete Hilfe laeuft (Tasten-Policy, uFindingActionMenu).
UEBER_MENUE = 'über Menü oder Glühbirne, nie über Strg+Alt+F'
NIE_TASTE = 'nur ' + UEBER_MENUE


class SourceError(Exception):
    """Eine Quelle fehlt oder hat eine Form, die der Generator nicht kennt
    (Exit 2)."""


def rel(path):
    return os.path.relpath(path, REPO).replace(os.sep, '/')


def load_text(path):
    """Text einer Quelle: UTF-8 (BOM erlaubt), Zeilenenden als LF."""
    try:
        with open(path, 'rb') as f:
            raw = f.read()
    except OSError as e:
        raise SourceError('%s nicht lesbar: %s' % (rel(path), e))
    if raw.startswith(BOM):
        raw = raw[len(BOM):]
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as e:
        raise SourceError('%s ist kein gueltiges UTF-8 (Byte %d)'
                          % (rel(path), e.start))
    return text.replace('\r\n', '\n').replace('\r', '\n')


# ---------------------------------------------------------------------------
# Pascal: Kommentare, Literale, Klammern, String-Ausdruecke, Routinen
# ---------------------------------------------------------------------------

def skip_string(text, i):
    """text[i] == "'": Index hinter dem Literal ('' ist ein Apostroph; ein
    Literal endet spaetestens am Zeilenende)."""
    n = len(text)
    j = i + 1
    while j < n and text[j] != '\n':
        if text[j] == "'":
            if j + 1 < n and text[j + 1] == "'":
                j += 2
                continue
            return j + 1
        j += 1
    return j


def _blank(s):
    return ''.join(c if c == '\n' else ' ' for c in s)


def strip_comments(text):
    """Kommentare ({ }, (* *), //, auch Direktiven) durch Leerzeichen
    ersetzen; Literale und Zeilenumbrueche bleiben, Positionen auch."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":
            j = skip_string(text, i)
        elif text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
        elif c == '{':
            j = text.find('}', i + 1)
            j = n if j < 0 else j + 1
        elif text.startswith('(*', i):
            j = text.find('*)', i + 2)
            j = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
            continue
        out.append(text[i:j] if c == "'" else _blank(text[i:j]))
        i = j
    return ''.join(out)


def scan_to_close(text, i, where):
    """text[i] ist '(' oder '[': Index der passenden schliessenden Klammer
    (Literale uebersprungen, Kommentare schon entfernt)."""
    want = []
    j, n = i, len(text)
    while j < n:
        c = text[j]
        if c == "'":
            j = skip_string(text, j)
            continue
        if c == '(':
            want.append(')')
        elif c == '[':
            want.append(']')
        elif c in ')]':
            if not want or want.pop() != c:
                break
            if not want:
                return j
        j += 1
    raise SourceError('%s: Klammern passen nicht zusammen' % where)


def split_top(text, sep):
    """text an sep teilen - nur ausserhalb von Literalen und Klammern."""
    parts, depth, start = [], 0, 0
    j, n = 0, len(text)
    while j < n:
        c = text[j]
        if c == "'":
            j = skip_string(text, j)
            continue
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif c == sep and depth == 0:
            parts.append(text[start:j])
            start = j + 1
        j += 1
    parts.append(text[start:])
    return parts


LIT_RE = re.compile(r"\s*(?:'((?:[^'\n]|'')*)'|#(\$[0-9A-Fa-f]+|[0-9]+))")
IDENT_RE = re.compile(r'[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*')


def literal_value(part):
    """Ein Operand nur aus Literalen und #-Zeichen ('a'#13'b') -> Text;
    None, wenn er etwas anderes enthaelt."""
    pos, out = 0, []
    while True:
        m = LIT_RE.match(part, pos)
        if not m or m.end() == pos:
            break
        if m.group(1) is not None:
            out.append(m.group(1).replace("''", "'"))
        else:
            code = m.group(2)
            out.append(chr(int(code[1:], 16) if code[0] == '$' else int(code)))
        pos = m.end()
    if not out or part[pos:].strip():
        return None
    return ''.join(out)


def eval_str(expr, resolve, loose=False):
    """Pascal-String-Ausdruck aus Literalen, #-Zeichen, Konstanten und '+'.
    loose: ein anderer Operand (Item.Short, ein Aufruf) wird '%s' - so
    erscheint ein Menuetext ohne _() mit seinem festen Teil."""
    out = []
    for part in split_top(expr, '+'):
        p = part.strip()
        if not p:
            raise SourceError('leerer Operand in %r' % expr.strip())
        lit = literal_value(p)
        if lit is not None:
            out.append(lit)
            continue
        if IDENT_RE.fullmatch(p):
            val = resolve(p)
            if val is not None:
                out.append(val)
                continue
        if loose:
            out.append('%s')
            continue
        raise SourceError('kein String aus Literalen und Konstanten: %r' % p)
    return ''.join(out)


def stmt_end(text, i):
    """Index des naechsten ';' ausserhalb von Literalen und Klammern."""
    depth, j, n = 0, i, len(text)
    while j < n:
        c = text[j]
        if c == "'":
            j = skip_string(text, j)
            continue
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif c == ';' and depth == 0:
            return j
        j += 1
    return n


def make_resolver(stripped):
    """Untypisierte String-Konstanten der Unit ('NAME = <Ausdruck>;') -> Wert
    (None, wenn es keine solche Konstante gibt)."""
    cache = {}

    def resolve(name):
        if name in cache:
            return cache[name]
        cache[name] = None                  # Schutz gegen Selbstbezug
        m = re.search(r'(?m)^[ \t]*' + re.escape(name) + r'[ \t]*=[ \t]*',
                      stripped)
        if not m:
            return None
        try:
            val = eval_str(stripped[m.end():stmt_end(stripped, m.end())],
                           resolve)
        except SourceError:
            val = None
        cache[name] = val
        return val
    return resolve


HEADER_RE = re.compile(
    r'(?m)^(?:class[ \t]+)?(?:function|procedure|constructor|destructor)'
    r'[ \t]+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)')
BODY_END_RE = re.compile(r'(?m)^end;')
UNIT_END_RE = re.compile(r'(?m)^(?:initialization|finalization|end\.)')


def routines(stripped, path):
    """Name -> Texte (Kopf bis zum 'end;' in Spalte 1) der Routinen des
    implementation-Teils; ein qualifizierter Name (TRdxFixRunner.X) steht
    auch unter dem Kurznamen. Die Units schreiben Kopf, 'begin' und 'end;'
    einer Routine in Spalte 1, lokale Routinen eingerueckt."""
    m = re.search(r'(?m)^implementation\b', stripped)
    if not m:
        raise SourceError('%s: kein implementation-Teil' % rel(path))
    stop_m = UNIT_END_RE.search(stripped, m.end())
    stop = stop_m.start() if stop_m else len(stripped)
    heads = [h for h in HEADER_RE.finditer(stripped, m.end())
             if h.start() < stop]
    res = {}
    for k, h in enumerate(heads):
        nxt = heads[k + 1].start() if k + 1 < len(heads) else stop
        e = BODY_END_RE.search(stripped, h.end(), nxt)
        body = stripped[h.start():e.end() if e else nxt]
        name = h.group(1)
        res.setdefault(name, []).append(body)
        short = name.rsplit('.', 1)[-1]
        if short != name:
            res.setdefault(short, []).append(body)
    return res


CB_RE = re.compile(r'\bChangesBehavior\s*:=\s*([^;]+);')
CALLEE_RE = re.compile(
    r'\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*(?:<[^<>()]*>\s*)?\(')


def changes_value(body):
    """Kennzeichnung, die ein Rumpf selbst setzt: 'ja' (nur ':= True'),
    'je nach Fund' (ein anderer Ausdruck) oder None (keine Zuweisung)."""
    vals = [v.strip() for v in CB_RE.findall(body)]
    if not vals:
        return None
    return 'ja' if all(v == 'True' for v in vals) else 'je nach Fund'


def changes_of(name, index, depth=0, seen=None):
    """Kennzeichnung der Routine name oder einer Routine, die sie ruft
    (hoechstens CALL_DEPTH Ebenen; Routinen der Tabelle und des Laeufers)."""
    seen = set() if seen is None else seen
    if name in seen or name not in index:
        return None
    seen.add(name)
    for body in index[name]:
        val = changes_value(body)
        if val:
            return val
    if depth >= CALL_DEPTH:
        return None
    for body in index[name]:
        for callee in CALLEE_RE.findall(body):
            for cand in (callee, callee.rsplit('.', 1)[-1]):
                if cand in index:
                    val = changes_of(cand, index, depth + 1, seen)
                    if val:
                        return val
                    break
    return None


# ---------------------------------------------------------------------------
# Quellen lesen
# ---------------------------------------------------------------------------

def parse_array(stripped, name):
    """'NAME: array[0..HIGH] of T = ( .. );' -> (HIGH, T, Elemente)."""
    m = re.search(r'\b%s\s*:\s*array\s*\[\s*0\s*\.\.\s*(\w+)\s*\]\s*of\s+'
                  r'(\w+)\s*=\s*\(' % re.escape(name), stripped)
    if not m:
        raise SourceError('%s: %s nicht gefunden (erwartet "%s: array[0..N] '
                          'of T = (...)")' % (rel(SRC_TABLE), name, name))
    close = scan_to_close(stripped, m.end() - 1, name)
    items = [s.strip() for s in split_top(stripped[m.end():close], ',')]
    return m.group(1), m.group(2), [] if items == [''] else items


def array_size(stripped, high):
    if high.isdigit():
        return int(high) + 1
    m = re.search(r'(?m)^[ \t]*%s[ \t]*=[ \t]*(\d+)[ \t]*;' % re.escape(high),
                  stripped)
    if not m:
        raise SourceError('%s: Konstante %s nicht gefunden'
                          % (rel(SRC_TABLE), high))
    return int(m.group(1)) + 1


def parse_row(item, i):
    where = 'FIX_ROWS[%d]' % i
    if not (item.startswith('(') and item.endswith(')')):
        raise SourceError('%s: kein Record "( .. )": %r' % (where, item[:60]))
    fields = {}
    for part in split_top(item[1:-1], ';'):
        part = part.strip()
        if not part:
            continue
        key, sep, val = part.partition(':')
        if not sep:
            raise SourceError('%s: Feld ohne ":": %r' % (where, part))
        fields[key.strip()] = val.strip()
    missing = [k for k in ('Kind', 'Plan', 'HintByPlanner', 'Changes')
               if k not in fields]
    if missing:
        raise SourceError('%s: Feld(er) %s fehlen' % (where, ', '.join(missing)))
    alt = fields.get('Alt', 'nil')
    if (not re.fullmatch(r'fk\w+', fields['Kind'])
            or not re.fullmatch(r'[A-Za-z_]\w*', fields['Plan'])
            or not re.fullmatch(r'[A-Za-z_]\w*', alt)
            or fields['Changes'] not in ('True', 'False')
            or fields['HintByPlanner'] not in ('True', 'False')):
        raise SourceError('%s: unbekannte Form: %r' % (where, item[:120]))
    return {'index': i, 'kind': fields['Kind'][2:], 'plan': fields['Plan'],
            'changes': fields['Changes'] == 'True',
            'hint_by_planner': fields['HintByPlanner'] == 'True',
            'alt': None if alt.lower() == 'nil' else alt}


def unmarked_units(read=None):
    """Units in reDelphix/source, die die Kennzeichnung setzen ('Changes-
    Behavior :=' im Code), deren Ruempfe der Generator aber nicht liest -
    er liest Tabelle, Laeufer und den Kern des Anbieters (Rezepte). read:
    die gelesenen
    Pfade (nur der Selbsttest gibt sie vor)."""
    if read is None:
        read = (SRC_TABLE, SRC_RUNNER, SRC_CORE)
    read = {os.path.normcase(os.path.abspath(p)) for p in read}
    out = []
    for path in sorted(glob.glob(os.path.join(SRC_DIR, '*.pas'))):
        if os.path.normcase(os.path.abspath(path)) in read:
            continue
        if os.path.basename(path) in NOT_DOCUMENTED:
            continue
        if CB_RE.search(strip_comments(load_text(path))):
            out.append(rel(path))
    return out


def parse_table(table_text=None, runner_text=None):
    """uRdxFixTable: Zeilen, Menuetexte, Kennzeichnung je Eintrag (die Texte
    der beiden Units gibt nur der Selbsttest vor)."""
    if table_text is None:
        table_text = load_text(SRC_TABLE)
    if runner_text is None:
        runner_text = load_text(SRC_RUNNER)
    st = strip_comments(table_text)
    resolve = make_resolver(st)
    arrays = {}
    for name in ('FIX_ROWS', 'FIX_CAPTIONS', 'FIX_ALT_CAPTIONS', 'FIX_HINTS'):
        high, typ, items = parse_array(st, name)
        arrays[name] = (array_size(st, high), typ, items)
    if arrays['FIX_ROWS'][1] != 'TRdxFixRow':
        raise SourceError('FIX_ROWS ist kein array of TRdxFixRow')
    rows = [parse_row(it, i) for i, it in enumerate(arrays['FIX_ROWS'][2])]
    captions = [eval_str(it, resolve) for it in arrays['FIX_CAPTIONS'][2]]
    alt_captions = [eval_str(it, resolve)
                    for it in arrays['FIX_ALT_CAPTIONS'][2]]
    hints = [eval_str(it, resolve) for it in arrays['FIX_HINTS'][2]]
    cap_changes = resolve('CAP_CHANGES')
    if not cap_changes:
        raise SourceError('%s: CAP_CHANGES nicht gefunden' % rel(SRC_TABLE))
    index = routines(st, SRC_TABLE)
    runner = routines(strip_comments(runner_text), SRC_RUNNER)
    for name, bodies in runner.items():
        index.setdefault(name, []).extend(bodies)
    for r in rows:
        for planner in (r['plan'], r['alt']):
            if planner and planner not in index:
                raise SourceError(
                    'FIX_ROWS[%d]: Planer %s ohne Rumpf in %s und %s - die '
                    'Adapter gehoeren in die Tabelle'
                    % (r['index'], planner, rel(SRC_TABLE), rel(SRC_RUNNER)))
        # Wie TRdxFixTable.FixFor: die Zeile ODER der Planer kennzeichnet;
        # den zweiten Eintrag kennzeichnet nur sein Planer.
        r['changes_main'] = ('ja' if r['changes']
                             else changes_of(r['plan'], index) or 'nein')
        r['changes_alt'] = (changes_of(r['alt'], index) or 'nein'
                            if r['alt'] else None)
    outside = unmarked_units()
    if outside:
        raise SourceError(
            "'ChangesBehavior :=' in %s - der Generator liest dort nicht, "
            "QUICKFIXES.md nennte die Hilfe still 'Aendert Verhalten: nein'. "
            "Den Adapter in die Tabelle (uRdxFixTable) legen oder die Unit "
            "hier aufnehmen"
            % ', '.join(outside))
    return {'rows': rows, 'captions': captions, 'alt_captions': alt_captions,
            'hints': hints,
            'sizes': {k: (v[0], len(v[2])) for k, v in arrays.items()},
            'cap_changes': cap_changes}


CALL_RE = re.compile(r'\b(AddRefactor|AddReplace|Add)\s*\(')
REG_RE = re.compile(r'\bF(\w*)Recipes\s*\[\s*\d+\s*\]\s*:=\s*([A-Za-z_]\w*)\s*;')


def caption_of(expr, resolve, where):
    """Menuetext-Argument -> msgid und ob es ueber _() uebersetzt wird."""
    calls = list(re.finditer(r'(?<![\w.])_\s*\(', expr))
    if len(calls) > 1:
        raise SourceError('%s: Menuetext aus mehreren _()-Teilen: %r - '
                          'Generator erweitern' % (where, expr))
    if calls:
        open_i = expr.index('(', calls[0].start())
        close_i = scan_to_close(expr, open_i, where)
        return {'msgid': eval_str(expr[open_i + 1:close_i], resolve),
                'translatable': True}
    return {'msgid': eval_str(expr, resolve, loose=True), 'translatable': False}


def analyze_recipe(meth, group, body, resolve):
    """Ein Rezept des Anbieters: Menuetexte, Art, Regel-Bindung,
    Kennzeichnung - alles aus seinem Rumpf."""
    caps, kinds = [], set()
    for m in CALL_RE.finditer(body):
        fn = m.group(1)
        close = scan_to_close(body, m.end() - 1, meth)
        args = [a.strip() for a in split_top(body[m.end():close], ',')]
        if len(args) < 2:
            raise SourceError('%s: %s(..) mit weniger als zwei Argumenten'
                              % (meth, fn))
        if fn == 'Add':          # Add(AList, Caption, Hint, Enabled, Action)
            active = len(args) >= 5 and args[3] != 'False' and args[4] != 'nil'
        elif fn == 'AddRefactor':  # AddRefactor(AList, Caption, Hint, Action)
            kinds.add('fakRefactor')
            active = len(args) >= 4 and args[3] != 'nil'
        else:                    # AddReplace(AList, Caption, File, Edit, Kind)
            active = True
            if len(args) >= 5 and re.fullmatch(r'fak\w+', args[4]):
                kinds.add(args[4])
        cap = caption_of(args[1], resolve, meth)
        for c in caps:
            if (c['msgid'], c['translatable']) == (cap['msgid'],
                                                   cap['translatable']):
                c['active'] = c['active'] or active
                break
        else:
            cap['active'] = active
            caps.append(cap)
    kinds.update(re.findall(r'\.\s*Kind\s*:=\s*(fak\w+)', body))
    if not kinds:
        kinds = {'fakFix'}       # TRdxActionCore.Add setzt fakFix
    if len(kinds) > 1:
        raise SourceError('%s erzeugt Aktionen mehrerer Arten (%s) - '
                          'Generator erweitern' % (meth, ', '.join(sorted(kinds))))
    modes = []
    for tok in re.findall(r"\bFixMode\s*<>\s*('(?:[^'\n]|'')*'|[A-Za-z_]\w*)",
                          body):
        val = literal_value(tok) if tok.startswith("'") else resolve(tok)
        if val is None:
            raise SourceError('%s: fixMode-Vergleich mit unbekanntem Wert %s'
                              % (meth, tok))
        modes.append(val.lower())
    return {
        'method': meth,
        'group': group,
        'key': 'recipe:' + (meth[3:] if meth.startswith('Add') else meth),
        'captions': caps,
        'art': kinds.pop(),
        'modes': sorted(set(modes)),
        'inc_kinds': sorted(set(re.findall(r'\bKind\s*<>\s*fk(\w+)', body))),
        'exc_kinds': sorted(set(re.findall(r'\bKind\s*=\s*fk(\w+)', body))),
        'changes': changes_value(body) or 'nein',
        'table_bridge': 'TRdxFixTable.' in body,
    }


def parse_provider(provider_text=None):
    """uRdxActionCore (Kern des Anbieters): die Rezepte in der Reihenfolge
    des Konstruktors (=
    Reihenfolge im Menue); das Rezept, das die Tabelle ruft, ist die
    Bruecke zu FIX_ROWS, kein eigenes."""
    if provider_text is None:
        provider_text = load_text(SRC_CORE)
    st = strip_comments(provider_text)
    resolve = make_resolver(st)
    index = routines(st, SRC_CORE)
    ctor = index.get(CORE_CLASS + '.Create')
    if not ctor:
        raise SourceError('%s: constructor %s.Create nicht gefunden'
                          % (rel(SRC_CORE), CORE_CLASS))
    regs = REG_RE.findall(ctor[0])
    if not regs:
        raise SourceError('%s: keine Rezepte im Konstruktor (erwartet '
                          '"F..Recipes[i] := AddXxx;")' % rel(SRC_CORE))
    # Jede Liste so viele Zuweisungen wie Plaetze (SetLength) - sonst stuende
    # ein Rezept in einer Form da, die der Generator nicht liest, und fehlte
    # still in der Doku.
    slots = dict(re.findall(r'\bSetLength\s*\(\s*F(\w*)Recipes\s*,\s*(\d+)\s*\)',
                            ctor[0]))
    for group in sorted(set(slots) | {g for g, _m in regs}):
        found = sum(1 for g, _m in regs if g == group)
        if slots.get(group) != str(found) or re.search(
                r'\bF%sRecipes\s*:=' % group, ctor[0]):
            raise SourceError('%s: F%sRecipes hat %s Plaetze (SetLength) und '
                              '%d Zuweisungen "F%sRecipes[i] := AddXxx;" - '
                              'Form unbekannt, Generator erweitern'
                              % (rel(SRC_CORE), group,
                                 slots.get(group, 'keine'), found, group))
    recipes, bridge = [], None
    for group, meth in regs:
        bodies = index.get(CORE_CLASS + '.' + meth)
        if not bodies:
            raise SourceError('%s: Rezept %s ohne Rumpf'
                              % (rel(SRC_CORE), meth))
        info = analyze_recipe(meth, group, bodies[0], resolve)
        if info['table_bridge']:
            if bridge:
                raise SourceError('zwei Rezepte rufen TRdxFixTable: %s, %s'
                                  % (bridge['method'], meth))
            bridge = info
        else:
            recipes.append(info)
    if not bridge:
        raise SourceError('kein Rezept ruft TRdxFixTable - die Tabelle haengt '
                          'nicht am Anbieter')
    return {'recipes': recipes, 'bridge': bridge}


def parse_po(path):
    """msgid -> msgstr wie uLocalization.ParsePo: Kommentar und Leerzeile
    beenden einen Eintrag, msgctxt und Pluralformen fallen weg, leeres
    msgstr heisst keine Uebersetzung, der erste Treffer gewinnt."""
    entries = {}
    state = {'sec': None, 'id': '', 'str': '', 'skip': False}

    def flush():
        if (not state['skip'] and state['id'] and state['str']
                and state['id'] not in entries):
            entries[state['id']] = state['str']
        state.update(sec=None, id='', str='')

    def end_entry():
        flush()
        state['skip'] = False

    for nr, line in enumerate(load_text(path).split('\n'), 1):
        s = line.strip()
        if not s or s.startswith('#'):
            end_entry()
        elif s.startswith('"'):
            if state['sec'] is None:
                raise SourceError('%s:%d: Fortsetzung ohne msgid/msgstr'
                                  % (rel(path), nr))
            lit = po_literal(s, path, nr)
            if state['sec'] in ('id', 'str'):
                state[state['sec']] += lit
        elif s.startswith('msgctxt'):
            if state['sec'] is not None:
                end_entry()
            state.update(skip=True, sec='ctx')
        elif s.startswith('msgid_plural'):
            state.update(skip=True, sec='id')
        elif s.startswith('msgstr['):
            state.update(skip=True, sec='str')
        elif s.startswith('msgid'):
            if state['sec'] in ('id', 'str'):
                end_entry()
            state.update(id=po_literal(s, path, nr), sec='id')
        elif s.startswith('msgstr'):
            state.update(str=po_literal(s, path, nr), sec='str')
        else:
            end_entry()
    end_entry()
    return entries


PO_ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', '\\': '\\',
              'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v', '0': '\0'}


def po_literal(line, path, nr):
    start = line.find('"')
    out, i = [], start + 1
    while 0 < i < len(line):
        c = line[i]
        if c == '"':
            return ''.join(out)
        if c == '\\' and i + 1 < len(line):
            i += 1
            out.append(PO_ESCAPES.get(line[i], line[i]))
        else:
            out.append(c)
        i += 1
    raise SourceError('%s:%d: Literal ohne schliessendes "' % (rel(path), nr))


def load_catalog():
    try:
        data = json.loads(load_text(CATALOG))
    except ValueError as e:
        raise SourceError('%s: kein JSON: %s' % (rel(CATALOG), e))
    return {r['kind']: r for r in data.get('rules', []) if 'kind' in r}


def load_data():
    try:
        data = json.loads(load_text(DATA))
    except ValueError as e:
        raise SourceError('%s: kein JSON: %s' % (rel(DATA), e))
    if not isinstance(data, dict) or not isinstance(data.get('eintraege'), dict):
        raise SourceError('%s: erwartet {"eintraege": {..}}' % rel(DATA))
    return data


def load_profile():
    """Die Arten des Profils code-aktionen (Liste, Reihenfolge der Datei)."""
    try:
        data = json.loads(load_text(PROFILE))
    except ValueError as e:
        raise SourceError('%s: kein JSON: %s' % (rel(PROFILE), e))
    kinds = (data.get('profiles') or {}).get(PROFILE_NAME) \
        if isinstance(data, dict) else None
    if not isinstance(kinds, list) or not all(isinstance(k, str) for k in kinds):
        raise SourceError('%s: erwartet {"profiles": {"%s": ["Art", ..]}}'
                          % (rel(PROFILE), PROFILE_NAME))
    return kinds


def load_inputs():
    return {
        'table': parse_table(),
        'provider': parse_provider(),
        'catalog': load_catalog(),
        'po': {lang: parse_po(path) for lang, path in PO_FILES},
        'data': load_data(),
        'profile': load_profile(),
    }


# ---------------------------------------------------------------------------
# Modell und Konsistenz
# ---------------------------------------------------------------------------

PLACEHOLDER_RE = re.compile(r'%(?:\d+:)?-?\d*(?:\.\d+)?[dusefgnmpx]', re.I)
FIELDS = {'titel', 'was', 'nichtAngeboten', 'beispielVorher',
          'beispielNachher', 'nachherTitel', 'weitereBeispiele', 'hinweis',
          'platzhalter', 'kennzeichnung', 'zweiterEintrag', 'regelText',
          'ohneBeispiel'}
FIELDS_SECOND = {'was', 'beispielVorher', 'beispielNachher', 'nachherTitel',
                 'nichtAngeboten', 'kennzeichnung'}
FIELDS_EXAMPLE = {'titel', 'vorher', 'nachher', 'nachherTitel'}


def rule_number(rule):
    m = re.search(r'\d+', rule.get('id', ''))
    return int(m.group()) if m else 99999


def as_lines(value):
    """Beispielcode: Liste von Zeilen oder ein String mit Zeilenumbruechen."""
    if isinstance(value, str):
        return value.split('\n')
    if isinstance(value, list) and all(isinstance(v, str) for v in value):
        return list(value)
    return None


def _text(doc, key, where, errors, required=True):
    val = doc.get(key)
    if val is None:
        if required:
            errors.append('%s: Feld "%s" fehlt' % (where, key))
        return
    if not isinstance(val, str) or not val.strip():
        errors.append('%s: "%s" ist kein Text' % (where, key))


def _list(doc, key, where, errors, required=True):
    val = doc.get(key)
    if val is None:
        if required:
            errors.append('%s: Feld "%s" fehlt' % (where, key))
        return
    if (not isinstance(val, list) or not val
            or not all(isinstance(v, str) and v.strip() for v in val)):
        errors.append('%s: "%s" ist keine Liste von Texten' % (where, key))


def _code(doc, key, where, errors, required=True):
    val = doc.get(key)
    if val is None:
        if required:
            errors.append('%s: Feld "%s" fehlt' % (where, key))
        return
    if not as_lines(val):
        errors.append('%s: "%s" ist kein Code (Liste von Zeilen)' % (where, key))


def check_marking(state, doc, where, errors):
    """Feld "kennzeichnung" gegen die Kennzeichnung aus dem Quelltext."""
    if state == 'je nach Fund' and 'kennzeichnung' not in doc:
        errors.append('%s: der Planer kennzeichnet je nach Fund - Feld '
                      '"kennzeichnung" fehlt (wann?)' % where)
    if state == 'nein' and 'kennzeichnung' in doc:
        errors.append('%s: "kennzeichnung", aber der Quelltext kennzeichnet '
                      'die Hilfe nie' % where)


def check_doc(entry, errors):
    """Pflicht- und Kann-Felder eines JSON-Eintrags gegen das, was der
    Quelltext ueber die Hilfe sagt."""
    key, doc = entry['key'], entry['doc']
    where = 'quickfixes-doc.json "%s"' % key
    unknown = sorted(k for k in doc if k not in FIELDS and not k.startswith('$'))
    if unknown:
        errors.append('%s: unbekannte Felder %s' % (where, ', '.join(unknown)))
    _text(doc, 'titel', where, errors)
    _text(doc, 'was', where, errors)
    _list(doc, 'nichtAngeboten', where, errors)
    for k in ('nachherTitel', 'hinweis', 'platzhalter', 'kennzeichnung',
              'regelText', 'ohneBeispiel'):
        _text(doc, k, where, errors, required=False)
    if 'ohneBeispiel' in doc:
        if 'beispielVorher' in doc or 'beispielNachher' in doc:
            errors.append('%s: "ohneBeispiel" und ein Beispiel zugleich' % where)
    else:
        _code(doc, 'beispielVorher', where, errors)
        _code(doc, 'beispielNachher', where, errors)
    more = doc.get('weitereBeispiele')
    if more is not None:
        if not isinstance(more, list) or not more:
            errors.append('%s: "weitereBeispiele" ist keine Liste' % where)
            more = []
        for n, ex in enumerate(more, 1):
            w = '%s, weiteres Beispiel %d' % (where, n)
            if not isinstance(ex, dict):
                errors.append('%s: kein Objekt' % w)
                continue
            bad = sorted(k for k in ex if k not in FIELDS_EXAMPLE)
            if bad:
                errors.append('%s: unbekannte Felder %s' % (w, ', '.join(bad)))
            _text(ex, 'titel', w, errors)
            _code(ex, 'vorher', w, errors)
            _code(ex, 'nachher', w, errors)
            _text(ex, 'nachherTitel', w, errors, required=False)
    # Platzhalter: erklaert genau dann, wenn ein Menuetext einen traegt.
    has_ph = any(PLACEHOLDER_RE.search(c['msgid']) for c in entry['captions'])
    if has_ph and 'platzhalter' not in doc:
        errors.append('%s: Menuetext mit Platzhalter (%s) - Feld "platzhalter" '
                      'fehlt' % (where, ' / '.join(c['msgid'] for c in
                                                   entry['captions'])))
    if not has_ph and 'platzhalter' in doc:
        errors.append('%s: "platzhalter", aber kein Menuetext traegt einen'
                      % where)
    # Kennzeichnung: "je nach Fund" muss sagen, wann; "ja" darf sagen,
    # warum; eine nie gekennzeichnete Hilfe hat nichts zu erklaeren.
    main = entry['captions'][0]['changes'] if entry['captions'] else 'nein'
    check_marking(main, doc, where, errors)
    # Zweiter Eintrag: beschrieben genau dann, wenn es ihn gibt.
    second = doc.get('zweiterEintrag')
    if entry.get('alt') and second is None:
        errors.append('%s: FIX_ROWS hat einen zweiten Eintrag (%s) - Feld '
                      '"zweiterEintrag" fehlt' % (where, entry['alt']))
    if not entry.get('alt') and second is not None:
        errors.append('%s: "zweiterEintrag", aber die Hilfe hat keinen' % where)
    if entry.get('alt') and isinstance(second, dict):
        w = where + ', zweiterEintrag'
        bad = sorted(k for k in second if k not in FIELDS_SECOND)
        if bad:
            errors.append('%s: unbekannte Felder %s' % (w, ', '.join(bad)))
        _text(second, 'was', w, errors)
        _code(second, 'beispielVorher', w, errors, required=False)
        _code(second, 'beispielNachher', w, errors)
        _list(second, 'nichtAngeboten', w, errors, required=False)
        _text(second, 'nachherTitel', w, errors, required=False)
        check_marking(entry['captions'][1]['changes'], second, w, errors)
    elif entry.get('alt') and second is not None:
        errors.append('%s: "zweiterEintrag" ist kein Objekt' % where)
    # Regel eines Rezepts: abgeleitet oder beschrieben.
    if entry['is_recipe']:
        if not entry['rules'] and not entry['exc_rules'] and 'regelText' not in doc:
            errors.append('%s: das Rezept bindet keine Regel im Quelltext - '
                          'Feld "regelText" fehlt' % where)
    elif 'regelText' in doc:
        errors.append('%s: "regelText" nur fuer Rezepte' % where)


def build(inputs):
    """Eingaben -> {'entries', 'errors', 'notes'}; aendert inputs nicht."""
    table, provider = inputs['table'], inputs['provider']
    catalog, po, data = inputs['catalog'], inputs['po'], inputs['data']
    docs = data['eintraege']
    errors, notes = [], []
    rows, caps, alts = table['rows'], table['captions'], table['alt_captions']
    hints = table['hints']

    # Die vier parallelen Arrays (Index fuer Index).
    lengths = {'FIX_ROWS': len(rows), 'FIX_CAPTIONS': len(caps),
               'FIX_ALT_CAPTIONS': len(alts), 'FIX_HINTS': len(hints)}
    for name, (declared, _found) in sorted(table['sizes'].items()):
        if lengths[name] != declared:
            errors.append('%s: %d Elemente, deklariert sind %d'
                          % (name, lengths[name], declared))
    if len(set(lengths.values())) > 1:
        errors.append('FIX_ROWS, FIX_CAPTIONS, FIX_ALT_CAPTIONS und FIX_HINTS '
                      'sind nicht gleich lang (%s) - die Arrays sind parallel'
                      % ', '.join('%s %d' % kv for kv in sorted(lengths.items())))

    entries, seen = [], {}
    for r in rows:
        i, kind = r['index'], r['kind']
        if kind in seen:
            errors.append('FIX_ROWS: Art %s steht zweimal (Index %d und %d)'
                          % (kind, seen[kind], i))
            continue
        seen[kind] = i
        rule = catalog.get(kind)
        if rule is None:
            errors.append('FIX_ROWS[%d]: Art %s fehlt im Katalog %s'
                          % (i, kind, rel(CATALOG)))
            continue
        if rule.get('editorHelp') is not True:
            errors.append('FIX_ROWS[%d]: %s %s hat eine Hilfe, im Katalog fehlt '
                          '"editorHelp": true' % (i, rule['id'], kind))
        cap = caps[i] if i < len(caps) else ''
        alt_cap = alts[i] if i < len(alts) else ''
        if not cap:
            errors.append('FIX_ROWS[%d] (%s): kein Menuetext in FIX_CAPTIONS'
                          % (i, kind))
        if bool(r['alt']) != bool(alt_cap):
            errors.append('FIX_ROWS[%d] (%s): zweiter Eintrag %s, Menuetext in '
                          'FIX_ALT_CAPTIONS %s - genau zusammen'
                          % (i, kind, r['alt'] or 'nil', repr(alt_cap)))
        # Wie TRdxFixTable.FixFor: den Hinweis setzt der Planer ODER die
        # Zeile (FIX_HINTS, seit Charge G7 statt des Felds Hint).
        hint = hints[i] if i < len(hints) else ''
        if bool(hint) == r['hint_by_planner']:
            errors.append('FIX_ROWS[%d] (%s): HintByPlanner %s, Hinweis in '
                          'FIX_HINTS %s - genau eines von beiden'
                          % (i, kind, r['hint_by_planner'], repr(hint)))
        captions = [{'msgid': cap, 'translatable': True, 'active': True,
                     'changes': r['changes_main']}]
        if r['alt'] and alt_cap:
            captions.append({'msgid': alt_cap, 'translatable': True,
                             'active': True, 'changes': r['changes_alt']})
        entries.append({
            'key': kind, 'is_recipe': False, 'rules': [rule], 'exc_rules': [],
            'modes': [], 'captions': captions, 'art': provider['bridge']['art'],
            'alt': r['alt'] if alt_cap else None,
            'sort': (0, rule_number(rule), kind)})

    recipe_kinds = set()
    for n, rc in enumerate(provider['recipes']):
        rules, unknown = [], []
        for mode in rc['modes']:
            rules.extend(r for r in catalog.values()
                         if str(r.get('fixMode', '')).lower() == mode)
        for kind in rc['inc_kinds']:
            if kind in catalog:
                rules.append(catalog[kind])
            else:
                unknown.append(kind)
        exc = []
        for kind in rc['exc_kinds']:
            if kind in catalog:
                exc.append(catalog[kind])
            else:
                unknown.append(kind)
        for kind in unknown:
            errors.append('%s: Art %s fehlt im Katalog' % (rc['key'], kind))
        rules = sorted({r['id']: r for r in rules}.values(), key=rule_number)
        recipe_kinds.update(r['kind'] for r in rules)
        if rc['modes'] and not any(r for r in rules if r.get('fixMode')):
            errors.append('%s: keine Regel im Katalog mit fixMode %s'
                          % (rc['key'], ', '.join(rc['modes'])))
        captions = [dict(c, changes=rc['changes']) for c in rc['captions']
                    if c['active']]
        captions += [dict(c, changes=rc['changes']) for c in rc['captions']
                     if not c['active']]
        if not captions:
            errors.append('%s: kein Menuetext im Rumpf von %s'
                          % (rc['key'], rc['method']))
        entries.append({
            'key': rc['key'], 'is_recipe': True, 'rules': rules,
            'exc_rules': sorted(exc, key=rule_number), 'modes': rc['modes'],
            'captions': captions, 'art': rc['art'], 'alt': None,
            'sort': (1, n, rc['key'])})
        # Gegenrichtung wie bei FIX_ROWS: ein Quick-Fix-Rezept, das eine
        # Regel bindet, ist eine Code-Aktion zu ihren Funden - die Regel
        # traegt editorHelp (Q17: SCA003 hatte die SQL-Vorlage, aber kein
        # Flag, also weder QF-Badge noch Quick-Wins im HTML).
        if rc['art'] == 'fakFix':
            for r in rules:
                if r.get('editorHelp') is not True:
                    errors.append('%s: %s %s hat eine Hilfe, im Katalog fehlt '
                                  '"editorHelp": true'
                                  % (rc['key'], r.get('id', '?'), r['kind']))

    keys = {e['key'] for e in entries}
    if len(keys) != len(entries):
        errors.append('zwei Hilfen mit demselben Schluessel')
    for e in entries:
        if e['art'] not in ART_NAMES:
            errors.append('%s: Art %s unbekannt - Generator erweitern'
                          % (e['key'], e['art']))
        doc = docs.get(e['key'])
        if doc is None:
            errors.append('%s %s: kein Eintrag in %s - Titel, Beschreibung, '
                          'Sperren und Beispiel ergaenzen'
                          % ('Rezept' if e['is_recipe'] else 'Art', e['key'],
                             rel(DATA)))
            continue
        if not isinstance(doc, dict):
            errors.append('quickfixes-doc.json "%s": kein Objekt' % e['key'])
            continue
        e['doc'] = doc
        check_doc(e, errors)
    for key in docs:
        if key not in keys and not key.startswith('$'):
            errors.append('quickfixes-doc.json "%s": keine solche Art in '
                          'FIX_ROWS und kein solches Rezept im Anbieter' % key)
    for kind, rule in sorted(catalog.items(), key=lambda kv: rule_number(kv[1])):
        if rule.get('editorHelp') is True and kind not in seen \
                and kind not in recipe_kinds:
            errors.append('%s %s: "editorHelp": true im Katalog, aber keine '
                          'Zeile in FIX_ROWS und kein Rezept, das sie bindet'
                          % (rule.get('id', '?'), kind))
    # Profil code-aktionen: jede Art mit Hilfe darin, keine ohne Hilfe ausser
    # PROFILE_EXTRA, keine doppelt.
    profile = inputs['profile']
    helped = set(seen) | recipe_kinds
    for kind in sorted(helped - set(profile),
                       key=lambda k: rule_number(catalog.get(k, {}))):
        errors.append('%s %s: hat eine Hilfe, fehlt aber im Profil %s in %s'
                      % (catalog.get(kind, {}).get('id', '?'), kind,
                         PROFILE_NAME, rel(PROFILE)))
    for kind in sorted(set(profile) - helped - set(PROFILE_EXTRA)):
        errors.append('Profil %s: Art %s hat keine Hilfe - streichen oder mit '
                      'Grund in PROFILE_EXTRA aufnehmen' % (PROFILE_NAME, kind))
    for kind in sorted({k for k in profile if profile.count(k) > 1}):
        errors.append('Profil %s: Art %s steht mehrfach' % (PROFILE_NAME, kind))
    for kind in sorted(set(PROFILE_EXTRA) - set(profile)):
        errors.append('PROFILE_EXTRA: %s steht nicht (mehr) im Profil %s - '
                      'Eintrag streichen' % (kind, PROFILE_NAME))
    for e in entries:
        for c in e['captions']:
            if not c['translatable']:
                continue
            for lang, _path in PO_FILES:
                if c['msgid'] not in po[lang]:
                    notes.append('%s: %s fehlt in i18n/%s.po'
                                 % (e['key'], c['msgid'], lang))
    entries.sort(key=lambda e: e['sort'])
    return {'entries': [e for e in entries if 'doc' in e], 'errors': errors,
            'notes': notes, 'cap_changes': table['cap_changes'],
            'all_entries': entries}


# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------

def code_span(text):
    text = text.replace('|', '\\|')
    run = max((len(m) for m in re.findall(r'`+', text)), default=0)
    fence = '`' * (run + 1)
    pad = ' ' if run or text.startswith('`') or text.endswith('`') else ''
    return fence + pad + text + pad + fence


def code_block(lines):
    fence = '```'
    while any(fence in ln for ln in lines):
        fence += '`'
    return [fence + 'pascal'] + lines + [fence]


def translation(c, lang, po):
    """Menuetext einer Sprache als Tabellenzelle."""
    if lang == 'en' or not c['translatable']:
        cell = code_span(c['msgid'])
        if lang != 'en' and not c['translatable']:
            cell += ' *(fester Text)*'
        return cell
    text = po[lang].get(c['msgid'])
    return code_span(text) if text else '**%s**' % FEHLT


def anchor(entry):
    if entry['is_recipe']:
        return 'rezept-' + entry['key'].split(':', 1)[1].lower()
    return entry['rules'][0]['id'].lower()


def rule_short(rule):
    return '%s %s' % (rule['id'], rule['kind'])


def rule_long(rule):
    return '%s `%s` – %s' % (rule['id'], rule['kind'],
                             rule.get('name', '').replace('|', '\\|'))


def rules_overview(e):
    if e['rules']:
        return ', '.join(rule_short(r) for r in e['rules'])
    if e['exc_rules']:
        return 'alle außer ' + ', '.join(r['id'] for r in e['exc_rules'])
    return e['doc']['regelText']


def rules_section(e):
    if not e['is_recipe']:
        return rule_long(e['rules'][0])
    parts = []
    if e['rules']:
        txt = '; '.join(rule_long(r) for r in e['rules'])
        if e['modes']:
            txt += ' (Katalog: fixMode %s)' % ', '.join(
                '`%s`' % m for m in e['modes'])
        parts.append(txt)
    elif e['exc_rules']:
        parts.append('alle Regeln außer ' + ', '.join(
            '%s `%s`' % (r['id'], r['kind']) for r in e['exc_rules']))
    if 'regelText' in e['doc']:
        parts.append(e['doc']['regelText'])
    return ' – '.join(parts)


def changes_overview(e):
    """Kennzeichnung je Eintrag; die Eintraege eines Rezepts teilen sie."""
    if e['alt']:
        return ' / '.join(c['changes'] for c in e['captions'])
    return e['captions'][0]['changes'] if e['captions'] else '?'


def marking(state, explain):
    """'ja' / 'je nach Fund' / 'nein' als Satz; explain aus dem Feld
    "kennzeichnung" (warum bzw. wann)."""
    if state == 'ja':
        return '**ja** – %s%s.' % (explain + '. Nur ' if explain else 'nur ',
                                   UEBER_MENUE)
    if state == 'je nach Fund':
        return ('**je nach Fund** – gekennzeichnet %s. Dann nur %s.'
                % (explain, UEBER_MENUE))
    return 'nein'


def changes_lines(e):
    """Die Zeile(n) "Aendert Verhalten" des Steckbriefs."""
    doc = e['doc']
    if e['alt']:
        second = doc.get('zweiterEintrag') or {}
        return ['- **Ändert Verhalten:**',
                '  - Eintrag 1: ' + marking(e['captions'][0]['changes'],
                                            doc.get('kennzeichnung', '')),
                '  - Eintrag 2: ' + marking(e['captions'][1]['changes'],
                                            second.get('kennzeichnung', ''))]
    # Ein Eintrag bzw. die Eintraege eines Rezepts (alle gleich gekennzeichnet).
    return ['- **Ändert Verhalten:** ' + marking(e['captions'][0]['changes'],
                                                 doc.get('kennzeichnung', ''))]


def render_example(a, vorher, nachher, nachher_titel):
    """Vorher/Nachher als Pascal-Bloecke; vorher None: wie Eintrag 1."""
    if vorher is None:
        a('Vorher wie bei Eintrag 1.')
    else:
        a('Vorher:')
        a('')
        for ln in code_block(vorher):
            a(ln)
    a('')
    a((nachher_titel or 'Nachher') + ':')
    a('')
    for ln in code_block(nachher):
        a(ln)
    a('')


def render_entry(e, po, a):
    doc = e['doc']
    a('<a id="%s"></a>' % anchor(e))
    a('')
    if e['is_recipe']:
        a('### %s' % doc['titel'])
    else:
        a('### %s – %s' % (e['rules'][0]['id'], doc['titel']))
    a('')
    a('- **Regel:** ' + rules_section(e))
    a('- **Art:** ' + ART_NAMES.get(e['art'], e['art']))
    for ln in changes_lines(e):
        a(ln)
    a('')
    # Menuetexte: Spalten je Sprache; mehrere Eintraege je eine Zeile.
    multi = len(e['captions']) > 1
    a(('| Eintrag | ' if multi else '| ') + ' | '.join(LANGS) + ' |')
    a('|---' * (len(LANGS) + (1 if multi else 0)) + '|')
    for n, c in enumerate(e['captions'], 1):
        cells = [translation(c, lang, po) for lang in LANGS]
        if multi:
            cells.insert(0, str(n) + ('' if c['active']
                                      else ' (nur ausgegraut)'))
        a('| ' + ' | '.join(cells) + ' |')
    a('')
    if 'platzhalter' in doc:
        a('**Platzhalter:** ' + doc['platzhalter'])
        a('')
    second = doc.get('zweiterEintrag') if e['alt'] else None
    a('**Wirkung%s:** %s' % (' (Eintrag 1)' if second else '', doc['was']))
    a('')
    if second:
        a('**Wirkung (Eintrag 2):** ' + second['was'])
        a('')
    a('**Nicht angeboten**')
    a('')
    for s in doc['nichtAngeboten']:
        a('- ' + s)
    for s in (second or {}).get('nichtAngeboten', []):
        a('- Eintrag 2: ' + s)
    a('')
    if 'ohneBeispiel' in doc:
        a('**Beispiel:** ' + doc['ohneBeispiel'])
        a('')
    else:
        a('**Beispiel%s**' % (' (Eintrag 1)' if second else ''))
        a('')
        render_example(a, as_lines(doc['beispielVorher']),
                       as_lines(doc['beispielNachher']), doc.get('nachherTitel'))
    if second:
        a('**Beispiel (Eintrag 2)**')
        a('')
        vorher = second.get('beispielVorher')
        render_example(a, as_lines(vorher) if vorher is not None else None,
                       as_lines(second['beispielNachher']),
                       second.get('nachherTitel'))
    for ex in doc.get('weitereBeispiele', []):
        a('**Beispiel: %s**' % ex['titel'])
        a('')
        render_example(a, as_lines(ex['vorher']), as_lines(ex['nachher']),
                       ex.get('nachherTitel'))
    if 'hinweis' in doc:
        a('**Hinweis.** ' + doc['hinweis'])
        a('')


def render(model, po):
    """Das ganze Dokument als Text mit LF (encode_doc macht CRLF und BOM)."""
    entries = model['entries']
    rows = [e for e in entries if not e['is_recipe']]
    recipes = [e for e in entries if e['is_recipe']]
    suffix = {'en': model['cap_changes']}
    for lang, _p in PO_FILES:
        suffix[lang] = po[lang].get(model['cap_changes'])
    L = []
    a = L.append
    a('# Quick-Fixes von reDelphix')
    a('')
    a('> **Erzeugte Datei – nicht von Hand bearbeiten.** Quelle: '
      '[`data/quickfixes-doc.json`](data/quickfixes-doc.json) (Titel, '
      'Beschreibung, Sperren, Beispiele) und der Quelltext: welche Hilfen es '
      'gibt, ihre Menütexte und ob sie das Verhalten ändern, stehen in '
      '[`source/uRdxFixTable.pas`](source/uRdxFixTable.pas) (`FIX_ROWS`, '
      '`FIX_CAPTIONS`, `FIX_ALT_CAPTIONS`) und '
      '[`source/uRdxActionCore.pas`](source/uRdxActionCore.pas) (Rezepte), '
      'die '
      'Übersetzungen in [`i18n/de.po`](../i18n/de.po) und '
      '[`i18n/fr.po`](../i18n/fr.po), Regel-IDs und Namen in '
      '[`rules/sca-rules.json`](../rules/sca-rules.json).')
    a('> Erzeugen (Repo-Wurzel): `python tools/gen-quickfix-doc.py`, '
      'prüfen: `python tools/gen-quickfix-doc.py --check` (auch in der CI, '
      '`.github/workflows/quickfix-doc.yml`).')
    a('')
    a('reDelphix hängt an Funde des SCA-Plugins Code-Aktionen. Hier steht '
      'jede: %d Quick-Fixes aus der Tabelle der einfachen Hilfen (%d davon '
      'mit zweitem Eintrag) und %d weitere Code-Aktionen des Anbieters. Wie '
      'die Hilfen im Einzelnen prüfen und schreiben, beschreibt '
      '[README.md](README.md), Abschnitt „Was die Aktionen tun“.'
      % (len(rows), sum(1 for e in rows if e['alt']), len(recipes)))
    a('')
    a('## Lesehilfe')
    a('')
    a('- **Quick-Fix** behebt den Fund: Glühbirne im Editor (nur verfügbare '
      'Hilfen), Kontextmenü des Funds im Editor und im Dock-Grid (dort auch '
      'ausgegraut, der Grund steht im Hinweis). **Strg+Alt+F** im Dock-Grid '
      'führt die erste verfügbare Hilfe aus, die nicht gekennzeichnet ist.')
    a('- **Ändert Verhalten** (Entscheid E2): der Menütext endet auf %s '
      '(de %s, fr %s). Eine solche Hilfe läuft %s.'
      % (code_span(suffix['en']),
         code_span(suffix['de']) if suffix['de'] else '**%s**' % FEHLT,
         code_span(suffix['fr']) if suffix['fr'] else '**%s**' % FEHLT,
         NIE_TASTE))
    a('- **Navigation** führt nur hin: Kontextmenü und Dock-Grid, nicht die '
      'Glühbirne.')
    a('- **Refactoring** formt um, behebt den Fund aber nicht: nur '
      'Kontextmenü und Dock-Grid, je Menü einmal.')
    a('- **Unterdrücken** setzt einen Marker: Kontextmenü, Dock-Grid und '
      '**Strg+Alt+S**; in der Glühbirne nur, wenn es zum Fund auch eine '
      'Hilfe gibt.')
    a('- **Menütext:** en ist die msgid aus dem Quelltext, de und fr kommen '
      'aus den .po-Dateien. Fehlt eine Übersetzung, steht hier **%s** – die '
      'IDE zeigt dann den englischen Text. `%%s` und `%%d` setzt reDelphix '
      'beim Menüaufbau ein; was sie bedeuten, steht je Abschnitt.' % FEHLT)
    a('- **Nicht angeboten:** die wichtigsten Sperren. Eine gesperrte Hilfe '
      'steht meist ausgegraut im Kontextmenü, der Hinweis nennt den Grund.')
    a('- **Beispiel:** aus den Tests (`reDelphix/tests/uTestRdx*.pas`), '
      'gekürzt auf die betroffenen Zeilen.')
    a('')
    a('## Übersicht')
    a('')
    a('| Regel | Menütext (de) | Art | Ändert Verhalten | Abschnitt |')
    a('|---|---|---|---|---|')
    for e in entries:
        de = ' / '.join(translation(c, 'de', po) for c in e['captions']
                        if c['active'])
        a('| %s | %s | %s | %s | [%s](#%s) |'
          % (rules_overview(e).replace('|', '\\|'), de,
             ART_NAMES.get(e['art'], e['art']), changes_overview(e),
             e['rules'][0]['id'] if not e['is_recipe'] and e['rules']
             else 'Details', anchor(e)))
    a('')
    a('## Quick-Fixes je Regel')
    a('')
    for e in rows:
        render_entry(e, po, a)
    a('## Weitere Code-Aktionen')
    a('')
    a('Rezepte des Anbieters (Kern `uRdxActionCore`), in der Reihenfolge '
      'des Menüs.')
    a('')
    for e in recipes:
        render_entry(e, po, a)
    while L and L[-1] == '':
        L.pop()
    return '\n'.join(L) + '\n'


def encode_doc(text):
    """Wie jede .md im Checkout: CRLF; mit Nicht-ASCII ein UTF-8-BOM
    (tools/encoding_gate.py)."""
    data = text.replace('\n', '\r\n').encode('utf-8')
    return (BOM + data) if any(b > 127 for b in data) else data


def describe_drift(expected, actual):
    """None bei Gleichheit, sonst die erste Abweichung in Worten."""
    if expected == actual:
        return None
    exp = expected.decode('utf-8-sig', errors='replace')
    act = actual.decode('utf-8-sig', errors='replace')
    if exp.replace('\r\n', '\n') == act.replace('\r\n', '\n'):
        if expected.startswith(BOM) != actual.startswith(BOM):
            return 'nur das UTF-8-BOM weicht ab'
        return 'nur die Zeilenenden weichen ab (erwartet CRLF)'
    el = exp.replace('\r\n', '\n').split('\n')
    al = act.replace('\r\n', '\n').split('\n')
    for i in range(max(len(el), len(al))):
        e = el[i] if i < len(el) else '<Dateiende>'
        g = al[i] if i < len(al) else '<Dateiende>'
        if e != g:
            return ('erste Abweichung in Zeile %d\n  erwartet:  %s\n  '
                    'vorhanden: %s' % (i + 1, e, g))
    return 'nur das UTF-8-BOM weicht ab'


# ---------------------------------------------------------------------------
# Selbsttest: jeder Mutant muss das Gate rot machen
# ---------------------------------------------------------------------------

def selftest():
    fails, checks = [], []

    def expect(cond, what):
        print('  %s  %s' % ('ok  ' if cond else 'ROT ', what))
        checks.append(what)
        if not cond:
            fails.append(what)

    st = strip_comments("x := '// {kein} (*Kommentar*)'; // weg\n"
                        "{ weg } y := 1; (* weg *) z := '''';")
    expect("'// {kein} (*Kommentar*)'" in st and 'weg' not in st
           and "''''" in st, 'strip_comments: Literal bleibt, Kommentar geht')
    expect(eval_str("'a''b' + #39 + 'c'#13'd' + K", lambda n: 'k' if n == 'K'
                    else None) == "a'b'c\rdk",
           "eval_str: '' und #-Zeichen, Konstante")
    expect(eval_str("'uses: ' + Item.Short + ' -> ' + F(x)", lambda n: None,
                    loose=True) == 'uses: %s -> %s',
           'eval_str loose: fester Text mit %s')
    expect(split_top("f(a, b), 'x,y', [1, 2]", ',')
           == ['f(a, b)', " 'x,y'", ' [1, 2]'], 'split_top: Klammern, Literal')
    expect(caption_of("Format(_(CAP_X), [Length(L)])",
                      lambda n: 'All %d' if n == 'CAP_X' else None, 't')
           == {'msgid': 'All %d', 'translatable': True},
           'caption_of: Format(_(KONSTANTE), ..)')
    po_probe = os.path.join(REPO, 'i18n', 'de.po')
    expect(parse_po(po_probe).get('Errors') == 'Fehler',
           'parse_po: msgid "Errors" -> "Fehler"')

    inputs = load_inputs()
    model = build(inputs)
    expect(not model['errors'], 'die echten Quellen sind konsistent%s'
           % (': ' + model['errors'][0] if model['errors'] else ''))
    rows = inputs['table']['rows']
    first = model['entries'][0]
    with_alt = next(r for r in rows if r['alt'])
    by_planner = next((r for r in rows if r['changes_main'] == 'je nach Fund'),
                      None)
    with_ph = next(e for e in model['entries']
                   if any(PLACEHOLDER_RE.search(c['msgid'])
                          for c in e['captions']))
    recipe = next(e for e in model['entries'] if e['is_recipe'])
    fix_recipe = next(e for e in model['entries']
                      if e['is_recipe'] and e['art'] == 'fakFix' and e['rules'])
    covered = {e['rules'][0]['kind'] for e in model['all_entries']
               if not e['is_recipe']}
    covered |= {r['kind'] for e in model['all_entries'] if e['is_recipe']
                for r in e['rules']}
    free_kind = next(k for k, r in sorted(inputs['catalog'].items())
                     if not r.get('editorHelp') and k not in covered)

    def drop_doc(key):
        return lambda i: i['data']['eintraege'].pop(key)

    def set_field(path, value):
        def mutate(i):
            obj = i
            for p in path[:-1]:
                obj = obj[p]
            if value is None:
                obj.pop(path[-1])
            else:
                obj[path[-1]] = value
        return mutate

    def extra_row(i):
        r = dict(i['table']['rows'][0], kind=free_kind)
        r['index'] = len(i['table']['rows'])
        i['table']['rows'].append(r)
        i['table']['captions'].append('Probe')
        i['table']['alt_captions'].append('')
        i['table']['hints'].append('' if r['hint_by_planner'] else 'Probe')
        for k in i['table']['sizes']:
            n, found = i['table']['sizes'][k]
            i['table']['sizes'][k] = (n + 1, found)

    never = next(e for e in model['entries']
                 if not e['is_recipe'] and not e['alt']
                 and e['captions'][0]['changes'] == 'nein')
    fixed_hint = next(r for r in rows if not r['hint_by_planner'])
    planner_hint = next(r for r in rows if r['hint_by_planner'])
    shown = next(e for e in model['entries']
                 if e['is_recipe'] and not e['rules'] and not e['exc_rules'])

    # Je Mutant die Teile, die in EINER Meldung zusammen stehen muessen - so
    # faellt auf, wenn ein Mutant nur aus einem anderen Grund rot wird
    # (eine neue Zeile ohne editorHelp ist auch ohne JSON-Pruefung rot).
    mutants = [
        ('Art ohne JSON-Eintrag', drop_doc(first['key']),
         ('Art %s:' % first['key'], 'kein Eintrag')),
        ('Rezept ohne JSON-Eintrag', drop_doc(recipe['key']),
         ('Rezept %s:' % recipe['key'], 'kein Eintrag')),
        ('JSON-Eintrag ohne Art',
         set_field(['data', 'eintraege', 'GibtEsNicht'], first['doc']),
         ('"GibtEsNicht"', 'keine solche Art')),
        ('neue Zeile im Modell ohne JSON-Eintrag', extra_row,
         ('Art %s:' % free_kind, 'kein Eintrag')),
        ('editorHelp ohne Hilfe',
         set_field(['catalog', free_kind, 'editorHelp'], True),
         (free_kind, 'keine Zeile in FIX_ROWS und kein Rezept')),
        ('Zeile ohne editorHelp im Katalog',
         set_field(['catalog', rows[0]['kind'], 'editorHelp'], None),
         (rows[0]['kind'], 'im Katalog fehlt "editorHelp"')),
        ('Quick-Fix-Rezept ohne editorHelp im Katalog',
         set_field(['catalog', fix_recipe['rules'][0]['kind'], 'editorHelp'],
                   None),
         (fix_recipe['key'], fix_recipe['rules'][0]['kind'],
          'im Katalog fehlt "editorHelp"')),
        ('FIX_CAPTIONS kuerzer als FIX_ROWS',
         lambda i: i['table']['captions'].pop(),
         ('FIX_CAPTIONS', 'nicht gleich lang')),
        ('FIX_HINTS kuerzer als FIX_ROWS',
         lambda i: i['table']['hints'].pop(),
         ('FIX_HINTS', 'nicht gleich lang')),
        ('fester Hinweis fehlt',
         set_field(['table', 'hints', fixed_hint['index']], ''),
         (fixed_hint['kind'], 'genau eines von beiden')),
        ('fester Hinweis neben HintByPlanner',
         set_field(['table', 'hints', planner_hint['index']], 'Probe'),
         (planner_hint['kind'], 'genau eines von beiden')),
        ('zweiter Eintrag ohne Menuetext',
         set_field(['table', 'alt_captions', with_alt['index']], ''),
         (with_alt['kind'], 'FIX_ALT_CAPTIONS')),
        ('Platzhalter nicht erklaert',
         set_field(['data', 'eintraege', with_ph['key'], 'platzhalter'], None),
         (with_ph['key'], 'Feld "platzhalter" fehlt')),
        ('unbekanntes Feld',
         set_field(['data', 'eintraege', first['key'], 'tittel'], 'x'),
         ('tittel', 'unbekannte Felder')),
        ('zweiter Eintrag nicht beschrieben',
         set_field(['data', 'eintraege', with_alt['kind'], 'zweiterEintrag'],
                   None), (with_alt['kind'], 'Feld "zweiterEintrag" fehlt')),
        ('Kennzeichnung bei einer nie gekennzeichneten Hilfe',
         set_field(['data', 'eintraege', never['key'], 'kennzeichnung'], 'x'),
         (never['key'], 'kennzeichnet die Hilfe nie')),
        ('Rezept ohne Regel und ohne regelText',
         set_field(['data', 'eintraege', shown['key'], 'regelText'], None),
         (shown['key'], 'Feld "regelText" fehlt')),
        ('Beispiel fehlt',
         set_field(['data', 'eintraege', first['key'], 'beispielNachher'],
                   None), (first['key'], 'Feld "beispielNachher" fehlt')),
    ]
    if by_planner:
        mutants.append(('Kennzeichnung je nach Fund nicht erklaert',
                        set_field(['data', 'eintraege', by_planner['kind'],
                                  'kennzeichnung'], None),
                        (by_planner['kind'], '"kennzeichnung" fehlt')))
    for name, mutate, parts in mutants:
        probe = copy.deepcopy(inputs)
        mutate(probe)
        errs = build(probe)['errors']
        expect(any(all(p in e for p in parts) for e in errs),
               'Mutant erkannt: %s' % name)

    # Mutanten am QUELLTEXT: eine neue Zeile in FIX_ROWS (mit Menuetexten
    # und FIX_ROW_HIGH) bzw. ein neues Rezept im Konstruktor des Anbieters
    # muessen die Parser finden - erst dann faellt eine neue Hilfe ohne
    # Doku auf.
    table_text = load_text(SRC_TABLE)
    grown = insert_before_close(table_text, 'FIX_ALT_CAPTIONS', ", ''")
    grown = insert_before_close(grown, 'FIX_CAPTIONS', ", 'Probe'")
    grown = insert_before_close(grown, 'FIX_HINTS', ", ''")
    grown = insert_before_close(
        grown, 'FIX_ROWS', ",\n    (Kind: fk%s; Plan: %s; "
        "HintByPlanner: True; Changes: False; Alt: nil)"
        % (free_kind, rows[0]['plan']))
    grown = sub_code(grown, r'(?m)^([ \t]*FIX_ROW_HIGH[ \t]*=[ \t]*)(\d+)',
                     lambda m: m.group(1) + str(int(m.group(2)) + 1))
    probe = dict(inputs, table=parse_table(grown))
    errs = build(probe)['errors']
    expect(len(probe['table']['rows']) == len(rows) + 1
           and any('Art %s:' % free_kind in e and 'kein Eintrag' in e
                   for e in errs),
           'Quelltext-Mutant erkannt: neue Zeile in FIX_ROWS ohne JSON-Eintrag')
    prov = load_text(SRC_CORE)
    last = list(REG_RE.finditer(strip_comments(prov)))[-1]
    unsized = prov[:last.end()] + '\n  FTextRecipes[9] := AddProbe;' \
        + prov[last.end():]
    end = UNIT_END_RE.search(strip_comments(unsized),
                             unsized.index('\nimplementation') + 1)
    unsized = (unsized[:end.start()]
               + 'procedure ' + CORE_CLASS + '.AddProbe(var AList: '
                 'TArray<TRdxActionEntry>;\n  const ACtx: TRdxRecipeContext);\n'
                 "begin\n  Add(AList, _('Probe'), '', True, nil);\nend;\n\n"
               + unsized[end.start():])
    sized = sub_code(unsized, r'\bSetLength\s*\(\s*FTextRecipes\s*,\s*(\d+)',
                     lambda m: m.group(0)[:m.start(1) - m.start()]
                     + str(int(m.group(1)) + 1))
    errs = build(dict(inputs, provider=parse_provider(sized)))['errors']
    expect(any('Rezept recipe:Probe:' in e and 'kein Eintrag' in e
               for e in errs),
           'Quelltext-Mutant erkannt: neues Rezept ohne JSON-Eintrag')
    try:
        parse_provider(unsized)
        guarded = False
    except SourceError as e:
        guarded = 'Plaetze (SetLength)' in str(e)
    expect(guarded, 'Quelltext-Mutant erkannt: Rezept ohne Platz in '
                    'SetLength (Form unbekannt)')

    # Profil code-aktionen (G10-05): eine Art mit Hilfe fehlt, eine Art ohne
    # Hilfe steht drin, eine steht doppelt.
    errs = build(dict(inputs, profile=[k for k in inputs['profile']
                                       if k != rows[0]['kind']]))['errors']
    expect(any(rows[0]['kind'] in e and 'fehlt aber im Profil' in e
               for e in errs),
           'Profil-Mutant erkannt: Art mit Hilfe fehlt im Profil')
    errs = build(dict(inputs, profile=inputs['profile'] + [free_kind]))['errors']
    expect(any('Art %s hat keine Hilfe' % free_kind in e for e in errs),
           'Profil-Mutant erkannt: Art ohne Hilfe im Profil')
    errs = build(dict(inputs, profile=inputs['profile']
                      + [rows[0]['kind']]))['errors']
    expect(any('steht mehrfach' in e for e in errs),
           'Profil-Mutant erkannt: Art doppelt im Profil')
    # Kennzeichnung ausserhalb der gelesenen Units (G10-25): liest der
    # Generator eine Unit nicht, die 'ChangesBehavior :=' setzt, faellt sie
    # auf - hier die Tabelle (ihre Adapter setzen die Kennzeichnung, seit
    # G09-07 auch die der zweiten Eintraege SCA093 und SCA046).
    outside = unmarked_units(read=(SRC_RUNNER, SRC_CORE))
    expect(rel(SRC_TABLE) in outside and not unmarked_units(),
           'Kennzeichnung ausserhalb erkannt (%s)'
           % os.path.basename(SRC_TABLE))

    text = render(model, inputs['po'])
    lines = text.split('\n')
    k = len(lines) // 2
    exp = encode_doc(text)
    act = encode_doc('\n'.join(lines[:k] + [lines[k] + ' x'] + lines[k + 1:]))
    expect('Zeile %d' % (k + 1) in (describe_drift(exp, act) or ''),
           'Drift: erste abweichende Zeile (%d)' % (k + 1))
    expect('Zeilenenden' in (describe_drift(exp, exp.replace(b'\r\n', b'\n'))
                             or ''), 'Drift: nur Zeilenenden')
    expect(describe_drift(exp, exp) is None, 'Drift: gleich ist gleich')
    probe = copy.deepcopy(inputs)
    probe['po']['de'].pop(first['captions'][0]['msgid'], None)
    text2 = render(build(probe), probe['po'])
    expect(text2.count(FEHLT) > text.count(FEHLT),
           'fehlende Uebersetzung steht als %s da' % FEHLT)

    if fails:
        print('SELBSTTEST ROT: %d von %d Pruefungen' % (len(fails),
                                                         len(checks)))
        return 1
    print('SELBSTTEST GRUEN: %d Pruefungen' % len(checks))
    return 0


def insert_before_close(text, name, addition):
    """Selbsttest: addition vor die schliessende Klammer des Arrays name
    (strip_comments haelt die Positionen, also gelten sie im Original)."""
    st = strip_comments(text)
    m = re.search(r'\b%s\s*:\s*array\b[^=]*=\s*\(' % re.escape(name), st)
    close = scan_to_close(st, m.end() - 1, name)
    return text[:close] + addition + text[close:]


def sub_code(text, pattern, repl):
    """Selbsttest: das erste Vorkommen von pattern im Code (nicht in einem
    Kommentar) ersetzen."""
    m = re.search(pattern, strip_comments(text))
    return text[:m.start()] + repl(m) + text[m.end():]


# ---------------------------------------------------------------------------
# Aufruf
# ---------------------------------------------------------------------------

def print_list(model):
    for e in model['all_entries']:
        rules = rules_overview(e) if 'doc' in e or e['rules'] else '-'
        print('%-34s %-12s %-28s %s' % (e['key'], ART_NAMES.get(e['art'], '?'),
                                         rules[:28], changes_overview(e)))
        for c in e['captions']:
            print('    %s%s%s' % (c['msgid'],
                                   '' if c['translatable'] else '  [fester Text]',
                                   '' if c['active'] else '  [nur ausgegraut]'))
    print('%d Eintraege' % len(model['all_entries']))


def main(argv=None):
    ap = argparse.ArgumentParser(
        description='erzeugt reDelphix/QUICKFIXES.md (siehe Kopf der Datei)')
    group = ap.add_mutually_exclusive_group()
    group.add_argument('--check', action='store_true',
                       help='nur pruefen: Konsistenz und Drift, Exit 1')
    group.add_argument('--list', action='store_true',
                       help='Inventar der Hilfen zeigen')
    group.add_argument('--selftest', action='store_true',
                       help='das Gate an Mutanten pruefen')
    args = ap.parse_args(argv)
    try:
        if args.selftest:
            return selftest()
        inputs = load_inputs()
        model = build(inputs)
        if args.list:
            print_list(model)
            return 0
        for err in model['errors']:
            print('KONSISTENZ: ' + err)
        for note in model['notes']:
            print('Hinweis (Uebersetzung fehlt): ' + note)
        if model['errors']:
            print('%d Konsistenzfehler - %s nicht %s.'
                  % (len(model['errors']), rel(OUT),
                     'geprueft' if args.check else 'geschrieben'))
            return 1
        data = encode_doc(render(model, inputs['po']))
        if args.check:
            try:
                with open(OUT, 'rb') as f:
                    have = f.read()
            except OSError:
                have = None
            drift = ('%s fehlt' % rel(OUT) if have is None
                     else describe_drift(data, have))
            if drift:
                print('DRIFT: %s - %s' % (rel(OUT), drift))
                print('Neu erzeugen: python tools/gen-quickfix-doc.py')
                return 1
            print('OK: %s aktuell (%d Hilfen).' % (rel(OUT),
                                                    len(model['entries'])))
            return 0
        with open(OUT, 'wb') as f:
            f.write(data)
        print('geschrieben: %s (%d Hilfen).' % (rel(OUT), len(model['entries'])))
        return 0
    except SourceError as e:
        print('FEHLER: %s' % e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
