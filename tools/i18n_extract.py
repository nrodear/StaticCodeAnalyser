#!/usr/bin/env python3
"""
Extrahiert alle _()-Aufrufe aus dem Delphi-Quellbaum und erzeugt daraus
i18n/template.pot (deterministisch + idempotent).

Referenz: i18n-Scharfschaltung 2026-07-26.
Seit der Scharfschaltung sind die .po-Dateien die EINZIGE Quelle der
Wahrheit fuer Uebersetzungen (das hartcodierte GDeMap in
SCA.Engine/sources/Common/uLocalization.pas entfaellt). Dieses Tool
liefert die Gegenprobe: welche msgids der Code ueberhaupt anfragt.

Erfasst werden beide Overloads:
    _('Text')
    _('Text %d', [Arg])
inklusive mehrzeiliger Pascal-Konkatenation:
    _('erste Haelfte ' +
      'zweite Haelfte')
sowie eingebetteter Zeichencodes (#13#10, #$0D). Dynamische Argumente
(Variablen, Funktionsaufrufe) werden bewusst uebersprungen - sie sind zur
Compile-Zeit kein uebersetzbarer Text.

Kommentare ({...}, (*...*), //...) und Strings werden korrekt uebersprungen,
d. h. ein "_(" in einem Kommentar oder in einem Literal (z. B. in den
Fix-Hint-Codebeispielen von uFixHint.pas) erzeugt KEINEN Eintrag.

Nutzung:
  python tools/i18n_extract.py                 # i18n/template.pot schreiben
  python tools/i18n_extract.py --check         # nur pruefen (CI, Exit 1 bei Diff)
  python tools/i18n_extract.py --json          # Eintraege maschinenlesbar
  python tools/i18n_extract.py --msgids-source # msgids aus dem Quellbaum (1/Zeile)
  python tools/i18n_extract.py --msgids-po i18n/de.po
                                               # msgids aus einer .po/.pot (1/Zeile)
  python tools/i18n_extract.py --dynamic       # uebersprungene _()-Aufrufe zeigen

--msgids-source / --msgids-po geben jede msgid PO-escaped (also ohne echte
Zeilenumbrueche) aus, damit zeilenbasierte Werkzeuge wie comm/diff in
tools/i18n_audit.sh damit rechnen koennen.

Idempotenz: Die Ausgabe haengt ausschliesslich vom Quellbaum ab (feste
POT-Creation-Date-Konstante, msgids alphabetisch sortiert, Referenzen
sortiert). Zweimal laufen lassen aendert nichts.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_POT = REPO_ROOT / "i18n" / "template.pot"

# Dateiendungen, die Pascal-Quelltext enthalten.
SOURCE_SUFFIXES = {".pas", ".dpr", ".dpk", ".inc"}

# Verzeichnisse, die auf JEDER Ebene uebersprungen werden:
#  - Build-/IDE-Artefakte (kein Quelltext bzw. veraltete Kopien)
#  - Testkorpora und Beispielcode (Analyse-INPUT, keine UI-Strings)
#  - Testprojekte (Assertions sind bewusst englisch, siehe uTestFixHint.pas)
EXCLUDED_DIRS = {
    ".git",
    "__history",
    "__recovery",
    "Win32",
    "Win64",
    "node_modules",
    "golden-corpus",
    "examples",
    "tests",
    "test",
}

# Verzeichnisse, die NUR direkt unter der Repo-Wurzel ausgeschlossen werden.
# Wichtig: "Output" ist auf Repo-Ebene ein Build-Ordner, tiefer im Baum aber
# ein echtes Quellverzeichnis (SCA.Engine/sources/Output/uFixHint.pas mit
# ueber 170 _()-Strings) - ein globaler Ausschluss verlor genau diese.
EXCLUDED_ROOT_DIRS = {
    "Output",
    "dist",
    "tmp",
    "installer",
}

# Feste Kopfzeilen-Werte: bewusst KEIN "jetzt"-Zeitstempel, sonst waere die
# Datei nicht idempotent und jeder Lauf erzeugte einen Diff.
POT_CREATION_DATE = "2026-07-26 00:00+0000"

POT_HEADER = f'''\
# Translation template for Static Code Analysis Tool for Delphi
# Copyright (C) Static Code Analysis Tool authors
# This file is distributed under the same license as the project.
#
# GENERIERT - NICHT VON HAND BEARBEITEN.
# Erzeugt aus dem Quellbaum von tools/i18n_extract.py
# (Referenz: i18n-Scharfschaltung 2026-07-26):
#
#   python tools/i18n_extract.py
#
# Neue Strings in die Sprachdateien uebernehmen:
#   msgmerge -U i18n/de.po i18n/template.pot
#   msgmerge -U i18n/fr.po i18n/template.pot
#
# Abdeckung pruefen:
#   bash tools/i18n_audit.sh
#
msgid ""
msgstr ""
"Project-Id-Version: Static Code Analysis Tool for Delphi 1.0\\n"
"POT-Creation-Date: {POT_CREATION_DATE}\\n"
"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\n"
"Language-Team: LANGUAGE <LL@li.org>\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
'''


# --------------------------------------------------------------------------
# PO-Escaping
# --------------------------------------------------------------------------

_ESCAPES = {
    "\\": "\\\\",
    '"': '\\"',
    "\n": "\\n",
    "\r": "\\r",
    "\t": "\\t",
}


def po_escape(text: str) -> str:
    """Delphi-String -> PO-Literal-Inhalt (ohne umschliessende Quotes)."""
    return "".join(_ESCAPES.get(ch, ch) for ch in text)


def po_unescape(text: str) -> str:
    """PO-Literal-Inhalt -> Rohtext."""
    out: list[str] = []
    i = 0
    simple = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            out.append(simple.get(nxt, nxt))
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


# --------------------------------------------------------------------------
# Pascal-Scanner
# --------------------------------------------------------------------------

class _Scanner:
    """Minimaler Pascal-Lexer, der nur so viel versteht, wie fuer das
    Auffinden von _()-Aufrufen noetig ist: Kommentare, String-Literale,
    Zeichencodes und Konkatenation mit '+'."""

    def __init__(self, text: str) -> None:
        self.s = text
        self.n = len(text)

    # -- Hilfen ------------------------------------------------------------
    def line_of(self, pos: int) -> int:
        return self.s.count("\n", 0, pos) + 1

    def skip_trivia(self, i: int) -> int:
        """Whitespace + alle Kommentarformen ueberspringen."""
        s, n = self.s, self.n
        while i < n:
            ch = s[i]
            if ch in " \t\r\n":
                i += 1
            elif ch == "/" and i + 1 < n and s[i + 1] == "/":
                j = s.find("\n", i)
                i = n if j < 0 else j + 1
            elif ch == "{":
                j = s.find("}", i)
                i = n if j < 0 else j + 1
            elif ch == "(" and i + 1 < n and s[i + 1] == "*":
                j = s.find("*)", i + 2)
                i = n if j < 0 else j + 2
            else:
                break
        return i

    def read_string(self, i: int) -> tuple[str, int]:
        """Liest ein 'Literal' ab s[i] == "'". Gibt (Inhalt, Position danach)
        zurueck. '' innerhalb des Literals ist ein einzelnes Apostroph."""
        s, n = self.s, self.n
        assert s[i] == "'"
        i += 1
        buf: list[str] = []
        while i < n:
            ch = s[i]
            if ch == "'":
                if i + 1 < n and s[i + 1] == "'":
                    buf.append("'")
                    i += 2
                    continue
                return "".join(buf), i + 1
            if ch == "\n":  # unterminiertes Literal -> abbrechen
                break
            buf.append(ch)
            i += 1
        return "".join(buf), i

    def read_charcode(self, i: int) -> tuple[str, int] | tuple[None, int]:
        """Liest #13 / #$0D. Gibt (Zeichen, Position danach) zurueck."""
        s, n = self.s, self.n
        assert s[i] == "#"
        i += 1
        if i < n and s[i] == "$":
            i += 1
            start = i
            while i < n and s[i] in "0123456789abcdefABCDEF":
                i += 1
            if i == start:
                return None, i
            return chr(int(s[start:i], 16)), i
        start = i
        while i < n and s[i].isdigit():
            i += 1
        if i == start:
            return None, i
        return chr(int(s[start:i])), i


def _is_ident_char(ch: str) -> bool:
    return ch.isalnum() or ch == "_"


def _preceded_by_routine_keyword(s: str, i: int) -> bool:
    """True, wenn vor Position i (Beginn von '_') das Schluesselwort
    'function' oder 'procedure' steht - dann ist es die Deklaration von _
    selbst und kein Aufruf."""
    j = i - 1
    while j >= 0 and s[j] in " \t\r\n":
        j -= 1
    end = j + 1
    while j >= 0 and _is_ident_char(s[j]):
        j -= 1
    return s[j + 1:end].lower() in ("function", "procedure")


def collect_string_consts(text: str) -> dict[str, str]:
    """Sammelt unit-lokale String-Konstanten (NAME = 'Text';).

    Noetig, weil einige Aufrufstellen ueber eine Konstante gehen:
        HEADER_METHOD = 'Method';
        ...
        FGrid.Cells[COL_METHOD, 0] := _(HEADER_METHOD);
    Ohne Aufloesung fielen genau diese UI-Strings aus der .pot heraus.
    """
    sc = _Scanner(text)
    s, n = text, len(text)
    consts: dict[str, str] = {}

    i = 0
    while i < n:
        ch = s[i]

        if ch == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if ch == "{":
            j = s.find("}", i)
            i = n if j < 0 else j + 1
            continue
        if ch == "(" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*)", i + 2)
            i = n if j < 0 else j + 2
            continue
        if ch == "'":
            _, i = sc.read_string(i)
            continue

        if ch.isalpha() or ch == "_":
            start = i
            # Nur DEKLARATIONEN zaehlen (2026-08-01): der Scanner lief ueber
            # den ganzen Dateitext und nahm jedes 'NAME = <literal>' mit -
            # auch mitten in einem Ausdruck. Aus
            #     Found := Ext = '.pas';
            # wurde die "Konstante" Ext mit dem Wert '.pas', und der landete
            # als msgid in template.pot. Eine echte Konstanten-Deklaration
            # eroeffnet ihre Zeile (nur Whitespace davor); ein Vergleich
            # mitten im Ausdruck tut das nicht.
            line_start = s.rfind("\n", 0, start) + 1
            at_line_begin = s[line_start:start].strip() == ""
            while i < n and _is_ident_char(s[i]):
                i += 1
            name = s[start:i]
            if not at_line_begin:
                continue
            j = sc.skip_trivia(i)
            # Optionale Typangabe: NAME: string = '...'
            if j < n and s[j] == ":":
                k = sc.skip_trivia(j + 1)
                t0 = k
                while k < n and _is_ident_char(s[k]):
                    k += 1
                if k > t0:
                    j = sc.skip_trivia(k)
                else:
                    j = n
            if j < n and s[j] == "=" and (j + 1 >= n or s[j + 1] != "="):
                k = sc.skip_trivia(j + 1)
                if k < n and s[k] in ("'", "#"):
                    value, after, ok = _read_literal_chain(sc, k, stops=(";",))
                    if ok and name not in consts:
                        consts[name] = value
                    i = after
                    continue
            continue

        i += 1

    return consts


def scan_source(text: str, consts: dict[str, str] | None = None
                ) -> tuple[list[tuple[str, int]], list[int]]:
    """Findet alle _()-Aufrufe mit konstantem Text-Argument.

    consts loest die Indirektion ueber unit-lokale String-Konstanten auf.

    Rueckgabe: (Liste (msgid, Zeile), Liste Zeilen dynamischer Aufrufe).
    """
    sc = _Scanner(text)
    s, n = text, len(text)
    consts = consts or {}
    found: list[tuple[str, int]] = []
    dynamic: list[int] = []

    i = 0
    while i < n:
        ch = s[i]

        # Kommentare komplett ueberspringen (auch {$IFDEF}-Direktiven).
        if ch == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if ch == "{":
            j = s.find("}", i)
            i = n if j < 0 else j + 1
            continue
        if ch == "(" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*)", i + 2)
            i = n if j < 0 else j + 2
            continue

        # String-Literale ueberspringen: ein "_(" DARIN ist Text, kein Aufruf
        # (uFixHint.pas zeigt _() in seinen Codebeispielen).
        if ch == "'":
            _, i = sc.read_string(i)
            continue

        # Aufruf-Kandidat: '_' als eigenstaendiger Bezeichner, gefolgt von '('.
        if ch == "_":
            prev = s[i - 1] if i > 0 else ""
            if _preceded_by_routine_keyword(s, i):
                # Die Deklaration/Implementierung von _ selbst
                # (uLocalization.pas) ist kein Aufruf.
                i += 1
                continue
            if not (_is_ident_char(prev) or prev == "."):
                j = sc.skip_trivia(i + 1)
                if j < n and s[j] == "(":
                    call_line = sc.line_of(i)
                    msgid, after, ok = _read_first_arg(sc, j + 1)
                    if not ok:
                        # Zweiter Versuch: Indirektion ueber eine unit-lokale
                        # String-Konstante, z. B. _(HEADER_METHOD).
                        msgid, after, ok = _read_const_arg(sc, j + 1, consts)
                    if ok:
                        found.append((msgid, call_line))
                    else:
                        dynamic.append(call_line)
                    i = after
                    continue
        i += 1

    return found, dynamic


def _read_literal_chain(sc: _Scanner, i: int,
                        stops: tuple[str, ...]) -> tuple[str, int, bool]:
    """Liest eine Pascal-Konkatenationskette aus String-Literalen und
    Zeichencodes ab Position i: 'a' + 'b' + #13#10 + 'c'.

    Die Kette endet an einem der Zeichen in stops. Alles andere
    (Bezeichner, Funktionsaufruf, Klammer) gilt als nicht-konstant.

    Rueckgabe: (Text, Position hinter dem Stopzeichen, konstant?)
    """
    s, n = sc.s, sc.n
    parts: list[str] = []
    expect_operand = True

    while True:
        i = sc.skip_trivia(i)
        if i >= n:
            return "", i, False

        ch = s[i]

        if expect_operand:
            if ch == "'":
                lit, i = sc.read_string(i)
                parts.append(lit)
                expect_operand = False
                continue
            if ch == "#":
                code, i = sc.read_charcode(i)
                if code is None:
                    return "", i, False
                parts.append(code)
                # Zeichencodes duerfen direkt aneinanderhaengen (#13#10) und
                # direkt an ein Literal ('a'#13) - also kein '+' erzwingen.
                expect_operand = False
                continue
            return "", i, False

        # Nach einem Operanden: '+' setzt die Kette fort, ein Stopzeichen
        # beendet sie, ein direkt folgendes Literal/# setzt sie ebenfalls
        # fort (Pascal erlaubt 'a'#13'b' ohne Plus).
        if ch == "+":
            i += 1
            expect_operand = True
            continue
        if ch in ("'", "#"):
            expect_operand = True
            continue
        if ch in stops:
            return "".join(parts), i + 1, True
        return "", i, False


def _read_first_arg(sc: _Scanner, i: int) -> tuple[str, int, bool]:
    """Liest das erste Argument eines _()-Aufrufs ab Position i (direkt
    hinter der oeffnenden Klammer). Deckt beide Overloads ab: die Kette
    endet entweder an ')' (einargumentig) oder an ',' (Format-Overload)."""
    return _read_literal_chain(sc, i, stops=(",", ")"))


def _read_const_arg(sc: _Scanner, i: int,
                    consts: dict[str, str]) -> tuple[str, int, bool]:
    """Behandelt _(NAME) bzw. _(NAME, [...]) mit NAME = unit-lokale
    String-Konstante. Nur ein einzelner Bezeichner wird aufgeloest -
    Ausdruecke bleiben bewusst dynamisch."""
    s, n = sc.s, sc.n
    j = sc.skip_trivia(i)
    start = j
    while j < n and _is_ident_char(s[j]):
        j += 1
    if j == start:
        return "", i, False
    name = s[start:j]
    j = sc.skip_trivia(j)
    if j < n and s[j] in (")", ",") and name in consts:
        return consts[name], j + 1, True
    return "", i, False


# --------------------------------------------------------------------------
# Quellbaum
# --------------------------------------------------------------------------

def iter_sources(root: Path):
    """Alle Pascal-Quelldateien unterhalb root, ohne EXCLUDED_DIRS."""
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        rel = path.relative_to(root)
        dirs = rel.parts[:-1]
        if any(part in EXCLUDED_DIRS for part in dirs):
            continue
        if dirs and dirs[0] in EXCLUDED_ROOT_DIRS:
            continue
        yield path


def read_text(path: Path) -> str:
    """Delphi-Quellen sind UTF-8 (oft mit BOM), aeltere evtl. ANSI."""
    data = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "cp1252"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("latin-1")


def collect(root: Path) -> tuple[dict[str, list[str]], list[str]]:
    """Sammelt msgid -> sortierte Referenzliste ("pfad:zeile") sowie die
    Referenzen aller uebersprungenen (dynamischen) Aufrufe."""
    entries: dict[str, set[str]] = {}
    dynamic_refs: list[str] = []

    for path in iter_sources(root):
        rel = path.relative_to(root).as_posix()
        try:
            text = read_text(path)
        except OSError as exc:  # pragma: no cover - defensiv
            print(f"WARN: {rel}: {exc}", file=sys.stderr)
            continue
        if "_(" not in text:
            continue
        found, dynamic = scan_source(text, collect_string_consts(text))
        for msgid, line in found:
            if not msgid:
                continue  # _('') ist die PO-Kopfzeile - nie als Eintrag
            entries.setdefault(msgid, set()).add(f"{rel}:{line}")
        for line in dynamic:
            dynamic_refs.append(f"{rel}:{line}")

    def ref_key(ref: str) -> tuple[str, int]:
        file_part, _, line_part = ref.rpartition(":")
        return file_part, int(line_part)

    ordered = {k: sorted(v, key=ref_key) for k, v in entries.items()}
    return ordered, sorted(dynamic_refs, key=ref_key)


# --------------------------------------------------------------------------
# POT-Rendering
# --------------------------------------------------------------------------

def render_pot(entries: dict[str, list[str]]) -> str:
    parts = [POT_HEADER]
    # Stabile Reihenfolge: alphabetisch nach msgid. Bewusst NICHT nach
    # Fundstelle - sonst wandern beim Verschieben von Code ganze Bloecke.
    for msgid in sorted(entries):
        parts.append("")
        for ref in entries[msgid]:
            parts.append(f"#: {ref}")
        parts.append(f'msgid "{po_escape(msgid)}"')
        parts.append('msgstr ""')
    return "\n".join(parts) + "\n"


# --------------------------------------------------------------------------
# PO-Leser (fuer --msgids-po)
# --------------------------------------------------------------------------

def read_po_entries(path: Path) -> list[tuple[str, str, bool]]:
    """Liest eine .po/.pot als Liste (msgid, msgstr, fuzzy).

    Mehrzeilige Literale ("..." Fortsetzungszeilen) werden zusammengefasst.
    Der Kopf-Eintrag (leere msgid) wird ausgelassen.
    """
    entries: list[tuple[str, str, bool]] = []

    msgid: list[str] | None = None
    msgstr: list[str] | None = None
    target: list[str] | None = None
    fuzzy = False
    pending_fuzzy = False

    def flush() -> None:
        nonlocal msgid, msgstr, target
        if msgid is not None:
            key = "".join(msgid)
            if key:
                entries.append((key, "".join(msgstr or []), fuzzy))
        msgid = None
        msgstr = None
        target = None

    for raw in read_text(path).splitlines():
        line = raw.strip()

        if not line:
            flush()
            continue

        if line.startswith("#"):
            if line.startswith("#,") and "fuzzy" in line:
                pending_fuzzy = True
            continue

        if line.startswith("msgid "):
            flush()
            fuzzy = pending_fuzzy
            pending_fuzzy = False
            msgid = [_po_literal(line[len("msgid "):])]
            target = msgid
            continue

        if line.startswith("msgstr"):
            # msgstr bzw. msgstr[0] (Plural - hier nur der erste Index).
            _, _, rest = line.partition(" ")
            if msgstr is None:
                msgstr = [_po_literal(rest)]
            else:
                msgstr.append(_po_literal(rest))
            target = msgstr
            continue

        if line.startswith('"') and target is not None:
            target.append(_po_literal(line))
            continue

    flush()
    return entries


def read_po_msgids(path: Path, only_translated: bool = False) -> list[str]:
    """msgids einer .po/.pot. only_translated laesst leere und fuzzy
    msgstr weg - nur die zaehlen als echte Uebersetzung."""
    out: list[str] = []
    for msgid, msgstr, fuzzy in read_po_entries(path):
        if only_translated and (not msgstr or fuzzy):
            continue
        out.append(msgid)
    return out


def _po_literal(token: str) -> str:
    token = token.strip()
    if len(token) >= 2 and token.startswith('"') and token.endswith('"'):
        return po_unescape(token[1:-1])
    return ""


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Extrahiert _()-Strings aus dem Quellbaum nach i18n/template.pot"
    )
    ap.add_argument("--root", type=Path, default=REPO_ROOT, help="Repo-Wurzel")
    ap.add_argument("--out", type=Path, default=DEFAULT_POT, help="Ziel-.pot")
    ap.add_argument("--check", action="store_true",
                    help="Nur pruefen ob die .pot aktuell ist. Exit 1 bei Diff.")
    ap.add_argument("--json", action="store_true",
                    help="Eintraege als JSON ausgeben (msgid + Referenzen)")
    ap.add_argument("--msgids-source", action="store_true",
                    help="msgids des Quellbaums PO-escaped, eine pro Zeile, sortiert")
    ap.add_argument("--msgids-po", type=Path, metavar="PO",
                    help="msgids einer .po/.pot PO-escaped, eine pro Zeile, sortiert")
    ap.add_argument("--only-translated", action="store_true",
                    help="mit --msgids-po: leere und fuzzy msgstr auslassen")
    ap.add_argument("--dynamic", action="store_true",
                    help="_()-Aufrufe ohne konstanten Text auflisten")
    args = ap.parse_args()

    # Windows-Konsole ist per Default cp1252 - msgids enthalten aber Unicode
    # (z. B. U+25B6). Ohne Umschaltung bricht jede Ausgabe mit
    # UnicodeEncodeError ab.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", newline="\n")

    # Reiner PO-Leser - kein Quellbaum-Scan noetig.
    if args.msgids_po is not None:
        po_path = args.msgids_po
        if not po_path.exists():
            print(f"ERROR: Datei nicht gefunden: {po_path}", file=sys.stderr)
            return 2
        for msgid in sorted(set(read_po_msgids(po_path, args.only_translated))):
            print(po_escape(msgid))
        return 0

    entries, dynamic_refs = collect(args.root)

    if args.msgids_source:
        for msgid in sorted(entries):
            print(po_escape(msgid))
        return 0

    if args.dynamic:
        for ref in dynamic_refs:
            print(ref)
        print(f"\n{len(dynamic_refs)} _()-Aufruf(e) ohne konstanten Text.",
              file=sys.stderr)
        return 0

    if args.json:
        payload = {
            "count": len(entries),
            "dynamic": dynamic_refs,
            "entries": [{"msgid": m, "refs": entries[m]} for m in sorted(entries)],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    content = render_pot(entries)

    if args.check:
        existing = args.out.read_text(encoding="utf-8") if args.out.exists() else ""
        if existing != content:
            print(f"DIFF: {args.out} ist nicht aktuell.", file=sys.stderr)
            print("Bitte ausfuehren: python tools/i18n_extract.py", file=sys.stderr)
            return 1
        print(f"OK: {args.out.name} aktuell ({len(entries)} msgids).")
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(content, encoding="utf-8", newline="\n")
    print(f"{args.out}: {len(entries)} msgids geschrieben "
          f"({len(dynamic_refs)} dynamische Aufrufe uebersprungen).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
