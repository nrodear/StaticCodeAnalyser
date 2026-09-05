# -*- coding: utf-8 -*-
"""FP-Quoten-Uebersicht: Audit 2026-08-15 x aktuelle rw41-Fundzahlen.

Erzeugt Todo_FpUebersicht_2026-08-26.md (lokal, gitignored - .gitignore
Zeile 140 'Todo_*.md'; die Datei darf NICHT ins git).

Rechenweg bewusst explizit: Quote x Fundzahl = hochgerechnete FP-Masse.
Die Quote ist je Regel unterschiedlich belastbar - deshalb traegt jede
Zeile ihre BASIS (Vollzaehlung / Stichprobe / Rechnung / Schaetzung)
statt einer nichtssagenden "24".

Vier Konsumenten-Sichten statt "strict vs. default": die Fundmenge, die
ein Nutzer sieht, haengt an ZWEI unabhaengigen Filtern - dem Profil
(sca-rules.json) und dem Test-Fixture-Post-Filter des Console-Runners
(uConsoleRunner.pas:1519-1540). Nur die CLI mit analyser.ini hat beide.
"""
import glob
import io
import json
import os
import re
from fnmatch import fnmatchcase

import sys

# Portiert nach tools/ am 2026-09-05 (Charge 11): SARIF-Pfad und
# Lauf-Label kommen als Argumente; die fruehere rwNN_je_regel.tsv-
# Abhaengigkeit ist weg (Level/Konfidenz entstehen im selben
# Streaming-Pass wie die Fixture-Zaehlung). Aufruf:
#   python tools/fp_uebersicht.py <lauf.sarif> "rw66 vom 2026-09-05"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if len(sys.argv) < 3:
    sys.exit('Aufruf: fp_uebersicht.py <sarif> "<Label, z.B. rw66 vom 2026-09-05>"')
SARIF = os.path.abspath(sys.argv[1])
LABEL = sys.argv[2]
FIXTURE_CACHE = SARIF + '.je_regel_cache.tsv'

# Gruppen-Schwellen der Arbeitsliste. EINE Quelle - der Text in der
# Legende wird daraus formatiert, damit Code und Doku nicht auseinander
# laufen koennen.
G_QUOTE = 30.0      # ab hier: Praezisionsproblem (Gruppe A)
G_FUNDE = 5000      # ab hier: Volumenproblem (Gruppe B)


def de(n):
    """1234567 -> '1.234.567'."""
    return '{:,}'.format(n).replace(',', '.')


def pz(x, k=1):
    """Prozent mit deutschem Komma."""
    return ('%.*f' % (k, x)).replace('.', ',') + ' %'


# ========================================================================
# 0) Regelkatalog - EINZIGE Quelle fuer Name, Tier und Profil-Zugehoerigkeit
#    (utf-8-sig! die Datei traegt ein BOM). Das Audit-Markdown kennt nur
#    die 142 Regeln vom 15.08. - SCA197/198 kamen am 25.08. dazu und
#    fehlten deshalb in allen bisherigen Tier-Summen.
# ========================================================================
_kat = json.load(io.open(os.path.join(REPO, 'rules', 'sca-rules.json'),
                         encoding='utf-8-sig'))
KIND = dict((r['id'], r['kind']) for r in _kat['rules'])
# Der Katalog sagt 'Hint', SARIF und das Audit sagen 'Note' - dieselbe Stufe.
TIER = dict((r['id'],
             'Note' if r['defaultSeverity'] == 'Hint' else r['defaultSeverity'])
            for r in _kat['rules'])
ALLE_KINDS = set(KIND.values())
_PROFILE = _kat['profiles']


def profil_kinds(name):
    """TRuleCatalog.ParseProfileTokens (uRuleCatalog.pas:1176ff) 1:1.

    Leerer/unbekannter Name -> AllKinds (GetProfile, uRuleCatalog.pas:1158).
    Unbekannte Tokens werden still ignoriert - genau wie dort.
    """
    if name == '' or name not in _PROFILE:
        return set(ALLE_KINDS)
    aktiv = set()
    for t in _PROFILE[name]:
        if t == '*':
            aktiv = set(ALLE_KINDS)
        elif t[:1] in ('!', '-'):
            aktiv.discard(t[1:])
        elif t in ALLE_KINDS:
            aktiv.add(t)
    return aktiv


def profil_regeln(name):
    ks = profil_kinds(name)
    return set(rid for rid, k in KIND.items() if k in ks)


DEFAULT_AN = profil_regeln('default')
IDEFAST_AN = profil_regeln('ide-fast')
ALLES_AN = profil_regeln('')
# Die im Default-Profil abgeschalteten Regeln, die im Korpus ueberhaupt
# feuern - wird weiter unten auf die Fundmenge eingeschraenkt.
DEFAULT_AUS_KINDS = sorted(ALLE_KINDS - profil_kinds('default'))


# ========================================================================
# 1) Test-Fixture-Post-Filter nachgebaut
#    TDetectorUtils.IsTestFixturePath(FileName, BaseDir, tplFixture)
#    -> uDetectorUtils.pas:564-692, Musterliste TEST_PATH_RULES:584-633.
#    Aufrufer: uConsoleRunner.pas:1533 mit BaseDir = Args.Path (Scanwurzel),
#    aktiv wenn EffectiveHideTestFixtures (:1327-1333) - also bei Profil
#    'default' und 'selftest-quiet' automatisch.
#    Weil BaseDir die Scanwurzel ist und die SARIF-URI genau der dazu
#    RELATIVE Pfad ist, ist die URI exakt das 'RelLow' der Delphi-Routine.
# ========================================================================
# Mode tmBaseName, Levels enthalten tplFixture (die tplSecret-Muster sind
# eine andere Strenge-Stufe und gelten hier NICHT):
FIX_BASENAME = ['utest*.pas', '*_test.pas', '*_tests.pas', '*testsuite*.pas',
                '*sample.pas', '*_sample_*.pas', '*demo.pas', '*_demo_*.pas',
                'meineunit.pas', '*demo.dfm']
# Mode tmDirSegment, Levels enthalten tplFixture:
FIX_DIRSEG = set(['test', 'tests', 'unittest', 'unittests', 'samples',
                  'demos', 'resources'])
# tmSegmentStart traegt auf tplFixture keine einzige Regel ('unittest' dort
# ist tplSecret) - deshalb kein dritter Zweig.
# fkFileReadError ist vom Filter ausgenommen (uConsoleRunner.pas:1530);
# das ist Regel SCA006 (sca-rules.json: kind FileReadError).
FIX_AUSNAHME = set(['SCA006'])


def ist_fixture(rel_uri):
    low = rel_uri.replace('\\', '/').lower()
    bare = low.rsplit('/', 1)[-1]
    for muster in FIX_BASENAME:
        if fnmatchcase(bare, muster):        # MatchesMask ist case-insensitiv
            return True
    for seg in low.split('/'):               # RelLow.Split(['/'])
        if seg in FIX_DIRSEG:
            return True
    return False


def je_regel_pass():
    """Je Regel: (n, fixture, error, warning, note, high, medium, low).
    EIN Streaming-Pass ueber das SARIF (Volllauf > 700 MB); Cache neben
    dem SARIF, verworfen wenn das SARIF juenger ist. Die '"results"'-
    Schranke haelt den rules-Metadatenblock (defaultConfiguration.level!)
    aus der Zaehlung - die alte "level zaehlt rules-Block mit"-Falle."""
    if (os.path.exists(FIXTURE_CACHE)
            and os.path.getmtime(FIXTURE_CACHE) >= os.path.getmtime(SARIF)):
        d = {}
        for i, z in enumerate(io.open(FIXTURE_CACHE, encoding='utf-8')):
            if i == 0:
                continue
            f = z.rstrip('\n').split('\t')
            d[f[0]] = tuple(int(x) for x in f[1:9])
        return d

    re_rid = re.compile(r'"ruleId"\s*:\s*"([^"]+)"')
    re_uri = re.compile(r'"uri"\s*:\s*"([^"]*)"')
    re_lvl = re.compile(r'"level"\s*:\s*"(error|warning|note)"')
    re_cnf = re.compile(r'"confidence"\s*:\s*"(high|medium|low)"')
    LIDX = dict(error=2, warning=3, note=4, high=5, medium=6, low=7)
    ges = {}
    in_results = False
    cur = None    # Regel des laufenden Results bis zur ersten uri
    rid = None    # Regel des laufenden Results bis zum NAECHSTEN ruleId
                  # (confidence steht in properties HINTER den locations)
    for zeile in io.open(SARIF, encoding='utf-8'):
        if not in_results:
            if '"results"' in zeile:
                in_results = True
            continue
        if '"invocations"' in zeile:         # results sind durch
            break
        m = re_rid.search(zeile)
        if m:
            cur = m.group(1)
            rid = cur
            z = ges.setdefault(cur, [0, 0, 0, 0, 0, 0, 0, 0])
            z[0] += 1
            continue
        if rid is not None:
            m = re_lvl.search(zeile)
            if m:
                ges[rid][LIDX[m.group(1)]] += 1
                continue
            m = re_cnf.search(zeile)
            if m:
                ges[rid][LIDX[m.group(1)]] += 1
                continue
        m = re_uri.search(zeile)
        if m and cur is not None:
            u = m.group(1).replace('\\/', '/').replace('\\\\', '\\')
            if ist_fixture(u):
                ges[cur][1] += 1
            cur = None                       # nur die ERSTE uri je result
    o = io.open(FIXTURE_CACHE, 'w', encoding='utf-8')
    o.write('rule\tn\tfixture\terror\twarning\tnote\thigh\tmedium\tlow\n')
    for k in sorted(ges):
        o.write(k + '\t' + '\t'.join(str(x) for x in ges[k]) + '\n')
    o.close()
    return dict((k, tuple(v)) for k, v in ges.items())


JE_REGEL = je_regel_pass()
FIXTURE = dict((k, (v[0], v[1])) for k, v in JE_REGEL.items())


# ========================================================================
# 2) Audit-Quoten einlesen. Quote wird GERECHNET (100*fp/(tp+fp)), nicht
#    aus der gerundeten Textspalte gelesen - die Rundung des Audits geht
#    gerichtet nach unten (23 TP/1 FP steht dort als "4 %", exakt sind
#    4,17 %) und verkleinert damit systematisch die FP-Masse.
# ========================================================================
audit = {}
for zeile in io.open(os.path.join(
        REPO, 'Todo_FpQuotenJeDetektor_2026-08-15_FINAL.md'),
        encoding='utf-8'):
    if not zeile.startswith('| SCA'):
        continue
    sp = [x.strip() for x in zeile.strip().strip('|').split('|')]
    if len(sp) < 7:
        continue
    rid, name, tier = sp[0], sp[1], sp[2]
    tp = int(sp[4]) if sp[4].isdigit() else 0
    fp = int(sp[5]) if sp[5].isdigit() else 0
    if KIND.get(rid) != name:
        # Der Nachtrag vom 05.09. traegt eine ZWEITE |SCA|-Tabelle mit
        # anderen Spalten (Messung/Methode/...) - deren Zeilen tragen in
        # Spalte 2 kein Detektor-Kind und gehoeren nicht in die
        # historische Audit-Basis dieser Sektion.
        continue
    audit[rid] = dict(tp=tp, fp=fp,
                      quote=(100.0 * fp / (tp + fp)) if (tp + fp) else None)


# ========================================================================
# 3) Aktuelle Fundzahlen (rw23)
# ========================================================================
akt = {}
for rid, v in JE_REGEL.items():
    akt[rid] = dict(n=v[0], error=v[2], warning=v[3], note=v[4],
                    high=v[5], medium=v[6], low=v[7])


# ========================================================================
# 4) FP-Klassen aus den Einzelakten des Audits vom 15.08.
#    Fuer JEDE der 142 auditierten Regeln liegt eine Akte vor. Sie ist der
#    Grund, warum "nie untersucht" falsch waere: untersucht ist alles, nur
#    gebaut wurde nichts.
#    Neben der ANZAHL wird jetzt auch Name, Sample-Treffer und Fix-Idee
#    eingelesen - die Diagnose war bezahlt und stand trotzdem nicht in der
#    Uebersicht. Format der Akten (alle 162 Klassen halten es ein):
#      * **<Name>** (<n> im Sample)
#        * Mechanismus: ...
#        * Fix-Idee: ...
# ========================================================================
def kurz(text, n=200):
    """Erste Aussage eines Fix-Idee-Absatzes. Schneidet an der ersten
    Satz-/Klauselgrenze hinter 70 Zeichen, sonst hart am Wortende."""
    t = ' '.join(text.split())
    for tr in ('; ', '. ', ' - '):
        p = t.find(tr, 70)
        if 0 < p <= n:
            return t[:p].rstrip(' -') + ' ...'
    if len(t) <= n:
        return t
    return t[:t.rfind(' ', 0, n)] + ' ...'


FPKLASSEN = {}
AUDITKLASSEN = {}
for p in glob.glob(os.path.join(REPO, 'Todo_Funde_Detector_SCA*_2026-08-15.md')):
    rid = re.search(r'(SCA\d+)', os.path.basename(p)).group(1)
    txt = io.open(p, encoding='utf-8').read()
    m = re.search(r'^## FP-Klassen\s*$(.*?)(^## |\Z)', txt, re.S | re.M)
    body = m.group(1) if m else ''
    posten = []
    for bl in re.split(r'^\* \*\*', body, flags=re.M)[1:]:
        name = bl.split('**')[0].strip()
        smp = re.match(r'[^\n]*?\((\d+) im Sample', bl.split('**', 1)[1])
        fx = re.search(r'^\s*\* Fix-Idee:\s*(.*)$', bl, re.M)
        assert fx, 'Akte %s: Klasse "%s" ohne Fix-Idee' % (rid, name)
        posten.append((name, int(smp.group(1)) if smp else None,
                       kurz(fx.group(1))))
    FPKLASSEN[rid] = len(posten)
    AUDITKLASSEN[rid] = posten


# ========================================================================
# 4b) FP-KLASSEN mit HARTER Groesse: gebaut (A/B) oder ueber die
#     Grundgesamtheit gezaehlt (Klassenzaehlung 28.08., sieben Regeln,
#     Vorlage scratchpad/Entscheidung_Klassenzaehlung.md, Rohdaten im
#     Task-Output w7vv1nbd0).
#
#     Felder: (Regel, Klasse, Groesse, Herkunft, Verdikt, drop-only,
#              Gate-Idee, Grund/Notiz)
#
#     Herkunft - dieselbe Ehrlichkeitsachse wie die Spalte "Basis" bei den
#     Quoten, nur fuer Klassen:
#       A/B          Drop-Zahl aus einem Lauf gegen den Korpus. Haerteste
#                    Form, weil sie das GEBAUTE Gate misst.
#       VOLLZAEHLUNG jeder einzelne Fund der Regel wurde beurteilt und
#                    einer Klasse zugeordnet (bisher nur SCA001, 568
#                    Verdikte). Fuer die GROESSE einer Klasse ist das
#                    staerker als GEZAEHLT: dort wird ein Praedikat
#                    gemessen, hier die Klasse selbst - und "Praedikat !=
#                    Klasse" ist einer der drei belegten Fehlerarten.
#       GEZAEHLT     Praedikat ueber die GANZE Grundgesamtheit ausgezaehlt
#                    (Python-Replik). Beweist die Groesse, nicht das Gate.
#       GESCHAETZT   begruendet geraten.
#       LEER         nur benannt (Audit-Akte), keine Groesse.
#
#     Verdikt - die adversariale Gegenpruefung schlaegt die Zaehlung. Wo
#     Zaehlung und Gegenpruefung verschiedene Zahlen nennen, steht hier die
#     der Gegenpruefung und die andere im Grund.
#       GEBAUT      im Code, mit A/B belegt
#       gruen       Klasse bestaetigt, Gate baubar
#       gelb        Klasse real, Bauanleitung nachweislich falsch/unfertig
#       Vertrag     kein Gate, sondern eine offene Entscheidung ueber den
#                   Meldevertrag - danach neu zaehlen
#       rot         widerlegt - NICHT wieder aufgreifen ohne neuen Befund
#       ungeprueft  Zahl steht, kein Skeptiker hat draufgeschaut
#       erledigt    Klasse existiert nicht mehr
# ========================================================================
_KLASSEN = [
    # --- gebaut -------------------------------------------------------
    ('SCA106', 'Gate 7: Dual-Mode-Header mit `{$IFDEF}` ist kein '
     'Methodenkopf (die EINE Klasse der Audit-Akte)', 806, 'A/B', 'GEBAUT',
     'ja - 0 Adds',
     'kein nkMethod aus Deklarationen, die syntaktisch in einem var-/'
     'threadvar-Block stehen',
     'In rw23 enthalten (11.192 -> 10.386). Alle 806 stehen in EINER Datei '
     '(skia4delphi/Source/System.Skia.API.pas) - und beide FP der '
     '24er-Stichprobe standen dort. Die gemessene FP-Masse der Regel ist '
     'damit weg, die Restquote ist ein Extrapolationsrest ohne benannte '
     'Klasse'),
    ('SCA168', 'Parser verliert das vorhandene `case`-else nach einem Arm '
     'der Form `if ... then <stmt>;` (Audit-Klasse 1)', 148, 'A/B', 'GEBAUT',
     'ja',
     'ParseIfStmt: das `else` nur ans `if` binden, wenn kein `;` '
     'dazwischen konsumiert wurde',
     'In rw23 enthalten (9.730 -> 9.582). Lehrstueck zur Hochrechnung: die '
     '24er-Stichprobe rechnete diese Klasse auf ~405 Funde hoch, gezaehlt '
     'wurden 148 - Faktor 2,7 zu hoch. Die zweite Audit-Klasse '
     '(vollstaendig abgedeckter Boolean-Selektor) steht noch'),
    ('SCA091', 'K1 Tiefe-1-Gate in CountBranches PLUS Abstieg in '
     'geschachtelte `case`; dazu K2 record-Variantenteil (29), K6 '
     'Phantom-case (1), K3 inline-var, K5 goto-Label', 467, 'A/B', 'GEBAUT',
     'NEIN - 401 Adds',
     'Tiefe mitfuehren und `:` nur auf Tiefe 1 zaehlen; der Punkt-Schutz '
     'gegen qualifizierte Enum-Namen ist PFLICHT (ohne ihn faellt ein '
     'echter Fund)',
     'IN rw23 ENTHALTEN (1.944 -> 1.878). Die Zeile in '
     'der Tabelle oben zeigt weiter 1.944. Und es ist kein Gewinn, sondern '
     'ein TAUSCH: 1.944 -> 1.878, netto nur -66. Die 401 Adds sind die '
     'vorher unsichtbaren INNEREN case (der Scan sprang mit `pEnd + 3` '
     'hinter das end). Wer dieses Paket an der Drop-Zahl misst, haelt es '
     'faelschlich fuer gescheitert: die Fundzahl sinkt kaum, die '
     'Fundqualitaet deutlich'),
    ('SCA070', 'C Adapter-Doku-Header mit Routinenname unter 4 Zeichen',
     155, 'A/B', 'GEBAUT', 'ja - 0 Adds',
     'IsAdapterDocHeader: Laengenschwelle von 4 auf 2 senken - NICHT '
     'streichen, bei Laenge 1 kippt der Unterstrich-Anker messbar',
     'In rw23 enthalten (15.863 -> 15.708). Ehrlich zur Beweislage: die '
     '155 sind keine 155 unabhaengigen Belege - 40 verschiedene Faelle in '
     'vier fast identischen Kopien desselben Quellbaums, `add` allein '
     'traegt 76 Fundstellen'),

    # --- SCA001: VOLLZAEHLUNG aller 568 Restfunde (28.08.) --------------
    #     Als Block beisammen gelassen und nicht in die Verdikt-Gruppen
    #     einsortiert, weil diese 14 Klassen etwas sind, das es hier noch
    #     nie gab: eine GESCHLOSSENE PARTITION. Sie summieren sich exakt
    #     auf die 423 Roh-FP der Zaehlung (Assert unten) - jeder Fund
    #     gehoert genau einer Klasse, Doppelzaehlung ist ausgeschlossen.
    #     Vorlage: scratchpad/Vollzaehlung_SCA001.md; Rohverdikte im
    #     Task-Output w4gtx5bda (12 Pakete x verdikte[], 3 Gegenpruefungen).
    ('SCA001', 'A Besitzende Container-Senke: `.Add/.Insert/.AddPair/'
     '.Objects[i] :=/X[i] :=`, Zieltyp besitzt nachweislich', 113,
     'VOLLZAEHLUNG', 'gelb', 'ungemessen - kein A/B-Lauf',
     '**dateilokal** - Positivliste besitzender Containertypen '
     '(`TObjectList<T>`, `TObjectList` mit `Create(True)`, `TCollection`, '
     '`System.JSON`, `fpjson`, `TFPObjectList`) ODER unit-lokales Feld, '
     'dessen Konstruktion `OwnsObjects=True` belegt',
     'groesster Einzelposten der Regel (26,7 % aller FP) und trotzdem '
     'gelb: die naheliegende Fassung "Add unterdrueckt" ist WIDERLEGT. '
     '`TStrings.AddObject`, `TTreeNodes.AddChildObject` und `TTreeNode.Data` '
     'besitzen NICHT - dort liegen vier belegte TP (ftreeviewmenu:230, '
     'JvAlarmsForm:106, HashingExampleMain:236, main:3743), die ein '
     'generisches Gate frisst. Das `OwnsObjects`-Argument muss gelesen '
     'werden, niemals eine Namensheuristik; die Groesse der so verengten '
     'Fassung ist nicht separat gezaehlt'),
    ('SCA001', 'F Callee-Ownership UNIT-LOKAL: der Rumpf des Aufgerufenen '
     'steht in derselben Datei', 41, 'VOLLZAEHLUNG', 'GEBAUT',
     'GEMESSEN rw33 -> rw36: **-21**, null Adds, keine andere Regel bewegt',
     '**dateilokal** - Callee im selben File, Rumpf passt auf eine von drei '
     'Formen: `<owningList>.Add(Param)`, `Result := TX.Create(Owner)`, '
     '`Param.Free` als letzte Anweisung auf allen Pfaden',
     'DIE UEBERRASCHUNG DER ZAEHLUNG: F (41) ist groesser als das '
     'cross-unit-Gegenstueck G (35). Was wie Cross-Unit-Ownership aussieht, '
     'ist ueberwiegend unit-lokal - Paket 2 formuliert es am schaerfsten: '
     '7 von 9 Callee-Faellen stehen in derselben Datei. Ehrlich zur '
     'Beweislage: elf der 41 stammen aus einer einzigen Methode '
     '(`blcksock.DelayedOption`). '
     'GEBAUT 30.08., eingeloest sind **21 von 41** - Eindeutigkeitspruefung '
     'und Ein-Parameter-Schnitt kosten den Rest und bleiben. '
     'LEHRSTUECK ZUR HANDPRUEFUNG: von 24 Drops waren drei aus dem FALSCHEN '
     'Grund weg (`AList.Add(AItem)` in doublecmd uColorExt trifft ein '
     'TJSONArray, waehrend unit-lokal ein `TColorExt.Add(AItem: TMaskItem)` '
     'steht). Alle drei waren INHALTLICH FPs - das Gate lag im Ergebnis '
     'richtig und war trotzdem falsch gebaut. Die Maschinenzaehlung sah '
     'drei saubere Drops; erst Argumentzahl- und Empfaengertyp-Schnitt '
     'haben sie zurueckgeholt'),
    ('SCA001', 'E Interface-Refcount (Interface-Variable/-Feld/-Parameter, '
     '`Supports`, TInterfacedObject)', 35, 'VOLLZAEHLUNG', 'ungeprueft',
     'ungemessen - kein A/B-Lauf',
     '**dateilokal** (TTypeIndex) - Zielvariable/-feld/-parameter hat '
     'Interface-Typ, oder das Objekt geht durch `Supports()`, oder die '
     'Klasse leitet von `TInterfacedObject` ab',
     'TP-Risiko gering, aber nicht null: Klassen mit unterdruecktem '
     'Refcount (`TSingletonImplementation`-Muster) werden eben NICHT vom '
     'Refcount zerstoert - das Gate braucht eine Whitelist der '
     'Basisklassen. Die Audit-Akte vom 15.08. kannte von dieser Klasse nur '
     'den Supports-Fall (1 von 24) und hat sie damit auf ein Siebtel ihrer '
     'Groesse geschaetzt'),
    ('SCA001', 'G Callee-Ownership CROSS-UNIT: der Aufgerufene steht in '
     'einer anderen Unit', 35, 'VOLLZAEHLUNG', 'ungeprueft',
     'ungemessen - kein A/B-Lauf',
     '**K1** - Callee-Summary-Index ueber Unit-Grenzen (Selbstregistrierung '
     'im Ctor, Factory mit Owner, Callee versenkt das Argument)',
     'DAS IST DIE GANZE K1-AUSBEUTE DIESER REGEL - und sie widerlegt die '
     'Planzahl: veranschlagt waren ~128 Funde, gezaehlt sind es 35 (mit der '
     'auswertbaren Teilmenge von C hoechstens 45). Faktor 2,8 bis 3,7 zu '
     'hoch. K1 ist damit der teuerste Baustein mit dem drittkleinsten '
     'Ertrag und gehoert HINTER die dateilokalen Schritte'),
    ('SCA001', 'B Benannte Framework-Senke aus der `OwnershipSinks`-'
     'Registry (DMVC, mORMot)', 34, 'VOLLZAEHLUNG', 'gruen',
     'ungemessen - kein A/B-Lauf',
     '**dateilokal** - Aufruf steht in der bestehenden `[Detectors] '
     'OwnershipSinks`-Registry: DMVC `Render/OKResponse/Body(J,True)`, '
     '`SetContentStream`, `NewDataset(ds,True)`, mORMot `owndb=true` / '
     '`OwnerMustFree`',
     'billigster Posten der Regel: die per-Framework-Registry existiert '
     'bereits (Paket #5 OwnershipSinks), es kommen nur belegte Eintraege '
     'dazu. TP-Risiko nahe null, solange jeder Eintrag einzeln belegt ist. '
     'Ehrlich zur Beweislage: groesster Klumpen sind neun '
     'PerfBenchControllerU-Funde in ZWEI Vendorings derselben Datei'),
    ('SCA001', 'I Free steht im Rumpf, aber nicht im finally '
     '(lsWarning-Zweig)', 39, 'VOLLZAEHLUNG', 'GEBAUT',
     'rw27: 0 Drops / 0 Adds - kein Gate, nur Vertrag und Sichtbarkeit',
     '**ERLEDIGT 29.08. (Stufe 0).** Der Vertrag steht jetzt am Zweig '
     'selbst (uLeakDetector2): der Fall ist ein ECHTER Befund. Wer ein '
     'try/finally schreibt, erklaert den Block fuer ausnahmefest; ein Free '
     'daneben widerspricht dem. lsWarning steht dort, weil das Leck einen '
     'Ausnahmefall BRAUCHT - nicht, weil der Fund unsicher waere',
     'ZWEI ANNAHMEN DER VOLLZAEHLUNG WAREN FALSCH. (1) Der Meldetext eines '
     'SCA001-Funds ist NUR der Variablenname - der Satz "created but never '
     'freed", gegen den drei Auditoren argumentiert haben, ist die '
     'REGELBESCHREIBUNG und gilt fuer alle 568 gemeinsam; eine .po-Zeile '
     'haette gar nichts gerichtet. Gebaut wurde stattdessen '
     '`properties.variant` im SARIF plus eine praezisierte '
     'Regelbeschreibung (en/de/fr), beides fingerprint-neutral. '
     '(2) Die Klasse ist **70 Funde gross, nicht 59** - rw27 misst sie, '
     'statt sie zuzuordnen: 420 never-freed / 70 freed-outside-finally / '
     '78 return-value (die harte Zahl 78 stimmte auf den Fund). Elf Funde '
     'hatten die 12 Pakete als "nie freigegeben" gelesen, obwohl ein Free '
     'im Rumpf steht. Die Spanne 67,4-77,8 % haengt damit an 70 statt 59 '
     'Funden und ist etwas breiter. NEBENBEI ein Bestandsfehler gefunden: '
     'uFixHint leitete die Variante aus Severity ab, die die '
     'Evidenz-Politik vorher auf lsWarning deckelt (568 von 568) - der '
     'lsError-Zweig war seit 26.08. unerreichbar, jedes echte Leck bekam '
     'im HTML- und Text-Export den Hinweis auf ein Free, das es nicht '
     'gibt. Behoben ueber TLeakFinding.OriginalSeverity'),
    ('SCA001', 'L Feld-Pfad mit falschem Lebenszyklus-Anker (Alias-Feld, '
     'OnDestroy, class destructor, Dtor-Helfer, Kindliste)', 23,
     'VOLLZAEHLUNG', 'gelb', 'ungemessen - kein A/B-Lauf',
     '**dateilokal** - sechs Untermuster; die Freigabe steht woanders als '
     'im `Destroy` des Feldeigentuemers, deshalb sieht der Feld-Pfad sie '
     'nicht',
     'hier sitzt der EINE echte Urteilsfehler der ganzen Zaehlung, und er '
     'ist eine Bauauflage: `mormot.orm.storage.pas:1463` sieht aus wie '
     '"Dtor ruft Helfer, Helfer enthaelt FreeAndNil(fCache)" - der '
     'Waechter am Methodenanfang (`if Value = GetShutdown then exit` mit '
     '`GetShutdown = Assigned(fCache)`) macht das Free im Destruktorpfad '
     'aber unerreichbar. Es ist ein echtes Leck. Jedes Freigabe-Gate '
     'braucht deshalb die Zusatzbedingung "kein unbedingter Ausstieg '
     'zwischen Methodenanfang und Free"'),
    ('SCA001', 'C Zuweisung in Feld/Property eines FREMDEN Objekts (inkl. '
     'RTTI `SetValue`)', 22, 'VOLLZAEHLUNG', 'rot', 'entfaellt - kein Gate',
     '**12 nicht loesbar / 10 K1** - fuer die RTTI-Haelfte existiert kein '
     'entscheidbares Praedikat',
     'die Gegenpruefung verbietet hier ausdruecklich ein Loesch-Gate: bei '
     '`MVCFramework.Rtti.Utils` `lField.SetValue(lCloned, '
     'lTargetCollection)` (12 Funde in vier Paketen) steht per '
     'Konstruktion erst zur LAUFZEIT fest, welche Klasse das geklonte Feld '
     'traegt. Die uebrigen 10 sind K1-Gebiet (fremdes Feld, dessen Dtor im '
     'Korpus sichtbar ist, z.B. Json.Schema.Field.Arrays.pas:77). Als '
     'FP-Paket ist die Klasse tot - sie gehoert zur Bodenplatte der '
     'erreichbaren Quote, nicht zur Arbeitsliste'),
    ('SCA001', 'D TComponent-Owner: Ctor mit Owner-Argument, '
     '`InsertComponent`, TCollectionItem', 21, 'VOLLZAEHLUNG', 'gelb',
     'ungemessen - kein A/B-Lauf',
     '**dateilokal** - `IsOwnerParamCreate` kennt heute nur '
     '`Self/Owner/AOwner/Application`; erweitern auf jedes Argument, dessen '
     'Typ von `TComponent` abstammt, plus `inherited Create(Application)` '
     'im unit-eigenen Konstruktor',
     'TP-Risiko konkret und in EINER Datei belegt: in '
     '`HeidiSQL/source/grideditlinks.pas` liegen drei Owner-FP '
     '(130/170/174) und ein echtes TP (134) in DERSELBEN Klasse. Das Gate '
     'darf nur greifen, wenn im Create tatsaechlich ein Owner-Argument '
     'steht - nicht, wenn die Klasse "typischerweise" einen Owner hat'),
    ('SCA001', 'M Selbstfreigabe/Selbstregistrierung (FreeOnTerminate, '
     '`Done()`, Callback, Custom-Release, SmartPtr)', 15, 'VOLLZAEHLUNG',
     'ungeprueft', 'ungemessen - kein A/B-Lauf',
     '**dateilokal fuer 12** - das Objekt gibt sich selbst frei oder traegt '
     'sich in eine Struktur ein, die es selbst freigibt',
     'drei der 15 sind NICHT loesbar und stehen deshalb unten in der '
     'Bodenplatte: Kastri `DW.OSTimer` fuehrt eine Registry, deren '
     'Buchhaltung nachweislich fehlerhaft ist (IDs kollidieren nach '
     '`Delete` ohne Neunummerierung). Die Verallgemeinerung "Objekt '
     'uebergibt sich an eine selbstfreigebende Registry, also sicher" ist '
     'dort unbelegbar'),
    ('SCA001', 'H Kein Objekt allokiert (`TFileName`-Homonym, String-Alias, '
     'Create im Argument)', 14, 'VOLLZAEHLUNG', 'GEBAUT',
     'GEMESSEN rw31: **-13** (TFileName-Homonym)',
     '**dateilokal** - Homonym-Regel im TTypeIndex plus Typpruefung im '
     'Rueckgabewert-Pfad (`OwningReturnCall`, Praefix `Make...`), der heute '
     'GAR KEINE hat',
     'TP-Risiko exakt null, und die Ursache ist ein Selbstlaeufer: '
     '`TFileName = class(TObject)` in `jvcl/run/JvBaseThumbnail.pas:73` '
     'traegt sich per AutoDiscovery korpusweit in LeakyClasses ein - '
     'seitdem gilt jeder RTL-String vom Typ `TFileName` als '
     'Leck-Kandidat. Eine einzige Fremdunit vergiftet den RTL-Alias fuer '
     'den ganzen Korpus. Zusammen mit J der Schritt 1 der Vorlage: '
     '"kostet nichts, frisst nichts"'),
    ('SCA001', 'J Free IST da, der Erkenner sieht es nicht (inline var, '
     'Leerzeichen vor `.Free`, except-all)', 11, 'VOLLZAEHLUNG', 'gruen',
     'ungemessen - kein A/B-Lauf',
     '**dateilokal** - kein Gate, sondern drei Luecken im Free-Erkenner: '
     '`inline var`-Deklarationen, `BinaryBitmap      .Free` mit Leerraum '
     'vor dem Punkt, `except`-all-Zweige, Free im finally uebersehen',
     'die einzige Klasse der Regel, die keine Bewertungsfrage ist, sondern '
     'ein Fehler: der Detektor behauptet etwas, das der Quelltext '
     'woertlich widerlegt. TP-Risiko null - eine Reparatur des Erkenners '
     'kann keinen echten Fund kosten. Die Audit-Akte kannte davon nur den '
     'except-Fall (1 von 24)'),
    ('SCA001', 'N Escape (Result, out-Parameter, Deref-Pointer, Globale, '
     'Record-Feld)', 13, 'VOLLZAEHLUNG', 'ungeprueft',
     'ungemessen - kein A/B-Lauf',
     '**dateilokal fuer 8** - der Wert verlaesst die Routine sichtbar: '
     'Rueckgabe, out-Parameter, Zuweisung an eine Unit-/threadvar-Variable '
     'mit gepaartem Teardown in derselben Unit',
     'fuenf der 13 sind nicht loesbar: bei `mormot.core.json` '
     '`PPointer(data)^ := o` wandert der Besitz per Zeiger-Dereferenzierung '
     'ins Ziel des Aufrufers - wohin, weiss nur der Aufrufer. Die '
     'Audit-Akte kannte von dieser Klasse nur den threadvar-Cache '
     '(1 von 24)'),
    ('SCA001', 'K Free in einer nested Subroutine / anderen Methode / ueber '
     'einen Alias', 7, 'VOLLZAEHLUNG', 'ungeprueft',
     'ungemessen - kein A/B-Lauf',
     '**dateilokal** - die Freigabe steht in einer im selben Rumpf '
     'deklarierten Unterroutine oder laeuft ueber eine Aliasvariable',
     'kleinster dateilokaler Posten der Regel. Mit 7 Funden lohnt ein '
     'eigenes Gate nur als Nebenprodukt des Free-Erkenners aus Klasse J - '
     'allein gebaut ist es teurer als sein Ertrag'),

    # --- gezaehlt, gruen ----------------------------------------------
    ('SCA070', 'B Prosa-Satz ohne jede Pascal-Syntax (Changelog-Eintraege, '
     'Doku-Bullets)', 140, 'GEZAEHLT', 'gruen',
     'NEIN - `uCommentedOutCode.pas:222` fehlt die `(Result = 0)`-Wache '
     '(im Quelltext verifiziert); korpusweit 0 Adds gemessen',
     'zweiter Fruehausstieg in LooksLikeCommentedCode: Rumpf ohne jedes '
     'Pascal-Zeichen und ohne starkes Keyword',
     'NICHT WIDERLEGT, nur zurueckgestellt - Groesse und FP-Urteil sind '
     'exakt reproduziert. Nicht gebaut, weil sie (a) den Einzeiler-Vorfix '
     'in Zeile 222 braucht und (b) in ihrer Groesse an Klasse A haengt: '
     'ohne A sind es 508 statt 140. Benannte Luecke: Bezeichner-Kopf plus '
     'schwaches Keyword'),

    # --- gezaehlt, gelb (Klasse real, Bauanleitung falsch) ------------
    ('SCA070', 'A Prosa mit dem englischen Wort function/procedure',
     792, 'GEZAEHLT', 'gelb', 'ja - empirisch und strukturell bewiesen',
     'Fruehausstieg in LooksLikeCommentedCode, wenn kein `:=`, kein '
     'Semikolon am Ende und kein `begin` dasteht',
     'Groesse haelt (korr. ~790), das FP-Urteil "0 von 792" ist WIDERLEGT: '
     'mindestens 2 echte Funde (JclMetadata.pas:1993 ist das einzige '
     'Signal einer 40-Zeilen-Region, Win64SEH.pas:76), und die Stichprobe '
     'deckte nur 25 % ab. Dazu zwei Bau-Blocker: `Content/Lower/Trimmed` '
     'sind nicht im Scope, und `Trimmed[Length(Trimmed)]` ohne '
     'Leerstring-Wache ist ein AV bei jedem nackten `//` (3,7 % der '
     'Aufrufe). Zusatzbedingung noetig: keine Deklarations-/'
     'Zuweisungsgestalt'),
    ('SCA103', 'K2 Parameter-Fortsetzungszeile einer mehrzeiligen '
     'Methodendeklaration (Audit-Klasse)', 563, 'GEZAEHLT', 'gelb',
     'ja fuer den minimalen Port; der woertliche uPublicField-Port '
     'erzeugt +43 Adds',
     'Klammer-Balance ueber Zeilengrenzen fortschreiben und bei '
     'OpenParens > 0 nicht melden',
     'gezaehlt 565, korrigiert 563. Klasse real, Beweisfuehrung an drei '
     'Stellen falsch: die Klammern muessen auf ALLEN Zeilen fortgeschrieben '
     'werden, nicht nur auf denen mit Anfangswort. Kein lebender TP unter '
     'den 563, aber 111 blinde Unterdrueckungsfenster ueber 284 Zeilen, '
     'die heute nur zufaellig leer sind'),
    ('SCA146', 'A Pass-through: der Parameter steht in der if-Bedingung nur '
     'als Call-Argument (Audit-Klasse)', 200, 'GEZAEHLT', 'gelb', 'ja',
     'in IfStmtRefersToIdent den Treffer verwerfen, wenn er im '
     'Argument-Slot eines Aufrufs steht',
     'gezaehlt 195, korrigiert 200. Praedikat ist nicht die Klasse: ~19 von '
     '200 sind echte Funde (Array-Index `array[Boolean]`, `ord(writer and '
     '...)`, indizierte Property), und 7 sind per SEINER EIGENEN Definition '
     'gar keine Pass-throughs. HAUSINVARIANTE GEBROCHEN: Klammern in '
     'String-Literalen zaehlen als Code. Vier Auflagen vor dem Bau: '
     'Literale maskieren, Argument-Slot pruefen, Intrinsics/Typecasts '
     'ausschliessen, unbalancierte Conds verwerfen'),
    ('SCA176', 'bitweises and/or/xor (Integer-Maskentest) zaehlt als '
     'Boolean-Operator - vom Audit gar nicht gesehen', 132, 'GEZAEHLT',
     'gelb',
     'ja fuer die Fundmenge, NEIN fuer die Identitaet: 874 ueberlebende '
     'Funde wechseln den Meldetext (Score) und damit den Fingerprint',
     'in CountBooleanOpsInCond die Klammertiefe mitfuehren und je Tiefe '
     'merken, ob dort ein Relationaloperator vorkommt',
     'Groesse ja, Gate nein: 41 der 132 haben Strukturanteil 14-15, haengen '
     'also schon ohne Maskentest an der Schwelle 15 und fallen aus einem '
     'anderen Grund als dem gemeldeten. Belegte Fehlgriffe bei Generics '
     '(`IsType<T> and ...`) und `Bool = Bool`. Braucht vorher eine '
     'Baseline-Entscheidung'),
    ('SCA103', 'K4 Member eines anonymen Inline-Records im Feldtyp '
     '(Audit-Klasse)', 108, 'GEZAEHLT', 'gelb',
     'ja (108/0) - aber nur, weil der `InClass := False`-Fehler bewusst '
     'stehenbleibt; repariert man ihn, sind es 108 Drops und +20 Adds',
     'Tiefenzaehler fuer Inline-`record ... end` und Melde-Guard davor',
     'gezaehlt 106, korrigiert 108. Die Bauanleitung ist ein NO-OP: das '
     '`Inc` steht hinter `Results.Add`. Zusaetzlich bricht ein '
     'Kommentar-Treffer die Hausinvariante, und der Zaehler leckt in die '
     'Folgeklasse'),

    # --- gezaehlt, rot (Gegenpruefung hat gestrichen) -----------------
    ('SCA146', 'B1 override - "Signatur vom Vorfahren fixiert" '
     '(Audit-Klasse)', 338, 'GEZAEHLT', 'rot', 'ja (innerhalb SCA146)',
     'Deklarationsindex je Unit, Methoden mit `override` ueberspringen '
     '(wie SCA147 Gate D)',
     'Praedikat != Begruendung UND Messmodell != Motor. Die Begruendung '
     'gilt nur bei FREMDER API - gemessen haben 257 von 338 (76 %) die '
     'virtual-Basis im selben Repository, 168 (50 %) in derselben Datei. '
     'Echt fremd bleiben 81 = 0,010 % des Korpus. Dazu ist der Namens-'
     'Index (Klasse, Methode) nicht entscheidbar: 106 Overload-Schluessel '
     'mit unterschiedlichen Direktiven, Generics loeschen den Namen, '
     'IFDEF-Zwillinge teilen den Slot. Und: mit einem Text-Scanner '
     'gemessen, gegen den AST gebaut'),
    ('SCA146', 'H Event-Handler/Callback (`Sender: TObject` als erster '
     'Parameter)', 194, 'GEZAEHLT', 'rot', 'ja (im Korpus)',
     'erstes nkParam pruefen und die ganze Methode ueberspringen',
     'Praedikat != Begruendung. Die Zahl ist exakt, die Klasse nicht: 51 '
     'der 194 sind BEWEISBAR keine Event-Slots (34 lokale Direktaufrufe, '
     '16 ActionChange-Overrides), darunter 4 eindeutige echte Funde - '
     'preferences.pas:908 ist woertlich das Lehrbuchbeispiel aus dem '
     'Detektor-Kopf. Umgekehrt verfehlt das Kriterium 55 gleichgeformte '
     'Faelle, die nicht "Sender" heissen. Es ist eine Namensheuristik, '
     'keine Signaturpruefung - der belastbare Ersatz waere die '
     'BINDUNG (DFM-Event, `:=`, `@`)'),
    ('SCA146', 'G Guard-Prozedur: der ganze Rumpf ist EIN if auf den '
     'nackten Parameter', 52, 'GEZAEHLT', 'rot', 'ja',
     'genau ein nkIfStmt als einziges Statement-Kind, TypeRef gleich dem '
     'Parameternamen',
     'Praedikat != Gate UND Messmodell != Motor. Gezaehlt 40, das '
     'formulierte Gate frisst 52 - 12 davon liegen ausserhalb von Zaehlung '
     'UND Stichprobe. Woertlich implementiert ist es ausserdem ein NO-OP: '
     '`ParseBlock` haengt die Anweisungen unter ein `nkBlock`, `M` hat nie '
     'ein nkIfStmt-Kind. Genau die Falle, die SCA017 Gate B schon zum '
     'No-Op gemacht hat'),
    ('SCA146', 'C3 Check/Assert-Namensheuristik', 34, 'GEZAEHLT', 'rot',
     'ja', '-',
     'vom Zaehler SELBST abgelehnt: mindestens 6 der 34 sind echte '
     'Options-Flags. Wer die Assert-Faelle will, braucht ein '
     'strukturelles Kriterium, keinen Namen'),
    ('SCA146', 'D punktqualifiziertes Vorkommen (`Obj.Flag`) / E Parameter '
     'matcht nur in einem String-Literal', 6, 'GEZAEHLT', 'rot', 'ja', '-',
     'TP-Risiko null, aber ERTRAG null: alle 6 sind schon von B1/H '
     'gedeckt, E hat 0 Drops. Eine Klasse ohne Ertrag ist kein Paket'),
    ('SCA132', 'K3 Top-Level mit vollstaendigem Fehler-Report '
     '(Audit-Klasse 3)', 200, 'GEZAEHLT', 'rot', 'ja', '-',
     'Praedikat != Begruendung - nicht trennbar ohne Caller-Wissen. 562 '
     'von 1.174 Funden (48 %) erfuellen "Handler ist letzte Anweisung"; '
     'das ist der Normalfall, kein Merkmal. Beweis: JTouchUtils.pas:199 '
     '(Audit-FP) und ushellmoveoperation.pas:102 (Audit-TP) haben '
     'IDENTISCHEN Text - nur der Aufrufer entscheidet. Eigene 12er-'
     'Stichprobe: 5 klare TP gegen 2 klare FP, hochgerechnet 80-100 '
     'verlorene TP. Das ist K1-Gebiet (Callee-Summary-Index)'),
    ('SCA132', 'K5 Catch-all als letzter Arm nach spezifischen on-Armen',
     50, 'GEZAEHLT', 'rot', 'ja', '-',
     'Praedikat != Begruendung. 50 Funde sind nur 23 distinkte Stellen, '
     'und auf der EIGENEN Codebasis liegt das Praedikat 25/25 falsch '
     '(`on EStackExhausted do raise;` vor dem Catch-all ist Hausidiom, '
     'keine Domaenen-Aufzaehlung). Kippt still die test-verankerte '
     'Entscheidung TranslateToNewException_StillReported. Und: `TAstNode` '
     'hat keinen Parent-Zeiger, die Bauanleitung ist so nicht umsetzbar'),
    ('SCA132', 'K2b Protokoll-Grenze OHNE Log', 9, 'GEZAEHLT', 'rot', 'ja',
     '-',
     'vom Zaehler selbst von K2a abgetrennt und ausgeschlossen: enthaelt '
     'DW.UnitScan.pas:219, Zeichen fuer Zeichen das Muster, das das Audit '
     'anderswo als TP verurteilt hat (Scanner, der jeden Fehler inklusive '
     'EAccessViolation in ein Feld verwandelt). Ohne die Log-Bedingung '
     'faellt die Trennung in sich zusammen'),
    ('SCA176', 'else-if-Kettenglied erbt den Nesting-Zuschlag des '
     'umgebenden Konstrukts (Audit-Klasse 1)', 240, 'GEZAEHLT', 'rot',
     'NEIN - 1.462 bestehende Funde bekommen einen HOEHEREN Score '
     '(max +2165), korpusweit 172 NEUE Funde', '-',
     'doppelt gefallen. (i) Praedikat != Gate: gezaehlt 387, korrigiert '
     '240 - 147 der 387 liegen unter voller Sonar-Semantik weiter ueber '
     '15, 163 auf exakt 15. (ii) Es ist nicht drop-only; die quadratische '
     'Explosion von 12c5f15 kaeme zurueck'),
    ('SCA176', 'and/or/xor wird je TOKEN statt je Sequenz gezaehlt '
     '(Audit-Beobachtung 2)', 52, 'GEZAEHLT', 'rot',
     'NEIN - Baseline-Bruch fuer 2.640 Funde', '-',
     'Praedikat != Gate: das Messmodell sagte 279, die Bauanleitung '
     'liefert 52 (der Reset-Satz am Ende widerspricht dem gemessenen '
     'Modell), und 4 von 6 eigenen Stichproben bewegen sich unter der '
     'Bauanleitung um keinen Punkt'),
    ('SCA176', 'IFDEF-Doppelzaehlung: beide `{$IFDEF}`/`{$ELSE}`-Zweige '
     'werden gezaehlt', 61, 'GEZAEHLT', 'rot', 'NEIN', '-',
     'Messmodell != Motor. Kein Detektor-Gate, sondern `--ifdef-aware` per '
     'Default - und mit der ECHTEN Exe gemessen kostet das -18.358 / '
     '+2.041 ueber 43 Regeln, SCA166 allein +140 neue Uninit-FP, das '
     'Error-Tier steigt 1.099 -> 1.123. Die Wurzel ist ausserdem nicht '
     '"der Lexer skippt nicht", sondern dass `{$INCLUDE}` ignoriert wird: '
     '13.990 von 15.709 `{$DEFINE}` stehen in .inc-Dateien. Kein '
     'FP-Paket, ein Blindheits-Paket'),
    ('SCA103', 'K9 Feld eines record/object (Wertetyp) statt einer Klasse',
     268, 'GEZAEHLT', 'rot', 'ja', '-',
     'Praedikat != Begruendung: das ist eine POLITIKAENDERUNG, keine '
     'FP-Klasse. 260 der 268 stehen unter explizitem `private`, 255 in '
     'Typen mit Methoden - SCA103 trennt Member von Local im '
     'Methodenrumpf, und genau der Fall existiert im Advanced Record. '
     'Anders als bei SCA089 gibt es hier keinen "oeffentliches '
     'Record-Feld ist Idiom"-Anteil. Sieben Volltexte des Skeptikers = '
     'sieben echte Funde'),
    ('SCA070', 'G Blockkommentar hinter Code auf derselben Zeile',
     40, 'GEZAEHLT', 'rot', 'ja', '-',
     'vom Zaehler selbst nicht empfohlen, vom Skeptiker bestaetigt: 10 '
     'echte stillgelegte Statements plus 12 Grenzfaelle gegen 27 FP. Die '
     'verengte Fassung braechte 9 Drops von 15.863'),
    ('SCA129', 'K3f Codepage-Roundtrip MIT Fallabbildung '
     '(Upper/Lower/Title)', 8, 'GEZAEHLT', 'rot', 'ja', '-',
     'ausdruecklich NICHT bauen: Fallabbildung verlaesst die Codepage. '
     'CP1252 0xB5 (MICRO SIGN) wird zu U+039C GREEK CAPITAL MU, das es in '
     'CP1252 nicht gibt - genau der Verlust, den die Regel meldet. Diese '
     '8 sind FP nur unter einer Annahme ueber die Eingaben, und bei '
     'CnGroupReplace und FastCode ist die Annahme angreifbar'),

    # --- gezaehlt, ungeprueft (kein Skeptiker draufgeschaut) ----------
    ('SCA132', 'K1 Fremd-Fehlerkanal an der Slot-Grenze (Audit-Klasse 1, '
     'Rest nach dem ABI-Gate vom 21.08.)', 37, 'GEZAEHLT', 'ungeprueft',
     'ja',
     'Konverter-Durchreichung plus Leave-Muster als eigenstaendiges '
     'Suppress-Kriterium, ZWINGEND mit `override`-Bedingung',
     'ohne die `override`-Bedingung frisst das Gate 2 belegte TP '
     '(GX_CodeLib.pas:268 ist ein selbsterklaerter Schluck-Handler)'),
    ('SCA132', 'K4 anweisungsloser Handler - Doppelmeldung mit SCA159',
     33, 'GEZAEHLT', 'ungeprueft', 'ja, aber nur als Paket',
     '`if not HandlerDoesSomething(N) then Continue` - die Funktion liegt '
     'in der Unit bereits vor, der Einbau ist eine Zeile',
     'REIHENFOLGE IST PFLICHT: 6 der 33 kennt SCA159 nicht (dessen Regex '
     'verlangt hinter dem `do` ein `;` oder `begin end`). Erst die '
     'SCA159-Regex erweitern (+6), dann gaten (-33) - sonst faellt die '
     'Stelle ganz aus der Meldung'),
    ('SCA129', 'K1a Reinterpret-Cast auf TVarData/TVarRec-Pointerfeld',
     21, 'GEZAEHLT', 'ungeprueft', 'ja',
     'Suffixvergleich des Operanden gegen eine Feld-Whitelist, ohne '
     'Typ-Resolver',
     '`VText` ist bewusst NICHT in der Whitelist - mormot.db.sql.oledb.'
     'pas:227 deklariert es als `WideString` und waere ein echter Fund'),
    ('SCA103', 'K6 typisierte Klassen-Konstante in einer const-'
     'Untersektion (Audit-Klasse)', 30, 'GEZAEHLT', 'ungeprueft', 'ja',
     'auf der bereinigten Zeile: steht dort ein `=`, ist es keine '
     'Felddeklaration -> Continue (wortgleich zu uPublicField.LooksLikeField)',
     'strukturell 0 Risiko - Delphi kennt keinen Feld-Initialisierer, was '
     'mit `=` dasteht ist eine Deklaration. SCA089 faehrt dasselbe '
     'Praedikat seit dem 27.08.'),
    ('SCA146', 'B2 Interface-Implementierung, Interface in derselben Unit '
     'aufloesbar', 26, 'GEZAEHLT', 'ungeprueft', 'ja',
     'SCA147 Gate E nachbauen und AUSSCHLIESSLICH den aufgeloesten Zweig '
     'verwenden',
     '0 TP fuer den aufgeloesten Zweig; `ifsBlanket` (416 Funde) darf '
     'NICHT gebaut werden'),
    ('SCA070', 'E `(*$...*)`-Direktive wird als Kommentar gelesen',
     21, 'GEZAEHLT', 'ungeprueft', 'ja',
     'drittes Zustandsflag InDirective im Scanner, als reines '
     'Emissions-Gate',
     '0 TP - ein JPP-Makrorumpf ist per Definition lebender Code'),
    ('SCA129', 'K3 Codepage-Roundtrip ohne Fallabbildung (Audit-Klasse)',
     18, 'GEZAEHLT', 'ungeprueft', 'ja',
     'Blattpruefung ueber den Operandentext - nur Exit, wenn JEDES '
     'wertliefernde Blatt eine bewiesene 8-bit-Hebung oder ein '
     'ASCII-Literal ist',
     'die Blattregel ist NICHT optional: die erste Fassung des Praedikats '
     'hat IdHTTPWebBrokerBridge.pas:455 gefressen, einen echten Fund '
     '(Index-Falle - die Hebung steht im Suchschluessel, der gecastete '
     'Wert kommt aus einem HTTP-Header)'),
    ('SCA070', 'D Doku-Header mit zitierter Signatur (DIE vom Audit '
     'benannte Klasse)', 16, 'GEZAEHLT', 'ungeprueft', 'ja',
     'IsApiDocSignature als vierter FP-Schutz, STRENGE Fassung',
     'die lose Fassung frisst die 22 zlibh.pas-TP; die strenge liegt bei 0'),
    ('SCA132', 'Logger-Idiome erweitern (Nachtrag des Skeptikers)',
     14, 'GESCHAETZT', 'ungeprueft', 'ja',
     'Faelle der Form `WriteError(...); ExitCode := 1; Exit;` - das '
     'Leave-Merkmal steht in der Datei',
     'einzige Klasse dieser Runde mit einer GESCHAETZTEN Groesse - "~14" '
     'ist nicht ausgezaehlt'),
    ('SCA070', 'F Prosa, die Code in doppelten Anfuehrungszeichen zitiert',
     14, 'GEZAEHLT', 'ungeprueft', 'ja',
     'StripBacktickCodeSpans auf doppelte Anfuehrungszeichen erweitern - '
     'in ScoreCodeMarkers UND HasStrongCodeMarker, sonst laufen Score und '
     'Strong-Test auseinander',
     '1 strittiger Verlust (JvToolEdit.pas:1852)'),
    ('SCA146', 'C1 Ternary-Utility (IfThen/iif/Iff), Boolean ist der '
     'Auswahlwert (Audit-Klasse, Teil 1)', 34, 'GEZAEHLT', 'ungeprueft',
     'ja', 'Namens-Tail gegen eine Konstantenliste, Boolean als erster '
     'Parameter - Liste im Detektor, nicht in der INI',
     '0 TP, alle 34 Namen durchgesehen'),
    ('SCA132', 'K2a Protokoll-Grenze MIT Log (Audit-Klasse 2)', 7,
     'GEZAEHLT', 'ungeprueft', 'ja',
     'HasLeave zusaetzlich setzen bei Zuweisung auf ein Protokoll-'
     'Fehlerfeld, aber NUR mit Log-Bedingung',
     '0 TP bei allen 7 einzeln gelesenen Faellen; die Log-Bedingung ist '
     'das, was K2a von K2b trennt'),
    ('SCA129', 'K1b Reinterpret-Cast auf Pointer-/PAnsiChar-Variable',
     7, 'GEZAEHLT', 'ungeprueft', 'ja',
     'deklarierten Typ des Operanden aufloesen und bei Pointertyp Exit',
     'PChar und PWideChar duerfen NICHT in die Liste: `AnsiString('
     'PWideChar(x))` konvertiert wirklich, 3 belegte TP im Korpus'),
    ('SCA103', 'K1 Zeile im Innern eines Blockkommentars', 7, 'GEZAEHLT',
     'ungeprueft', 'ja, wenn nur der Zustand genutzt wird',
     'StripLineStateful AUSSCHLIESSLICH als Stummschalter - die bereinigte '
     'Zeile darf nicht in die Extraktion',
     'der woertliche uPublicField-Port erzeugt +42 Adds'),
    ('SCA129', 'K5 Operand ist bereits 8-bit deklariert (No-op-Cast)',
     5, 'GEZAEHLT', 'ungeprueft', 'ja',
     'ASCII_SAFE_OPERAND_PREFIXES von der Cast-Schreibweise auf den '
     'DEKLARIERTEN Typ erweitern',
     'gefaehrlichste der SCA129-Klassen: codepage-parametrisierte Aliase '
     '(`OemString = type AnsiString(CP_OEMCP)`, `RawUnicode`, `RawUtf8`) '
     'sind echte Konverter und wuerden gefressen'),
    ('SCA129', 'K8 Inline-var mit ASCII-Produzent als Initialisierer',
     4, 'GEZAEHLT', 'ungeprueft', 'ja',
     'Prefix-Gate um eine Indirektionsstufe erweitern',
     'die Pruefung auf Zwischenzuweisungen ist PFLICHT, nicht Kuer; '
     'FloatToStr/DateToStr/CurrToStr duerfen nicht in die '
     'Produzentenliste (FormatSettings)'),
    ('SCA129', 'K4 Wert am Fundort beweisbar ASCII (ClassName/UnitName)',
     3, 'GEZAEHLT', 'ungeprueft', 'ja', 'Suffix-Whitelist im Operandentest',
     'im Korpus 0 Risiko (keine Nicht-ASCII-Klassennamen gefunden); mit 3 '
     'Funden den Bauaufwand kaum wert'),
    ('SCA129', 'K6 untypisierter var-Parameter als Operand', 1, 'GEZAEHLT',
     'ungeprueft', 'ja', 'Parameterliste der umgebenden Routine pruefen',
     'strukturell 0 Risiko - ein untypisierter var-Parameter hat keinen '
     'statischen Typ, der Cast kann definitionsgemaess nichts '
     'konvertieren. Preis: die Klasse ist genau 1 Fund gross'),

    # --- erledigt ------------------------------------------------------
    ('SCA129', 'K2 UTF8String-Ziel (Audit-Klasse)', 0, 'GEZAEHLT',
     'erledigt', '-', '-',
     'seit dem 16.08. geschlossen, 0 Treffer - nichts zu bauen. Steht hier, '
     'damit niemand sie aus der Audit-Akte erneut aufgreift'),
]

_VERDIKT_RANG = {'GEBAUT': 0, 'gruen': 1, 'gelb': 2, 'Vertrag': 3,
                 'ungeprueft': 4, 'nur benannt': 5, 'rot': 6, 'erledigt': 7}
_HERKUNFT_RANG = {'A/B': 0, 'VOLLZAEHLUNG': 1, 'GEZAEHLT': 2,
                  'GESCHAETZT': 3, 'LEER': 4}
_ZAEHLREGELN = ['SCA146', 'SCA091', 'SCA132', 'SCA129', 'SCA176', 'SCA103',
                'SCA070']
# Regeln, deren Klassen aus einer Fund-fuer-Fund-Vollzaehlung stammen. Sie
# stehen BEWUSST nicht in _ZAEHLREGELN: alle Summen und Lehrsaetze, die
# oben an der Klassenzaehlung vom 28.08. haengen (4.685 gezaehlte
# Fehlalarme, -1.884 in der Gegenpruefung, 40 %), gelten fuer jene sieben
# Regeln und wuerden mit einer zweiten Methode im selben Topf unlesbar.
_VOLLZAEHLREGELN = ['SCA001']

# ------------------------------------------------------------------
# SCA001, Vollzaehlung 28.08. - die Eckdaten an EINER Stelle, damit die
# Quote unten, die Klassentabelle und die Lesetexte nicht auseinander
# laufen koennen.
#   568 Verdikte (12 Pakete; ausgezaehlt aus den Verdikt-LISTEN, nicht aus
#   den Paket-Kopfzeilen - deren Summe sagt 567 und ist um eins zu
#   niedrig). Roh 423 FP / 145 TP. Drei adversariale Gegenpruefungen haben
#   115 Verdikte neu aufgemacht und 8 gekippt, alle acht FP -> TP.
# ------------------------------------------------------------------
_S1_N = 568
_S1_ROH_FP = 423           # Summe der 14 Klassen - Assert weiter unten
_S1_KIPP = 8               # dokumentierte Kipps der Gegenpruefung
_S1_GEPRUEFT = 115         # davon gegengeprueft
# Die Spanne: der Kippgrund der sieben lsWarning-Kipps klassenweit
# angewandt (= 383/185) gegen den woertlichen Meldetext (= 442/126).
_S1_FP_MIN, _S1_FP_MAX = 383, 442

# ENTSCHIEDEN 29.08. (Stufe 0): der lsWarning-Vertrag steht jetzt am
# Zweig selbst - "Free vorhanden, aber neben dem finally" ist ein ECHTER
# Befund. Damit ist die Spanne kein Ermessen mehr, sondern ihre UNTERE
# Grenze ist die Arbeitszahl. Herleitung: von den 39 Funden, die neun
# Pakete als FP gezaehlt hatten, waren 7 bereits in den 8 Kipps
# enthalten - 415 - 32 = 383.
#
# rw27 MISST die Klasse ausserdem, statt sie zuzuordnen
# (properties.variant): sie ist 70 Funde gross, nicht 59. Wie die elf
# zusaetzlichen von den Paketen einzeln bewertet wurden, geht aus deren
# Verdikten nicht hervor - deshalb bleibt es bei 383 und wird NICHT
# weitergerechnet. Die wahre Zahl duerfte etwas niedriger liegen.
_S1_FP = _S1_FP_MIN                     # 383, vorher 415 (Vertrag offen)
_S1_TP = _S1_N - _S1_FP                 # 185

# ------------------------------------------------------------------
# EINGELOEST seit der Vollzaehlung: Funde, die ein Gate seither
# entfernt hat. Sie fallen aus BEIDEN Zahlen - aus der Grundgesamtheit
# UND aus den FPs. Wer nur die Fundzahl nachzieht und die Quote stehen
# laesst, rechnet mit Faellen weiter, die es nicht mehr gibt: genau das
# ist hier bis zum 30.08. passiert (die Quote stand auf 383/568 =
# 67,4 %, obwohl die 13 TFileName-Funde laengst weg waren).
#   (Klasse, Anzahl, Lauf, Beleg)
# ------------------------------------------------------------------
_S1_EINGELOEST = [
    ('H', 13, 'rw31', 'TFileName-Homonym - es wird gar kein Objekt '
                      'allokiert'),
    ('F', 21, 'rw36', 'unit-lokaler Callee uebernimmt; alle 24 Drops des '
                      'ersten Laufs von Hand geprueft, drei davon waren '
                      'aus dem falschen Grund weg und haben zwei '
                      'Nachschaerfungen erzwungen'),
    ('D',  6, 'rw41', 'Owner-Argument ueber den TYP statt ueber eine '
                      'Namensliste; das Veto verlangt, dass die ERZEUGTE '
                      'Klasse eine Komponente sein kann'),
    ('L',  3, 'rw41', 'OnDestroy-Event als Freigabeort, mit '
                      'Event-Signatur als Bedingung'),
    ('L',  2, 'rw41', 'BESTANDSFEHLER: class destructor traegt den TypeRef '
                      '"destructor;class" und wurde von FindMethod nie '
                      'gefunden'),
    # Sammel-Eintrag (Portierung 2026-09-05): die September-Chargen im
    # SALDO 523 -> 482. Darin verrechnet: Klasse-J-Gruppen 1/5/6 (E2,
    # 02.09.), die AQL-Fixserie, der GuardAdvance-Parser-Recall (dessen
    # SCA001-ADDS hier gegenlaufen) und K-nested -4 (rw62, exakt
    # vertragsgeprueft). Die lauf-genaue Klassen-Attribution steht in
    # den vertrag_rwNN.md der Chargen - sie hier je Zwischenlauf
    # nachzubauen waere Scheinpraezision aus dem Gedaechtnis.
    ('Sammel-Sept', 41, 'rw45-rw66', 'Saldo der September-Chargen '
                      '(J-Gruppen, AQL-Fixserie, GuardAdvance-ADDS '
                      'gegenlaufend, K-nested); Details in den '
                      'Bewegungsvertraegen der Chargen'),
]
_S1_WEG      = sum(x[1] for x in _S1_EINGELOEST)    # 34
_S1_N_HEUTE  = _S1_N - _S1_WEG                      # 534
_S1_FP_HEUTE = _S1_FP - _S1_WEG                     # 349

# Selbstkontrolle: die Rechnung MUSS die gemessene Fundzahl treffen.
# Tut sie es nicht, ist entweder ein Gate gebaut worden, ohne es hier
# einzutragen, oder eine Einloesung war keine.
assert _S1_N_HEUTE == akt['SCA001']['n'], (
    'SCA001-Rechnung %d != Korpus %d - fehlt eine Einloesung in '
    '_S1_EINGELOEST?' % (_S1_N_HEUTE, akt['SCA001']['n']))

# Loesbarkeit je Klasse - vier Toepfe, per Assert an die Groessen in
# _KLASSEN gebunden, damit die beiden Listen nicht auseinanderlaufen.
# (Klasse, dateilokal, K1/cross-unit, gar nicht loesbar, Vertragsfrage)
# Die Vorlage nennt als Schlagzeile "dateilokal 327 = 77,3 %".
# Nachgerechnet geht das nicht auf: die 5 Deref-Escapes aus N und die 3
# nichtdeterministischen Registry-Faelle aus M stehen dort ZUGLEICH unter
# "nicht loesbar", und die Schrittliste der Vorlage summiert selbst nur
# 322. Diese Datei fuehrt die Partition, die auf 423 aufgeht, und nennt
# die Spanne - an der Groessenordnung ("rund drei Viertel") aendert das
# nichts.
_SCA001_LOESBAR = [
    ('A', 113, 0, 0, 0),
    ('B', 34, 0, 0, 0),
    ('C', 0, 10, 12, 0),
    ('D', 21, 0, 0, 0),
    ('E', 35, 0, 0, 0),
    ('F', 41, 0, 0, 0),
    ('G', 0, 35, 0, 0),
    ('H', 14, 0, 0, 0),
    ('I', 0, 0, 0, 39),
    ('J', 11, 0, 0, 0),
    ('K', 7, 0, 0, 0),
    ('L', 23, 0, 0, 0),
    ('M', 12, 0, 3, 0),
    ('N', 8, 0, 5, 0),
]
_S1_KL = dict((k[1].split(' ')[0], k[2])
              for k in _KLASSEN if k[0] == 'SCA001')
assert len(_S1_KL) == len(_SCA001_LOESBAR) == 14, \
    'SCA001: %d Klassen in _KLASSEN, %d in _SCA001_LOESBAR' \
    % (len(_S1_KL), len(_SCA001_LOESBAR))
assert set(_S1_KL) == set(x[0] for x in _SCA001_LOESBAR), \
    'SCA001: Klassenbuchstaben uneins %r' % (
        set(_S1_KL) ^ set(x[0] for x in _SCA001_LOESBAR),)
for _b, _dl, _k1, _nl, _vt in _SCA001_LOESBAR:
    assert _S1_KL[_b] == _dl + _k1 + _nl + _vt, \
        'SCA001-Klasse %s: Loesbarkeit summiert %d, _KLASSEN sagt %d' \
        % (_b, _dl + _k1 + _nl + _vt, _S1_KL[_b])
_S1_DL = sum(x[1] for x in _SCA001_LOESBAR)     # 319 dateilokal
_S1_K1 = sum(x[2] for x in _SCA001_LOESBAR)     #  45 cross-unit
_S1_NL = sum(x[3] for x in _SCA001_LOESBAR)     #  20 nicht loesbar
_S1_VT = sum(x[4] for x in _SCA001_LOESBAR)     #  39 Vertragsfrage
assert _S1_DL + _S1_K1 + _S1_NL + _S1_VT == _S1_ROH_FP, \
    'SCA001-Loesbarkeit summiert %d statt %d' \
    % (_S1_DL + _S1_K1 + _S1_NL + _S1_VT, _S1_ROH_FP)
assert sum(_S1_KL.values()) == _S1_ROH_FP, \
    'SCA001-Klassen summieren %d statt %d' % (sum(_S1_KL.values()),
                                              _S1_ROH_FP)
# Die K1-Neubewertung in einer Zeile - beide Zahlen werden im Lesetext
# gebraucht und duerfen nicht getippt werden.
_K1_ALT = 128
_S1_K1_SICHER = dict((x[0], x[2]) for x in _SCA001_LOESBAR)['G']  # 35 = G
_K1_FAKTOR_MIN = _K1_ALT / float(_S1_K1)            # 2,8 (mit C-Teilmenge)
_K1_FAKTOR_MAX = _K1_ALT / float(_S1_K1_SICHER)     # 3,7 (nur G)

# Welche Klassen der Audit-Akte vom 15.08. sind durch die harten Daten oben
# schon abgedeckt? Ohne diese Zuordnung stuende die gebaute SCA106-Klasse
# unten noch einmal als "nur benannt, nie gemessen" - und jemand haette sie
# ein zweites Mal aufgegriffen. 'alle' = die Zaehlung hat die ganze Akte
# eingeholt (fuer die sieben gezaehlten Regeln einzeln nachgeprueft).
_AUDIT_GEDECKT = dict((r, 'alle') for r in _ZAEHLREGELN)
_AUDIT_GEDECKT['SCA106'] = set([0])     # IFDEF-Doppeldeklaration = Gate 7
_AUDIT_GEDECKT['SCA168'] = set([0])     # Parser-case-else; Klasse 1 bleibt
# SCA001: alle sieben Akten-Klassen sind in den 14 Klassen der Vollzaehlung
# aufgegangen - Container/indizierte Zuweisung = A, fremder Ctor/Owner = D,
# Property-Alias = L, Free im except = J, Record-Ctor/RTTI-Referenz = H,
# modul-globaler Cache = N, Supports() = E. Einzeln nachgeprueft.
_AUDIT_GEDECKT['SCA001'] = 'alle'



# Verhaeltnis der harten Daten zur Audit-Akte - je Regel EINE Zeile. Ohne
# sie liest sich die Klassentabelle so, als haette das Audit all das benannt.
_ZAEHL_NOTIZ = {
    'SCA106': 'Die Akte nannte GENAU EINE Klasse - sie ist als Gate 7 '
              'gebaut. Was die Restquote von ~1,2 % traegt, hat niemand '
              'benannt; die naechste ehrliche Handlung ist eine '
              'Nachmessung an den 10.386 Restfunden, keine weitere '
              'Hochrechnung.',
    'SCA168': 'Die Akte nannte 2 Klassen mit je einem Sample-Treffer. Die '
              'erste (Parser-Bug) ist gebaut, die zweite steht unten und '
              'ist nie gezaehlt worden.',
    'SCA146': 'Die Akte vom 15.08. nannte 3 Klassen (Pass-through = A, '
              'Override = B1, "Boolean ist Datenwert" = C1/C2/C3); die '
              'Zaehlung fand 7 weitere. Keine der 3 Audit-Klassen '
              'ueberlebt die Gegenpruefung in ihrer Audit-Form.',
    'SCA091': 'Die Akte nannte 1 Klasse (Nested-case-Aggregation = K1) - '
              'gebaut. Vier weitere kamen beim Zaehlen dazu und sind im '
              'selben Paket erledigt.',
    'SCA132': 'Die Akte nannte 3 Klassen (Python-C-API = K1, '
              'Dispatcher-Grenze = K2, Top-Level-Report = K3). K3 ist '
              'widerlegt, K1 und K2a sind ungeprueft; K4 und K5 fand erst '
              'die Zaehlung.',
    'SCA129': 'Die Akte nannte 4 Klassen (Pointer/PAnsiChar = K1a/K1b, '
              'UTF8String = K2 (erledigt), Roundtrip = K3, ASCII-Wert = '
              'K4); K5/K6/K8 kamen dazu. KEINE einzige Klasse dieser Regel '
              'ist gegengeprueft.',
    'SCA176': 'Die Akte nannte 2 Klassen - beide widerlegt. Die einzige '
              'ueberlebende (bitweise Maskentests) hat die Akte gar nicht '
              'gesehen. Regel komplett zurueckstellen.',
    'SCA103': 'Die Akte nannte 3 Klassen (Fortsetzungszeile = K2, private '
              'const = K6, Inline-Record = K4); K9 und K1 fand erst die '
              'Zaehlung, und K9 stellte sich als Politikfrage heraus.',
    'SCA070': 'Die Akte nannte GENAU EINE Klasse (Doku-Header mit '
              'zitierter Signatur = D). Die Zaehlung fand sechs weitere. '
              'Das ist der schaerfste Beleg der Runde dafuer, dass eine '
              '24er-Ziehung eine 4-%-Klasse nicht sehen kann.',
}
_ZAEHL_NOTIZ['SCA001'] = (
    'SONDERFALL, und der Unterschied ist der Punkt: bei den sieben Regeln '
    'oben ist je EIN PRAEDIKAT ueber die Grundgesamtheit gezaehlt worden - '
    'hier wurde JEDER EINZELNE der %s Funde beurteilt (12 Pakete, %s '
    'Verdikte, drei adversariale Gegenpruefungen ueber %d davon). Die 14 '
    'Klassen sind deshalb eine geschlossene Partition: sie summieren sich '
    'exakt auf die %s ROH-FP. Die Quote in den Tabellen oben fuehrt '
    'dagegen %s - acht Verdikte hat die Gegenpruefung gekippt, alle acht '
    'von FP nach TP (sieben aus Klasse I, einer aus L).\n\n'
    'Die Akte vom 15.08. nannte %d Klassen; die Vollzaehlung hat alle %d '
    'wiedergefunden und sieben weitere danebengestellt (B, C, F, G, I, K, '
    'M). Die Klassenliste des Audits war also richtig - falsch war die '
    'GEWICHTUNG, und genau darauf beruht jede Bauentscheidung.\n\n'
    '**Loesbarkeit - die eigentliche Nachricht: dateilokal %s von %s '
    '(%s), K1/cross-unit %d, gar nicht loesbar %d, Vertragsfrage %d.** Die '
    'Vorlage nennt als Schlagzeile 327 dateilokal (77,3 %%); nachgerechnet '
    'sind es %d bis 322, weil die fuenf Deref-Escapes aus N und die drei '
    'nichtdeterministischen Registry-Faelle aus M dort zugleich unter '
    '"nicht loesbar" stehen. Die Tabelle fuehrt die Partition, die auf %s '
    'aufgeht. An der Groessenordnung aendert der Streit nichts: rund drei '
    'Viertel der Fehlalarme dieser Regel fallen OHNE jeden '
    'Cross-Unit-Index.\n\n'
    'Reihenfolge aus der Vorlage: Schritt 0 der lsWarning-Vertrag (Klasse '
    'I - null Zeilen Detektorlogik, aber ohne ihn misst die naechste Runde '
    'wieder etwas anderes), Schritt 1 H+J (25 Funde, TP-Risiko null), '
    'Schritt 2 A (113 - der grosse Hebel), Schritt 3 F (41), Schritt 4 der '
    'Rest in absteigender Groesse. K1 kommt DANACH.'
    % (de(_S1_N), de(_S1_N), _S1_GEPRUEFT, de(_S1_ROH_FP), de(_S1_FP),
       len(AUDITKLASSEN['SCA001']), len(AUDITKLASSEN['SCA001']),
       de(_S1_DL), de(_S1_ROH_FP), pz(100.0 * _S1_DL / _S1_ROH_FP),
       _S1_K1, _S1_NL, _S1_VT, _S1_DL, de(_S1_ROH_FP)))

_kseen = {}
for _k in _KLASSEN:
    assert len(_k) == 8, 'Klassen-Tupel mit %d Feldern: %r' % (len(_k), _k[:2])
    assert _k[0] in KIND, 'unbekannte Regel in _KLASSEN: %s' % _k[0]
    assert _k[3] in _HERKUNFT_RANG, 'Herkunft %r bei %s' % (_k[3], _k[0])
    assert _k[4] in _VERDIKT_RANG, 'Verdikt %r bei %s' % (_k[4], _k[0])
    _sl = (_k[0], _k[1][:40])
    assert _sl not in _kseen, 'Klassen-Dublette %s' % (_sl,)
    _kseen[_sl] = 1
    # Eine nicht gebaute Klasse OHNE Grund ist genau der Fehler, den diese
    # Tabelle verhindern soll - dann greift die naechste Runde sie erneut
    # auf oder laesst eine berechtigte liegen.
    assert _k[7] and len(_k[7]) > 30, 'Klasse ohne Grund: %s / %s' % _sl
_HARTE_REGELN = sorted(set(k[0] for k in _KLASSEN))
for _r in _ZAEHLREGELN + _VOLLZAEHLREGELN:
    assert _r in _HARTE_REGELN, 'keine Klasse fuer %s' % _r
# Die beiden Beweisarten duerfen sich nicht vermischen - sonst wandern
# Vollzaehl-Klassen in die Summen der Klassenzaehlung (und umgekehrt).
assert set(_ZAEHLREGELN) & set(_VOLLZAEHLREGELN) == set(), \
    'Regel steht in beiden Zaehl-Listen'
for _k in _KLASSEN:
    assert (_k[3] == 'VOLLZAEHLUNG') == (_k[0] in _VOLLZAEHLREGELN), \
        'Herkunft %r passt nicht zur Zaehl-Liste bei %s' % (_k[3], _k[0])
for _r in _HARTE_REGELN:
    assert _r in _ZAEHL_NOTIZ, 'keine Audit-Notiz fuer %s' % _r
    assert _r in _AUDIT_GEDECKT, 'keine Audit-Zuordnung fuer %s' % _r
assert set(_ZAEHL_NOTIZ) == set(_HARTE_REGELN) == set(_AUDIT_GEDECKT)


def klassen_von(rid):
    return [k for k in _KLASSEN if k[0] == rid]


def audit_offen(rid):
    """Klassen der Audit-Akte, die von den harten Daten NICHT abgedeckt
    sind - (Name, Sample-Treffer, Fix-Idee)."""
    ged = _AUDIT_GEDECKT.get(rid, set())
    if ged == 'alle':
        return []
    return [p for i, p in enumerate(AUDITKLASSEN.get(rid, []))
            if i not in ged]



#    keine Gruppe: ob eine Regel schon angefasst wurde, sagt nichts
#    darueber, wie schlecht sie heute ist).
# ========================================================================
GEFIXT = {
    'SCA003': 'Konventions-Gates 26.08. (84->64; Klassen 5+6 offen)',
    'SCA109': 'Audit-FP-Klassen 26.08. (40->35, Rest fcHigh)',
    'SCA121': 'goto-Parserfix 16.08. (126->101), Gates verifiziert',
    'SCA166': 'Typname-/out-Merge-/Label-Fix 26.08. (30->22)',
    'SCA001': 'fcMedium-Demote + Quick-Wins A 27.08. (587->568; '
              'Closure/AsObject/FreeOnTerminate); VOLLZAEHLUNG aller 568 '
              'Restfunde 28.08. - der Zusatz "Rest -> K1" stand hier bis '
              'dahin und ist widerlegt: 319 der 423 FP sind dateilokal, '
              'nur 35-45 sind K1',
    'SCA072': 'Vier Gates 27.08. (725->400)',
    'SCA173': 'In-Loop-Gate + fcMedium 27.08. (613->332)',
    'SCA071': 'Kommentar-Zustand 27.08. (196->25)',
    'SCA016': 'Drei Gates 27.08. (134->26)',
    'SCA088': 'Token-Walk-Neubau 27.08. (168->21, +6 TP)',
    'SCA151': 'Escape-Scan 27.08. (180->51, +3 TP)',
    'SCA017': 'Gate A+D 27.08. (3.887->2.899) - Restquote UNSICHER',
    'SCA008': 'fcMedium + S-Paket-Gates 27.08. (48->30); Arm-Exklusivitaet '
              '28.08. nachgezogen (0 Adds gemessen, Fundzahl unbewegt); '
              'M-Paket offen',
    'SCA106': 'Gate 7 (Dual-Mode-Header) 28.08. (11.192->10.386, -806) - '
              'Audit-Quote GEGENSTANDSLOS, Restquote UNSICHER',
    'SCA168': 'case-else-Parserfix 28.08. (9.730->9.582, -148) - '
              'Audit-Quote GEGENSTANDSLOS, Restquote neu gerechnet',
    'SCA115': 'Fuenf Gates 27.08. (176->86)',
    'SCA118': 'Basisklassen-Gate 27.08. (85->22)',
    'SCA018': 'else-if-Gate 27.08. (6.035->3.708) + eine FP-Beseitigung '
              '28.08. (3.708->3.707)',
    'SCA054': 'Vier Gates 27.08. (13.959->12.448), GATE E 30.08. (12.448->5.014)',
    'SCA144': 'Waechter-Idiom-Gate 30.08. (441->421). Nur die enge Form '
              '"if v = 0 then v := x"; die 116 Vergleiche auf BERECHNETE '
              'Werte bleiben zu Recht',
    'SCA097': 'TObject-Basis-Demote 30.08.: 94 von 161 error->warning, 67 '
              'bleiben error. Error-Tier des Korpus 1.098->1.004',
    'SCA004': 'Drei Gates 27.08. (16->10)',
    'SCA193': 'Dekodier-Gate 27.08. (3->1)',
    'SCA011': 'Detektorfix 4e2a248 16.08. (132->59) - die Audit-Quote von '
              '54 % gilt fuer die ALTE Grundgesamtheit',
    'SCA047': 'Detektor-Umbau 19./20.08. (134->30) - die Audit-Quote von '
              '83 % gilt fuer die ALTE Grundgesamtheit',
    'SCA053': 'Parser-Root-Fix 26.08. (-75 Phantome)',
    'SCA119': 'Record-Const-Parserfix 25.08.',
    'SCA110': 'Literal-Fix 25.08. (+12 echte Funde)',
    'SCA089': 'Lex-Sanierung 26.08. + published/=-Gates rw18 (8.234->4.111)',
    'SCA123': 'Operand-Gate 26.08. (604->146)',
    'SCA086': 'G1-G4-Gates + fcLow 26.08.: Default 0, '
              'opt-in ~5.800 Rest (~57 % Vendoring)',
    'SCA117': 'Aktennotiz 27.08.: KEIN Code - beide Gate-Vorschlaege in der '
              'Gegenpruefung durchgefallen, einer haette Funde ADDIERT',
    # Diese beiden sind seit rw23 IN der Messung (gebaut nach 03dcdfc,
    # Fundzahl in der Zeile ist die VOR dem Gate - das muss dranstehen,
    # sonst rechnet jemand die FP-Masse zweimal ab.
    'SCA091': 'Tiefe-1-Gate + Abstieg in geschachtelte case 28.08. '
              '(1.944 -> 1.878: 467 Drops, aber 401 Adds - ein TAUSCH, kein '
              'Abbau) - in rw23 enthalten, die Fundzahl links ist die NACH '
              'dem Gate',
    'SCA070': 'Adapter-Doku-Header 28.08. (15.863 -> 15.708, -155) - NOCH '
              'in rw23 enthalten, die Fundzahl links ist die NACH dem Gate',
}


# ========================================================================
# 6) Quoten, die NICHT die rohe Audit-Stichprobe sind.
#    Als LISTE gefuehrt und mit Assert auf Dubletten geprueft - im
#    Vorgaenger stand SCA089 zweimal (42,0 / 2,0) und SCA008 zweimal
#    (92,0 / 87,0); Python nahm still den letzten, und bei SCA089 war das
#    ein Copy-Paste-Unfall (die "40 von 40"-Vollzaehlung gehoert zu
#    SCA117, siehe Merge-Notiz fp-massen).
#    Felder: (Regel, Quote %, Basis-n, Art, Herkunft)
#    Art: Vollzaehlung | Stichprobe | Rechnung | Schaetzung
# ========================================================================
_ABGELEITET = [
    # Vollzaehlungen werden als BRUCH geschrieben, nicht als gerundete
    # Prozentzahl - sonst weicht Quote x n um ein paar Funde von der
    # tatsaechlich gezaehlten Menge ab (SCA117: 2,66 % x 89.240 = 2.374
    # statt der gezaehlten 2.376).
    ('SCA117', 100.0 * 2376 / 89240, 89240, 'Vollzaehlung',
     'byte-genaue Detektor-Replik ueber alle 89.240 Funde in 6.270 Dateien '
     '(Autopsie 27.08.): F6 mehrzeiliger Doku-Block 615 + F7 nachgestellter '
     'Doku-Kommentar 1.771, Vereinigung 2.376. Die konkurrierende Zahl '
     '"40 von 40 korrekt" ist eine 40er-Stichprobe auf der WORTLAUT-Ebene '
     'und misst etwas anderes; die Audit-Quote 4,17 % stammt aus 24 Faellen. '
     'Untergrenze eines Skeptikers: nur F6 = 0,69 %'),
    ('SCA001', 100.0 * _S1_FP_HEUTE / _S1_N_HEUTE, _S1_N_HEUTE, 'Vollzaehlung',
     'jeder einzelne der 568 Restfunde beurteilt (28.08., 12 Pakete): roh '
     '423 FP / 145 TP, nach den acht Kipps der drei Gegenpruefungen 415 FP '
     '/ 153 TP. Damit ist die staerkste Datenlage dieser Datei erreicht - '
     'und trotzdem UNSICHER, in BEIDE Richtungen: die belastbare Spanne '
     'ist 67,4 bis 77,8 %. Dazwischen liegen die 39 strittigen Verdikte '
     'der lsWarning-Klasse ("Free steht im Rumpf, aber nicht im finally"), '
     'die die 12 Pakete ohne gemeinsamen Vertrag bewertet haben. '
     'Kippgrund klassenweit angewandt (lsWarning = TP): 383/185 = 67,4 %. '
     'Meldetext woertlich genommen (lsWarning = FP): 442/126 = 77,8 %. '
     'Diesen Streit loest keine weitere Messung, sondern eine Entscheidung '
     '- siehe Klasse I im Klassenabschnitt. Abgeloest wird eine '
     'Stichprobe: 62,5 % aus 24 Faellen, also ~355 FP; die FP-Masse dieser '
     'Regel STEIGT durch die Zaehlung um 60'),
    ('SCA089', 42.0, 4187, 'Rechnung',
     'Audit-FP-Masse 71 % x 8.234 = ~5.846 minus ~4.100 am Korpus belegte '
     'FP-Drops (rw12+rw13b: Signatur-Fortsetzungen, Kommentar-Zustand, '
     'record/object, FPC-"public name") -> ~1.750 auf 4.187'),
    ('SCA123', 51.0, 146, 'Rechnung',
     '88 % x 604 = ~532 FP minus 458 Drops mit dokumentiertem Preis 1 TP '
     '-> ~74 auf 146'),
    ('SCA115', 24.0, 86, 'Rechnung',
     'Vollklassifikation aller 176 rw16-Funde (110 FP / 66 TP) minus 90 '
     'Gate-Drops -> ~20 auf 86 Restfunde. Die Restklasse (Anzeigetext in '
     'const/resourcestring) ist ohne Cross-Unit-Symbolindex nicht trennbar'),
    ('SCA017', 44.0, 2899, 'Rechnung',
     'Audit-FP-Masse 2.254 minus 988 belegte Drops -> ~1.266 auf 2.899. '
     'UNSICHER: die 58-%-Audit-Quote beruht zu einem Gutteil auf der '
     'zwischen zwei Schlichtungen STRITTIGEN Konsolen-UI-Lesart'),
    ('SCA008', 87.0, 30, 'Rechnung',
     '~44 Audit-FP minus 18 belegte Drops -> ~26 auf 30 Funde. Das M-Paket '
     '(Flag-Korrelation, TypeIndex-Alias) ist kartiert, nicht gebaut'),
    ('SCA011', 100.0 * 2 / 59, 59, 'Vollzaehlung',
     'alle 59 Funde einzeln geprueft (27.08.): 57 TP / 2 FP, von einem '
     'Skeptiker mit eigenem Korpuslauf unabhaengig reproduziert'),
    ('SCA047', 0.0, 30, 'Vollzaehlung',
     'alle 30 Funde einzeln geprueft (27.08.): 30 TP / 0 FP'),
    ('SCA004', 100.0 * 7 / 10, 10, 'Vollzaehlung',
     'alle 10 Restfunde nach den drei Gates: 3 TP / 7 FP'),
    ('SCA193', 0.0, 1, 'Vollzaehlung',
     'der eine Restfund nach dem Dekodier-Gate ist ein TP'),
    ('SCA071', 4.0, 25, 'Schaetzung',
     'alle 25 Restfunde am Korpus als echter Code gesichtet (0 FP); die '
     '4 % sind ein bewusster Aufschlag von einem Fund, keine Messung'),
    ('SCA088', 2.0, 21, 'Schaetzung',
     'alle 21 Restfunde als echte Legacy-Inits verifiziert (0 FP); 2 % als '
     'Restrisiko-Aufschlag'),
    ('SCA072', 6.0, 19, 'Stichprobe',
     'Scout-Sample nach den vier Gates: 1 FP / 18 Keeps'),
    ('SCA173', 12.5, 24, 'Stichprobe',
     'Rest-FP-Sample nach Gate A: 3 FP / 24'),
    ('SCA151', 8.0, 13, 'Stichprobe',
     '13 der 51 Keeps gesichtet, 0 FP; Callback-Konstanten bleiben als '
     'Grauzone stehen - 8 % als Aufschlag darauf'),
    ('SCA016', 32.0, 26, 'Schaetzung',
     '26 Restfunde, davon 7-10 in der Sonden-/Fallback-Grauzone '
     '(Skeptiker-Korrektur)'),
    ('SCA118', 20.0, 22, 'Schaetzung',
     '22 Keeps, davon ~6 aus maschinengenerierten Fremd-Headern '
     'grenzwertig (Skeptiker-Korrektur an der 0-%-Schlagzeile)'),
    # 30.08.: 200er-Stichprobe (seed 20260830) aus rw32, klassifiziert und
    # in vier Faellen am Quelltext verifiziert. Die alte Schaetzung von
    # 6,0 % lag um FAKTOR 10 daneben - dieselbe Fehlerart wie bei SCA011
    # und SCA047, nur diesmal in die andere Richtung und mit Messung
    # dagegen.
    ('SCA054', 36.5, 5014, 'Stichprobe 200',
     'GATE E (Prozedurwert) ist GEBAUT und hat 7.434 der 12.448 Funde '
     'genommen (-59,7 %, 0 Adds, rw33). Die Quote hier gilt fuer den REST: '
     'von 200 Stichprobenfunden trugen 123 (62 %) eine fremdbestimmte '
     'Signatur - die sind jetzt weg; 73 (36 %) blieben Kandidaten fuer '
     'echte Funde, und das ist die Quote der verbliebenen 5.014. UNSICHER '
     'nach unten: in den 73 stehen weitere Verdaechtige (eine '
     'Python-C-API-Signatur ist darunter), nur kein maschinell fassbares '
     'Muster mehr. Die Audit-Akte vom 15.08. hatte GATE E uebrigens schon '
     'vorgeschlagen - Klasse 1, Fix-Idee woertlich "Adressnahme/Methodenwert-'
     'Verwendung als Signatur-Bindung werten". Sie fand sie in 2 von 24 '
     'Sample-Faellen (8 %); gemessen sind es 62 %. Die Akte hatte recht, sie '
     'hat nur um Faktor 8 zu klein geschaetzt'),
    # 28.08.: Gate 7 bzw. der case-else-Parserfix haben bei beiden Regeln
    # die Grundgesamtheit ausgetauscht. Die Audit-Quote 8,3 % (2 FP / 24)
    # gilt fuer eine Menge, die es nicht mehr gibt - dieselbe Lage wie bei
    # SCA011 und SCA047, nur diesmal mit den Akten in der Hand.
    # 30.08.: 200er-Stichprobe (seed 20260830). Hier war NICHTS zu bauen,
    # und das ist das Ergebnis - nicht das Ausbleiben eines Ergebnisses.
    ('SCA018', 0.0, 3707, 'Stichprobe 200',
     'ERKENNUNG FEHLERFREI. 200 Funde gegen die Quelltext-Einrueckung '
     'plausibilisiert: 92 % passen, in NULL Faellen zaehlt der Detektor zu '
     'hoch. else-if-Ketten zaehlen korrekt als EINE Verzweigung, '
     'try/finally zaehlt nicht mit - beides am Quelltext nachgeprueft. Die '
     '0,0 % heissen NICHT "keine Fehlalarme", sondern "kein '
     'ERKENNUNGSfehler": ob Tiefe 5 zu tief ist, entscheidet die Schwelle '
     '(MAX_DEPTH=4; Tiefe 5 macht 68 % der Funde). Das ist Konfiguration, '
     'kein Detektorproblem - hier ist nichts zu gaten'),
    # 30.08. aus dem Fremdkorpus SVGIconImageList, beide GEBAUT und am
    # Referenzkorpus gemessen.
    ('SCA106', 100.0 * 127 / 10386, 10386, 'Rechnung',
     'Audit-FP-Masse 8,33 % x 11.192 = ~933 minus die 806 am Korpus '
     'belegten Gate-7-Drops -> ~127 auf 10.386. UNSICHER, und zwar nach '
     'unten: die Audit-Akte nennt GENAU EINE FP-Klasse (IFDEF-Doppel'
     'deklaration - Funktionszeiger-Variable im var-Block als Methode '
     'gemeldet), und BEIDE FP der Stichprobe stehen in derselben Datei '
     'skia4delphi/Source/System.Skia.API.pas, die Gate 7 geraeumt hat. '
     'Der Artefaktanteil 806/11.192 = 7,2 % deckt sich fast genau mit der '
     'Audit-Quote 8,3 %. Die gemessene FP-Masse ist damit vollstaendig '
     'weg; die verbleibenden ~127 sind ein Extrapolationsrest ohne '
     'benannte Klasse und liegen innerhalb der Streuung einer '
     '2-von-24-Stichprobe. Belastbar ist nur: deutlich unter 8,3 %, '
     'moeglicherweise 0 - eine Nachmessung an den 10.386 Restfunden steht '
     'aus'),
    ('SCA168', 100.0 * 663 / 9582, 9582, 'Rechnung',
     'Audit-FP-Masse 8,33 % x 9.730 = ~811 minus die 148 belegten Drops '
     'des case-else-Parserfixes -> ~663 auf 9.582. Diese Rechnung geht '
     'NICHT sauber auf, und das ist hier die eigentliche Information: die '
     'Audit-Akte nennt ZWEI FP-Klassen mit je einem Treffer - den '
     'Parser-Bug (jetzt raus) und den vollstaendig abgedeckten '
     'Boolean-Selektor `case B of True/False` (bleibt, kein Gate gebaut). '
     'Klassenweise gerechnet bliebe nur die zweite Klasse: 1 von 24 = '
     '4,17 % -> ~399. Die Luecke entsteht, weil die Stichprobe die '
     'Parser-Klasse auf 1/24 x 9.730 = ~405 Funde hochrechnete, gezaehlt '
     'wurden aber 148 - Faktor 2,7 zu hoch. Die Tabelle fuehrt die '
     'konservativere Zahl; die ehrliche Spanne ist 4,2 bis 6,9 %'),
]
_seen = {}
for _e in _ABGELEITET:
    assert _e[0] not in _seen, (
        'ABGELEITET-Dublette %s: %r vs %r - Python haette still den letzten '
        'genommen' % (_e[0], _seen[_e[0]], _e[1]))
    _seen[_e[0]] = _e[1]
ABGELEITET = dict((e[0], e[1:]) for e in _ABGELEITET)


# ========================================================================
# 7) Zeilen bauen
# ========================================================================
zeilen = []
for rid in sorted(set(audit) | set(akt) | set(KIND)):
    a = audit.get(rid, {})
    k = akt.get(rid, {})
    n = k.get('n', 0)
    n_fix = FIXTURE.get(rid, (0, 0))[1]
    if rid in FIX_AUSNAHME:
        n_fix = 0
    if rid in ABGELEITET:
        q, basis, art, herkunft = ABGELEITET[rid]
    elif a.get('quote') is not None:
        q, basis, art = a['quote'], a['tp'] + a['fp'], 'Stichprobe'
        herkunft = 'Voll-Audit 15.08., %d TP / %d FP im Detail' % (a['tp'],
                                                                   a['fp'])
    else:
        q = basis = art = herkunft = None
    zeilen.append(dict(
        rid=rid, name=KIND.get(rid, '?'), tier=TIER.get(rid, '?'),
        n=n, n_fix=n_fix, n_ohne_fix=n - n_fix,
        err=k.get('error', 0), warn=k.get('warning', 0), note=k.get('note', 0),
        high=k.get('high', 0), med=k.get('medium', 0),
        quote=q, basis=basis, art=art, herkunft=herkunft,
        fpm=(int(round(n * q / 100.0)) if (q is not None and n) else None),
        fpm_nutzer=(int(round((n - n_fix) * q / 100.0))
                    if (q is not None and n) else None),
        fix=GEFIXT.get(rid, ''),
        klassen=FPKLASSEN.get(rid)))
Z = dict((z['rid'], z) for z in zeilen)


def basis_txt(z):
    if z['art'] is None:
        return '-'
    if z['basis'] is None:
        return z['art']
    return '%s %s' % (z['art'], de(z['basis']))


def klassen_kurz(rid):
    """Verdikt-Bilanz der noch OFFENEN gezaehlten Klassen einer Regel, fuer
    die Spalte Stand. Die gebauten stehen ohnehin schon in GEFIXT; und eine
    blosse Anzahl wuerde wieder verschweigen, wie viele davon die
    Gegenpruefung gekippt hat."""
    zahl = {}
    offen = [k for k in klassen_von(rid) if k[4] != 'GEBAUT']
    for k in offen:
        zahl[k[4]] = zahl.get(k[4], 0) + 1
    teile = ['%d %s' % (zahl[v], v)
             for v in ('gruen', 'gelb', 'Vertrag', 'ungeprueft', 'rot',
                       'erledigt')
             if v in zahl]
    if not teile:
        return ''
    # Die Vollzaehlung ist eine andere Beweisart als die Klassenzaehlung -
    # das muss auch in der Kurzform stehen, sonst liest sich beides gleich.
    kopf = ('Vollzaehlung 28.08.'
            if all(k[3] == 'VOLLZAEHLUNG' for k in offen)
            else 'Klassen ausgezaehlt 28.08.')
    return kopf + ': ' + ' / '.join(teile)


def stand_txt(z):
    kk = klassen_kurz(z['rid'])
    if z['fix']:
        return z['fix'] + (' -- ' + kk if kk else '')
    if kk:
        return kk
    if z['klassen'] is None:
        return 'nicht im Audit vom 15.08. (Regel kam am 25.08. dazu)'
    if z['klassen'] == 0:
        return 'Audit 15.08., kein Gate gebaut (keine FP-Klasse benannt)'
    return ('Audit 15.08., kein Gate gebaut (%d FP-Klasse%s benannt)'
            % (z['klassen'], 'n' if z['klassen'] > 1 else ''))


# ========================================================================
# 8) Sichten
# ========================================================================
def sicht(regeln, fixture_filter):
    """(Funde, FP-Masse) einer Konsumenten-Sicht."""
    n = f = 0
    for z in zeilen:
        if z['rid'] not in regeln:
            continue
        nn = z['n_ohne_fix'] if fixture_filter else z['n']
        n += nn
        if z['quote'] is not None:
            f += int(round(nn * z['quote'] / 100.0))
    return n, f


SICHTEN = [
    ('CLI ohne analyser.ini, ohne --profile', '- (keins)', 'nein',
     ALLES_AN, False,
     'TRepoSettings-Default FProfile = \'\' (uRepoSettings.pas:1270); '
     'GetProfile(\'\') liefert AllKinds (uRuleCatalog.pas:1166). '
     'EffectiveHideTestFixtures bleibt False. Deckungsgleich mit dem '
     'Messlauf, weil das Profil `strict` (`["*","UnusedUses"]`) ebenfalls '
     'alle Kinds anschaltet'),
    ('CLI mit analyser.ini `Profile=default`', 'default', 'JA',
     DEFAULT_AN, True,
     'Args.Profile ueberschreibt Settings.Profile (uConsoleRunner.pas:1130), '
     'also gilt dasselbe fuer `--profile default` auf der Kommandozeile: '
     'mit dem Profil springt EffectiveHideTestFixtures an (:1331-1333) und '
     'der Post-Filter loescht jeden Fund in einer Fixture-Datei (:1519-1540)'),
    ('Standalone-Form', 'default', 'nein', DEFAULT_AN, False,
     'PopulateProfileCombo faellt auf \'default\' zurueck '
     '(uMainForm.pas:3613); den Fixture-Post-Filter gibt es NUR im '
     'Console-Runner'),
    ('IDE-Plugin', 'ide-fast', 'nein', IDEFAST_AN, False,
     'TRepoSettings.IdeProfile-Default = \'ide-fast\' '
     '(uRepoSettings.pas:1275)'),
]

ges_n = sum(z['n'] for z in zeilen)
ges_fpm = sum(z['fpm'] for z in zeilen if z['fpm'] is not None)
ges_fix = sum(z['n_fix'] for z in zeilen)
# Selbst nachgerechnet, nicht geglaubt - mit einem ZWEITEN Verfahren
# (chk_rw20_fixture.py: auf die Einrueckung verankertes `match` statt des
# rw23: der Wert aendert sich mit jedem Gate, das Fixture-Funde trifft.
# Erst nachrechnen, dann hier eintragen (alter Wert rw20: 195.014).
FIXTURE_ERWARTET = -1   # parametrischer Betrieb (Portierung 05.09.): keine feste rw41-Zahl mehr - der Lauf DRUCKT den Wert, die Plausibilitaet prueft der Leser gegen den Vorlauf   # rw36 = rw33 (Klasse F traf keine
                            # Fixture-Datei); rw23 war 194.845.
                            # NACHGERECHNET je Regel, nicht durchgewunken:
                            #   SCA054 -2.525  (GATE E, Prozedurwert)
                            #   SCA144     -2  (Waechter-Idiom)
                            #   SCA025 +1.120  \ die DFM-Fixes aus dem
                            #   SCA024   +713  | GITLAK-Paket - sie machen
                            #   SCA039    +21  | 32 vorher unparsbare
                            #   SCA029    +13  | Dateien sichtbar, und die
                            #   SCA042     +7  | liegen ueberwiegend in
                            #   SCA041     +3  | Demo-/Sample-Baeumen
                            #   SCA030     +2  |
                            #   SCA057     +2  /
                            # Summe -646. Vorher rw20: 195.014.
# freien `search` von oben). Beide kommen auf 195.014.
# Vorher rw19: 195.044. Der Unterschied sind exakt 30 Funde, alle SCA168
# (2.258 -> 2.228) - die Fixture-Anteile der 148 case-else-Drops. SCA106
# hat im ganzen Korpus keinen einzigen Fund in einer Fixture-Datei,
# deshalb bewegen die 806 Gate-7-Drops diese Zahl nicht.
if FIXTURE_ERWARTET >= 0: assert ges_fix == FIXTURE_ERWARTET, (
    "Fixture-Filter: %d statt %d - nachrechnen, nicht durchwinken"
    % (ges_fix, FIXTURE_ERWARTET))
assert sicht(ALLES_AN, False) == (ges_n, ges_fpm), \
    'die filterlose Sicht muss die Rohmessung sein'
mit_funden = [z for z in zeilen if z['n']]
ohne_quote = [z for z in zeilen if z['quote'] is None and z['n']]

# Die Nutzer-Sicht der Arbeitsliste = CLI mit INI (Profil + Fixture-Filter):
# strengster der vier Filter und der, den ein Kunde per Default bekommt.
NUTZ_N, NUTZ_F = sicht(DEFAULT_AN, True)

# Beitrag der sieben im Default abgeschalteten Style-Regeln (nur die, die
# im Korpus ueberhaupt feuern).
_aus = [z for z in mit_funden if z['rid'] not in DEFAULT_AN]
_aus_n = sum(z['n'] for z in _aus)
_aus_f = sum(z['fpm'] or 0 for z in _aus)


def tier_sum(t):
    tz = [z for z in zeilen if z['tier'] == t]
    n = sum(z['n'] for z in tz)
    f = sum(z['fpm'] for z in tz if z['fpm'] is not None)
    return len([z for z in tz if z['n']]), n, f


# ========================================================================
# 9) Ausgabe
# ========================================================================
out = io.open(os.path.join(REPO, 'Todo_FpUebersicht_2026-08-26.md'),
              'w', encoding='utf-8')
w = out.write
w('# FP-Quoten-Uebersicht aller Detektoren\n\n')
w('> Der Dateiname traegt das Datum der ERSTEN Fassung und bleibt\n')
w('> stabil, damit Verweise nicht brechen - massgeblich ist der Stand\n')
w('> in dieser Zeile. Neu erzeugt aus tools/fp_uebersicht.py.\n')
w('> LOKAL und gitignored (.gitignore Zeile 140, `Todo_*.md`).\n\n')
w('> ACHTUNG QUOTEN-BASIS: die Hochrechnung nutzt weiterhin das\n')
w('> 15.08.-Audit als Quotenquelle; die FRISCHEN September-Quoten\n')
w('> (Nachtrag in Todo_FpQuotenJeDetektor_2026-08-15_FINAL.md:\n')
w('> SCA017 0 %, SCA070 0,8 %, ...) sind NOCH NICHT eingerechnet -\n')
w('> die FP-Masse ist damit eine OBERGRENZE. Ueberlagerung =\n')
w('> notierte Folgeaufgabe der Portierung.\n')
w('>\n')
w('> Zwei Quellen, bewusst getrennt gehalten:\n')
w('> * **Quote** = FP-Anteil je Regel. Woher sie kommt, sagt die Spalte\n')
w('>   **Basis** - das ist der Unterschied zwischen "alle 59 Funde\n')
w('>   gezaehlt" und "24 von 15.000 angesehen".\n')
w('> * **Funde** = Korpuslauf %s (Referenzkorpus\n' % LABEL)
w('>   D:\\git-sca-realworld, `--full --profile strict --min-severity hint`,\n')
w('>   Stand main = 523c52f), %s Funde in %d Regeln. Vorgaenger war rw36\n'
  % (de(ges_n), len(mit_funden)))
w('>   (778.554, main = eb6101d), davor rw33 (778.575) und rw23 (782.884).\n')
w('>   Seit rw23 dazugekommen, nach Groesse: SCA054 GATE E (Prozedurwert)\n')
w('>   **-7.434**, die DFM-Fixes aus dem GITLAK-Bericht **+3.158** (32\n')
w('>   Dateien waren vorher gar nicht parsbar), SCA144-Waechter-Idiom -20,\n')
w('>   SCA001 Klasse F **-21**, SCA001 Klassen D+L samt Bestandsfehler\n')
w('>   **-11**, SCA001-TFileName -13.\n')
w('>   Netto -4.341.\n')
w('>   NICHT in der Fundzahl sichtbar, aber wichtig: 94 SCA097 sind von\n')
w('>   error auf warning gewandert - das Error-Tier faellt von 1.098 auf\n')
w('>   1.004.\n')
w('>\n')
w('> rw37 und rw41 sind REFACTOR-BEWEISE, keine Messpunkte: byte-\n')
w('> identisch zu rw36 bzw. rw40, gleicher SHA-256 ueber 737 MB.\n')
w('>\n')
w('> **FP-Masse** = Quote x Funde. Das ist eine HOCHRECHNUNG, keine\n')
w('> Zaehlung - ausser wo die Basis "Vollzaehlung" heisst.\n')
w('> Name und Tier stammen aus `rules/sca-rules.json` (die einzige Quelle,\n')
w('> die auch die nach dem Audit ergaenzten Regeln SCA197/198 kennt);\n')
w('> der Katalog sagt "Hint", wo SARIF und Audit "Note" sagen - dieselbe\n')
w('> Stufe, hier durchgehend als Note gefuehrt.\n\n')

w('## Summen (strict, ohne Fixture-Filter - die Rohmessung)\n\n')
w('| Groesse | Wert |\n|---|---:|\n')
w('| Regeln mit Funden im Lauf | %d |\n' % len(mit_funden))
w('| Funde gesamt | %s |\n' % de(ges_n))
# SARIF-Level != Katalog-Tier: die Evidenz-Politik ("Error nur fuer
# fcHigh") demotiert einen Teil der Error-Tier-Regeln im Ausgabe-Level.
# Deshalb stehen hier 1.099 und in der Tier-Tabelle weiter unten 1.769.
w('| davon SARIF-Level `error` | %s |\n' % de(sum(z['err'] for z in zeilen)))
w('| davon SARIF-Level `warning` | %s |\n' % de(sum(z['warn'] for z in zeilen)))
w('| davon SARIF-Level `note` | %s |\n' % de(sum(z['note'] for z in zeilen)))
w('| Konfidenz high | %s |\n' % de(sum(z['high'] for z in zeilen)))
w('| Konfidenz medium | %s |\n' % de(sum(z['med'] for z in zeilen)))
w('| Funde in Test-/Demo-/Sample-Dateien | %s (%s) |\n'
  % (de(ges_fix), pz(100.0 * ges_fix / ges_n)))
w('| **FP-Masse hochgerechnet** | **~%s** |\n' % de(ges_fpm))
w('| **FP-Quote fundzahlgewichtet** | **~%s** |\n'
  % pz(100.0 * ges_fpm / ges_n, 2))
w('| Regeln ohne jede Quote (nicht hochgerechnet) | %d |\n\n'
  % len(ohne_quote))

w('### Vier Konsumenten, vier Fundmengen\n\n')
w('"Default" ist kein Zustand, sondern vier verschiedene. Zwei Filter\n')
w('wirken unabhaengig voneinander, und nur EIN Konsument hat beide:\n\n')
w('* **Profil** (`rules/sca-rules.json`) schaltet Regeln ab. Das\n')
w('  Default-Profil nimmt %d Style-Regeln heraus:\n'
  % len(DEFAULT_AUS_KINDS))
for _i in range(0, len(DEFAULT_AUS_KINDS), 3):
    _teil = DEFAULT_AUS_KINDS[_i:_i + 3]
    _letzte = _i + 3 >= len(DEFAULT_AUS_KINDS)
    w('  %s%s\n' % (', '.join('`' + x + '`' for x in _teil),
                    '.' if _letzte else ','))
w('* **Test-Fixture-Post-Filter** (`uConsoleRunner.pas:1519-1540`) loescht\n')
w('  jeden Fund, dessen Pfad `TDetectorUtils.IsTestFixturePath(...,\n')
w('  tplFixture)` erfuellt - Dateinamen `uTest*.pas`, `*_Test(s).pas`,\n')
w('  `*TestSuite*.pas`, `*Sample.pas`, `*_Sample_*.pas`, `*Demo.pas`,\n')
w('  `*_Demo_*.pas`, `MeineUnit.pas`, `*Demo.dfm` sowie die Pfadsegmente\n')
w('  `test`, `tests`, `unittest(s)`, `samples`, `demos`, `resources`.\n')
w('  Er greift NUR im Console-Runner und dort nur bei Profil `default`\n')
w('  bzw. `selftest-quiet` (`uConsoleRunner.pas:1327-1333`). Am rw23-Korpus\n')
w('  trifft er %s der %s Funde (%s).\n\n'
  % (de(ges_fix), de(ges_n), pz(100.0 * ges_fix / ges_n)))
w('| Konsument | Profil | Fixture-Filter | Funde | FP-Masse | Quote |\n')
w('|---|---|:--:|---:|---:|---:|\n')
for name, prof, ff, regeln, filt, _q in SICHTEN:
    n, f = sicht(regeln, filt)
    w('| %s | %s | %s | %s | ~%s | %s |\n'
      % (name, prof, ff, de(n), de(f), pz(100.0 * f / n if n else 0, 2)))
w('\n')
for name, prof, ff, regeln, filt, quelle in SICHTEN:
    w('* **%s** - %s.\n' % (name, quelle))
w('\n')
w('Die sieben im Default abgeschalteten Style-Regeln tragen %s Funde\n'
  % de(_aus_n))
w('(%s aller Funde), aber nur ~%s FP-Masse (%s der FP-Masse).\n'
  % (pz(100.0 * _aus_n / ges_n), de(_aus_f),
     pz(100.0 * _aus_f / ges_fpm)))
w('Sie abzuschalten senkt also die Fundzahl staerker als die Fehlermenge -\n')
w('genau deshalb steigt die Quote von %s auf %s.\n\n'
  % (pz(100.0 * ges_fpm / ges_n, 2), pz(100.0 * NUTZ_F / NUTZ_N, 2)))
w('Konsequenz fuer die Priorisierung: eine Regel, die beim Kunden gar\n')
w('nicht laeuft, ist als FP-Traeger zweitrangig - unabhaengig davon,\n')
w('wie gross ihre Masse im strict-Lauf aussieht. Die Arbeitsliste unten\n')
w('faehrt deshalb die Sicht "CLI mit analyser.ini".\n\n')
w('> Annahme, die in jeder Fixture-gefilterten Zahl steckt: die FP-Quote\n')
w('> ist innerhalb und ausserhalb von Testverzeichnissen gleich. Gemessen\n')
w('> ist das nicht - die Quoten stammen aus Stichproben ueber den GESAMTEN\n')
w('> Korpus.\n\n')

w('### Je Tier (Katalog-Tier, strict)\n\n')
w('| Tier | Regeln | Funde | FP-Masse (hochger.) | Quote |\n')
w('|---|---:|---:|---:|---:|\n')
_tn = 0
for t in ('Error', 'Warning', 'Note'):
    c, n, f = tier_sum(t)
    _tn += n
    w('| %s | %d | %s | ~%s | %s |\n'
      % (t, c, de(n), de(f), pz(100.0 * f / n if n else 0)))
w('\n')
assert _tn == ges_n, 'Tier-Tabelle summiert %d statt %d' % (_tn, ges_n)

w('## Die 25 groessten FP-Massen (strict, Hochrechnung)\n\n')
w('| Regel | Detektor | Tier | Funde | Quote | Basis | FP-Masse |\n')
w('|---|---|---|---:|---:|---|---:|\n')
for z in sorted([x for x in zeilen if x['fpm']], key=lambda x: -x['fpm'])[:25]:
    w('| %s | %s | %s | %s | %s | %s | ~%s |\n'
      % (z['rid'], z['name'], z['tier'], de(z['n']), pz(z['quote']),
         basis_txt(z), de(z['fpm'])))
w('\n')


# --- Arbeitsliste ------------------------------------------------------
def gruppe(z):
    """NUR nach Quote und Fundzahl - der Bearbeitungsstand steht in einer
    eigenen Spalte. Im Vorgaenger wurde er zuerst geprueft, wodurch die
    beiden hoechsten Quoten des Korpus (SCA001, SCA017) in der
    'bearbeitet'-Gruppe verschwanden."""
    q = z['quote'] or 0
    if q >= G_QUOTE:
        return 'A'
    if z['n_ohne_fix'] >= G_FUNDE:
        return 'B'
    return 'C'


GRUPPENTEXT = {
    'A': 'Praezision - Quote >= %s' % pz(G_QUOTE, 0),
    'B': 'Volumen - Quote < %s, aber >= %s Funde in der Nutzer-Sicht'
         % (pz(G_QUOTE, 0), de(G_FUNDE)),
    'C': 'kleiner Posten - Quote < %s und < %s Funde'
         % (pz(G_QUOTE, 0), de(G_FUNDE)),
}

_al = [z for z in zeilen if z['n_ohne_fix'] and z['rid'] in DEFAULT_AN]
_al.sort(key=lambda z: -(z['fpm_nutzer'] or 0))
_top = _al[:25]

w('## Arbeitsliste: die naechsten 25 (Sicht "CLI mit analyser.ini")\n\n')
w('Sortiert nach hochgerechneter FP-Masse in der Nutzer-Sicht: Profil\n')
w('`default` UND Test-Fixture-Filter. Die Spalte **Gruppe** sagt, welche\n')
w('Art Arbeit ansteht - das ist wichtiger als der Rang:\n\n')
for g in ('A', 'B', 'C'):
    w('* **%s** - %s\n' % (g, GRUPPENTEXT[g]))
w('\n')
w('| # | Gr. | Regel | Detektor | Funde | Quote | Basis | FP-Masse | Stand |\n')
w('|--:|:--:|---|---|---:|---:|---|---:|---|\n')
for i, z in enumerate(_top, 1):
    w('| %d | %s | %s | %s | %s | %s | %s | ~%s | %s |\n'
      % (i, gruppe(z), z['rid'], z['name'], de(z['n_ohne_fix']),
         pz(z['quote']) if z['quote'] is not None else '-',
         basis_txt(z), de(z['fpm_nutzer'] or 0), stand_txt(z)))
_t25 = sum(z['fpm_nutzer'] or 0 for z in _top)
_tall = sum(z['fpm_nutzer'] or 0 for z in _al)
w('\nDiese 25 tragen ~%s der ~%s FP-Masse der Nutzer-Sicht (%s).\n\n'
  % (de(_t25), de(_tall), pz(100.0 * _t25 / max(1, _tall), 0)))
w('**Woraus die Masse einer Regel besteht, steht im Abschnitt "FP-Klassen\n')
w('der Top-25" weiter unten** - je Klasse mit Groesse, Herkunft der\n')
w('Groesse, Verdikt der Gegenpruefung und Gate-Idee. Die Spalte "Stand"\n')
w('hier fasst davon nur die Verdikt-Bilanz zusammen.\n\n')

w('### Wie diese Liste zu lesen ist\n\n')
# Das Beispiel fuer die Extrapolation wird GEWAEHLT, nicht fest
# verdrahtet: hier stand SCA106, das seit dem 28.08. keine Stichproben-
# quote mehr traegt (Gate 7 hat die Grundgesamtheit ausgetauscht).
# Gewaehlt wird aus den 25 Zeilen DIESER Tabelle - ein Beispiel aus einer
# Regel, die hier gar nicht steht, erklaert die Spalte nicht.
_bsp = max([z for z in _top if z['art'] == 'Stichprobe' and z['basis'] == 24],
           key=lambda z: z['n_ohne_fix'])
# Auch das Vollzaehlungs-Beispiel wird GEWAEHLT: seit dem 28.08. steht mit
# SCA001 eine 568er-Vollzaehlung in der Liste, und ein Beispiel aus dieser
# Tabelle erklaert die Spalte besser als eine Regel weit ausserhalb.
_bspv = sorted([z for z in _top if z['art'] == 'Vollzaehlung'],
               key=lambda z: -(z['basis'] or 0))
w('**Die Spalte Basis ist die wichtigste der Tabelle.**')
if _bspv:
    w(' "Vollzaehlung %s"\n' % de(_bspv[0]['basis']))
    w('heisst: jeder einzelne Fund wurde angesehen und beurteilt - bei %s\n'
      % _bspv[0]['rid'])
    w('sind das %s Einzelverdikte, keine Hochrechnung.' % de(_bspv[0]['basis']))
else:
    w(' "Vollzaehlung" heisst:\njeder Fund wurde angesehen.')
w(' "Stichprobe 24" heisst: bei %s\n' % _bsp['rid'])
w('mit %s Funden ist das eine Extrapolation um Faktor %s.\n'
  % (de(_bsp['n_ohne_fix']), de(int(round(_bsp['n_ohne_fix'] / 24.0)))))
w('"Rechnung" heisst: Audit-FP-Masse minus am Korpus belegte Drops -\n')
w('belastbar, solange die Drops wirklich alle FP waren. "Schaetzung"\n')
w('heisst: begruendet geraten, nicht gemessen.\n\n')
_stat = {}
for z in _al:
    _stat[z['art']] = _stat.get(z['art'], 0) + (z['fpm_nutzer'] or 0)
w('In der Nutzer-Sicht verteilt sich die FP-Masse so auf die Basis-Arten:\n\n')
w('| Basis | FP-Masse | Anteil |\n|---|---:|---:|\n')
for _a in ('Vollzaehlung', 'Rechnung', 'Stichprobe', 'Schaetzung', None):
    if _a in _stat:
        w('| %s | ~%s | %s |\n'
          % (_a or 'ohne Quote', de(_stat[_a]),
             pz(100.0 * _stat[_a] / max(1, _tall), 0)))
w('\n%s der Nutzer-FP-Masse ruhen also auf Stichproben, die fast '
  % pz(100.0 * _stat.get('Stichprobe', 0) / max(1, _tall)))
w('durchweg\n24 Faelle gross sind.\n\n')
w('**Und die Quoten altern - aber nicht, weil das Audit schlecht misst.**\n')
w('Bei SCA011 fiel die Quote von 54 % auf 3,4 %, bei SCA047 von 83 % auf\n')
w('0 %. In beiden Faellen hat ein Detektorfix die GRUNDGESAMTHEIT\n')
w('ausgetauscht: SCA011 ging mit 4e2a248 (16.08., bedingt kompilierter\n')
w('Terminator) von 132 auf 59 Funde, SCA047 mit dem Umbau vom 19./20.08.\n')
w('von 134 auf 30. Die alte Quote galt fuer eine Menge, die es nicht mehr\n')
w('gibt - sie war zum Messzeitpunkt richtig. Die Lehre ist deshalb nicht\n')
w('"Stichproben taugen nichts", sondern: **jeder Detektorfix macht die\n')
w('Quote seiner Regel ungueltig.** Bei SCA137 lag es anders - dort war die\n')
w('Stichprobe schlicht der Groesse 1. Wer nach dieser Liste plant, misst\n')
w('die Quote des gewaehlten Postens ZUERST nach.\n\n')
w('**Der 28.08. liefert zwei frische Faelle derselben Lehre - diesmal\n')
w('mit den Audit-Akten in der Hand.** Bei SCA106 MethodName hat Gate 7\n')
w('806 Funde entfernt, die samt und sonders Parser-Artefakte an EINER\n')
w('Datei waren (Dual-Mode-Header mit `{$IFDEF}` in\n')
w('skia4delphi/Source/System.Skia.API.pas). Genau diese Klasse ist die\n')
w('einzige, die die Audit-Akte fuer SCA106 benennt, und beide FP der\n')
w('24er-Stichprobe stehen in dieser Datei: die Audit-Quote von 8,3 %\n')
w('misst eine FP-Masse, die es nicht mehr gibt. Bei SCA168\n')
w('DefaultCaseInCaseStatement hat der case-else-Parserfix 148 Funde\n')
w('entfernt, in denen das `case` im Quelltext nachweislich ein `else`\n')
w('hat - eine der beiden Audit-FP-Klassen; die zweite (vollstaendig\n')
w('abgedeckter Boolean-Selektor) steht noch. Beide Regeln tragen\n')
w('deshalb ab sofort eine GERECHNETE statt einer gemessenen Quote, mit\n')
w('Herleitung unten unter "Herkunft der nicht-auditierten Quoten". Bei\n')
w('SCA106 ist der Rest so klein, dass er von der Stichprobenstreuung\n')
w('nicht mehr zu unterscheiden ist - dort ist die naechste ehrliche\n')
w('Handlung eine Nachmessung, keine weitere Hochrechnung.\n\n')
w('**Der dritte frische Fall ist der unbequemste - und er betrifft nicht\n')
w('die FP-Quote, sondern die AUSBEUTE.** Bei SCA001 MemoryLeak ist am\n')
w('28.08. nicht nachgemessen, sondern VOLLGEZAEHLT worden: 568 Funde,\n')
w('568 Verdikte, %d FP. Das sind %s statt der 62,5 %% aus 24 Faellen.\n'
  % (_S1_FP, pz(Z['SCA001']['quote'], 1)))
w('Die alte Zahl war deswegen nicht falsch - sie war NICHT\n')
w('AUSSAGEFAEHIG: bei n=24 betraegt das 95-%-Intervall um 62 % rund\n')
w('+/- 19 Punkte (Standardfehler 9,9), und die gemessene Spanne von 67\n')
w('bis 78 % liegt vollstaendig darin. Eine 24er-Ziehung kann 62 % und\n')
w('74 % nicht trennen; wer daraus einen Bauplan ableitet, leitet ihn aus\n')
w('Rauschen ab.\n\n')
w('Bemerkenswert ist die RICHTUNG des Fehlers, und sie ist teuer. Die\n')
w('FP-Zahl lag nur um Faktor 1,1 bis 1,3 zu niedrig (352 geschaetzt, 415\n')
w('gemessen). Die AUSBEUTE dagegen - die Zahl der echten Funde - war um\n')
w('Faktor 1,2 bis 1,7 zu HOCH: erwartet waren 216 echte Lecks, gezaehlt\n')
w('wurden 126 bis 185. Wer mit "SCA001 findet uns 216 Lecks" geplant hat,\n')
w('plant mit rund anderthalbmal zu viel Substanz. Fuer diese Datei heisst\n')
w('das: **die Spalte FP-Masse ist eine Arbeitsmenge, keine Wertaussage.**\n')
w('Wer nach ihr priorisiert, trifft die Fehlermenge passabel und\n')
w('ueberschaetzt systematisch den Wert der Regel - und damit den Preis\n')
w('eines zu scharfen Gates.\n\n')
w('**Gruppe B ist kein Gate-Problem.** Bei einstelliger Fehlerrate und\n')
w('fuenfstelligen Fundzahlen ist nicht die Praezision das Thema, sondern\n')
w('die Frage, ob die Regel in dieser Menge ueberhaupt gelesen wird. Die\n')
w('ehrlichen Optionen dort heissen Schwellwert, Profil-Zugehoerigkeit\n')
w('oder Konfidenz - nicht "noch ein Gate".\n\n')
_hq = sorted([z for z in _top if z['quote'] is not None],
             key=lambda z: -z['quote'])[0]
_hqrang = [z['rid'] for z in _top].index(_hq['rid']) + 1
w('**Die schlechteste Quote der Liste ist %s %s** - %s bei\n'
  % (_hq['rid'], _hq['name'], pz(_hq['quote'])))
w('%s Funden, nach Masse Rang %d mit ~%s FP.\n\n'
  % (de(_hq['n_ohne_fix']), _hqrang, de(_hq['fpm_nutzer'] or 0)))
if _hq['rid'] == 'SCA001':
    # Der Satz, der hier bis zum 28.08. stand, war der AUSGANGSPUNKT der
    # Vollzaehlung - und ist von ihr widerlegt worden. Er wird deshalb
    # zitiert und nicht stillschweigend ersetzt: wer die Datei kennt, muss
    # sehen, dass sich die Aussage geaendert hat und warum.
    w('**Hier stand bis zum 28.08. der Zusatz "und faellt ohne\n')
    w('Cross-Unit-Callee-Index nicht weiter". Dieser Satz ist\n')
    w('widerlegt.** Er war der Ausgangspunkt der Vollzaehlung und haette\n')
    w('beinahe die Reihenfolge der naechsten Arbeit bestimmt. Was die\n')
    w('Zaehlung aller %s Funde stattdessen zeigt:\n\n' % de(_S1_N))
    w('* K1 traegt **%d Funde sicher** (Klasse G, echt cross-unit),\n'
      % _S1_K1_SICHER)
    w('  hoechstens %d mit der auswertbaren Teilmenge von C. Veranschlagt\n'
      % _S1_K1)
    w('  waren ~%d - **Faktor %s bis %s zu hoch.**\n'
      % (_K1_ALT, ('%.1f' % _K1_FAKTOR_MIN).replace('.', ','),
         ('%.1f' % _K1_FAKTOR_MAX).replace('.', ',')))
    w('* **%s der %s Fehlalarme (%s) fallen dateilokal**, ohne jeden\n'
      % (de(_S1_DL), de(_S1_ROH_FP), pz(100.0 * _S1_DL / _S1_ROH_FP)))
    w('  Index. Der groesste Einzelposten - die besitzende Container-Senke\n')
    w('  mit 113 Funden - ist eine Positivliste von Typen, mehr nicht.\n')
    w('* Der Grund steht woertlich in acht der zwoelf Paketberichte: **was\n')
    w('  wie Cross-Unit-Ownership aussieht, ist ueberwiegend unit-lokal.**\n')
    w('  Der Callee-Rumpf steht in derselben Datei - Factory, Add-Wrapper,\n')
    w('  `Done()`-Selbstfreigabe, Ctor-Selbstregistrierung. Die\n')
    w('  unit-lokale Klasse F (41) ist GROESSER als die cross-unit-Klasse\n')
    w('  G (%d).\n\n' % _S1_K1_SICHER)
    w('Konsequenz: K1 gehoert HINTER die dateilokalen Schritte, nicht\n')
    w('davor - teuerster Baustein, drittkleinster Ertrag. Begruendet\n')
    w('bleibt der Index trotzdem, nur nicht mehr von dieser Regel her:\n')
    w('die Read-Allowlist von SCA166 braucht ihn (Upstream-Bericht\n')
    w('2026-08-27), und der unit-lokale Rumpf-Check (Klasse F) ist ohnehin\n')
    w('die Vorstufe, deren Praedikate K1 spaeter ebenfalls braucht.\n\n')
else:
    w('Den Cross-Unit-Callee-Index (K1) braucht inzwischen die\n')
    w('Read-Allowlist von SCA166 (Upstream-Bericht 2026-08-27); fuer\n')
    w('SCA001 ist er seit der Vollzaehlung vom 28.08. nur noch 35 bis 45\n')
    w('Funde wert und gehoert hinter die dateilokalen Schritte.\n\n')
_c117 = Z['SCA117']
_q117a = 100.0 * audit['SCA117']['fp'] / (audit['SCA117']['tp']
                                          + audit['SCA117']['fp'])
w('**SCA117 ist der Praezedenzfall fuer "erst messen".** %s Funde im\n'
  % de(_c117['n']))
w('strict-Lauf - die groesste Fundzahl des Korpus - aber im Default-Profil\n')
w('abgeschaltet, also in der Nutzer-Sicht gar nicht da. Und die Quote hat\n')
w('drei Werte: das Audit sagte %s (24 Faelle), eine 40er-Stichprobe auf\n'
  % pz(_q117a, 2))
w('der Wortlaut-Ebene sagte 0 % (40/40 korrekt), und die Vollzaehlung\n')
w('ueber alle %s Funde mit einer byte-genauen Detektor-Replik sagt %s\n'
  % (de(_c117['n']), pz(_c117['quote'], 2)))
w('(%s harte FP). Drei Methoden, Faktor %s zwischen der hoechsten und\n'
  % (de(_c117['fpm']),
     ('%.1f' % (_q117a / _c117['quote'])).replace('.', ',')))
w('der niedrigsten nicht-null-Zahl - das ist die Streuung, mit der jede\n')
w('Zeile dieser Datei behaftet ist. Die Tabelle fuehrt die Vollzaehlung,\n')
w('weil sie die einzige der drei ist, die jeden Fund angesehen hat.\n\n')

# --- FP-Klassen der Top-25 ---------------------------------------------
# Die Diagnose war bezahlt und stand trotzdem nicht in der Uebersicht: bis
# zum 28.08. zeigte die Spalte "Stand" nur die ANZAHL benannter Klassen.
_TOPIDS = [z['rid'] for z in _top]
_rang = dict((r, i + 1) for i, r in enumerate(_TOPIDS))
# Regeln mit harten Klassendaten kriegen eine eigene Tabelle - auch wenn
# sie aus den Top 25 herausfallen sollten (dann Rang '-').
_MITTABELLE = [r for r in _TOPIDS if r in _HARTE_REGELN]
_MITTABELLE += [r for r in _HARTE_REGELN if r not in _TOPIDS]

# Die dritte Quelle: nur benannte Klassen aus den Audit-Akten. Sie kommen
# fuer jede Top-25-Regel OHNE harte Daten vollstaendig dazu; bei den
# Regeln mit harter Tabelle nur die, die dort noch nicht abgedeckt sind
# (sonst stuende die gebaute SCA106-Klasse hier als "nie gemessen").
_nur_benannt = []
for _r in _TOPIDS:
    if _r in _HARTE_REGELN:
        continue
    for _nm, _smp, _fix in AUDITKLASSEN.get(_r, []):
        _nur_benannt.append((_r, _nm, _smp, _fix))
_nb_in_tabelle = sum(len(audit_offen(r)) for r in _MITTABELLE)

_bilanz = {}
for _k in _KLASSEN:
    _e = _bilanz.setdefault(_k[4], [0, 0])
    _e[0] += 1
    _e[1] += _k[2]
_bilanz['nur benannt'] = [len(_nur_benannt) + _nb_in_tabelle, 0]
_herk = {}
for _k in _KLASSEN:
    _herk[_k[3]] = _herk.get(_k[3], 0) + 1
_herk['LEER'] = len(_nur_benannt) + _nb_in_tabelle
_klassen_ges = len(_KLASSEN) + _herk['LEER']
# Alle drei Summen sind BEWUSST auf die Herkunft GEZAEHLT eingeschraenkt.
# Sie tragen die Lehrsaetze zur Klassenzaehlung vom 28.08. (4.685 gezaehlte
# Fehlalarme, davon ~40 % in der Gegenpruefung gefallen); die Vollzaehlung
# von SCA001 ist eine andere Beweisart und wird getrennt ausgewiesen -
# sonst waeren beide Zahlen hinterher unlesbar.
_gezaehlt_ges = sum(k[2] for k in _KLASSEN if k[3] == 'GEZAEHLT')
_gruen_ges = sum(k[2] for k in _KLASSEN
                 if k[3] == 'GEZAEHLT' and k[4] == 'gruen')
_rot_ges = sum(k[2] for k in _KLASSEN
               if k[3] == 'GEZAEHLT' and k[4] == 'rot')
_rot_alle = sum(k[2] for k in _KLASSEN if k[4] == 'rot')
_offen_gez = [k for k in _KLASSEN
              if k[3] == 'GEZAEHLT' and k[4] in ('gruen', 'gelb', 'Vertrag',
                                                 'ungeprueft')]
_groesste_offen = max(_offen_gez, key=lambda k: k[2])
_voll_ges = sum(k[2] for k in _KLASSEN if k[3] == 'VOLLZAEHLUNG')
_voll_regeln = sorted(set(k[0] for k in _KLASSEN
                          if k[3] == 'VOLLZAEHLUNG'))

w('## FP-Klassen der Top-25\n\n')
w('Die Quotenspalten oben sagen, WIE GROSS das Problem einer Regel ist.\n')
w('Dieser Abschnitt sagt, WORAUS es besteht. Bis hierher stand davon nur\n')
w('die Anzahl in der Spalte "Stand" - wer damit plante, musste jedes Mal\n')
w('die Einzelakte oeffnen.\n\n')
w('**Die Lehre der Zaehlung vom 28.08. steht vor allem anderen.** Sieben\n')
w('Regeln wurden ueber ihre GANZE Grundgesamtheit ausgezaehlt statt\n')
w('bestichprobt; 15 der groesseren Klassen hat danach ein Skeptiker\n')
w('angegriffen. (Am selben Tag kam mit %s eine Vollzaehlung dazu - andere\n'
  % ', '.join(_voll_regeln))
w('Beweisart, eigener Absatz weiter unten. Alle Zahlen dieses Absatzes\n')
w('gehoeren zu den sieben Klassenzaehlungen.) Von **4.685 so gezaehlten\n')
w('Fehlalarmen fielen rund 40 %\n')
w('in der Gegenpruefung** (Entscheidungsvorlage: -1.884 auf die rohen\n')
w('Zaehlwerte; ihre roten Verdikte summieren sich hier auf %s, weil die\n'
  % de(_rot_ges))
w('Tabellen durchweg die KORRIGIERTEN Groessen fuehren - SCA176 else-if\n')
w('240 statt 387, SCA176 and/or 52 statt 279 - und dafuer zwei vom\n')
w('Zaehler selbst ausgeschlossene Klassen mitzaehlen. Die Verdikt-Tabelle\n')
w('weiter unten zeigt %s: die Differenz von %d ist die RTTI-Klasse von\n'
  % (de(_rot_alle), _rot_alle - _rot_ges))
w('SCA001, die aus der Vollzaehlung stammt.) Zaehlen schlaegt\n')
w('Hochrechnen: fuenf\n')
w('vergleichbare Audit-Hochrechnungen lagen um Faktor 2 bis 9 daneben, und\n')
w('zweimal hat eine 24er-Ziehung eine ganze Klasse gar nicht gesehen.\n')
w('Aber: **Zaehlen beweist die GROESSE einer Klasse, nicht dass ein Gate\n')
w('sie sauber trifft.** Die drei Fehlerarten, jede mehrfach belegt:\n\n')
w('* **Praedikat != Gate** - gezaehlt wird das eine, gebaut das andere\n')
w('  (SCA146 G: 40 gezaehlt, das Gate frisst 52; SCA176 and/or: Messmodell\n')
w('  279, Bauanleitung 52; SCA103 K4: die Bauanleitung ist ein No-Op).\n')
w('* **Praedikat != Begruendung** - die Klasse trifft, der Grund traegt\n')
w('  nicht (SCA146 B1: 76 % der "fremden Signaturen" gehoeren dem Autor\n')
w('  selbst; SCA103 K9 ist eine Politikaenderung; SCA132 K5 liegt auf der\n')
w('  eigenen Codebasis 25/25 falsch).\n')
w('* **Messmodell != Motor** - mit einem Text-Scanner gemessen, gegen den\n')
w('  AST gebaut, oder auf AST-Formen gesetzt, die es nicht gibt\n')
w('  (`nkIfStmt` unter `M` statt unter `nkBlock` - dieselbe Falle, die\n')
w('  SCA017 Gate B zum No-Op gemacht hat).\n\n')
w('**Die Vollzaehlung von %s misst zum ersten Mal die Fehlerrate der\n'
  % ', '.join(_voll_regeln))
w('Zaehlung selbst.** Drei adversariale Gegenpruefungen haben %d der %s\n'
  % (_S1_GEPRUEFT, de(_S1_N)))
w('Verdikte neu aufgemacht (%s) und %d davon gekippt - **%s. Und alle\n'
  % (pz(100.0 * _S1_GEPRUEFT / _S1_N), _S1_KIPP,
     pz(100.0 * _S1_KIPP / _S1_GEPRUEFT)))
w('acht in dieselbe Richtung: FP -> TP, kein einziger Gegenkipp.** Das\n')
w('ist kein Rauschen, sondern eine Tendenz zum Freispruch - Rauschen\n')
w('kippte in beide Richtungen. Auf die Grundgesamtheit hochgerechnet\n')
w('stuenden rund 30 weitere FP-Verdikte einer Pruefung nicht durch; die\n')
w('gemessene FP-Quote ist damit eher eine **Obergrenze** als eine\n')
w('Untergrenze.\n\n')
w('Und sieben der acht Kipps sind kein Urteilsfehler, sondern ein\n')
w('**Definitionsfehler**: sie betreffen alle dieselbe Klasse (lsWarning -\n')
w('"Free steht im Rumpf, aber nicht im finally"), fuer die es keinen\n')
w('gemeinsamen Vertrag gab. Dieselbe Konstellation ist in Paket 6/8/10\n')
w('ein TP und in den neun uebrigen ein FP. Das ist kein Auditorenproblem,\n')
w('das ist ein **Auftragsproblem** - und die Lehre fuer jede weitere\n')
w('Zaehlung: der Vertrag fuer jeden Melde-Tier muss schriftlich\n')
w('vorliegen, mit Beispiel, BEVOR gezaehlt wird. Sonst misst man 67 %\n')
w('und 78 % im selben Datensatz. Sauber war dagegen die Zeilentreue:\n')
w('eine der Gegenpruefungen hat fuer alle 31 gezogenen Faelle den Text\n')
w('der gemeldeten Zeile gegengelesen - 31/31 korrekt, keine verschobene\n')
w('Fundstelle. Die Streitpunkte liegen ausschliesslich in der Bewertung,\n')
w('nie in der Lokalisierung.\n\n')
w('**Herkunft der Groesse** - dieselbe Ehrlichkeitsachse wie die Spalte\n')
w('"Basis" bei den Quoten, nur fuer Klassen. Sie ist der eigentliche Punkt\n')
w('dieses Abschnitts:\n\n')
w('| Herkunft | Klassen | Bedeutung |\n|---|---:|---|\n')
w('| `A/B` | %d | Drop-Zahl aus einem Lauf gegen den Korpus. Haerteste '
  'Form, weil sie das GEBAUTE Gate misst. |\n' % _herk.get('A/B', 0))
w('| `VOLLZAEHLUNG` | %d | jeder einzelne Fund der Regel beurteilt und '
  'einer Klasse zugeordnet (%s, %s Verdikte). Fuer die GROESSE einer '
  'Klasse staerker als `GEZAEHLT`: dort wird ein Praedikat gemessen, hier '
  'die Klasse selbst - und "Praedikat != Klasse" ist eine der drei '
  'belegten Fehlerarten. |\n'
  % (_herk.get('VOLLZAEHLUNG', 0), ', '.join(_voll_regeln), de(_S1_N)))
w('| `GEZAEHLT` | %d | Praedikat ueber die ganze Grundgesamtheit '
  'ausgezaehlt (Python-Replik, drei davon byte-exakt gegen die Referenz '
  'validiert). |\n' % _herk.get('GEZAEHLT', 0))
w('| `GESCHAETZT` | %d | begruendet geraten, nicht gezaehlt. |\n'
  % _herk.get('GESCHAETZT', 0))
w('| `LEER` | %d | nur benannt (Audit-Akte 15.08.), Groesse nie gemessen; '
  'was dort steht, ist der Treffer in einer 24er-Ziehung. |\n'
  % _herk.get('LEER', 0))
w('\n**Verdikt** - wo Zaehlung und Gegenpruefung verschiedene Zahlen '
  'nennen,\n')
w('steht hier die der Gegenpruefung; die andere steht in der Spalte '
  '"Warum".\n\n')
w('| Verdikt | Klassen | Funde | Bedeutung |\n|---|---:|---:|---|\n')
_VBED = [
    ('GEBAUT', 'im Code, mit A/B belegt'),
    ('gruen', 'Klasse bestaetigt, Gate baubar - aufgreifen'),
    ('gelb', 'Klasse real, Bauanleitung nachweislich falsch oder unfertig'),
    ('Vertrag', 'kein Gate, sondern eine offene Entscheidung ueber den '
                'Meldevertrag - erst festlegen, dann neu zaehlen'),
    ('ungeprueft', 'Zahl steht, kein Skeptiker hat draufgeschaut'),
    ('rot', 'widerlegt - NICHT erneut aufgreifen ohne neuen Befund'),
    ('erledigt', 'Klasse existiert nicht mehr'),
    ('nur benannt', 'im Audit beschrieben, nie gezaehlt'),
]
for _v, _bed in _VBED:
    if _v in _bilanz:
        w('| **%s** | %d | %s | %s |\n'
          % (_v, _bilanz[_v][0],
             de(_bilanz[_v][1]) if _bilanz[_v][1] else '-', _bed))
w('| Summe | %d | | |\n\n' % _klassen_ges)
_gr_gruen = max([k for k in _KLASSEN
                 if k[3] == 'GEZAEHLT' and k[4] == 'gruen'],
                key=lambda k: k[2])
w('Die groesste GEZAEHLTE noch offene Klasse ist **%s %s**\n'
  % (_groesste_offen[0], _groesste_offen[1].split(' (')[0]))
w('mit %s Funden, Verdikt %s. Die groesste **gruene** ist %s %s mit\n'
  % (de(_groesste_offen[2]), _groesste_offen[4], _gr_gruen[0],
     _gr_gruen[1].split(' (')[0]))
w('%s - und die haengt noch an einem Vorfix. Das ist das ehrliche\n'
  % de(_gr_gruen[2]))
w('Verhaeltnis zwischen "viel gezaehlt" und "sicher baubar": von %s\n'
  % de(_gezaehlt_ges))
w('gezaehlten Funden sind %s gruen.\n\n' % de(_gruen_ges))
w('Die %s vollgezaehlten Funde von %s stehen daneben und liegen anders:\n'
  % (de(_voll_ges), ', '.join(_voll_regeln)))
w('%s sind dateilokal loesbar, aber nur %s tragen ein gruenes Verdikt.\n'
  % (de(_S1_DL),
     de(sum(k[2] for k in _KLASSEN
            if k[3] == 'VOLLZAEHLUNG' and k[4] == 'gruen'))))
w('Die %s gelben haengen an einer je benannten Bauauflage - das\n'
  % de(sum(k[2] for k in _KLASSEN
           if k[3] == 'VOLLZAEHLUNG' and k[4] == 'gelb')))
w('`OwnsObjects`-Argument lesen, kein unbedingter Ausstieg vor dem Free,\n')
w('das Owner-Argument wirklich pruefen. Der Vorsprung dieser Methode\n')
w('liegt woanders: wer die Klasse selbst zaehlt statt eines Praedikats,\n')
w('kann sich beim Schritt "Praedikat != Klasse" nicht mehr irren - und\n')
w('genau der hat oben die Haelfte der gezaehlten Masse gekostet.\n\n')

w('### Gebaut (Herkunft A/B)\n\n')
w('| Regel | Klasse | Drops | drop-only | Gate | Was dabei zu wissen ist |\n')
w('|---|---|---:|---|---|---|\n')
for _k in sorted([x for x in _KLASSEN if x[4] == 'GEBAUT'],
                 key=lambda x: -x[2]):
    w('| %s | %s | %s | %s | %s | %s |\n'
      % (_k[0], _k[1], de(_k[2]), _k[5], _k[6], _k[7]))
w('\n> Alle vier sind im Messstand rw23 enthalten - SCA091 und SCA070 seit\n')
w('> heute. Ihre Zeilen zeigen jetzt die Fundzahl NACH dem Gate - aber\n')
w('> ihre Audit-Quoten gelten wie bei SCA011/SCA047/SCA106/SCA168 noch\n')
w('> fuer eine Grundgesamtheit, die es so nicht mehr gibt. Wer diese beiden\n')
w('> Posten plant, misst zuerst nach. Und SCA091 ist kein Drop-Paket,\n')
w('> sondern ein Tausch: 467 falsche Funde gehen, 401 vorher unsichtbare\n')
w('> richtige kommen.\n\n')

w('### Die %d Regeln mit harten Klassendaten\n\n' % len(_MITTABELLE))
w('Je Regel eine Tabelle, sortiert nach Verdikt und dann nach Groesse.\n')
w('Die Zeile unter der Ueberschrift sagt, wie sich die harten Daten zur\n')
w('Audit-Akte vom 15.08. verhalten - ohne sie liest sich die Tabelle so,\n')
w('als haette das Audit all das benannt. Klassen der Akte, die von den\n')
w('harten Daten NICHT eingeholt sind, stehen mit Herkunft `LEER` in\n')
w('derselben Tabelle.\n\n')
for _r in _MITTABELLE:
    _z = Z[_r]
    w('#### %s %s - Rang %s der Arbeitsliste, %s Funde, ~%s FP\n\n'
      % (_r, _z['name'], _rang.get(_r, '-'), de(_z['n_ohne_fix']),
         de(_z['fpm_nutzer'] or 0)))
    w('%s\n\n' % _ZAEHL_NOTIZ[_r])
    w('| Klasse | Groesse | Herkunft | Verdikt | drop-only | Gate-Idee '
      '| Warum dieses Verdikt |\n')
    w('|---|---:|---|---|---|---|---|\n')
    _rows = [(_VERDIKT_RANG[k[4]], -k[2], k[1], de(k[2]) if k[2] else '-',
              k[3], k[4], k[5], k[6], k[7]) for k in klassen_von(_r)]
    for _nm, _smp, _fix in audit_offen(_r):
        _rows.append((_VERDIKT_RANG['nur benannt'], 0, _nm, '-', 'LEER',
                      'nur benannt',
                      '?', _fix,
                      'im Audit vom 15.08. beschrieben (%s), nie gezaehlt - '
                      'wer sie aufgreift, misst zuerst ihre Groesse'
                      % (('%d von 24 im Sample' % _smp) if _smp is not None
                         else 'ohne Sample-Treffer')))
    for _row in sorted(_rows):
        w('| %s | %s | %s | **%s** | %s | %s | %s |\n' % _row[2:])
    w('\n')

w('### Nur benannt: die uebrigen %d Regeln der Top-25\n\n'
  % len(set(x[0] for x in _nur_benannt)))
w('Diese Klassen stehen in den Audit-Akten vom 15.08. mit Mechanismus und\n')
w('Fix-Idee, aber ihre Groesse ist NIE gemessen worden - die Zahl in der\n')
w('Spalte "im Sample" ist der Treffer in einer 24er-Ziehung, keine\n')
w('Klassengroesse. Wer eine davon aufgreift, zaehlt sie zuerst.\n\n')
w('| Regel | Rang | Klasse | im Sample | Fix-Idee (Kurzform, Akte hat den '
  'Volltext) |\n')
w('|---|--:|---|:--:|---|\n')
for _r, _nm, _smp, _fix in sorted(_nur_benannt, key=lambda x: _rang[x[0]]):
    w('| %s | %d | %s | %s | %s |\n'
      % (_r, _rang[_r], _nm, ('%d/24' % _smp) if _smp is not None else '-',
         _fix))
w('\n> Volltext je Regel: `Todo_Funde_Detector_<ID>_2026-08-15.md`,\n')
w('> Abschnitt "## FP-Klassen" (Mechanismus, Belegstellen, Fix-Idee).\n')
w('> Ueber alle 142 Akten sind es %d benannte Klassen; hier stehen die\n'
  % sum(FPKLASSEN.values()))
w('> %d der Top-25-Regeln ohne harte Daten, %d weitere in den Tabellen\n'
  % (len(_nur_benannt), _nb_in_tabelle))
w('> darueber.\n\n')

w('## Alle Regeln mit Funden\n\n')
w('| Regel | Detektor | Tier | Funde | Fixture | Nutzer | E | W | N '
  '| Quote | Basis | FP-Masse | Stand |\n')
w('|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|\n')
for z in sorted(zeilen, key=lambda z: -z['n']):
    if not z['n']:
        continue
    w('| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n'
      % (z['rid'], z['name'], z['tier'], de(z['n']), de(z['n_fix']),
         de(z['n_ohne_fix']), de(z['err']), de(z['warn']), de(z['note']),
         pz(z['quote']) if z['quote'] is not None else '-',
         basis_txt(z),
         ('~' + de(z['fpm'])) if z['fpm'] is not None else '-',
         stand_txt(z)))

w('\n## Herkunft der nicht-auditierten Quoten\n\n')
w('Jede Quote, die nicht die rohe Audit-Stichprobe ist, mit ihrer\n')
w('Herleitung - damit nachvollziehbar bleibt, was gemessen und was\n')
w('gerechnet wurde:\n\n')
for e in sorted(_ABGELEITET):
    z = Z[e[0]]
    w('* **%s %s** - %s, %s: %s\n'
      % (e[0], z['name'], pz(e[1], 2), basis_txt(z), e[4]))

nf = [z for z in zeilen if not z['n']]
w('\n## Regeln OHNE Funde in rw23 (%d)\n\n' % len(nf))
w(', '.join(z['rid'] + (' (%s)' % z['fix'] if z['fix'] else '')
            for z in sorted(nf, key=lambda z: z['rid'])) + '\n')
out.close()

print('Todo_FpUebersicht_2026-08-26.md geschrieben')
print('strict : %s Funde | FP-Masse ~%s | %s'
      % (de(ges_n), de(ges_fpm), pz(100.0 * ges_fpm / ges_n, 2)))
for name, prof, ff, regeln, filt, _q in SICHTEN:
    n, f = sicht(regeln, filt)
    print('%-38s %9s Funde | ~%6s FP | %s'
          % (name, de(n), de(f), pz(100.0 * f / n if n else 0, 2)))
print('Fixture-Filter droppt %s (%s)'
      % (de(ges_fix), pz(100.0 * ges_fix / ges_n)))
print('Klassen sichtbar: %d (%s)'
      % (_klassen_ges, ', '.join('%s %d' % (h, _herk[h])
                                 for h in ('A/B', 'VOLLZAEHLUNG', 'GEZAEHLT',
                                           'GESCHAETZT', 'LEER')
                                 if h in _herk)))
print('  Verdikte: %s' % ', '.join(
    '%s %d' % (v, _bilanz[v][0]) for v, _ in _VBED if v in _bilanz))
print('  gezaehlte Masse %s, davon rot %s (%s)'
      % (de(_gezaehlt_ges), de(_rot_ges),
         pz(100.0 * _rot_ges / _gezaehlt_ges)))
print('  groesste GEZAEHLTE offene Klasse: %s %s = %s (%s)'
      % (_groesste_offen[0], _groesste_offen[1].split(' (')[0],
         de(_groesste_offen[2]), _groesste_offen[4]))
print('  vollgezaehlt %s: %s FP in %d Klassen - dateilokal %s / K1 %d / '
      'nicht loesbar %d / Vertrag %d'
      % (', '.join(_voll_regeln), de(_voll_ges),
         len([k for k in _KLASSEN if k[3] == 'VOLLZAEHLUNG']),
         de(_S1_DL), _S1_K1, _S1_NL, _S1_VT))
