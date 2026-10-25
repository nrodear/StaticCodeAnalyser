#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wiederholbarer Laufzeit-A/B zweier SCA-Exes (Perf-Check nach jeder Charge).

Zweck: pruefen, ob die Scan-Laufzeit gegenueber einer Referenz-Exe (letzter
Release, z. B. v0.9.18) gewachsen ist, und welcher Detektor schuld ist.
Nur Messung - baut nichts, schreibt nichts ins Repo (ausser --out zeigt
dorthin). Korpora werden nur gelesen. Kein Gate (Laufzeit Minuten);
Ablauf und Schwellen: tools/perf_analyse.md, Skill perf-check.

ABLAUF JE KORPUS
  1. saubere temporaere APPDATA unter --out (optional mit Kopie einer
     analyser.ini / profiles.json - fuer BEIDE Exes identisch); die echte
     ini unter %APPDATA% bleibt unberuehrt (UI-Tests driften sie)
  2. Aufwaermlauf je Exe (Datei-Cache), verworfen
  3. N Wiederholungen, abwechselnd Basis/Kandidat (Drift verteilt sich)
  4. je Lauf: Wandzeit, CPU-Zeit (GetProcessTimes), Spitzen-Arbeitsspeicher,
     --time-detectors-out-Tabelle, Scan-Log (Phasen-Zeitstempel,
     "langsam!"-Ereignisse je Datei)
  5. Bericht (perf_ab_report.md, perf_ab_detectors.tsv, perf_ab_runs.json):
     Summen je Korpus (Median), je Detektor alt/neu/Delta/Faktor, neue und
     entfallene Detektoren, Regressionen ueber Schwelle (Standard +20 % UND
     +200 ms), Markierung "Unit seit <ref> geaendert", Zuordnung
     Detektor -> Unit -> Regel-Ids (rules/sca-rules.json detectorUnit).

ZEITFORMAT DER DETEKTOR-TABELLE
  Format 1 (bis v0.9.18 und alle Exes vor 2026-10-25): die Engine summierte
  je Aufruf ganze ms, ABGESCHNITTEN - Aufrufe unter 1 ms zaehlten 0, die
  Tabelle zeigte auf grossen Korpora nur ~50 % der echten Detektorzeit.
  Format 2 (Kennzeile 'Timing format: 2'): Ticks je Aufruf summiert, ms mit
  Nachkommastellen. Haben Basis und Kandidat VERSCHIEDENE Formate, ist der
  Vergleich je Detektor nicht belastbar (Format 2 zeigt systematisch mehr):
  der Bericht sagt das und markiert dann keine Regressionen je Detektor.
  Die Summen (Wand/CPU) bleiben gueltig; fuer die Zuordnung dann:
    --sweep          ein Profil je Detektor-Unit gegen [FileReadError]
                     (billig, ~7 s je Lauf; ueberzeichnet Units, die
                     geteilte Caches als Erste fuellen)
    --sweep --loo    Leave-one-out gegen den Volllauf aller gemeinsamen
                     Kinds (teuer, ~65 s je Lauf; der echte Grenzbeitrag)
    --sweep-changed  nur Units, die seit --git-ref geaendert sind

HYBRID-CPU
  Der Prozess wird auf einen P-Kern gepinnt (--affinity, Standard 0xC = ein
  P-Kern samt HT-Partner auf i7-14700K & Co.) und mit hoher Prioritaet
  gestartet - ohne das wandert der seriell arbeitende Scan zwischen P- und
  E-Kernen, CPU- und Wandzeit streuen um bis zu 40 %.

BEISPIEL (Basis = letzter Release-Zip, Kandidat = Output-Exe, gepatcht)
  powershell -File tools\\patch-stack-size.ps1 "Output\\Win64 Release\\StaticCodeAnalyser.d12.exe"
  python -I tools\\perf_ab.py --corpus self=. --corpus "laz=D:\\git-sca-lazarus" ^
    --corpus "jvcl=D:\\git-sca-realworld\\jvcl" --candidate-args=--dialect=delphi ^
    --profile strict --repeats 3 --out C:\\temp\\perf\\ab_strict

  --baseline darf eine Exe oder ein Release-Zip sein (wird nach
  <out>/baseline entpackt, rules/ liegt dort mit). Ohne --baseline: der
  neueste release-artifacts/StaticCodeAnalyser-v*-Win64.zip im Repo.
  Ohne --candidate: Output/Win64 Release/StaticCodeAnalyser.d12.exe.

  Zusatzargumente nur fuer eine Seite: --candidate-args=--dialect=delphi
  (MIT Gleichheitszeichen - argparse nimmt einen Wert, der mit '--'
  beginnt, sonst fuer einen eigenen Schalter)
  (v0.9.18 kennt --dialect noch nicht; ohne den Schalter waehlt der
  Kandidat fuer Lazarus-Baeume dlFpc und misst etwas anderes).
  Korpus-spezifisch: --corpus "laz=D:\\git-sca-lazarus|--dialect=fpc" (Text
  nach | geht an beide Exes).
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import datetime as dt
import glob
import json
import os
import re
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import time
import zipfile

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CANDIDATE = os.path.join(REPO, 'Output', 'Win64 Release', 'StaticCodeAnalyser.d12.exe')
MIN_STACK_MB = 32   # tools/patch-stack-size.ps1; darunter Lesefehler statt Funde

# --------------------------------------------------------------- Win32-Messung
_k32 = ctypes.WinDLL('kernel32', use_last_error=True)
_psapi = ctypes.WinDLL('psapi', use_last_error=True)


class _FT(ctypes.Structure):
    _fields_ = [('lo', wt.DWORD), ('hi', wt.DWORD)]


class _PMC(ctypes.Structure):
    _fields_ = [('cb', wt.DWORD), ('PageFaultCount', wt.DWORD),
                ('PeakWorkingSetSize', ctypes.c_size_t), ('WorkingSetSize', ctypes.c_size_t),
                ('QuotaPeakPagedPoolUsage', ctypes.c_size_t), ('QuotaPagedPoolUsage', ctypes.c_size_t),
                ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t), ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                ('PagefileUsage', ctypes.c_size_t), ('PeakPagefileUsage', ctypes.c_size_t)]


def _ft_sec(ft):
    return ((ft.hi << 32) | ft.lo) / 1e7


def proc_stats(handle):
    """CPU (user+kernel, s), User-CPU (s) und Spitzen-Arbeitsspeicher (MB) eines beendeten Prozesses."""
    c, e, k, u = _FT(), _FT(), _FT(), _FT()
    cpu = user = None
    if _k32.GetProcessTimes(wt.HANDLE(handle), ctypes.byref(c), ctypes.byref(e), ctypes.byref(k), ctypes.byref(u)):
        user = _ft_sec(u)
        cpu = user + _ft_sec(k)
    pmc = _PMC()
    pmc.cb = ctypes.sizeof(_PMC)
    peak = None
    if _psapi.GetProcessMemoryInfo(wt.HANDLE(handle), ctypes.byref(pmc), pmc.cb):
        peak = pmc.PeakWorkingSetSize / (1024 * 1024)
    return cpu, user, peak


def pe_stack_reserve_mb(path):
    """SizeOfStackReserve aus dem PE-Header (MB), None wenn nicht lesbar."""
    try:
        with open(path, 'rb') as f:
            head = f.read(4096)
        pe = struct.unpack_from('<I', head, 0x3C)[0]
        if head[pe:pe + 4] != b'PE\0\0':
            return None
        opt = pe + 24
        magic = struct.unpack_from('<H', head, opt)[0]
        fmt = '<Q' if magic == 0x20B else '<I'
        return struct.unpack_from(fmt, head, opt + 72)[0] / (1024 * 1024)
    except (OSError, struct.error):
        return None


AFFINITY = 0


# --------------------------------------------------------------- Parser
# '| 1 | LeakDetector | 1234.567 | 900 | 1.3717 | 12.3% |' (Format 2) bzw.
# '| 1 | LeakDetector | 1234 | 900 | 1,37 | 12,3% |' (Format 1, Landes-Komma
# nur in Avg/% - die werden nicht gelesen).
_ROW = re.compile(r'^\|\s*\d+\s*\|\s*([^|]+?)\s*\|\s*(\d+(?:\.\d+)?)\s*\|\s*(\d+)\s*\|')
_TOTAL = re.compile(r'^Total:\s*(\d+(?:\.\d+)?)\s*ms')
_FORMAT = re.compile(r'^Timing format:\s*(\d+)')


def parse_timing_md(path):
    """({Detektor: (ms, calls)}, Gesamt-ms, Format) aus --time-detectors-out.

    Format 1 = ganze ms je Aufruf abgeschnitten (keine Kennzeile),
    Format 2 = Ticks summiert, ms mit Dezimalpunkt. None, wenn die Datei fehlt.
    """
    det, total, form = {}, None, None
    if not os.path.exists(path):
        return det, total, form
    form = 1
    with open(path, encoding='utf-8-sig', errors='replace') as f:
        for line in f:
            m = _ROW.match(line)
            if m:
                det[m.group(1)] = (float(m.group(2)), int(m.group(3)))
                continue
            s = line.strip()
            m = _TOTAL.match(s)
            if m:
                total = float(m.group(1))
                continue
            m = _FORMAT.match(s)
            if m:
                form = int(m.group(1))
    return det, total, form


_LOG_START = re.compile(r'=== Scan gestartet: (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)')
_LOG_PL_START = re.compile(r'=== ParseLeaks gestartet: (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \((\d+) Dateien\)')
_LOG_PL_END = re.compile(r'=== ParseLeaks fertig: (\d\d:\d\d:\d\d)')
_LOG_FILE = re.compile(r'^\[\d+/\d+\]\s+(.+?)\s+\(\d+\s+KB\)')
_LOG_SLOW = re.compile(r'^\s+(Detektor\s+(\S+)|Parse|Acquire):\s+(\d+)\s+ms')


def parse_scan_log(path):
    """Phasen (Sekundenaufloesung) und langsame Einzelereignisse aus dem Scan-Log."""
    res = {'scan_start': None, 'loop_start': None, 'loop_end': None, 'files': None, 'slow': []}
    if not os.path.exists(path):
        return res
    cur = None
    with open(path, encoding='utf-8-sig', errors='replace') as f:
        for line in f:
            m = _LOG_START.search(line)
            if m and res['scan_start'] is None:
                res['scan_start'] = dt.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
                continue
            m = _LOG_PL_START.search(line)
            if m:
                if res['loop_start'] is None:
                    res['loop_start'] = dt.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
                res['files'] = (res['files'] or 0) + int(m.group(2))
                continue
            m = _LOG_PL_END.search(line)
            if m and res['loop_start'] is not None:
                t = dt.datetime.strptime(m.group(1), '%H:%M:%S').time()
                end = dt.datetime.combine(res['loop_start'].date(), t)
                if end < res['loop_start']:
                    end += dt.timedelta(days=1)
                res['loop_end'] = end
                continue
            m = _LOG_FILE.match(line)
            if m:
                cur = m.group(1)
                continue
            m = _LOG_SLOW.match(line)
            if m and ('langsam' in line) and cur:
                what = m.group(2) or m.group(1)
                res['slow'].append((what, cur, int(m.group(3))))
    return res


# --------------------------------------------------------------- Repo-Zuordnung
def repo_maps(repo):
    """Detektor-Timingname -> Unit-Datei, Unit -> Regel-Ids."""
    name2unit, unit2rules = {}, {}
    reg = os.path.join(repo, 'SCA.Engine', 'sources', 'Infrastructure', 'uStaticAnalyzer2.pas')
    if not os.path.exists(reg):
        return name2unit, unit2rules
    with open(reg, encoding='utf-8-sig', errors='replace') as f:
        src = f.read()
    regs = re.findall(r"\bAddD3?\(\s*'(\w+)'\s*,\s*(fk\w+)\s*,\s*(?:(T\w+)\.|procedure)", src)
    cls2unit = {}
    for root, _dirs, files in os.walk(os.path.join(repo, 'SCA.Engine', 'sources')):
        if '__history' in root or '__recovery' in root:
            continue
        for fn in files:
            if fn.lower().endswith('.pas'):
                try:
                    with open(os.path.join(root, fn), encoding='utf-8-sig', errors='replace') as f:
                        txt = f.read()
                except OSError:
                    continue
                for c in re.findall(r'\b(T\w+)\s*=\s*class\b', txt):
                    cls2unit.setdefault(c, fn)
    for name, _fk, cls in regs:
        if cls:
            name2unit[name] = cls2unit.get(cls, '?')
        elif name == 'DfmAnalysis':
            name2unit[name] = 'uDfmAnalysisRunner.pas'
    cat = os.path.join(repo, 'rules', 'sca-rules.json')
    if os.path.exists(cat):
        with open(cat, encoding='utf-8-sig') as f:
            for r in json.load(f).get('rules', []):
                u = r.get('detectorUnit')
                if u:
                    unit2rules.setdefault(u, []).append(r['id'])
    return name2unit, unit2rules


def changed_files(repo, ref, sub):
    try:
        out = subprocess.run(['git', '-C', repo, 'diff', '--name-only', ref, 'HEAD', '--', sub],
                             capture_output=True, text=True, check=True).stdout
        return {os.path.basename(p) for p in out.split() if p.lower().endswith('.pas')}
    except (subprocess.CalledProcessError, FileNotFoundError):
        return set()


# --------------------------------------------------------------- Exes
def _version_key(path):
    m = re.search(r'-v(\d+(?:\.\d+)*)-', os.path.basename(path))
    return tuple(int(x) for x in m.group(1).split('.')) if m else ()


def default_baseline(repo):
    zips = glob.glob(os.path.join(repo, 'release-artifacts', 'StaticCodeAnalyser-v*-Win64.zip'))
    return max(zips, key=_version_key) if zips else ''


def resolve_baseline(path, out):
    """Exe direkt; Release-Zip -> nach <out>/baseline entpacken (rules/ inklusive)."""
    if not path.lower().endswith('.zip'):
        return path
    dst = os.path.join(out, 'baseline')
    with zipfile.ZipFile(path) as z:
        z.extractall(dst)
        for info in z.infolist():   # Datum aus dem Zip, nicht das des Entpackens
            stamp = time.mktime(info.date_time + (0, 0, -1))
            os.utime(os.path.join(dst, info.filename), (stamp, stamp))
    exes = [p for p in glob.glob(os.path.join(dst, '*.exe')) if 'setup' not in os.path.basename(p).lower()]
    if not exes:
        sys.exit('keine Exe im Zip: %s' % path)
    return exes[0]


def check_exe(label, path):
    if not os.path.isfile(path):
        sys.exit('%s nicht gefunden: %s' % (label, path))
    mb = pe_stack_reserve_mb(path)
    if mb is not None and mb < MIN_STACK_MB:
        print('WARNUNG %s: Stack-Reserve %.0f MB < %d MB - erst tools\\patch-stack-size.ps1 laufen lassen, '
              'sonst werden tiefe Dateien zu Lesefehlern und der Lauf ist zu schnell UND falsch: %s'
              % (label, mb, MIN_STACK_MB, path), flush=True)


# --------------------------------------------------------------- Lauf
def run_once(exe, args, appdata, workdir, label, outdir):
    md = os.path.join(outdir, label + '.timing.md')
    full = [exe] + args + ['--quiet', '--fail-on', 'none', '--time-detectors-out', md]
    env = dict(os.environ)
    env['APPDATA'] = appdata
    log_src = os.path.join(appdata, 'StaticCodeAnalyser', 'StaticCodeAnalyser_scan.log')
    if os.path.exists(log_src):
        os.remove(log_src)
    with open(os.path.join(outdir, label + '.stdout.txt'), 'wb') as so, \
            open(os.path.join(outdir, label + '.stderr.txt'), 'wb') as se:
        t0 = time.perf_counter()
        p = subprocess.Popen(full, stdout=so, stderr=se, env=env, cwd=workdir)
        if AFFINITY:
            # Hybrid-CPU: ohne Festlegung wandert der (seriell arbeitende)
            # Scan zwischen P- und E-Kernen, CPU- und Wandzeit streuen dann
            # um +-40 %. i7-14700K: logische CPUs 0..15 = P-Kerne.
            _k32.SetProcessAffinityMask(wt.HANDLE(int(p._handle)), ctypes.c_size_t(AFFINITY))
            _k32.SetPriorityClass(wt.HANDLE(int(p._handle)), 0x80)  # HIGH_PRIORITY_CLASS
        p.wait()
        wall = time.perf_counter() - t0
        cpu, user, peak = proc_stats(int(p._handle))
    log_dst = os.path.join(outdir, label + '.scan.log')
    if os.path.exists(log_src):
        shutil.copyfile(log_src, log_dst)
    det, total, form = parse_timing_md(md)
    lg = parse_scan_log(log_dst)
    pre = loop = post = None
    if lg['scan_start'] and lg['loop_start']:
        pre = (lg['loop_start'] - lg['scan_start']).total_seconds()
    if lg['loop_start'] and lg['loop_end']:
        loop = (lg['loop_end'] - lg['loop_start']).total_seconds()
    if pre is not None and loop is not None:
        post = wall - pre - loop  # inkl. Prozessstart, Katalog, Export (+-1 s Logaufloesung)
    return {'label': label, 'wall': wall, 'cpu': cpu, 'user': user, 'peak': peak, 'exit': p.returncode,
            'det': det, 'det_total': total, 'timing_format': form, 'pre': pre, 'loop': loop, 'post': post,
            'files': lg['files'], 'slow': lg['slow'], 'cmd': subprocess.list2cmdline(full)}


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def fmt(x, nd=1):
    if x is None:
        return '-'
    return f'{x:.{nd}f}'


def load_catalog(path):
    with open(path, encoding='utf-8-sig') as f:
        rules = json.load(f).get('rules', [])
    unit2kinds = {}
    for r in rules:
        unit2kinds.setdefault(r.get('detectorUnit') or '?', []).append(r['kind'])
    return {r['kind'] for r in rules}, unit2kinds, {r['kind']: r['id'] for r in rules}


# --------------------------------------------------------------- Sweep / LOO
def sweep(a, sides, appdata):
    """Ablation: je Unit ein Lauf mit nur ihren Kinds, Zuwachs gegen [FileReadError]."""
    brules = a.baseline_rules or os.path.join(os.path.dirname(sides['old'][0]), 'rules', 'sca-rules.json')
    crules = a.candidate_rules or os.path.join(a.repo, 'rules', 'sca-rules.json')
    kinds_old = load_catalog(brules)[0]
    kinds_new, unit2kinds, kind2id = load_catalog(crules)
    changed = changed_files(a.repo, a.git_ref, 'SCA.Engine/sources/Detectors')
    pj = os.path.join(appdata, 'StaticCodeAnalyser', 'profiles.json')
    prof = {'version': 1, 'profiles': {}}
    if os.path.exists(pj):
        with open(pj, encoding='utf-8-sig') as f:
            prof = json.load(f)
    units = sorted(u for u in unit2kinds if u not in ('?', '(parser)'))
    if a.sweep_units:
        want = {x.strip() for x in a.sweep_units.split(',')}
        units = [u for u in units if u in want]
    if a.sweep_changed:
        units = [u for u in units if u in changed]
    # LOO-Modus: Basis = alle Kinds, die BEIDE Exes kennen; je Unit wird sie
    # weggelassen (gemeinsame Unit) bzw. hinzugefuegt (nur Kandidat). Der
    # Zuwachs ist dann der echte Grenzbeitrag im Volllauf (geteilte Caches
    # sind bereits bezahlt) - teurer (Volllaeufe), aber genauer als der Sweep.
    loo_remove = {}
    if a.loo:
        common = sorted(kinds_old & set(kinds_new))
        prof['profiles']['sw-base'] = common
        for u in units:
            if all(k in kinds_old for k in unit2kinds[u]):
                prof['profiles']['sw-' + u] = [k for k in common if k not in unit2kinds[u]]
                loo_remove[u] = True
            else:
                prof['profiles']['sw-' + u] = common + [k for k in unit2kinds[u] if k not in common]
                loo_remove[u] = False
    else:
        prof['profiles']['sw-base'] = ['FileReadError']
        for u in units:
            prof['profiles']['sw-' + u] = ['FileReadError'] + unit2kinds[u]
    with open(pj, 'w', encoding='utf-8') as f:
        json.dump(prof, f, indent=1)
    workdir = os.path.join(a.out, 'cwd')
    res = {}
    for spec in a.corpus:
        label, rest = spec.split('=', 1)
        path, _, extra = rest.partition('|')
        path = os.path.abspath(path)  # die Exe laeuft in <out>/cwd

        def go(side, pname, tag, label=label, path=path, extra=extra):
            exe, sargs = sides[side]
            args = ['--path', path, '--full', '--profile', pname, '--min-severity', a.min_severity] + extra.split() + sargs
            return run_once(exe, args, appdata, workdir, f'{label}_{side}_{tag}', a.out)['cpu']

        for _w in range(a.warmup):
            go('old', 'sw-base', 'warm')
            go('new', 'sw-base', 'warm')
        for u in ['(base)'] + units:
            pname = 'sw-base' if u == '(base)' else 'sw-' + u
            ks = ['FileReadError'] if u == '(base)' else unit2kinds[u]
            old_ok = all(k in kinds_old for k in ks)
            vals = {'old': [], 'new': []}
            tag = u.replace('(', '').replace(')', '')
            for i in range(a.repeats):
                for side in (('old', 'new') if i % 2 == 0 else ('new', 'old')):
                    if side == 'old' and not old_ok:
                        continue
                    vals[side].append(go(side, pname, f'{tag}_r{i + 1}'))
            res[(label, u)] = (med(vals['old']), med(vals['new']))
            print(f'{label} {u}: old {fmt(res[(label, u)][0], 2)} new {fmt(res[(label, u)][1], 2)}', flush=True)
    L = [f'# Perf-Sweep je Detektor-Unit {dt.datetime.now():%Y-%m-%d %H:%M}\n',
         f'- Basis `{sides["old"][0]}`, Kandidat `{sides["new"][0]}`; CPU-Sekunden (Median aus {a.repeats}); '
         + ('LOO: Zuwachs = Lauf mit allen gemeinsamen Kinds minus Lauf ohne die Kinds der Unit '
            '(neue Units: mit minus ohne)' if a.loo else
            'Zuwachs = Lauf mit [FileReadError + Kinds der Unit] minus Lauf mit [FileReadError]'),
         '- Grenzen: Units mit ini-Freigabe (UnusedUses: [Detectors] UsesCheck) laufen nur, wenn die ini es erlaubt; '
         'geteilte Caches (FindAll-Walk, Strip-Cache) bezahlt im Einzellauf die Unit selbst - die Summe der Zuwaechse '
         'ist daher groesser als der Volllauf; Rauschen je Lauf ca. +-0,1 s.\n']
    tsv = ['corpus\tunit\trules\tchanged\told_inc_s\tnew_inc_s\tdelta_s\tflag']
    for spec in a.corpus:
        label = spec.split('=', 1)[0]
        bo, bn = res[(label, '(base)')]
        L.append(f'## {label}: Basis alt {fmt(bo, 2)} s, neu {fmt(bn, 2)} s\n')
        L.append('| Unit | Regeln | seit Ref geaendert | alt +s | neu +s | Delta s | Faktor | Marke |')
        L.append('|---|---|---|---:|---:|---:|---:|---|')
        rows = []
        for u in units:
            o, n = res[(label, u)]
            io = (o - bo) if (o is not None and bo is not None) else None
            inn = (n - bn) if (n is not None and bn is not None) else None
            if loo_remove.get(u):
                io = -io if io is not None else None
                inn = -inn if inn is not None else None
            d = (inn or 0) - (io or 0)
            if io is None:
                flag = 'NEU'
            elif d * 1000 >= a.threshold_ms and (io <= 0 or d / max(io, 1e-9) * 100 >= a.threshold_pct):
                flag = 'REGRESSION'
            elif -d * 1000 >= a.threshold_ms and io > 0 and -d / io * 100 >= a.threshold_pct:
                flag = 'schneller'
            else:
                flag = ''
            fac = (inn / io) if (io is not None and io > 0.05 and inn is not None) else None
            rules = ','.join(kind2id[k] for k in unit2kinds[u] if k in kind2id)
            rows.append((u, rules, 'ja' if u in changed else '', io, inn, d, fac, flag))
            tsv.append(f'{label}\t{u}\t{rules}\t{rows[-1][2]}\t{fmt(io, 3)}\t{fmt(inn, 3)}\t{d:.3f}\t{flag}')
        for r in sorted(rows, key=lambda r: -r[5]):
            L.append(f'| {r[0]} | {r[1]} | {r[2]} | {fmt(r[3], 2)} | {fmt(r[4], 2)} | {r[5]:+.2f} | {fmt(r[6], 2)} | {r[7]} |')
        L.append('')
    with open(os.path.join(a.out, 'perf_sweep_report.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(L) + '\n')
    with open(os.path.join(a.out, 'perf_sweep.tsv'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(tsv) + '\n')
    print('Bericht:', os.path.join(a.out, 'perf_sweep_report.md'))
    shutil.rmtree(appdata, ignore_errors=True)


# --------------------------------------------------------------- A/B
def detector_rows(a, lab, ro, rn, name2unit, unit2rules, changed, flag_ok, tsv):
    names = set().union(*[r['det'].keys() for r in ro + rn])
    rows = []
    for n in names:
        o = med([r['det'][n][0] for r in ro if n in r['det']])
        nw = med([r['det'][n][0] for r in rn if n in r['det']])
        unit = name2unit.get(n, '?')
        rules = ','.join(unit2rules.get(unit, []))
        chg = 'ja' if unit in changed else ''
        if o is None:
            flag = 'NEU'
        elif nw is None:
            flag = 'ENTFALLEN'
        elif not flag_ok:
            flag = ''
        elif nw - o >= a.threshold_ms and (o == 0 or (nw - o) / o * 100 >= a.threshold_pct):
            flag = 'REGRESSION'
        elif o - nw >= a.threshold_ms and (o - nw) / o * 100 >= a.threshold_pct:
            flag = 'schneller'
        else:
            flag = ''
        fac = (nw / o) if (o and nw is not None) else None
        rows.append((n, unit, rules, chg, o, nw, (nw or 0) - (o or 0), fac, flag))
        tsv.append(f"{lab}\t{n}\t{unit}\t{rules}\t{chg}\t{fmt(o, 3) if o is not None else ''}\t"
                   f"{fmt(nw, 3) if nw is not None else ''}\t{(nw or 0) - (o or 0):.3f}\t"
                   f"{fmt(fac, 2) if fac else ''}\t{flag}")
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--baseline', default='',
                    help='Basis-Exe oder Release-Zip (Standard: neuester release-artifacts/StaticCodeAnalyser-v*-Win64.zip)')
    ap.add_argument('--candidate', default=DEFAULT_CANDIDATE,
                    help='Kandidat-Exe (Standard: Output/Win64 Release/StaticCodeAnalyser.d12.exe)')
    ap.add_argument('--corpus', action='append', required=True,
                    help='label=pfad[|zusatzargs fuer beide]; mehrfach')
    ap.add_argument('--profile', default='strict')
    ap.add_argument('--min-severity', default='hint')
    ap.add_argument('--repeats', type=int, default=3)
    ap.add_argument('--warmup', type=int, default=1)
    ap.add_argument('--baseline-args', default='')
    ap.add_argument('--candidate-args', default='')
    ap.add_argument('--sarif', action='store_true', help='SARIF mitschreiben (misst Exportphase mit; r1 bleibt liegen)')
    ap.add_argument('--ini', default='', help='analyser.ini fuer die temp. APPDATA (Standard: keine = Werkseinstellung)')
    ap.add_argument('--profiles-json', default='', help='profiles.json fuer die temp. APPDATA (eigene Profile)')
    ap.add_argument('--repo', default=REPO, help='Repo fuer Detektor->Unit->Regel und git diff (Standard: dieses)')
    ap.add_argument('--git-ref', default='v0.9.18', help='Referenz fuer "seit Ref geaendert"')
    ap.add_argument('--threshold-pct', type=float, default=20.0)
    ap.add_argument('--threshold-ms', type=float, default=200.0)
    ap.add_argument('--affinity', default='0xC',
                    help='Prozessor-Affinitaetsmaske (hex), Standard 0xC = ein P-Kern samt HT-Partner; 0 = aus')
    ap.add_argument('--candidate-only', action='store_true',
                    help='nur den Kandidaten laufen lassen (Leave-one-out-Profile, Profile die die Basis nicht kennt)')
    ap.add_argument('--sweep', action='store_true',
                    help='Ablation je Detektor-Unit: ein Profil pro detectorUnit (alle Kinds der Unit), '
                         'Zuwachs (CPU-Sekunden) gegen das Basisprofil [FileReadError]')
    ap.add_argument('--loo', action='store_true',
                    help='mit --sweep: Leave-one-out gegen den Volllauf aller gemeinsamen Kinds statt Einzelprofil')
    ap.add_argument('--sweep-changed', action='store_true',
                    help='mit --sweep: nur Units, die seit --git-ref geaendert wurden')
    ap.add_argument('--sweep-units', default='', help='nur diese Units (Komma-Liste, z. B. uUninitVar.pas)')
    ap.add_argument('--baseline-rules', default='', help='sca-rules.json der Basis (Standard: <exe-Ordner>/rules)')
    ap.add_argument('--candidate-rules', default='', help='sca-rules.json des Kandidaten (Standard: <repo>/rules)')
    ap.add_argument('--out', required=True, help='Ausgabeordner (ausserhalb des Repos)')
    a = ap.parse_args()
    global AFFINITY
    AFFINITY = int(a.affinity, 16)

    os.makedirs(a.out, exist_ok=True)
    baseline = a.baseline or default_baseline(a.repo)
    if not baseline:
        sys.exit('keine Basis: --baseline angeben (kein release-artifacts/StaticCodeAnalyser-v*-Win64.zip)')
    baseline = resolve_baseline(baseline, a.out)
    check_exe('Basis', baseline)
    check_exe('Kandidat', a.candidate)

    appdata = tempfile.mkdtemp(prefix='sca_appdata_', dir=a.out)
    os.makedirs(os.path.join(appdata, 'StaticCodeAnalyser'), exist_ok=True)
    if a.ini:
        shutil.copyfile(a.ini, os.path.join(appdata, 'StaticCodeAnalyser', 'analyser.ini'))
    if a.profiles_json:
        shutil.copyfile(a.profiles_json, os.path.join(appdata, 'StaticCodeAnalyser', 'profiles.json'))
    workdir = os.path.join(a.out, 'cwd')
    os.makedirs(workdir, exist_ok=True)

    sides = {'old': (baseline, a.baseline_args.split()), 'new': (a.candidate, a.candidate_args.split())}
    if a.sweep:
        return sweep(a, sides, appdata)
    results = {}  # (corpus, side) -> [run]
    for spec in a.corpus:
        label, rest = spec.split('=', 1)
        path, _, extra = rest.partition('|')
        path = os.path.abspath(path)  # die Exe laeuft in <out>/cwd
        base = ['--path', path, '--full', '--profile', a.profile, '--min-severity', a.min_severity] + extra.split()
        plan = []
        for w in range(a.warmup):
            plan += [('old', f'{label}_old_warm{w}'), ('new', f'{label}_new_warm{w}')]
        for i in range(a.repeats):
            order = ['old', 'new'] if i % 2 == 0 else ['new', 'old']
            plan += [(s, f'{label}_{s}_r{i + 1}') for s in order]
        if a.candidate_only:
            plan = [(s, rl) for s, rl in plan if s == 'new']
        for side, run_label in plan:
            exe, sargs = sides[side]
            args = base + sargs
            if a.sarif:
                args += ['--report-sarif', os.path.join(a.out, run_label + '.sarif')]
            r = run_once(exe, args, appdata, workdir, run_label, a.out)
            print(f"{run_label}: wall {r['wall']:.2f}s cpu {fmt(r['cpu'], 2)}s peak {fmt(r['peak'], 0)}MB "
                  f"exit {r['exit']} det {fmt(r['det_total'], 0)}ms (Format {r['timing_format'] or '-'})", flush=True)
            if '_warm' not in run_label:
                results.setdefault((label, side), []).append(r)
                if a.sarif and not run_label.endswith('_r1'):
                    try:
                        os.remove(os.path.join(a.out, run_label + '.sarif'))  # nur r1 behalten (Platz)
                    except OSError:
                        pass
            elif a.sarif:
                try:
                    os.remove(os.path.join(a.out, run_label + '.sarif'))
                except OSError:
                    pass

    name2unit, unit2rules = repo_maps(a.repo)
    changed = changed_files(a.repo, a.git_ref, 'SCA.Engine/sources/Detectors')
    changed_infra = sorted(changed_files(a.repo, a.git_ref, 'SCA.Engine/sources') - changed)

    L = []
    L.append(f'# Perf-A/B {dt.datetime.now():%Y-%m-%d %H:%M}\n')
    L.append(f'- Basis: `{baseline}` (Aenderungsdatum {dt.datetime.fromtimestamp(os.path.getmtime(baseline)):%Y-%m-%d %H:%M})')
    L.append(f'- Kandidat: `{a.candidate}` (Aenderungsdatum {dt.datetime.fromtimestamp(os.path.getmtime(a.candidate)):%Y-%m-%d %H:%M})')
    L.append(f'- Profil `{a.profile}`, min-severity `{a.min_severity}`, {a.repeats} Wiederholungen + {a.warmup} Aufwaermlauf, '
             f'APPDATA temporaer (ini: {a.ini or "Werkseinstellung"}), SARIF: {"ja" if a.sarif else "nein"}, '
             f'Affinitaet {a.affinity}, Prioritaet hoch')
    L.append(f'- Geaenderte Detektor-Units seit `{a.git_ref}`: {len(changed)}; geaenderte sonstige Engine-Units: {len(changed_infra)}\n')
    L.append('## Summen je Korpus (Median)\n')
    L.append('| Korpus | Seite | Dateien | Wand s | CPU s | Spitze MB | Detektoren s | Zeitformat | Vorphase s | Dateischleife s | Nachphase s | Exit |')
    L.append('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|')
    tsv = ['corpus\tdetector\tunit\trules\tchanged\told_ms\tnew_ms\tdelta_ms\tfactor\tflag']
    corpora = []
    for spec in a.corpus:
        lab = spec.split('=', 1)[0]
        if lab not in corpora:
            corpora.append(lab)
    detail = []
    for lab in corpora:
        for side in ('old', 'new'):
            rs = results.get((lab, side), [])
            if not rs:
                continue
            forms = sorted({r['timing_format'] for r in rs if r['timing_format']})
            L.append(f"| {lab} | {side} | {rs[0]['files'] or '-'} | {fmt(med([r['wall'] for r in rs]), 2)} | "
                     f"{fmt(med([r['cpu'] for r in rs]), 2)} | {fmt(med([r['peak'] for r in rs]), 0)} | "
                     f"{fmt((med([r['det_total'] for r in rs]) or 0) / 1000, 2)} | {','.join(map(str, forms)) or '-'} | "
                     f"{fmt(med([r['pre'] for r in rs]), 0)} | "
                     f"{fmt(med([r['loop'] for r in rs]), 0)} | {fmt(med([r['post'] for r in rs]), 0)} | "
                     f"{','.join(str(r['exit']) for r in rs)} |")
        ro, rn = results.get((lab, 'old'), []), results.get((lab, 'new'), [])
        if not ro or not rn:
            continue
        fo = {r['timing_format'] for r in ro}
        fn_ = {r['timing_format'] for r in rn}
        flag_ok = fo == fn_
        rows = detector_rows(a, lab, ro, rn, name2unit, unit2rules, changed, flag_ok, tsv)
        common = [r for r in rows if r[4] is not None and r[5] is not None]
        detail.append(f'\n## {lab}: Detektoren\n')
        if not flag_ok:
            detail.append(f'- **Zeitformat verschieden (Basis {sorted(fo, key=str)}, Kandidat {sorted(fn_, key=str)})**: '
                          'Format 1 schneidet je Aufruf auf ganze ms ab und zeigt systematisch weniger. '
                          'Vergleich je Detektor NICHT belastbar, keine Regressionsmarken - Zuordnung per '
                          '`--sweep` bzw. `--sweep --loo`.')
        detail.append(f"- gemeinsam ({len(common)}): alt {sum(r[4] for r in common) / 1000:.2f} s, "
                      f"neu {sum(r[5] for r in common) / 1000:.2f} s")
        newd = sorted([r for r in rows if r[4] is None], key=lambda r: -r[5])
        gone = [r for r in rows if r[5] is None]
        detail.append(f"- neu ({len(newd)}): {sum(r[5] for r in newd) / 1000:.2f} s - " +
                      ', '.join(f'{r[0]} {r[5]:.0f} ms' for r in newd))
        if gone:
            detail.append(f"- entfallen/umbenannt ({len(gone)}): " + ', '.join(f'{r[0]} {r[4]:.0f} ms' for r in gone))
        flagged = sorted([r for r in rows if r[8] == 'REGRESSION'], key=lambda r: -r[6])
        detail.append(f"\n### Regressionen (>= +{a.threshold_pct:.0f} % und >= +{a.threshold_ms:.0f} ms): "
                      f"{len(flagged) if flag_ok else 'nicht bewertet (Zeitformat)'}\n")
        if flagged:
            detail.append('| Detektor | Unit | Regeln | seit Ref geaendert | alt ms | neu ms | Delta | Faktor |')
            detail.append('|---|---|---|---|---:|---:|---:|---:|')
            for r in flagged:
                detail.append(f'| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]:.0f} | {r[5]:.0f} | {r[6]:+.0f} | {fmt(r[7], 2)} |')
        detail.append('\n### Top 15 (neu, nach ms)\n')
        detail.append('| Detektor | Unit | geaendert | alt ms | neu ms | Delta | Faktor | Marke |')
        detail.append('|---|---|---|---:|---:|---:|---:|---|')
        for r in sorted(rows, key=lambda r: -(r[5] or 0))[:15]:
            detail.append(f"| {r[0]} | {r[1]} | {r[3]} | {fmt(r[4], 0)} | {fmt(r[5], 0)} | {r[6]:+.0f} | {fmt(r[7], 2)} | {r[8]} |")
        detail.append('\n### Top 10 (alt, nach ms)\n')
        detail.append('| Detektor | alt ms | neu ms |')
        detail.append('|---|---:|---:|')
        for r in sorted(rows, key=lambda r: -(r[4] or 0))[:10]:
            detail.append(f'| {r[0]} | {fmt(r[4], 0)} | {fmt(r[5], 0)} |')
        for side, rs in (('old', ro), ('new', rn)):
            slow = {}
            for what, fn, ms in rs[0]['slow']:
                slow[(what, fn)] = ms
            top = sorted(slow.items(), key=lambda kv: -kv[1])[:8]
            if top:
                detail.append(f'\n### langsame Einzelereignisse {side} (Lauf 1, Log "langsam!")\n')
                for (what, fn), ms in top:
                    detail.append(f'- {what}: {ms} ms - `{fn}`')
    L += detail
    L.append('\n## Geaenderte Engine-Units ausserhalb Detectors seit ' + a.git_ref + '\n')
    L.append(', '.join(changed_infra) if changed_infra else '-')
    L.append('\n## Kommandos (Lauf 1 je Seite)\n')
    for (lab, side), rs in results.items():
        L.append(f'- {lab}/{side}: `{rs[0]["cmd"]}`')
    with open(os.path.join(a.out, 'perf_ab_report.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(L) + '\n')
    with open(os.path.join(a.out, 'perf_ab_detectors.tsv'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(tsv) + '\n')
    with open(os.path.join(a.out, 'perf_ab_runs.json'), 'w', encoding='utf-8') as f:
        json.dump({f'{k[0]}/{k[1]}': [{x: y for x, y in r.items() if x not in ('slow',)} for r in v]
                   for k, v in results.items()}, f, indent=1, default=str)
    print('Bericht:', os.path.join(a.out, 'perf_ab_report.md'))
    shutil.rmtree(appdata, ignore_errors=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
