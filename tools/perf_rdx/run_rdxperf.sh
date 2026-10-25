#!/usr/bin/env bash
# reDelphix-Zeitmessung ohne Delphi-Bau (FPC 3.2.2, i386-win32). Misst je
# Fundstelle eines SARIF, was das Aktionsmenue/die Gluehbirne fuer diesen
# Fund an TEXT-Arbeit bezahlt (Lines.Text, Unterdrueck-Marker, Map-Planer,
# Kontext-Runner) - Einzelheiten im Kopf von rdxperf.lpr.
#
#   bash tools/perf_rdx/run_rdxperf.sh <sarif> [maxN] [regel,regel,..] [topN]
#
# Beispiele:
#   bash tools/perf_rdx/run_rdxperf.sh C:/temp/perf/ab_strict/self_new_r1.sarif
#   bash tools/perf_rdx/run_rdxperf.sh C:/temp/perf/ab_strict/laz_new_r1.sarif 50000
#   bash tools/perf_rdx/run_rdxperf.sh self.sarif "" SCA101,SCA015 40
#
# Ergebnis im Arbeitsverzeichnis RDXPERF_WORK (Standard
# ${TMPDIR:-/tmp}/sca_rdxperf, NIE im Repo):
#   out/<name>.csv   je Fund eine Zeile (ms je Anteil, Zaehler)
#   out/<name>.txt   Zusammenfassung je Regel + langsamste Fundstellen
#   excluded_units.txt  Planer-Units, die FPC 3.2.2 nicht uebersetzt - ihre
#                    Regeln laufen dann nur mit der Grundlast lines/supp/ctx
#   unmapped_rows.txt   Tabellenzeilen ohne MapFix-Form (nur im Delphi-
#                    Harness messbar)
#
# Fasst das Repo nicht an: reDelphix/tools/fpc-pruefstand/build.sh legt seine
# Kopien in <work>/units (PRUEFSTAND_DIR), nur diese Kopien werden gepatcht
# (Zaehler, patch_counters.py) und uebersetzt.
# SCA_ROOT=<pfad> waehlt einen anderen Checkout (Standard: der, in dem dieses
# Skript liegt), FPC=<pfad> einen anderen Compiler.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCA="${SCA_ROOT:-$(cd "$HERE/../.." && pwd)}"
SCAW="$(cd "$SCA" && pwd -W)"
FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
WORK="${RDXPERF_WORK:-${TMPDIR:-/tmp}/sca_rdxperf}"
if [ $# -lt 1 ]; then
  sed -n '2,12p' "$0"; exit 2
fi
SARIF="$1"; MAXN="${2:-}"; ONLY="${3:-}"; TOPN="${4:-25}"
[ -f "$SARIF" ] || { echo "SARIF fehlt: $SARIF"; exit 2; }
NAME="$(basename "$SARIF" .sarif)${MAXN:+_$MAXN}${ONLY:+_sel}"
mkdir -p "$WORK/out"
WORK="$(cd "$WORK" && pwd)"
WORKW="$(cd "$WORK" && pwd -W)"   # fuer Python (natives Windows-Programm)
case "$WORK/" in
  "$SCA"/*) echo "RDXPERF_WORK liegt im Repo ($WORK) - bitte ausserhalb"; exit 2;;
esac
REV="$(git -C "$SCA" rev-parse --short HEAD)"
echo "rdxperf: SCA=$SCA @ $REV, Arbeitsverzeichnis $WORK"
. "$SCA/tools/fpc_runner_lib.sh"
: > "$WORK/excluded_units.txt"

for attempt in $(seq 1 30); do
  # 1) frische angepasste Kopien des aktuellen Stands
  PRUEFSTAND_DIR="$WORK/units" SCA_ROOT="$SCA" bash "$SCA/reDelphix/tools/fpc-pruefstand/build.sh" \
    uTestRdxContextRunner > "$WORK/out/build_sh.log" 2>&1 \
    || { echo "build.sh rot - $WORK/out/build_sh.log"; tail -5 "$WORK/out/build_sh.log"; exit 1; }
  # 2) Planer-Tabelle aus uRdxFixTable + Fundstellen
  python -I "$HERE/gen_harness.py" "$SCAW" "$WORKW/units" "$SARIF" "$WORKW/out/$NAME.sites.tsv" "$MAXN" "$ONLY" || exit 1
  # 3) Planer-Units, die build.sh nicht kopiert, ebenso anpassen
  EXTRA=()
  while read -r u; do
    [ -n "$u" ] && EXTRA+=("$SCA/reDelphix/source/$u.pas")
  done < "$WORK/extra_units.txt"
  if [ ${#EXTRA[@]} -gt 0 ]; then
    FPC_ADAPT_EXTRA='System.Hash=HashStub' fpc_adapt "$WORK/units" "${EXTRA[@]}" || exit 1
  fi
  # 4) Zaehler in die Kopien
  python -I "$HERE/patch_counters.py" "$WORKW/units" > /dev/null || exit 1
  # 5) uebersetzen (frisches -FU, Hauptquelle im units-Verzeichnis)
  cp "$HERE/rdxperf.lpr" "$WORK/planners.inc" "$WORK/planner_uses.inc" "$WORK/units/"
  rm -rf "$WORK/bin" && mkdir -p "$WORK/bin"
  ( cd "$WORK/units" && "$FPC" -Mdelphiunicode -Sh -O2 -vew -FU../bin -FE../bin rdxperf.lpr > ../out/fpc.log 2>&1 )
  [ -f "$WORK/bin/rdxperf.exe" ] && break
  BAD="$(tr -d '\r' < "$WORK/out/fpc.log" | grep -E '^uRdx[A-Za-z0-9]+\.pas\([0-9,]+\) (Error|Fatal)' | head -1 | sed 's/\.pas.*//')"
  if [ -z "$BAD" ] || grep -qx "$BAD" "$WORK/excluded_units.txt" \
     || ! grep -qx "$BAD" "$WORK/extra_units.txt"; then
    echo "FPC-Bau gescheitert (nicht durch eine Zusatz-Unit) - $WORK/out/fpc.log:"
    grep -E 'Error|Fatal' "$WORK/out/fpc.log" | head -20; exit 1
  fi
  echo "  FPC uebersetzt $BAD nicht - Planer ausgenommen"
  echo "$BAD" >> "$WORK/excluded_units.txt"
done

# 6) Messlauf
"$WORK/bin/rdxperf.exe" "$WORK/out/$NAME.sites.tsv" "$WORK/out/$NAME.csv" "$TOPN" \
  | tee "$WORK/out/$NAME.txt"
echo "ausgenommen (FPC): $(tr '\n' ' ' < "$WORK/excluded_units.txt")" | tee -a "$WORK/out/$NAME.txt"
echo "CSV: $WORK/out/$NAME.csv"
