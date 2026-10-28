"""Zieht aus einem SARIF-Lauf je Regel eine reproduzierbare Stichprobe von
Fundstellen als 'Datei<TAB>Zeile<TAB>RuleId' fuer RdxActionProbe (Realworld-
Probe der Editorhilfen, Entscheid E3). Streamt zeilenweise wie
sites_from_sarif.py (huebsch formatiertes SARIF; kein json.load - die
Referenzlaeufe sind > 700 MB), mit derselben uri-Dekodierung und
Korpuswurzel-Ersetzung.

  python sites_sample.py <lauf.sarif> <Korpuswurzel> <sites.tsv>
         [--rules SCA017,SCA044 | --catalog [sca-rules.json]]
         [--n 100] [--seed 1] [--cap 0.25]
  python sites_sample.py --selftest

Welche Regeln: --rules (Komma-Liste); sonst die Regeln, die im SARIF
(tool.driver.rules) properties.editorHelp = true tragen, falls der Lauf das
Feld fuehrt; sonst --catalog: alle mit "editorHelp": true im Regelkatalog
(Vorgabe rules/sca-rules.json des Checkouts). Ohne alles: Exit 2.

Je Regel:
  * Stellen gleicher Datei und Zeile zaehlen einmal.
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

Ausgabe: UTF-8 ohne BOM, eine Stelle je Zeile, sortiert nach Datei, Zeile,
Regel (die Probe gruppiert ohnehin nach Datei). Zusammenfassung nach
stdout: je Regel Kandidaten, nach Inhalts-Dubletten, Stichprobe, Repos.

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
RE_URI = re.compile(r'^\s*"uri":\s*"(.*?)",?\s*$')
RE_LINE = re.compile(r'^\s*"startLine":\s*(\d+)')
RE_RULE_ID = re.compile(r'^\s*"id":\s*"([A-Za-z0-9_]+)"')
RE_EDITOR_HELP = re.compile(r'^\s*"editorHelp":\s*true\b')


def fail(msg):
    sys.stderr.write(msg + '\n')
    sys.exit(2)


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


def read_sarif(path, wanted=None):
    """(Stellen, Regeln mit editorHelp im SARIF). Stellen: Liste von
    (ruleId, uri, Zeile); wanted = Menge von RuleIds oder None (alle)."""
    sites = []
    helped = set()
    cur = None
    rule_def = None
    try:
        with open(path, 'r', encoding='utf-8-sig') as f:
            for line in f:
                m = RE_RESULT_RULE.match(line)
                if m:
                    if cur and 'uri' in cur and 'line' in cur:
                        sites.append((cur['rule'], cur['uri'], cur['line']))
                    rid = m.group(1)
                    cur = {'rule': rid} if wanted is None or rid in wanted else None
                    continue
                if cur is None:
                    # Regelblock (tool.driver.rules): "id" und editorHelp.
                    m = RE_RULE_ID.match(line)
                    if m:
                        rule_def = m.group(1)
                        continue
                    if rule_def and RE_EDITOR_HELP.match(line):
                        helped.add(rule_def)
                    continue
                if 'uri' not in cur:
                    m = RE_URI.match(line)
                    if m:
                        cur['uri'] = json.loads('"' + m.group(1) + '"')
                        continue
                if 'line' not in cur:
                    m = RE_LINE.match(line)
                    if m:
                        cur['line'] = int(m.group(1))
    except OSError as e:
        fail('%s: %s' % (path, e.strerror or e))
    except UnicodeDecodeError as e:
        fail('%s: kein UTF-8 (%s)' % (path, e.reason))
    if cur and 'uri' in cur and 'line' in cur:
        sites.append((cur['rule'], cur['uri'], cur['line']))
    return sites, helped


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
    """Stichprobe einer Regel. cands: Liste (uri, Zeile). Liefert (Auswahl
    als Liste (Pfad, Zeile, Repo), Statistik)."""
    stats = {'candidates': 0, 'missing': 0, 'dup_content': 0}
    seen = set()
    rows = []
    for uri, line in cands:
        path = to_path(root, uri)
        if (path.lower(), line) in seen:
            continue
        seen.add((path.lower(), line))
        rows.append((path, line, repo_of(uri)))
    stats['candidates'] = len(rows)
    # Inhalts-Dubletten: je Hash bleibt der kleinste Pfad.
    keep = {}
    for path in sorted({p for p, _l, _r in rows}, key=str.lower):
        h = hasher(path)
        if h is None:
            continue
        keep.setdefault(h, path)
    kept = []
    for path, line, repo in rows:
        h = hasher(path)
        if h is None:
            stats['missing'] += 1
        elif keep[h] != path:
            stats['dup_content'] += 1
        else:
            kept.append((path, line, repo))
    kept.sort(key=lambda r: (r[0].lower(), r[1]))
    rng = random.Random('%s:%s' % (seed, rule))
    rng.shuffle(kept)
    limit = max(1, int(cap * n))
    per_repo = {}
    out = []
    for path, line, repo in kept:
        if len(out) >= n:
            break
        if per_repo.get(repo, 0) >= limit:
            continue
        per_repo[repo] = per_repo.get(repo, 0) + 1
        out.append((path, line, repo))
    stats['sample'] = len(out)
    stats['repos'] = len(per_repo)
    stats['cap'] = limit
    return out, stats


def parse_args(argv):
    opts = {'rules': None, 'catalog': None, 'n': 100, 'seed': 1, 'cap': 0.25}
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


def run(argv, out=sys.stdout):
    (src, root, dest), opts = parse_args(argv)
    root = root.rstrip('/' + BACKSLASH)
    wanted = set(opts['rules']) if opts['rules'] else None
    sites, helped = read_sarif(src, wanted)
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
    for rule, uri, line in sites:
        if rule in wanted:
            by_rule.setdefault(rule, []).append((uri, line))
    hasher = Hasher()
    chosen = []
    missing = 0
    out.write('%-8s %10s %8s %8s %10s %6s %4s\n' % (
        'Regel', 'Kandidaten', 'fehlt', 'Dublette', 'Stichprobe', 'Repos',
        'Deckel'))
    for rule in sorted(wanted):
        picked, st = sample_rule(rule, by_rule.get(rule, []), root,
                                 opts['n'], opts['seed'], opts['cap'], hasher)
        missing += st['missing']
        short = ' (kleiner als --n)' if st['sample'] < opts['n'] else ''
        out.write('%-8s %10d %8d %8d %10d %6d %4d%s\n' % (
            rule, st['candidates'], st['missing'], st['dup_content'],
            st['sample'], st['repos'], st['cap'], short))
        chosen.extend((path, line, rule) for path, line, _repo in picked)
    chosen.sort(key=lambda r: (r[0].lower(), r[1], r[2]))
    try:
        with open(dest, 'w', encoding='utf-8', newline='\n') as f:
            for path, line, rule in chosen:
                f.write('%s\t%d\t%s\n' % (path, line, rule))
    except OSError as e:
        fail('%s: %s' % (dest, e.strerror or e))
    out.write('%d Stellen -> %s\n' % (len(chosen), dest))
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
              "id": "SCA017",
              "properties": {
                "editorHelp": true
              }
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
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "%s",
                  "uriBaseId": "SRCROOT"
                },
                "region": {
                  "startLine": %d
                }
              }
            }
          ]
        },
'''
SARIF_TAIL = '''      ]
    }
  ]
}
'''


def selftest():
    """Doctests plus ein Lauf auf einem kleinen Kunst-Korpus: Regelfilter,
    Deckel je Repo, Inhalts-Dubletten, fehlende Dateien, Reproduzierbarkeit.
    """
    failed, _ = doctest.testmod(verbose=False)
    ok = failed == 0
    checks = []

    def expect(cond, what):
        checks.append((bool(cond), what))

    with tempfile.TemporaryDirectory(prefix='rdx_sample_') as tmp:
        root = os.path.join(tmp, 'corpus')
        results = []
        # Fuenf Repos, je 10 Dateien mit eigenem Inhalt und je 4 SCA017-
        # Stellen; repo0 hat eine Kopie von repo1/f0.pas (Dublette).
        for r in range(5):
            for k in range(10):
                d = os.path.join(root, 'repo%d' % r)
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, 'f%d.pas' % k), 'w') as f:
                    f.write('unit f%d_%d;\n' % (r, k))
                for line in (3, 5, 7, 9):
                    results.append(('SCA017', 'repo%d/f%d.pas' % (r, k), line))
        with open(os.path.join(root, 'repo0', 'copy.pas'), 'w') as f:
            f.write('unit f1_0;\n')
        results.append(('SCA017', 'repo0/copy.pas', 3))
        results.append(('SCA017', 'repo0/copy.pas', 3))   # doppelt im SARIF
        results.append(('SCA017', 'repo9/missing.pas', 4))
        results.append(('SCA012', 'repo1/f1.pas', 1))      # nicht gewollt
        with open(os.path.join(root, 'repo2', 'My Dir.pas'), 'w') as f:
            f.write('unit MyDir;\n')
        results.append(('SCA044', 'repo2/My%20Dir.pas', 2))
        sarif = os.path.join(tmp, 'lauf.sarif')
        with open(sarif, 'w', encoding='utf-8') as f:
            f.write(SARIF_HEAD)
            for i, (rule, uri, line) in enumerate(results):
                block = SARIF_RESULT % (rule, uri, line)
                if i == len(results) - 1:
                    block = block.rstrip().rstrip(',') + '\n'
                f.write(block)
            f.write(SARIF_TAIL)
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
        expect(a == b, 'gleicher seed -> gleiche Stichprobe')
        expect(open(dest1, 'rb').read() == open(dest2, 'rb').read(),
               'gleicher seed -> gleiche Datei')
        expect(a != c, 'anderer seed -> andere Stichprobe')
        expect(len(a) == 20, 'N = 20 erreicht (5 Repos, Deckel 5)')
        expect({rule for _p, _l, rule in a} == {'SCA017'},
               'nur Regeln mit editorHelp aus dem SARIF (SCA017)')
        repos = {}
        for path, _l, _r in a:
            rel = os.path.relpath(path, root).split(os.sep)[0]
            repos[rel] = repos.get(rel, 0) + 1
        expect(max(repos.values()) <= 5, 'Deckel 25 %% je Repo: %r' % repos)
        expect(not any(p.endswith('copy.pas') for p, _l, _r in a),
               'Inhalts-Dublette (copy.pas) faellt weg')
        expect(not any(p.endswith('missing.pas') for p, _l, _r in a),
               'fehlende Datei faellt weg')
        lines = open(dest1, encoding='utf-8').read().splitlines()
        expect(all(len(l.split('\t')) == 3 for l in lines),
               'TSV: Datei, Zeile, Regel')
        with open(os.devnull, 'w') as quiet:
            d = run([sarif, root, os.path.join(tmp, 's4.tsv'), '--rules',
                     'SCA044', '--n', '4'], quiet)
        expect(len(d) == 1 and d[0][0].endswith('My Dir.pas'),
               '--rules waehlt SCA044, uri dekodiert')
        _p, st = sample_rule('SCA017', [('repo0/f%d.pas' % k, 3)
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
