#!/usr/bin/env bash
# FPC-Pruefstand fuer die ToolsAPI-freien Units von VarNameProject
# (source/uVnpPlan.pas, source/uVnpEdits.pas) und ihre DUnitX-Testunits
# (tests/uTestVnp*.pas) - dieselben Tests, die tests/VarNameProject.Test.dpr
# in Delphi faehrt, hier ohne IDE (FPC 3.2.2, i386-win32). Muster:
# reDelphix/tools/fpc-pruefstand, aber eigenstaendig (VarNameProject haengt
# weder an SCA.Engine noch an reDelphix); die Bausteine (Anpassung der
# Quellen, Runner, Bau, Abgleich der Testzahl) kommen aus
# tools/fpc_runner_lib.sh im Wurzelverzeichnis des Repos - gemeinsam mit
# SCA.SharedUI/tools/run_fpc_pure.sh (Review Woche 2026-10-21, G10-01;
# Folgewelle A7).
# Aufruf: build.sh [<testunit> ...]   ohne Argument: alle tests/uTestVnp*.pas
# WORK=<ordner> legt Kopien, runner.pas und out/ dort ab (Vorgabe: work/
#   neben diesem Skript) - so stoeren sich zwei Laeufe nicht.
# FPC=<pfad> ueberschreibt den Compiler.
# Exit: 0 alle Tests gruen; 1 Test rot, Bau gescheitert, Lauf ohne
#   Zusammenfassung oder mit einer anderen Testzahl als den [Test]-
#   Attributen; 2 Aufruf- oder Quellfehler, auch wenn die Zahl der
#   [Test]-Attribute einer Testunit nicht zur Zahl der erkannten
#   Testmethoden passt (der Runner liesse sonst Tests still aus).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VNP="$(cd "$HERE/../.." && pwd)"
LIB="$(cd "$VNP/.." && pwd)/tools/fpc_runner_lib.sh"
FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
WORK="${WORK:-$HERE/work}"
if [ ! -x "$FPC" ]; then
  echo "FPC nicht gefunden: $FPC (FPC=<pfad> setzen)" >&2
  exit 2
fi
if [ ! -f "$LIB" ]; then
  echo "Bausteine fehlen: $LIB" >&2
  exit 2
fi
# shellcheck source=../../../tools/fpc_runner_lib.sh
. "$LIB"
if [ $# -eq 0 ]; then
  set -- $(cd "$VNP/tests" 2>/dev/null && ls uTestVnp*.pas 2>/dev/null \
    | sed 's/\.pas$//')
fi
if [ $# -eq 0 ]; then
  echo "keine Testunits uTestVnp*.pas in $VNP/tests" >&2
  exit 2
fi
REV="$(git -C "$VNP" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "Pruefstand VarNameProject: $VNP (HEAD $REV, Arbeitsstand), WORK=$WORK"
mkdir -p "$WORK/out" || exit 2
# Kopien eines frueheren Laufs weg - eine fehlende Quelle bricht dann ab,
# statt still die alte Kopie zu uebersetzen.
rm -f "$WORK"/*.pas "$WORK"/out/*

# Fuer FPC 3.2.2 anpassen (fpc_adapt: Namensraeume, DUnitX-Attribute,
# generisches AreEqual<Integer> - nur ausserhalb von String-Literalen).
for u in uVnpPlan uVnpEdits; do
  if [ ! -f "$VNP/source/$u.pas" ]; then
    echo "Quelle fehlt: $VNP/source/$u.pas" >&2
    exit 2
  fi
  fpc_adapt "$WORK" "$VNP/source/$u.pas" || exit 2
done
cp "$HERE/DUnitX.TestFramework.pas" "$WORK/" || exit 2

# Runner erzeugen. Laeuft in der aktuellen Shell (Gruppe, keine Subshell):
# ein exit hier beendet das Skript, Meldungen gehen deshalb nach stderr;
# total zaehlt die [Test]-Attribute aller Testunits fuer den Abgleich mit
# dem Lauf.
total=0
{
  fpc_runner_head "$@"
  n=0
  for t in "$@"; do
    src="$VNP/tests/$t.pas"
    if [ ! -f "$src" ]; then
      echo "Testunit fehlt: $src" >&2
      exit 2
    fi
    fpc_adapt "$WORK" "$src" || exit 2
    fpc_fixture_info "$src" "$WORK/$t.pas" || exit 2
    # Abgleich: jede [Test]-Methode muss als '    procedure Name;' erkannt
    # sein, sonst fehlte ihr Run()-Aufruf und der Lauf meldete trotzdem gruen.
    if [ -z "$FPC_CLS" ] || [ "$FPC_EXPECTED" != "$FPC_GOT" ]; then
      echo "$t: Fixture-Klasse '${FPC_CLS:-?}', [Test]-Attribute $FPC_EXPECTED, erkannte Testmethoden $FPC_GOT - Abbruch" >&2
      exit 2
    fi
    n=$((n+1))
    total=$((total + FPC_GOT))
    # shellcheck disable=SC2086 # FPC_PROCS: ein Name je Zeile
    fpc_runner_suite "$n" "$t" "$FPC_CLS" $FPC_PROCS
  done
  fpc_runner_main "$n"
} > "$WORK/runner.pas"

# Bauen und laufen lassen, beides in WORK (fpc_build: FPC-Exit zaehlt;
# fpc_run_check: Zusammenfassung und Testzahl wie reDelphix, Review R6-02;
# jeder Exit des Runners ungleich 0 wird 1 - Vertrag oben 0/1/2, ein
# Absturz endete sonst mit FPCs Laufzeitfehler-Code 216/217, G10-21).
fpc_build "$WORK" "" || exit 1
cd "$WORK" || exit 2
fpc_run_check "$WORK/out/runner.exe" "$WORK/run.log" "$total" \
  "die Testunits tragen $total [Test]-Attribute - das Ergebnis gehoert nicht zu diesem Aufruf" rc \
  || exit 1
exit 0
