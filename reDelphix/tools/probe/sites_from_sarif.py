"""Zieht aus einem SARIF-Lauf die Fundstellen einer Regel als Liste
'Datei<TAB>Zeile' fuer RdxCorpusProbe. Streamt zeilenweise (huebsch
formatiertes SARIF; kein json.load - die Referenzlaeufe sind > 700 MB).

  python sites_from_sarif.py <lauf.sarif> <RuleId> <Korpuswurzel> <sites.txt> [N seed]

Mit N und seed: reproduzierbare Zufallsstichprobe von N Stellen. Die
Korpuswurzel ersetzt die uriBaseId (SRCROOT) des Laufs. Die uri wird
prozent-dekodiert (der Export kodiert '%', ' ', '#', '?'); file:-uris
(Dateien ausserhalb der Scanwurzel) bleiben absolut, fuer sie gilt die
Korpuswurzel nicht. Stellen, deren Datei es nicht gibt, meldet das Skript
am Ende als Warnung - ein falscher Wurzelpfad faellt so sofort auf, statt
nur die Aktiv-Quote der Probe zu druecken.

Exit 2 bei falschem Aufruf, nicht lesbarer Eingabe oder nicht
schreibbarer Ausgabe.
"""
import json
import os
import random
import re
import sys
import urllib.parse


def fail(msg):
    sys.stderr.write(msg + '\n')
    sys.exit(2)


def to_path(root, uri):
    """SARIF-uri -> Windows-Pfad. Erst das Schema abtrennen, dann
    dekodieren - wie tools/rw_audit_sample.py und fp_audit_group.py.
      'Some%20Dir/x.pas'       -> <root>\\Some Dir\\x.pas
      'file:///C:/a%20b/y.pas' -> C:\\a b\\y.pas
      'file://srv/sh/z.pas'    -> \\\\srv\\sh\\z.pas
    """
    if uri.startswith('file:///'):
        return urllib.parse.unquote(uri[8:]).replace('/', '\\')
    if uri.startswith('file://'):
        return '\\\\' + urllib.parse.unquote(uri[7:]).replace('/', '\\')
    return root + '\\' + urllib.parse.unquote(uri).replace('/', '\\')


if len(sys.argv) < 5:
    print(__doc__)
    sys.exit(2)
src, rule, root, out = sys.argv[1:5]
try:
    n_sample = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    seed = int(sys.argv[6]) if len(sys.argv) > 6 else 0
except ValueError:
    sys.stderr.write(__doc__ + '\n')
    fail('N und seed muessen ganze Zahlen sein.')
if n_sample < 0:
    fail('N darf nicht negativ sein.')

re_rule = re.compile(r'^\s*"ruleId":\s*"([A-Z0-9]+)"')
re_uri = re.compile(r'^\s*"uri":\s*"(.*?)",?\s*$')
re_line = re.compile(r'^\s*"startLine":\s*(\d+)')

sites = []
cur = None
try:
    with open(src, 'r', encoding='utf-8-sig') as f:
        for line in f:
            m = re_rule.match(line)
            if m:
                if cur and 'uri' in cur and 'line' in cur:
                    sites.append(cur)
                cur = {} if m.group(1) == rule else None
                continue
            if cur is None:
                continue
            if 'uri' not in cur:
                m = re_uri.match(line)
                if m:
                    cur['uri'] = json.loads('"' + m.group(1) + '"')
                    continue
            if 'line' not in cur:
                m = re_line.match(line)
                if m:
                    cur['line'] = int(m.group(1))
except OSError as e:
    fail('%s: %s' % (src, e.strerror or e))
except UnicodeDecodeError as e:
    fail('%s: kein UTF-8 (%s)' % (src, e.reason))
if cur and 'uri' in cur and 'line' in cur:
    sites.append(cur)

if n_sample and n_sample < len(sites):
    sites = random.Random(seed).sample(sites, n_sample)

root = root.rstrip('\\/')
missing = 0
exists = {}
try:
    with open(out, 'w', encoding='utf-8') as f:
        for s in sites:
            path = to_path(root, s['uri'])
            if path not in exists:
                exists[path] = os.path.isfile(path)
            if not exists[path]:
                missing += 1
            f.write(path + '\t' + str(s['line']) + '\n')
except OSError as e:
    fail('%s: %s' % (out, e.strerror or e))
print(f'{rule}: {len(sites)} Stellen -> {out}')
if missing:
    sys.stderr.write(f'WARNUNG: {missing} Stellen: Datei fehlt '
                     f'(Korpuswurzel {root} richtig?)\n')
