#!/usr/bin/env bash
# i18n_audit.sh - Vergleicht alle _()-Strings im Source-Tree gegen die
# msgids JEDER ausgelieferten i18n/<code>.po. Liefert je Sprache die Liste
# fehlender und toter Eintraege.
#
# Nutzung:
#   tools/i18n_audit.sh                  # Zusammenfassung, alle Sprachen
#   tools/i18n_audit.sh --missing [de]   # nur fehlende Strings
#   tools/i18n_audit.sh --dead    [de]   # nur tote Eintraege
#   tools/i18n_audit.sh --json           # maschinenlesbar, alle Sprachen
#
# EXIT-CODE: 0 wenn in KEINER Sprache ein Quell-String fehlt, sonst 1.
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
src_dir1="$repo_root/StaticCodeAnalyserForm/sources"
src_dir2="$repo_root/StaticCodeAnalyserIDE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# 1. Source-Strings: alle _('...')-Aufrufe extrahieren.
#    Beschraenkung: Strings ohne eingebettete Apostrophen ('' Escape im
#    Source) - das deckt >99% der echten UI-Strings ab.
grep -rohE "_\('[^']*'\)" "$src_dir1" "$src_dir2" 2>/dev/null \
  | sed -E "s/^_\('(.*)'\)$/\1/" | sort -u > "$tmp_dir/src.txt"
src_count=$(wc -l < "$tmp_dir/src.txt")

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
    | sed -E 's/^msgid "(.*)"$/\1/' \
    | sed 's/\\"/"/g; s/\\\\/\\/g' \
    | grep -v '^$' | sort -u > "$tmp_dir/$code.txt"
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
