#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Abgleich Export <-> SonarQube-Server nach dem Import (nur lesend).

Liest den Generic-Issue-Report (--sonar-export) und fragt den Server per
GET ab:
  /api/server/version                       (Version, ohne Token)
  /api/issues/search?componentKeys=<key>&rules=external_<engine>:<id>...
                                            (Paging p/ps, je Regel, falls
                                             > 10.000 Treffer)
  /api/rules/search?include_external=true&repositories=external_<engine>
                                            (Regel-Metadaten)

Vergleicht je Schluessel (ruleId, filePath, startLine) als Multimenge:
  FEHLT     - im Export, nicht auf dem Server
  ZUSAETZL. - auf dem Server (gleiche Engine), nicht im Export
  ABWEICHT  - gleicher Schluessel, aber message / endLine / effort anders
und je Regel: Name, cleanCodeAttribute, impacts.

Token NUR per Umgebungsvariable SONAR_TOKEN (nie als Argument, nie in
Dateien). Es werden ausschliesslich GET-Anfragen an --host gesendet, keine
Daten aus dem Export verlassen den Rechner (nur projectKey, Regel-Keys und
Branch-Name stehen in den Abfrage-URLs).

Aufruf:
  set SONAR_TOKEN=squ_...
  python sca_sonar_reconcile.py export.json --host https://sonar.local:9000
         --project-key mein-projekt [--branch main] [--insecure | --cafile x.pem]
         [--engine static-code-analyser] [--all-statuses] [--max-list 25]
         [--json abgleich.json]
  python sca_sonar_reconcile.py --selftest
Exit-Code: 0 = deckungsgleich, 1 = Abweichungen, 3 = Aufruf-/Verbindungsfehler.
"""

import argparse
import base64
import collections
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

PAGE_SIZE = 500
ES_LIMIT = 10000          # /api/issues/search liefert hoechstens p*ps <= 10.000
MESSAGE_MAX = 1333        # Sonar kuerzt Meldungen (abbreviate)


# ---------------------------------------------------------------------------
# Export lesen (kompakt; der Validator prueft die Form)
# ---------------------------------------------------------------------------

def load_export(path):
    with open(path, 'rb') as fh:
        raw = fh.read()
    if raw.startswith(b'\xef\xbb\xbf'):
        raw = raw[3:]
    d = json.loads(raw.decode('utf-8'), strict=False)
    rules = {r['id']: r for r in d.get('rules', []) if isinstance(r, dict) and 'id' in r}
    issues = []
    for it in d.get('issues', []):
        pl = it.get('primaryLocation') or {}
        tr = pl.get('textRange') or {}
        issues.append({
            'rule': it.get('ruleId'),
            'file': pl.get('filePath'),
            'line': tr.get('startLine'),
            'endLine': tr.get('endLine'),
            'message': pl.get('message'),
            'effort': it.get('effortMinutes', 0) or 0,
        })
    engines = collections.Counter(r.get('engineId') for r in rules.values())
    return rules, issues, engines


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

class Server:
    def __init__(self, host, token, insecure=False, cafile=None, timeout=60):
        self.host = host.rstrip('/')
        self.token = token
        self.timeout = timeout
        if insecure:
            self.ctx = ssl._create_unverified_context()
        elif cafile:
            self.ctx = ssl.create_default_context(cafile=cafile)
        else:
            self.ctx = ssl.create_default_context()
        self.basic = False
        self.calls = 0

    def _headers(self):
        h = {'Accept': 'application/json'}
        if self.token:
            if self.basic:
                h['Authorization'] = 'Basic ' + base64.b64encode(
                    (self.token + ':').encode()).decode()
            else:
                h['Authorization'] = 'Bearer ' + self.token
        return h

    def get(self, path, params=None, raw=False):
        url = self.host + path
        if params:
            url += '?' + urllib.parse.urlencode(params)
        for attempt in (0, 1):
            req = urllib.request.Request(url, headers=self._headers(), method='GET')
            self.calls += 1
            try:
                with urllib.request.urlopen(req, timeout=self.timeout,
                                            context=self.ctx) as resp:
                    body = resp.read().decode('utf-8')
                    return body if raw else json.loads(body)
            except urllib.error.HTTPError as e:
                # Aeltere Server (< 10.0) kennen Bearer nicht fuer alle
                # Token-Arten: einmal mit Basic (token als Benutzer) probieren.
                if e.code == 401 and self.token and not self.basic and attempt == 0:
                    self.basic = True
                    continue
                detail = e.read().decode('utf-8', 'replace')[:300]
                raise RuntimeError('HTTP %d bei GET %s: %s' % (e.code, path, detail))
        raise RuntimeError('unerreichbar')


def comp_path(issue, comps, project_key):
    c = comps.get(issue.get('component'))
    if c and c.get('path'):
        return c['path']
    comp = issue.get('component', '')
    pre = project_key + ':'
    return comp[len(pre):] if comp.startswith(pre) else comp


def fetch_issues(srv, project_key, rule_keys, branch, all_statuses, log):
    """Alle Issues der angegebenen Regel-Keys (Liste) holen; teilt bei Bedarf."""
    out = []

    def query(keys):
        base = {'componentKeys': project_key, 'rules': ','.join(keys),
                'ps': PAGE_SIZE, 's': 'FILE_LINE'}
        if branch:
            base['branch'] = branch
        if not all_statuses:
            base['resolved'] = 'false'
        first = srv.get('/api/issues/search', dict(base, p=1))
        total = first.get('paging', {}).get('total', first.get('total', 0))
        if total > ES_LIMIT and len(keys) > 1:
            half = len(keys) // 2
            query(keys[:half])
            query(keys[half:])
            return
        if total > ES_LIMIT:
            log('WARNUNG: Regel %s hat %d Issues > %d - Abgleich unvollstaendig'
                % (keys[0], total, ES_LIMIT))
        pages = min((total + PAGE_SIZE - 1) // PAGE_SIZE, ES_LIMIT // PAGE_SIZE)
        resp = first
        for p in range(1, pages + 1):
            if p > 1:
                resp = srv.get('/api/issues/search', dict(base, p=p))
            comps = {c['key']: c for c in resp.get('components', [])}
            for it in resp.get('issues', []):
                it['_path'] = comp_path(it, comps, project_key)
                out.append(it)

    # Regel-Keys in Paketen (URL-Laenge)
    keys = sorted(rule_keys)
    for i in range(0, len(keys), 40):
        query(keys[i:i + 40])
    return out


def fetch_engine_issues_unfiltered(srv, project_key, engine, branch, all_statuses):
    """Anzahl aller Issues des Projekts je Regel-Key der Engine (Facette)."""
    params = {'componentKeys': project_key, 'ps': 1, 'facets': 'rules'}
    if branch:
        params['branch'] = branch
    if not all_statuses:
        params['resolved'] = 'false'
    resp = srv.get('/api/issues/search', params)
    res = collections.Counter()
    for f in resp.get('facets', []):
        if f.get('property') == 'rules':
            for v in f.get('values', []):
                if v.get('val', '').startswith('external_%s:' % engine):
                    res[v['val']] = v.get('count', 0)
    return res


def fetch_rules(srv, engine):
    res = {}
    p = 1
    while True:
        resp = srv.get('/api/rules/search', {
            'include_external': 'true', 'repositories': 'external_' + engine,
            'ps': PAGE_SIZE, 'p': p, 'f': 'name,severity,lang,impacts,'
                                          'cleanCodeAttribute,sysTags,repo,isExternal'})
        for r in resp.get('rules', []):
            res[r['key']] = r
        total = resp.get('total', resp.get('paging', {}).get('total', 0))
        if p * PAGE_SIZE >= total:
            return res
        p += 1


# ---------------------------------------------------------------------------
# Vergleich
# ---------------------------------------------------------------------------

def parse_effort(text):
    """'1h30min' / '10min' / '2d' -> Minuten (Sonar: 1d = 8h)."""
    if text is None:
        return None
    if isinstance(text, int):
        return text
    m = 0
    for num, unit in re.findall(r'(\d+)\s*(d|h|min)', str(text)):
        m += int(num) * {'d': 480, 'h': 60, 'min': 1}[unit]
    return m


def norm_msg(s):
    if s is None:
        return ''
    s = s.strip()
    if len(s) > MESSAGE_MAX:
        s = s[:MESSAGE_MAX - 3] + '...'
    return s


def compare(exp_rules, exp_issues, srv_issues, srv_rules, engine, max_list):
    pre = 'external_%s:' % engine
    rep = {'missing': [], 'extra': [], 'diff': collections.Counter(), 'diff_samples':
           collections.defaultdict(list), 'rules': [], 'stats': {}}
    ex = collections.defaultdict(list)
    for it in exp_issues:
        ex[(it['rule'], it['file'], it['line'])].append(it)
    sv = collections.defaultdict(list)
    for it in srv_issues:
        rk = it.get('rule', '')
        rid = rk[len(pre):] if rk.startswith(pre) else rk
        tr = it.get('textRange') or {}
        line = it.get('line', tr.get('startLine'))
        sv[(rid, it.get('_path'), line)].append(it)
    matched = 0
    for key in set(ex) | set(sv):
        a = ex.get(key, [])
        b = list(sv.get(key, []))
        # innerhalb eines Schluessels erst gleiche Meldungen paaren
        rest_a = []
        for e in a:
            hit = None
            for i, s in enumerate(b):
                if norm_msg(s.get('message')) == norm_msg(e['message']):
                    hit = i
                    break
            if hit is None:
                rest_a.append(e)
            else:
                s = b.pop(hit)
                matched += 1
                _detail(e, s, rep, max_list, key)
        for e in rest_a:
            if b:
                s = b.pop(0)
                matched += 1
                rep['diff']['message'] += 1
                if len(rep['diff_samples']['message']) < max_list:
                    rep['diff_samples']['message'].append(
                        '%s %s:%s  Export=%r  Server=%r' % (key[0], key[1], key[2],
                                                            e['message'][:120],
                                                            (s.get('message') or '')[:120]))
                _detail(e, s, rep, max_list, key)
            else:
                rep['missing'].append(key)
        for s in b:
            rep['extra'].append(key + (s.get('message', '')[:120],))
    rep['stats'] = {'export': len(exp_issues), 'server': len(srv_issues), 'paired': matched,
                    'endLineKept': rep['diff'].pop('_endKept', 0),
                    'endLineLost': rep['diff'].pop('_endLost', 0)}
    # Regeln
    used_rules = {it['rule'] for it in exp_issues}
    for rid, r in sorted(exp_rules.items()):
        sr = srv_rules.get(pre + rid)
        if sr is None:
            used = rid in used_rules
            rep['rules'].append((rid, 'auf dem Server nicht gefunden'
                                 + ('' if used else ' (Regel ohne Issue - erwartet)')))
            continue
        diffs = []
        if sr.get('name') and sr['name'] != r.get('name'):
            diffs.append('name: %r != %r' % (sr.get('name'), r.get('name')))
        if sr.get('cleanCodeAttribute') and r.get('cleanCodeAttribute') and \
                sr['cleanCodeAttribute'] != r['cleanCodeAttribute']:
            diffs.append('cleanCodeAttribute: %s != %s' % (sr['cleanCodeAttribute'],
                                                           r['cleanCodeAttribute']))
        si = {(i.get('softwareQuality'), i.get('severity')) for i in sr.get('impacts', [])}
        ei = {(i.get('softwareQuality'), i.get('severity')) for i in r.get('impacts', [])}
        if si and si != ei:
            diffs.append('impacts: Server %s != Export %s' % (sorted(si), sorted(ei)))
        if diffs:
            rep['rules'].append((rid, '; '.join(diffs)))
    return rep


def _detail(e, s, rep, max_list, key):
    # Mehrzeilige Funde: kommt endLine an? (ohne startColumn markiert der
    # Importer nur startLine - genau das soll der Roundtrip zeigen)
    if e['endLine']:
        se = (s.get('textRange') or {}).get('endLine')
        rep['diff']['_endKept' if se == e['endLine'] else '_endLost'] += 1
    se = parse_effort(s.get('effort', s.get('debt')))
    if se is not None and se != (e['effort'] or 0):
        rep['diff']['effort'] += 1
        if len(rep['diff_samples']['effort']) < max_list:
            rep['diff_samples']['effort'].append('%s %s:%s Export=%s Server=%s' % (
                key[0], key[1], key[2], e['effort'], s.get('effort')))


def render(rep, server_info, max_list):
    st = rep['stats']
    out = ['Server: %s' % server_info,
           'Export-Issues: %d   Server-Issues (Engine): %d   gepaart: %d'
           % (st['export'], st['server'], st['paired']),
           'mehrzeilige Funde: endLine angekommen=%d, verloren=%d'
           % (st['endLineKept'], st['endLineLost'])]
    miss = collections.Counter(k[0] for k in rep['missing'])
    extra = collections.Counter(k[0] for k in rep['extra'])
    out.append('FEHLT auf dem Server: %d  %s' % (len(rep['missing']), dict(miss)))
    for k in rep['missing'][:max_list]:
        out.append('    %s %s:%s' % k)
    files = collections.Counter(k[1] for k in rep['missing'])
    if files:
        out.append('  fehlende je Datei (Top 10): ' + ', '.join(
            '%s=%d' % kv for kv in files.most_common(10)))
    out.append('ZUSAETZLICH auf dem Server: %d  %s' % (len(rep['extra']), dict(extra)))
    for k in rep['extra'][:max_list]:
        out.append('    %s %s:%s  %s' % k)
    for what, n in sorted(rep['diff'].items()):
        out.append('ABWEICHUNG %s: %d' % (what, n))
        for s in rep['diff_samples'][what]:
            out.append('    ' + s)
    out.append('Regel-Abweichungen: %d' % len(rep['rules']))
    mm = sum(1 for _, t in rep['rules'] if "Server [('MAINTAINABILITY', 'MEDIUM')]" in t)
    if mm and mm == sum(1 for _, t in rep['rules'] if 'impacts:' in t) and mm >= 3:
        out.append('  HINWEIS: alle abweichenden Regeln stehen auf dem Server als '
                   'MAINTAINABILITY/MEDIUM - das ist der Vorgabewert des ALTFORMATS. '
                   'Der Scanner hat rules[] offenbar nicht ausgewertet (Scanner-Log auf '
                   '"deprecated format" pruefen).')
    for rid, t in rep['rules'][:max_list * 4]:
        out.append('    %s: %s' % (rid, t))
    return '\n'.join(out)


# ---------------------------------------------------------------------------
# Selbsttest (ohne Netz)
# ---------------------------------------------------------------------------

def _selftest():
    ok = True

    def check(c, t):
        nonlocal ok
        print(('  ok    ' if c else '  FEHLT ') + t)
        ok = ok and c

    check(parse_effort('1h30min') == 90, "parse_effort('1h30min') == 90")
    check(parse_effort('1d') == 480, "parse_effort('1d') == 480")
    check(parse_effort('10min') == 10, "parse_effort('10min') == 10")
    exp_rules = {'R1': {'id': 'R1', 'name': 'Eins', 'cleanCodeAttribute': 'LOGICAL',
                        'impacts': [{'softwareQuality': 'RELIABILITY', 'severity': 'HIGH'}]},
                 'R2': {'id': 'R2', 'name': 'Zwei', 'impacts': []}}
    exp = [{'rule': 'R1', 'file': 'src/a.pas', 'line': 3, 'endLine': None, 'message': 'm1',
            'effort': 10},
           {'rule': 'R1', 'file': 'src/a.pas', 'line': 3, 'endLine': None, 'message': 'm1',
            'effort': 10},
           {'rule': 'R1', 'file': 'src/b.pas', 'line': 5, 'endLine': 9, 'message': 'm2',
            'effort': 10},
           {'rule': 'R2', 'file': 'src/c.pas', 'line': 1, 'endLine': None, 'message': 'x',
            'effort': 0}]
    pre = 'external_e:'
    srv = [{'rule': pre + 'R1', '_path': 'src/a.pas', 'line': 3, 'message': 'm1',
            'effort': '10min', 'textRange': {'startLine': 3, 'endLine': 3}},
           {'rule': pre + 'R1', '_path': 'src/b.pas', 'line': 5, 'message': 'm2 anders',
            'effort': '20min', 'textRange': {'startLine': 5, 'endLine': 5}},
           {'rule': pre + 'R1', '_path': 'src/z.pas', 'line': 7, 'message': 'neu'}]
    srules = {pre + 'R1': {'key': pre + 'R1', 'name': 'Eins', 'cleanCodeAttribute': 'LOGICAL',
                           'impacts': [{'softwareQuality': 'RELIABILITY', 'severity': 'MEDIUM'}]}}
    rep = compare(exp_rules, exp, srv, srules, 'e', 10)
    check(len(rep['missing']) == 2, 'zwei fehlende (Dublette a.pas:3 + c.pas:1): %s'
          % rep['missing'])
    check(len(rep['extra']) == 1 and rep['extra'][0][1] == 'src/z.pas', 'ein zusaetzliches')
    check(rep['diff']['message'] == 1, 'eine Meldungsabweichung')
    check(rep['diff']['effort'] == 1, 'eine Effort-Abweichung')
    check(rep['stats']['endLineLost'] == 1, 'endLine verloren erkannt')
    check(any(r[0] == 'R1' and 'impacts' in r[1] for r in rep['rules']), 'Impact-Abweichung R1')
    check(any(r[0] == 'R2' for r in rep['rules']), 'R2 fehlt auf dem Server')
    print(render(rep, 'selftest', 3))
    print('SELBSTTEST ' + ('BESTANDEN' if ok else 'FEHLGESCHLAGEN'))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('report', nargs='?')
    ap.add_argument('--host', help='z. B. https://sonar.firma.local:9000')
    ap.add_argument('--project-key')
    ap.add_argument('--branch', help='Branch (nur Developer Edition aufwaerts)')
    ap.add_argument('--engine', help='engineId (Standard: aus dem Export)')
    ap.add_argument('--insecure', action='store_true', help='TLS-Zertifikat nicht pruefen')
    ap.add_argument('--cafile', help='eigene CA (PEM) fuer selbstsignierte Server')
    ap.add_argument('--all-statuses', action='store_true',
                    help='auch geschlossene/behobene Issues (Standard: resolved=false)')
    ap.add_argument('--max-list', type=int, default=25)
    ap.add_argument('--json', help='Ergebnis zusaetzlich als JSON')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    if not (a.report and a.host and a.project_key):
        ap.error('report, --host und --project-key sind Pflicht')
    token = os.environ.get('SONAR_TOKEN', '')
    if not token:
        print('Hinweis: SONAR_TOKEN nicht gesetzt - anonyme Abfrage', file=sys.stderr)
    exp_rules, exp_issues, engines = load_export(a.report)
    engine = a.engine or (engines.most_common(1)[0][0] if engines else 'static-code-analyser')
    srv = Server(a.host, token, a.insecure, a.cafile)
    log = lambda m: print(m, file=sys.stderr)  # noqa: E731
    try:
        version = srv.get('/api/server/version', raw=True).strip()
        rule_keys = ['external_%s:%s' % (engine, r) for r in exp_rules]
        facet = fetch_engine_issues_unfiltered(srv, a.project_key, engine, a.branch,
                                               a.all_statuses)
        # auch Regeln, die nur auf dem Server vorkommen (alte Laeufe)
        rule_keys = sorted(set(rule_keys) | set(facet))
        srv_issues = fetch_issues(srv, a.project_key, rule_keys, a.branch,
                                  a.all_statuses, log)
        srv_rules = fetch_rules(srv, engine)
    except (RuntimeError, urllib.error.URLError, OSError) as e:
        print('Verbindungs-/Abfragefehler: %s' % e, file=sys.stderr)
        return 3
    rep = compare(exp_rules, exp_issues, srv_issues, srv_rules, engine, a.max_list)
    info = '%s  SonarQube %s  Projekt %s%s  Engine %s  (%d GET-Abfragen)' % (
        a.host, version, a.project_key, (' Branch ' + a.branch) if a.branch else '',
        engine, srv.calls)
    print(render(rep, info, a.max_list))
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as fh:
            json.dump({'server': info, 'stats': rep['stats'],
                       'missing': rep['missing'], 'extra': rep['extra'],
                       'diff': dict(rep['diff']),
                       'diffSamples': {k: v for k, v in rep['diff_samples'].items()},
                       'rules': rep['rules']}, fh, ensure_ascii=False, indent=1)
    bad = rep['missing'] or rep['extra'] or rep['diff'] or rep['rules']
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
