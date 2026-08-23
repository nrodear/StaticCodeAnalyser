# -*- coding: utf-8 -*-
"""Gate fuer den D13-Projektsatz.

WOZU: Fuer Delphi 13 gibt es einen zweiten Satz Projektdateien
(*.d13.dproj + StaticCodeAnalyser.d13.groupproj). Zwei Saetze heissen
zwei Stellen, an denen jemand etwas nachziehen muss.

Entschaerft ist das dadurch, dass beide Saetze DIESELBE .dpk/.dpr
benutzen (<MainSource>) - die Unit-Listen koennen gar nicht
auseinanderlaufen. Was auseinanderlaufen KANN, sind die Einstellungen
der .dproj. Und der zweite Anlauf traegt Eigenschaften, die er nicht
wieder verlieren darf; jede davon steht fuer einen Fehler, der schon
einmal Zeit gekostet hat.

Geprueft wird:

  1  Paarigkeit D12 <-> D13.
  2  Beide zeigen mit <MainSource> auf dieselbe Quelldatei.
  3  Compilereinstellungen je Bedingungsblock gleich (ohne die bewusst
     abweichenden Ausgabe- und Suchpfade).
  4  Kein Ausgabepfad wird von beiden Saetzen benutzt.
  5  ProjectGuids repoweit eindeutig.
  6  Jedes D13-Projekt steht in der Gruppe.
  7  Bauordnung: was der Compiler als DCP zieht, steht unter
     <Dependencies> - UND die ItemGroup-Reihenfolge ist topologisch
     korrekt. Letzteres ist das eigentlich Wirksame: das Build-Target in
     CodeGear.Group.Targets baut mit Projects="@(Projects)", also in
     ItemGroup-Reihenfolge, nicht mit der aus <Dependencies>
     aufgeloesten Liste (gemessen 2026-08-22).
  8  Unterscheidbare <ProjectName> (…d13). Ohne das sind die Knoten im
     Project Manager nicht auseinanderzuhalten - der Hauptgrund, warum
     der erste Anlauf fuenfmal die falsche Datei gebaut hat.
  9  Jedes D13-Package traegt <DllSuffix>$(Auto)</DllSuffix>, und KEIN
     D12-Projekt traegt einen DllSuffix. Der Suffix ist eine Eigenschaft
     des Projekts, nicht des Pakets - deshalb bleibt D12 unberuehrt.
 10  Jedes D13-Projekt leitet seine Ausgabe ueber $(SCAOut) ab und
     definiert $(SCAGen)/$(SCARoot)/$(SCAOut) selbst.
 11  Jeder Konsument fremder DCPs hat die dcp-Zelle im
     DCC_UnitSearchPath. Ohne das findet er die Schwesterpakete nicht,
     sobald das DCP nicht mehr in $(BDSCOMMONDIR)\\Dcp liegt.

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
DCP_ZELLE = '$(SCAOut)' + BS + 'dcp'

# Einstellungen, deren Gleichheit den Bau bestimmt. Ausgabe- und
# Suchpfade fehlen bewusst: die weichen ab, das ist der Zweck des Umbaus.
COMPILE_KEYS = ('DCC_Define', 'DCC_Namespace', 'DCC_UsePackage',
                'DCC_ResourcePath', 'DCC_ObjPath', 'DCC_IncludePath')

ALLOWED = {
    'ProjectVersion': 'D12 schreibt 20.1, D13 schreibt 20.3.',
    'ProjectGuid': 'muss unterschiedlich sein.',
    'ProjectName': 'muss unterschiedlich sein - siehe Pruefung 8.',
    'TargetedPlatforms': 'D13 baut die Pakete auch als Win64.',
    'Ausgabepfade': 'D13 legt nach lib/<gen>/<plat>/<config> ab.',
}

PGROUP = re.compile(r'<PropertyGroup(?:\s+Condition="([^"]*)")?\s*>(.*?)'
                    r'</PropertyGroup>', re.S)


def read(path):
    return io.open(os.path.join(REPO, path), encoding='utf-8-sig').read()


def values(text, tag):
    return re.findall(r'<%s[^>]*>([^<]*)</%s>' % (tag, tag), text)


def all_dprojs():
    found = []
    skip = (BS + '.git', BS + '__history', BS + 'output', BS + 'lib',
            BS + 'win32', BS + 'win64')
    for base, _dirs, files in os.walk(REPO):
        if any(p in base.lower() for p in skip):
            continue
        for f in files:
            if f.lower().endswith('.dproj'):
                found.append(os.path.relpath(os.path.join(base, f), REPO))
    return sorted(found)


def d12_of(d13_rel):
    head = d13_rel[:-len('.d13.dproj')]
    for cand in (head + '.dproj', head + '.d12.dproj'):
        if os.path.isfile(os.path.join(REPO, cand)):
            return cand
    return None


def blocks(text):
    """{Bedingung: {Schluessel: Wert}} - verglichen wird pro Block.

    Ueber die ganze Datei zu vergleichen meldet jeden NEUEN Win64-Block
    als Drift - also genau das, was Absicht ist.
    """
    res = {}
    for cond, body in PGROUP.findall(text):
        d = res.setdefault(cond or '(ohne)', {})
        for key in COMPILE_KEYS:
            for v in re.findall(r'<%s>([^<]*)</%s>' % (key, key), body):
                d[key] = v
    return res


def outputs(text):
    return set(re.findall(r'<DCC_(?:Exe|Dcu|Dcp|Bpl|Hpp)Output>([^<]*)<',
                          text))


def ist_package(text):
    return 'Package' in values(text, 'AppType')


def declared_deps(group_text, proj):
    m = re.search(r'<Projects Include="%s">\s*<Dependencies(?:\s*/>|>(.*?)'
                  r'</Dependencies>)'
                  % re.escape(proj.replace(os.sep, BS)), group_text, re.S)
    if not m or not m.group(1):
        return set()
    return {d.strip().replace(BS, os.sep)
            for d in m.group(1).split(';') if d.strip()}


def needed_deps(proj, text, by_name):
    """Schwesterprojekte, deren DCP dieses Projekt zieht.

    Quelle: requires der .dpk bzw. DCC_UsePackage bei UsePackages=true.
    """
    need, words = set(), set()
    main = values(text, 'MainSource')
    src = os.path.join(os.path.dirname(proj), main[0]) if main else None
    if src and os.path.isfile(os.path.join(REPO, src)):
        m = re.search(r'^requires(.*?);', read(src), re.S | re.M | re.I)
        if m:
            words |= {w.strip() for w in re.split(r'[,\s]+', m.group(1))}
    if 'true' in [v.lower() for v in values(text, 'UsePackages')]:
        for v in values(text, 'DCC_UsePackage'):
            words |= {w.strip() for w in v.split(';')}
    for w in words:
        if w in by_name and by_name[w] != proj:
            need.add(by_name[w])
    return need


def group_order(group_text):
    return [p.replace(BS, os.sep)
            for p in re.findall(r'<Projects Include="([^"]+)"', group_text)]


def main():
    out = []
    dprojs = all_dprojs()
    d13 = [p for p in dprojs if p.lower().endswith('.d13.dproj')]
    d12 = [p for p in dprojs if not p.lower().endswith('.d13.dproj')]

    if not d13:
        print('Kein D13-Projektsatz vorhanden - nichts zu pruefen.')
        return 0

    paired = {}
    for p in d13:
        partner = d12_of(p)
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

        m13, m12 = values(t13, 'MainSource'), values(t12, 'MainSource')
        if m13[:1] != m12[:1]:
            out.append('%s und %s zeigen auf verschiedene Quelldateien '
                       '(%s vs %s) - zwei Unit-Bestaende koennen '
                       'auseinanderlaufen.' % (p13, p12, m13[:1], m12[:1]))

        b13, b12 = blocks(t13), blocks(t12)
        for cond in sorted(set(b13) & set(b12)):
            for key in COMPILE_KEYS:
                v13, v12 = b13[cond].get(key), b12[cond].get(key)
                if v13 != v12:
                    out.append('%s, Block %s:%s        <%s>%s        D12: %s'
                               '%s        D13: %s'
                               % (p13, cond or '(ohne)', chr(10), key, chr(10),
                                  v12 or '-', chr(10), v13 or '-'))

        shared = outputs(t13) & outputs(t12)
        if shared:
            out.append('%s teilt Ausgabepfade mit %s: %s'
                       % (p13, p12, ', '.join(sorted(shared))))

        # 8 unterscheidbare Namen
        n13 = values(t13, 'ProjectName')
        n12 = values(t12, 'ProjectName')
        if n13 and n12 and n13[0] == n12[0]:
            out.append('%s traegt denselben <ProjectName> "%s" wie %s - im '
                       'Project Manager sind beide dann nicht '
                       'auseinanderzuhalten.' % (p13, n13[0], p12))
        elif n13 and not n13[0].endswith('.d13'):
            out.append('%s: <ProjectName> "%s" endet nicht auf ".d13".'
                       % (p13, n13[0]))

        # 9 DllSuffix
        if ist_package(t13):
            if '$(Auto)' not in ''.join(values(t13, 'DllSuffix')):
                out.append('%s ist ein Package ohne '
                           '<DllSuffix>$(Auto)</DllSuffix> - die BPL hiesse '
                           'dann wie die von D12.' % p13)
        if values(t12, 'DllSuffix'):
            out.append('%s traegt einen DllSuffix. D12 soll unveraendert '
                       'ohne Suffix bauen - sonst zieht eine Migration von '
                       'Installer, Registry und Entwicklerinstallation '
                       'nach.' % p12)

        # 10 zentrale Ablage
        # 10b Die Tiefe von $(SCARoot) muss zum Ablageort passen.
        #     Ein relativer Pfad ist noetig, weil die Delphi-IDE
        #     $(MSBuildThisFileDirectory) NICHT setzt - dort bricht
        #     [MSBuild]::GetDirectoryNameOfFileAbove mit leerem Pfad ab.
        #     Auf der Kommandozeile funktioniert die Funktion; gemessen
        #     wurde zuerst nur dort, also im falschen Wirt (2026-08-23).
        root = values(t13, 'SCARoot')
        if root:
            tiefe = p13.replace(os.sep, '/').count('/')
            soll = BS.join(['..'] * tiefe) if tiefe else '.'
            if root[0] != soll:
                out.append('%s: <SCARoot> ist "%s", bei dieser Tiefe '
                           'muss es "%s" sein - sonst landet die Ausgabe '
                           'neben dem Repo statt darin.'
                           % (p13, root[0], soll))

        for tag in ('SCAGen', 'SCARoot', 'SCAOut'):
            if not values(t13, tag):
                out.append('%s definiert $(%s) nicht.' % (p13, tag))
        for tag in ('DCC_DcuOutput', 'DCC_ExeOutput'):
            v = values(t13, tag)
            if v and '$(SCAOut)' not in v[0]:
                out.append('%s: <%s> = "%s" liegt nicht in der Zelle '
                           '$(SCAOut).' % (p13, tag, v[0]))
        if ist_package(t13) and not values(t13, 'DCC_DcpOutput'):
            out.append('%s ist ein Package ohne <DCC_DcpOutput> - das DCP '
                       'landet dann in der Studio-Installation statt in '
                       'der Zelle.' % p13)

    # 5 GUIDs
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

    # 6/7/11 Gruppe
    if os.path.isfile(os.path.join(REPO, GROUP13)):
        g = read(GROUP13)
        listed = group_order(g)
        for p in d13:
            if p not in listed:
                out.append('%s fehlt in %s.' % (p, GROUP13))
        for p in listed:
            if not os.path.isfile(os.path.join(REPO, p)):
                out.append('%s nennt %s - die Datei gibt es nicht.'
                           % (GROUP13, p))

        by_name = {}
        for q in d13:
            n = re.findall(r'<ProjectName[^>]*>([^<]+)</ProjectName>', read(q))
            if n:
                # In requires/DCC_UsePackage steht der PAKETNAME ohne .d13.
                by_name[n[0][:-4] if n[0].endswith('.d13') else n[0]] = q
        for q in sorted(d13):
            t = read(q)
            need = needed_deps(q, t, by_name)
            for miss in sorted(need - declared_deps(g, q)):
                out.append('%s braucht %s, aber %s nennt es nicht unter '
                           '<Dependencies>.' % (q, miss, GROUP13))
            # 7b ItemGroup-Reihenfolge
            if q in listed:
                for dep in need:
                    if dep in listed and listed.index(dep) > listed.index(q):
                        out.append('%s steht in %s VOR seiner Vorbedingung '
                                   '%s. Im msbuild-Weg zaehlt genau diese '
                                   'Reihenfolge.' % (q, GROUP13, dep))
            # 11 dcp-Zelle im Suchpfad
            if need:
                sp = ''.join(values(t, 'DCC_UnitSearchPath'))
                if DCP_ZELLE not in sp:
                    out.append('%s zieht fremde DCPs, hat aber "%s" nicht '
                               'im DCC_UnitSearchPath - es findet die '
                               'Schwesterpakete dann nicht.'
                               % (q, DCP_ZELLE))
    else:
        out.append('%s fehlt.' % GROUP13)

    print('Geprueft: %d D13-Projekte, %d Paare.' % (len(d13), len(paired)))
    if not out:
        print('GATE GRUEN: D12- und D13-Projektsatz sind stimmig.')
        print('Bewusste Unterschiede: %s' % ', '.join(sorted(ALLOWED)))
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
