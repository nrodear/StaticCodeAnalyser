#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_po_inc.py - erzeugt SCA.Engine\\sources\\Common\\uLocalizationPo.inc aus i18n\\*.po

i18n-Scharfschaltung 2026-07-26, Teil 2b (Deployment ohne lose Dateien).

WARUM DIESES TOOL (statt {$R ...rc} / RCDATA):
  Die Repo-Praxis fuer Ressourcen (branding\\sca_branding.rc) verlangt einen
  <RcCompile>-Eintrag in JEDER konsumierenden .dproj plus ein {$R '...res'} im
  dpk - und der Kommentar in StaticCodeAnalyser.IDE.d12.dpk dokumentiert, dass
  BRCC32 hier 16-bit-Erbe mitschleppt (E2161, 'Allocate failed'). uLocalization
  wird von CLI, Form, IDE-Plugin und TestProject konsumiert; der RCDATA-Weg
  haette also 4+ dproj-Aenderungen erzwungen (Auflage 4) und waere ohne Build
  nicht verifizierbar gewesen (Auflage 5).
  Ein $INCLUDE braucht dagegen NULL Projektdatei-Aenderungen: {$I ...} wird
  relativ zur einbindenden Unit aufgeloest und funktioniert in .dpr wie .dpk
  identisch. Die .po bleibt Single Source of Truth im Repo; die .inc ist ein
  reines, wortgetreues Transkript (Zeile fuer Zeile diffbar gegen die .po).

AUFRUF (Git-Bash oder PowerShell, aus dem Repo-Root):
  python tools/gen_po_inc.py

NACH JEDER AENDERUNG AN i18n\\*.po ERNEUT AUSFUEHREN.
Danach in der IDE: Clean + Build (die IDE trackt .inc-Abhaengigkeiten nicht
zuverlaessig -> sonst stiller Stale-Build).
"""

import os
import sys
import glob
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PO_DIR = os.path.join(REPO, "i18n")
OUT = os.path.join(REPO, "SCA.Engine", "sources", "Common", "uLocalizationPo.inc")

# Sprachkuerzel muessen als Pascal-Bezeichner-Suffix taugen.
LANG_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")


def pascal_literal(line):
    """Eine Quellzeile -> ASCII-only Pascal-String-Ausdruck.

    Non-ASCII wird als #$XXXX kodiert (Repo-Stil, siehe altes GDeMap), damit
    die .inc unabhaengig von BOM/Codepage/Editor-Einstellungen korrekt
    kompiliert. Ergebnis ist immer ein gueltiger String-Ausdruck.
    """
    if line == "":
        return "''"
    parts = []
    buf = []
    for ch in line:
        o = ord(ch)
        if 32 <= o <= 126:
            if ch == "'":
                buf.append("''")
            else:
                buf.append(ch)
        else:
            if buf:
                parts.append("'" + "".join(buf) + "'")
                buf = []
            parts.append("#$%04X" % o)
    if buf:
        parts.append("'" + "".join(buf) + "'")
    return "".join(parts)


def read_po_lines(path):
    with open(path, "rb") as f:
        data = f.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    text = data.decode("utf-8")  # bewusst hart: kaputtes UTF-8 = Build-Stopper
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    return lines, len(data)


def scan_duplicates(lines, lang):
    """Warnt vor doppelten msgid - der Loader nimmt den ERSTEN Treffer."""
    seen = {}
    dups = []
    for ln in lines:
        s = ln.strip()
        if s.startswith("msgid ") and not s.startswith("msgid_plural"):
            key = s[6:].strip()
            if key in ("", '""'):
                continue
            if key in seen:
                dups.append(key)
            else:
                seen[key] = True
    if dups:
        sys.stderr.write(
            "WARNUNG %s.po: %d doppelte msgid (Loader nimmt den ersten):\n"
            % (lang, len(dups))
        )
        for d in sorted(set(dups))[:20]:
            sys.stderr.write("  %s\n" % d)
    return len(dups)


def main():
    files = sorted(glob.glob(os.path.join(PO_DIR, "*.po")))
    if not files:
        sys.stderr.write("FEHLER: keine .po in %s\n" % PO_DIR)
        return 2

    langs = []
    for path in files:
        lang = os.path.splitext(os.path.basename(path))[0]
        if not LANG_RE.match(lang):
            sys.stderr.write("uebersprungen (kein Bezeichner): %s\n" % path)
            continue
        lines, nbytes = read_po_lines(path)
        ndup = scan_duplicates(lines, lang)
        langs.append((lang, lines, nbytes, ndup))

    o = []
    a = o.append
    a("{ ==========================================================================")
    a("  uLocalizationPo.inc - GENERIERT. NICHT VON HAND EDITIEREN.")
    a("")
    a("  i18n-Scharfschaltung 2026-07-26: eingebettete Kopie der i18n\\*.po.")
    a("  Erzeugt von tools\\gen_po_inc.py - Single Source of Truth bleibt die")
    a("  .po im Repo. Nach jeder .po-Aenderung neu generieren, danach in der")
    a("  IDE Clean + Build (die IDE trackt .inc-Abhaengigkeiten nicht sicher).")
    a("")
    a("  Inhalt ist ein WORTGETREUES Transkript der .po-Zeilen (kein Parsing),")
    a("  damit uLocalization._() eingebettete und externe .po durch exakt")
    a("  denselben Parser schickt. Non-ASCII ist als #$XXXX kodiert, die Datei")
    a("  ist daher reines ASCII (BOM-/Codepage-unabhaengig).")
    a("  ========================================================================== }")
    a("")
    a("const")
    for lang, lines, nbytes, ndup in langs:
        a("  // i18n\\%s.po - %d Zeilen, %d Bytes%s"
          % (lang, len(lines), nbytes,
             ", %d doppelte msgid" % ndup if ndup else ""))
        a("  CPoLines_%s: array[0..%d] of string = (" % (lang, len(lines) - 1))
        for i, ln in enumerate(lines):
            sep = "," if i < len(lines) - 1 else ""
            a("    " + pascal_literal(ln) + sep)
        a("  );")
        a("")

    a("// Kuerzel aller eingebetteten .po, in Dateisystem-Sortierung. Quelle")
    a("// fuer uLocalization.AvailableLanguages - damit die Sprachauswahl in")
    a("// der UI aus den tatsaechlich vorhandenen Uebersetzungen kommt und")
    a("// nicht aus einer von Hand gepflegten Liste (die zwangslaeufig driftet).")
    a("function EmbeddedLanguages: TArray<string>;")
    a("begin")
    a("  Result := TArray<string>.Create(%s);"
      % ", ".join("'%s'" % lang for lang, _, _, _ in langs))
    a("end;")
    a("")

    a("// Liefert den eingebetteten .po-Text zu einem normalisierten Sprach-")
    a("// kuerzel, oder '' wenn zu der Sprache nichts eingebettet ist.")
    a("function EmbeddedPoText(const ALang: string): string;")
    a("begin")
    first = True
    for lang, lines, nbytes, ndup in langs:
        # SameText statt '=' (2026-08-01): der Dateiname bestimmt das
        # Kuerzel, der Aufrufer normalisiert es aber. Eine 'PT.po' erzeugte
        # vorher den Vergleich "ALang = 'PT'" und wurde von einem
        # normalisierten 'pt' NIE getroffen - die eingebettete Kopie war
        # damit tot, ohne dass irgendetwas fehlschlug.
        a("  %sif SameText(ALang, '%s') then"
          % ("" if first else "else ", lang))
        a("    Result := JoinPoLines(CPoLines_%s)" % lang)
        first = False
    a("  else")
    a("    Result := '';")
    a("end;")
    a("")

    text = "\n".join(o) + "\n"
    with open(OUT, "w", encoding="ascii", newline="\r\n") as f:
        f.write(text)

    total = sum(len(l) for _, l, _, _ in langs)
    print("geschrieben: %s" % OUT)
    print("Sprachen: %s" % ", ".join(l for l, _, _, _ in langs))
    print("Zeilen gesamt: %d, .inc-Zeilen: %d" % (total, len(o)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
