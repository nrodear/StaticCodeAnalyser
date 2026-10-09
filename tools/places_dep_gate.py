# -*- coding: utf-8 -*-
"""places_dep_gate - Richtung der Abhaengigkeit des Quellstellen-Dienstes.

WARUM ES DIESES GATE GIBT (2026-10-03)
--------------------------------------
Der Quellstellen-Dienst (uSourcePlaces mit uRefactorInfo,
uRefactorInfoBuilder, uRefactorConcat) liefert einem Fremd-Konsumenten
beschriebene Stellen einer Quelldatei - auf Anfrage, ausserhalb des
Scans. Die Zusage dahinter: Fundzahl, FP-Quote, Baselines und SARIF
koennen sich durch ihn nicht bewegen. Diese Zusage haelt nur, solange die
Abhaengigkeit in EINE Richtung zeigt: der Dienst darf die Engine lesen,
die Engine darf den Dienst nicht kennen.

Konzept_SourceRefactor_Quellstellen_2026-10-02.md, Abschnitt 6 (G2).

GEPRUEFT WIRD (ueber die uses-Klauseln; Kommentare und String-Literale
entfernt, per {$I datei} eingebundene Dateien mitgelesen):

  1. Kein Detektor (Detectors/), kein Parser (Parsing/), kein Exporter
     (Output/) und keine Infrastruktur-Unit ausser uSourcePlaces und
     uEngineApi importiert eine der vier Dienst-Units.
  2. Keine Common-Unit ausser den drei Refactor-Units selbst importiert
     eine der vier Dienst-Units.
  3. Detectors/, Parsing/, Output/, Common/ und der Scan
     (uStaticAnalyzer2) importieren auch uEngineApi nicht: die Unit traegt
     uSourcePlaces im interface-uses und reicht TSourcePlaces, TNodeRef
     usw. als Aliase weiter - ein Detektor mit 'uses uEngineApi' saehe den
     Dienst, ohne ihn beim Namen zu nennen.
  4. Die vier Dienst-Units importieren keinen Detektor und nicht
     uStaticAnalyzer2 (den Scan).

GRENZE: geprueft wird SICHTBARKEIT (direkte uses-Eintraege), nicht das
Linken. Bekannte Link-Kante: uRepoSettings (Infrastructure) importiert
uEngineApi im implementation-uses, ohne etwas davon weiterzureichen. Damit
wird der Dienst in jeden Scan-Pfad mitgelinkt (Detektor -> uRepoSettings
-> uEngineApi -> uSourcePlaces), sichtbar wird er dem Detektor dadurch
nicht: Delphi reicht uses nicht weiter, und die Dienst-Units haben weder
initialization noch finalization.

EXIT-CODE
  0  Richtung eingehalten (bzw. Selbsttest gruen)
  1  mindestens ein verbotener Import (bzw. Selbsttest rot)
  2  Aufruf-/Laufzeitfehler

    python tools/places_dep_gate.py
    python tools/places_dep_gate.py --sources <Ordner>   (Fixture-Probe)
    python tools/places_dep_gate.py --selftest

In der CI: .github/workflows/places-dep.yml (Selbsttest + Gate).
"""
import io
import os
import re
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(REPO, 'SCA.Engine', 'sources')
FOLDERS = ('Common', 'Detectors', 'Infrastructure', 'Output', 'Parsing')

SERVICE_UNITS = {'usourceplaces', 'urefactorinfo', 'urefactorinfobuilder',
                 'urefactorconcat'}
# Infrastruktur-Units, die den Dienst kennen DUERFEN.
INFRA_ALLOWED = {'usourceplaces', 'uengineapi'}
# Units, die den Dienst SICHTBAR machen: die Dienst-Units selbst und
# uEngineApi (uSourcePlaces im interface-uses, Aliase re-exportiert).
EXPOSING_UNITS = SERVICE_UNITS | {'uengineapi'}
# Was die Dienst-Units selbst nicht importieren duerfen.
SCAN_UNITS = {'ustaticanalyzer2'}

# EIN Durchgang von links nach rechts, String-Literal und Kommentar als
# gleichrangige Token: was zuerst beginnt, gewinnt - wie im Compiler. Ein
# eigener Kommentar-Strip VOR den Literalen liess ein '{' oder '(*' im
# Literal einen Schein-Kommentar bis zur naechsten '}' bzw. '*)' oeffnen,
# der eine dazwischen liegende uses-Klausel verschluckte (Audit reDelphiX
# 2026-10-07, Minor 28).
TOKEN_RE = re.compile(r"'(?:[^'\r\n]|'')*'|\{.*?\}|\(\*.*?\*\)|//[^\r\n]*",
                      re.S)
# {$I datei} / {$INCLUDE 'datei'} - nicht {$I+}/{$IFDEF}/{$IOCHECKS}.
INCLUDE_RE = re.compile(r"\{\$(?:I|INCLUDE)\s+('[^']*'|[^\s}]+)\s*\}", re.I)
USES_RE = re.compile(r'\buses\b(.*?);', re.S | re.I)
IDENT_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_.]*')


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
    """Literale -> '', Kommentare -> ' '; dazu die Namen der Includes."""
    includes = []

    def repl(m):
        tok = m.group(0)
        if tok.startswith("'"):
            return "''"
        inc = INCLUDE_RE.fullmatch(tok)
        if inc:
            includes.append(inc.group(1).strip("'"))
        return ' '

    return TOKEN_RE.sub(repl, raw), includes


def find_include(base_dir, name):
    """Include relativ zur einbindenden Datei, Schreibweise egal wie unter
    Windows (die CI laeuft auf Linux). None, wenn es die Datei nicht gibt -
    {$I %DATE%} u. ae. sind keine Dateien, und ein fehlendes echtes
    Include laesst ohnehin den Bau scheitern."""
    path = os.path.normpath(os.path.join(base_dir, name.replace('\\', '/')))
    if os.path.isfile(path):
        return path
    folder, leaf = os.path.split(path)
    if os.path.isdir(folder):
        for entry in os.listdir(folder):
            if entry.lower() == leaf.lower():
                return os.path.join(folder, entry)
    return None


def uses_of(path, _seen=None):
    """Alle Unit-Namen aus allen uses-Klauseln, klein geschrieben -
    einschliesslich der per {$I datei} eingebundenen Dateien."""
    seen = set() if _seen is None else _seen
    key = os.path.normcase(os.path.abspath(path))
    if key in seen:
        return set()
    seen.add(key)
    text, includes = strip_code(read_text(path))
    names = set()
    for m in USES_RE.finditer(text):
        body = re.sub(r"\bin\s+'[^']*'", ' ', m.group(1))
        for ident in IDENT_RE.findall(body):
            names.add(ident.split('.')[-1].lower())
    for name in includes:
        inc_path = find_include(os.path.dirname(path), name)
        if inc_path:
            names |= uses_of(inc_path, seen)
    return names


def check(sources):
    """Befunde (rel. Pfad, Art, verbotene Units) und Zahl geprueften Units."""
    base = os.path.dirname(os.path.dirname(sources))
    det_dir = os.path.join(sources, 'Detectors')
    detectors = {os.path.splitext(n)[0].lower() for n in os.listdir(det_dir)
                 if n.lower().endswith('.pas')} if os.path.isdir(det_dir) else set()
    findings = []
    checked = 0
    for folder in FOLDERS:
        root = os.path.join(sources, folder)
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            if not name.lower().endswith('.pas'):
                continue
            unit = os.path.splitext(name)[0].lower()
            path = os.path.join(root, name)
            used = uses_of(path)
            checked += 1
            rel = os.path.relpath(path, base)
            if unit in SERVICE_UNITS:
                # Regel 4 - Dateiname in Originalschreibung aus listdir,
                # damit die Pruefung auch unter Linux greift.
                bad = sorted(used & SCAN_UNITS)
                if bad:
                    findings.append((rel, 'importiert den Scan', bad))
                bad = sorted(used & detectors)
                if bad:
                    findings.append((rel, 'importiert Detektoren', bad))
                continue
            if folder == 'Infrastructure' and unit not in SCAN_UNITS:
                if unit in INFRA_ALLOWED:
                    continue
                forbidden = SERVICE_UNITS          # Regel 1
            else:
                forbidden = EXPOSING_UNITS         # Regel 1-3
            bad = sorted(used & forbidden)
            if bad:
                findings.append((rel, 'importiert den Quellstellen-Dienst', bad))
    return findings, checked


# Selbsttest: je Luecke, die das Gate schliessen soll, eine Fixture-Unit
# mit genau EINEM erwarteten Befund; uFxInfra muss gruen bleiben.
SELFTEST_FIXTURES = {
    # '{' im Literal darf die uses-Klausel dahinter nicht verschlucken.
    'Detectors/uFxLiteral.pas':
        "unit uFxLiteral;\ninterface\nconst C = '{';\nimplementation\n"
        "uses uSourcePlaces;\nconst D = '}';\nend.\n",
    # uses-Klausel in einer {$I}-Datei, Schreibweise abweichend.
    'Output/uFxInclude.pas':
        "unit uFxInclude;\ninterface\n{$I fxsvc.inc}\nimplementation\nend.\n",
    'Output/FxSvc.inc':
        "uses\n  uRefactorInfo;\n",
    # uEngineApi reicht den Dienst weiter.
    'Parsing/uFxApi.pas':
        "unit uFxApi;\ninterface\nuses uEngineApi;\nimplementation\nend.\n",
    # erlaubt: Infrastruktur darf uEngineApi; Literal/Kommentar zaehlt nicht.
    'Infrastructure/uFxInfra.pas':
        "unit uFxInfra;\ninterface\nimplementation\nuses uEngineApi;\n"
        "const S = 'uses uSourcePlaces;'; // uses uRefactorConcat;\nend.\n",
    # Dienst-Unit importiert einen Detektor.
    'Common/uRefactorInfo.pas':
        "unit uRefactorInfo;\ninterface\nuses uFxLiteral;\nimplementation\nend.\n",
}
SELFTEST_EXPECTED = {
    'uFxLiteral.pas': ['usourceplaces'],
    'uFxInclude.pas': ['urefactorinfo'],
    'uFxApi.pas': ['uengineapi'],
    'uRefactorInfo.pas': ['ufxliteral'],
}


def selftest():
    with tempfile.TemporaryDirectory() as tmp:
        sources = os.path.join(tmp, 'SCA.Engine', 'sources')
        for rel, text in SELFTEST_FIXTURES.items():
            path = os.path.join(sources, *rel.split('/'))
            if not os.path.isdir(os.path.dirname(path)):
                os.makedirs(os.path.dirname(path))
            with io.open(path, 'w', encoding='ascii', newline='\r\n') as fh:
                fh.write(text)
        findings, _ = check(sources)
    got = {}
    for rel, _, bad in findings:
        got.setdefault(os.path.basename(rel), []).extend(bad)
    errors = []
    for unit in sorted(set(got) | set(SELFTEST_EXPECTED)):
        want = SELFTEST_EXPECTED.get(unit, [])
        if sorted(got.get(unit, [])) != want:
            errors.append('%s: erwartet %s, bekommen %s'
                          % (unit, want, sorted(got.get(unit, []))))
    if errors:
        print('SELBSTTEST ROT:')
        for e in errors:
            print('  ' + e)
        return 1
    print('SELBSTTEST GRUEN: %d Fixture-Dateien, %d erwartete Befunde'
          % (len(SELFTEST_FIXTURES), len(SELFTEST_EXPECTED)))
    return 0


def main(argv):
    sources = SOURCES
    if argv == ['--selftest']:
        return selftest()
    if len(argv) == 2 and argv[0] == '--sources':
        sources = os.path.abspath(argv[1])
    elif argv:
        print(__doc__)
        return 2
    if not os.path.isdir(sources):
        print('FEHLER: Quellordner fehlt: %s' % sources)
        return 2
    findings, checked = check(sources)
    if findings:
        print('GATE ROT: %d verbotene Import(e) in %d geprueften Units'
              % (len(findings), checked))
        for rel, what, bad in findings:
            print('  %s %s: %s' % (rel, what, ', '.join(bad)))
        return 1
    print('GATE GRUEN: %d Units geprueft, der Quellstellen-Dienst wird von '
          'keinem Detektor und keiner Engine-Unit importiert.' % checked)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
