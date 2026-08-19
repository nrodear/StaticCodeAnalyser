#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generiert SCA.Engine/sources/Common/uRuleCatalogData.inc aus rules/sca-rules.json.

HINTERGRUND (2026-07-26): uFixHint hat fuer 175 der 194 Kinds fest einkompilierte
Hand-Branches; die uebrigen 19 (SCA167-SCA184 + SCA194, u.a. SCA176
CognitiveComplexity) beziehen Before/After AUSSCHLIESSLICH ueber
TRuleCatalog.GetRule -> rules/sca-rules.json. Findet der Katalog die Datei zur
Laufzeit nicht, greift LoadFallback/MakeFallbackMeta - und das liess
BadExample/GoodExample LEER. Im IDE-Plugin passiert genau das: die BPL liegt im
Embarcadero-BPL-Verzeichnis (typisch C:\\Users\\Public\\...), das Repo auf einem
anderen Laufwerk - der 8-Ebenen-Aufwaertswalk kann die JSON nie erreichen.
Folge: die 19 Regeln zeigten im Plugin gar keinen Vorher/Nachher-Hinweis.

Dieser Generator legt die Katalog-Texte als Pascal-Konstanten ab, sodass der
Fallback INHALTLICH VOLLSTAENDIG ist - ohne Laufzeit-Datei. Die JSON bleibt die
einzige Quelle der Wahrheit; der .inc ist generiertes Artefakt (wie docs/rules).

Aufruf:
    python tools/gen-rules-inc.py            # schreibt den .inc
    python tools/gen-rules-inc.py --check    # nur pruefen (CI-Gate), Exit 1 bei Drift
"""
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'rules', 'sca-rules.json')
DST = os.path.join(ROOT, 'SCA.Engine', 'sources', 'Common', 'uRuleCatalogData.inc')
# Zweite Tabelle: einkompilierte Sprach-Overlays. Im IDE-Plugin der
# Normalfall - die BPL findet die losen rules\-JSONs meist nicht
# (s. Kopf von uRuleCatalogData.inc); ohne diese Tabelle waere das
# Overlay-Feature dort schlicht abwesend.
DST_OV = os.path.join(ROOT, 'SCA.Engine', 'sources', 'Common', 'uRuleCatalogOverlay.inc')
OVERLAY_LANGS = ('de', 'fr')
Q = "'"


def pas_parts(s: str) -> list:
    """Python-String -> Delphi-String-Literal.

    Regeln (die Fallstricke, die hier wirklich weh tun):
      * einfache Anfuehrungszeichen MUESSEN verdoppelt werden - sonst endet
        das Literal mitten im Text und der Compiler sieht Bezeichner.
      * Zeilenumbrueche werden zu #13#10 ausserhalb der Quotes.
      * Non-ASCII als #$XX, damit die .inc reines ASCII bleibt.
      * leerer String -> ''
    """
    if s is None:
        s = ''
    s = s.replace('\r\n', '\n').replace('\r', '\n')
    parts = []      # fertige Teilstuecke (Literale und #-Codes)
    buf = []        # aktueller Text im Literal

    def flush():
        if buf:
            parts.append(Q + ''.join(buf) + Q)
            buf.clear()

    for ch in s:
        if ch == '\n':
            flush()
            parts.append('#13#10')
        elif ch == Q:
            buf.append(Q + Q)          # verdoppeln
        elif ord(ch) < 32 or ord(ch) > 126:
            flush()
            parts.append('#$%02X' % ord(ch))
        else:
            buf.append(ch)
    flush()
    if not parts:
        return [Q + Q]
    return parts


def wrap(parts: list, indent: str) -> str:
    """Teile zu einem Pascal-Ausdruck fuegen und dabei umbrechen.

    WICHTIG: es wird ueber die TEILE-LISTE umgebrochen, niemals ueber den
    fertigen Text. Ein frueherer Versuch splittete den zusammengesetzten
    Ausdruck an ' + ' - das zerriss jedes Code-Beispiel, das selbst ein
    ' + ' enthaelt (z.B. 'Result := A + B;'), mitten im String-Literal
    (E2052 'Nicht abgeschlossener String').
    """
    out, line = [], ''
    for tok in parts:
        cand = tok if not line else line + ' + ' + tok
        if len(indent) + len(cand) > 100 and line:
            out.append(line + ' +')
            line = tok
        else:
            line = cand
    out.append(line)
    return ('\n' + indent).join(out)


def build() -> str:
    with io.open(SRC, encoding='utf-8-sig') as f:
        rules = json.load(f)['rules']

    L = []
    L.append('// ==========================================================================')
    L.append('// GENERIERT von tools/gen-rules-inc.py - NICHT VON HAND EDITIEREN.')
    L.append('// Quelle: rules/sca-rules.json  (dort aendern, dann Generator laufen lassen)')
    L.append('//')
    L.append('// Zweck: Katalog-Texte einkompiliert, damit TRuleCatalog auch OHNE gefundene')
    L.append('// rules/sca-rules.json vollstaendige Metadaten liefert. Ohne das zeigten die')
    L.append('// 19 Kinds ohne uFixHint-Hand-Branch (SCA167-SCA184, SCA194) im IDE-Plugin')
    L.append('// GAR KEINEN Vorher/Nachher-Hinweis: die Plugin-BPL liegt im Embarcadero-')
    L.append('// BPL-Verzeichnis, das Repo auf einem anderen Laufwerk - der Aufwaertswalk')
    L.append('// der Pfadsuche erreicht die JSON dort nie.')
    L.append('// ==========================================================================')
    L.append('')
    L.append('const')
    L.append('  // Index == Ord(TFindingKind) - die JSON ist positionsgleich zum Enum')
    L.append('  // (Test RuleIDMatchesOrdinal sichert das ab).')
    L.append('  RULE_CATALOG_DATA : array[0..%d] of TRuleFallbackData = (' % (len(rules) - 1))

    for i, r in enumerate(rules):
        ex = r.get('examples') or {}
        fields = [
            ('RuleID',    r.get('id', '')),
            ('Name',      r.get('name', '')),
            ('ShortDesc', r.get('shortDescription', '')),
            ('BadEx',     ex.get('bad', '') or ''),
            ('GoodEx',    ex.get('good', '') or ''),
        ]
        L.append('    // %s' % r.get('id', '?'))
        L.append('    (')
        for n, (fname, val) in enumerate(fields):
            lit = wrap(pas_parts(val), ' ' * 8)
            sep = ';' if n < len(fields) - 1 else ''
            L.append('      %-9s: %s%s' % (fname, lit, sep))
        L.append('    )%s' % (',' if i < len(rules) - 1 else ''))

    L.append('  );')
    L.append('')
    return '\n'.join(L) + '\n'


def build_overlay() -> str:
    """Baut uRuleCatalogOverlay.inc aus rules/sca-rules.<lang>.json.

    Reihenfolge und Index kommen aus dem KANONISCHEN Katalog (Index ==
    Ord(TFindingKind)); die Overlays liefern nur die Texte. Eine Regel,
    die ein Overlay nicht fuehrt, bekommt leere Felder - der Delphi-Leser
    behandelt leer als englischen Rueckfall. Die englische Tabelle
    RULE_CATALOG_DATA wird hier NIE angefasst: sie speist SARIF/Sonar,
    und ein uebersetzter Fallback wuerde die Dedup-Fingerprints von
    GitHub Code Scanning kippen.
    """
    src = os.path.join(ROOT, 'rules', 'sca-rules.json')
    with io.open(src, encoding='utf-8-sig') as f:
        ids = [r.get('id', '') for r in json.load(f)['rules']]

    L = []
    L.append('// ==========================================================================')
    L.append('// GENERIERT von tools/gen-rules-inc.py - NICHT VON HAND EDITIEREN.')
    L.append('// Quelle: rules/sca-rules.<lang>.json (dort aendern, Generator laufen lassen)')
    L.append('//')
    L.append('// Einkompilierte Sprach-Overlays (Name + ShortDescription je Regel).')
    L.append('// Rangfolge im Leser (TRuleCatalog.EnsureOverlay): lose Datei schlaegt')
    L.append('// diese Tabelle; die Tabelle schlaegt Englisch. FullDescription wird')
    L.append('// bewusst nicht eingebettet - die Overlays uebersetzen sie nicht.')
    L.append('// ==========================================================================')
    L.append('')
    L.append('const')
    for lang in OVERLAY_LANGS:
        ov_path = os.path.join(ROOT, 'rules', 'sca-rules.%s.json' % lang)
        with io.open(ov_path, encoding='utf-8-sig') as f:
            ov = json.load(f).get('rules', {})
        L.append('  // Index == Ord(TFindingKind), Drift-Guard im Leser wie bei')
        L.append('  // RULE_CATALOG_DATA (RuleID muss zur Position passen).')
        L.append('  RULE_OVERLAY_%s : array[0..%d] of TRuleOverlayData = ('
                 % (lang.upper(), len(ids) - 1))
        for i, rid in enumerate(ids):
            e = ov.get(rid, {})
            fields = [
                ('RuleID',    rid),
                ('Name',      e.get('name', '')),
                ('ShortDesc', e.get('shortDescription', '')),
            ]
            L.append('    // %s' % (rid or '?'))
            L.append('    (')
            for n, (fname, val) in enumerate(fields):
                lit = wrap(pas_parts(val), ' ' * 8)
                sep = ';' if n < len(fields) - 1 else ''
                L.append('      %-9s: %s%s' % (fname, lit, sep))
            L.append('    )%s' % (',' if i < len(ids) - 1 else ''))
        L.append('  );')
        L.append('')
    return '\n'.join(L) + '\n'


def main() -> int:
    check = '--check' in sys.argv
    rc = 0
    for dst, text in ((DST, build()), (DST_OV, build_overlay())):
        old = ''
        if os.path.exists(dst):
            with io.open(dst, encoding='utf-8', newline='') as f:
                old = f.read()
        if check:
            if old.replace('\r\n', '\n') == text:
                print('OK: %s ist aktuell (%d Regel-Eintraege).'
                      % (os.path.basename(dst), text.count('    // SCA')))
            else:
                print('DRIFT: %s weicht von den rules/-Quellen ab '
                      '- "python tools/gen-rules-inc.py" ausfuehren.'
                      % os.path.basename(dst))
                rc = 1
            continue
        with io.open(dst, 'w', encoding='utf-8', newline='\r\n') as f:
            f.write(text)
        print('Generated %s (%d Regel-Eintraege, %d Zeichen).'
              % (os.path.basename(dst), text.count('    // SCA'), len(text)))
    return rc


if __name__ == '__main__':
    sys.exit(main())
