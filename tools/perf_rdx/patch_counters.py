#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Patcht NUR die adaptierten Kopien im units-Verzeichnis (nie das Repo).

Zaehler fuer TRdxCodeMap-Aufbau, Include-FileExists, Verzeichnis-Scans
(FindFirst) und LoadFileSmart, die rdxperf.lpr je Fund ausgibt.
Idempotent (Marke 'RDXPERF'). Aufruf (von run_rdxperf.sh):

    python -I patch_counters.py <work>/units
"""
import os
import re
import sys


def rw(units, name, fn):
    p = os.path.join(units, name)
    with open(p, encoding='utf-8', errors='surrogateescape') as f:
        s = f.read()
    if 'RDXPERF' in s:
        return
    s2 = fn(s)
    assert s2 != s, name
    with open(p, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(s2)


def codemap(s):
    i = s.index('\nimplementation')
    decl = ('\n{ RDXPERF-Zaehler }\nvar\n  GRdxMapBuilds, GRdxMapLines, GRdxFileExists,'
            ' GRdxDirScans : Int64;\nfunction RdxPerfFileExists(const S: string): Boolean;\n')
    s = s[:i] + decl + s[i:]
    # Konstruktor zaehlen
    m = re.search(r'constructor TRdxCodeMap\.Create\(ALines: TStrings\);.*?inherited Create;', s, re.S)
    s = s[:m.end()] + ' Inc(GRdxMapBuilds); Inc(GRdxMapLines, ALines.Count);' + s[m.end():]
    j = s.rindex('end.')
    body = ('function RdxPerfFileExists(const S: string): Boolean;\nbegin\n'
            '  Inc(GRdxFileExists);\n  Result := SysUtils.FileExists(S);\nend;\n\n')
    return s[:j] + body + s[j:]


def blocks(s):
    # nur im Implementationsteil, nur echte Aufrufe (keine Kommentare)
    i = s.index('\nimplementation')
    head, tail = s[:i], s[i:]
    tail = re.sub(r'(?<![\w.])FileExists\(', 'RdxPerfFileExists(', tail)
    return head + '{ RDXPERF }' + tail


def magic(s):
    return s.replace('if FindFirst(', 'Inc(GRdxDirScans); if FindFirst(', 1) + '{ RDXPERF }'


def ftc(s):
    i = s.index('\nimplementation')
    s = s[:i] + '\n{ RDXPERF }\nvar GRdxFileLoads : Int64;\n' + s[i:]
    k = s.index('function LoadFileSmart', s.index('\nimplementation'))
    b = re.compile(r'^begin\b', re.M).search(s, k)
    return s[:b.end()] + ' Inc(GRdxFileLoads);' + s[b.end():]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    units = sys.argv[1]
    rw(units, 'uRdxCodeMap.pas', codemap)
    rw(units, 'uRdxBlocks.pas', blocks)
    rw(units, 'uRdxMagicFixes.pas', magic)
    rw(units, 'uFileTextCache.pas', ftc)
    print('Zaehler gepatcht in', units)
    return 0


if __name__ == '__main__':
    sys.exit(main())
