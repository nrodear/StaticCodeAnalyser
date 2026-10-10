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

Schreibweise: das Modul schreibt den qualifizierten Namen woertlich in die
uses-Klausel des Benutzers. Massgeblich ist deshalb der Name, den die Unit
selbst deklariert ('unit Winapi.Foundation;' - die Datei heisst
WinAPI.Foundation.pas); gibt es keine .pas, das Praefix in der
DCC_Namespace-Schreibweise (Winapi, Vcl, Datasnap ...) plus das letzte
Segment des Dateinamens.

Aufruf:  python tools/gen_unitscopes.py [<Studio-Verzeichnis>]
Format:  eine Zeile je Kurzname, 'kurzname=Qualifiziert1;Qualifiziert2',
         Kurzname klein geschrieben, qualifizierte Namen wie oben,
         alphabetisch; '#' leitet Kommentare ein.
Fehlt ein Studio-Verzeichnis oder findet sich keine Unit, endet das Skript
mit Exit 2 und laesst die Tabelle unangetastet.
"""
import os
import re
import sys
from collections import defaultdict

STUDIO = sys.argv[1] if len(sys.argv) > 1 else r"C:\Program Files (x86)\Embarcadero\Studio\23.0"

# Unit-Scope-Praefixe (klein) -> Schreibweise der DCC_Namespace-Vorgabe.
PREFIXES = {"system": "System", "system.win": "System.Win", "winapi": "Winapi",
            "data": "Data", "data.win": "Data.Win", "datasnap": "Datasnap",
            "datasnap.win": "Datasnap.Win", "web": "Web", "web.win": "Web.Win",
            "soap": "Soap", "soap.win": "Soap.Win", "xml": "Xml",
            "xml.win": "Xml.Win", "bde": "Bde", "vcl": "Vcl",
            "vcl.imaging": "Vcl.Imaging", "vcl.touch": "Vcl.Touch",
            "vcl.samples": "Vcl.Samples", "vcl.shell": "Vcl.Shell", "fmx": "FMX"}

NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+")
COMMENT_RE = re.compile(r"\{.*?\}|\(\*.*?\*\)|//[^\r\n]*", re.S)
UNIT_RE = re.compile(r"^\s*unit\s+([A-Za-z_][A-Za-z0-9_.]*)", re.I | re.M)


def declared_name(path):
    """Name aus dem Unit-Kopf der .pas, oder None. Vor dem Kopf stehen nur
    Kommentare und Direktiven - die fallen mit COMMENT_RE weg."""
    with open(path, "rb") as fh:
        raw = fh.read(65536)
    m = UNIT_RE.search(COMMENT_RE.sub(" ", raw.decode("latin-1")))
    return m.group(1) if m else None


def collect(studio):
    names = {}   # qualifiziert.lower() -> (Rang, qualifiziert); kleiner Rang gewinnt
    for root in (os.path.join(studio, "source"), os.path.join(studio, "lib", "win32", "release")):
        for dp, dirs, files in os.walk(root):
            dirs.sort()
            for f in sorted(files):
                base, ext = os.path.splitext(f)
                if ext.lower() not in (".pas", ".dcu"):
                    continue
                if "." not in base or not NAME_RE.fullmatch(base):
                    continue
                prefix, last = base.rsplit(".", 1)
                if prefix.lower() not in PREFIXES:
                    continue
                # Rang 0: Unit-Kopf der .pas; 1: .pas ohne passenden Kopf;
                # 2: nur .dcu. 1 und 2 normalisieren das Praefix.
                rank, name = 2, PREFIXES[prefix.lower()] + "." + last
                if ext.lower() == ".pas":
                    decl = declared_name(os.path.join(dp, f))
                    if decl and decl.lower() == base.lower():
                        rank, name = 0, decl
                    else:
                        rank = 1
                key = base.lower()
                if key not in names or rank < names[key][0]:
                    names[key] = (rank, name)
    return {key: name for key, (_, name) in names.items()}


def main():
    roots = (os.path.join(STUDIO, "source"), os.path.join(STUDIO, "lib", "win32", "release"))
    missing = [r for r in roots if not os.path.isdir(r)]
    if missing:
        sys.stderr.write("Studio-Verzeichnis unvollstaendig, Tabelle bleibt unveraendert:\n")
        for r in missing:
            sys.stderr.write("  fehlt: %s\n" % r)
        sys.exit(2)
    names = collect(STUDIO)
    if not names:
        sys.stderr.write("keine Unit unter den Scope-Praefixen in %s - Tabelle bleibt unveraendert\n" % STUDIO)
        sys.exit(2)
    table = defaultdict(list)
    for qualified in names.values():
        table[qualified.rsplit(".", 1)[1].lower()].append(qualified)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "unitscopes.txt")
    # Erst vollstaendig daneben schreiben, dann tauschen: ein Abbruch
    # mittendrin laesst die eingecheckte Tabelle stehen.
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="ascii", newline="\r\n") as fh:
        fh.write("# reDelphix Scope-Tabelle: Kurzname -> qualifizierte Unit-Namen (Embarcadero-Scopes).\n")
        fh.write("# Erzeugt von tools/gen_unitscopes.py aus %s\n" % STUDIO.replace("\\", "/"))
        fh.write("# Nur Units unter den Unit-Scope-Praefixen eines Win32-VCL-/FMX-Projekts (DCC_Namespace-Vorgabe).\n")
        fh.write("# Mehrere Treffer je Kurzname loest das Modul in der Reihenfolge der Scope-Liste des Rahmenwerks auf (uRdxScopeTable).\n")
        for short in sorted(table):
            fh.write("%s=%s\n" % (short, ";".join(sorted(table[short], key=str.lower))))
    os.replace(tmp, out)
    ambiguous = sum(1 for v in table.values() if len(v) > 1)
    print("units: %d  kurznamen: %d  mehrdeutig: %d  -> %s" % (len(names), len(table), ambiguous, os.path.normpath(out)))


if __name__ == "__main__":
    main()
