#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stresslauf fuer die seltene Heap-Korruption (AV-Jagd 2026-10-25).

ANLASS: 1 von 22 seriellen Realworld-Volllaeufen (Win64 Release) brachte
zwei SCA006-Lesefehler mit EAccessViolation tief in der Speicherverwaltung
(DynArraySetLength, TStringBuilder.Create) - Opfer einer frueheren
Heap-Korruption. Ein Einzellauf beweist dabei nichts; erst viele gleiche
Laeufe zeigen, ob und wo es wieder passiert.

JE LAUF
  1. frische temporaere APPDATA mit einer KOPIE von analyser.ini,
     profiles.json und ignore.txt (Standard: %APPDATA%\\StaticCodeAnalyser)
     - die echte ini bleibt unberuehrt, kein Lauf erbt Drift vom vorigen
  2. SCA_CRASH_STACK=<out>/runNN.crashstack.log (abschaltbar), damit die
     Exe an jedem Fangpunkt Ort, Datei und Stapel schreibt (uCrashDiag)
  3. CLI-Lauf, stdout/stderr in Dateien, Exit-Code, Dauer
  4. Auswertung der Fundzeilen der Konsolenausgabe ('Sev  Pfad:Zeile  Kind
     Meldung'): Lesefehler (FileReadError = SCA006), davon die mit
     Ausnahme-Text (Exception, EAccessViolation, EInvalidPointer, 'failed')
  5. Fundmenge als Multimenge gegen Lauf 1: Zugaenge/Abgaenge mit Beispielen
  6. Diagnosedatei: Zahl der Eintraege; mit Map (Standard <Exe>.map neben
     der Exe) aufgeloest nach runNN.crashstack.resolved.txt
  7. FastMM-FullDebugMode-Bau: neuer Inhalt von
     <Exe>_MemoryManager_EventLog.txt -> runNN.fastmm.txt

AUFBEWAHRT: Lauf 1 (Referenz) und jeder auffaellige Lauf komplett, sonst
nur die Kennzahlen (eine Konsolenausgabe des Realworld-Korpus hat ~170 MB);
--keep-output behaelt alles.

BEISPIEL
  set SCA=Output\\Win64 Release\\StaticCodeAnalyser.d12.exe
  powershell -File tools\\patch-stack-size.ps1 "%SCA%"
  python -I tools\\av_stress.py --corpus D:\\git-sca-realworld --runs 22 ^
      --out C:\\temp\\avstress
  (Ergebnis: <out>\\av_stress_report.md, <out>\\status.tsv)

EXIT  0 kein Lauf auffaellig | 1 mindestens ein Lauf auffaellig | 2 Aufruffehler
"""
import argparse
import collections
import datetime as dt
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_EXE = os.path.join(REPO, 'Output', 'Win64 Release', 'StaticCodeAnalyser.d12.exe')
DEFAULT_ARGS = '--dialect=delphi --full --profile strict --min-severity hint'
MIN_STACK_MB = 32   # tools/patch-stack-size.ps1; darunter Lesefehler statt Funde
SEVERITIES = ('Error', 'Warning', 'Hint', 'Info')
EXC_TEXT = re.compile(r'Exception|EAccessViolation|EInvalidPointer|EOutOfMemory|failed|Zugriffsverletzung')
SUMMARY = re.compile(r'^Summary:.*?(\d+) Read Error')
CRASH_ENTRY = re.compile(r'^=== \d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+ Thread ')


def pe_stack_reserve_mb(path):
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


def finding_parts(line):
    """(sev, ort, kind, meldung) einer Fundzeile, sonst None."""
    if not line.startswith(SEVERITIES):
        return None
    parts = line.rstrip('\r\n').split('  ', 3)
    if len(parts) < 3 or parts[0] not in SEVERITIES:
        return None
    while len(parts) < 4:
        parts.append('')
    return tuple(parts)


def digest(line):
    return hashlib.blake2b(line.rstrip('\r\n').encode('utf-8', 'replace'), digest_size=8).digest()


def scan_stdout(path):
    """Multimenge der Fundzeilen (Digest) + Lesefehler + Summenzeile."""
    counts = collections.Counter()
    read_errors, exc_errors = [], []
    summary_read = None
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            p = finding_parts(line)
            if p is None:
                m = SUMMARY.match(line)
                if m:
                    summary_read = int(m.group(1))
                continue
            counts[digest(line)] += 1
            if p[2] == 'FileReadError':
                read_errors.append(line.rstrip('\r\n'))
                if EXC_TEXT.search(p[3]):
                    exc_errors.append(line.rstrip('\r\n'))
    return counts, read_errors, exc_errors, summary_read


def lines_with_digests(path, wanted, limit):
    out = []
    if not wanted:
        return out
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            if finding_parts(line) is None:
                continue
            if digest(line) in wanted:
                out.append(line.rstrip('\r\n'))
                if len(out) >= limit:
                    break
    return out


def count_crash_entries(path):
    if not os.path.exists(path):
        return None
    n = 0
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            if CRASH_ENTRY.match(line):
                n += 1
    return n


def file_size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def copy_tail(src, start, dst):
    """Was seit 'start' an src angehaengt wurde, nach dst. Bytes oder 0."""
    size = file_size(src)
    if size <= start:
        return 0
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        f.seek(start)
        o.write(f.read())
    return size - start


def fresh_appdata(root, src_dir, label):
    ad = os.path.join(root, 'appdata_' + label)
    shutil.rmtree(ad, ignore_errors=True)
    os.makedirs(os.path.join(ad, 'StaticCodeAnalyser'))
    copied = []
    for fn in ('analyser.ini', 'profiles.json', 'ignore.txt'):
        s = os.path.join(src_dir, fn) if src_dir else ''
        if s and os.path.isfile(s):
            shutil.copyfile(s, os.path.join(ad, 'StaticCodeAnalyser', fn))
            copied.append(fn)
    return ad, copied


def resolve_crash_log(map_path, crash_log, dst, exe_name):
    script = os.path.join(REPO, 'tools', 'map_resolve.py')
    r = subprocess.run([sys.executable, '-I', script, map_path, '--log', crash_log,
                        '--module', exe_name, '--out', dst],
                       capture_output=True, text=True)
    return r.returncode == 0 or os.path.exists(dst)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--exe', default=DEFAULT_EXE, help='CLI-Exe (Standard: Output/Win64 Release/StaticCodeAnalyser.d12.exe)')
    ap.add_argument('--corpus', required=True, help='zu scannender Ordner (--path der CLI)')
    ap.add_argument('--runs', type=int, default=10)
    ap.add_argument('--out', required=True, help='Ausgabeordner (ausserhalb des Repos)')
    ap.add_argument('--args', default=DEFAULT_ARGS,
                    help='weitere CLI-Argumente (MIT Gleichheitszeichen angeben: --args="...")')
    ap.add_argument('--appdata-src', default=os.path.join(os.environ.get('APPDATA', ''), 'StaticCodeAnalyser'),
                    help='Ordner mit analyser.ini/profiles.json/ignore.txt fuer die Kopie ("" = Werkseinstellung)')
    ap.add_argument('--map', default='', help='Detailed-Map des Baus (Standard: <Exe ohne Endung>.map)')
    ap.add_argument('--no-crash-stack', action='store_true', help='SCA_CRASH_STACK NICHT setzen')
    ap.add_argument('--keep-output', action='store_true', help='Konsolenausgabe jedes Laufs behalten')
    ap.add_argument('--stop-on-hit', action='store_true', help='nach dem ersten auffaelligen Lauf aufhoeren')
    ap.add_argument('--timeout', type=float, default=0, help='Sekunden je Lauf (0 = ohne)')
    ap.add_argument('--examples', type=int, default=5, help='Beispielzeilen je Zugang/Abgang')
    a = ap.parse_args()

    exe = os.path.abspath(a.exe)
    if not os.path.isfile(exe):
        print('Exe nicht gefunden:', exe)
        return 2
    mb = pe_stack_reserve_mb(exe)
    if mb is not None and mb < MIN_STACK_MB:
        print('WARNUNG: Stack-Reserve %.0f MB < %d MB - erst tools\\patch-stack-size.ps1, '
              'sonst Lesefehler aus Stapelmangel statt der gesuchten AV' % (mb, MIN_STACK_MB), flush=True)
    corpus = os.path.abspath(a.corpus)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    workdir = os.path.join(out, 'cwd')
    os.makedirs(workdir, exist_ok=True)
    tmp_root = tempfile.mkdtemp(prefix='sca_avstress_', dir=out)
    map_path = a.map or (os.path.splitext(exe)[0] + '.map')
    if not os.path.isfile(map_path):
        map_path = ''
    exe_name = os.path.basename(exe)
    fastmm_log = os.path.splitext(exe)[0] + '_MemoryManager_EventLog.txt'
    extra = a.args.split()

    status = os.path.join(out, 'status.tsv')
    if not os.path.exists(status):
        with open(status, 'w', encoding='utf-8') as f:
            f.write('run\texit\tsecs\tfindings\tread_errors\texc_read_errors\tadds\tdrops\t'
                    'crash_entries\tfastmm_bytes\tauffaellig\n')

    ref_counts, ref_out, ref_entries = None, None, None
    rows, exc_index = [], collections.OrderedDict()
    copied = []
    started = dt.datetime.now()
    for i in range(1, a.runs + 1):
        label = 'run%02d' % i
        appdata, copied = fresh_appdata(tmp_root, a.appdata_src, label)
        so_path = os.path.join(out, label + '.stdout.txt')
        se_path = os.path.join(out, label + '.stderr.txt')
        crash = os.path.join(out, label + '.crashstack.log')
        if os.path.exists(crash):
            os.remove(crash)
        env = dict(os.environ)
        env['APPDATA'] = appdata
        if a.no_crash_stack:
            env.pop('SCA_CRASH_STACK', None)
        else:
            env['SCA_CRASH_STACK'] = crash
        fm_start = file_size(fastmm_log)
        cmd = [exe, '--path', corpus] + extra
        t0 = time.perf_counter()
        with open(so_path, 'wb') as so, open(se_path, 'wb') as se:
            p = subprocess.Popen(cmd, stdout=so, stderr=se, env=env, cwd=workdir)
            try:
                rc = p.wait(timeout=a.timeout or None)
            except subprocess.TimeoutExpired:
                p.kill()
                rc = 'timeout'
        secs = time.perf_counter() - t0

        counts, read_errors, exc_errors, summary_read = scan_stdout(so_path)
        adds = drops = 0
        add_ex, drop_ex = [], []
        if ref_counts is None:
            ref_counts, ref_out = counts, so_path
        else:
            plus = counts - ref_counts
            minus = ref_counts - counts
            adds, drops = sum(plus.values()), sum(minus.values())
            add_ex = lines_with_digests(so_path, set(plus), a.examples)
            drop_ex = lines_with_digests(ref_out, set(minus), a.examples)
        entries = count_crash_entries(crash)
        fm_bytes = copy_tail(fastmm_log, fm_start, os.path.join(out, label + '.fastmm.txt'))
        # Auffaellig = anders als Lauf 1. Deterministische Lesefehler (eine
        # Datei, die IMMER scheitert) stehen in jedem Lauf gleich und
        # machen keinen Lauf auffaellig; Lauf 1 selbst ist es, sobald er
        # ueberhaupt Ausnahme-Lesefehler oder Diagnose-Eintraege hat.
        if i == 1:
            ref_entries = entries
            odd = bool(exc_errors or entries)
        else:
            odd = bool(adds or drops or entries != ref_entries)
        odd = odd or rc not in (0, 1, 2, 3) or fm_bytes > 0
        resolved = ''
        if entries and map_path:
            dst = os.path.join(out, label + '.crashstack.resolved.txt')
            if resolve_crash_log(map_path, crash, dst, exe_name):
                resolved = dst
        scan_log = os.path.join(appdata, 'StaticCodeAnalyser', 'StaticCodeAnalyser_scan.log')
        if odd and os.path.exists(scan_log):
            shutil.copyfile(scan_log, os.path.join(out, label + '.scan.log'))
        if not odd and not a.keep_output and i > 1:
            os.remove(so_path)
        if entries == 0 and not odd and os.path.exists(crash):
            os.remove(crash)   # nur der Kopf - kein Fangpunkt erreicht
        shutil.rmtree(appdata, ignore_errors=True)

        for line in exc_errors:
            parts = finding_parts(line)
            key = (parts[1], parts[3]) if parts else (line, '')
            exc_index.setdefault(key, []).append(i)
        n = sum(counts.values())
        rows.append({'run': i, 'rc': rc, 'secs': secs, 'n': n, 'read': len(read_errors),
                     'exc': len(exc_errors), 'adds': adds, 'drops': drops, 'entries': entries,
                     'fm': fm_bytes, 'odd': odd, 'add_ex': add_ex, 'drop_ex': drop_ex,
                     'resolved': resolved, 'summary_read': summary_read})
        with open(status, 'a', encoding='utf-8') as f:
            f.write('%d\t%s\t%.0f\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%s\n'
                    % (i, rc, secs, n, len(read_errors), len(exc_errors), adds, drops,
                       '-' if entries is None else entries, fm_bytes, 'JA' if odd else ''))
        print('%s exit=%s %.0fs funde=%d lesefehler=%d davon_ausnahme=%d zu=%d ab=%d '
              'diagnose=%s fastmm=%dB%s' % (label, rc, secs, n, len(read_errors), len(exc_errors),
                                            adds, drops, '-' if entries is None else entries, fm_bytes,
                                            '  <== AUFFAELLIG' if odd else ''), flush=True)
        if odd and a.stop_on_hit:
            break

    shutil.rmtree(tmp_root, ignore_errors=True)
    L = ['# AV-Stresslauf %s\n' % started.strftime('%Y-%m-%d %H:%M'),
         '- Exe: `%s` (Aenderungsdatum %s)' % (exe, dt.datetime.fromtimestamp(os.path.getmtime(exe)).strftime('%Y-%m-%d %H:%M')),
         '- Korpus: `%s`, Argumente: `%s`' % (corpus, ' '.join(extra)),
         '- APPDATA je Lauf frisch, kopiert aus `%s`: %s' % (a.appdata_src or '-', ', '.join(copied) or 'nichts (Werkseinstellung)'),
         '- Diagnose-Stapel: %s; Map: %s' % ('aus' if a.no_crash_stack else 'SCA_CRASH_STACK je Lauf', map_path or 'keine gefunden'),
         '- Laeufe: %d, auffaellig: %d\n' % (len(rows), sum(1 for r in rows if r['odd'])),
         '| Lauf | Exit | s | Funde | Lesefehler | mit Ausnahme | Zugang | Abgang | Diagnose-Eintraege | FastMM B |',
         '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for r in rows:
        L.append('| %s%d | %s | %.0f | %d | %d | %d | %d | %d | %s | %d |'
                 % ('**' if r['odd'] else '', r['run'], r['rc'], r['secs'], r['n'], r['read'], r['exc'],
                    r['adds'], r['drops'], '-' if r['entries'] is None else r['entries'], r['fm']))
    if exc_index:
        L.append('\n## Lesefehler mit Ausnahme (Datei / Meldung -> Laeufe)\n')
        for (loc, msg), runs in exc_index.items():
            L.append('- `%s` - %s - Laeufe %s' % (loc, msg[:300], ','.join(map(str, runs))))
    for r in rows:
        if not r['odd']:
            continue
        L.append('\n## Lauf %d\n' % r['run'])
        if r['resolved']:
            L.append('- Diagnose aufgeloest: `%s`' % r['resolved'])
        elif r['entries']:
            L.append('- Diagnose (unaufgeloest, keine Map): `%s`'
                     % os.path.join(out, 'run%02d.crashstack.log' % r['run']))
        if r['fm']:
            L.append('- FastMM-Ereignisse: `%s`' % os.path.join(out, 'run%02d.fastmm.txt' % r['run']))
        for x in r['add_ex']:
            L.append('  - + `%s`' % x[:300])
        for x in r['drop_ex']:
            L.append('  - - `%s`' % x[:300])
    rep = os.path.join(out, 'av_stress_report.md')
    with open(rep, 'w', encoding='utf-8') as f:
        f.write('\n'.join(L) + '\n')
    print('Bericht:', rep)
    return 1 if any(r['odd'] for r in rows) else 0


if __name__ == '__main__':
    sys.exit(main())
