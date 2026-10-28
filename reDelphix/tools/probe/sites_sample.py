"""Zieht aus einem SARIF-Lauf je Regel eine reproduzierbare Stichprobe von
Fundstellen fuer RdxActionProbe (Realworld-Probe der Editorhilfen, Entscheid
E3). Streamt zeilenweise wie sites_from_sarif.py (huebsch formatiertes
SARIF; kein json.load - die Referenzlaeufe sind > 700 MB), mit derselben
uri-Dekodierung und Korpuswurzel-Ersetzung.

  python sites_sample.py <lauf.sarif> <Korpuswurzel> <sites.tsv>
         [--rules SCA017,SCA044 | --catalog [sca-rules.json]]
         [--n 100] [--seed 1] [--cap 0.25] [--counts counts.tsv]
  python sites_sample.py --selftest

Welche Regeln: --rules (Komma-Liste); sonst die Regeln, deren Funde im SARIF
properties.editorHelp tragen (Schalter --sarif-editor-help, Zweig
e/HilfeExport: "editorHelp": ["SCA017:changes:slug", "SCA017.2:changes:slug"]
im properties-Bag des Results - die RuleId ist der Teil vor ':' ohne '.N')
bzw. im Regelblock tool.driver.rules properties.editorHelp = true; sonst
--catalog: alle mit "editorHelp": true im Regelkatalog (Vorgabe
rules/sca-rules.json des Checkouts). Ohne alles: Exit 2.

Je Regel:
  * Stellen gleicher Datei, Zeile und Meldung zaehlen einmal (zwei Funde
    einer Regel auf einer Zeile mit verschiedener Meldung bleiben zwei).
  * Dateien gleichen Inhalts (SHA-1 der Bytes; Kopien derselben Bibliothek
    in mehreren Repos) zaehlen einmal: es bleibt die Datei mit dem kleinsten
    Pfad, die Stellen der Kopien fallen weg. Eine Datei, die es nicht gibt,
    faellt ebenso weg (Warnung am Ende - falsche Korpuswurzel?).
  * Stichprobe N (--n, Vorgabe 100), reproduzierbar mit --seed (je Regel
    ein eigener Zufallsstrom aus seed und RuleId - eine weitere Regel in
    der Liste aendert die Stichproben der anderen nicht).
  * Deckel je Repo (erster Pfadteil unter der Korpuswurzel; bei file:-uris
    der erste Ordner unter dem Laufwerk bzw. der Freigabe): hoechstens
    --cap (Vorgabe 0,25) der Stichprobe, mindestens 1 Stelle. Reichen die
    Repos dafuer nicht, wird die Stichprobe kleiner (die Zusammenfassung
    nennt es) - der Deckel gilt vor der Groesse.

sites.tsv (UTF-8 ohne BOM, LF, sortiert nach Datei, Zeile, Regel), je
Stelle sieben Spalten:
  Datei<TAB>Zeile<TAB>RuleId<TAB>Meldung<TAB>EndLine<TAB>variant<TAB>confidence
Meldung = message.text, EndLine = region.endLine (leer: einzeilig), variant
und confidence aus dem properties-Bag (leer, wenn das SARIF sie nicht
fuehrt - confidence nur bei aktiver Evidenz-Politik, variant nur SCA001).
Kodierung der Textspalten wie die CSV der Probe: Backslash als \\,
Zeilenumbruch als \n, einzelnes CR als \r, dazu TAB als \t - umkehrbar.
Die Probe nimmt damit den Fund aus dem SARIF, wenn ihr Einzeldatei-Scan ihn
nicht liefert (Quelle 'sarif').

counts.tsv (--counts, Vorgabe neben sites.tsv), je Regel der Auswahl die
Grundgesamtheit: RuleId<TAB>Funde<TAB>gezogen<TAB>Repos<TAB>ReposGesamt -
Funde = alle Results der Regel im SARIF (vor jeder Bereinigung), gezogen =
Stellen der Stichprobe, Repos = Repos der Stichprobe, ReposGesamt = Repos
mit mindestens einem Fund der Regel.

Exit 2 bei falschem Aufruf, nicht lesbarer Eingabe oder nicht schreibbarer
Ausgabe; --selftest: 0 gruen, 1 rot.
"""
import doctest
import hashlib
import json
import os
import random
import re
import sys
import tempfile
import urllib.parse

BACKSLASH = chr(92)
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
DEFAULT_CATALOG = os.path.join(REPO, 'rules', 'sca-rules.json')

RE_RESULT_RULE = re.compile(r'^\s*"ruleId":\s*"([A-Za-z0-9_]+)"')
RE_URI = re.compile(r'^\s*"uri":\s*"(.*)"\s*,?\s*$')
RE_TEXT = re.compile(r'^\s*"text":\s*"(.*)"\s*,?\s*$')
RE_LINE = re.compile(r'^\s*"startLine":\s*(\d+)')
RE_END_LINE = re.compile(r'^\s*"endLine":\s*(\d+)')
RE_CONFIDENCE = re.compile(r'^\s*"confidence":\s*"(.*)"\s*,?\s*$')
RE_VARIANT = re.compile(r'^\s*"variant":\s*"(.*)"\s*,?\s*$')
RE_RULE_ID = re.compile(r'^\s*"id":\s*"([A-Za-z0-9_]+)"')
RE_EDITOR_HELP_TRUE = re.compile(r'^\s*"editorHelp":\s*true\b')
RE_EDITOR_HELP_ARRAY = re.compile(r'^\s*"editorHelp":\s*\[(.*)$')
RE_JSON_STRING = re.compile(r'"((?:[^"' + BACKSLASH * 2 + r']|' + BACKSLASH * 2
                            + r'.)*)"')


def fail(msg):
    sys.stderr.write(msg + '\n')
    sys.exit(2)


def json_str(raw):
    """Der Inhalt eines JSON-String-Literals (ohne die Anfuehrungszeichen)."""
    return json.loads('"' + raw + '"')


def tsv_enc(s):
    """Textspalte TSV-sicher und umkehrbar (wie die CSV der Probe, dazu TAB).

    >>> tsv_enc('a' + BACKSLASH + 'b') == 'a' + BACKSLASH * 2 + 'b'
    True
    >>> tsv_enc('x\\r\\ny\\tz\\rw') == 'x' + BACKSLASH + 'ny' + BACKSLASH + 'tz' + BACKSLASH + 'rw'
    True
    >>> tsv_dec(tsv_enc('p' + BACKSLASH + 'n\\tq\\nr')) == 'p' + BACKSLASH + 'n\\tq\\nr'
    True
    """
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == BACKSLASH:
            out.append(BACKSLASH * 2)
        elif c == '\n':
            out.append(BACKSLASH + 'n')
        elif c == '\r':
            if i + 1 < len(s) and s[i + 1] == '\n':
                i += 1
                out.append(BACKSLASH + 'n')
            else:
                out.append(BACKSLASH + 'r')
        elif c == '\t':
            out.append(BACKSLASH + 't')
        else:
            out.append(c)
        i += 1
    return ''.join(out)


def tsv_dec(s):
    """Umkehrung von tsv_enc (die Probe dekodiert ebenso)."""
    table = {'n': '\n', 'r': '\r', 't': '\t', BACKSLASH: BACKSLASH}
    return re.sub(BACKSLASH * 2 + '(.)',
                  lambda m: table.get(m.group(1), m.group(1)), s)


def to_path(root, uri):
    """SARIF-uri -> Windows-Pfad (wie sites_from_sarif.py). Erst das Schema
    abtrennen, dann dekodieren.

    >>> to_path('D:' + BACKSLASH + 'rw', 'Some%20Dir/x.pas') == BACKSLASH.join(['D:', 'rw', 'Some Dir', 'x.pas'])
    True
    >>> to_path('D:', 'file:///C:/a%20b/y.pas') == BACKSLASH.join(['C:', 'a b', 'y.pas'])
    True
    >>> to_path('D:', 'file://srv/sh/z.pas') == BACKSLASH * 2 + BACKSLASH.join(['srv', 'sh', 'z.pas'])
    True
    """
    if uri.startswith('file:///'):
        return urllib.parse.unquote(uri[8:]).replace('/', BACKSLASH)
    if uri.startswith('file://'):
        return BACKSLASH * 2 + urllib.parse.unquote(uri[7:]).replace('/', BACKSLASH)
    return root + BACKSLASH + urllib.parse.unquote(uri).replace('/', BACKSLASH)


def repo_of(uri):
    """Der Repo-Schluessel einer uri: erster Pfadteil unter der Korpuswurzel;
    bei file:-uris Laufwerk bzw. Freigabe samt erstem Ordner.

    >>> repo_of('mORMot2/src/core/x.pas')
    'mormot2'
    >>> repo_of('file:///C:/libs/jcl/a.pas')
    'c:/libs'
    >>> repo_of('file://srv/share/b.pas')
    '//srv/share'
    >>> repo_of('single.pas')
    'single.pas'
    """
    if uri.startswith('file:///'):
        parts = urllib.parse.unquote(uri[8:]).split('/')
        return '/'.join(parts[:2]).lower()
    if uri.startswith('file://'):
        parts = urllib.parse.unquote(uri[7:]).split('/')
        return '//' + '/'.join(parts[:2]).lower()
    return urllib.parse.unquote(uri).split('/')[0].lower()


def help_rule(entry):
    """RuleId eines editorHelp-Eintrags 'SCA017.2:changes:slug'.

    >>> help_rule('SCA017:changes:wrap'), help_rule('SCA017.2:none:delete')
    ('SCA017', 'SCA017')
    """
    return entry.split(':', 1)[0].split('.', 1)[0].strip()


def read_sarif(path, wanted=None):
    """(Stellen, Regeln mit editorHelp, Funde je Regel, Repos je Regel).
    Stellen: Liste von Dicts rule, uri, line, msg, end, variant, confidence;
    wanted = Menge von RuleIds oder None (alle). Gezaehlt werden alle
    Results, auch die nicht gewollter Regeln."""
    sites = []
    helped = set()
    totals = {}
    repos = {}
    cur = None          # das laufende Result einer gewollten Regel
    in_result = None    # RuleId des laufenden Results (jeder Regel)
    rule_def = None     # "id" im Regelblock (vor den Results)
    in_help = False     # innerhalb eines mehrzeiligen editorHelp-Arrays

    def close():
        if cur and 'uri' in cur and 'line' in cur:
            sites.append(cur)

    try:
        with open(path, 'r', encoding='utf-8-sig') as f:
            for line in f:
                if in_help:
                    for raw in RE_JSON_STRING.findall(line):
                        helped.add(help_rule(json_str(raw)))
                    if ']' in line:
                        in_help = False
                    continue
                m = RE_RESULT_RULE.match(line)
                if m:
                    close()
                    rid = m.group(1)
                    in_result = rid
                    totals[rid] = totals.get(rid, 0) + 1
                    cur = ({'rule': rid, 'msg': '', 'end': 0, 'variant': '',
                            'confidence': ''}
                           if wanted is None or rid in wanted else None)
                    continue
                m = RE_EDITOR_HELP_ARRAY.match(line)
                if m:
                    rest = m.group(1)
                    for raw in RE_JSON_STRING.findall(rest):
                        helped.add(help_rule(json_str(raw)))
                    in_help = ']' not in rest
                    continue
                if in_result is None:
                    # Regelblock (tool.driver.rules): "id" und editorHelp.
                    m = RE_RULE_ID.match(line)
                    if m:
                        rule_def = m.group(1)
                        continue
                    if rule_def and RE_EDITOR_HELP_TRUE.match(line):
                        helped.add(rule_def)
                    continue
                if cur is None:
                    # Nicht gewollte Regel: nur ihre Repos (ReposGesamt).
                    m = RE_URI.match(line)
                    if m:
                        repos.setdefault(in_result, set()).add(
                            repo_of(json_str(m.group(1))))
                    continue
                if 'uri' not in cur:
                    m = RE_TEXT.match(line)
                    if m and not cur['msg']:
                        cur['msg'] = json_str(m.group(1))
                        continue
                    m = RE_URI.match(line)
                    if m:
                        cur['uri'] = json_str(m.group(1))
                        repos.setdefault(in_result, set()).add(
                            repo_of(cur['uri']))
                        continue
                if 'line' not in cur:
                    m = RE_LINE.match(line)
                    if m:
                        cur['line'] = int(m.group(1))
                        continue
                if not cur['end']:
                    m = RE_END_LINE.match(line)
                    if m:
                        cur['end'] = int(m.group(1))
                        continue
                if not cur['confidence']:
                    m = RE_CONFIDENCE.match(line)
                    if m:
                        cur['confidence'] = json_str(m.group(1))
                        continue
                if not cur['variant']:
                    m = RE_VARIANT.match(line)
                    if m:
                        cur['variant'] = json_str(m.group(1))
    except OSError as e:
        fail('%s: %s' % (path, e.strerror or e))
    except UnicodeDecodeError as e:
        fail('%s: kein UTF-8 (%s)' % (path, e.reason))
    close()
    return sites, helped, totals, repos


def catalog_rules(path):
    """RuleIds mit "editorHelp": true im Regelkatalog."""
    try:
        with open(path, 'r', encoding='utf-8-sig') as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        fail('%s: %s' % (path, e))
    return sorted(r['id'] for r in data.get('rules', [])
                  if r.get('editorHelp') is True and 'id' in r)


class Hasher:
    """SHA-1 des Dateiinhalts, je Pfad einmal gelesen; None, wenn die Datei
    fehlt oder nicht lesbar ist."""

    def __init__(self):
        self.memo = {}

    def __call__(self, path):
        if path not in self.memo:
            try:
                with open(path, 'rb') as f:
                    self.memo[path] = hashlib.sha1(f.read()).hexdigest()
            except OSError:
                self.memo[path] = None
        return self.memo[path]


def sample_rule(rule, cands, root, n, seed, cap, hasher):
    """Stichprobe einer Regel. cands: Liste von Stellen-Dicts (uri, line,
    msg ...). Liefert (Auswahl als Liste von Dicts mit 'path' und 'repo',
    Statistik)."""
    stats = {'candidates': 0, 'missing': 0, 'dup_content': 0}
    seen = set()
    rows = []
    for c in cands:
        path = to_path(root, c['uri'])
        key = (path.lower(), c['line'], c.get('msg', ''))
        if key in seen:
            continue
        seen.add(key)
        row = dict(c)
        row['path'] = path
        row['repo'] = repo_of(c['uri'])
        rows.append(row)
    stats['candidates'] = len(rows)
    # Inhalts-Dubletten: je Hash bleibt der kleinste Pfad.
    keep = {}
    for path in sorted({r['path'] for r in rows}, key=str.lower):
        h = hasher(path)
        if h is None:
            continue
        keep.setdefault(h, path)
    kept = []
    for r in rows:
        h = hasher(r['path'])
        if h is None:
            stats['missing'] += 1
        elif keep[h] != r['path']:
            stats['dup_content'] += 1
        else:
            kept.append(r)
    kept.sort(key=lambda r: (r['path'].lower(), r['line'], r.get('msg', '')))
    rng = random.Random('%s:%s' % (seed, rule))
    rng.shuffle(kept)
    limit = max(1, int(cap * n))
    per_repo = {}
    out = []
    for r in kept:
        if len(out) >= n:
            break
        if per_repo.get(r['repo'], 0) >= limit:
            continue
        per_repo[r['repo']] = per_repo.get(r['repo'], 0) + 1
        out.append(r)
    stats['sample'] = len(out)
    stats['repos'] = len(per_repo)
    stats['cap'] = limit
    return out, stats


def parse_args(argv):
    opts = {'rules': None, 'catalog': None, 'n': 100, 'seed': 1, 'cap': 0.25,
            'counts': None}
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--rules' and i + 1 < len(argv):
            opts['rules'] = [r.strip() for r in argv[i + 1].split(',') if r.strip()]
            i += 2
        elif a == '--catalog':
            # Ein Pfad dahinter nur, wenn er auf .json endet - sonst der
            # Katalog des Checkouts (rules/sca-rules.json).
            if i + 1 < len(argv) and argv[i + 1].lower().endswith('.json'):
                opts['catalog'] = argv[i + 1]
                i += 2
            else:
                opts['catalog'] = DEFAULT_CATALOG
                i += 1
        elif a == '--counts' and i + 1 < len(argv):
            opts['counts'] = argv[i + 1]
            i += 2
        elif a in ('--n', '--seed', '--cap') and i + 1 < len(argv):
            try:
                opts[a[2:]] = (float if a == '--cap' else int)(argv[i + 1])
            except ValueError:
                fail('%s erwartet eine Zahl, nicht %r' % (a, argv[i + 1]))
            i += 2
        elif a.startswith('--'):
            fail('unbekannter Schalter: %s\n%s' % (a, __doc__))
        else:
            pos.append(a)
            i += 1
    if len(pos) != 3:
        fail(__doc__)
    if opts['n'] < 1 or not 0 < opts['cap'] <= 1:
        fail('--n muss >= 1 und --cap in (0, 1] sein.')
    return pos, opts


def write_lines(path, lines):
    try:
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            for line in lines:
                f.write(line + '\n')
    except OSError as e:
        fail('%s: %s' % (path, e.strerror or e))


def run(argv, out=sys.stdout):
    (src, root, dest), opts = parse_args(argv)
    root = root.rstrip('/' + BACKSLASH)
    counts_path = opts['counts'] or os.path.join(
        os.path.dirname(os.path.abspath(dest)), 'counts.tsv')
    wanted = set(opts['rules']) if opts['rules'] else None
    sites, helped, totals, repos = read_sarif(src, wanted)
    if wanted is None:
        if helped:
            wanted = helped
            out.write('Regeln mit editorHelp im SARIF: %d\n' % len(wanted))
        elif opts['catalog']:
            wanted = set(catalog_rules(opts['catalog']))
            out.write('Regeln mit editorHelp im Katalog %s: %d\n'
                      % (opts['catalog'], len(wanted)))
        else:
            fail('Das SARIF fuehrt kein properties.editorHelp - Regeln mit '
                 '--rules oder --catalog angeben.')
    by_rule = {}
    for s in sites:
        if s['rule'] in wanted:
            by_rule.setdefault(s['rule'], []).append(s)
    hasher = Hasher()
    chosen = []
    counts = ['RuleId\tFunde\tgezogen\tRepos\tReposGesamt']
    missing = 0
    out.write('%-8s %8s %10s %8s %8s %10s %6s %4s\n' % (
        'Regel', 'Funde', 'Kandidaten', 'fehlt', 'Dublette', 'Stichprobe',
        'Repos', 'Deckel'))
    for rule in sorted(wanted):
        picked, st = sample_rule(rule, by_rule.get(rule, []), root,
                                 opts['n'], opts['seed'], opts['cap'], hasher)
        missing += st['missing']
        short = ' (kleiner als --n)' if st['sample'] < opts['n'] else ''
        out.write('%-8s %8d %10d %8d %8d %10d %6d %4d%s\n' % (
            rule, totals.get(rule, 0), st['candidates'], st['missing'],
            st['dup_content'], st['sample'], st['repos'], st['cap'], short))
        counts.append('%s\t%d\t%d\t%d\t%d' % (
            rule, totals.get(rule, 0), st['sample'], st['repos'],
            len(repos.get(rule, ()))))
        chosen.extend(picked)
    chosen.sort(key=lambda r: (r['path'].lower(), r['line'], r['rule'],
                               r.get('msg', '')))
    write_lines(dest, ['\t'.join([
        r['path'], str(r['line']), r['rule'], tsv_enc(r.get('msg', '')),
        str(r['end']) if r.get('end') else '', tsv_enc(r.get('variant', '')),
        tsv_enc(r.get('confidence', ''))]) for r in chosen])
    write_lines(counts_path, counts)
    out.write('%d Stellen -> %s, Grundgesamtheit -> %s\n'
              % (len(chosen), dest, counts_path))
    if missing:
        sys.stderr.write('WARNUNG: %d Stellen: Datei fehlt (Korpuswurzel %s '
                         'richtig?)\n' % (missing, root))
    return chosen


SARIF_HEAD = '''{
  "runs": [
    {
      "tool": {
        "driver": {
          "rules": [
            {
              "id": "SCA017"
            },
            {
              "id": "SCA012"
            }
          ]
        }
      },
      "results": [
'''
SARIF_RESULT = '''        {
          "ruleId": "%s",
          "level": "warning",
          "message": {
            "text": %s
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "%s",
                  "uriBaseId": "SRCROOT"
                },
                "region": {
                  "startLine": %d%s
                }
              }
            }
          ],
          "partialFingerprints": {
            "primaryLocationLineHash": "abc"
          },
          "properties": {
            "confidence": "medium"%s
          }
        },
'''
SARIF_TAIL = '''      ]
    }
  ]
}
'''
# Die editorHelp-Form des Zweigs e/HilfeExport (Result-properties-Bag).
HELP_SCA017 = (',\n            "editorHelp": [\n'
               '              "SCA017:changes:wrap-debug",\n'
               '              "SCA017.2:changes:delete-debug"\n'
               '            ]')
# Die Form im Regelblock (boolean), zweiter Kunst-Lauf.
SARIF_RULES_BOOL = '''{
  "runs": [
    {
      "tool": {
        "driver": {
          "rules": [
            {
              "id": "SCA044",
              "properties": {
                "editorHelp": true
              }
            }
          ]
        }
      },
      "results": [
      ]
    }
  ]
}
'''


def selftest():
    """Doctests plus Laeufe auf einem kleinen Kunst-Korpus: Regelfilter
    (editorHelp im Result und im Regelblock), Deckel je Repo,
    Inhalts-Dubletten, fehlende Dateien, Reproduzierbarkeit, SARIF-Felder
    in sites.tsv, counts.tsv."""
    failed, _ = doctest.testmod(verbose=False)
    ok = failed == 0
    checks = []

    def expect(cond, what):
        checks.append((bool(cond), what))

    with tempfile.TemporaryDirectory(prefix='rdx_sample_') as tmp:
        root = os.path.join(tmp, 'corpus')
        results = []   # (rule, uri, line, msg, end, variant)
        # Fuenf Repos, je 10 Dateien mit eigenem Inhalt und je 4 SCA017-
        # Stellen; repo0 hat eine Kopie von repo1/f0.pas (Dublette).
        for r in range(5):
            for k in range(10):
                d = os.path.join(root, 'repo%d' % r)
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, 'f%d.pas' % k), 'w') as f:
                    f.write('unit f%d_%d;\n' % (r, k))
                for line in (3, 5, 7, 9):
                    results.append(('SCA017', 'repo%d/f%d.pas' % (r, k), line,
                                    'Debug output: writeln', 0, ''))
        with open(os.path.join(root, 'repo0', 'copy.pas'), 'w') as f:
            f.write('unit f1_0;\n')
        results.append(('SCA017', 'repo0/copy.pas', 3, 'm', 0, ''))
        results.append(('SCA017', 'repo0/copy.pas', 3, 'm', 0, ''))  # doppelt
        results.append(('SCA017', 'repo9/missing.pas', 4, 'm', 0, ''))
        results.append(('SCA012', 'repo1/f1.pas', 1, 'long', 0, ''))  # nicht gewollt
        with open(os.path.join(root, 'repo2', 'My Dir.pas'), 'w') as f:
            f.write('unit MyDir;\n')
        tricky = 'a\tb "q" c' + BACKSLASH + 'n\nzwei'
        results.append(('SCA044', 'repo2/My%20Dir.pas', 2, tricky, 4, ''))
        results.append(('SCA044', 'repo2/My%20Dir.pas', 2, 'andere', 0, ''))
        results.append(('SCA001', 'repo3/f1.pas', 2, 'L', 0,
                        'freed-outside-finally'))
        sarif = os.path.join(tmp, 'lauf.sarif')
        with open(sarif, 'w', encoding='utf-8') as f:
            f.write(SARIF_HEAD)
            for i, (rule, uri, line, msg, end, variant) in enumerate(results):
                props = HELP_SCA017 if rule == 'SCA017' else ''
                if variant:
                    props += ',\n            "variant": %s' % json.dumps(variant)
                block = SARIF_RESULT % (
                    rule, json.dumps(msg), uri, line,
                    (',\n                  "endLine": %d' % end) if end else '',
                    props)
                if i == len(results) - 1:
                    block = block.rstrip().rstrip(',') + '\n'
                f.write(block)
            f.write(SARIF_TAIL)
        sites, helped, totals, _repos = read_sarif(sarif)
        expect(helped == {'SCA017'}, 'editorHelp im Result: SCA017 (%r)'
               % sorted(helped))
        expect(totals.get('SCA017') == 203 and totals.get('SCA044') == 2,
               'Funde je Regel gezaehlt (%r)' % totals)
        t = [s for s in sites if s['rule'] == 'SCA044' and s['end'] == 4]
        expect(len(t) == 1 and t[0]['msg'] == tricky
               and t[0]['confidence'] == 'medium',
               'message.text, endLine, confidence gelesen')
        v = [s for s in sites if s['rule'] == 'SCA001']
        expect(len(v) == 1 and v[0]['variant'] == 'freed-outside-finally',
               'variant gelesen')
        quiet = open(os.devnull, 'w')
        try:
            dest1 = os.path.join(tmp, 's1.tsv')
            dest2 = os.path.join(tmp, 's2.tsv')
            dest3 = os.path.join(tmp, 's3.tsv')
            a = run([sarif, root, dest1, '--n', '20', '--seed', '7'], quiet)
            b = run([sarif, root, dest2, '--n', '20', '--seed', '7'], quiet)
            c = run([sarif, root, dest3, '--n', '20', '--seed', '8'], quiet)
        finally:
            quiet.close()
        key = [(r['path'], r['line']) for r in a]
        expect(key == [(r['path'], r['line']) for r in b],
               'gleicher seed -> gleiche Stichprobe')
        expect(open(dest1, 'rb').read() == open(dest2, 'rb').read(),
               'gleicher seed -> gleiche Datei')
        expect(key != [(r['path'], r['line']) for r in c],
               'anderer seed -> andere Stichprobe')
        expect(len(a) == 20, 'N = 20 erreicht (5 Repos, Deckel 5)')
        expect({r['rule'] for r in a} == {'SCA017'},
               'nur Regeln mit editorHelp aus dem SARIF (SCA017)')
        per = {}
        for r in a:
            rel = os.path.relpath(r['path'], root).split(os.sep)[0]
            per[rel] = per.get(rel, 0) + 1
        expect(max(per.values()) <= 5, 'Deckel 25 %% je Repo: %r' % per)
        expect(not any(r['path'].endswith('copy.pas') for r in a),
               'Inhalts-Dublette (copy.pas) faellt weg')
        expect(not any(r['path'].endswith('missing.pas') for r in a),
               'fehlende Datei faellt weg')
        lines = open(dest1, encoding='utf-8').read().splitlines()
        expect(all(len(l.split('\t')) == 7 for l in lines)
               and lines[0].split('\t')[3] == 'Debug output: writeln',
               'TSV: sieben Spalten, Meldung an vierter Stelle')
        counts = open(os.path.join(tmp, 'counts.tsv'),
                      encoding='utf-8').read().splitlines()
        expect(counts[0] == 'RuleId\tFunde\tgezogen\tRepos\tReposGesamt'
               and counts[1] == 'SCA017\t203\t20\t5\t6',
               'counts.tsv: Grundgesamtheit (%r)' % counts[1:])
        with open(os.devnull, 'w') as quiet:
            d = run([sarif, root, os.path.join(tmp, 's4.tsv'), '--rules',
                     'SCA044', '--n', '4', '--cap', '1', '--counts',
                     os.path.join(tmp, 'c4.tsv')], quiet)
        expect(len(d) == 2 and d[0]['path'].endswith('My Dir.pas'),
               '--rules waehlt SCA044, uri dekodiert, zwei Meldungen auf '
               'einer Zeile bleiben zwei')
        row = [l for l in open(os.path.join(tmp, 's4.tsv'),
                               encoding='utf-8').read().splitlines()
               if '\t4\t' in l]
        f4 = row[0].split('\t') if row else []
        expect(len(f4) == 7 and tsv_dec(f4[3]) == tricky and f4[4] == '4'
               and f4[6] == 'medium',
               'Meldung mit TAB/Backslash/Umbruch umkehrbar kodiert, '
               'EndLine, confidence')
        bool_sarif = os.path.join(tmp, 'bool.sarif')
        with open(bool_sarif, 'w', encoding='utf-8') as f:
            f.write(SARIF_RULES_BOOL)
        _s, helped2, _t, _r = read_sarif(bool_sarif)
        expect(helped2 == {'SCA044'}, 'editorHelp: true im Regelblock')
        _p, st = sample_rule('SCA017', [{'uri': 'repo0/f%d.pas' % k,
                                         'line': 3, 'rule': 'SCA017'}
                                        for k in range(10)],
                             root, 8, 1, 0.25, Hasher())
        expect(st['sample'] == 2 and st['cap'] == 2,
               'ein Repo, Deckel 2 -> Stichprobe 2 statt 8')
    for good, what in checks:
        print('  %s  %s' % ('ok  ' if good else 'ROT ', what))
        ok = ok and good
    print('doctest: %d Fehler' % failed)
    print('SELBSTTEST %s: %d Pruefungen' % ('GRUEN' if ok else 'ROT',
                                            len(checks)))
    return 0 if ok else 1


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if sys.argv[1:] == ['--selftest']:
        sys.exit(selftest())
    run(sys.argv[1:])
