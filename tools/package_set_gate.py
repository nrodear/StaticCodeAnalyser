# -*- coding: utf-8 -*-
"""Gate: der ausgelieferte Paketsatz ist in sich stimmig.

WOZU: Seit 0.9.19 geht das IDE-Plugin als Paketsatz raus, nicht mehr als
Monolith: SCA.Engine + SCA.SharedUI (Laufzeit) und
StaticCodeAnalyser.IDE.d12 + reDelphix.d12 (Entwurfszeit), auf drei
Schienen (D12 Win32, D13 Win32, D13 Win64). Release == Dev.

Dieser Satz hat Vertraege, die kein Compilerlauf prueft. Jeder Bruch hier
faellt sonst erst beim Kunden oder beim Handtest auf:

  (1) Eine Unit in zwei Paketen: die IDE weigert sich zu laden ("enthaelt
      die Unit ..., die auch im Package ... enthalten ist"). Eine Unit in
      keinem Paket: der Compiler zieht sie still in das erste Paket, das
      sie benutzt, und der Fehler (1) kommt beim naechsten Paket.
  (2) reDelphix darf nur an der Engine haengen. Haengt es an SharedUI oder
      am IDE-Paket, ist es nicht mehr abwaehlbar (E5) bzw. das Setup
      liefert ein Paket ohne seine Abhaengigkeit. designide in einem
      Laufzeitpaket verhindert jeden Win64-Bau.
  (3) .dpk und .dproj muessen denselben Pakettyp nennen: massgeblich ist
      die .dpk, die .dproj steuert, was die IDE anbietet.
  (4) LIBSUFFIX nur an RUNONLY: die Laufzeitpakete werden ueber den PATH
      gefunden und muessen je Generation anders heissen. Die Design-Pakete
      stehen mit vollem Pfad in den Known Packages; ein Suffix daran bricht
      Installer und Release-Skript.
  (5) Alle vier Pakete zielen auf Win32 und Win64, und die Design-Pakete
      tragen die Sperre gegen Win64 unter Delphi 12 (dort gibt es kein
      designide; ohne Sperre endet der Bau in einem E2202 ohne Plattform).
  (6) VerInfo Win32 == Win64 == Release-Version, Keys UND Zahlenfelder.
      R8 aus dem Konzept: die Engine-Win64-BPL hatte gar keine VERSIONINFO,
      und die Zahlenfelder standen ein Release hinter dem Keys-String.
      Dazu tool.version im Regelkatalog: das Feld steht in den Kopfzeilen
      der HTML-Workbench und stand fuenf Releases auf 0.9.14.

Kommentare zaehlen nicht: die .dpk-Koepfe erwaehnen {$RUNONLY}, LIBSUFFIX
und designide im Fliesstext. Geprueft wird nur, was der Compiler sieht.

    python tools/package_set_gate.py
    python tools/package_set_gate.py --version 0.9.19
    python tools/package_set_gate.py --version 0.9.19.1   (vierteilig)
    python tools/package_set_gate.py --repo <Kopie>     (Mutantenproben)

Ohne --version gilt uSCAConsts.SCA_VERSION als Release-Version.

EXIT  0 stimmig | 1 Abweichung | 2 Aufruffehler
"""
import io
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

RUN = 'RUNONLY'
DESIGN = 'DESIGNONLY'

# Name, Pfad ohne Endung, Pakettyp, Quellordner, SCA-Pakete in requires.
PAKETE = (
    ('SCA.Engine', 'SCA.Engine/SCA.Engine', RUN,
     'SCA.Engine/sources', ()),
    ('SCA.SharedUI', 'SCA.SharedUI/SCA.SharedUI', RUN,
     'SCA.SharedUI/sources', ('SCA.Engine',)),
    ('StaticCodeAnalyser.IDE.d12',
     'StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12', DESIGN,
     'StaticCodeAnalyserIDE', ('SCA.Engine', 'SCA.SharedUI')),
    ('reDelphix.d12', 'reDelphix/reDelphix.d12', DESIGN,
     'reDelphix/source', ('SCA.Engine',)),
)

# Alles, was nach eigenem Paket aussieht, zaehlt im requires-Graphen. So
# faellt auch eine Abhaengigkeit auf den Monolithen auf.
EIGENE_PRAEFIXE = ('sca.', 'staticcodeanalyser', 'redelphix')

CONSTS = 'SCA.Engine/sources/Common/uSCAConsts.pas'
KATALOG = 'rules/sca-rules.json'


def abbruch(meldung):
    print(meldung)
    sys.exit(2)


def lies(repo, rel):
    return io.open(os.path.join(repo, rel), encoding='utf-8-sig').read()


def zerlege_pascal(text):
    """Trennt Pascal-Quelltext in Code und Compilerdirektiven.

    Liefert (code, direktiven). code ist der Text ohne Kommentare, Strings
    bleiben stehen. direktiven ist die Liste [(NAME, rest, tiefe)] in
    Textreihenfolge; tiefe zaehlt die umschliessenden {$IF...}.

    Bewusst kein Regex: { } schachtelt nicht, und ein // vor {$RUNONLY}
    macht daraus einen Kommentar. Beides muss hier stimmen, sonst bleibt
    eine auskommentierte Sperre gruen.
    """
    code, direktiven = [], []
    tiefe, i, n = 0, 0, len(text)

    def direktive(roh):
        nonlocal tiefe
        m = re.match(r'\s*([A-Za-z]+)(.*)', roh, re.S)
        if not m:
            return
        name, rest = m.group(1).upper(), m.group(2).strip()
        if name in ('ENDIF', 'IFEND'):
            tiefe = max(0, tiefe - 1)
        direktiven.append((name, rest, tiefe))
        if name in ('IF', 'IFDEF', 'IFNDEF', 'IFOPT'):
            tiefe += 1

    while i < n:
        c = text[i]
        if c == "'":
            ende = text.find("'", i + 1)
            ende = n - 1 if ende < 0 else ende
            code.append(text[i:ende + 1])
            i = ende + 1
        elif text.startswith('//', i):
            ende = text.find('\n', i)
            i = n if ende < 0 else ende
        elif c == '{':
            ende = text.find('}', i)
            ende = n if ende < 0 else ende
            if text.startswith('{$', i):
                direktive(text[i + 2:ende])
            code.append(' ')
            i = ende + 1
        elif text.startswith('(*', i):
            ende = text.find('*)', i)
            ende = n if ende < 0 else ende
            if text.startswith('(*$', i):
                direktive(text[i + 3:ende])
            code.append(' ')
            i = ende + 2
        else:
            code.append(c)
            i += 1
    return ''.join(code), direktiven


def klausel(code, wort):
    """Eintraege einer requires-/contains-Klausel als Liste, sonst None."""
    m = re.search(r'\b%s\b(.*?);' % wort, code, re.S | re.I)
    if not m:
        return None
    return [e.strip() for e in m.group(1).split(',') if e.strip()]


def contains_units(code):
    """[(Unit, Quellpfad)] aus der contains-Klausel."""
    out = []
    for eintrag in klausel(code, 'contains') or []:
        m = re.match(r"([A-Za-z_][\w.]*)(?:\s+in\s+'([^']*)')?$", eintrag,
                     re.S)
        out.append((m.group(1), m.group(2)) if m else (eintrag, None))
    return out


def dproj_ohne_kommentare(text):
    return re.sub(r'<!--.*?-->', '', text, flags=re.S)


def gruppe(dproj, bedingung):
    """Inhalt der PropertyGroup mit Condition="'$(<bedingung>)'!=''"."""
    m = re.search(r"""<PropertyGroup Condition="'\$\(%s\)'!=''">(.*?)"""
                  r"""</PropertyGroup>""" % re.escape(bedingung), dproj, re.S)
    return m.group(1) if m else None


def tag_wert(block, tag):
    m = re.search(r'<%s>([^<]*)</%s>' % (tag, tag), block)
    return m.group(1).strip() if m else None


def pruefe_units(repo, geparst, befunde):
    """(1) Jede Unit in genau einem der vier contains."""
    besitzer = {}
    for name, _b, _t, _q, _r in PAKETE:
        for unit, _pfad in geparst[name]['units']:
            besitzer.setdefault(unit.lower(), []).append((name, unit))
    for treffer in sorted(besitzer.values(), key=lambda v: v[0][1].lower()):
        if len(treffer) > 1:
            befunde.append((1, '%s steht %d-mal im Paketsatz: %s'
                            % (treffer[0][1], len(treffer),
                               ', '.join(n for n, _u in treffer))))
    for name, basis, _t, quellen, _r in PAKETE:
        wurzel = os.path.join(repo, quellen)
        if not os.path.isdir(wurzel):
            befunde.append((1, '%s: Quellordner %s fehlt' % (name, quellen)))
            continue
        for ordner, _d, dateien in os.walk(wurzel):
            for f in dateien:
                stamm, endung = os.path.splitext(f)
                if endung.lower() == '.pas' and stamm.lower() not in besitzer:
                    rel = os.path.relpath(os.path.join(ordner, f), repo)
                    befunde.append((1, '%s liegt im Quellordner von %s, steht '
                                    'aber in keinem contains'
                                    % (rel.replace(os.sep, '/'), name)))
        dpk_ordner = os.path.dirname(os.path.join(repo, basis))
        for unit, pfad in geparst[name]['units']:
            if pfad is None:
                befunde.append((1, "%s: Eintrag '%s' ohne in-Pfad"
                                % (name, unit)))
            elif not os.path.isfile(os.path.join(
                    dpk_ordner, pfad.replace(chr(92), os.sep))):
                befunde.append((1, '%s: %s zeigt auf fehlende Datei %s'
                                % (name, unit, pfad)))


def pruefe_requires(geparst, befunde):
    """(2) requires-Graph und designide."""
    for name, _b, typ, _q, soll in PAKETE:
        requires = geparst[name]['requires']
        eigene = {r.lower() for r in requires
                  if r.lower().startswith(EIGENE_PRAEFIXE)}
        erwartet = {s.lower() for s in soll}
        for r in sorted(eigene - erwartet):
            befunde.append((2, '%s requires %s, erlaubt ist nur: %s'
                            % (name, r, ', '.join(soll) or '(kein SCA-Paket)')))
        for r in sorted(erwartet - eigene):
            befunde.append((2, '%s fehlt requires %s' % (name, r)))
        hat_designide = any(r.lower() == 'designide' for r in requires)
        if hat_designide and typ == RUN:
            befunde.append((2, '%s ist Laufzeitpaket und requires designide '
                            '- kein Win64-Bau moeglich' % name))
        if not hat_designide and typ == DESIGN:
            befunde.append((2, '%s ist Design-Paket ohne requires designide'
                            % name))


def pruefe_typ(geparst, befunde):
    """(3) Pakettyp in .dpk und .dproj gepaart."""
    for name, _b, typ, _q, _r in PAKETE:
        p = geparst[name]
        wirksam = {d[0] for d in p['direktiven']
                   if d[0] in (RUN, DESIGN) and d[2] == 0}
        if wirksam != {typ}:
            befunde.append((3, '%s: .dpk soll genau {$%s} tragen (unbedingt), '
                            'gefunden: %s'
                            % (name, typ, ', '.join(sorted(wirksam)) or '-')))
        run = tag_wert(p['dproj'], 'RuntimeOnlyPackage')
        design = tag_wert(p['dproj'], 'DesignOnlyPackage')
        ist_run, ist_design = (run or '').lower() == 'true', \
            (design or '').lower() == 'true'
        if (ist_run, ist_design) != (typ == RUN, typ == DESIGN):
            befunde.append((3, '%s: .dproj passt nicht zu {$%s} '
                            '(RuntimeOnlyPackage=%s, DesignOnlyPackage=%s)'
                            % (name, typ, run, design)))


def pruefe_suffix(geparst, befunde):
    """(4) LIBSUFFIX nur an RUNONLY-Paketen (E10: AUTO)."""
    for name, _b, typ, _q, _r in PAKETE:
        p = geparst[name]
        suffixe = [d for d in p['direktiven'] if d[0] == 'LIBSUFFIX']
        dll = tag_wert(p['dproj'], 'DllSuffix')
        if typ == RUN:
            if len(suffixe) != 1 or suffixe[0][1].upper() != 'AUTO' \
                    or suffixe[0][2] != 0:
                befunde.append((4, '%s: Laufzeitpaket braucht genau einmal '
                                '{$LIBSUFFIX AUTO} (unbedingt)' % name))
            if dll != '$(Auto)':
                befunde.append((4, '%s: .dproj braucht <DllSuffix>$(Auto), '
                                'gefunden: %s' % (name, dll)))
        else:
            if suffixe:
                befunde.append((4, '%s: Design-Paket darf kein {$LIBSUFFIX} '
                                'tragen' % name))
            if dll is not None:
                befunde.append((4, '%s: Design-Paket darf kein <DllSuffix> '
                                'tragen' % name))


def hat_sperre(direktiven):
    """{$IF WIN64 und VER360} direkt gefolgt von {$MESSAGE FATAL}."""
    for i, (name, rest, _t) in enumerate(direktiven[:-1]):
        bed = re.sub(r'\s+', '', rest).upper()
        if name == 'IF' and 'DEFINED(WIN64)' in bed \
                and 'DEFINED(VER360)' in bed and 'NOT' not in bed:
            folge = direktiven[i + 1]
            if folge[0] == 'MESSAGE' and folge[1].upper().startswith('FATAL'):
                return True
    return False


def pruefe_plattformen(geparst, befunde):
    """(5) Win32+Win64 in allen vieren, Sperre in beiden Design-.dpk."""
    for name, _b, typ, _q, _r in PAKETE:
        p = geparst[name]
        tp = tag_wert(p['dproj'], 'TargetedPlatforms')
        if tp != '3':
            befunde.append((5, '%s: TargetedPlatforms=%s, Soll 3' % (name, tp)))
        for plat in ('Win32', 'Win64'):
            m = re.search(r'<Platform value="%s">(\w+)</Platform>' % plat,
                          p['dproj'])
            if not (m and m.group(1).lower() == 'true'):
                befunde.append((5, '%s: Platform %s ist nicht True'
                                % (name, plat)))
        if typ == DESIGN and not hat_sperre(p['direktiven']):
            befunde.append((5, '%s: .dpk ohne Sperre {$IF Defined(WIN64) and '
                            'Defined(VER360)} + {$MESSAGE FATAL}' % name))


def pruefe_verinfo(geparst, soll, release, befunde):
    """(6) VerInfo Win32 == Win64 == Release-Version."""
    teile = soll.split('.')
    for name, _b, _t, _q, _r in PAKETE:
        d = geparst[name]['dproj']
        for bed in ('Base_Win32', 'Base_Win64'):
            block = gruppe(d, bed)
            if block is None:
                befunde.append((6, '%s: PropertyGroup %s fehlt' % (name, bed)))
                continue
            if tag_wert(block, 'VerInfo_IncludeVerInfo') != 'true':
                befunde.append((6, '%s %s: VerInfo_IncludeVerInfo nicht true'
                                % (name, bed)))
            for tag, wert in zip(('MajorVer', 'MinorVer', 'Release', 'Build'),
                                 teile):
                ist = tag_wert(block, 'VerInfo_' + tag)
                if ist != wert:
                    befunde.append((6, '%s %s: VerInfo_%s=%s, Soll %s'
                                    % (name, bed, tag, ist, wert)))
            keys = tag_wert(block, 'VerInfo_Keys') or ''
            for feld in ('FileVersion', 'ProductVersion'):
                m = re.search(r'(?:^|;)%s=([^;]*)' % feld, keys)
                ist = m.group(1) if m else None
                if ist != soll:
                    befunde.append((6, '%s %s: Keys %s=%s, Soll %s'
                                    % (name, bed, feld, ist, soll)))
            # Comments=Release x.y.z landet ebenso in der BPL. Beim Bump auf
            # 0.9.19 blieb der Key zunaechst auf 0.9.18 stehen. Bewusst ohne
            # Datum: ein spaeteres Release-Datum braucht keinen Neubau.
            m = re.search(r'(?:^|;)Comments=Release ([\d.]+)', keys)
            if m and m.group(1) != release:
                befunde.append((6, '%s %s: Keys Comments nennt Release %s, '
                                'Soll %s' % (name, bed, m.group(1), release)))
        # Eine Cfg-Gruppe erbt nicht nur, sie ueberschreibt: stuende dort ein
        # eigener Wert, baute die IDE ihn, und die Pruefung oben waere gruen.
        for bed, block in re.findall(
                r"""<PropertyGroup Condition="'\$\((Cfg_\w+)\)'!=''">(.*?)"""
                r"""</PropertyGroup>""", d, re.S):
            for tag in ('Keys', 'MajorVer', 'MinorVer', 'Release', 'Build'):
                if tag_wert(block, 'VerInfo_' + tag) is not None:
                    befunde.append((6, '%s %s ueberschreibt VerInfo_%s'
                                    % (name, bed, tag)))


def pruefe_katalog(repo, release, befunde):
    """(6) tool.version im Regelkatalog == Release-Version.

    Nicht verwechseln mit der Wurzel-"version" (Katalogversion, basedOn der
    Overlays): die zaehlt unabhaengig vom Release.
    """
    ist = (json.loads(lies(repo, KATALOG)).get('tool') or {}).get('version')
    if ist != release:
        befunde.append((6, '%s: tool.version=%s, Soll %s'
                        % (KATALOG, ist, release)))


def vierteilig(version):
    """x.y.z -> x.y.z.0, x.y.z.w bleibt. Die VERSIONINFO hat vier Felder.

    Bis 0.9.19 war jede Release-Version dreiteilig und die VERSIONINFO
    hing ".0" an. Ein Nachzuegler wie 0.9.19.1 traegt sein viertes Feld
    selbst; ".0" dahinter ergaebe 0.9.19.1.0 und damit fuenf Felder.
    """
    return version + '.0' if version.count('.') == 2 else version


def release_version(repo, befunde, vorgabe):
    """SCA_VERSION_FULL aus uSCAConsts, gegen SCA_VERSION und --version.

    Liefert (soll, release): soll ist vierteilig (VERSIONINFO), release so,
    wie SCA_VERSION/--version sie schreiben (x.y.z oder x.y.z.w).
    """
    t = lies(repo, CONSTS)
    kurz = re.search(r"\bSCA_VERSION\s*=\s*'([^']+)'", t)
    voll = re.search(r"\bSCA_VERSION_FULL\s*=\s*'([^']+)'", t)
    if not (kurz and voll):
        abbruch('SCA_VERSION/SCA_VERSION_FULL nicht gefunden: ' + CONSTS)
    if voll.group(1) != vierteilig(kurz.group(1)):
        befunde.append((6, 'uSCAConsts: SCA_VERSION_FULL=%s passt nicht zu '
                        'SCA_VERSION=%s' % (voll.group(1), kurz.group(1))))
    if vorgabe and vorgabe != kurz.group(1):
        befunde.append((6, 'uSCAConsts: SCA_VERSION=%s, verlangt wurde %s'
                        % (kurz.group(1), vorgabe)))
    release = vorgabe or kurz.group(1)
    if not re.match(r'^\d+\.\d+\.\d+(\.\d+)?$', release):
        abbruch('Version muss x.y.z oder x.y.z.w lauten: ' + release)
    return vierteilig(release), release


def argument(name):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 >= len(sys.argv):
            abbruch(name + ' braucht einen Wert')
        return sys.argv[i + 1]
    return None


def main():
    repo = argument('--repo') or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    befunde = []
    soll, release = release_version(repo, befunde, argument('--version'))

    geparst = {}
    for name, basis, _t, _q, _r in PAKETE:
        code, direktiven = zerlege_pascal(lies(repo, basis + '.dpk'))
        requires, units = klausel(code, 'requires'), contains_units(code)
        if requires is None or not units:
            abbruch('requires/contains nicht lesbar: %s.dpk' % basis)
        geparst[name] = {
            'direktiven': direktiven, 'requires': requires, 'units': units,
            'dproj': dproj_ohne_kommentare(lies(repo, basis + '.dproj'))}

    pruefe_units(repo, geparst, befunde)
    pruefe_requires(geparst, befunde)
    pruefe_typ(geparst, befunde)
    pruefe_suffix(geparst, befunde)
    pruefe_plattformen(geparst, befunde)
    pruefe_verinfo(geparst, soll, release, befunde)
    pruefe_katalog(repo, release, befunde)

    print('Paketsatz: %s = %d Units, Release-Version %s'
          % (' + '.join('%s %d' % (p[0], len(geparst[p[0]]['units']))
                        for p in PAKETE),
             sum(len(geparst[p[0]]['units']) for p in PAKETE), soll))
    titel = ((1, 'Unit in genau einem Paket'), (2, 'requires-Graph'),
             (3, 'Pakettyp .dpk/.dproj'), (4, 'LIBSUFFIX nur an RUNONLY'),
             (5, 'Plattformen + Win64-Sperre'), (6, 'Versionen == Release'))
    for nr, text in titel:
        eigene = [b for n, b in befunde if n == nr]
        print('  (%d) %-27s %s' % (nr, text,
                                   'ok' if not eigene else 'ROT %d' % len(eigene)))
        for b in eigene:
            print('        ' + b)

    if befunde:
        print('\nGATE ROT: %d Befund(e). Der Dev-Bau kann davon gruen bleiben '
              '- die Luecke faellt erst im ausgelieferten Satz auf.'
              % len(befunde))
        return 1
    print('GATE GRUEN: vier Pakete, sechs Pruefungen, keine Abweichung.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:      # noqa: BLE001 - ein Gate darf nie haengen
        print('Gate-Fehler: %s' % exc)
        sys.exit(2)
