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

Konzept_SourceRefactor_Quellstellen_2026-10-02.md, §6 (G2).

GEPRUEFT WIRD (ueber die uses-Klauseln, Kommentare entfernt):

  1. Kein Detektor (Detectors/), kein Parser (Parsing/), kein Exporter
     (Output/) und keine Infrastruktur-Unit ausser uSourcePlaces und
     uEngineApi importiert eine der vier Dienst-Units.
  2. Keine Common-Unit ausser den drei Refactor-Units selbst importiert
     eine der vier Dienst-Units.
  3. Die vier Dienst-Units importieren keinen Detektor und nicht
     uStaticAnalyzer2 (den Scan).

EXIT-CODE
  0  Richtung eingehalten
  1  mindestens ein verbotener Import
  2  Aufruf-/Laufzeitfehler

    python tools/places_dep_gate.py
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
SOURCES = os.path.join(REPO, 'SCA.Engine', 'sources')

SERVICE_UNITS = {'usourceplaces', 'urefactorinfo', 'urefactorinfobuilder',
                 'urefactorconcat'}
# Infrastruktur-Units, die den Dienst kennen DUERFEN.
INFRA_ALLOWED = {'usourceplaces', 'uengineapi'}
# Was die Dienst-Units selbst nicht importieren duerfen.
SCAN_UNITS = {'ustaticanalyzer2'}

COMMENT_RE = re.compile(r'\{.*?\}|\(\*.*?\*\)|//[^\r\n]*', re.S)
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


def uses_of(path):
    """Alle Unit-Namen aus allen uses-Klauseln, klein geschrieben."""
    text = COMMENT_RE.sub(' ', read_text(path))
    names = set()
    for m in USES_RE.finditer(text):
        body = re.sub(r"\bin\s+'[^']*'", ' ', m.group(1))
        for ident in IDENT_RE.findall(body):
            names.add(ident.split('.')[-1].lower())
    return names


def main():
    if not os.path.isdir(SOURCES):
        print('FEHLER: Quellordner fehlt: %s' % SOURCES)
        return 2
    findings = []
    checked = 0
    for folder in ('Common', 'Detectors', 'Infrastructure', 'Output', 'Parsing'):
        root = os.path.join(SOURCES, folder)
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            if not name.lower().endswith('.pas'):
                continue
            unit = os.path.splitext(name)[0].lower()
            path = os.path.join(root, name)
            used = uses_of(path)
            checked += 1
            rel = os.path.relpath(path, REPO)
            if unit in SERVICE_UNITS:
                bad = sorted(used & SCAN_UNITS)
                if bad:
                    findings.append('%s importiert den Scan: %s' % (rel, ', '.join(bad)))
                continue
            allowed = (folder == 'Infrastructure' and unit in INFRA_ALLOWED)
            if allowed:
                continue
            bad = sorted(used & SERVICE_UNITS)
            if bad:
                findings.append('%s importiert den Quellstellen-Dienst: %s'
                                % (rel, ', '.join(bad)))
    # Detektoren duerfen von den Dienst-Units auch nicht importiert werden.
    det_dir = os.path.join(SOURCES, 'Detectors')
    detectors = {os.path.splitext(n)[0].lower() for n in os.listdir(det_dir)
                 if n.lower().endswith('.pas')} if os.path.isdir(det_dir) else set()
    for folder in ('Common', 'Infrastructure'):
        for unit in SERVICE_UNITS:
            path = os.path.join(SOURCES, folder, unit + '.pas')
            if not os.path.isfile(path):
                continue
            # Dateiname mit Originalschreibweise suchen
            for name in os.listdir(os.path.join(SOURCES, folder)):
                if name.lower() == unit + '.pas':
                    path = os.path.join(SOURCES, folder, name)
            bad = sorted(uses_of(path) & detectors)
            if bad:
                findings.append('%s importiert Detektoren: %s'
                                % (os.path.relpath(path, REPO), ', '.join(bad)))
    if findings:
        print('GATE ROT: %d verbotene Import(e) in %d geprueften Units'
              % (len(findings), checked))
        for f in findings:
            print('  ' + f)
        return 1
    print('GATE GRUEN: %d Units geprueft, der Quellstellen-Dienst wird von '
          'keinem Detektor und keiner Engine-Unit importiert.' % checked)
    return 0


if __name__ == '__main__':
    sys.exit(main())
