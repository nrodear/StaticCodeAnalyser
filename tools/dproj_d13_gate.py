# -*- coding: utf-8 -*-
"""Gate gegen Auseinanderlaufen der D12- und D13-Projektsaetze.

WOZU: Fuer Delphi 13 gibt es einen zweiten Satz Projektdateien
(*.d13.dproj + StaticCodeAnalyser.d13.groupproj). Zwei Saetze heissen
zwei Stellen, an denen jemand etwas nachziehen muss - und genau das
vergisst man. Der Einwand bei der Anlage war deshalb berechtigt.

Entschaerft ist er dadurch, dass beide Saetze DIESELBE .dpk/.dpr
benutzen (<MainSource>). Die Unit-Listen koennen damit gar nicht
auseinanderlaufen. Was auseinanderlaufen KANN, sind die Einstellungen
der .dproj - Suchpfade, Defines, benutzte Packages. Das prueft dieses
Gate.

Geprueft wird:
  1  Jedes D12-Projekt hat ein D13-Gegenstueck und umgekehrt.
  2  Beide zeigen mit <MainSource> auf dieselbe Quelldatei
     (kein zweiter, driftender Unit-Bestand).
  3  Die compilerrelevanten Einstellungen sind gleich
     (Suchpfad, Defines, Namespaces, benutzte Packages).
  4  Kein Ausgabepfad wird von beiden Saetzen benutzt
     (sonst ueberschreiben sich DCU/DCP/EXE - in diesem Repo eine
     bekannte Fehlerklasse, siehe F2613).
  5  Alle ProjectGuids sind repoweit eindeutig.
  6  Jedes D13-Projekt steht in der D13-Gruppe.

Abweichungen, die ABSICHT sind, stehen in ALLOWED - mit Begruendung.

    python tools/dproj_d13_gate.py

EXIT  0 gruen | 1 Befunde | 2 Aufruffehler
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
GROUP13 = 'StaticCodeAnalyser.d13.groupproj'
BS = chr(92)

# Einstellungen, deren Gleichheit den Bau bestimmt.
COMPILE_KEYS = ('DCC_UnitSearchPath', 'DCC_Define', 'DCC_Namespace',
                'DCC_UsePackage', 'DCC_ResourcePath', 'DCC_ObjPath',
                'DCC_IncludePath')

# Bewusste Unterschiede. Ohne Begruendung kommt hier nichts rein.
ALLOWED = {
    'ProjectVersion':
        'D12 schreibt 20.1, D13 schreibt 20.3 - die jeweilige IDE dreht '
        'den Wert beim Oeffnen ohnehin zurueck.',
    'TargetedPlatforms':
        'D13 baut die IDE-Pakete auch als Win64, weil die 64-Bit-IDE '
        'eine Win64-BPL laden muss.',
    'ProjectGuid':
        'muss unterschiedlich sein - gleiche GUID in zwei Projekten '
        'verwirrt die IDE und den Gruppen-Build.',
}


def read(path):
    return io.open(os.path.join(REPO, path), encoding='utf-8-sig').read()


def all_dprojs():
    found = []
    for base, _dirs, files in os.walk(REPO):
        skip = (BS + '.git', BS + '__history', BS + 'output',
                BS + 'win32', BS + 'win64')
        if any(p in base.lower() for p in skip):
            continue
        for f in files:
            if f.lower().endswith('.dproj'):
                found.append(os.path.relpath(os.path.join(base, f), REPO))
    return sorted(found)


def d12_name_of(d13_rel):
    """Pfad des D12-Gegenstuecks zu einem *.d13.dproj."""
    head = d13_rel[:-len('.d13.dproj')]
    for cand in (head + '.dproj', head + '.d12.dproj'):
        if os.path.isfile(os.path.join(REPO, cand)):
            return cand
    return None


def values(text, tag):
    return re.findall(r'<%s>([^<]*)</%s>' % (tag, tag), text)


PGROUP = re.compile(r'<PropertyGroup(?:\s+Condition="([^"]*)")?\s*>(.*?)'
                    r'</PropertyGroup>', re.S)


def blocks(text):
    """{Bedingung: {Schluessel: Wert}} - Vergleichseinheit ist der Block.

    Die D13-Projekte haben Bloecke, die es in D12 nicht gibt (Win64). Wer
    ueber die ganze Datei vergleicht, meldet genau die als Drift - also
    das, was Absicht ist. Verglichen werden deshalb nur Bedingungen, die in
    BEIDEN Dateien vorkommen.
    """
    res = {}
    for cond, body in PGROUP.findall(text):
        d = res.setdefault(cond or '(ohne)', {})
        for key in COMPILE_KEYS:
            for v in re.findall(r'<%s>([^<]*)</%s>' % (key, key), body):
                d[key] = v
    return res


def outputs(text):
    return set(re.findall(r'<DCC_(?:Exe|Dcu|Dcp|Bpl)Output>([^<]*)<', text))


def main():
    out = []
    dprojs = all_dprojs()
    d13 = [p for p in dprojs if p.lower().endswith('.d13.dproj')]
    d12 = [p for p in dprojs if not p.lower().endswith('.d13.dproj')]

    if not d13:
        print('Kein D13-Projektsatz vorhanden - nichts zu pruefen.')
        return 0

    # 1 Paarigkeit
    paired = {}
    for p in d13:
        partner = d12_name_of(p)
        if partner is None:
            out.append('%s hat kein D12-Gegenstueck.' % p)
        else:
            paired[p] = partner
    for p in d12:
        head = p[:-len('.dproj')]
        head = head[:-4] if head.endswith('.d12') else head
        if not os.path.isfile(os.path.join(REPO, head + '.d13.dproj')):
            out.append('%s hat kein D13-Gegenstueck - beim Anlegen eines '
                       'neuen Projekts BEIDE Saetze pflegen.' % p)

    for p13, p12 in sorted(paired.items()):
        t13, t12 = read(p13), read(p12)

        # 2 gemeinsame Quelldatei
        m13, m12 = values(t13, 'MainSource'), values(t12, 'MainSource')
        if m13[:1] != m12[:1]:
            out.append('%s und %s zeigen auf verschiedene Quelldateien '
                       '(%s vs %s) - damit gibt es zwei Unit-Bestaende, die '
                       'auseinanderlaufen koennen.'
                       % (p13, p12, m13[:1], m12[:1]))

        # 3 Compilereinstellungen - pro Bedingungsblock
        b13, b12 = blocks(t13), blocks(t12)
        for cond in sorted(set(b13) & set(b12)):
            for key in COMPILE_KEYS:
                v13, v12 = b13[cond].get(key), b12[cond].get(key)
                if v13 != v12:
                    out.append('%s, Block %s:\n        <%s>'
                               '\n        D12: %s\n        D13: %s'
                               % (p13, cond or '(ohne)', key,
                                  v12 or '-', v13 or '-'))

        # 4 Ausgabepfade
        shared = outputs(t13) & outputs(t12)
        if shared:
            out.append('%s teilt Ausgabepfade mit %s: %s - D12- und '
                       'D13-Artefakte wuerden sich ueberschreiben.'
                       % (p13, p12, ', '.join(sorted(shared))))

    # 5 GUID-Eindeutigkeit (dproj + groupproj)
    seen = {}
    files = dprojs + [f for f in os.listdir(REPO)
                      if f.lower().endswith('.groupproj')]
    for f in files:
        for g in values(read(f), 'ProjectGuid'):
            if g in seen:
                out.append('ProjectGuid %s steht in %s UND in %s.'
                           % (g, seen[g], f))
            else:
                seen[g] = f

    # 6 Gruppenmitgliedschaft
    if os.path.isfile(os.path.join(REPO, GROUP13)):
        g = read(GROUP13)
        listed = set(re.findall(r'<Projects Include="([^"]+)"', g))
        listed = {p.replace(BS, os.sep) for p in listed}
        for p in d13:
            if p not in listed:
                out.append('%s fehlt in %s.' % (p, GROUP13))
        for p in sorted(listed):
            if not os.path.isfile(os.path.join(REPO, p)):
                out.append('%s nennt %s - die Datei gibt es nicht.'
                           % (GROUP13, p))
    else:
        out.append('%s fehlt.' % GROUP13)

    print('Geprueft: %d D13-Projekte, %d Paare.' % (len(d13), len(paired)))
    if not out:
        print('GATE GRUEN: D12- und D13-Projektsatz sind deckungsgleich.')
        print('Bewusste Unterschiede (nicht geprueft): %s'
              % ', '.join(sorted(ALLOWED)))
        return 0
    print()
    for o in out:
        print('  * %s' % o)
    print('\nGATE ROT: %d Befund(e).' % len(out))
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:      # noqa: BLE001 - ein Gate darf nie haengen
        print('Gate-Fehler: %s' % exc)
        sys.exit(2)
