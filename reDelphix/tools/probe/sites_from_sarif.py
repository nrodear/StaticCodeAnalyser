"""Zieht aus einem SARIF-Lauf die Fundstellen einer Regel als Liste
'Datei<TAB>Zeile' fuer RdxCorpusProbe. Streamt zeilenweise (huebsch
formatiertes SARIF; kein json.load - die Referenzlaeufe sind > 700 MB).

  python sites_from_sarif.py <lauf.sarif> <RuleId> <Korpuswurzel> <sites.txt> [N seed]

Mit N und seed: reproduzierbare Zufallsstichprobe von N Stellen. Die
Korpuswurzel ersetzt die uriBaseId (SRCROOT) des Laufs.
"""
import json
import random
import re
import sys

if len(sys.argv) < 5:
    print(__doc__)
    sys.exit(2)
src, rule, root, out = sys.argv[1:5]
n_sample = int(sys.argv[5]) if len(sys.argv) > 5 else 0
seed = int(sys.argv[6]) if len(sys.argv) > 6 else 0

re_rule = re.compile(r'^\s*"ruleId":\s*"([A-Z0-9]+)"')
re_uri = re.compile(r'^\s*"uri":\s*"(.*?)",?\s*$')
re_line = re.compile(r'^\s*"startLine":\s*(\d+)')

sites = []
cur = None
with open(src, 'r', encoding='utf-8') as f:
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
if cur and 'uri' in cur and 'line' in cur:
    sites.append(cur)

if n_sample and n_sample < len(sites):
    sites = random.Random(seed).sample(sites, n_sample)

root = root.rstrip('\\/')
with open(out, 'w', encoding='utf-8') as f:
    for s in sites:
        path = root + '\\' + s['uri'].replace('/', '\\')
        f.write(path + '\t' + str(s['line']) + '\n')
print(f'{rule}: {len(sites)} Stellen -> {out}')
