# -*- coding: utf-8 -*-
"""Welche Paket-Artefakte sind aelter als ihre Quelle?

WOZU: Ein Paket, das ein anderes 'requires', zieht dessen Units aus dem
DCP - NICHT aus der Quelle. Ist das DCP aelter als die Quelle, meldet
der Compiler Fehler, die im Quelltext laengst behoben sind. Am
2026-08-22 genau so: 'E2003 Undeklarierter Bezeichner EncodeLineSnapshot'
gegen ein SCA.SharedUI.dcp von 11 Stunden vor der Funktion.

Diese Fehlerklasse ist in diesem Projekt wiederkehrend (F2613,
CLI-Detector-Dropout, TEditSource-Crash - alle drei waren Stale-Builds).
Die Meldung des Compilers zeigt dabei immer auf den FALSCHEN Ort: auf
die Aufrufstelle, nicht auf das veraltete Artefakt.

    python tools/stale_artifacts_check.py
    python tools/stale_artifacts_check.py --clean-commands

EXIT  0 alles aktueller als die Quelle | 1 veraltete Artefakte | 2 Fehler
"""
import io
import os
import re
import sys
import time

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBLIC = os.path.join(os.environ.get('PUBLIC', 'C:' + os.sep + 'Users' + os.sep + 'Public'),
                      'Documents', 'Embarcadero', 'Studio')

# Studio-Nummer -> Anzeigename. Die Nummer ist ein Sprung, nie eine
# Rechnung: D12 ist 23.0, D13 ist 37.0.
STUDIOS = (('23.0', 'D12'), ('37.0', 'D13'))

PACKAGES = (
    ('SCA.Engine',                    'SCA.Engine/SCA.Engine.dpk'),
    ('SCA.SharedUI',                  'SCA.SharedUI/SCA.SharedUI.dpk'),
    ('StaticCodeAnalyser.IDE.d12',
     'StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dpk'),
    ('StaticCodeAnalyser.Plugin.d12',
     'StaticCodeAnalyserIDE/StaticCodeAnalyser.Plugin.d12.dpk'),
)


def dproj_of(dpk_rel, gen):
    """Die .dproj dieses Pakets.

    Es gibt nur EINEN Projektsatz; er traegt beide Generationen. Der
    Parameter gen bleibt in der Signatur, weil die Aufrufstelle je
    Generation durchlaeuft - die Datei ist fuer beide dieselbe.

    Bis 2026-08-23 stand hier die Suche nach '*.d13.dproj'. Nachdem der
    zweite Projektsatz zurueckgerollt war, fand sie nichts mehr und der
    Pruefer war fuer die gesamte D13-Seite BLIND - er meldete gruen,
    wo er nichts geprueft hatte.
    """
    del gen
    base = dpk_rel[:-4]
    for c in (base + '.dproj', base + '.d12.dproj'):
        if os.path.isfile(os.path.join(REPO, c)):
            return c
    return None


STUDIO_PROGRAMM = {
    'D12': r'C:\Program Files (x86)\Embarcadero\Studio\23.0',
    'D13': r'C:\Program Files (x86)\Embarcadero\Studio\37.0',
}


def braucht_designide(dpk_rel):
    """Steht designide in der requires-Klausel dieses Pakets?"""
    f = os.path.join(REPO, dpk_rel)
    if not os.path.isfile(f):
        return False
    t = io.open(f, encoding='utf-8-sig', errors='replace').read()
    m = re.search(r'^requires(.*?);', t, re.S | re.M | re.I)
    return bool(m) and 'designide' in m.group(1).lower()


def designide_da(gen, plat):
    """Liefert diese Delphi-Installation designide fuer diese Plattform?

    Gemessen statt angenommen. Delphi 12 hat designide NUR fuer Win32 -
    kein 23.0/lib/win64/release/designide.dcp. Ein Entwurfszeitpaket kann
    dort also gar keinen Win64-Bau haben, und ein Pruefer, der einen
    erwartet, meldet dauerhaft ein FEHLT, das niemand beheben kann.
    """
    root = STUDIO_PROGRAMM.get(gen)
    if not root or not os.path.isdir(root):
        return True          # unbekannt -> nicht ausschliessen
    return os.path.isfile(os.path.join(root, 'lib', plat.lower(), 'release',
                                       'designide.dcp'))


def erwartete_plattformen(dpk_rel, gen):
    """Welche Plattformen dieses Paket in dieser Generation bauen SOLL.

    Ohne das zeigt die Tabelle nur, was da ist - und ein Paket, das nie
    gebaut wurde, faellt einfach aus der Liste. Genau daran ist am
    2026-08-22 eine ganze Abendrunde vorbeigelaufen.
    """
    d = dproj_of(dpk_rel, gen)
    if not d:
        return []
    t = io.open(os.path.join(REPO, d), encoding='utf-8-sig').read()
    out = []
    braucht = braucht_designide(dpk_rel)
    for plat in ('Win32', 'Win64'):
        m = re.search(r'<Platform value="%s">(\w+)</Platform>' % plat, t)
        if not (m and m.group(1).lower() == 'true'):
            continue
        if braucht and not designide_da(gen, plat):
            continue         # kann es in dieser Generation nicht geben
        out.append(plat)
    return out


def pfad_kollision():
    """Stehen Bpl-Ordner BEIDER Generationen im PATH?

    dcc faellt bei der Aufloesung von 'requires' auf den PATH zurueck. Am
    2026-08-22 hat ein D13-Bau darueber ein D12-Artefakt gegriffen und
    F2141 'Falsches Dateiformat' gemeldet - mit einem Pfad, der in keiner
    Suchpfad-Option des Compileraufrufs stand.
    """
    teile = [x for x in os.environ.get('PATH', '').split(os.pathsep)
             if 'embarcadero' in x.lower() and x.lower().rstrip(os.sep)
             .endswith(('bpl', 'win64', 'win32'))]
    gefunden = {}
    for ver, label in STUDIOS:
        for t in teile:
            if (os.sep + ver + os.sep) in t + os.sep:
                gefunden.setdefault(label, []).append(t)
    return gefunden


def bpl_gewinner():
    """Welche gleichnamige BPL findet der Loader zuerst?

    Die PATH-Warnung darunter galt bisher nur dem Compiler. Am 2026-08-24
    hat dieselbe Reihenfolge den IDE-LOADER getroffen: das D12-Plugin
    fordert per requires "SCA.Engine.bpl" an, im PATH stand aber
    37.0\Bpl VOR 23.0\Bpl - die IDE lud die Delphi-13-Fassung und
    stuerzte mit einer Zugriffsverletzung in bds.exe ab.

    Vorher fiel das nie auf, weil alle drei Dev-BPLs mit ABSOLUTEM Pfad
    in den Known Packages standen; da gibt es keine PATH-Suche. Erst
    {$RUNONLY} (2026-08-23) hat diese Registrierung unmoeglich gemacht
    und damit die Aufloesung an den PATH abgegeben.

    Liefert je Dateiname die Liste der Fundorte in PATH-Reihenfolge -
    der erste gewinnt.
    """
    teile = [x for x in os.environ.get('PATH', '').split(os.pathsep)
             if x and 'embarcadero' in x.lower()]
    treffer = {}
    for t in teile:
        try:
            namen = os.listdir(t)
        except OSError:
            continue
        for n in namen:
            if not n.lower().endswith('.bpl'):
                continue
            if not (n.startswith('SCA.') or n.startswith('StaticCodeAnalyser')):
                continue
            treffer.setdefault(n, []).append(os.path.join(t, n))
    # NUR generationsuebergreifende Doppel melden. Derselbe Name in
    # 23.0\Bpl und 23.0\Bpl\Win64 ist Absicht - dort trennt die
    # Bitbreite, und die 32-Bit-IDE findet den Win32-Ordner zuerst. Ein
    # Doppel zwischen 23.0 und 37.0 ist dagegen immer ein Fehler.
    def gen(p):
        low = p.lower()
        for ver, label in STUDIOS:
            if (os.sep + ver.lower() + os.sep) in low:
                return label
        return '?'

    echt = {}
    for n, v in treffer.items():
        if len({gen(p) for p in v}) > 1:
            echt[n] = v
    return echt


def when(ts):
    return time.strftime('%Y-%m-%d %H:%M', time.localtime(ts))


def newest_source(dpk_rel):
    """Juengste Quelldatei eines Pakets: die .dpk selbst plus alles aus
    ihrer contains-Klausel."""
    base = os.path.dirname(os.path.join(REPO, dpk_rel))
    text = io.open(os.path.join(REPO, dpk_rel), encoding='utf-8-sig').read()
    newest, who = os.path.getmtime(os.path.join(REPO, dpk_rel)), dpk_rel
    for rel in re.findall(r"in\s+'([^']+\.pas)'", text):
        f = os.path.join(base, rel.replace(chr(92), os.sep))
        if os.path.isfile(f):
            t = os.path.getmtime(f)
            if t > newest:
                newest, who = t, os.path.relpath(f, REPO)
    return newest, who


def main():
    rows, stale, fehlend = [], 0, 0
    for name, dpk in PACKAGES:
        if not os.path.isfile(os.path.join(REPO, dpk)):
            continue
        src_ts, src_who = newest_source(dpk)
        for ver, label in STUDIOS:
            root = os.path.join(PUBLIC, ver)
            if not os.path.isdir(root):
                continue
            for plat in erwartete_plattformen(dpk, label):
                sub = '' if plat == 'Win32' else plat
                dcp = os.path.join(root, 'Dcp', sub, name + '.dcp')
                if not os.path.isfile(dcp):
                    # FEHLT ist eine eigene Kategorie. Wer nur zeigt, was
                    # da ist, verschweigt genau das, wonach gesucht wird.
                    fehlend += 1
                    rows.append((label, plat, name, None, src_ts, src_who,
                                 True))
                    continue
                art = os.path.getmtime(dcp)
                bad = art < src_ts
                stale += bad
                rows.append((label, plat, name, art, src_ts, src_who, bad))

    kol = pfad_kollision()
    if len(kol) > 1:
        print('WARNUNG: Bpl-Ordner BEIDER Generationen stehen im PATH.')
        for label in sorted(kol):
            for t in kol[label]:
                print('   %-4s %s' % (label, t))
        print('   Das trifft ZWEI Werkzeuge:')
        print('   * dcc faellt bei der Aufloesung von "requires" auf den')
        print('     PATH zurueck. Fehlt das DCP der eigenen Generation,')
        print('     greift es das der anderen - Meldung dann F2141')
        print('     "Falsches Dateiformat", mit einem Pfad, der in keiner')
        print('     Suchpfad-Option des Compileraufrufs steht.')
        print('   * der IDE-LOADER tut dasselbe mit den BPLs, sobald ein')
        print('     Paket nicht mit absolutem Pfad in den Known Packages')
        print('     steht. Ein Laufzeitpaket ({$RUNONLY}) kann dort gar')
        print('     nicht stehen - dann entscheidet allein der PATH.')
        print()

    doppelt = bpl_gewinner()
    if doppelt:
        print('ROT: %d BPL-Name(n) liegen MEHRFACH im PATH.' % len(doppelt))
        print('Der Loader nimmt den ersten Treffer - die anderen sind tot:')
        for n in sorted(doppelt):
            for i, p in enumerate(doppelt[n]):
                mark = '  <== wird geladen' if i == 0 else ''
                print('   %-30s %s%s' % (n if i == 0 else '', p, mark))
        print('   Gehoeren die Fundorte zu verschiedenen Delphi-')
        print('   Generationen, laedt die IDE die falsche und stuerzt ab.')
        print()

    if not rows:
        print('Keine gebauten Paket-Artefakte gefunden - nichts zu pruefen.')
        return 0

    print('%-4s %-11s %-30s %-16s %-16s' %
          ('IDE', 'Plattform', 'Paket', 'DCP gebaut', 'Quelle zuletzt'))
    for label, plat, name, art, src, who, bad in rows:
        zustand = 'FEHLT' if art is None else ('VERALTET' if bad else 'ok')
        print('%-4s %-11s %-30s %-16s %-16s %s'
              % (label, plat, name, '-' if art is None else when(art),
                 when(src), zustand))

    if not stale and not fehlend:
        print('\nGRUEN: jedes DCP ist juenger als seine Quelle.')
        return 0

    if '--clean-commands' in sys.argv:
        # Zeigt die Loeschbefehle nur AN. Dieses Werkzeug fasst nichts
        # an, was es nicht selbst gebaut hat - die Artefakte liegen in
        # der Delphi-Installation des Nutzers.
        print()
        print('Veraltete Artefakte wegraeumen'
              ' (nur angezeigt, nicht ausgefuehrt).')
        print('Danach meldet der Compiler ein FEHLENDES Paket statt'
              ' eines irrefuehrenden E2003:')
        print()
        by_label = dict((b, a) for a, b in STUDIOS)
        seen, any_line = set(), False
        # Nach IDE gruppiert: die D12-Zeilen betreffen eine LAUFENDE
        # Installation. Wer sie mitloescht, legt sein installiertes
        # D12-Plugin lahm, bis es neu gebaut ist.
        for want in [lbl for _v, lbl in STUDIOS]:
            block = []
            for label, plat, name, art, src, who, bad in rows:
                if not bad or label != want:
                    continue
                sub = '' if plat.startswith('(') else plat
                for kind, exts in (('Dcp', ('.dcp', '.bpi', '.lib', '.a')),
                                   ('Bpl', ('.bpl',))):
                    for e in exts:
                        f = os.path.join(PUBLIC, by_label[label], kind,
                                         sub, name + e)
                        if os.path.isfile(f) and f not in seen:
                            seen.add(f)
                            block.append('  del "%s"' % f)
            if block:
                any_line = True
                print('  --- %s (Studio %s) ---'
                      % (want, by_label[want]))
                print(chr(10).join(block))
                print()
        if not any_line:
            print('  (nichts gefunden)')

    print()
    print('ROT: %d Artefakt(e) FEHLEN, %d sind aelter als die Quelle.'
          % (fehlend, stale))
    print('Ein Paket, das darauf "requires", compiliert gegen den ALTEN')
    print('Stand - der Compiler meldet dann Fehler an der Aufrufstelle,')
    print('nicht am veralteten DCP. Betroffene Pakete neu bauen, in der')
    print('Reihenfolge SCA.Engine -> SCA.SharedUI -> IDE/Plugin.')
    for label, plat, name, art, src, who, bad in rows:
        if bad:
            print('  %s %s %s: juengste Quelle ist %s (%s)'
                  % (label, plat, name, who, when(src)))
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:      # noqa: BLE001 - Werkzeug darf nie haengen
        print('Fehler: %s' % exc)
        sys.exit(2)
