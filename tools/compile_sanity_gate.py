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
        werte |= set(re.findall(r'[(,]\s*(' + pat + r')\s*[,)]', alle))
    return werte


def ohne_kommentar(text):
    out = []
    for ln in text.split('\n'):
        i = ln.find('//')
        out.append(ln[:i] if i >= 0 else ln)
    return '\n'.join(out)


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
    kind2cls = {}
    for m in re.finditer(r"AddD\(\s*'[^']*'\s*,\s*(fk[A-Za-z0-9_]+)\s*,\s*"
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
        pruefe_enums(d, deklariert, befunde)
        if os.sep + 'tests' + os.sep in d.replace('/', os.sep):
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
