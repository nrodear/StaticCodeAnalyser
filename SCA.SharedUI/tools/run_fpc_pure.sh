#!/usr/bin/env bash
# FPC-Pruefstand fuer die REINEN Units von SCA.SharedUI (ohne VCL, ohne
# ToolsAPI) und ihre DUnitX-Tests aus StaticCodeAnalyserForm\tests.
#
# Aufruf (Git-Bash, aus beliebigem Verzeichnis):
#   SCA.SharedUI/tools/run_fpc_pure.sh                 # alle Units unten
#   SCA.SharedUI/tools/run_fpc_pure.sh uBulbDecision   # nur diese
# Je Unit uXyz wird die Testunit uTestXyz uebersetzt und ein Runner gebaut.
# Umgebung: FPC=<pfad> ueberschreibt den Compiler (Vorgabe Lazarus 4.8 /
#   FPC 3.2.2, i386-win32 - die einzige lokal gebaute Zielplattform);
#   KEEP=1 laesst das Arbeitsverzeichnis stehen (sonst mktemp, wird
#   geloescht).
# Exit: 0 alle Tests gruen; 1 Test rot oder Bau gescheitert; 2 Aufruf-
#   oder Umgebungsfehler, auch wenn die Zahl der [Test]-Attribute einer
#   Testunit nicht zur Zahl der erkannten Testmethoden passt (der Runner
#   liesse sonst Tests still aus).
#
# WARUM (Review 2026-10-14): uHitCacheRepair behauptete "im FPC-Pruefstand
# getestet", aber reDelphix/tools/fpc-pruefstand/build.sh kennt die Unit
# nicht - der Lauf gab es nur als Skript im Scratchpad. Jetzt liegt er im
# Repo, mit demselben DUnitX-Shim wie reDelphix und einem eigenen Runner je
# Unit, ohne Registrierungspruefung und ohne Grabsteine. Anpassung der
# Quellen, Runner-Erzeugung, Bau und Abgleich der Testzahl kommen aus
# tools/fpc_runner_lib.sh - gemeinsam mit VarNameProject (Review Woche
# 2026-10-21, G10-01: die dritte Kopie der Runner-Erzeugung lief hinter
# build.sh zurueck; Folgewelle A7).
# -Cr -Co: Range- und Overflow-Pruefung an, wie die Delphi-Pakete ($R+ $Q+).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCA="$(cd "$HERE/../.." && pwd)"
FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
SHIM="$SCA/reDelphix/tools/fpc-pruefstand/DUnitX.TestFramework.pas"
LIB="$SCA/tools/fpc_runner_lib.sh"
UNITS=("$@")
if [ ${#UNITS[@]} -eq 0 ]; then
  # uEditorBulbGeometry fehlt bewusst: seine Tests nutzen die Integer-
  # Ueberladung von Assert.AreEqual, die der Shim nicht kennt.
  UNITS=(uHitCacheRepair uBulbDecision uFindingSourcePick)
fi
if [ ! -x "$FPC" ]; then
  echo "FPC nicht gefunden: $FPC (FPC=<pfad> setzen)" >&2
  exit 2
fi
if [ ! -f "$SHIM" ]; then
  echo "DUnitX-Shim fehlt: $SHIM" >&2
  exit 2
fi
if [ ! -f "$LIB" ]; then
  echo "Bausteine fehlen: $LIB" >&2
  exit 2
fi
# shellcheck source=../../tools/fpc_runner_lib.sh
. "$LIB"
# Unter Git-Bash muss das Arbeitsverzeichnis fuer den Windows-FPC erreichbar
# sein: nicht /tmp (das waere \tmp), sondern das Windows-Temp aus $TMP.
# Ohne Arbeitsverzeichnis abbrechen: sonst waere WORK leer, und SRC wuerde
# '/<Unit>' (Review Woche 2026-10-21, G10-01).
WORK="$(mktemp -d "$(cygpath -u "${TMP:-${TEMP:-/tmp}}")/sca_fpc_pure.XXXXXX")" \
  && [ -n "$WORK" ] && [ -d "$WORK" ] \
  || { echo "kein Arbeitsverzeichnis (mktemp/cygpath gescheitert)" >&2; exit 2; }
cleanup() { [ "${KEEP:-0}" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT
echo "Pruefstand: SCA=$SCA ($(git -C "$SCA" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') @ $(git -C "$SCA" rev-parse --short HEAD 2>/dev/null || echo '?'))  Arbeitsverzeichnis $WORK"

rc_all=0
for U in "${UNITS[@]}"; do
  T="uTest${U#u}"
  SRC="$WORK/$U"; OUT="$SRC/out"
  mkdir -p "$SRC" "$OUT"
  USRC="$SCA/SCA.SharedUI/sources/$U.pas"
  TSRC="$SCA/StaticCodeAnalyserForm/tests/$T.pas"
  for f in "$USRC" "$TSRC"; do
    if [ ! -f "$f" ]; then echo "Quelle fehlt: $f" >&2; exit 2; fi
  done
  cp "$SHIM" "$SRC/"
  fpc_adapt "$SRC" "$USRC" "$TSRC" || exit 2
  fpc_fixture_info "$TSRC" "$SRC/$T.pas" || exit 2
  echo "== $U / $T ($FPC_CLS): [Test]=$FPC_EXPECTED erkannt=$FPC_GOT"
  if [ "$FPC_EXPECTED" != "$FPC_GOT" ]; then echo "Abgleich gescheitert" >&2; exit 2; fi
  {
    fpc_runner_head "$T"
    # shellcheck disable=SC2086 # FPC_PROCS: ein Name je Zeile
    fpc_runner_suite 1 "$T" "$FPC_CLS" $FPC_PROCS
    fpc_runner_main 1
  } > "$SRC/runner.pas"
  # -Cr -Co wie im Kopf; der Runner laeuft im Verzeichnis des Aufrufers.
  rc=0
  if fpc_build "$SRC" "$U" -Cr -Co; then
    fpc_run_check "$OUT/runner.exe" "$SRC/run.log" "$FPC_EXPECTED" \
      "$T traegt $FPC_EXPECTED [Test]-Attribute" || rc=1
  else
    rc=1
  fi
  echo "   exit=$rc"
  [ "$rc" -eq 0 ] || rc_all=1
done
exit $rc_all
