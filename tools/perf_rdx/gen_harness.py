#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generator fuer den reDelphix-Zeitmess-Harness (FPC, ohne Delphi-Bau).

Aufruf (von run_rdxperf.sh, nicht von Hand noetig):

    python -I gen_harness.py <SCA-Wurzel> <work>/units <sarif> <sites.tsv> [maxN] [regel,regel,..]

Schritte:
  1. liest TFindingKind (uSCAConsts) -> SCA-Id = Ord+1
  2. liest FIX_ROWS (uRdxFixTable): Kind -> Plan (+ Alt)
  3. je Plan-Funktion in uRdxFixTable/uRdxFixRunner: ruft sie
     MapFix(ALines, <Zeile>, <Meldung>, TRdxX.M) -> Planer der Form
     TRdxMapPlanner (reine Code-Sicht, FPC-tauglich)
  4. schreibt planners.inc (Dispatch Regel-Id -> Planer), planner_uses.inc,
     planners.json, unmapped_rows.txt und extra_units.txt (Planer-Units, die
     build.sh nicht kopiert und run_rdxperf.sh zusaetzlich anpasst)
  5. zieht aus dem SARIF Datei<TAB>Zeile<TAB>Regel<TAB>Meldung (sites.tsv),
     streamend (Referenz-SARIFs sind > 700 MB)

Alle erzeugten Dateien landen im Arbeitsverzeichnis (<units>/..), nie im
Repo. excluded_units.txt dort (von run_rdxperf.sh gefuehrt) nimmt Planer
aus, deren Unit FPC 3.2.2 nicht uebersetzt.
"""
import json
import os
import re
import sys
import urllib.parse

PASCAL_EXT = ('.pas', '.dpr', '.dpk', '.pp', '.inc', '.lpr')


def read(p):
    with open(p, encoding='utf-8', errors='replace') as f:
        return f.read()


def finding_kinds(sca):
    """fkXxx -> 'SCAnnn' (Ord+1) aus TFindingKind in uSCAConsts."""
    consts = read(os.path.join(sca, 'SCA.Engine', 'sources', 'Common', 'uSCAConsts.pas'))
    consts = re.sub(r'//[^\n]*', '', consts)
    consts = re.sub(r'\{[^}]*\}', '', consts)
    m = re.search(r'TFindingKind\s*=\s*\((.*?)\);', consts, re.S)
    kinds = [k.strip() for k in m.group(1).split(',') if k.strip()]
    return {k: 'SCA%03d' % (i + 1) for i, k in enumerate(kinds)}


def plan_functions(table, runner):
    """Plan-Funktion -> (Klasse, Methode) des MapFix-Planers."""
    plan_map = {}
    for text in (table, runner):
        for fm in re.finditer(r'^function (\w+)\((.*?)^end;', text, re.S | re.M):
            name, fbody = fm.group(1), fm.group(2)
            mm = re.search(r'MapFix\(\s*ALines,\s*[\w.]+,\s*[\w.]+,\s*(TRdx\w+)\.(\w+)\)', fbody)
            if mm:
                plan_map.setdefault(name, (mm.group(1), mm.group(2)))
    # Plan, der nur an eine andere Plan-Funktion weiterreicht (Result := X(...))
    for text in (table, runner):
        for fm in re.finditer(r'^function (\w+)\((.*?)^end;', text, re.S | re.M):
            name, fbody = fm.group(1), fm.group(2)
            if name in plan_map:
                continue
            mm = re.search(r'Result\s*:=\s*(\w+)\(', fbody)
            if mm and mm.group(1) in plan_map:
                plan_map[name] = plan_map[mm.group(1)]
    return plan_map


def class_units(src):
    cls_unit = {}
    for fn in os.listdir(src):
        if fn.endswith('.pas'):
            for cm in re.finditer(r'^\s*(TRdx\w+)\s*=\s*class\b', read(os.path.join(src, fn)), re.M):
                cls_unit.setdefault(cm.group(1), fn[:-4])
    return cls_unit


def extract_sites(sarif, sites, max_n, only):
    """Fundstellen aus dem SARIF streamend nach sites.tsv; liefert (Anzahl, Wurzel)."""
    re_rule = re.compile(r'^\s*"ruleId":\s*"([A-Z0-9]+)"')
    re_text = re.compile(r'^\s*"text":\s*"(.*)"\s*$')
    re_uri = re.compile(r'^\s*"uri":\s*"(.*?)",?\s*$')
    re_line = re.compile(r'^\s*"startLine":\s*(\d+)')
    root = None
    rule = text = uri = None
    n = 0
    in_results = False
    with open(sarif, encoding='utf-8', errors='replace') as f, \
            open(sites, 'w', encoding='utf-8', newline='\n') as out:
        for line in f:
            if not in_results:
                if root is None and '"SRCROOT"' in line:
                    nxt = next(f)
                    um = re_uri.match(nxt) or re.search(r'"uri":\s*"(.*?)"', nxt)
                    if um:
                        root = urllib.parse.unquote(um.group(1).replace('\\/', '/'))
                        root = root[8:] if root.startswith('file:///') else root
                        root = root.replace('/', '\\').rstrip('\\')
                if re.match(r'^\s*"results":\s*\[', line):
                    in_results = True
                continue
            mm = re_rule.match(line)
            if mm:
                rule, text, uri = mm.group(1), None, None
                continue
            if rule and text is None:
                mm = re_text.match(line)
                if mm:
                    text = json.loads('"' + mm.group(1) + '"')
                    continue
            if rule and uri is None:
                mm = re_uri.match(line)
                if mm:
                    uri = json.loads('"' + mm.group(1) + '"')
                    continue
            mm = re_line.match(line)
            if mm and rule and uri:
                if only is None or rule in only:
                    if uri.startswith('file:///'):
                        path = urllib.parse.unquote(uri[8:]).replace('/', '\\')
                    else:
                        path = (root or '') + '\\' + urllib.parse.unquote(uri).replace('/', '\\')
                    if path.lower().endswith(PASCAL_EXT):
                        out.write('%s\t%s\t%s\t%s\n' % (path, mm.group(1), rule,
                                  (text or '').replace('\t', ' ').replace('\n', ' ')))
                        n += 1
                        if max_n and n >= max_n:
                            break
                rule = None
    return n, root


def write_planners_inc(path, entries, kind_id):
    lines = ['// GENERIERT von gen_harness.py - nicht von Hand aendern.',
             'function PlannerCount: Integer;', 'begin', '  Result := %d;' % len(entries), 'end;', '',
             'procedure PlannerAt(AIdx: Integer; out ARule, AName: string; out AFn: TRdxMapPlanner);',
             'begin', '  case AIdx of']
    for i, (rid, _kind, _p, cls, meth, alt) in enumerate(entries):
        lines.append("    %d: begin ARule := '%s'; AName := '%s.%s%s'; AFn := @%s.%s; end;"
                     % (i, rid, cls, meth, ' (alt)' if alt else '', cls, meth))
    lines += ['  else', "    begin ARule := ''; AName := ''; AFn := nil; end;", '  end;', 'end;', '']
    # Regel-Id -> Kind-Name ohne 'fk' (Marker-Text fuer LineMarker/FileMarker)
    lines += ['function RuleKindName(const ARule: string): string;', 'begin', "  Result := '';"]
    for k, rid in kind_id.items():
        lines.append("  if ARule = '%s' then Exit('%s');" % (rid, k[2:]))
    lines += ['end;']
    with open(path, 'w', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    sca, units, sarif, sites = sys.argv[1:5]
    max_n = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] else 0
    only = set(sys.argv[6].split(',')) if len(sys.argv) > 6 and sys.argv[6] else None
    work = os.path.join(units, '..')
    src = os.path.join(sca, 'reDelphix', 'source')

    kind_id = finding_kinds(sca)
    table = read(os.path.join(src, 'uRdxFixTable.pas'))
    runner = read(os.path.join(src, 'uRdxFixRunner.pas'))
    rows = re.findall(r'\(Kind:\s*(fk\w+);\s*Plan:\s*(\w+);.*?Alt:\s*(\w+)\)', table, re.S)
    plan_map = plan_functions(table, runner)
    cls_unit = class_units(src)

    excl_path = os.path.join(work, 'excluded_units.txt')
    excluded = set()
    if os.path.exists(excl_path):
        with open(excl_path) as f:
            excluded = {line.strip() for line in f if line.strip()}
    entries = []   # (ruleId, kind, plan, cls, meth, alt)
    for kind, plan, alt in rows:
        rid = kind_id.get(kind)
        for p, is_alt in ((plan, False), (alt, True)):
            if p == 'nil' or p not in plan_map:
                continue
            cls, meth = plan_map[p]
            if cls_unit.get(cls) in excluded:
                continue
            entries.append((rid, kind, p, cls, meth, is_alt))

    needed = sorted({cls_unit[c] for _, _, _, c, _, _ in entries if c in cls_unit})
    have = {f[:-4] for f in os.listdir(units) if f.endswith('.pas')}
    extra = [u for u in needed if u not in have]
    with open(os.path.join(work, 'extra_units.txt'), 'w', newline='\n') as f:
        f.write('\n'.join(extra) + '\n')

    unmapped = sorted({kind_id.get(k, k) + ' ' + p for k, p, _ in rows if p not in plan_map})
    with open(os.path.join(work, 'unmapped_rows.txt'), 'w') as f:
        f.write('Tabellenzeilen ohne MapFix-Form (AST/Places noetig - nur im Delphi-Harness messbar):\n')
        f.write('\n'.join(unmapped) + '\n')

    with open(os.path.join(work, 'planners.json'), 'w') as f:
        json.dump({'entries': entries, 'units': needed, 'extra': extra}, f, indent=1)
    print('Tabellenzeilen %d, MapFix-Planer %d, Units %d (zusaetzlich %d), ohne MapFix %d'
          % (len(rows), len(entries), len(needed), len(extra), len(unmapped)))

    n, root = extract_sites(sarif, sites, max_n, only)
    print('Fundstellen: %d (Wurzel %s) -> %s' % (n, root, sites))

    write_planners_inc(os.path.join(work, 'planners.inc'), entries, kind_id)
    with open(os.path.join(work, 'planner_uses.inc'), 'w', newline='\n') as f:
        f.write('  ' + ',\n  '.join(needed) + ',\n' if needed else '')
    return 0


if __name__ == '__main__':
    sys.exit(main())
