# -*- coding: utf-8 -*-
"""Doku-Paritaets-Gate: haelt die Sprachfassungen strukturell im Gleichschritt.

WARUM ES DIESES GATE GIBT (2026-08-18): die EN/DE-Paare des Repos waren
strukturell exakt parallel (identische Ueberschriftenfolge, Zeilenverhaeltnis
0,92-1,06) - aber nur durch Disziplin, nicht durch ein Werkzeug. Mit der
dritten Sprache (fr) verdreifacht sich die Drift-Flaeche. Dieses Gate macht
die Invariante pruefbar, die bisher stillschweigend galt:

  1. Jede Sprachfassung hat DIESELBE Ueberschriften-Ebenenfolge wie die
     englische Basis (## folgt #, drittes ## bleibt drittes ## ...).
     Die Ebenenfolge - nicht der Text: Ueberschriften WERDEN uebersetzt.
  2. Das Zeilenverhaeltnis liegt in einem Band (Default 0,75-1,35).
     Ein Abschnitt, der nur in einer Sprache waechst, faellt hier auf.

Gruppen werden per Namenskonvention gefunden: zu X.md gehoeren X_de.md und
X_fr.md, soweit vorhanden. Eine fehlende Sprachfassung ist KEIN Fehler -
nicht jede Datei ist (schon) uebersetzt; das Gate prueft nur, dass
Vorhandenes nicht driftet.

EXIT-CODE
  0  alle Gruppen im Gleichschritt
  1  mindestens eine Gruppe driftet
  2  Aufruf-/Laufzeitfehler

    python tools/doc_parity.py            # pruefen
    python tools/doc_parity.py --list     # nur die Gruppen zeigen
"""
import argparse
import io
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ('de', 'fr')
RATIO_MIN = 0.75
RATIO_MAX = 1.35

HEADING = re.compile(r'^(#{1,6})\s')
FENCE = re.compile(r'^\s*(```|~~~)')


def tracked_md():
    out = subprocess.run(['git', 'ls-files', '*.md'], cwd=REPO,
                         capture_output=True, text=True)
    return [f for f in out.stdout.split() if f]


def headings_and_lines(path):
    """Ueberschriften-Ebenenfolge und Zeilenzahl.

    Zaeune (```/~~~) schalten einen Code-Modus: ein '#' darin ist ein
    Shell-Kommentar oder Beispieltext, keine Ueberschrift. Ohne diese
    Unterscheidung meldete das Gate Drift, sobald ein Bash-Beispiel in nur
    einer Sprache einen Kommentar mehr traegt.
    """
    levels = []
    n = 0
    fence = False
    # utf-8-sig: ein BOM wuerde sonst vor dem ersten '#' kleben und die
    # Eroeffnungs-Ueberschrift unsichtbar machen - exakt so gefunden bei
    # docs/releases/v0.5.0_de.md, der einzigen md-Datei des Repos mit BOM.
    # Das Gate soll Struktur pruefen, nicht Byte-Hygiene.
    for line in io.open(os.path.join(REPO, path), encoding='utf-8-sig',
                        errors='replace'):
        n += 1
        if FENCE.match(line):
            fence = not fence
            continue
        if fence:
            continue
        m = HEADING.match(line)
        if m:
            levels.append(len(m.group(1)))
    return levels, n


def groups():
    files = set(tracked_md())
    out = []
    for f in sorted(files):
        base, ext = os.path.splitext(f)
        if any(base.endswith('_' + l) for l in LANGS):
            continue
        variants = {}
        for l in LANGS:
            cand = base + '_' + l + ext
            if cand in files:
                variants[l] = cand
        if variants:
            out.append((f, variants))
    return out


LINK = re.compile(r'\]\(([^)\s#]+)(#[^)]*)?\)')


def tote_links():
    """Relative Markdown-Links, deren Ziel es nicht gibt.

    WARUM HIER UND NICHT ALS EIGENES WERKZEUG: Sprachfassungen verweisen
    massiv aufeinander ('Version française', 'Deutsche Fassung'), und eine
    umbenannte oder noch nicht uebersetzte Datei erzeugt genau hier den
    Schaden - der Leser klickt auf seine Sprache und landet im Nichts.
    Struktur-Gleichschritt und erreichbare Ziele sind dieselbe Frage.

    Geprueft wird gegen den GIT-INDEX, nicht gegen das Dateisystem: eine
    Datei, die nur lokal existiert und nicht eingecheckt ist, ist fuer
    jeden anderen Leser ein toter Link. Genau so entstehen die
    Verweise auf interne Doku, die das Projekt bewusst nicht ausliefert.

    Externe Links (http, mailto) und reine Anker (#abschnitt) bleiben
    aussen vor - die eine brauchen Netz, die andere eine
    Ueberschriften-Aufloesung, und beides waere ein anderes Gate.
    """
    idx = subprocess.run(['git', 'ls-files'], cwd=REPO,
                         capture_output=True, text=True)
    bekannt = {f for f in idx.stdout.split() if f}
    tot = []
    geprueft = 0
    for md in sorted(f for f in bekannt if f.endswith('.md')):
        try:
            t = io.open(os.path.join(REPO, md), encoding='utf-8-sig',
                        errors='replace').read()
        except OSError:
            continue
        heim = os.path.dirname(md)
        for m in LINK.finditer(t):
            ziel = m.group(1)
            if ziel.startswith(('http://', 'https://', 'mailto:', '#')):
                continue
            geprueft += 1
            p = os.path.normpath(os.path.join(heim, ziel)).replace(
                os.sep, '/')
            if p in bekannt:
                continue
            # Verzeichnis-Link: der Index fuehrt nur Dateien, ein Ordner
            # gilt als vorhanden, sobald etwas darin liegt. Ohne diesen
            # Zweig meldet das Gate jeden Verweis auf einen Quellordner
            # als tot - der haeufigste Link in der Detektor-Doku.
            if any(f.startswith(p + '/') for f in bekannt):
                continue
            tot.append((md, ziel))
    return tot, geprueft


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--list', action='store_true',
                    help='nur die gefundenen Gruppen zeigen')
    args = ap.parse_args()

    grps = groups()
    if args.list:
        for base, variants in grps:
            print('%-48s %s' % (base, ' '.join(sorted(variants))))
        print('%d Gruppen' % len(grps))
        return 0

    fehler = 0
    ok = 0
    for base, variants in grps:
        try:
            base_lv, base_n = headings_and_lines(base)
        except OSError as e:
            print('FEHLER  %s nicht lesbar: %s' % (base, e))
            return 2
        for lang, path in sorted(variants.items()):
            lv, n = headings_and_lines(path)
            probleme = []
            if lv != base_lv:
                # Erste Abweichungsstelle benennen - "Folge ungleich" allein
                # hilft niemandem beim Suchen.
                pos = next((i for i, (a, b)
                            in enumerate(zip(base_lv, lv)) if a != b),
                           min(len(base_lv), len(lv)))
                probleme.append(
                    'Ueberschriftenfolge weicht ab (en: %d, %s: %d '
                    'Ueberschriften; erste Abweichung bei Nr. %d)'
                    % (len(base_lv), lang, len(lv), pos + 1))
            ratio = (n / base_n) if base_n else 0.0
            if not (RATIO_MIN <= ratio <= RATIO_MAX):
                probleme.append('Zeilenverhaeltnis %.2f ausserhalb %.2f-%.2f'
                                % (ratio, RATIO_MIN, RATIO_MAX))
            if probleme:
                fehler += 1
                print('DRIFT   %s <-> %s' % (base, path))
                for p in probleme:
                    print('        %s' % p)
            else:
                ok += 1

    tot, geprueft = tote_links()
    for md, ziel in tot:
        print('TOTER LINK  %s -> %s' % (md, ziel))

    print()
    print('Gruppen: %d   Fassungen im Gleichschritt: %d   Drift: %d'
          % (len(grps), ok, fehler))
    print('Relative Links: %d geprueft, %d ohne Ziel im Git-Index'
          % (geprueft, len(tot)))
    return 1 if (fehler or tot) else 0


if __name__ == '__main__':
    sys.exit(main())
