#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Loest Adressen gegen eine Delphi-Detailed-Map (DCC_MapFile=3) auf.

WOZU (AV-Jagd 2026-10-25): der Diagnose-Stapel der Standalone-Exe
(Umgebungsvariable SCA_CRASH_STACK, uCrashDiag) schreibt je Rahmen
'Modul+$RVA', SCA006-Meldetexte tragen '[modulrelativ $RVA]'. Beides ist
erst mit der Map des GLEICHEN Baus etwas wert: Unit, Routine, Zeile.

EINGABEN
  RVA (modulrelativ)    1A2B3C | 0x1A2B3C | $1A2B3C
                        StaticCodeAnalyser.d12.exe+$1A2B3C
  absolute Adresse      --abs 00007FF6A1B2C3D4 --base 00007FF6A0000000
                        (Basis = 'Modul  : ... Basis $...' im Kopf der
                        Diagnosedatei; ASLR verschiebt sie je Lauf)
  ganze Diagnosedatei   --log datei.crashstack.log
                        haengt an jede Zeile mit '<map-modul>+$RVA' bzw.
                        '[modulrelativ $RVA]' die Aufloesung an; fremde
                        Module (ntdll, kernelbase) bleiben unveraendert

MAP-FORMAT (das Delphi schreibt, Win32 und Win64)
   Start         Length     Name                   Class
   0001:00401000 0025B2F8H .text                   CODE
  Detailed map of segments
   0001:00000000 0000F1D8 C=CODE     S=.text    G=(none)   M=System   ACBP=A9
    Address             Publics by Value
   0001:00000000       System.Ord
  Line numbers for System.SysUtils(System.SysUtils.pas) segment .text
    1234 0001:0000AA20  1235 0001:0000AA2B
  Die Startspalte der Segmenttabelle ist eine VA zur BEVORZUGTEN Basis
  (Delphi-Standard $400000, beide Plattformen). Abweichend: --image-base
  oder --exe (liest ImageBase aus dem PE-Kopf der Exe).
  Zeilennummern stehen nur fuer Units mit Debug-Info ($D+ bzw.
  DCC_DebugInformation >= 1); ohne sie bleibt es bei Unit + Routine.

AUFRUF
  python -I tools/map_resolve.py "Output/Win64 Release/StaticCodeAnalyser.d12.map" 1A2B3C 1A2C00
  python -I tools/map_resolve.py X.map --log run03.crashstack.log
  python -I tools/map_resolve.py --selftest

EXIT  0 ok | 1 Selbsttest rot / nichts aufloesbar | 2 Aufruffehler
"""
import argparse
import bisect
import os
import re
import struct
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

DEFAULT_IMAGE_BASE = 0x400000

_SEG = re.compile(r'^\s*([0-9A-Fa-f]{4}):([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)H\s+(\S+)\s+(\S+)\s*$')
_DETAIL = re.compile(r'^\s*([0-9A-Fa-f]{4}):([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)\s+C=\S+\s+S=\S+\s+G=\S+\s+M=(\S+)')
_PUBLIC = re.compile(r'^\s*([0-9A-Fa-f]{4}):([0-9A-Fa-f]+)\s+(\S.*?)\s*$')
_LINEHDR = re.compile(r'^Line numbers for (.+?)\((.*?)\)\s+segment\s+(\S+)')
_LINEPAIR = re.compile(r'(\d+)\s+([0-9A-Fa-f]{4}):([0-9A-Fa-f]+)')


class DelphiMap(object):
    """Segmente, Unit-Bereiche, Routinen und Zeilen einer Detailed-Map."""

    def __init__(self, text, image_base=DEFAULT_IMAGE_BASE):
        self.image_base = image_base
        self.segments = {}     # seg -> (start_va, length, name, cls)
        self.units = {}        # seg -> sortierte [(off, len, unit)]
        self.publics = {}      # seg -> sortierte [(off, name)]
        self.lines = {}        # seg -> sortierte [(off, line, unit, file)]
        self._parse(text)
        self._pub_keys = {s: [p[0] for p in v] for s, v in self.publics.items()}
        self._unit_keys = {s: [u[0] for u in v] for s, v in self.units.items()}
        self._line_keys = {s: [l[0] for l in v] for s, v in self.lines.items()}

    def _parse(self, text):
        mode = 'segments'
        cur_line_unit = None
        pubs = {}
        for raw in text.splitlines():
            line = raw.rstrip()
            s = line.strip()
            if not s:
                continue
            if s.startswith('Detailed map of segments'):
                mode = 'detail'
                continue
            if 'Publics by Name' in s:
                mode = 'pubname'
                continue
            if 'Publics by Value' in s:
                mode = 'pubvalue'
                continue
            m = _LINEHDR.match(s)
            if m:
                mode = 'lines'
                cur_line_unit = (m.group(1), m.group(2))
                continue
            if s.startswith('Bound resource files') or s.startswith('Program entry point'):
                mode = 'other'
                continue
            if mode == 'segments':
                m = _SEG.match(line)
                if m:
                    seg = int(m.group(1), 16)
                    self.segments[seg] = (int(m.group(2), 16), int(m.group(3), 16),
                                          m.group(4), m.group(5))
            elif mode == 'detail':
                m = _DETAIL.match(line)
                if m:
                    seg = int(m.group(1), 16)
                    self.units.setdefault(seg, []).append(
                        (int(m.group(2), 16), int(m.group(3), 16), m.group(4)))
            elif mode in ('pubname', 'pubvalue'):
                m = _PUBLIC.match(line)
                if m:
                    seg = int(m.group(1), 16)
                    pubs[(seg, int(m.group(2), 16), m.group(3))] = True
            elif mode == 'lines' and cur_line_unit:
                for m in _LINEPAIR.finditer(line):
                    seg = int(m.group(2), 16)
                    self.lines.setdefault(seg, []).append(
                        (int(m.group(3), 16), int(m.group(1)), cur_line_unit[0], cur_line_unit[1]))
        for (seg, off, name) in pubs:
            self.publics.setdefault(seg, []).append((off, name))
        for d in (self.units, self.publics, self.lines):
            for seg in d:
                d[seg].sort()

    def segment_of_rva(self, rva):
        """(seg, offset) zur RVA, None wenn in keinem Segment mit VA-Start."""
        va = self.image_base + rva
        for seg, (start, length, _name, _cls) in self.segments.items():
            # .tls/.bss-artige Segmente mit Start 0 sind keine VA-Bereiche
            if start and start <= va < start + length:
                return seg, va - start
        return None

    def resolve_rva(self, rva):
        """Dict mit unit, routine, delta, line, file - oder None."""
        hit = self.segment_of_rva(rva)
        if hit is None:
            return None
        seg, off = hit
        res = {'seg': seg, 'offset': off, 'unit': None, 'routine': None,
               'delta': None, 'line': None, 'file': None}
        ukeys = self._unit_keys.get(seg, [])
        i = bisect.bisect_right(ukeys, off) - 1
        if i >= 0:
            uoff, ulen, uname = self.units[seg][i]
            if off < uoff + ulen:
                res['unit'] = uname
        pkeys = self._pub_keys.get(seg, [])
        i = bisect.bisect_right(pkeys, off) - 1
        if i >= 0:
            poff, pname = self.publics[seg][i]
            res['routine'] = pname
            res['delta'] = off - poff
        lkeys = self._line_keys.get(seg, [])
        i = bisect.bisect_right(lkeys, off) - 1
        # die naechstkleinere Zeile muss zur selben Unit gehoeren - sonst
        # laege die Adresse in einer Unit ohne Zeileninfo und man bekaeme
        # die letzte Zeile der Vorgaenger-Unit
        while i >= 0:
            loff, lno, lunit, lfile = self.lines[seg][i]
            if res['unit'] is None or lunit == res['unit']:
                res['line'] = lno
                res['file'] = lfile
                break
            if res['unit'] is not None:
                break
            i -= 1
        return res


def format_hit(res):
    if res is None:
        return '<ausserhalb aller Segmente der Map>'
    parts = []
    if res['routine']:
        parts.append('%s+$%X' % (res['routine'], res['delta']))
    elif res['unit']:
        parts.append(res['unit'])
    if res['unit'] and res['routine'] and not res['routine'].startswith(res['unit'] + '.'):
        parts.append('[%s]' % res['unit'])
    if res['line'] is not None:
        parts.append('(%s:%d)' % (res['file'] or res['unit'], res['line']))
    return ' '.join(parts) if parts else '<kein Symbol>'


def parse_number(s):
    s = s.strip()
    m = re.search(r'\+\$([0-9A-Fa-f]+)$', s)
    if m:
        return int(m.group(1), 16)
    s = s.lstrip('$')
    if s.lower().startswith('0x'):
        s = s[2:]
    return int(s, 16)


def pe_image_base(path):
    with open(path, 'rb') as f:
        head = f.read(4096)
    pe = struct.unpack_from('<I', head, 0x3C)[0]
    if head[pe:pe + 4] != b'PE\0\0':
        raise ValueError('kein PE-Kopf: %s' % path)
    opt = pe + 24
    magic = struct.unpack_from('<H', head, opt)[0]
    if magic == 0x20B:
        return struct.unpack_from('<Q', head, opt + 24)[0]
    return struct.unpack_from('<I', head, opt + 28)[0]


_LOG_FRAME = re.compile(r'([\w.\-]+\.(?:exe|dll|bpl))\+\$([0-9A-Fa-f]+)', re.I)
_LOG_MODREL = re.compile(r'\[modulrelativ \$([0-9A-Fa-f]+)\]')


def annotate_log(dmap, text, module):
    """Haengt an jede passende Zeile die Aufloesung an. module=None: jedes .exe."""
    out = []
    hits = 0
    for line in text.splitlines():
        add = []
        for m in _LOG_FRAME.finditer(line):
            mod = m.group(1)
            if (module and mod.lower() != module.lower()) or \
                    (not module and not mod.lower().endswith('.exe')):
                continue
            add.append(format_hit(dmap.resolve_rva(int(m.group(2), 16))))
        for m in _LOG_MODREL.finditer(line):
            add.append(format_hit(dmap.resolve_rva(int(m.group(1), 16))))
        if add:
            hits += 1
            line = line + '   => ' + ' | '.join(add)
        out.append(line)
    return '\n'.join(out) + '\n', hits


# --------------------------------------------------------------- Selbsttest
# Kuenstliche, aber formatgetreue Map (Win64-Schreibweise, 16-stellige
# Segmentstarts). .text beginnt bei VA $401000 = RVA $1000.
_SELFTEST_MAP = """
 Start                 Length     Name                   Class
 0001:0000000000401000 00003000H .text                   CODE
 0002:0000000000404000 00000200H .data                   DATA
 0003:0000000000000000 00000010H .tls                    TLS


Detailed map of segments

 0001:00000000 00001000 C=CODE     S=.text    G=(none)   M=System   ACBP=A9
 0001:00001000 00000800 C=CODE     S=.text    G=(none)   M=uDuplicateBlock ACBP=A9
 0001:00001800 00000800 C=CODE     S=.text    G=(none)   M=uNoLines ACBP=A9


  Address             Publics by Name

 0001:00000100       System.@GetMem
 0001:00001040       uDuplicateBlock.TDuplicateBlockDetector.Run


  Address             Publics by Value

 0001:00000100       System.@GetMem
 0001:00000400       System.DynArraySetLength
 0001:00001040       uDuplicateBlock.TDuplicateBlockDetector.Run
 0001:00001200       uDuplicateBlock.HashWindow
 0001:00001810       uNoLines.Helper


Line numbers for System(System.pas) segment .text

   100 0001:00000100   101 0001:00000108   400 0001:00000400   405 0001:00000420

Line numbers for uDuplicateBlock(uDuplicateBlock.pas) segment .text

    50 0001:00001040    51 0001:00001050    90 0001:00001200    95 0001:00001230

Bound resource files

Program entry point at 0001:00002F00
"""


def selftest():
    dm = DelphiMap(_SELFTEST_MAP)
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    check(dm.segments.get(1, (0,))[0] == 0x401000, 'Segment .text nicht gelesen')
    # RVA $2238 = VA $402238 = .text+$1238 -> HashWindow+$38, Zeile 95
    r = dm.resolve_rva(0x2238)
    check(r and r['routine'] == 'uDuplicateBlock.HashWindow', 'Routine falsch: %r' % (r,))
    check(r and r['delta'] == 0x38, 'Abstand falsch: %r' % (r,))
    check(r and r['line'] == 95 and r['file'] == 'uDuplicateBlock.pas', 'Zeile falsch: %r' % (r,))
    check(r and r['unit'] == 'uDuplicateBlock', 'Unit falsch: %r' % (r,))
    # RVA $1410 = .text+$410 -> DynArraySetLength+$10, Zeile 400 (System)
    r = dm.resolve_rva(0x1410)
    check(r and r['routine'] == 'System.DynArraySetLength' and r['line'] == 400,
          'System-Aufloesung falsch: %r' % (r,))
    # Unit ohne Zeileninfo: KEINE Zeile der Vorgaenger-Unit uebernehmen
    r = dm.resolve_rva(0x2820)
    check(r and r['routine'] == 'uNoLines.Helper' and r['line'] is None,
          'Zeile aus fremder Unit uebernommen: %r' % (r,))
    # ausserhalb jedes Segments
    check(dm.resolve_rva(0x900000) is None, 'Adresse ausserhalb nicht erkannt')
    # Eingabeformen
    check(parse_number('StaticCodeAnalyser.d12.exe+$2238') == 0x2238, 'Modul+$RVA nicht gelesen')
    check(parse_number('$2238') == 0x2238 and parse_number('0x2238') == 0x2238
          and parse_number('2238') == 0x2238, 'Zahlformen nicht gelesen')
    # Diagnosedatei: nur das eigene Modul aufloesen, ntdll unveraendert
    log = ('  #00 $00007FF6A0402238 StaticCodeAnalyser.d12.exe+$2238\n'
           '  #01 $00007FFB10001234 ntdll.dll+$1234\n'
           'Fehler : EAccessViolation: x [NT-Status $C0000005] [modulrelativ $1410]\n')
    txt, hits = annotate_log(dm, log, 'StaticCodeAnalyser.d12.exe')
    lines = txt.splitlines()
    check(hits == 2, 'falsche Trefferzahl im Log: %d' % hits)
    check('HashWindow+$38' in lines[0] and '(uDuplicateBlock.pas:95)' in lines[0],
          'Logzeile 0 nicht aufgeloest: ' + lines[0])
    check('=>' not in lines[1], 'fremdes Modul aufgeloest: ' + lines[1])
    check('DynArraySetLength+$10' in lines[2], 'modulrelativ nicht aufgeloest: ' + lines[2])
    if fails:
        for f in fails:
            print('ROT:', f)
        return 1
    print('Selbsttest gruen (%d Pruefungen)' % 14)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('map', nargs='?', help='Delphi-Detailed-Map (.map)')
    ap.add_argument('addr', nargs='*', help='RVAs (hex, $hex, 0xhex, Modul+$hex)')
    ap.add_argument('--abs', action='append', default=[], help='absolute Adresse (hex), braucht --base')
    ap.add_argument('--base', default='', help='Ladebasis des Moduls in DIESEM Lauf (hex, Kopf der Diagnosedatei)')
    ap.add_argument('--image-base', default='', help='bevorzugte ImageBase der Map (hex, Standard 400000)')
    ap.add_argument('--exe', default='', help='Exe des Baus: ImageBase aus dem PE-Kopf statt --image-base')
    ap.add_argument('--log', default='', help='Diagnosedatei (SCA_CRASH_STACK) oder Log mit [modulrelativ $..] annotieren')
    ap.add_argument('--module', default='', help='Modulname fuer --log (Standard: <Map-Name>.exe)')
    ap.add_argument('--out', default='', help='--log: Ergebnis in diese Datei statt auf stdout')
    ap.add_argument('--selftest', action='store_true', help='Selbsttest gegen eine eingebaute Mini-Map')
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.map:
        ap.error('Map-Datei fehlt')
    base = DEFAULT_IMAGE_BASE
    if a.exe:
        base = pe_image_base(a.exe)
    elif a.image_base:
        base = parse_number(a.image_base)
    with open(a.map, encoding='utf-8', errors='replace') as f:
        dm = DelphiMap(f.read(), base)
    if not dm.segments:
        print('keine Segmenttabelle in %s - ist das eine Delphi-Map?' % a.map)
        return 2
    rc = 0
    if a.log:
        module = a.module or (os.path.splitext(os.path.basename(a.map))[0] + '.exe')
        with open(a.log, encoding='utf-8-sig', errors='replace') as f:
            txt, hits = annotate_log(dm, f.read(), module)
        if a.out:
            with open(a.out, 'w', encoding='utf-8') as f:
                f.write(txt)
            print('%d Zeilen aufgeloest -> %s' % (hits, a.out))
        else:
            sys.stdout.write(txt)
        if hits == 0:
            rc = 1
    for s in a.addr:
        rva = parse_number(s)
        print('$%X  %s' % (rva, format_hit(dm.resolve_rva(rva))))
    if a.abs:
        if not a.base:
            ap.error('--abs braucht --base')
        load = parse_number(a.base)
        for s in a.abs:
            ab = parse_number(s)
            if ab < load:
                print('$%X  <unter der Ladebasis $%X>' % (ab, load))
                continue
            rva = ab - load
            print('$%X (RVA $%X)  %s' % (ab, rva, format_hit(dm.resolve_rva(rva))))
    return rc


if __name__ == '__main__':
    sys.exit(main())
