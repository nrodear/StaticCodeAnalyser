# -*- coding: utf-8 -*-
"""rdx_fixargs_gate - rohe Meldungs-Leser in reDelphiX (Konzept
Fix-Datenfeld_2026-10-28, Abschnitt 7).

WARUM ES DIESES GATE GIBT
--------------------------
Bis zur vollstaendigen Umstellung auf TLeakFinding.FixArgs (S2..S6) liest
reDelphiX die Daten eines Quick-Fixes (Spalte, Bezeichner, Wert) ganz
ueberwiegend noch aus dem rohen Meldungstext (AMessage/AIn) - 81 Routinen
zum Stand von S1 (Konzept Abschnitt 3). Dieses Gate haelt diese Menge als
Allowlist fest und laesst sie nur SCHRUMPFEN: ein neuer roher Leser ist
rot, ein Allowlist-Eintrag ohne passenden Treffer ist ebenfalls rot (die
Regel wurde umgestellt oder der Leser entfernt - die Allowlist muss
nachgezogen werden, damit sie den Ist-Stand nie unbemerkt ueberholt).

GEPRUEFT WIRD (ueber reDelphix/source/*.pas; Kommentare und
String-Literale vorher entfernt, wie places_dep_gate.py):
  1. Jede Routine mit einem Parameter AMessage oder AIn (Gross-/
     Kleinschreibung egal - das ist die Heuristik-Grenze, s. unten), deren
     Rumpf entweder einen der rohen Operatoren (Pos/Copy/Length/
     StartsWith/EndsWith) AUF DERSELBEN ZEILE wie den Parameternamen
     aufruft, oder einen der Lese-Helfer (ColumnFromMessage, QuotedText,
     NumberAfterKey, NumberAt, TextBetween, WordAfter, MessagePart,
     MessageTail, FirstWordOf, NameFromMessage) ueberhaupt aufruft.
  2. Zweite Pruefung: das Token 'FixArgs' kommt in SCA.Engine/sources/
     Output/*.pas und in uBaseline.pas/uExport.pas/uExportHtml.pas/
     uFindingsWorkbenchExport.pas (Infrastructure) nicht vor - FixArgs
     bewegt keinen Export, keine Baseline, keinen Fingerprint.

GRENZE (aus dem Konzept uebernommen): Heuristik ueber den Parameternamen.
Ein Parameter, der nicht AMessage/AIn heisst, faellt nicht auf - 30
Routinen in uRdxSqlTemplate/uRdxSuppress/uRdxText nennen ihn AText und
lesen damit KEINE Meldung; sie bleiben deshalb bewusst aussen vor.

EXIT-CODE
  0  Gate gruen (bzw. Selbsttest gruen)
  1  mindestens ein roter Befund (bzw. Selbsttest rot)
  2  Aufruf-/Laufzeitfehler

    python tools/rdx_fixargs_gate.py
    python tools/rdx_fixargs_gate.py --report
    python tools/rdx_fixargs_gate.py --selftest
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(REPO, 'reDelphix', 'source')
ALLOW_PATH = os.path.join(REPO, 'tools', 'rdx_fixargs_gate.allow')

OUTPUT_DIR = os.path.join(REPO, 'SCA.Engine', 'sources', 'Output')
EXPORT_FILES = [
    os.path.join(REPO, 'SCA.Engine', 'sources', 'Infrastructure', n)
    for n in ('uBaseline.pas', 'uExport.pas', 'uExportHtml.pas',
              'uFindingsWorkbenchExport.pas')
]

# Wie places_dep_gate.py: EIN Durchgang, String-Literal und Kommentar als
# gleichrangige Token - was zuerst beginnt, gewinnt.
TOKEN_RE = re.compile(r"'(?:[^'\r\n]|'')*'|\{.*?\}|\(\*.*?\*\)|//[^\r\n]*",
                      re.S)
HEADER_RE = re.compile(
    r'^[ \t]*(?:class\s+)?(?:function|procedure)\s+'
    r'([A-Za-z_][A-Za-z0-9_.<>]*)\s*\(([^)]*)\)', re.M)
PARAM_NAME_RE = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*:')
MESSAGE_PARAM_NAMES = {'amessage', 'ain'}
RAW_OPS = ('pos(', 'copy(', 'length(', 'startswith(', 'endswith(')
HELPER_NAMES = ('columnfrommessage(', 'quotedtext(', 'numberafterkey(',
                 'numberat(', 'textbetween(', 'wordafter(', 'messagepart(',
                 'messagetail(', 'firstwordof(', 'namefrommessage(')
FIXARGS_RE = re.compile(r'\bFixArgs\b')


def read_text(path):
    with io.open(path, 'rb') as fh:
        raw = fh.read()
    for enc in ('utf-8-sig', 'cp1252'):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode('latin-1')


def strip_code(raw):
    """Literale -> '', Kommentare -> ' ' (kein Include-Bedarf hier)."""
    def repl(m):
        tok = m.group(0)
        return "''" if tok.startswith("'") else ' '
    return TOKEN_RE.sub(repl, raw)


def param_names(param_text):
    return [m.group(1) for m in PARAM_NAME_RE.finditer(param_text)]


def iter_routines(text):
    """(Name, Parameternamen, Rumpftext) je Routine - der Rumpf reicht vom
    eigenen Kopf bis zum naechsten Routinenkopf (Heuristik wie die
    Fundgrenzen anderer Tool-Gates in diesem Projekt)."""
    headers = list(HEADER_RE.finditer(text))
    for i, m in enumerate(headers):
        start = m.end()
        end = headers[i + 1].start() if i + 1 < len(headers) else len(text)
        yield m.group(1), param_names(m.group(2)), text[start:end]


def routine_reads_message(params, body):
    names = {p.lower() for p in params}
    if not (names & MESSAGE_PARAM_NAMES):
        return False
    low = body.lower()
    for helper in HELPER_NAMES:
        if helper in low:
            return True
    msg_param = next(p for p in params if p.lower() in MESSAGE_PARAM_NAMES)
    word_re = re.compile(r'\b%s\b' % re.escape(msg_param), re.I)
    for line in body.splitlines():
        low_line = line.lower()
        if any(op in low_line for op in RAW_OPS) and word_re.search(line):
            return True
    return False


def check_readers(source_dir):
    """{(unit, routine)} je echtem rohen Leser."""
    found = set()
    if not os.path.isdir(source_dir):
        return found
    for name in sorted(os.listdir(source_dir)):
        if not name.lower().endswith('.pas'):
            continue
        path = os.path.join(source_dir, name)
        text = strip_code(read_text(path))
        unit = os.path.splitext(name)[0]
        for routine, params, body in iter_routines(text):
            if routine_reads_message(params, body):
                found.add((unit, routine))
    return found


def check_exports():
    """Dateien, die 'FixArgs' nennen, obwohl sie es nicht duerfen."""
    bad = []
    files = list(EXPORT_FILES)
    if os.path.isdir(OUTPUT_DIR):
        files += [os.path.join(OUTPUT_DIR, n)
                  for n in sorted(os.listdir(OUTPUT_DIR))
                  if n.lower().endswith('.pas')]
    for path in files:
        if not os.path.isfile(path):
            continue
        text = strip_code(read_text(path))
        if FIXARGS_RE.search(text):
            bad.append(os.path.relpath(path, REPO))
    return bad


def load_allowlist(path):
    """{(Unit, Routine): (Regel, Grund)} - Format Unit|Routine|Regel|Grund,
    '#' leitet eine Kommentarzeile ein, Leerzeilen zaehlen nicht."""
    entries = {}
    if not os.path.isfile(path):
        return entries
    with io.open(path, encoding='utf-8') as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('|')
            if len(parts) != 4:
                raise ValueError('%s:%d: Format Unit|Routine|Regel|Grund '
                                  'erwartet: %r' % (path, lineno, line))
            unit, routine, regel, grund = parts
            entries[(unit, routine)] = (regel, grund)
    return entries


def diff(found, allowlist):
    """(neue Leser, veraltete Eintraege) - je eine sortierte Liste."""
    new_readers = sorted(found - set(allowlist))
    stale_entries = sorted(set(allowlist) - found)
    return new_readers, stale_entries


def run_gate(report=False):
    found = check_readers(SOURCE_DIR)
    allowlist = load_allowlist(ALLOW_PATH)
    new_readers, stale_entries = diff(found, allowlist)
    export_hits = check_exports()
    if report:
        print('Rohe Leser gefunden: %d, Allowlist-Eintraege: %d'
              % (len(found), len(allowlist)))
    red = bool(new_readers or stale_entries or export_hits)
    if new_readers:
        print('NEUE ROHE LESER (nicht in der Allowlist, %s):' % ALLOW_PATH)
        for unit, routine in new_readers:
            print('  %s|%s' % (unit, routine))
    if stale_entries:
        print('VERALTETE ALLOWLIST-EINTRAEGE (kein Treffer mehr - Regel '
              'umgestellt oder Leser entfernt, Allowlist nachziehen):')
        for unit, routine in stale_entries:
            regel, grund = allowlist[(unit, routine)]
            print('  %s|%s|%s|%s' % (unit, routine, regel, grund))
    if export_hits:
        print('FixArgs taucht in einem Export/Baseline-Pfad auf (verboten):')
        for rel in export_hits:
            print('  %s' % rel)
    if red:
        print('GATE ROT')
        return 1
    print('GATE GRUEN: %d rohe Leser (Allowlist deckungsgleich), kein '
          'FixArgs in Export/Baseline.' % len(found))
    return 0


# Selbsttest: synthetische Fixtures statt des echten Quelltexts, damit das
# Gate unabhaengig vom jeweiligen Ist-Stand von reDelphix/source gruen
# bleibt (wie places_dep_gate.py.selftest).
SELFTEST_FIXTURES = {
    # AMessage + Pos auf derselben Zeile -> roher Leser.
    'uFxRawPos.pas':
        "unit uFxRawPos;\ninterface\nimplementation\n"
        "function ReadIt(const AMessage: string): Integer;\nbegin\n"
        "  Result := Pos('x', AMessage);\nend;\nend.\n",
    # Helfer-Aufruf -> roher Leser, unabhaengig von der Zeile des Arguments.
    'uFxHelper.pas':
        "unit uFxHelper;\ninterface\nimplementation\n"
        "function ColOf(const AIn: string): Integer;\nbegin\n"
        "  Result := ColumnFromMessage(AIn);\nend;\nend.\n",
    # AMessage ungenutzt -> kein Leser.
    'uFxUnused.pas':
        "unit uFxUnused;\ninterface\nimplementation\n"
        "function Noop(const AMessage: string): Integer;\nbegin\n"
        "  Result := 0;\nend;\nend.\n",
    # Pos auf einer anderen Variable als AMessage -> kein Leser (Heuristik
    # prueft die Zeile, nicht nur die Routine).
    'uFxOtherVar.pas':
        "unit uFxOtherVar;\ninterface\nimplementation\n"
        "function ReadOther(const AMessage, AOther: string): Integer;\n"
        "begin\n  Result := Pos('x', AOther);\nend;\nend.\n",
    # Anderer Parametername (AText) liest trotz Pos nicht als Meldung -
    # dokumentierte Heuristik-Grenze aus dem Konzept.
    'uFxOtherName.pas':
        "unit uFxOtherName;\ninterface\nimplementation\n"
        "function ReadText(const AText: string): Integer;\nbegin\n"
        "  Result := Pos('x', AText);\nend;\nend.\n",
    # Literal mit '{' darf keine folgende Routine verschlucken.
    'uFxLiteralBrace.pas':
        "unit uFxLiteralBrace;\ninterface\nimplementation\n"
        "const C = '{';\n"
        "function ReadIt(const AMessage: string): Integer;\nbegin\n"
        "  Result := Pos('x', AMessage);\nend;\nend.\n",
}
SELFTEST_EXPECTED = {
    ('uFxRawPos', 'ReadIt'),
    ('uFxHelper', 'ColOf'),
    ('uFxLiteralBrace', 'ReadIt'),
}


def selftest():
    found = set()
    for name, text in SELFTEST_FIXTURES.items():
        unit = os.path.splitext(name)[0]
        stripped = strip_code(text)
        for routine, params, body in iter_routines(stripped):
            if routine_reads_message(params, body):
                found.add((unit, routine))
    errors = []
    if found != SELFTEST_EXPECTED:
        missing = SELFTEST_EXPECTED - found
        extra = found - SELFTEST_EXPECTED
        if missing:
            errors.append('fehlend: %s' % sorted(missing))
        if extra:
            errors.append('zu viel: %s' % sorted(extra))
    if errors:
        print('SELBSTTEST ROT: ' + '; '.join(errors))
        return 1
    print('SELBSTTEST GRUEN: %d Fixture-Dateien, %d erwartete Befunde'
          % (len(SELFTEST_FIXTURES), len(SELFTEST_EXPECTED)))
    return 0


def main(argv):
    if argv == ['--selftest']:
        return selftest()
    if argv == ['--report']:
        return run_gate(report=True)
    if argv:
        print(__doc__)
        return 2
    return run_gate(report=False)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
