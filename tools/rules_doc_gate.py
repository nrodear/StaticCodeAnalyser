# -*- coding: utf-8 -*-
"""Regelkatalog-Gate: haelt docs/rules.md und rules/sca-rules.json deckungsgleich.

WARUM ES DIESES GATE GIBT (2026-08-19)
--------------------------------------
docs/rules.md traegt in der ersten Zeile "Single source of truth:
rules/sca-rules.json". Gepflegt wurde die Datei aber von Hand, und beim
Nachmessen war das Versprechen gebrochen: 56 der 196 Regeln wichen ab -
zwei Kurzbeschreibungen und 54 Volltexte, und zwar in BEIDE Richtungen
(22-mal hatte die md mehr Text als die JSON, 31-mal wichen die Formulierungen
echt voneinander ab). Wer eine Regel in der JSON aendert, aendert damit SARIF,
Sonar und die Oberflaeche - die Doku-Seite blieb stehen, ohne dass es jemand
sah.

Das Gate prueft NICHT auf Zeichengleichheit. Die md darf reicher sein: sie
setzt Inline-Code in Backticks, wo die JSON blanken Text fuehrt, weil deren
Text unveraendert nach SARIF und Sonar geht und dort Backticks als literale
Zeichen erschienen. Verglichen wird deshalb der Prosa-KERN - ohne Backticks,
mit normalisiertem Leerraum. Genau diese Auszeichnung ist der Grund, warum
docs/rules.md (noch) nicht generiert wird.

Geprueft wird je Regel:
  * Abschnitt vorhanden (und kein Abschnitt ohne Regel)
  * Zeile in der Uebersichtstabelle: Name, Severity, Typ, Detektor
  * Feld-Tabelle: Severity, Typ, Tags, CWE, OWASP, Config, Detektor,
    Editor help (editorHelps, wortgleich)
  * Prosa: Name, Kurzbeschreibung, Volltext - je modulo Backticks

EXIT-CODE
  0  deckungsgleich
  1  mindestens eine Abweichung
  2  Aufruf-/Lesefehler

    python tools/rules_doc_gate.py           # pruefen (kompakte Liste)
    python tools/rules_doc_gate.py --full    # ganze Texte statt Auszuege
"""
import argparse
import io
import json
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

BT = chr(96)
REPO = Path(__file__).resolve().parent.parent
RULES_JSON = REPO / 'rules' / 'sca-rules.json'
RULES_MD = REPO / 'docs' / 'rules.md'

# Severity wird in der md fett gesetzt, sobald sie eskaliert - der Katalog
# kennt den Fettdruck nicht, also hier abbilden statt dort.
BOLD_SEVERITIES = ('Error',)


def kern(s):
    """Prosa-Kern: nur der Wortlaut, ohne Markdown-Auszeichnung.

    Entfernt wird alles, was die Doku-Seite an Typografie DARF und der
    Katalog nicht kann, weil sein Text unveraendert nach SARIF und Sonar
    geht: Backticks, Fettdruck, der Abschnittstrenner am Ende, und
    Halbgeviert-/Geviertstriche werden auf den einfachen Bindestrich
    normalisiert. Ohne diese Normalisierung meldet das Gate Drift, wo nur
    ein Gedankenstrich schoener gesetzt ist - und solche Phantome sind
    genau der Grund, warum Gates ungelesen bleiben.
    """
    s = s.replace(BT, '').replace('**', '')
    s = s.replace(chr(0x2014), '-').replace(chr(0x2013), '-')
    s = re.sub(r'\s*-{3,}\s*$', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()


def sev_md(sev):
    return '**%s**' % sev if sev in BOLD_SEVERITIES else sev


def lade():
    try:
        cat = json.load(io.open(RULES_JSON, encoding='utf-8-sig'))
    except OSError as e:
        print('rules/sca-rules.json nicht lesbar: %s' % e, file=sys.stderr)
        raise SystemExit(2)
    except ValueError as e:
        print('rules/sca-rules.json ist kein gueltiges JSON: %s' % e,
              file=sys.stderr)
        raise SystemExit(2)
    try:
        md = io.open(RULES_MD, encoding='utf-8').read()
    except OSError as e:
        print('docs/rules.md nicht lesbar: %s' % e, file=sys.stderr)
        raise SystemExit(2)
    return cat.get('rules', []), md


def abschnitte(md):
    """Rule-ID -> Abschnittstext, vom '## SCAnnn' bis zum naechsten."""
    return {m.group(1): m.group(2) for m in
            re.finditer(r'^## (SCA\d+)$(.*?)(?=^## SCA\d+$|\Z)',
                        md, re.M | re.S)}


def index_zeilen(md):
    """Rule-ID -> Zellen der Uebersichtstabelle (ohne die ID-Zelle)."""
    out = {}
    for m in re.finditer(r'^\|\s*\[(SCA\d+)\]\(#sca\d+\)\s*\|(.*)\|\s*$',
                         md, re.M):
        out[m.group(1)] = [c.strip() for c in m.group(2).split('|')]
    return out


def feld(body, name):
    """Wert einer Zeile '| <name> | <wert> |' aus der Feld-Tabelle."""
    m = re.search(r'^\|\s*' + re.escape(name) + r'\s*\|(.*?)\|\s*$',
                  body, re.M)
    return m.group(1).strip() if m else None


def volltext(body):
    """Prosa zwischen Feld-Tabelle und Codeblock.

    Ansatzpunkt ist die LETZTE Tabellenzeile, nicht die Detector-Zeile: 14
    Regeln tragen hinter Detector noch Sonderfelder (Scope, Construct und
    ein paar Einzelstuecke wie "`override`"). Wer an der Detector-Zeile
    ansetzt, zieht diese Zeilen in die Prosa und meldet 14 Phantom-Drifts.
    """
    zeilen = body.split(chr(10))
    letzte = -1
    for i, z in enumerate(zeilen):
        if z.lstrip().startswith('|'):
            letzte = i
    if letzte < 0:
        return None
    rest = chr(10).join(zeilen[letzte + 1:])
    p = rest.find(BT * 3)
    return rest if p < 0 else rest[:p]


def pruefe(rules, md, voll):
    sec = abschnitte(md)
    idx = index_zeilen(md)
    by_id = {r['id']: r for r in rules}
    funde = []

    def melde(rid, was, ist, soll):
        funde.append((rid, was, ist, soll))

    for rid in sorted(set(sec) - set(by_id)):
        melde(rid, 'Abschnitt ohne Regel im Katalog', '-', '-')
    for r in rules:
        rid = r['id']
        if rid not in sec:
            melde(rid, 'Regel ohne Abschnitt in docs/rules.md', '-', '-')
            continue
        body = sec[rid]

        # --- Uebersichtstabelle -------------------------------------------
        row = idx.get(rid)
        if row is None:
            melde(rid, 'Zeile in der Uebersichtstabelle fehlt', '-', '-')
        elif len(row) >= 4:
            for pos, (was, soll) in enumerate((
                    ('Uebersicht/Name', r['name']),
                    ('Uebersicht/Severity', sev_md(r['defaultSeverity'])),
                    ('Uebersicht/Typ', r['type']),
                    ('Uebersicht/Detektor', BT + r['detectorUnit'] + BT))):
                if kern(row[pos]) != kern(soll):
                    melde(rid, was, row[pos], soll)

        # --- Feld-Tabelle --------------------------------------------------
        # Severity und Typ stehen in EINER Zeile ('| Severity | X | Type | Y |'),
        # deshalb hier ueber den Rohtext statt ueber feld().
        m = re.search(r'^\|\s*Severity\s*\|\s*(.+?)\s*\|\s*Type\s*\|'
                      r'\s*(.+?)\s*\|\s*$', body, re.M)
        if not m:
            melde(rid, 'Feld-Tabelle ohne Severity/Type-Zeile', '-', '-')
        else:
            if kern(m.group(1)) != kern(sev_md(r['defaultSeverity'])):
                melde(rid, 'Severity', m.group(1),
                      sev_md(r['defaultSeverity']))
            if kern(m.group(2)) != kern(r['type']):
                melde(rid, 'Typ', m.group(2), r['type'])

        soll_tags = ', '.join(BT + t + BT for t in r['tags'])
        ist_tags = feld(body, 'Tags')
        if kern(ist_tags or '') != kern(soll_tags):
            melde(rid, 'Tags', ist_tags, soll_tags)

        ist_det = feld(body, 'Detector')
        if kern(ist_det or '') != kern(r['detectorUnit']):
            melde(rid, 'Detektor', ist_det, r['detectorUnit'])

        # CWE/OWASP/Config sind optional - fehlt das Feld im Katalog, darf
        # auch keine Zeile dastehen (und umgekehrt).
        for was, key, ist in (('CWE', 'cwe', feld(body, 'CWE')),
                              ('OWASP', 'owasp', feld(body, 'OWASP')),
                              ('Config', 'configKey', feld(body, 'Config'))):
            hat_kat = key in r and r[key]
            if hat_kat and ist is None:
                melde(rid, was + ' fehlt in der Doku', '-', str(r[key]))
            elif not hat_kat and ist is not None:
                melde(rid, was + ' steht nur in der Doku', ist, '-')
            elif hat_kat:
                soll = r[key] if isinstance(r[key], str) else ' '.join(r[key])
                # CWE ist in der md verlinkt - die IDs muessen vorkommen.
                fehlend = [x for x in soll.split() if x not in ist]
                if fehlend:
                    melde(rid, was, ist, soll)

        # Editorhilfen (2026-10-28): optional wie Config, aber wortgleich -
        # dieselben 'id:effect:slug' wie SARIF properties.editorHelp.
        ist = feld(body, 'Editor help')
        soll = ', '.join(BT + ':'.join((h['id'], h['effect'], h['slug'])) + BT
                         for h in r.get('editorHelps') or [])
        if soll and ist is None:
            melde(rid, 'Editor help fehlt in der Doku', '-', soll)
        elif not soll and ist is not None:
            melde(rid, 'Editor help steht nur in der Doku', ist, '-')
        elif soll and ist != soll:
            melde(rid, 'Editor help', ist, soll)

        # Konfidenz (2026-11-03): optional wie Config. Ohne die Zeile sagte
        # die Seite "BAD", und im Standardlauf (MinConfidence=medium) kam
        # bei 21 Regeln trotzdem nichts - Doku-Review 2026-11-01.
        ist = feld(body, 'Confidence')
        soll = r.get('defaultConfidence')
        if soll and ist is None:
            melde(rid, 'Confidence fehlt in der Doku', '-', soll)
        elif not soll and ist is not None:
            melde(rid, 'Confidence steht nur in der Doku', ist, '-')
        elif soll and not ist.startswith(BT + soll + BT):
            melde(rid, 'Confidence', ist, soll)

        # --- Prosa ----------------------------------------------------------
        mn = re.search(r'^\*\*(.+?)\*\*$', body, re.M)
        if not mn:
            melde(rid, 'Name-Zeile fehlt', '-', r['name'])
        elif kern(mn.group(1)) != kern(r['name']):
            melde(rid, 'Name', mn.group(1), r['name'])

        ms = re.search(r'^> (.+)$', body, re.M)
        if not ms:
            melde(rid, 'Kurzbeschreibung fehlt', '-', r['shortDescription'])
        elif kern(ms.group(1)) != kern(r['shortDescription']):
            melde(rid, 'Kurzbeschreibung', ms.group(1),
                  r['shortDescription'])

        vt = volltext(body)
        if vt is None:
            melde(rid, 'Volltext nicht auffindbar', '-', '-')
        elif kern(vt) != kern(r['fullDescription']):
            melde(rid, 'Volltext', kern(vt), kern(r['fullDescription']))

        # --- Beispiele ------------------------------------------------------
        # Der erste Codeblock ('// BAD ... // GOOD ...') muss die Beispiele
        # des Katalogs tragen. Bis 2026-11-03 prueft das Gate nur Prosa - so
        # blieb auf der helpUri-Zielseite das alte SCA115-Beispiel stehen,
        # das die Regel selbst ueberspringt, obwohl der Katalog es laengst
        # korrigiert hatte. Ein Abschnitt OHNE Codeblock bleibt erlaubt,
        # ebenso ein angehaengter '// NOT REPORTED'-Teil und ein Zusatz am
        # GOOD-Etikett ('// GOOD (.pas at runtime)').
        mb = re.search(r'^```\w*\n(.*?)\n```', body, re.M | re.S)
        if mb:
            bm = re.match(r'(?://|;) BAD[^\n]*\n(.*?)\n\n(?://|;) GOOD[^\n]*'
                          r'\n(.*?)(?:\n\n// NOT REPORTED.*)?$',
                          mb.group(1), re.S)
            if not bm:
                melde(rid, 'Codeblock ohne BAD/GOOD-Gliederung', '-', '-')
            else:
                ex = r.get('examples') or {}
                for was, ist, soll in (
                        ('Beispiel bad', bm.group(1), ex.get('bad', '')),
                        ('Beispiel good', bm.group(2), ex.get('good', ''))):
                    if leer(ist) != leer(soll):
                        melde(rid, was, leer(ist), leer(soll))

    return funde, len(sec)


def leer(s):
    """Codevergleich: nur der Leerraum ist normalisiert, Backticks zaehlen."""
    return re.sub(r'\s+', ' ', s).strip()


def kind_konfidenzen():
    """Kind -> 'fcLow'/'fcMedium'/'fcHigh' aus uSCAConsts.KindDefaultConfidence.

    Gelesen wird die IMPLEMENTIERUNG (zweites Vorkommen der Signatur), ohne
    Kommentare. Was dort nicht steht, ist fcHigh (else-Zweig).
    """
    pfad = REPO / 'SCA.Engine' / 'sources' / 'Common' / 'uSCAConsts.pas'
    text = pfad.read_text(encoding='utf-8-sig', errors='replace')
    sig = 'function KindDefaultConfidence(K: TFindingKind): TFindingConfidence;'
    a = text.find(sig, text.find(sig) + 1)
    if a < 0:
        return None
    b = text.find('\nend;', a)
    rumpf = re.sub(r'//[^\n]*', '', text[a:b])
    rumpf = re.sub(r'\{[^}]*\}', '', rumpf)
    out = {}
    for m in re.finditer(r'((?:fk\w+\s*,\s*)*fk\w+)\s*:\s*Result\s*:=\s*'
                         r'(fc\w+)', rumpf):
        for k in re.findall(r'fk(\w+)', m.group(1)):
            out[k] = m.group(2)
    return out


def pruefe_konfidenz(rules):
    """Katalogfeld defaultConfidence gegen den Code.

      * Kind mit fcLow in KindDefaultConfidence -> Feld 'low' oder 'mixed'
        (sonst fehlt der Seite der Hinweis, und ihr Beispiel schweigt im
        Standardlauf).
      * Feld 'mixed' -> Kind fcLow, und die Detektor-Unit hebt einzelne
        Funde an (fcMedium/fcHigh im Quelltext).
      * Feld 'low' bei einem Kind ohne fcLow -> die Detektor-Unit setzt
        fcLow selbst (z.B. SCA163 je Fund).
    """
    konf = kind_konfidenzen()
    if konf is None:
        return [('?', 'KindDefaultConfidence in uSCAConsts.pas nicht gefunden',
                 '-', '-')]
    units = {}
    for p in (REPO / 'SCA.Engine' / 'sources').rglob('*.pas'):
        units.setdefault(p.name.lower(), p)
    funde = []
    for r in rules:
        rid, feld_ = r['id'], r.get('defaultConfidence')
        kind_low = konf.get(r['kind']) == 'fcLow'
        unit = units.get(r.get('detectorUnit', '').lower())
        utext = (unit.read_text(encoding='utf-8-sig', errors='replace')
                 if unit else '')
        if kind_low and feld_ not in ('low', 'mixed'):
            funde.append((rid, 'defaultConfidence fehlt im Katalog',
                          str(feld_), 'low (KindDefaultConfidence = fcLow)'))
        elif feld_ == 'mixed' and not (
                kind_low and re.search(r'\bfc(Medium|High)\b', utext)):
            funde.append((rid, 'defaultConfidence mixed ohne Beleg im Code',
                          'mixed', 'Kind fcLow + Detektor hebt Funde an'))
        elif feld_ == 'low' and not kind_low and not re.search(
                r'\bfcLow\b', utext):
            funde.append((rid, 'defaultConfidence low ohne Beleg im Code',
                          'low', 'KindDefaultConfidence oder Detektor fcLow'))
    return funde


def pruefe_overlays(rules, katalog_version):
    """Sprach-Overlays gegen den Katalog.

    FEHLER ist nur, was nachweislich kaputt ist: eine Regel-ID, die es im
    Katalog nicht (mehr) gibt, und ein basedOn, das nicht zur
    Katalogversion passt - dann wurde gegen einen aelteren Stand
    uebersetzt, und niemand haette es gemerkt.

    Eine LUECKE ist ausdruecklich kein Fehler: fehlende Regeln und
    fehlende Felder fallen laut Schema auf Englisch zurueck, damit
    Uebersetzung regelweise voranschreiten kann. Die Abdeckung wird
    berichtet, nicht erzwungen - sonst waere jede neue Regel sofort ein
    roter Build in drei Sprachen.
    """
    ids = {r['id'] for r in rules}
    funde = []
    zeilen = []
    for pfad in sorted((REPO / 'rules').glob('sca-rules.*.json')):
        if pfad.name.endswith('.schema.json'):
            continue
        lang = pfad.name.split('.')[1]
        try:
            ov = json.load(io.open(pfad, encoding='utf-8-sig'))
        except ValueError as e:
            funde.append((lang, 'kein gueltiges JSON: %s' % e, '-', '-'))
            continue
        if ov.get('basedOn') != katalog_version:
            funde.append((lang, 'basedOn passt nicht zur Katalogversion',
                          ov.get('basedOn'), katalog_version))
        fremd = sorted(set(ov.get('rules', {})) - ids)
        if fremd:
            funde.append((lang, 'Regel-IDs ohne Entsprechung im Katalog',
                          ' '.join(fremd[:8]), '-'))
        n = len(ov.get('rules', {}))
        felder = sum(len(v) for v in ov.get('rules', {}).values())
        zeilen.append('   %s: %d/%d Regeln, %d uebersetzte Felder (%.0f %%)'
                      % (lang, n, len(ids), felder,
                         100.0 * n / len(ids) if ids else 0))
    return funde, zeilen


def pruefe_detectors_md(rules):
    """DETECTORS.md/_de/_fr sind laut README die "kanonische
    Detektor-Liste". Das Gate hielt bisher nur docs/rules.md nach -
    diese drei Dateien sind handgepflegt und drifteten still: Stand
    2026-08-20 fehlte SCA060 in ALLEN drei Fassungen (die Tabelle
    begann bei SCA061, obwohl die Ueberschrift 'SCA060-SCA119'
    versprach), und sechs Abschnitts-Zaehlungen waren falsch - teils
    widersprachen sich die Sprachfassungen sogar gegenseitig
    (162 vs. ~166 'detector kinds').

    Zwei Zusagen werden geprueft:
      1. jede Katalog-Regel kommt in einer Tabellenzeile vor;
      2. jede Ueberschrift, die '(N Regeln)' behauptet, listet auch N.
    Kombinierte Zellen ('| SCA034/SCA035 |') zaehlen fuer beide IDs -
    ein Detektor mit zwei Rule-IDs ist eine legitime Doku-Form.
    """
    ids = {r.get('id', '') for r in rules}
    zahl = re.compile(r'\((?:~)?(\d+)\s*(?:rules?|Regeln?|r[\u00e8e]gles?)\b')
    funde = []
    for name in ('DETECTORS.md', 'DETECTORS_de.md', 'DETECTORS_fr.md'):
        pfad = REPO / name
        if not pfad.exists():
            continue
        zeilen = pfad.read_text(encoding='utf-8-sig',
                                errors='replace').split(chr(10))
        gelistet = set()
        for z in zeilen:
            if z.startswith('|'):
                gelistet |= set(re.findall(r'SCA\d{3}', z))
        fehlt = sorted(ids - gelistet)
        if fehlt:
            funde.append((name, 'Regeln fehlen in der Tabelle',
                          ', '.join(fehlt)))
        grenzen = [i for i, z in enumerate(zeilen)
                   if z.startswith('## ')]
        grenzen.append(len(zeilen))
        for k in range(len(grenzen) - 1):
            von, bis = grenzen[k], grenzen[k + 1]
            m = zahl.search(zeilen[von])
            if not m:
                continue
            drin = set()
            for z in zeilen[von:bis]:
                if z.startswith('|'):
                    drin |= set(re.findall(r'SCA\d{3}', z))
            if int(m.group(1)) != len(drin):
                funde.append((name,
                              'Abschnitt behauptet %s, listet %d'
                              % (m.group(1), len(drin)),
                              zeilen[von].strip()[:70]))
    return funde


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--full', action='store_true',
                    help='ganze Texte statt Auszuege zeigen')
    args = ap.parse_args()

    rules, md = lade()
    kat_version = json.load(
        io.open(RULES_JSON, encoding='utf-8-sig')).get('version')
    funde, n_sec = pruefe(rules, md, args.full)
    funde += pruefe_konfidenz(rules)
    ov_funde, ov_zeilen = pruefe_overlays(rules, kat_version)

    grenze = 100000 if args.full else 110
    letzte = None
    for rid, was, ist, soll in funde:
        if rid != letzte:
            print()
            print(rid)
            letzte = rid
        print('   %s' % was)
        if ist != '-':
            print('      doku : %s' % str(ist)[:grenze])
        if soll != '-':
            print('      json : %s' % str(soll)[:grenze])

    for lang, was, ist, soll in ov_funde:
        print()
        print('rules/sca-rules.%s.json' % lang)
        print('   %s' % was)
        if ist != '-':
            print('      ist  : %s' % ist)
        if soll != '-':
            print('      soll : %s' % soll)

    print()
    print('Regeln im Katalog: %d   Abschnitte in docs/rules.md: %d'
          % (len(rules), n_sec))
    if ov_zeilen:
        print('Sprach-Overlays (Luecken sind erlaubt, Rueckfall auf '
              'Englisch):')
        for z in ov_zeilen:
            print(z)
    betroffen = len({f[0] for f in funde})
    if ov_funde and not funde:
        print('ABWEICHUNGEN: %d in den Sprach-Overlays.' % len(ov_funde))
        return 1
    if funde:
        print('ABWEICHUNGEN: %d in %d Regeln.' % (len(funde), betroffen))
        print('Der Katalog ist die Quelle - docs/rules.md zieht nach, '
              'ausser die Doku-Fassung ist nachweislich die bessere; dann '
              'wandert sie in die JSON.')
        return 1
    det_funde = pruefe_detectors_md(rules)
    if det_funde:
        print('ABWEICHUNGEN in der kanonischen Detektor-Liste '
              '(DETECTORS.md/_de/_fr): %d' % len(det_funde))
        for datei, was, detail in det_funde:
            print('   %-18s %s' % (datei, was))
            print('      %s' % detail)
        return 1
    print('GATE GRUEN: docs/rules.md und DETECTORS.md/_de/_fr decken '
          'sich mit dem Katalog.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
