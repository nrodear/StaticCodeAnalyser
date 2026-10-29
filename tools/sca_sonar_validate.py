#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Offline-Pruefung eines SonarQube-Generic-Issue-Reports (--sonar-export).

Prueft eine Export-Datei
  * gegen die Spezifikation "Generic issue import format" (je Server-Version),
  * gegen die Quelldateien unter --base-dir (= sonar.projectBaseDir): Datei
    vorhanden (Gross-/Kleinschreibung exakt wie Sonar), startLine/endLine in
    den Dateigrenzen nach Sonars Zeilenzaehlung (CR, LF und CRLF trennen),
    Spalten <= Zeilenlaenge in UTF-16-Einheiten (so zaehlt Java/Sonar),
  * optional gegen eine sonar-project.properties (sonar.sources,
    sonar.inclusions/exclusions): Funde in nicht indexierten Dateien
    verwirft Sonar still ("External issues ignored for N unknown files").

Liest den Report stromweise (Element fuer Element), damit auch Exporte von
mehreren hundert MB durchgehen. Keine Netzwerkzugriffe.

Schweregrade der Befunde:
  REJECT  - der Scanner verwirft den GESAMTEN Report (Validator-Fehler).
  ABORT   - Scanner-Ausnahme beim Anlegen der Position (Zeile/Spalte
            ausserhalb der Datei): je nach Version bricht die Analyse ab.
  DROP    - genau dieser Fund kommt nicht an (Datei unbekannt/ausgeschlossen).
  WARN    - Risiko oder wirkungslos (z. B. endLine ohne startColumn).
  INFO    - Statistik / Hinweis.

Exit-Code: 0 = keine REJECT/ABORT/DROP, 1 = mindestens einer, 3 = Aufruffehler.
Mit --strict zaehlt auch WARN.

Aufruf:
  python sca_sonar_validate.py export.json --base-dir D:\\proj [--properties
         D:\\proj\\sonar-project.properties] [--server-version 2025.1]
         [--encoding utf-8] [--max-list 25] [--json befunde.json]
  python sca_sonar_validate.py --selftest
"""

import argparse
import codecs
import collections
import fnmatch  # noqa: F401  (bewusst NICHT benutzt: Sonar-Wildcards weichen ab)
import io
import json
import os
import re
import shutil
import sys
import tempfile
from array import array

# ---------------------------------------------------------------------------
# Spezifikation
# ---------------------------------------------------------------------------

CLEAN_CODE_ATTRIBUTES = {
    'FORMATTED', 'CONVENTIONAL', 'IDENTIFIABLE',            # Consistency
    'CLEAR', 'LOGICAL', 'COMPLETE', 'EFFICIENT',            # Intentionality
    'FOCUSED', 'DISTINCT', 'MODULAR', 'TESTED',             # Adaptability
    'LAWFUL', 'TRUSTWORTHY', 'RESPECTFUL',                  # Responsibility
}
SOFTWARE_QUALITIES = {'SECURITY', 'RELIABILITY', 'MAINTAINABILITY'}
IMPACT_SEV_10_3 = {'HIGH', 'MEDIUM', 'LOW'}                 # 10.3 .. 10.7
IMPACT_SEV_10_8 = {'BLOCKER', 'HIGH', 'MEDIUM', 'LOW', 'INFO'}  # ab 10.8
RULE_TYPES = {'BUG', 'VULNERABILITY', 'CODE_SMELL'}
RULE_SEVERITIES = {'BLOCKER', 'CRITICAL', 'MAJOR', 'MINOR', 'INFO'}

RULE_FIELDS = {'id', 'name', 'description', 'engineId', 'cleanCodeAttribute',
               'type', 'severity', 'impacts'}
ISSUE_FIELDS = {'ruleId', 'effortMinutes', 'primaryLocation',
                'secondaryLocations'}
ISSUE_FIELDS_LEGACY = {'engineId', 'severity', 'type'}
LOC_FIELDS = {'message', 'filePath', 'textRange'}
RANGE_FIELDS = {'startLine', 'endLine', 'startColumn', 'endColumn'}

# Sonar kuerzt Issue-Meldungen (DefaultIssueLocation, abbreviate) - kein
# Abweisungsgrund, aber im Abgleich ein erwarteter Unterschied.
MESSAGE_MAX = 1333

# Endungen, die eingebaute Sonar-Sprachplugins per Voreinstellung
# beanspruchen. Kein Importfehler - aber das Plugin parst die Datei
# (Parse-Warnungen im Scanner-Log, ggf. eigene Funde).
CLAIMED_SUFFIXES = {
    '.inc': 'PHP (sonar.php.file.suffixes enthaelt "inc")',
}

SEVERITY_ORDER = ['REJECT', 'ABORT', 'DROP', 'WARN', 'INFO']


def parse_version(text):
    """'10.6', '2025.1.2', '25.3' (Community Build) -> (Gen, Tupel).

    Gen: 'legacy' (< 10.3), 'mqr1' (10.3 .. 10.7), 'mqr2' (>= 10.8)."""
    nums = tuple(int(x) for x in re.findall(r'\d+', text or '')[:3])
    if not nums:
        raise ValueError('Server-Version nicht lesbar: %r' % text)
    major = nums[0]
    minor = nums[1] if len(nums) > 1 else 0
    if major >= 2025 or 24 <= major < 100:   # Server 2025.x / Community Build 24.12+
        return 'mqr2', nums
    if major > 10 or (major == 10 and minor >= 8):
        return 'mqr2', nums
    if major == 10 and minor >= 3:
        return 'mqr1', nums
    return 'legacy', nums


# ---------------------------------------------------------------------------
# Stromweiser JSON-Leser fuer {"rules":[...],"issues":[...]}
# ---------------------------------------------------------------------------

class JsonDupKeyError(Exception):
    pass


def _pairs_hook(pairs):
    seen = {}
    dups = []
    for k, v in pairs:
        if k in seen:
            dups.append(k)
        seen[k] = v
    if dups:
        seen['\x00__dupkeys__'] = dups
    return seen


class StreamReader:
    """Minimaler Strom-Leser: Top-Level-Objekt, Arrays elementweise."""

    def __init__(self, text_stream, chunk=1 << 20):
        self.f = text_stream
        self.chunk = chunk
        self.buf = ''
        self.pos = 0
        self.eof = False
        self.consumed = 0          # Zeichen vor self.buf (fuer Positionen)
        self.strict_dec = json.JSONDecoder(object_pairs_hook=_pairs_hook)
        self.lax_dec = json.JSONDecoder(object_pairs_hook=_pairs_hook,
                                        strict=False)
        self.control_char_hits = 0

    def _fill(self):
        data = self.f.read(self.chunk)
        if not data:
            self.eof = True
        self.consumed += self.pos
        self.buf = self.buf[self.pos:] + data
        self.pos = 0

    def where(self):
        return self.consumed + self.pos

    def skip_ws(self):
        while True:
            b = self.buf
            n = len(b)
            p = self.pos
            while p < n and b[p] in ' \t\r\n':
                p += 1
            self.pos = p
            if p < n or self.eof:
                return
            self._fill()

    def peek(self):
        self.skip_ws()
        return self.buf[self.pos] if self.pos < len(self.buf) else ''

    def expect(self, ch):
        c = self.peek()
        if c != ch:
            raise ValueError('erwartet %r, gefunden %r an Zeichen %d'
                             % (ch, c, self.where()))
        self.pos += 1

    def value(self):
        self.skip_ws()
        while True:
            try:
                obj, end = self.strict_dec.raw_decode(self.buf, self.pos)
                if end >= len(self.buf) and not self.eof:
                    raise json.JSONDecodeError('evtl. abgeschnitten',
                                               self.buf, end)
                self.pos = end
                return obj
            except json.JSONDecodeError as e:
                if not self.eof:
                    self._fill()
                    continue
                if 'Invalid control character' in e.msg:
                    obj, end = self.lax_dec.raw_decode(self.buf, self.pos)
                    self.control_char_hits += 1
                    self.pos = end
                    return obj
                raise ValueError('JSON ungueltig an Zeichen %d: %s'
                                 % (self.consumed + e.pos, e.msg))

    def iter_array(self):
        self.expect('[')
        if self.peek() == ']':
            self.pos += 1
            return
        while True:
            yield self.value()
            c = self.peek()
            if c == ',':
                self.pos += 1
                continue
            if c == ']':
                self.pos += 1
                return
            raise ValueError('erwartet , oder ] an Zeichen %d, gefunden %r'
                             % (self.where(), c))


def iter_report(path, on_top_key):
    """Liefert ('rule'|'issue'|'other', Element) in Dateireihenfolge.

    on_top_key(name) wird fuer jeden Top-Level-Schluessel gerufen."""
    raw = open(path, 'rb')
    head = raw.read(3)
    bom = head == codecs.BOM_UTF8
    if not bom:
        raw.seek(0)
    text = io.TextIOWrapper(raw, encoding='utf-8', errors='strict', newline='')
    rd = StreamReader(text)
    try:
        rd.expect('{')
        if rd.peek() == '}':
            rd.pos += 1
        else:
            while True:
                key = rd.value()
                if not isinstance(key, str):
                    raise ValueError('Top-Level-Schluessel erwartet')
                rd.expect(':')
                on_top_key(key)
                if key in ('rules', 'issues') and rd.peek() == '[':
                    kind = 'rule' if key == 'rules' else 'issue'
                    for el in rd.iter_array():
                        yield kind, el
                else:
                    yield 'other', (key, rd.value())
                c = rd.peek()
                if c == ',':
                    rd.pos += 1
                    continue
                if c == '}':
                    rd.pos += 1
                    break
                raise ValueError('erwartet , oder } an Zeichen %d' % rd.where())
        if rd.peek() != '':
            raise ValueError('Daten nach dem Top-Level-Objekt an Zeichen %d'
                             % rd.where())
        yield 'meta', {'bom': bom, 'control_chars': rd.control_char_hits}
    finally:
        text.close()


# ---------------------------------------------------------------------------
# Quelldateien wie Sonar sehen
# ---------------------------------------------------------------------------

class SourceFile:
    __slots__ = ('lines', 'lens', 'nul', 'bom', 'decode_errors')


class SourceIndex:
    """Datei-Existenz (Gross/Klein exakt) und Zeilenmetrik nach Sonar-Art."""

    def __init__(self, base_dir, encoding):
        self.base = os.path.abspath(base_dir)
        self.encoding = encoding
        self._dir_cache = {}
        self._files = {}

    def _listdir(self, d):
        r = self._dir_cache.get(d)
        if r is None:
            try:
                r = set(os.listdir(d))
            except OSError:
                r = set()
            self._dir_cache[d] = r
        return r

    def resolve(self, rel):
        """-> (abs_path | None, Grund). Grund: '' | 'missing' | 'case:<echt>'."""
        parts = rel.split('/')
        cur = self.base
        real = []
        for part in parts:
            entries = self._listdir(cur)
            if part in entries:
                real.append(part)
                cur = os.path.join(cur, part)
                continue
            low = {e.lower(): e for e in entries}
            if part.lower() in low:
                real.append(low[part.lower()])
                cur = os.path.join(cur, low[part.lower()])
                for rest in parts[len(real):]:
                    real.append(rest)
                return None, 'case:' + '/'.join(real)
            return None, 'missing'
        if not os.path.isfile(cur):
            return None, 'missing'
        return cur, ''

    def metrics(self, abs_path):
        sf = self._files.get(abs_path)
        if sf is not None:
            return sf
        with open(abs_path, 'rb') as fh:
            data = fh.read()
        sf = SourceFile()
        sf.nul = b'\x00' in data
        sf.bom = data.startswith(codecs.BOM_UTF8)
        enc = self.encoding
        if sf.bom and enc.replace('-', '').lower() == 'utf8':
            data = data[3:]
        errs = [0]

        def handler(exc):
            errs[0] += 1
            return ('\ufffd', exc.end)
        name = 'sca_sonar_count_%d' % id(errs)
        codecs.register_error(name, handler)
        text = data.decode(enc, errors=name)
        sf.decode_errors = errs[0]
        # Sonar (FileMetadata/LineCounter): CR, LF und CRLF beenden je eine
        # Zeile; Zeilenzahl = Terminatoren + 1 (eine abschliessende leere
        # Zeile zaehlt mit).
        lens = array('I')
        for line in re.split('\r\n|\r|\n', text):
            # Laenge in UTF-16-Einheiten (Java-char), ohne Terminator.
            lens.append(len(line.encode('utf-16-le')) // 2)
        sf.lens = lens
        sf.lines = len(lens)
        self._files[abs_path] = sf
        return sf


# ---------------------------------------------------------------------------
# sonar-project.properties (vereinfachte Indexierungsregel)
# ---------------------------------------------------------------------------

def read_properties(path):
    props = {}
    with open(path, 'r', encoding='utf-8-sig', errors='replace') as fh:
        lines = fh.read().splitlines()
    buf = ''
    for ln in lines:
        s = ln.strip()
        if not buf and (not s or s[0] in '#!'):
            continue
        if s.endswith('\\') and not s.endswith('\\\\'):
            buf += s[:-1]
            continue
        s = buf + s
        buf = ''
        m = re.match(r'([^=:\s]+)\s*[=:]\s*(.*)$', s)
        if m:
            props[m.group(1)] = m.group(2).strip()
    return props


def sonar_wildcard_to_regex(pat):
    """Sonar-Wildcards: ** = beliebige Verzeichnisse, * = ohne '/', ? = 1 Zeichen."""
    pat = pat.strip().replace('\\', '/')
    out = []
    i = 0
    while i < len(pat):
        c = pat[i]
        if pat.startswith('**/', i):
            out.append('(?:.*/)?')
            i += 3
        elif pat.startswith('**', i):
            out.append('.*')
            i += 2
        elif c == '*':
            out.append('[^/]*')
            i += 1
        elif c == '?':
            out.append('[^/]')
            i += 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.compile('^' + ''.join(out) + '$')


class IndexRule:
    """Welche relativen Pfade indexiert der Scanner (vereinfachte Sicht)."""

    def __init__(self, props):
        def lst(key):
            v = props.get(key, '')
            return [x.strip().replace('\\', '/').strip('/') for x in v.split(',')
                    if x.strip()]
        self.sources = lst('sonar.sources') or ['.']
        self.tests = lst('sonar.tests')
        self.excl = [sonar_wildcard_to_regex(p) for p in lst('sonar.exclusions')]
        self.incl = [sonar_wildcard_to_regex(p) for p in lst('sonar.inclusions')]
        self.excl += [sonar_wildcard_to_regex(p)
                      for p in lst('sonar.global.exclusions')]

    @staticmethod
    def _under(rel, root):
        if root in ('', '.'):
            return True
        return rel == root or rel.startswith(root + '/')

    def why_not(self, rel):
        if not any(self._under(rel, r) for r in self.sources + self.tests):
            return 'nicht unter sonar.sources/sonar.tests'
        if self.incl and not any(rx.match(rel) for rx in self.incl):
            return 'nicht in sonar.inclusions'
        for rx in self.excl:
            if rx.match(rel):
                return 'sonar.exclusions trifft (%s)' % rx.pattern
        return ''


# ---------------------------------------------------------------------------
# Pruefung
# ---------------------------------------------------------------------------

class Collector:
    def __init__(self, max_list):
        self.max_list = max_list
        self.counts = collections.Counter()      # (sev, code) -> n
        self.samples = collections.defaultdict(list)
        self.text = {}

    def add(self, sev, code, text, where=''):
        key = (sev, code)
        self.counts[key] += 1
        self.text.setdefault(key, text)
        if len(self.samples[key]) < self.max_list:
            self.samples[key].append(where)

    def total(self, sevs):
        return sum(n for (s, _), n in self.counts.items() if s in sevs)


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def blank(v):
    return not isinstance(v, str) or v.strip() == ''


class Validator:
    def __init__(self, base_dir=None, properties=None, server_version='2025.1',
                 encoding='utf-8', max_list=25):
        self.gen, self.ver = parse_version(server_version)
        self.c = Collector(max_list)
        self.src = SourceIndex(base_dir, encoding) if base_dir else None
        self.index_rule = IndexRule(read_properties(properties)) if properties else None
        self.rule_ids = {}
        self.rule_engine = collections.Counter()
        self.issue_count = 0
        self.issues_per_rule = collections.Counter()
        self.files_seen = set()
        self.dup_keys = collections.Counter()
        self.top_keys = []
        self.meta = {}
        self.issues_before_rules = 0
        self.ext_count = collections.Counter()
        self.endline_no_col = 0
        self.multi_line = 0

    # ---- Regeln -----------------------------------------------------------
    def check_rule(self, r, idx):
        c = self.c
        w = 'rules[%d]' % idx
        if not isinstance(r, dict):
            c.add('REJECT', 'rule-not-object', 'Regel ist kein Objekt', w)
            return
        self._dupkeys(r, w)
        rid = r.get('id')
        if blank(rid):
            c.add('REJECT', 'rule-id', 'rules[].id fehlt/leer', w)
        else:
            w = '%s id=%s' % (w, rid)
            if rid in self.rule_ids:
                c.add('REJECT', 'rule-dup', 'Regel-id mehrfach in rules[]', w)
            self.rule_ids[rid] = r
        if blank(r.get('name')):
            c.add('REJECT', 'rule-name', 'rules[].name fehlt/leer', w)
        if blank(r.get('engineId')):
            c.add('REJECT', 'rule-engine', 'rules[].engineId fehlt/leer', w)
        else:
            self.rule_engine[r['engineId']] += 1
        if blank(r.get('description')):
            if self.gen == 'mqr2':
                c.add('WARN', 'rule-desc',
                      'rules[].description leer - laut Doku 10.8+/2025.x Pflicht', w)
            else:
                c.add('INFO', 'rule-desc', 'rules[].description leer', w)
        cca = r.get('cleanCodeAttribute')
        if cca is None:
            if self.gen == 'mqr1':
                c.add('REJECT', 'rule-cca',
                      'cleanCodeAttribute fehlt (Pflicht in 10.3-10.7)', w)
        elif cca not in CLEAN_CODE_ATTRIBUTES:
            c.add('REJECT', 'rule-cca-value',
                  'cleanCodeAttribute unbekannt: %r' % (cca,), w)
        imps = r.get('impacts')
        has_ts = r.get('type') is not None and r.get('severity') is not None
        allowed = IMPACT_SEV_10_8 if self.gen == 'mqr2' else IMPACT_SEV_10_3
        if imps is None:
            if self.gen == 'mqr1' or not has_ts:
                c.add('REJECT', 'rule-impacts',
                      'impacts fehlt (und nicht type+severity)', w)
        elif not isinstance(imps, list) or not imps:
            c.add('REJECT', 'rule-impacts', 'impacts leer/kein Array', w)
        else:
            qs = collections.Counter()
            for j, im in enumerate(imps):
                wj = '%s impacts[%d]' % (w, j)
                if not isinstance(im, dict):
                    c.add('REJECT', 'impact-obj', 'impact ist kein Objekt', wj)
                    continue
                q = im.get('softwareQuality')
                s = im.get('severity')
                if q not in SOFTWARE_QUALITIES:
                    c.add('REJECT', 'impact-quality',
                          'softwareQuality unbekannt: %r' % (q,), wj)
                qs[q] += 1
                if s not in allowed:
                    if s in IMPACT_SEV_10_8:
                        c.add('REJECT', 'impact-sev-version',
                              'impact-severity %s erst ab SonarQube 10.8 erlaubt' % s, wj)
                    else:
                        c.add('REJECT', 'impact-sev', 'impact-severity unbekannt: %r'
                              % (s,), wj)
            for q, n in qs.items():
                if n > 1:
                    c.add('REJECT', 'impact-dup-quality',
                          'softwareQuality %s mehrfach in impacts' % q, w)
        if r.get('type') is not None and r.get('type') not in RULE_TYPES:
            c.add('REJECT', 'rule-type', 'type unbekannt: %r' % (r.get('type'),), w)
        if r.get('severity') is not None and r.get('severity') not in RULE_SEVERITIES:
            c.add('REJECT', 'rule-sev', 'severity unbekannt: %r' % (r.get('severity'),), w)
        extra = set(r) - RULE_FIELDS - {'\x00__dupkeys__'}
        if extra:
            c.add('INFO', 'rule-extra', 'unbekannte Regel-Felder (werden ignoriert): '
                  + ','.join(sorted(extra)), w)

    # ---- Issues -----------------------------------------------------------
    def check_issue(self, it, idx):
        c = self.c
        self.issue_count += 1
        w = 'issues[%d]' % idx
        if not isinstance(it, dict):
            c.add('REJECT', 'issue-not-object', 'Issue ist kein Objekt', w)
            return
        self._dupkeys(it, w)
        rid = it.get('ruleId')
        legacy = self.gen == 'legacy'
        if blank(rid):
            c.add('REJECT', 'issue-ruleid', 'issues[].ruleId fehlt/leer', w)
        else:
            self.issues_per_rule[rid] += 1
        if legacy:
            for f in ('engineId', 'severity', 'type'):
                if blank(it.get(f)):
                    c.add('REJECT', 'legacy-' + f,
                          'Altformat (< 10.3): issues[].%s ist Pflicht' % f, w)
        else:
            for f in ('severity', 'type'):
                if f in it:
                    c.add('REJECT', 'issue-deprecated-' + f,
                          'issues[].%s ist Altformat-Feld - mit rules[] verwirft '
                          'der Scanner den Report' % f, w)
            if 'engineId' in it:
                c.add('WARN', 'issue-engineid',
                      'issues[].engineId steht nicht in der aktuellen Spezifikation '
                      '(Altformat-Feld; laut Importer wirkungslos)', w)
        eff = it.get('effortMinutes')
        if eff is not None and (not is_int(eff) or eff < 0):
            c.add('REJECT', 'issue-effort', 'effortMinutes keine Ganzzahl >= 0: %r'
                  % (eff,), w)
        extra = set(it) - ISSUE_FIELDS - ISSUE_FIELDS_LEGACY - {'\x00__dupkeys__'}
        if extra:
            c.add('INFO', 'issue-extra', 'unbekannte Issue-Felder: '
                  + ','.join(sorted(extra)), w)
        pl = it.get('primaryLocation')
        if not isinstance(pl, dict):
            c.add('REJECT', 'issue-primary', 'primaryLocation fehlt', w)
        else:
            self.check_location(pl, w + '.primaryLocation', rid, primary=True)
        sl = it.get('secondaryLocations')
        if sl is not None:
            if not isinstance(sl, list):
                c.add('REJECT', 'issue-secondary', 'secondaryLocations kein Array', w)
            else:
                for j, loc in enumerate(sl):
                    if isinstance(loc, dict):
                        self.check_location(loc, '%s.secondaryLocations[%d]' % (w, j),
                                            rid, primary=False)
                    else:
                        c.add('REJECT', 'issue-secondary', 'Location kein Objekt', w)

    def check_location(self, loc, w, rid, primary):
        c = self.c
        self._dupkeys(loc, w)
        msg = loc.get('message')
        fp = loc.get('filePath')
        if primary and blank(msg):
            c.add('REJECT', 'loc-message', 'message fehlt/leer', w)
        elif isinstance(msg, str) and len(msg.strip()) > MESSAGE_MAX:
            c.add('INFO', 'loc-message-long',
                  'message > %d Zeichen - Sonar kuerzt' % MESSAGE_MAX, w)
        if blank(fp):
            c.add('REJECT', 'loc-filepath', 'filePath fehlt/leer', w)
            return
        w2 = '%s %s' % (fp, w)
        tr = loc.get('textRange')
        if tr is None:
            if not primary:
                c.add('REJECT', 'loc-range', 'textRange fehlt (Pflicht bei secondary)', w2)
        elif not isinstance(tr, dict):
            c.add('REJECT', 'loc-range', 'textRange kein Objekt', w2)
            tr = None
        else:
            extra = set(tr) - RANGE_FIELDS - {'\x00__dupkeys__'}
            if extra:
                c.add('INFO', 'range-extra', 'unbekannte textRange-Felder: '
                      + ','.join(sorted(extra)), w2)
            sl = tr.get('startLine')
            if not is_int(sl) or sl < 1:
                c.add('REJECT', 'range-startline', 'startLine fehlt/< 1 (1-basiert): %r'
                      % (sl,), w2)
                tr = None
            else:
                for f in ('endLine', 'startColumn', 'endColumn'):
                    v = tr.get(f)
                    if v is not None and (not is_int(v) or v < 0):
                        c.add('REJECT', 'range-' + f.lower(), '%s keine Ganzzahl >= 0: %r'
                              % (f, v), w2)
                        tr = None
                        break
        if tr is not None:
            sl = tr['startLine']
            el = tr.get('endLine')
            sc = tr.get('startColumn')
            ec = tr.get('endColumn')
            if el is not None and el < sl:
                c.add('ABORT', 'range-end-before-start', 'endLine < startLine', w2)
            if el is not None and el > sl:
                self.multi_line += 1
                if sc is None:
                    self.endline_no_col += 1
                    c.add('WARN', 'range-endline-ignored',
                          'endLine ohne startColumn - Importer markiert nur startLine '
                          '(selectLine), endLine ist wirkungslos', w2)
            if sc is None and ec is not None:
                c.add('WARN', 'range-endcol-ignored', 'endColumn ohne startColumn wird '
                      'ignoriert', w2)
            if sc is not None and ec is not None and (el is None or el == sl) and ec <= sc:
                c.add('ABORT', 'range-empty', 'leerer/negativer Bereich '
                      '(endColumn <= startColumn auf derselben Zeile)', w2)
        if primary:
            self.ext_count[os.path.splitext(fp)[1].lower()] += 1
        self.check_file(fp, tr, w2)

    def check_file(self, fp, tr, w):
        c = self.c
        first = fp not in self.files_seen
        self.files_seen.add(fp)
        if '\\' in fp:
            c.add('DROP', 'path-backslash', 'Backslash im filePath', w)
        if re.match(r'^[A-Za-z]:[/\\]', fp) or fp.startswith('/') or fp.startswith('//'):
            c.add('WARN', 'path-absolute', 'absoluter filePath - nur gueltig, wenn er '
                  'unter sonar.projectBaseDir liegt', w)
            return
        segs = fp.split('/')
        if '..' in segs or '.' in segs:
            c.add('DROP', 'path-dots', "'.'/'..' im filePath - Sonar vergleicht den "
                  'normalisierten relativen Pfad', w)
        if first and any(s.startswith('.') and s not in ('.', '..') for s in segs[:-1]):
            c.add('WARN', 'path-hidden', 'Datei in verstecktem Ordner - vor SonarQube '
                  '10.6 nicht indexiert', w)
        ext = os.path.splitext(fp)[1].lower()
        if first and ext in CLAIMED_SUFFIXES:
            c.add('INFO', 'suffix-claimed', 'Endung %s wird von %s beansprucht - Datei '
                  'wird dort mitgeparst' % (ext, CLAIMED_SUFFIXES[ext]), fp)
        if self.index_rule is not None:
            why = self.index_rule.why_not(fp)
            if why:
                c.add('DROP', 'not-indexed', 'Datei nicht indexiert (%s) - Sonar '
                      'verwirft den Fund still' % why, w)
        if self.src is None:
            return
        absp, why = self.src.resolve(fp)
        if absp is None:
            if why.startswith('case:'):
                c.add('DROP', 'path-case', 'Gross-/Kleinschreibung im filePath weicht '
                      'von der Platte ab - Sonar vergleicht exakt', '%s -> echt: %s'
                      % (w, why[5:]))
            else:
                c.add('DROP', 'file-missing', 'Datei existiert nicht unter --base-dir', w)
            return
        sf = self.src.metrics(absp)
        if first:
            if sf.decode_errors:
                c.add('WARN', 'file-encoding', 'Bytefolgen passen nicht zu '
                      'sonar.sourceEncoding=%s - Sonar warnt, Zeilen bleiben gleich'
                      % self.src.encoding, '%s  (%d Stellen)' % (fp, sf.decode_errors))
        if tr is None:
            return
        if sf.nul:
            c.add('WARN', 'file-binary', 'Zeilenposition in einer Datei mit NUL-Bytes '
                  '(binaere .dfm?) - die Zeile zeigt bei Sonar auf Binaerinhalt; '
                  'besser Dateiebene', w)
        sl = tr['startLine']
        el = tr.get('endLine')
        sc = tr.get('startColumn')
        ec = tr.get('endColumn')
        if sl > sf.lines:
            c.add('ABORT', 'line-out-of-file', 'startLine > Zeilenzahl der Datei (Sonar-'
                  'Zaehlung)', '%s  startLine=%d Zeilen=%d' % (w, sl, sf.lines))
            return
        if el is not None and el > sf.lines:
            c.add('ABORT', 'endline-out-of-file', 'endLine > Zeilenzahl der Datei',
                  '%s  endLine=%d Zeilen=%d' % (w, el, sf.lines))
            return
        if sc is not None:
            ln = sf.lens[sl - 1]
            if sc > ln:
                c.add('ABORT', 'startcol-out-of-line', 'startColumn > Zeilenlaenge (UTF-16)',
                      '%s  startColumn=%d Laenge=%d' % (w, sc, ln))
            if ln == 0 and (el is None or el == sl):
                c.add('ABORT', 'startcol-empty-line', 'startColumn auf leerer Zeile '
                      '(Spezifikation: nicht angeben)', w)
            if ec is not None:
                eln = sf.lens[(el or sl) - 1]
                if ec > eln:
                    c.add('ABORT', 'endcol-out-of-line', 'endColumn > Zeilenlaenge (UTF-16)',
                          '%s  endColumn=%d Laenge=%d' % (w, ec, eln))

    def _dupkeys(self, obj, w):
        d = obj.pop('\x00__dupkeys__', None)
        if d:
            self.c.add('WARN', 'json-dup-key', 'doppelter JSON-Schluessel: '
                       + ','.join(d), w)

    # ---- Gesamtlauf -------------------------------------------------------
    def run(self, path):
        c = self.c
        try:
            os.path.getsize(path)
        except OSError as e:
            c.add('REJECT', 'file-io', 'Report nicht lesbar: %s' % e, path)
            return
        ri = ii = 0
        issue_keys = collections.Counter()
        try:
            for kind, el in iter_report(path, self.top_keys.append):
                if kind == 'rule':
                    self.check_rule(el, ri)
                    ri += 1
                elif kind == 'issue':
                    if ri == 0 and 'rules' not in self.top_keys:
                        self.issues_before_rules += 1
                    self.check_issue(el, ii)
                    if isinstance(el, dict) and isinstance(el.get('primaryLocation'), dict):
                        pl = el['primaryLocation']
                        tr = pl.get('textRange') if isinstance(pl.get('textRange'), dict) else {}
                        issue_keys[(el.get('ruleId'), pl.get('filePath'),
                                    tr.get('startLine'), tr.get('startColumn'),
                                    pl.get('message'))] += 1
                    ii += 1
                elif kind == 'other':
                    key, _ = el
                    c.add('INFO', 'top-extra', 'unbekannter Top-Level-Schluessel: %s' % key,
                          path)
                elif kind == 'meta':
                    self.meta = el
        except (ValueError, UnicodeDecodeError) as e:
            c.add('REJECT', 'json-invalid', 'Report ist kein gueltiges JSON/UTF-8: %s' % e,
                  path)
            return
        if self.meta.get('bom'):
            c.add('WARN', 'json-bom', 'UTF-8-BOM am Dateianfang (RFC 8259 8.1)', path)
        if self.meta.get('control_chars'):
            c.add('WARN', 'json-control-char', 'unescapte Steuerzeichen in Strings '
                  '(RFC 8259 verlangt Escaping)', path)
        if 'issues' not in self.top_keys:
            c.add('REJECT', 'no-issues', 'Top-Level "issues" fehlt', path)
        if self.gen != 'legacy':
            if 'rules' not in self.top_keys:
                c.add('WARN', 'no-rules', 'kein rules[] - Altformat, Sonar setzt '
                      'CONVENTIONAL/MAINTAINABILITY/MEDIUM ein', path)
            else:
                # Erst jetzt pruefbar: ruleId-Referenzen (Regeln koennen nach
                # den Issues stehen).
                for rid, n in self.issues_per_rule.items():
                    if rid not in self.rule_ids:
                        for _ in range(n):
                            c.add('REJECT', 'issue-rule-missing', 'issues[].ruleId ohne '
                                  'Regel in rules[] (checkRuleExistsInReport)', rid)
                for rid in self.rule_ids:
                    if rid not in self.issues_per_rule:
                        c.add('INFO', 'rule-unused', 'Regel ohne Issue', rid)
        else:
            if 'rules' in self.top_keys:
                c.add('INFO', 'legacy-rules', 'rules[] wird von < 10.3 ignoriert', path)
        if len(self.rule_engine) > 1:
            c.add('INFO', 'multi-engine', 'mehrere engineIds: %s'
                  % dict(self.rule_engine), path)
        for k, n in issue_keys.items():
            if n > 1:
                c.add('INFO', 'issue-duplicate', 'identisches Issue %dx (Regel, Datei, '
                      'Zeile, Spalte, Meldung) - Sonar legt es mehrfach an' % n,
                      '%s %s:%s' % (k[0], k[1], k[2]))

    # ---- Ausgabe ----------------------------------------------------------
    def summary(self):
        c = self.c
        out = []
        out.append('Server-Generation: %s (%s)' % (self.gen, '.'.join(map(str, self.ver))))
        out.append('Regeln: %d   Issues: %d   Dateien: %d   mehrzeilig: %d'
                   % (len(self.rule_ids), self.issue_count, len(self.files_seen),
                      self.multi_line))
        out.append('Endungen: ' + ', '.join('%s=%d' % kv for kv in self.ext_count.most_common()))
        out.append('Issues je Regel: ' + ', '.join('%s=%d' % kv for kv in
                                                     sorted(self.issues_per_rule.items())))
        tot = collections.Counter()
        for (s, _), n in c.counts.items():
            tot[s] += n
        out.append('Befunde: ' + '  '.join('%s=%d' % (s, tot.get(s, 0)) for s in SEVERITY_ORDER))
        for sev in SEVERITY_ORDER:
            keys = sorted(k for k in c.counts if k[0] == sev)
            for key in keys:
                out.append('')
                out.append('[%s] %s  (%d)  %s' % (sev, key[1], c.counts[key], c.text[key]))
                for s in c.samples[key]:
                    out.append('    ' + s)
                if c.counts[key] > len(c.samples[key]):
                    out.append('    ... (%d weitere)' % (c.counts[key] - len(c.samples[key])))
        return '\n'.join(out)

    def as_json(self):
        c = self.c
        return {
            'serverGeneration': self.gen,
            'rules': len(self.rule_ids), 'issues': self.issue_count,
            'files': len(self.files_seen),
            'issuesPerRule': dict(self.issues_per_rule),
            'findings': [{'severity': k[0], 'code': k[1], 'count': n,
                          'text': c.text[k], 'samples': c.samples[k]}
                         for k, n in sorted(c.counts.items())],
        }


# ---------------------------------------------------------------------------
# Selbsttest
# ---------------------------------------------------------------------------

def _selftest():
    tmp = tempfile.mkdtemp(prefix='sca_sonar_selftest_')
    ok = True

    def check(cond, text):
        nonlocal ok
        print(('  ok    ' if cond else '  FEHLT ') + text)
        ok = ok and cond

    try:
        src = os.path.join(tmp, 'proj', 'src')
        os.makedirs(os.path.join(src, 'Ümlaut'))
        # 3 Zeilen nach Sonar: "a", "bb", "" (abschliessender Umbruch)
        with open(os.path.join(src, 'Crlf.pas'), 'wb') as fh:
            fh.write(b'unit Crlf;\r\nbegin\r\n')
        # Mischumbrueche: CR allein zaehlt bei Sonar als Zeilenende -> 4 Zeilen
        with open(os.path.join(src, 'Mix.pas'), 'wb') as fh:
            fh.write(b'a\rb\r\nc\nd')
        # Umlaut-Datei UTF-8, Zeile 1 = "x := 'Größe';" -> 13 Zeichen
        with open(os.path.join(src, 'Ümlaut', 'Größe.pas'), 'wb') as fh:
            fh.write('x := \'Größe\';\n\tend.'.encode('utf-8'))
        with open(os.path.join(src, 'Ansi.pas'), 'wb') as fh:
            fh.write('s := \'Ä\';'.encode('cp1252'))
        with open(os.path.join(src, 'Form.dfm'), 'wb') as fh:
            fh.write(b'TPF0\x00\x01binary')
        with open(os.path.join(tmp, 'proj', 'sonar-project.properties'), 'w',
                  encoding='utf-8') as fh:
            fh.write('sonar.projectKey=t\nsonar.sources=src\n'
                     'sonar.exclusions=**/Ansi.pas\n')

        def rule(rid, **kw):
            r = {'id': rid, 'name': 'n' + rid, 'description': 'd', 'engineId': 'e',
                 'cleanCodeAttribute': 'LOGICAL',
                 'impacts': [{'softwareQuality': 'RELIABILITY', 'severity': 'HIGH'}]}
            r.update(kw)
            return {k: v for k, v in r.items() if v is not None}

        def issue(rid, fp, sl, **tr):
            t = {'startLine': sl}
            t.update(tr)
            return {'ruleId': rid, 'effortMinutes': 5,
                    'primaryLocation': {'message': 'm', 'filePath': fp, 'textRange': t}}

        def run(report, version='2025.1', props=True):
            p = os.path.join(tmp, 'r.json')
            with open(p, 'w', encoding='utf-8') as fh:
                json.dump(report, fh, ensure_ascii=False)
            v = Validator(os.path.join(tmp, 'proj'),
                          os.path.join(tmp, 'proj', 'sonar-project.properties') if props else None,
                          version, 'utf-8', 50)
            v.run(p)
            return {code for (_, code) in v.c.counts}, v

        good = {'rules': [rule('R1')], 'issues': [
            issue('R1', 'src/Crlf.pas', 3),
            issue('R1', 'src/Mix.pas', 4),
            issue('R1', 'src/Ümlaut/Größe.pas', 1, startColumn=0, endColumn=13),
            issue('R1', 'src/Ümlaut/Größe.pas', 1, endLine=2, startColumn=0),
        ]}
        codes, v = run(good)
        bad_sev = {code for (s, code) in v.c.counts if s in ('REJECT', 'ABORT', 'DROP')}
        check(not bad_sev, 'gueltiger Report ohne REJECT/ABORT/DROP (%s)' % sorted(bad_sev))
        check(v.src.metrics(os.path.join(src, 'Mix.pas')).lines == 4,
              'CR allein zaehlt als Zeilenende (Mix.pas = 4 Zeilen)')

        cases = [
            ('Zeile hinter Dateiende', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Crlf.pas', 4)]}, 'line-out-of-file'),
            ('endLine hinter Dateiende', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Crlf.pas', 1, endLine=9)]}, 'endline-out-of-file'),
            ('Spalte > Zeilenlaenge (UTF-16)', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Ümlaut/Größe.pas', 1, startColumn=0, endColumn=14)]},
             'endcol-out-of-line'),
            ('Datei fehlt', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Fehlt.pas', 1)]}, 'file-missing'),
            ('Gross/Klein', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/crlf.pas', 1)]}, 'path-case'),
            ('ausgeschlossen', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Ansi.pas', 1)]}, 'not-indexed'),
            ('Kodierung', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Ansi.pas', 1)]}, 'file-encoding'),
            ('binaer', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Form.dfm', 1)]}, 'file-binary'),
            ('ruleId ohne Regel', {'rules': [rule('R1')], 'issues': [
                issue('R2', 'src/Crlf.pas', 1)]}, 'issue-rule-missing'),
            ('doppelte Regel', {'rules': [rule('R1'), rule('R1')], 'issues': []},
             'rule-dup'),
            ('leere message', {'rules': [rule('R1')], 'issues': [
                {'ruleId': 'R1', 'primaryLocation': {'message': ' ', 'filePath': 'src/Crlf.pas',
                                                     'textRange': {'startLine': 1}}}]},
             'loc-message'),
            ('severity am Issue', {'rules': [rule('R1')], 'issues': [
                dict(issue('R1', 'src/Crlf.pas', 1), severity='MAJOR')]},
             'issue-deprecated-severity'),
            ('engineId am Issue', {'rules': [rule('R1')], 'issues': [
                dict(issue('R1', 'src/Crlf.pas', 1), engineId='e')]}, 'issue-engineid'),
            ('cleanCodeAttribute falsch', {'rules': [rule('R1', cleanCodeAttribute='NICE')],
                                           'issues': []}, 'rule-cca-value'),
            ('Backslash', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src\\Crlf.pas', 1)]}, 'path-backslash'),
            ('endLine ohne Spalte', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Crlf.pas', 1, endLine=2)]}, 'range-endline-ignored'),
            ('startLine 0', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Crlf.pas', 0)]}, 'range-startline'),
            ('leere Zeile mit Spalte', {'rules': [rule('R1')], 'issues': [
                issue('R1', 'src/Crlf.pas', 3, startColumn=0)]}, 'startcol-empty-line'),
        ]
        for name, rep, code in cases:
            codes, _ = run(rep)
            check(code in codes, '%s -> %s' % (name, code))
        # Versionsabhaengigkeit: BLOCKER/INFO erst ab 10.8
        rep = {'rules': [rule('R1', impacts=[{'softwareQuality': 'SECURITY',
                                              'severity': 'BLOCKER'}])], 'issues': []}
        codes, _ = run(rep, '10.6')
        check('impact-sev-version' in codes, '10.6: impact BLOCKER -> impact-sev-version')
        codes, _ = run(rep, '2025.1')
        check('impact-sev-version' not in codes, '2025.1: impact BLOCKER erlaubt')
        codes, _ = run(rep, '25.4')
        check('impact-sev-version' not in codes, 'Community Build 25.4: BLOCKER erlaubt')
        rep = {'rules': [rule('R1', cleanCodeAttribute=None)], 'issues': []}
        codes, _ = run(rep, '10.5')
        check('rule-cca' in codes, '10.5: cleanCodeAttribute Pflicht')
        codes, _ = run(rep, '2025.1')
        check('rule-cca' not in codes, '2025.1: cleanCodeAttribute optional')
        codes, _ = run({'rules': [rule('R1')], 'issues': [issue('R1', 'src/Crlf.pas', 1)]},
                       '9.9')
        check('legacy-severity' in codes, '9.9: neues Format wird abgewiesen')
        # Steuerzeichen roh / BOM / kaputtes JSON
        p = os.path.join(tmp, 'raw.json')
        with open(p, 'wb') as fh:
            fh.write(codecs.BOM_UTF8 + b'{"rules":[],"issues":[{"ruleId":"X","primaryLocation"'
                     b':{"message":"a\x01b","filePath":"src/Crlf.pas"}}]}')
        v = Validator(None, None, '2025.1', 'utf-8', 5)
        v.run(p)
        codes = {code for (_, code) in v.c.counts}
        check({'json-bom', 'json-control-char', 'issue-rule-missing'} <= codes,
              'BOM + rohes Steuerzeichen + fehlende Regel erkannt (%s)' % sorted(codes))
        with open(p, 'wb') as fh:
            fh.write(b'{"rules":[],"issues":[{"ruleId":')
        v = Validator(None, None, '2025.1', 'utf-8', 5)
        v.run(p)
        check(('REJECT', 'json-invalid') in v.c.counts, 'abgeschnittenes JSON -> json-invalid')
        # Strom-Leser mit winzigen Puffern
        p = os.path.join(tmp, 'big.json')
        rep = {'rules': [rule('R%d' % i) for i in range(50)],
               'issues': [issue('R%d' % (i % 50), 'src/Crlf.pas', 1) for i in range(500)]}
        with open(p, 'w', encoding='utf-8') as fh:
            json.dump(rep, fh, indent=1)
        n = 0
        with open(p, 'rb') as raw:
            rd = StreamReader(io.TextIOWrapper(raw, encoding='utf-8'), chunk=7)
            rd.expect('{')
            for _ in range(2):
                rd.value()
                rd.expect(':')
                n += sum(1 for _ in rd.iter_array())
                if rd.peek() == ',':
                    rd.pos += 1
        check(n == 550, 'Strom-Leser mit 7-Zeichen-Puffer liest 550 Elemente (%d)' % n)
        # Sonar-Wildcards
        rx = sonar_wildcard_to_regex('**/Win32/**')
        check(bool(rx.match('a/Win32/b.pas')) and bool(rx.match('Win32/b.pas'))
              and not rx.match('a/Win321/b.pas'), 'Wildcard **/Win32/**')
        rx = sonar_wildcard_to_regex('src/*.pas')
        check(bool(rx.match('src/a.pas')) and not rx.match('src/x/a.pas'), 'Wildcard src/*.pas')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('SELBSTTEST ' + ('BESTANDEN' if ok else 'FEHLGESCHLAGEN'))
    return 0 if ok else 1


# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('report', nargs='?', help='Generic-Issue-JSON (--sonar-export)')
    ap.add_argument('--base-dir', help='= sonar.projectBaseDir (Wurzel der filePath)')
    ap.add_argument('--properties', help='sonar-project.properties (sources/exclusions)')
    ap.add_argument('--server-version', default='2025.1',
                    help='SonarQube-Version, z. B. 10.6, 2025.1, 25.4 (Community Build)')
    ap.add_argument('--encoding', default='utf-8', help='= sonar.sourceEncoding')
    ap.add_argument('--max-list', type=int, default=25, help='Beispiele je Befundart')
    ap.add_argument('--json', help='Befunde zusaetzlich als JSON schreiben')
    ap.add_argument('--strict', action='store_true', help='WARN zaehlt als Fehler')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    if not a.report:
        ap.error('Report fehlt')
    if a.properties and not a.base_dir:
        props = read_properties(a.properties)
        a.base_dir = props.get('sonar.projectBaseDir') or os.path.dirname(
            os.path.abspath(a.properties))
    try:
        v = Validator(a.base_dir, a.properties, a.server_version, a.encoding, a.max_list)
    except (ValueError, LookupError) as e:
        print('Aufruffehler: %s' % e, file=sys.stderr)
        return 3
    v.run(a.report)
    print(v.summary())
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as fh:
            json.dump(v.as_json(), fh, ensure_ascii=False, indent=1)
    sevs = ('REJECT', 'ABORT', 'DROP') + (('WARN',) if a.strict else ())
    return 1 if v.c.total(sevs) else 0


if __name__ == '__main__':
    sys.exit(main())
