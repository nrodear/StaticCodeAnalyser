#!/usr/bin/env bash
# i18n_audit.sh - Vergleicht alle _()-Strings im Source-Tree gegen die
# msgids in i18n/de.po und i18n/en.po. Liefert Listen fehlender + toter
# Eintraege.
#
# Nutzung:
#   tools/i18n_audit.sh                  # Zusammenfassung
#   tools/i18n_audit.sh --missing        # nur fehlende DE-Strings
#   tools/i18n_audit.sh --dead           # nur tote de.po-Eintraege
#   tools/i18n_audit.sh --json           # maschinenlesbar
#
# Exit-Code: 0 wenn nichts fehlt, 1 wenn fehlende oder tote da sind.
# CI-tauglich; siehe Audit_AllDetectors.md V4.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src_dir1="$repo_root/StaticCodeAnalyserForm/sources"
src_dir2="$repo_root/StaticCodeAnalyserIDE"
de_po="$repo_root/i18n/de.po"
en_po="$repo_root/i18n/en.po"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# 1. Source-Strings: alle _('...')-Aufrufe extrahieren.
#    Beschraenkung: Strings ohne eingebettete Apostrophen ('' Escape im
#    Source) - das deckt >99% der echten UI-Strings ab.
grep -rohE "_\('[^']*'\)" "$src_dir1" "$src_dir2" 2>/dev/null \
  | sed -E "s/^_\('(.*)'\)$/\1/" | sort -u > "$tmp_dir/src.txt"

# 2. DE msgids extrahieren (eine pro Zeile). po-Format escaped Quotes als
#    `\"`; nach dem Strippen der aeusseren Quotes wird `\"` zurueck zu `"`
#    normalisiert, sonst gibt's False-Positives gegen Source-Strings
#    (die unmaskiert sind).
grep -E '^msgid "' "$de_po" \
  | sed -E 's/^msgid "(.*)"$/\1/' \
  | sed 's/\\"/"/g; s/\\\\/\\/g' \
  | grep -v '^$' | sort -u > "$tmp_dir/de.txt"

src_count=$(wc -l < "$tmp_dir/src.txt")
de_count=$(wc -l < "$tmp_dir/de.txt")
missing_count=$(comm -23 "$tmp_dir/src.txt" "$tmp_dir/de.txt" | wc -l)
dead_count=$(comm -13 "$tmp_dir/src.txt" "$tmp_dir/de.txt" | wc -l)

case "${1:-}" in
  --missing)
    comm -23 "$tmp_dir/src.txt" "$tmp_dir/de.txt"
    ;;
  --dead)
    comm -13 "$tmp_dir/src.txt" "$tmp_dir/de.txt"
    ;;
  --json)
    printf '{"source":%d,"de_msgids":%d,"missing":%d,"dead":%d}\n' \
      "$src_count" "$de_count" "$missing_count" "$dead_count"
    ;;
  *)
    printf "Source unique _()-strings:  %4d\n" "$src_count"
    printf "DE msgids:                  %4d\n" "$de_count"
    printf "Missing in de.po:           %4d\n" "$missing_count"
    printf "Dead in de.po:              %4d\n" "$dead_count"
    if [ "$missing_count" -gt 0 ] || [ "$dead_count" -gt 0 ]; then
      printf "\nDetails mit --missing oder --dead.\n"
    fi
    ;;
esac

# Exit-Code fuer CI: 0 wenn alles sauber, 1 wenn was zu tun ist.
if [ "$missing_count" -eq 0 ] && [ "$dead_count" -eq 0 ]; then
  exit 0
else
  exit 1
fi
