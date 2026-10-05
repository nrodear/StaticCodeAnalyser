#!/usr/bin/env python3
"""Erzeugt data/unitscopes.txt - die Scope-Tabelle des Moduls reDelphix.

Quelle ist die lokale Delphi-Installation: alle Units mit Punkt im Namen
aus <Studio>/source und <Studio>/lib/win32/release, deren Praefix (alles
vor dem letzten Segment) in der Unit-Scope-Vorgabe (DCC_Namespace) eines
Win32-VCL- oder -FMX-Projekts steht. Nur fuer DIE loest der Compiler einen
Kurznamen auf; 'FireDAC.Comp.Client' hat keinen Scope-Eintrag, ein
'uses Client' gibt es nicht - solche Units gehoeren nicht in die Tabelle.

Je Kurzname (letztes Segment) stehen alle qualifizierten Namen, in denen
er vorkommt - 'Forms' ist Vcl.Forms UND FMX.Forms. Die Wahl trifft das
Modul (uRdxScopeTable) in der Reihenfolge der Scope-Liste des Rahmenwerks
der Datei, nicht diese Tabelle.

Aufruf:  python tools/gen_unitscopes.py [<Studio-Verzeichnis>]
Format:  eine Zeile je Kurzname, 'kurzname=Qualifiziert1;Qualifiziert2',
         Kurzname klein geschrieben, qualifizierte Namen in Originalschreibung,
         alphabetisch; '#' leitet Kommentare ein.
"""
import os
import re
import sys
from collections import defaultdict

STUDIO = sys.argv[1] if len(sys.argv) > 1 else r"C:\Program Files (x86)\Embarcadero\Studio\23.0"

PREFIXES = {"system", "system.win", "winapi", "data", "data.win", "datasnap",
            "datasnap.win", "web", "web.win", "soap", "soap.win", "xml",
            "xml.win", "bde", "vcl", "vcl.imaging", "vcl.touch", "vcl.samples",
            "vcl.shell", "fmx"}

NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+")


def collect(studio):
    names = {}   # qualifiziert.lower() -> qualifiziert (pas vor dcu: Originalschreibung)
    for root in (os.path.join(studio, "source"), os.path.join(studio, "lib", "win32", "release")):
        for dp, _, files in os.walk(root):
            for f in sorted(files):
                base, ext = os.path.splitext(f)
                if ext.lower() not in (".pas", ".dcu"):
                    continue
                if "." not in base or not NAME_RE.fullmatch(base):
                    continue
                if base.rsplit(".", 1)[0].lower() not in PREFIXES:
                    continue
                names.setdefault(base.lower(), base)
    return names


def main():
    names = collect(STUDIO)
    table = defaultdict(list)
    for qualified in names.values():
        table[qualified.rsplit(".", 1)[1].lower()].append(qualified)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "unitscopes.txt")
    with open(out, "w", encoding="ascii", newline="\r\n") as fh:
        fh.write("# reDelphix Scope-Tabelle: Kurzname -> qualifizierte Unit-Namen (Embarcadero-Scopes).\n")
        fh.write("# Erzeugt von tools/gen_unitscopes.py aus %s\n" % STUDIO.replace("\\", "/"))
        fh.write("# Nur Units unter den Unit-Scope-Praefixen eines Win32-VCL-/FMX-Projekts (DCC_Namespace-Vorgabe).\n")
        fh.write("# Mehrere Treffer je Kurzname loest das Modul in der Reihenfolge der Scope-Liste des Rahmenwerks auf (uRdxScopeTable).\n")
        for short in sorted(table):
            fh.write("%s=%s\n" % (short, ";".join(sorted(table[short], key=str.lower))))
    ambiguous = sum(1 for v in table.values() if len(v) > 1)
    print("units: %d  kurznamen: %d  mehrdeutig: %d  -> %s" % (len(names), len(table), ambiguous, os.path.normpath(out)))


if __name__ == "__main__":
    main()
