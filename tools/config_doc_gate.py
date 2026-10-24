# -*- coding: utf-8 -*-
"""Konfigurations-Gate: haelt Code, INI-Vorlage und Doku deckungsgleich.

WARUM ES DIESES GATE GIBT (2026-08-19)
--------------------------------------
Dieselbe Fehlerklasse, die im Regelkatalog aufgefallen ist, nur eine Ebene
tiefer. Dort dokumentierten 25 Regeln einen Konfigurationsschluessel, den
der Code nie liest - wer ihn setzte, bekam weder Wirkung noch Warnung.
Die Konfiguration hat drei Beschreibungen desselben Gegenstands, die
unabhaengig voneinander gepflegt werden:

  1. der CODE          - Ini.ReadXxx / QuickReadXxx, die einzige Wahrheit
  2. die INI-VORLAGE   - DEFAULT_INI_CONTENT, was der Nutzer vorfindet
  3. die DOKU          - docs/configuration.md und ihre Sprachfassungen

Auseinanderlaufen kann jedes Paar, und jede Richtung hat ihren eigenen
Schaden:

  dokumentiert, aber nicht gelesen  -> Nutzer stellt etwas ein, das nichts
                                       tut. Der schlimmste Fall, weil er
                                       still ist.
  gelesen, aber nicht dokumentiert  -> unsichtbare Option; niemand findet
                                       sie ausser durch Quelltextlesen.
  gelesen, aber nicht in der Vorlage -> die Datei, die der Nutzer beim
                                       ersten Start bekommt, verschweigt
                                       eine Stellschraube.

ZWEITE DATEI: redelphix.ini (Entscheid E29, 2026-10-15)
--------------------------------------------------------
reDelphix hat eine eigene ini neben analyser.ini - dieselbe Fehlerklasse,
ein eigenes Tripel: der Code liest ueber RdxIniValue/ReadRdxIni
(reDelphix/source/uRdxText.pas), die Vorlage ist RDX_INI_TEMPLATE in
derselben Unit, die Doku die Tabellen unter '### `[Sektion]`' im
Abschnitt "## Sprache und redelphix.ini" von reDelphix/README.md. Getrennt
von analyser.ini geprueft: [UI] Language steht in beiden Dateien, mit
verschiedener Vorgabe (en bzw. auto) - zusammengeworfen saehe das Gate
einen fehlenden Schluessel der einen Datei in der anderen als vorhanden.
Dass uRdxText im Fall 'auto' auch analyser.ini [UI] Language liest, zaehlt
hier nicht: der Schluessel gehoert der SCA, die ihn selbst liest.

EXIT-CODE
  0  deckungsgleich
  1  mindestens eine Abweichung
  2  Aufruf-/Lesefehler

    python tools/config_doc_gate.py           # pruefen
    python tools/config_doc_gate.py --list    # alle Schluessel je Quelle
"""
import argparse
import io
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

NL = chr(10)
Q = chr(39)
REPO = Path(__file__).resolve().parent.parent
SETTINGS = REPO / 'SCA.Engine' / 'sources' / 'Infrastructure' / 'uRepoSettings.pas'
DOKU = REPO / 'docs' / 'configuration.md'

QUELLEN = ('SCA.Engine', 'SCA.SharedUI',
           'StaticCodeAnalyserForm/sources', 'StaticCodeAnalyserIDE')

# redelphix.ini (s. Kopf): Code, Vorlage, Doku-Abschnitt.
RDX_QUELLEN = ('reDelphix/source',)
RDX_VORLAGE = REPO / 'reDelphix' / 'source' / 'uRdxText.pas'
RDX_DOKU = REPO / 'reDelphix' / 'README.md'
RDX_ABSCHNITT = '## Sprache und redelphix.ini'
# RdxIniValue(<Sektion>, <Schluessel>) und der interne ReadRdxIni - beide
# Argumente Literal oder Konstante wie bei LESER. Die Deklarationen
# ('(const ASection, ...') passen nicht: 'const ASection' ist kein Token.
RDX_LESER = re.compile(
    r"\b(?:RdxIniValue|ReadRdxIni)\s*\(\s*"
    r"('[\w.<>]+'|[A-Za-z_]\w*)\s*,\s*('[\w.<>]+'|[A-Za-z_]\w*)")

# Ini.ReadString(<Sektion>, <Schluessel>, ...) und die Quick-Varianten.
# BEIDE Argumente duerfen ein Literal ODER ein Bezeichner sein: das Projekt
# ruft an mehreren Stellen QuickReadStr(INI_SECTION, KEY_EXE, '') mit
# lokalen Konstanten. Eine Fassung, die nur Literale sieht, meldet genau
# diese Stellen als "vom Code nie gelesen" - drei Phantome allein aus
# uEditorCommand, dazu [UI] Theme aus uAppTheme.
LESER = re.compile(
    r"\b\w*\.?(?:Read(?:String|Bool|Integer|Float)|"
    r"QuickRead(?:Bool|IntDef|Str))\s*\(\s*"
    r"('[\w.<>]+'|[A-Za-z_]\w*)\s*,\s*('[\w.<>]+'|[A-Za-z_]\w*)")

# "IDENT = 'Text';" - Konstantendeklarationen, um die Bezeichner oben
# aufzuloesen. Bewusst dateiweit und ohne Scope-Analyse: die Namen sind
# je Unit eindeutig, und ein falsch aufgeloester Name faellt beim
# Gate-Lauf sofort als unbekannte Sektion auf.
KONST = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*'([^']*)'\s*;", re.M)

# Schluessel, die zur Laufzeit zusammengesetzt werden. uUiElementRegistry
# baut "'Element.' + <Elementname>"; in Vorlage und Doku steht dafuer ein
# Platzhalter. Ohne diese Bruecke meldet das Gate 'Element.<Name>' als
# undokumentiert und 'Element.AnnotationOverlay' als ungelesen.
DYNAMISCH = {"'Element.'": ('UI', 'Element.<Name>')}

# Schluessel, die BEWUSST nicht in Vorlage und Doku stehen: reiner
# Sitzungszustand, den die Oberflaeche selbst schreibt und wieder liest.
# Sie in die Vorlage aufzunehmen hiesse, dem Nutzer Fensterkoordinaten
# zum Editieren anzubieten - und ihn glauben zu machen, sie waeren als
# Einstellung gemeint.
NUR_ZUSTAND = {
    ('Window', 'Left'), ('Window', 'Top'),
    ('Window', 'Width'), ('Window', 'Height'), ('Window', 'Maximized'),
    ('FindingsPropertiesPanel', 'Left'), ('FindingsPropertiesPanel', 'Top'),
    ('FindingsPropertiesPanel', 'Width'),
    ('FindingsPropertiesPanel', 'Height'),
    ('Grid', 'W'),
}


def normiere(paar):
    """Konkrete Element-Namen auf den Platzhalter zurueckfuehren.

    Die Vorlage zeigt ';Element.AnnotationOverlay=0' als BEISPIEL fuer
    eine ganze Schluesselfamilie, die Doku fuehrt sie als
    'Element.<Name>'. Ohne diese Normierung stritte das Gate ueber den
    Beispielnamen statt ueber die Familie.
    """
    sek, key = paar
    if sek == 'UI' and key.startswith('Element.'):
        return ('UI', 'Element.<Name>')
    return paar


def code_schluessel(quellen=QUELLEN, leser=LESER, dynamisch=DYNAMISCH):
    """(Sektion, Schluessel) -> Menge der Fundorte.

    Ohne Argumente analyser.ini; redelphix.ini mit RDX_QUELLEN/RDX_LESER
    und ohne DYNAMISCH (dort setzt niemand Schluessel zusammen).
    """
    out = {}
    for q in quellen:
        wurzel = REPO / q
        if not wurzel.is_dir():
            continue
        for p in wurzel.rglob('*.pas'):
            if '__history' in p.parts:
                continue
            try:
                t = io.open(p, encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            konst = dict(KONST.findall(t))

            def loese(x, _k=konst):
                if x.startswith(Q):
                    return x.strip(Q)
                return _k.get(x)

            rel = str(p.relative_to(REPO)).replace('\\', '/')
            for m in leser.finditer(t):
                sek, key = loese(m.group(1)), loese(m.group(2))
                if not sek or not key:
                    continue        # Bezeichner ohne auffindbare Konstante
                out.setdefault((sek, key), set()).add(rel)
            # Zusammengesetzte Schluessel: nur der Praefix steht als
            # Literal im Code, der Rest entsteht zur Laufzeit.
            for marke, ziel in dynamisch.items():
                if marke in t:
                    out.setdefault(ziel, set()).add(rel)
    return out


def vorlagen_schluessel(datei=SETTINGS, konstante='DEFAULT_INI_CONTENT'):
    """Was die Vorlage anbietet - aktiv wie auskommentiert.

    Ohne Argumente DEFAULT_INI_CONTENT (analyser.ini), sonst die
    Konstante in datei (RDX_INI_TEMPLATE fuer redelphix.ini).
    Der Block ist eine Pascal-Stringverkettung mit VERDOPPELTEN
    Apostrophen; deshalb geparst statt gegrept. Ende ist die erste
    Literalzeile ohne abschliessendes Plus - die Suche nach "';" am
    Zeilenende laeuft ueber den Block hinaus, weil weiter unten
    'FBaseBranch := '''';' auf dasselbe Muster passt.
    """
    t = io.open(datei, encoding='utf-8-sig').read()
    i = t.index('  %s =' % konstante)
    zeilen = []
    for z in t[i:].split(NL):
        zeilen.append(z)
        if z.strip().startswith(Q) and not z.rstrip().endswith('+'):
            break
    muster = re.compile(r"^\s*'((?:[^']|'')*)'(?:#13#10)?\s*\+?\s*;?\s*$")
    text = []
    for z in zeilen:
        m = muster.match(z)
        if m:
            text.append(m.group(1).replace(Q + Q, Q))

    aktiv, beispiel, sek = set(), set(), None
    for z in text:
        s = z.strip()
        m = re.match(r'^\[(\w+)\]$', s)
        if m:
            sek = m.group(1)
            continue
        if sek is None:
            continue
        m = re.match(r'^([\w.<>]+)\s*=', s)
        if m:
            aktiv.add((sek, m.group(1)))
            continue
        # ';Key=Wert' - Beispiel. Das Leerzeichen hinter dem Semikolon
        # trennt Beispiel von Erklaertext, genau wie in EnsureSection.
        if len(s) > 1 and s[0] == ';' and s[1] not in ' \t' and '=' in s:
            m = re.match(r'^;([\w.<>]+)\s*=', s)
            if m:
                beispiel.add((sek, m.group(1)))
    return aktiv, beispiel


def doku_schluessel(pfad, abschnitt=None):
    """Aus den Markdown-Tabellen: '## `[Sektion]`' und '| `Key` | ...'.

    Mit abschnitt nur die Zeilen von dieser Ueberschrift bis zur naechsten
    '## '-Ueberschrift (reDelphix/README.md beschreibt mehr als die ini);
    fehlt die Ueberschrift, ist das ein Lesefehler, kein leerer Abschnitt.
    """
    out = set()
    sek = None
    zeilen = io.open(pfad, encoding='utf-8-sig').read().split(NL)
    if abschnitt is not None:
        kopf = [n for n, z in enumerate(zeilen) if z.rstrip() == abschnitt]
        if not kopf:
            raise ValueError('Abschnitt "%s" fehlt in %s' % (abschnitt, pfad))
        rest = zeilen[kopf[0] + 1:]
        ende = [n for n, z in enumerate(rest) if z.startswith('## ')]
        zeilen = rest[:ende[0]] if ende else rest
    for z in zeilen:
        m = re.match(r'^##+\s+`\[(\w+)\]`', z)
        if m:
            sek = m.group(1)
            continue
        if sek is None:
            continue
        m = re.match(r'^\|\s*`([\w.<>]+)`\s*\|', z)
        if m:
            out.add((sek, m.group(1)))
    return out


def zeig(titel, menge, extra=None):
    if not menge:
        return 0
    print()
    print(titel)
    for sek, key in sorted(menge):
        rest = ''
        if extra and (sek, key) in extra:
            rest = '   (%s)' % ', '.join(sorted(extra[(sek, key)])[:2])
        print('   [%s] %s%s' % (sek, key, rest))
    return len(menge)


def lies_tripel():
    """Je ini (Name, Code, (aktiv, Beispiel), Doku, Ausnahmen)."""
    return (
        ('analyser.ini', code_schluessel(), vorlagen_schluessel(),
         doku_schluessel(DOKU), NUR_ZUSTAND),
        ('redelphix.ini', code_schluessel(RDX_QUELLEN, RDX_LESER, {}),
         vorlagen_schluessel(RDX_VORLAGE, 'RDX_INI_TEMPLATE'),
         doku_schluessel(RDX_DOKU, RDX_ABSCHNITT), frozenset()),
    )


def pruefe(name, code, vorlage_paar, doku, ausnahmen, liste):
    """Die vier Richtungen EINER ini; Rueckgabe: Zahl der Abweichungen."""
    aktiv, beispiel = vorlage_paar
    vorlage = {normiere(k) for k in (aktiv | beispiel)}
    # 'nur als Beispiel': eine ';Key='-Zeile OHNE aktive Zeile daneben. Die
    # Vorlage traegt oft beides ('Language=auto' aktiv, ';Language=de' als
    # Beispiel) - vorher zaehlte die Ausgabe auch diese mit und meldete
    # '56 (davon 56 nur als Beispiel)' (Review Woche 2026-10-21, G10-24).
    beispiel = {normiere(k) for k in beispiel} - {normiere(k) for k in aktiv}
    code_keys = {normiere(k) for k in code} - ausnahmen
    doku = {normiere(k) for k in doku}

    print('== %s ==' % name)
    if liste:
        for titel, m in (('CODE', code_keys), ('VORLAGE', vorlage),
                         ('DOKU', doku)):
            print('%s (%d):' % (titel, len(m)))
            for sek, key in sorted(m):
                print('   [%s] %s' % (sek, key))
            print()
        return 0

    fehler = 0
    # Der schlimmste Fall zuerst: dokumentiert, aber tot.
    fehler += zeig('DOKUMENTIERT, ABER VOM CODE NIE GELESEN '
                   '(der Nutzer stellt etwas ein, das nichts tut):',
                   doku - code_keys)
    fehler += zeig('IN DER VORLAGE, ABER VOM CODE NIE GELESEN:',
                   vorlage - code_keys)
    fehler += zeig('VOM CODE GELESEN, ABER NICHT DOKUMENTIERT:',
                   code_keys - doku, code)
    fehler += zeig('VOM CODE GELESEN, ABER NICHT IN DER VORLAGE:',
                   code_keys - vorlage, code)

    print()
    print('Code %d   Vorlage %d (davon %d nur als Beispiel)   Doku %d'
          % (len(code_keys), len(vorlage), len(beispiel), len(doku)))
    if ausnahmen:
        print('Ausgenommen als reiner Sitzungszustand: %s'
              % ', '.join('[%s] %s' % k for k in sorted(ausnahmen)))
    print()
    return fehler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--list', action='store_true',
                    help='alle Schluessel je Quelle zeigen')
    args = ap.parse_args()

    try:
        tripel = lies_tripel()
    except (OSError, ValueError) as e:
        print('Lesefehler: %s' % e, file=sys.stderr)
        return 2

    fehler = 0
    for name, code, vorlage_paar, doku, ausnahmen in tripel:
        fehler += pruefe(name, code, vorlage_paar, doku, ausnahmen,
                         args.list)
    if args.list:
        return 0
    if fehler:
        print('ABWEICHUNGEN: %d.' % fehler)
        print('Der Code ist die Wahrheit. Was er nicht liest, gehoert '
              'nicht in Vorlage oder Doku; was er liest, gehoert in beide.')
        return 1
    print('GATE GRUEN: Code, INI-Vorlage und Doku nennen dieselben '
          'Schluessel (analyser.ini und redelphix.ini).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
