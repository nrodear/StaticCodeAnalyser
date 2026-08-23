# -*- coding: utf-8 -*-
"""Gate: EIN Projektsatz traegt Delphi 12 und Delphi 13.

WOZU: Am 2026-08-22/23 gab es zwei Anlaeufe mit einem zweiten Dateisatz
(*.d13.dproj). Beide sind gescheitert, und zwar an derselben Wurzel: der
Name der .dproj war nicht mehr der Name der .dpk. Daraus folgten
nacheinander ein falscher BPL-Name, ein falscher <OutputName>, eine
falsche .res und zuletzt ein Ladefehler, den ich nicht mehr aufloesen
konnte. Jeder Fix erzeugte das naechste Symptom.

Der Satz ist deshalb wieder EINER. Welche Generation gebaut wird,
entscheidet allein die IDE, die man startet:

  {$LIBSUFFIX AUTO}   in der .dpk   -> der Compiler haengt 290 bzw. 370 an
  <DllSuffix>$(Auto)> in der .dproj -> die IDE erwartet denselben Namen
  $(SCAGen)           in der .dproj -> die DCUs landen getrennt

Dieses Gate haelt die Invarianten fest, die das tragen. Jede steht fuer
einen Fehler, der schon einmal Zeit gekostet hat.

  1  Es gibt keinen zweiten Projektsatz (*.d13.dproj o. ae.).
  2  Der Basisname der .dproj ist der Basisname ihrer <MainSource>.
     DAS ist die Wurzel der ganzen Episode.
  3  Jedes Package traegt <DllSuffix>$(Auto)</DllSuffix> UND seine .dpk
     ein {$LIBSUFFIX AUTO}. Die .dproj-Angabe allein reicht nicht - sie
     sagt nur, welchen Namen die IDE ERWARTET.
  4  Jedes Package deklariert genau einen Pakettyp, in .dproj UND .dpk.
     Ohne {$RUNONLY}/{$DESIGNONLY} installiert die IDE jedes Paket nach
     dem Bau in sich selbst.
  5  Jedes Projekt definiert $(SCAGen) und $(SCARoot), und die Tiefe von
     $(SCARoot) passt zum Ablageort.
  6  Die DCU-Ausgabe liegt in der generationsgetrennten Zelle. Ohne das
     schreiben D12 und D13 in denselben Ordner.

    python tools/dproj_multiversion_gate.py

EXIT  0 gruen | 1 Befunde | 2 Aufruffehler
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

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
ZELLE = '$(SCARoot)' + BS + 'lib' + BS + '$(SCAGen)'

PAKETTYPEN = (('RuntimeOnlyPackage', 'RUNONLY'),
              ('DesignOnlyPackage', 'DESIGNONLY'))


def read(rel):
    return io.open(os.path.join(REPO, rel), encoding='utf-8-sig').read()


def values(text, tag):
    return re.findall(r'<%s[^>]*>([^<]*)</%s>' % (tag, tag), text)


def ohne_kommentare(text):
    """Zeilen- und Blockkommentare ausblenden.

    Der Erklaerblock in genau diesen .dpk NENNT die Direktiven, die hier
    gesucht werden. Wer den rohen Text prueft, haelt den Warnhinweis fuer
    die Direktive - das ist mir in dieser Sitzung zweimal passiert.
    """
    raus = []
    for zeile in text.split(chr(10)):
        code = zeile.split('//')[0]
        code = re.sub(r'\{(?!\$)[^}]*\}', ' ', code)   # { } ist Kommentar,
        raus.append(code)                              # {$ } eine Direktive
    return chr(10).join(raus)


def dprojs():
    out = subprocess.run(['git', '-C', REPO, 'ls-files', '*.dproj'],
                         capture_output=True, text=True, timeout=30)
    return sorted(out.stdout.split())


def main():
    befunde = []
    alle = dprojs()
    if not alle:
        print('Keine Projektdateien gefunden.')
        return 2

    # 1 kein zweiter Satz
    zweite = [p for p in alle
              if re.search(r'\.d1[3-9]\.dproj$', p, re.I)]
    for p in zweite:
        befunde.append('%s sieht nach einem zweiten Projektsatz aus. Ein '
                       'Satz traegt beide Generationen - siehe Kopf dieses '
                       'Gates, warum das so ist.' % p)

    for p in alle:
        t = read(p)
        base = os.path.splitext(os.path.basename(p))[0]

        # 2 dproj-Name == MainSource-Name
        main = values(t, 'MainSource')
        if main:
            src_base = os.path.splitext(main[0])[0]
            if src_base != base:
                befunde.append(
                    '%s heisst anders als seine Quelldatei %s. Dann weicht '
                    'der Name, den die IDE erwartet, von dem ab, den der '
                    'Compiler schreibt - genau daran sind zwei Anlaeufe '
                    'gescheitert.' % (p, main[0]))

        ist_paket = 'Package' in values(t, 'AppType')
        dpk = os.path.join(os.path.dirname(p), main[0]) if main else None
        dpk_code = (ohne_kommentare(read(dpk)).upper()
                    if dpk and os.path.isfile(os.path.join(REPO, dpk))
                    else '')

        if ist_paket:
            # 3 Suffix auf beiden Seiten
            if '$(Auto)' not in ''.join(values(t, 'DllSuffix')):
                befunde.append('%s ist ein Package ohne '
                               '<DllSuffix>$(Auto)</DllSuffix>.' % p)
            if 'LIBSUFFIX AUTO' not in dpk_code:
                befunde.append('%s traegt kein {$LIBSUFFIX AUTO} - dann '
                               'erzeugt der Compiler eine BPL ohne Suffix, '
                               'und beide Delphi-Generationen wollen '
                               'denselben Dateinamen.' % dpk)

            # 4 Pakettyp auf beiden Seiten, genau einer
            gesetzt = [(prop, direktive) for prop, direktive in PAKETTYPEN
                       if 'true' in [v.lower() for v in values(t, prop)]]
            if not gesetzt:
                befunde.append('%s deklariert weder <RuntimeOnlyPackage> '
                               'noch <DesignOnlyPackage> - die IDE haelt es '
                               'dann fuer beides und laedt es nach jedem '
                               'Bau.' % p)
            elif len(gesetzt) > 1:
                befunde.append('%s deklariert BEIDE Pakettypen.' % p)
            else:
                prop, direktive = gesetzt[0]
                if ('{$' + direktive) not in dpk_code:
                    befunde.append('%s setzt <%s>, aber %s traegt kein '
                                   '{$%s}. Nur die Direktive haelt die IDE '
                                   'davon ab, das Paket zu laden.'
                                   % (p, prop, dpk, direktive))

        # 5 Generationskennung
        for tag in ('SCAGen', 'SCARoot'):
            if not values(t, tag):
                befunde.append('%s definiert $(%s) nicht.' % (p, tag))
        root = values(t, 'SCARoot')
        if root:
            tiefe = p.count('/')
            soll = BS.join(['..'] * tiefe) if tiefe else '.'
            if root[0] != soll:
                befunde.append('%s: <SCARoot> ist "%s", bei dieser Tiefe '
                               'muss es "%s" sein.' % (p, root[0], soll))

        # 6 DCU in der Zelle
        dcu = values(t, 'DCC_DcuOutput')
        if not dcu:
            befunde.append('%s setzt kein <DCC_DcuOutput>.' % p)
        elif not all(ZELLE in v for v in dcu):
            befunde.append('%s: <DCC_DcuOutput> = "%s" liegt nicht in der '
                           'generationsgetrennten Zelle - D12 und D13 '
                           'schreiben dann in denselben Ordner.'
                           % (p, dcu[0]))

    print('Geprueft: %d Projektdateien.' % len(alle))
    if not befunde:
        print('GATE GRUEN: ein Projektsatz, beide Generationen sauber '
              'getrennt.')
        return 0
    print()
    for b in befunde:
        print('  * %s' % b)
    print('\nGATE ROT: %d Befund(e).' % len(befunde))
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:      # noqa: BLE001 - ein Gate darf nie haengen
        print('Gate-Fehler: %s' % exc)
        sys.exit(2)
