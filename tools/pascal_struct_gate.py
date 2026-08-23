# -*- coding: utf-8 -*-
"""Compilerfreier Struktur-Check fuer Pascal-Quelltexte.

WOZU: In dieser Sitzung sind drei Baufehler beim Nutzer gelandet, die alle
maschinell erkennbar gewesen waeren, weil sie NICHTS mit Semantik zu tun
haben - nur mit Struktur:

  * E2010  Create-Aufruf auf einen neuen Typ umgestellt, die
           Variablendeklaration darueber nicht.
  * E2070/E2029  Methodenrumpf hinter 'initialization' eingehaengt, weil
           blind vor 'end.' angehaengt wurde.
  * E2065  [Test]-Methode deklariert, aber nicht implementiert (oder
           umgekehrt).
  * E2026  {$IF RTLVersion >= NN} in einer .dpk - RTLVersion ist eine
           Gleitkommakonstante und dort kein Konstantenausdruck.

Hier kann nicht compiliert werden (nur der Nutzer baut, in der IDE). Dieses
Skript ist der Ersatz fuer den Compiler bei genau diesen Klassen - es liest
Text, kennt keine Typen und will das auch nicht.

    python tools/pascal_struct_gate.py [pfad ...]      # Default: geaenderte Dateien

EXIT
  0  keine Befunde
  1  mindestens ein Befund
  2  Aufruf-/Laufzeitfehler
"""
import io
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NL = chr(10)

ROUTINE_HEAD = re.compile(
    r'^\s*(?:class\s+)?(?:procedure|function|constructor|destructor)\s+'
    r'([A-Za-z_][\w.]*)', re.I)
# Signaturende: schliessende Klammer (+ optionaler Rueckgabetyp) + ';'
# ODER parameterlos: Name (+ Rueckgabetyp) + ';'
SIG_END = re.compile(r'\)\s*(?::\s*[\w<>, .]+)?\s*;|^\s*(?:class\s+)?'
                     r'(?:procedure|function|constructor|destructor)\s+'
                     r'[\w.]+\s*(?::\s*[\w<>, .]+)?\s*;', re.I)
TEST_DECL = re.compile(r'\[Test\]\s*procedure\s+(\w+)', re.I)


def strip_noise(text):
    """Kommentare und String-Literale durch Leerzeichen ersetzen, Zeilen und
    Spalten aber erhalten.

    Ohne das meldet der Parameter-Check jedes deutsche Grossbuchstabenwort
    aus einem Kommentar ("ALLEN", "ANDERES", "ABSTEIGEND") als vergessenen
    Parameter - beim ersten Versuch genau so passiert. Ein Gate mit
    Fehlalarmen wird ignoriert und ist damit schlechter als keins.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":                      # String-Literal
            j = i + 1
            while j < n and text[j] != "'" and text[j] != '\n':
                j += 1
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        elif text.startswith('//', i):    # Zeilenkommentar
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif c == '{':                    # Blockkommentar (schachtelt NICHT)
            j = text.find('}', i)
            j = n if j < 0 else j
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        elif text.startswith('(*', i):
            j = text.find('*)', i)
            j = n if j < 0 else j + 1
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        else:
            i += 1
    return ''.join(out)


def read(path):
    for enc in ('utf-8-sig', 'utf-8', 'cp1252'):
        try:
            return io.open(path, encoding=enc).read().replace('\r\n', '\n')
        except UnicodeDecodeError:
            continue
    return None


def section_bounds(lines):
    """(implementation, initialization|finalization, end.) - jeweils Index oder -1."""
    impl = init = fin = -1
    for i, l in enumerate(lines):
        s = l.strip().lower()
        if impl < 0 and s == 'implementation':
            impl = i
        elif init < 0 and s in ('initialization', 'finalization'):
            init = i
        elif s == 'end.':
            fin = i
    return impl, init, fin


def check_bodies_before_initialization(path, lines, out):
    """E2070/E2029: Methodenrumpf hinter initialization/finalization."""
    impl, init, _ = section_bounds(lines)
    if init < 0:
        return
    for i in range(init + 1, len(lines)):
        m = ROUTINE_HEAD.match(lines[i])
        if m and '.' in m.group(1):
            out.append((path, i + 1,
                        'Methodenrumpf %s steht HINTER "%s" - dort sind nur '
                        'Anweisungen erlaubt (E2070/E2029). Rumpf davor '
                        'einhaengen.' % (m.group(1), lines[init].strip())))


def routine_spans(lines, start, stop):
    """[(kopfzeile, signatur, rumpf, name)] im Bereich [start, stop)."""
    heads = [i for i in range(start, stop) if ROUTINE_HEAD.match(lines[i])]
    for k, i in enumerate(heads):
        end = heads[k + 1] if k + 1 < len(heads) else stop
        j = i
        while j < end and not SIG_END.search(lines[j]):
            j += 1
        j = min(j, end - 1)
        yield (i, '\n'.join(lines[i:j + 1]), '\n'.join(lines[j + 1:end]),
               ROUTINE_HEAD.match(lines[i]).group(1))


# Auch ANONYME Methoden: 'procedure(const AFileName: string)' hat
# keinen Namen, ihre Parameter sind im umgebenden Rumpf aber gueltig.
# ---------------------------------------------------------------------
# ENTFERNT am 2026-08-23: check_param_consistency
#
# Die Pruefung sollte E2003 abfangen ("Aufrufstelle auf einen neuen
# Parameter umgestellt, Signatur nicht"). Sie suchte Bezeichner im
# Projektstil A<GrossKlein>, die im Rumpf stehen, aber nicht in der
# Signatur.
#
# Gemessen auf dem eigenen Repo: 121 Befunde in Quelltext, der
# nachweislich uebersetzt - 91 in der Engine, 25 im IDE-Paket, 5 in
# SharedUI. Zwei Ursachen liessen sich noch schliessen (fehlende
# Wortgrenze, sodass "IOTAAboutBoxServices" als "AAboutBoxServices"
# gelesen wurde; verschachtelte und anonyme Routinen, deren Parameter im
# umgebenden Rumpf gueltig sind). Danach blieben immer noch 121 - Pascal
# hat zu viele Wege, einen Bezeichner gueltig zu machen (with-Bloecke,
# Methoden von Klassen im implementation-Teil, Record-Felder,
# Unit-Variablen), als dass Textsuche das entscheiden koennte.
#
# Der Kopf dieser Datei sagt es selbst: ein Gate mit Fehlalarmen wird
# ignoriert und ist damit schlechter als keins. Die drei verbleibenden
# Pruefungen sind praezise und bleiben.
#
# Wer es neu versucht, braucht einen Parser, keinen regulaeren Ausdruck.
# ---------------------------------------------------------------------


KLASSENKOPF = re.compile(r'^\s*(T\w+)\s*=\s*class\s*\(\s*(T\w+)',
                         re.M | re.I)
_VORFAHREN = {}


def vorfahren_index():
    """{Klasse: Basisklasse} aus allen .pas des Repos.

    Ohne Vererbung meldet die E2010-Pruefung jede Polymorphie als Fehler:
    'Enc: TEncoding := TUTF8Encoding.Create' ist voellig richtig. Am
    2026-08-23 waren genau solche Faelle die letzten zwei Fehlalarme.
    """
    if _VORFAHREN:
        return _VORFAHREN
    for base, _dirs, files in os.walk(ROOT):
        if any(t in base.lower() for t in ('\\.git', '\\__history',
                                           '\\output', '\\lib')):
            continue
        for f in files:
            if not f.lower().endswith('.pas'):
                continue
            t = read(os.path.join(base, f))
            if t:
                for kind, ancestor in KLASSENKOPF.findall(t):
                    _VORFAHREN.setdefault(kind, ancestor)
    return _VORFAHREN


def ist_nachfahre(kind, moeglicher_vorfahre):
    """Kann ich BEWEISEN, dass kind von moeglicher_vorfahre abstammt?

    Rueckgabe None heisst "unbekannt" - dann schweigt die Pruefung.
    Klassen aus RTL/VCL stehen nicht im Repo und sind damit unbekannt;
    lieber kein Befund als ein falscher.
    """
    idx = vorfahren_index()
    if kind not in idx:
        return None
    gesehen = set()
    while kind in idx and kind not in gesehen:
        gesehen.add(kind)
        kind = idx[kind]
        if kind == moeglicher_vorfahre:
            return True
    return False


def check_var_type_matches_create(path, lines, out):
    """E2010: 'X := TFoo.Create' obwohl 'X : TBar' deklariert ist.

    Meldet nur, wenn die Ableitung im Repo AUFLOESBAR ist und TFoo
    nachweislich kein TBar ist. Ist die Klasse unbekannt (RTL, VCL,
    Fremdbibliothek), bleibt die Pruefung still.
    """
    impl, init, fin = section_bounds(lines)
    if impl < 0:
        return
    stop = init if init > 0 else (fin if fin > 0 else len(lines))
    for head, sig, body, name in routine_spans(lines, impl, stop):
        decls = dict(re.findall(r'^\s*(\w+)\s*:\s*([\w<>., ]+?)\s*;',
                                sig + NL + body, re.M))
        for var, typ in re.findall(r'^\s*(\w+)\s*:=\s*(T\w+)\.Create',
                                   body, re.M):
            declared = (decls.get(var) or '').strip()
            if not declared or declared == typ:
                continue
            if ist_nachfahre(typ, declared) is not False:
                continue          # abgeleitet oder unbekannt -> schweigen
            out.append((path, head + 1,
                        '%s: "%s" ist als %s deklariert, bekommt aber '
                        '%s.Create - und %s stammt nicht davon ab (E2010)'
                        % (name, var, declared, typ, typ)))


def check_test_decl_impl(path, lines, out):
    """E2065: [Test]-Deklaration ohne Rumpf (und umgekehrt)."""
    impl, _, _ = section_bounds(lines)
    if impl < 0:
        return
    head, body = '\n'.join(lines[:impl]), '\n'.join(lines[impl:])
    for m in TEST_DECL.finditer(head):
        if not re.search(r'procedure\s+\w+\.%s\b' % re.escape(m.group(1)),
                         body, re.I):
            out.append((path, 0, '[Test] %s ist deklariert, aber nicht '
                                 'implementiert (E2065)' % m.group(1)))


IF_VERSION = re.compile(r'\{\$IF[^}]*(RTLVersion|CompilerVersion)[^}]*\}',
                        re.I)


def check_dpk_version_if(path, lines, out):
    """E2026: {$IF RTLVersion >= NN} in einer .dpk.

    In einer .dpk bricht das ab - dcc64 meldet erst W1023 und dann
    E2026 "Konstantenausdruck erwartet", weil RTLVersion eine
    Gleitkommakonstante ist. Hier am 2026-08-22 gemessen, nicht
    vermutet. Was traegt, ist das Versions-Symbol: {$IFDEF VER370}
    (belegt in source/Indy10/System/IdCompilerDefines.inc der
    D13-Installation, Ueberschrift "Delphi & CBuilder 13.0 Florence").
    """
    for i, line in enumerate(lines):
        # Nur echten Code ansehen. Der Erklaerblock in genau diesen .dpk
        # NENNT die falsche Form ("NICHT {$IF RTLVersion...}") - wer die
        # ganze Zeile prueft, meldet den eigenen Warnhinweis als Fehler.
        m = IF_VERSION.search(line.split('//')[0])
        if m:
            out.append((path, i + 1,
                        '%s in einer Package-Datei: dcc meldet darauf E2026 '
                        '"Konstantenausdruck erwartet" - stattdessen '
                        '{$IFDEF VERxxx} benutzen.' % m.group(0)))


def changed_files():
    try:
        o = subprocess.run(['git', 'diff', '--name-only', 'HEAD'], cwd=ROOT,
                           capture_output=True, text=True, timeout=30)
        u = subprocess.run(['git', 'ls-files', '-o', '--exclude-standard'],
                           cwd=ROOT, capture_output=True, text=True, timeout=30)
    except Exception:
        return []
    names = (o.stdout + u.stdout).splitlines()
    return [os.path.join(ROOT, n) for n in names
            if n.lower().endswith(('.pas', '.dpk', '.dpr'))]


def main():
    targets = [os.path.abspath(a) for a in sys.argv[1:]] or changed_files()
    targets = [t for t in targets if os.path.isfile(t)]
    if not targets:
        print('Nichts zu pruefen (keine geaenderten .pas-Dateien).')
        return 0

    out = []
    for path in targets:
        text = read(path)
        if text is None:
            continue
        lines = text.split('\n')
        try:
            rel = os.path.relpath(path, ROOT)
        except ValueError:
            # anderes Laufwerk (Windows) - dann eben der volle Pfad
            rel = path
        if path.lower().endswith(('.dpk', '.dpr')):
            check_dpk_version_if(rel, lines, out)
            continue
        check_bodies_before_initialization(rel, lines, out)
        check_var_type_matches_create(rel, lines, out)
        check_test_decl_impl(rel, lines, out)

    if not out:
        print('GATE GRUEN: %d Datei(en) geprueft, keine Strukturbefunde.'
              % len(targets))
        return 0

    for path, line, msg in out:
        where = '%s:%d' % (path, line) if line else path
        print('%s\n   %s' % (where, msg))
    print('\nGATE ROT: %d Befund(e). Das sind Fehler, die der Compiler beim '
          'Nutzer meldet - hier vorher.' % len(out))
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:      # noqa: BLE001 - Gate darf nie haengenbleiben
        print('Gate-Fehler: %s' % exc)
        sys.exit(2)
