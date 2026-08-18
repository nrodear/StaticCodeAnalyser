#!/usr/bin/env bash
# i18n_audit.sh - Vergleicht die Quell-Strings aus i18n/template.pot gegen
# die msgids JEDER ausgelieferten i18n/<code>.po. Liefert je Sprache die
# Liste fehlender und toter Eintraege.
#
# template.pot ist die massgebliche Quell-String-Liste; erzeugt wird sie von
# tools/i18n_extract.py. Dieses Skript extrahiert NICHT selbst - siehe die
# Begruendung an der Lese-Stelle weiter unten.
#
# Nutzung:
#   tools/i18n_audit.sh                  # Zusammenfassung, alle Sprachen
#   tools/i18n_audit.sh --missing [de]   # nur fehlende Strings
#   tools/i18n_audit.sh --dead    [de]   # nur tote Eintraege
#   tools/i18n_audit.sh --json           # maschinenlesbar, alle Sprachen
#
# EXIT-CODE: 0 wenn in KEINER Sprache ein Quell-String fehlt; 1 bei
# fehlenden Strings; 2 bei Aufruffehlern (template.pot fehlt oder leer).
# Tote Eintraege werden berichtet, schlagen aber NICHT fehl. Grund: ein
# fehlender String ist ein sichtbarer Mangel - die Oberflaeche faellt still
# auf Englisch zurueck. Ein toter Eintrag kostet nur ein paar Byte. Solange
# beides denselben Exit-Code ausloeste, stand das Gate wegen ~290
# Alt-Eintraegen aus der GDeMap-Seed-Migration dauerhaft auf rot - und ein
# Gate, das immer rot ist, wird nicht gelesen.
#
# CI-tauglich; siehe Audit_AllDetectors.md V4.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# 1. Source-Strings kommen aus i18n/template.pot - NICHT mehr aus einer
#    eigenen grep-Extraktion.
#
#    WARUM (2026-08-18): die alte Zeile lief mit `grep -roh` ueber
#    StaticCodeAnalyserForm/sources und StaticCodeAnalyserIDE, und zwar
#    OHNE Dateityp-Filter. Damit las sie Delphis __history/-Sicherungen
#    und .bak2/.bak3-Dateien mit. Von 329 gemeldeten Quell-Strings waren
#    111 Phantome aus alten Fassungen - 34 %. Das Gate meldete Strings,
#    die es im Quelltext gar nicht mehr gibt, stand deshalb dauerhaft auf
#    Exit 1 und wurde folgerichtig ignoriert. Zugleich sah es NUR diese
#    zwei Verzeichnisse und verpasste die _()-Strings aus SCA.Engine und
#    SCA.SharedUI.
#
#    tools/i18n_extract.py macht beides richtig (SOURCE_SUFFIXES auf
#    .pas/.dpr/.dpk/.inc, EXCLUDED_DIRS mit __history) und schreibt das
#    Ergebnis nach i18n/template.pot. Diese Datei IST die Liste der
#    Quell-Strings. Sie hier ein zweites Mal nachzubauen war die Ursache
#    der Drift - zwei Extraktionen, die auseinanderlaufen koennen.
#
#    VORAUSSETZUNG: template.pot ist aktuell. Nach Aenderungen an
#    _()-Strings zuerst `python tools/i18n_extract.py` laufen lassen.
pot_file="$repo_root/i18n/template.pot"
if [ ! -f "$pot_file" ]; then
  echo "i18n/template.pot fehlt - erst 'python tools/i18n_extract.py' laufen lassen." >&2
  exit 2
fi
# tr -d CR ZUERST: auf ubuntu-Runnern checkt .gitattributes die .po mit
# CRLF aus, die .pot ohne - mit \r im Zeilenrest matcht weder das
# sed-Muster noch spaeter comm, und das Gate stand in CI dauerhaft auf
# Exit 1 (531 Phantom-Missing je Sprache), waehrend es lokal unter
# Git-Bash gruen war. sed '/^$/d' statt 'grep -v': grep liefert rc 1,
# wenn es nichts auswaehlt, und risse unter pipefail das ganze Skript.
grep -E '^msgid "' "$pot_file" \
  | tr -d '\r' \
  | sed -E 's/^msgid "(.*)"$/\1/' \
  | sed 's/\\"/"/g; s/\\\\/\\/g' \
  | sed '/^$/d' | sort -u > "$tmp_dir/src.txt"
src_count=$(wc -l < "$tmp_dir/src.txt")
if [ "$src_count" -eq 0 ]; then
  echo "template.pot enthaelt keine msgids - erst 'python tools/i18n_extract.py' laufen lassen." >&2
  exit 2
fi

# 2. msgids je Sprache. po-Format escaped Quotes als `\"`; nach dem
#    Strippen der aeusseren Quotes wird `\"` zurueck zu `"` normalisiert,
#    sonst gibt's False-Positives gegen die unmaskierten Source-Strings.
#    en.po traegt nur den Header - Englisch ist die Quellsprache und
#    braucht keine Eintraege.
langs=()
for po in "$repo_root"/i18n/*.po; do
  code="$(basename "$po" .po)"
  [ "$code" = "en" ] && continue
  grep -E '^msgid "' "$po" \
    | tr -d '\r' \
    | sed -E 's/^msgid "(.*)"$/\1/' \
    | sed 's/\\"/"/g; s/\\\\/\\/g' \
    | sed '/^$/d' | sort -u > "$tmp_dir/$code.txt"
  langs+=("$code")
done

missing_total=0
mode="${1:-}"
want="${2:-}"

for code in "${langs[@]}"; do
  m=$(comm -23 "$tmp_dir/src.txt" "$tmp_dir/$code.txt" | wc -l)
  missing_total=$((missing_total + m))
done

case "$mode" in
  --missing|--dead)
    for code in "${langs[@]}"; do
      if [ -n "$want" ] && [ "$want" != "$code" ]; then continue; fi
      if [ ${#langs[@]} -gt 1 ] && [ -z "$want" ]; then printf '## %s\n' "$code"; fi
      if [ "$mode" = "--missing" ]; then
        comm -23 "$tmp_dir/src.txt" "$tmp_dir/$code.txt"
      else
        comm -13 "$tmp_dir/src.txt" "$tmp_dir/$code.txt"
      fi
    done
    ;;
  --json)
    printf '{"source":%d,"languages":{' "$src_count"
    sep=""
    for code in "${langs[@]}"; do
      n=$(wc -l < "$tmp_dir/$code.txt")
      m=$(comm -23 "$tmp_dir/src.txt" "$tmp_dir/$code.txt" | wc -l)
      d=$(comm -13 "$tmp_dir/src.txt" "$tmp_dir/$code.txt" | wc -l)
      printf '%s"%s":{"msgids":%d,"missing":%d,"dead":%d}' \
        "$sep" "$code" "$n" "$m" "$d"
      sep=","
    done
    printf '}}\n'
    ;;
  *)
    printf "Source unique _()-strings:  %4d\n\n" "$src_count"
    printf "%-6s %8s %8s %8s %9s\n" "Lang" "msgids" "missing" "dead" "coverage"
    for code in "${langs[@]}"; do
      n=$(wc -l < "$tmp_dir/$code.txt")
      m=$(comm -23 "$tmp_dir/src.txt" "$tmp_dir/$code.txt" | wc -l)
      d=$(comm -13 "$tmp_dir/src.txt" "$tmp_dir/$code.txt" | wc -l)
      if [ "$src_count" -gt 0 ]; then
        pct=$(( (src_count - m) * 100 / src_count ))
      else
        pct=100
      fi
      printf "%-6s %8d %8d %8d %8d%%\n" "$code" "$n" "$m" "$d" "$pct"
    done
    if [ "$missing_total" -gt 0 ]; then
      printf "\nFehlende Strings mit --missing [lang] auflisten.\n"
    else
      printf "\nAlle Quell-Strings sind in jeder Sprache belegt.\n"
    fi
    printf "Tote Eintraege (--dead) sind folgenlos und lassen das Gate gruen.\n"
    ;;
esac

# Exit-Code fuer CI: nur fehlende Strings sind ein Fehler.
[ "$missing_total" -eq 0 ]
