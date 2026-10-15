#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gate: deutsche Texte in reDelphix/source ohne Uebersetzung (Entscheid E29).

WARUM (Charge C1, 2026-10-15)
-----------------------------
Jeder Text, den reDelphix dem Nutzer zeigt (Menuetext, Hinweis, Grund
eines ausgegrauten Eintrags, Statuszeile, Fehlermeldung), ist eine
ENGLISCHE msgid, uebersetzt ueber uRdxText._ in die Sprache der
SCA-Oberflaeche. Vor der Umstellung standen rund 960 deutsche
Text-Literale fest im Quelltext; die Umstellung laeuft in Gruppen je Unit.
Dieses Gate zeigt, was noch fehlt, und haelt den Stand danach: ein neuer
deutscher Grund ohne _() faellt sofort auf, nicht erst einem Nutzer mit
englischer Oberflaeche.

Was es meldet (je Fund Unit, Zeile, Art, Text):
  text      ein deutsches Text-Literal, das weder erstes Argument von _()
            ist noch Wert einer msgid-Konstante. Deutsch (is_german): ein
            Wort aus drei Buchstaben und ein typisch deutsches Wort - als
            ganzes Wort (Liste des Inventars, scratchpad
            w7/i18n_inventory.py, erweitert) oder als Ende eines
            zusammengesetzten ('Formdateien', 'asm-Rumpf') -, ein Umlaut,
            ein umschriebener Umlaut in einer Folge, die es englisch nicht
            gibt ('Groesse') oder eine Zahl mit grossgeschriebenem Nomen
            ('%d Parameter'). Ein Leerzeichen braucht es nicht: auch ein
            einzelnes Wort ('unbekannt') ist Text. Verkettete Literale
            ('a ' + 'b', 'a'#13) zaehlen als EIN Text; ein Bezeichner
            dazwischen trennt.
  msgid     ein deutscher Text IN _() bzw. in einer msgid-Konstante - die
            msgid ist englisch (E29), die deutsche Fassung steht in de.po.
  qualif    ein qualifizierter Aufruf X._(..): tools/i18n_extract.py sieht
            ihn nicht, die msgid fehlte in template.pot.
  fremd     _(NAME) mit einem Konstanten-Namen (GROSS_MIT_UNTERSTRICH),
            der in DIESER Unit keine reine Literal-Konstante ist - der
            Extraktor loest nur Konstanten derselben Unit auf; die msgid
            fehlte in template.pot (Lehre: msgid-Konstanten nicht
            verschieben).
  dynamisch _(..) mit einem anderen ersten Argument als einer Literal-Kette
            oder einer msgid-Konstante bzw. einem msgid-Array dieser Unit:
            ein Parameter (_(AWhat)), _(Format(..)), _('a ' + X). Der
            Extraktor ueberspringt den Aufruf still (nur --dynamic nennt
            ihn), die msgid fehlte in template.pot, de und fr zeigten den
            Text unuebersetzt. Text fuer eine andere Unit uebersetzt der
            Aufrufer (reDelphix/README.md, "Texte umstellen").

Grenzen der Heuristik: ein deutscher Text nur aus Woertern, die es auch
englisch gibt ('Parameter' ohne Zahl, 'Operand', 'Format'), faellt nicht
auf; ein englischer mit '%d <Grosswort>' ('%d Bytes') faellt auf - dann
klein schreiben wie jede msgid. Stand Nachpruefung FIX-C1: alle nicht
gemeldeten Ketten mit Buchstaben in reDelphix/source gesichtet - darunter
kein sichtbarer deutscher Text mehr (nur Protokoll, Code, englische
Meldungsschluessel).

msgid-Konstante = wie der Extraktor: eine Konstante derselben Unit, deren
Deklaration ihre Zeile eroeffnet und deren Wert eine reine Literal-Kette
ist ('a' + 'b'; 'a' + R_X ist es NICHT), mit einem Aufruf _(NAME) bzw.
_(NAME, [..]) in der Unit; ein String-Array mit _(NAME[i]).

Bewusst feste Texte stehen in tools/rdx_i18n_gate.allow, je Eintrag mit
Begruendung (Format im Kopf der Datei): das Protokoll (uRdxLog, RdxLog-
Aufrufe), Code-Schnipsel, Schluesselwoerter, englische Meldungsschluessel
zum Lesen der SCA-Meldungen. Ein Eintrag, der nichts (mehr) trifft, ist
selbst ein Fund ('ausnahme') - die Liste veraltet sonst still.

Aufruf (aus der Repo-Wurzel):
  python tools/rdx_i18n_gate.py              # Gate: Funde je Unit, Exit 1 bei Funden
  python tools/rdx_i18n_gate.py --report     # Stand je Unit (Zahlen), Exit 0
  python tools/rdx_i18n_gate.py --unit uRdxFlowFixes.pas
                                             # Gate nur fuer diese Unit(s)
  python tools/rdx_i18n_gate.py --selftest   # Mutanten gegen den Pruefer
Exit 0 = keine Funde, 1 = Funde, 2 = Aufruf- oder Ausnahmelisten-Fehler.
Noch NICHT in der CI: bis die Gruppen der Umstellung fertig sind, ist es
absichtlich rot.
"""
import bisect
import pathlib
import re
import shutil
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC_DIR = REPO / "reDelphix" / "source"
ALLOW_FILE = REPO / "tools" / "rdx_i18n_gate.allow"

# Typisch deutsche Woerter: die Liste des Inventars (w7/i18n_inventory.py)
# und Woerter aus reDelphix-Texten, die keines davon tragen (Nachmessung
# Charge C1: '%d Aufrufe %s(', ', alle bewiesen', 'Implementierung: ',
# '%d-mal ' ...), dazu deutsche Endungen ('Sprunganweisungen'). Nur Woerter,
# die es im Englischen nicht gibt: zusammen mit GERMAN_TAIL, TRANSCRIPTION
# und COUNT_NOUN gegen alle msgids der SCA gemessen (template.pot 674,
# de.po 814, fr.po 811, vor C1 795; Nachpruefung FIX-C1) 0 Treffer - eine
# msgid oder ein englischer Meldungsschluessel der SCA ausserhalb von _()
# faellt nicht auf.
GERMAN = re.compile(
    r"\b(der|die|das|den|dem|des|ein|eine|einen|einer|eines|nicht|kein|keine|"
    r"keinen|keiner|ist|sind|wird|werden|mit|ohne|und|oder|aber|auf|aus|bei|"
    r"bis|fuer|ueber|unter|vor|nach|hinter|zeile|zeilen|datei|spalte|"
    r"gleiche|bedeutung|geoeffnet|gesperrt|aendert|laeuft|steht|stehen|"
    r"kommt|meldung|fund|funde|hilfe|loeschen|einfuegen|von|zu|im|am|als|"
    r"auch|nur|noch|schon|sonst|unbekannt|gefunden|fehlt|traegt|rumpf|"
    r"kopf|koepfe|anweisung|anweisungen|deklaration|bereich|zweig|klammer|"
    r"leer|leere|leerer|leeren|mehrdeutig|verschoben|veraltet|pruefen|bitte|"
    r"hier|dort|davor|dahinter|danach|darin|darueber|darunter|kette|vorlage|"
    r"aufruf|aufrufe|gemeldete|gemeldeten|unklar|lesbar|geschrieben|"
    r"schreibgeschuetzt|verfuegbar|eintraege|ersetzen|ersetzt|entfernen|"
    r"entfernt|eingefuegt|alle|allen|anderen|bewiesen|laut|liefert|liefern|"
    r"numerisch|terme|erwartet|zeichen|protokoll|lokale|lokalen|"
    r"implementierung|bereits|qualifiziert|reihenfolge|verschachtelte|"
    r"verdoppelte|binden|mitgelesen|konstante|konstanten|zuweisung|"
    r"zuweisungen|sperre|sperren|nichts|wie|bisher|bzw|mal|alte|altes|neu|"
    r"neue|neuer|erst|immer|wenn|weil|dann|denn|doch|sich|sie|er|es|wir|man|"
    r"dieser|diese|dieses|ohnehin|gilt|gelten|waere|wuerde|koennte|muss|"
    r"muesste|soll|sollte|darf|kann|koennen)\b"
    r"|\b\w*(ungen|keiten|heiten|lich|liche|lichen|ische|ischen|isch)\b",
    re.I)
# Deutsche Nomen auch als ENDE eines zusammengesetzten Worts - ohne \b
# davor (Nachpruefung FIX-C1, V-C1-1): '%d Routinenkoepfe', 'Formdateien',
# 'Include-Dateien', 'Ansi-Ergebnis', 'asm-Rumpf' trugen kein Wort der
# Liste als ganzes Wort und blieben still. Nur Nomen, auf die kein
# englisches Wort endet ('fund' fehlt: 'refund').
GERMAN_TAIL = re.compile(
    r"(datei|dateien|zeile|zeilen|spalte|spalten|kopf|koepfe|rumpf|ergebnis|"
    r"ergebnisse|puffer|platte|anweisung|deklaration|deklarationen|klammer|"
    r"klammern|konstante|konstanten|zuweisung|bereich|bereiche|zweig|zweige|"
    r"kette|ketten|vorlage|vorlagen|aufruf|aufrufe|meldung|eintrag|eintraege|"
    r"zeichen|schluessel|woerter|fehler)\b",
    re.I)
# Eine Zahl mit grossgeschriebenem Nomen ('%d Parameter', '%d Casts '): im
# Deutschen gross, in einer englischen msgid klein ('%d parameters') - so
# faellt ein Text auf, dessen Woerter es auch englisch gibt.
COUNT_NOUN = re.compile(r"%d [A-Z][a-z]{2,}")
# Umschriebene Umlaute ('Groesse ueberschritten'), nur in Folgen, die im
# Englischen nicht vorkommen: gemessen an 552.502 verschiedenen Woertern
# der 16.051 Pascal-Dateien des Realwelt-Korpus (nur deutsche Woerter bzw.
# Namen: zulaessig, Rueck, Gaertner) und an allen msgids (0). Gross/klein
# zaehlt: ohne sie trafen 56 Bezeichner wie 'AEngine', 'TAesSignature',
# 'WSAEHOSTDOWN' (Parameter, Typen, Konstanten). Weggelassen, weil englisch:
# oes (does), uer (query), ues (values), uen (sequence), uess (guess), uem
# (uEmptyBlock), oeff mitten im Wort (coefficient), ueb/uef/ueg/ueh
# (bluebar, valuefor, Bluegrass, valuehex), aend (metaend), aeb, oest.
TRANSCRIPTION = re.compile(
    r"[Aa]e(?:h|u|ng|ss|lt|rk|rt|gt|ch)|[Oo]e(?:ss|nn|sch|gl|pf|rt)"
    r"|[Uu]e(?:lt|nf|rz|tz|ck)|\b[Uu]eber|\b[Oo]eff")
UMLAUT = re.compile("[\u00e4\u00f6\u00fc\u00c4\u00d6\u00dc\u00df]")
WORD3 = re.compile(r"[A-Za-z\u00c0-\u00ff]{3,}")
CONST_NAME = re.compile(r"^[A-Z][A-Z0-9]*_[A-Z0-9_]*$")
HEX = set("0123456789abcdefABCDEF")
TWO_CHAR_SYMS = (":=", "<=", ">=", "<>", "..")
KINDS = ("unit", "const", "text", "regex", "call", "name")


def is_german(text):
    """Ein Wort aus drei Buchstaben und ein deutsches Wort (GERMAN, auch als
    Ende eines zusammengesetzten: GERMAN_TAIL), ein Umlaut, ein
    umschriebener Umlaut (TRANSCRIPTION) oder eine Zahl mit grossem Nomen
    (COUNT_NOUN). Das Leerzeichen der Inventar-Heuristik verlangt sie seit
    FIX-C1 nicht mehr: 'unbekannt' und 'Formdateien' standen als einzelnes
    Wort im Grund."""
    if WORD3.search(text) is None:
        return False
    return (GERMAN.search(text) is not None
            or GERMAN_TAIL.search(text) is not None
            or UMLAUT.search(text) is not None
            or TRANSCRIPTION.search(text) is not None
            or COUNT_NOUN.search(text) is not None)


# --------------------------------------------------------------------------
# Pascal-Leser
# --------------------------------------------------------------------------

def tokenize(text):
    """Tokens (art, wert, pos): 'str' (Literal, dekodiert), 'chr' (#13,
    #$0D), 'id' (Bezeichner), 'num', 'sym' (ein Zeichen bzw. ':=' '<='
    '>=' '<>' '..'). Kommentare und Direktiven ({..}, (*..*), //..) fallen
    weg - ein Apostroph darin ist kein Literal."""
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif c == "{":
            j = text.find("}", i + 1)
            i = n if j < 0 else j + 1
        elif text.startswith("(*", i):
            j = text.find("*)", i + 2)
            i = n if j < 0 else j + 2
        elif c == "'":
            j, buf = i + 1, []
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        buf.append("'")
                        j += 2
                        continue
                    j += 1
                    break
                if text[j] in "\r\n":       # offenes Literal: Zeilenende
                    break
                buf.append(text[j])
                j += 1
            toks.append(("str", "".join(buf), i))
            i = j
        elif c == "#":
            j = i + 1
            if j < n and text[j] == "$":
                j += 1
                s = j
                while j < n and text[j] in HEX:
                    j += 1
                code = int(text[s:j], 16) if j > s else None
            else:
                s = j
                while j < n and text[j].isdigit():
                    j += 1
                code = int(text[s:j]) if j > s else None
            toks.append(("chr", chr(code) if code is not None else "", i))
            i = j
        elif c.isalpha() or c == "_":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            toks.append(("id", text[i:j], i))
            i = j
        elif c.isdigit() or c == "$":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            toks.append(("num", text[i:j], i))
            i = j
        else:
            two = text[i:i + 2]
            if two in TWO_CHAR_SYMS:
                toks.append(("sym", two, i))
                i += 2
            else:
                toks.append(("sym", c, i))
                i += 1
    return toks


def is_lit(tok):
    return tok[0] in ("str", "chr")


def is_sym(tok, value):
    return tok[0] == "sym" and tok[1] == value


def chains_of(toks):
    """Literal-Ketten: (erstes, letztes Token, Text). 'a' 'b' direkt
    hintereinander ('a'#13'b') und 'a' + 'b' gehoeren zusammen."""
    out, k, n = [], 0, len(toks)
    while k < n:
        if not is_lit(toks[k]):
            k += 1
            continue
        start, parts = k, [toks[k][1]]
        while True:
            if k + 1 < n and is_lit(toks[k + 1]):
                k += 1
                parts.append(toks[k][1])
            elif (k + 2 < n and is_sym(toks[k + 1], "+")
                  and is_lit(toks[k + 2])):
                k += 2
                parts.append(toks[k][1])
            else:
                break
        out.append((start, k, "".join(parts)))
        k += 1
    return out


def first_arg_end(toks, k):
    """Index des ',' bzw. ')' hinter dem ersten Argument eines Aufrufs,
    dessen '(' bei k steht (Klammertiefe 0); len(toks) ohne Ende."""
    depth, j = 0, k + 1
    while j < len(toks):
        t = toks[j]
        if t[0] == "sym":
            if t[1] in ("(", "["):
                depth += 1
            elif t[1] in (")", "]"):
                if depth == 0:
                    return j
                depth -= 1
            elif t[1] == "," and depth == 0:
                return j
        j += 1
    return len(toks)


def matching_close(toks, k):
    """Index der Klammer, die die '(' bzw. '[' bei k schliesst; len(toks)
    ohne."""
    depth = 0
    for j in range(k, len(toks)):
        t = toks[j]
        if t[0] != "sym":
            continue
        if t[1] in ("(", "["):
            depth += 1
        elif t[1] in (")", "]"):
            depth -= 1
            if depth == 0:
                return j
    return len(toks)


def at_line_start(text, pos):
    line_start = text.rfind("\n", 0, pos) + 1
    return text[line_start:pos].strip() == ""


class Unit:
    """Eine Unit, gelesen: Tokens, Ketten, Konstanten, _()-Aufrufe."""

    def __init__(self, name, text):
        self.name = name
        self.text = text
        self.toks = tokenize(text)
        self.chains = chains_of(self.toks)
        self.line_starts = [0] + [m.end() for m in re.finditer("\n", text)]
        self.consts = {}       # NAME -> (erstes, letztes Token, rein?, Array?)
        self.msgid_calls = []  # (erstes, letztes Token) des 1. Arguments
        self.calls = {}        # name(klein) -> [(erstes, letztes Token)]
        self.const_uses = {}   # NAME -> 'scalar' / 'array' (in _())
        self.qualified = []    # Token-Index von '_' in X._(
        self.foreign = []      # (Token-Index, NAME) von _(NAME) ohne Wert
        self.dynamic = []      # (Token-Index, Argument) von _(<Ausdruck>)
        self._read_consts()
        self._read_calls()

    def line_of(self, pos):
        return bisect.bisect_right(self.line_starts, pos)

    def _read_consts(self):
        toks, n = self.toks, len(self.toks)
        for k, t in enumerate(toks):
            if t[0] != "id" or not at_line_start(self.text, t[2]):
                continue
            if k + 1 >= n:
                continue
            j = k + 1
            is_array = False
            if is_sym(toks[j], ":"):
                j += 1
                if j < n and toks[j][0] == "id" and toks[j][1].lower() == "array":
                    is_array = True
                while j < n and not is_sym(toks[j], "=") and not is_sym(toks[j], ";"):
                    j += 1
            if j >= n or not is_sym(toks[j], "="):
                continue
            v = j + 1
            if is_array:
                if v >= n or not is_sym(toks[v], "("):
                    continue
                end = first_arg_end(toks, v)
                while end < n and is_sym(toks[end], ","):
                    end = first_arg_end(toks, end)
                pure = self._pure_list(v + 1, end)
                self.consts.setdefault(t[1], (v, end, pure, True))
            else:
                if v >= n or not is_lit(toks[v]):
                    continue
                e = v
                while e < n and not is_sym(toks[e], ";"):
                    e += 1
                pure = any(c[0] == v and c[1] == e - 1 for c in self.chains)
                self.consts.setdefault(t[1], (v, e - 1, pure, False))

    def _pure_list(self, first, close):
        """Jedes Element zwischen first und close ist genau eine Kette."""
        starts = {c[0]: c[1] for c in self.chains}
        k = first
        while k < close:
            if k not in starts:
                return False
            k = starts[k] + 1
            if k < close and not is_sym(self.toks[k], ","):
                return False
            k += 1
        return True

    def _read_calls(self):
        toks, n = self.toks, len(self.toks)
        for k, t in enumerate(toks):
            if t[0] != "id" or k + 1 >= n or not is_sym(toks[k + 1], "("):
                continue
            prev = toks[k - 1] if k > 0 else ("sym", "", 0)
            end = first_arg_end(toks, k + 1)
            span = (k + 2, end - 1)
            self.calls.setdefault(t[1].lower(), []).append(span)
            if t[1] != "_":
                continue
            if prev[0] == "id" and prev[1].lower() in ("function", "procedure"):
                continue
            if is_sym(prev, "."):
                self.qualified.append(k)
                continue
            self.msgid_calls.append(span)
            self._read_msgid_arg(k, span)

    def _read_msgid_arg(self, k, span):
        """Das erste Argument von _(..) wie tools/i18n_extract.py: eine
        Literal-Kette (die msgid selbst), _(NAME) bzw. _(NAME, [..]) mit
        einer msgid-Konstante und _(NAME[i]) mit einem msgid-Array dieser
        Unit (const_uses). Ein Konstanten-Name ohne reinen Wert hier ist
        'fremd', jedes andere Argument 'dynamisch'."""
        first, last = span
        toks = self.toks
        if any(c[0] == first and c[1] == last for c in self.chains):
            return
        kind = None
        if first <= last and toks[first][0] == "id":
            if first == last:
                kind = "scalar"
            elif is_sym(toks[first + 1], "[") and matching_close(toks, first + 1) == last:
                kind = "array"
        if kind:
            name = toks[first][1]
            const = self.consts.get(name)
            if const and const[2] and const[3] == (kind == "array"):
                self.const_uses[name] = kind
                return
            if CONST_NAME.match(name):
                self.foreign.append((k, name))
                return
        self.dynamic.append((k, self._source_of(first, last)))

    def _source_of(self, first, last):
        """Der Quelltext der Tokens first..last, Leerraum zu einem
        Leerzeichen - so steht ein dynamisches Argument im Fund und in
        einer Ausnahme 'name'."""
        if first > last:
            return ""
        end = self.toks[last + 1][2] if last + 1 < len(self.toks) else len(self.text)
        return " ".join(self.text[self.toks[first][2]:end].split())


def in_spans(chain, spans):
    return any(a <= chain[0] and chain[1] <= b for a, b in spans)


# --------------------------------------------------------------------------
# Ausnahmeliste
# --------------------------------------------------------------------------

class AllowEntry:
    def __init__(self, line_no, unit, kind, value, reason):
        self.line_no, self.unit, self.kind = line_no, unit, kind
        self.value, self.reason, self.hits = value, reason, 0
        self.rx = re.compile(value) if kind == "regex" else None

    def label(self):
        return "%s | %s %s" % (self.unit, self.kind, self.value)


def read_allow(path):
    """Eintraege '<Unit.pas|*> | <art> <wert> | <Begruendung>'; Fehler als
    Liste von Texten (Exit 2)."""
    entries, errors = [], []
    if not path.exists():
        return entries, ["Ausnahmeliste fehlt: %s" % path]
    for no, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(" | ", 1)
        if len(parts) != 2 or " | " not in parts[1]:
            errors.append("%s:%d: Format '<Unit> | <art> <wert> | <Begruendung>'"
                          % (path.name, no))
            continue
        unit = parts[0].strip()
        kindval, reason = parts[1].rsplit(" | ", 1)
        kind, _, value = kindval.strip().partition(" ")
        if kind not in KINDS:
            errors.append("%s:%d: unbekannte Art %r (%s)" % (path.name, no, kind, "/".join(KINDS)))
            continue
        if not reason.strip():
            errors.append("%s:%d: Eintrag ohne Begruendung" % (path.name, no))
            continue
        if kind != "unit" and not value.strip():
            errors.append("%s:%d: %s ohne Wert" % (path.name, no, kind))
            continue
        if unit == "*" and kind in ("unit", "const", "name"):
            errors.append("%s:%d: '*' nur mit text/regex/call" % (path.name, no))
            continue
        try:
            entries.append(AllowEntry(no, unit, kind, value.strip(), reason.strip()))
        except re.error as exc:
            errors.append("%s:%d: Regex %r: %s" % (path.name, no, value, exc))
    return entries, errors


def allowed(unit, chain, entries):
    """Der erste Eintrag, der die Kette freistellt (zaehlt seinen Treffer)."""
    for e in entries:
        if e.unit not in ("*", unit.name):
            continue
        hit = False
        if e.kind == "unit":
            hit = True
        elif e.kind == "const":
            c = unit.consts.get(e.value)
            hit = c is not None and c[0] <= chain[0] and chain[1] <= c[1]
        elif e.kind == "text":
            hit = chain[2] == e.value
        elif e.kind == "regex":
            hit = e.rx.search(chain[2]) is not None
        elif e.kind == "call":
            hit = in_spans(chain, unit.calls.get(e.value.lower(), []))
        if hit:
            e.hits += 1
            return e
    return None


def allowed_name(unit, value, entries):
    """Ausnahme fuer einen Fund ohne Kette (qualif/fremd/dynamisch): Art
    'name' mit dem gemeldeten Namen bzw. Argument."""
    for e in entries:
        if e.unit in ("*", unit.name) and e.kind == "name" and e.value == value:
            e.hits += 1
            return e
    return None


# --------------------------------------------------------------------------
# Pruefung
# --------------------------------------------------------------------------

def check_unit(unit, entries):
    """Funde (Zeile, Art, Text) einer Unit."""
    found = []
    msgid_spans = list(unit.msgid_calls)
    for name, kind in unit.const_uses.items():
        c = unit.consts[name]
        msgid_spans.append((c[0], c[1]))
    for chain in unit.chains:
        if not is_german(chain[2]):
            continue
        art = "msgid" if in_spans(chain, msgid_spans) else "text"
        if allowed(unit, chain, entries):
            continue
        found.append((unit.line_of(unit.toks[chain[0]][2]), art, chain[2]))
    for k in unit.qualified:
        q = unit.toks[k - 2][1] + "._" if k >= 2 else "._"
        if not allowed_name(unit, q, entries):
            found.append((unit.line_of(unit.toks[k][2]), "qualif", q))
    for k, name in unit.foreign:
        if not allowed_name(unit, name, entries):
            found.append((unit.line_of(unit.toks[k][2]), "fremd", name))
    for k, arg in unit.dynamic:
        if not allowed_name(unit, arg, entries):
            found.append((unit.line_of(unit.toks[k][2]), "dynamisch", arg))
    return sorted(found)


def read_units(src_dir, only=None):
    units = []
    for path in sorted(src_dir.glob("*.pas")):
        if only and path.name.lower() not in only:
            continue
        units.append(Unit(path.name, path.read_text(encoding="utf-8-sig", errors="replace")))
    return units


def run_check(src_dir, allow_path, only=None):
    """(Funde je Unit, unbenutzte Eintraege, Fehler der Liste). Mit only
    (Teilmenge der Units) zaehlen nur die Eintraege dieser Units als tot -
    ob ein '*'-Eintrag woanders trifft, sieht ein Teillauf nicht."""
    entries, errors = read_allow(allow_path)
    units = read_units(src_dir, only)
    result = {u.name: check_unit(u, entries) for u in units}
    names = {u.name for u in units}
    unused = [e for e in entries if e.hits == 0
              and (not only or e.unit in names)]
    return result, unused, errors


def short(text, width=100):
    text = text.replace("\r", "\\r").replace("\n", "\\n")
    return text if len(text) <= width else text[:width - 3] + "..."


def gate(argv_units):
    only = {u.lower() for u in argv_units} if argv_units else None
    result, unused, errors = run_check(SRC_DIR, ALLOW_FILE, only)
    if errors:
        for e in errors:
            print(e)
        return 2
    if only and not result:
        print("keine dieser Units in %s: %s" % (SRC_DIR, ", ".join(sorted(only))))
        return 2
    total = 0
    for name, found in result.items():
        for line, art, text in found:
            print("reDelphix/source/%s:%d: [%s] %s" % (name, line, art, short(text)))
        total += len(found)
    for e in unused:
        print("tools/%s:%d: [ausnahme] trifft nichts mehr: %s"
              % (ALLOW_FILE.name, e.line_no, e.label()))
    bad = total + len(unused)
    if bad:
        units = sum(1 for f in result.values() if f)
        print("\nGATE ROT: %d deutsche bzw. unuebersetzte Text(e) in %d Unit(s), "
              "%d tote Ausnahme(n) - Muster in reDelphix/README.md, Abschnitt "
              "\"Texte umstellen\"." % (total, units, len(unused)))
        return 1
    print("GATE GRUEN: %d Unit(s) ohne deutschen Text ausserhalb der .po." % len(result))
    return 0


def report():
    result, unused, errors = run_check(SRC_DIR, ALLOW_FILE)
    if errors:
        for e in errors:
            print(e)
        return 2
    rows = sorted(result.items(), key=lambda x: (-len(x[1]), x[0]))
    total = sum(len(f) for f in result.values())
    print("Stand je Unit (Funde: text / msgid / qualif / fremd / dynamisch):")
    for name, found in rows:
        if not found:
            continue
        arts = [sum(1 for f in found if f[1] == a)
                for a in ("text", "msgid", "qualif", "fremd", "dynamisch")]
        print("  %4d  %-26s %s" % (len(found), name, " / ".join(str(a) for a in arts)))
    clean = [n for n, f in rows if not f]
    print("  ohne Fund: %d Unit(s)%s" % (len(clean), (" - " + ", ".join(clean)) if clean else ""))
    print("Summe: %d Fund(e) in %d Unit(s); tote Ausnahmen: %d"
          % (total, sum(1 for f in result.values() if f), len(unused)))
    for e in unused:
        print("  tote Ausnahme Zeile %d: %s" % (e.line_no, e.label()))
    return 0


# --------------------------------------------------------------------------
# Selbsttest
# --------------------------------------------------------------------------

BASE_UNIT = """unit uRdxProbe;

interface

implementation

uses
  uRdxText, uRdxLog;

const
  R_GOOD = 'end of the statement ' + 'not found';
  CAPTIONS: array[0..1] of string = ('Show location', 'Hide location');
  KEY_MSG = 'Comment at column ';
  // die Zeile ist ein Kommentar - kein Text
  { ein Apostroph ' im Kommentar und noch einer ' }

function Probe(I: Integer): string;
begin
  Result := _('no valid range');
  Result := _(R_GOOD);
  Result := _(CAPTIONS[I]);
  Result := _('line %d to %d', [1, 2]);
  RdxLog('Protokoll: die Zeile ist leer');
  if Pos(KEY_MSG, Result) > 0 then
    Result := 'raise ENotImplemented.Create(''x'');';
end;

end.
"""

ALLOW_BASE = "# Selbsttest\n* | call RdxLog | Protokoll\n"
GERMAN_CONST = "'Ende der Anweisung ' + 'nicht gefunden'"
ENGLISH_CONST = "'end of the statement ' + 'not found'"
RAISE_LIT = "'raise ENotImplemented.Create(''x'');'"


def _probe(unit_text, allow_text):
    """(Arten der Funde sortiert, Zahl toter Ausnahmen, Fehler?) fuer eine
    Probe-Unit in einem eigenen Temp-Verzeichnis."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="rdx_i18n_gate_"))
    try:
        (tmp / "uRdxProbe.pas").write_text(unit_text, encoding="utf-8")
        allow = tmp / "probe.allow"
        allow.write_text(allow_text, encoding="utf-8")
        result, unused, errors = run_check(tmp, allow)
        arts = sorted(f[1] for f in result.get("uRdxProbe.pas", []))
        return arts, len(unused), bool(errors)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _mutants():
    """(Name, Unit-Text, Ausnahmeliste, erwartete Arten, tote Ausnahmen,
    Listenfehler?) - Mutanten muessen mit IHRER Art auffallen, gutartige
    Abwandlungen nicht."""
    b, a = BASE_UNIT, ALLOW_BASE
    return [
        ("Grundform", b, a, [], 0, False),
        ("_() entfernt", b.replace("_('no valid range')", "'kein gueltiger Bereich'"), a, ["text"], 0, False),
        ("deutsche msgid", b.replace("_('no valid range')", "_('kein gueltiger Bereich')"), a, ["msgid"], 0, False),
        ("deutsche msgid-Konstante", b.replace(ENGLISH_CONST, GERMAN_CONST), a, ["msgid"], 0, False),
        ("Konstante ohne _()", b.replace("_(R_GOOD)", "R_GOOD").replace(ENGLISH_CONST, GERMAN_CONST), a, ["text"], 0, False),
        ("Konstante mit Bezeichner im Wert",
         b.replace("R_GOOD = " + ENGLISH_CONST, "R_GOOD = KEY_MSG + 'und dann Ende der Anweisung'"),
         a, ["fremd", "text"], 0, False),
        ("Array ohne _()", b.replace("_(CAPTIONS[I])", "CAPTIONS[I]").replace("'Hide location'", "'Stelle nicht zeigen'"), a, ["text"], 0, False),
        ("Format ohne _()", b.replace("_('line %d to %d', [1, 2])", "Format('Zeile %d bis %d', [1, 2])"), a, ["text"], 0, False),
        ("Umlaut", b.replace(RAISE_LIT, "'Fehler \u00fcberall'"), a, ["text"], 0, False),
        ("Kette ueber Zeilen", b.replace("_('no valid range')", "'kein ' +\n    'gueltiger Bereich'"), a, ["text"], 0, False),
        ("deutsch als Format-Argument", b.replace("[1, 2]", "[1, 'die Zeile']"), a, ["text"], 0, False),
        ("qualifizierter Aufruf", b.replace("_('no valid range')", "uRdxText._('no valid range')"), a, ["qualif"], 0, False),
        ("Konstante einer anderen Unit", b.replace("_(R_GOOD)", "_(R_ELSEWHERE)"), a, ["fremd"], 0, False),
        # Nachpruefung FIX-C1, V-C1-1: Texte ohne Wort der Liste bzw. ohne
        # Leerzeichen - und gutartige Code-Woerter, die still bleiben.
        ("Zahl mit Kompositum", b.replace(RAISE_LIT, "'%d Routinenkoepfe'"), a, ["text"], 0, False),
        ("Kompositum ohne Leerzeichen", b.replace(RAISE_LIT, "'Formdateien'"), a, ["text"], 0, False),
        ("Kompositum mit Bindestrich", b.replace(RAISE_LIT, "'Ansi-Ergebnis'"), a, ["text"], 0, False),
        ("ein Wort der Liste", b.replace(RAISE_LIT, "'unbekannt'"), a, ["text"], 0, False),
        ("umschriebene Umlaute", b.replace(RAISE_LIT, "'Groesse ueberschritten'"), a, ["text"], 0, False),
        ("Zahl mit grossem Nomen", b.replace(RAISE_LIT, "Format('%d Parameter', [I])"), a, ["text"], 0, False),
        ("Code-Woerter bleiben still",
         b.replace(RAISE_LIT, "'%d begin' + IntToStr(I) + 'Default()' + I.ToString + '%d declarations'"),
         a, [], 0, False),
        # V-C1-2: Argumente von _(), die der Extraktor still uebergeht.
        ("Parameter als msgid", b.replace("_('no valid range')", "_(AWhat)"), a, ["dynamisch"], 0, False),
        ("Format in _()", b.replace("_('no valid range')", "_(Format('no range in line %d', [I]))"),
         a, ["dynamisch"], 0, False),
        ("Kette mit Ausdruck in _()", b.replace("_('no valid range')", "_('no range ' + IntToStr(I))"),
         a, ["dynamisch"], 0, False),
        ("Array mit Ausdruck in _()", b.replace("_(CAPTIONS[I])", "_(CAPTIONS[I] + ' ')"),
         a, ["dynamisch"], 0, False),
        ("Ausnahme name fuer dynamisch", b.replace("_('no valid range')", "_(AWhat)"),
         a + "uRdxProbe.pas | name AWhat | Probe\n", [], 0, False),
        ("Protokoll ohne Ausnahme", b, "# leer\n", ["text"], 0, False),
        ("tote Ausnahme", b, a + "uRdxProbe.pas | text gibt es nicht | Probe\n", [], 1, False),
        ("deutsch im Kommentar", b.replace("// die Zeile", "// die Zeile ist nicht 'kein Text' und"), a, [], 0, False),
        ("Ausnahme text", b.replace("_('no valid range')", "'kein gueltiger Bereich'"),
         a + "uRdxProbe.pas | text kein gueltiger Bereich | Probe\n", [], 0, False),
        ("Ausnahme const", b.replace("_(R_GOOD)", "R_GOOD").replace(ENGLISH_CONST, GERMAN_CONST),
         a + "uRdxProbe.pas | const R_GOOD | Probe\n", [], 0, False),
        ("Ausnahme unit", b.replace("_('no valid range')", "'kein gueltiger Bereich'"),
         a + "uRdxProbe.pas | unit | Probe\n", [], 0, False),
        ("Ausnahme regex", b.replace("_('no valid range')", "'kein gueltiger Bereich'"),
         a + "* | regex ^kein g | Probe\n", [], 0, False),
        ("Ausnahme name", b.replace("_(R_GOOD)", "_(R_ELSEWHERE)"),
         a + "uRdxProbe.pas | name R_ELSEWHERE | Probe\n", [], 0, False),
        ("Ausnahme ohne Begruendung", b, a + "uRdxProbe.pas | unit | \n", None, 0, True),
        ("Ausnahme mit unbekannter Art", b, a + "uRdxProbe.pas | zeile 12 | Probe\n", None, 0, True),
    ]


def selftest():
    ok = True
    for name, unit_text, allow_text, arts, dead, err in _mutants():
        got_arts, got_dead, got_err = _probe(unit_text, allow_text)
        if err:
            good = got_err
        else:
            good = not got_err and got_arts == arts and got_dead == dead
        if not good:
            print("SELFTEST FEHLER: %s - Arten %r (erwartet %r), tote Ausnahmen %d "
                  "(erwartet %d), Listenfehler %s" % (name, got_arts, arts, got_dead, dead, got_err))
            ok = False
    german = ("kein gueltiger Bereich", "%d Routinenkoepfe", "Formdateien",
              "Include-Dateien", "asm-Rumpf", "unbekannt", "%d Parameter",
              "Groesse ueberschritten", "Rueckgabe")
    english = ("Comment at column ", "%d begin", "unassigned", "Default()",
               "%d declarations of %s in classes of this name - overload?",
               "Remove the cast to %s before Free", "Parameter",
               "the coefficient does not match the query values", "blueberry",
               "AEngine", "TAesSignature")
    wrong = ([t for t in german if not is_german(t)]
             + [t for t in english if is_german(t)])
    if wrong:
        print("SELFTEST FEHLER: Heuristik is_german bei %r" % wrong)
        ok = False
    print("SELFTEST %s (%d Faelle)" % ("GRUEN" if ok else "ROT", len(_mutants())))
    return 0 if ok else 1


def main(argv):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", newline="\n")
    if argv == ["--selftest"]:
        return selftest()
    if argv == ["--report"]:
        return report()
    if argv and argv[0] == "--unit" and len(argv) > 1:
        return gate(argv[1:])
    if argv:
        print(__doc__)
        return 2
    return gate(None)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
