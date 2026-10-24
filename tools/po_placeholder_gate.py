"""Gate: Format-Platzhalter in i18n/*.po stimmen zwischen msgid und msgstr.

WARUM (2026-10-15): die Oberflaeche uebersetzt Texte mit _() und formatiert
sie danach mit Format(). Traegt eine Uebersetzung einen anderen Platzhalter
als die msgid ('%d' statt '%s', einer zu wenig, Tippfehler '%z'), wirft
Format zur Laufzeit EConvertError - im Birnen- oder Kontextmenue der IDE,
also mitten in der Arbeit des Nutzers. Fuer fr.po gibt es keinen Test, der
die Uebersetzungen ausfuehrt; der Fehler fiele erst beim Kunden auf. Dieses
Gate prueft jede uebersetzte Zeile jeder ausgelieferten .po statisch.

Regel (Delphi-Format: '%' [Index ':'] ['-'] [Breite] ['.' Genauigkeit] Typ,
Typen d u e f g n m p s x, '%%' = Prozentzeichen):
  * ohne Index-Angaben muss die FOLGE der Typen gleich sein - Format nimmt
    die Argumente der Reihe nach;
  * mit Index-Angaben ('%1:s') muss jeder Index denselben Typ tragen und
    jeder Index der msgid in der msgstr vorkommen (umgestellte Satzglieder
    sind dann erlaubt);
  * Breite und Genauigkeit duerfen abweichen (Darstellung, kein Typfehler);
  * '%%' zaehlt nicht als Platzhalter.
Eine leere msgstr bedeutet "nicht uebersetzt" und wird uebersprungen (die
Oberflaeche zeigt dann die msgid - das prueft tools/i18n_audit.sh).

Aufruf:
  python tools/po_placeholder_gate.py             # alle i18n/*.po
  python tools/po_placeholder_gate.py --selftest  # Mutanten gegen den Pruefer
Exit 0 = alles passt, 1 = Abweichungen (Liste), 2 = Aufruffehler.
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
PO_DIR = REPO / "i18n"

# '%' [Index ':'] ['-'] [Breite|'*'] ['.' Genauigkeit|'*'] Typ
SPEC = re.compile(r"%(?:(\d+|\*):)?-?(?:\d+|\*)?(?:\.(?:\d+|\*))?([duefgnmpsxDUEFGNMPSX])")
ANY_PERCENT = re.compile(r"%(?!%)")


def unescape(s):
    """Die C-Escapes der .po-Datei (\\n, \\t, \\", \\\\) aufloesen."""
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, "\\" + nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_po(text):
    """Liste (Zeilennummer, msgid, msgstr) - mehrzeilige Eintraege werden
    zusammengesetzt, Kommentare und msgctxt ueberlesen."""
    entries, cur, field = [], None, None
    for no, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if line.startswith("#") or not line:
            if cur and "msgstr" in cur:
                entries.append((cur["line"], cur["msgid"], cur["msgstr"]))
                cur = None
            field = None
            continue
        m = re.match(r'(msgid|msgstr|msgctxt)\s+"(.*)"$', line)
        if m:
            key, val = m.group(1), m.group(2)
            if key == "msgid":
                if cur and "msgstr" in cur:
                    entries.append((cur["line"], cur["msgid"], cur["msgstr"]))
                cur = {"line": no, "msgid": val}
            elif cur is not None:
                cur[key] = val
            field = key
            continue
        if line.startswith('"') and line.endswith('"') and cur is not None and field:
            cur[field] = cur.get(field, "") + line[1:-1]
    if cur and "msgstr" in cur:
        entries.append((cur["line"], cur["msgid"], cur["msgstr"]))
    return [(no, unescape(a), unescape(b)) for no, a, b in entries]


def specs_of(text):
    """Platzhalter eines Texts als Liste (Index oder None, Typ klein).
    '%%' wird vorher entfernt."""
    cleaned = text.replace("%%", "")
    found = [(m.group(1), m.group(2).lower()) for m in SPEC.finditer(cleaned)]
    # ein '%', das zu keinem gueltigen Platzhalter gehoert (Tippfehler '%z',
    # abgeschnittenes '%' am Ende) loest in Format ebenfalls EConvertError aus
    stray = len(ANY_PERCENT.findall(cleaned)) - len(found)
    return found, stray


def compare(msgid, msgstr):
    """'' wenn die Platzhalter vertraeglich sind, sonst der Grund."""
    a, stray_a = specs_of(msgid)
    b, stray_b = specs_of(msgstr)
    if stray_b > stray_a:
        return "ungueltiges '%' in der Uebersetzung"
    indexed = any(i is not None and i != "*" for i, _ in a + b)
    if not indexed:
        ta, tb = [t for _, t in a], [t for _, t in b]
        if ta != tb:
            return "Platzhalter-Folge %s statt %s" % ("".join("%" + t for t in tb) or "(keine)",
                                                       "".join("%" + t for t in ta) or "(keine)")
        return ""
    # mit Index: jeder Index -> Typ; Platzhalter ohne Index zaehlen weiter
    def mapping(specs):
        res, nxt = {}, 0
        for idx, typ in specs:
            if idx is None or idx == "*":
                k = nxt
            else:
                k = int(idx)
            res.setdefault(k, set()).add(typ)
            nxt = k + 1
        return res
    ma, mb = mapping(a), mapping(b)
    if set(ma) != set(mb):
        return "Argument-Indizes %s statt %s" % (sorted(mb), sorted(ma))
    for k in ma:
        if ma[k] != mb[k]:
            return "Argument %d: %s statt %s" % (k, "/".join(sorted(mb[k])), "/".join(sorted(ma[k])))
    return ""


def check_file(path):
    text = path.read_text(encoding="utf-8-sig")
    problems = []
    for no, msgid, msgstr in parse_po(text):
        if not msgid or not msgstr:
            continue
        why = compare(msgid, msgstr)
        if why:
            problems.append((no, msgid, msgstr, why))
    return problems


def run(paths):
    total = 0
    for p in paths:
        probs = check_file(p)
        for no, msgid, msgstr, why in probs:
            print("%s:%d: %s" % (p.relative_to(REPO), no, why))
            print("    msgid : %s" % msgid[:120])
            print("    msgstr: %s" % msgstr[:120])
        total += len(probs)
    if total:
        print("\nGATE ROT: %d Uebersetzung(en) mit abweichenden Format-Platzhaltern - "
              "Format() wuerde zur Laufzeit EConvertError werfen." % total)
        return 1
    print("GATE GRUEN: %d .po-Datei(en), alle Format-Platzhalter passen." % len(paths))
    return 0


def selftest():
    """Mutanten gegen compare(): jeder muss mit SEINEM Grund rot werden,
    die gutartigen Faelle gruen bleiben."""
    good = [
        ("Delete unused routine %s", "Ungenutzte Routine %s loeschen"),
        ("%d of %d", "%d von %d"),
        ("Line %d: %s", "Zeile %d: %s"),
        ("100%% done", "100%% fertig"),
        ("%1:s before %0:s", "%0:s nach %1:s"),
        ("%-10s|%5.2f", "%s|%f"),
        ("no placeholder", "kein Platzhalter"),
    ]
    bad = [
        (("Delete %s", "%d loeschen"), "Platzhalter-Folge"),
        (("%d of %d", "%d von"), "Platzhalter-Folge"),
        (("Line %d: %s", "%s: Zeile %d"), "Platzhalter-Folge"),
        (("Value %s", "Wert %z"), "ungueltiges"),
        (("Value %s", "Wert %s %"), "ungueltiges"),
        (("%1:s before %0:s", "%0:s nach %1:d"), "Argument 1"),
        (("%1:s before %0:s", "%0:s nach"), "Argument-Indizes"),
    ]
    ok = True
    for a, b in good:
        why = compare(a, b)
        if why:
            print("SELFTEST FEHLER: gutartig, aber rot: %r -> %r (%s)" % (a, b, why))
            ok = False
    for (a, b), expect in bad:
        why = compare(a, b)
        if expect not in why:
            print("SELFTEST FEHLER: Mutante nicht erkannt: %r -> %r (erwartet %r, war %r)"
                  % (a, b, expect, why))
            ok = False
    sample = 'msgid "A %s"\nmsgstr ""\n"B %d"\n\nmsgid ""\n"multi %s"\nmsgstr "x %s"\n'
    parsed = parse_po(sample)
    if [(m, s) for _, m, s in parsed] != [("A %s", "B %d"), ("multi %s", "x %s")]:
        print("SELFTEST FEHLER: Leser fuer mehrzeilige Eintraege: %r" % parsed)
        ok = False
    print("SELFTEST %s" % ("GRUEN" if ok else "ROT"))
    return 0 if ok else 1


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if argv:
        print(__doc__)
        return 2
    paths = sorted(PO_DIR.glob("*.po"))
    if not paths:
        print("keine i18n/*.po gefunden", file=sys.stderr)
        return 2
    return run(paths)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
