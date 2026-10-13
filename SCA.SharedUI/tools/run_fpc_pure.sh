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
# Repo; derselbe DUnitX-Shim, dieselben Anpassungen (System.SysUtils ->
# SysUtils, Attribute weg, Assert.AreEqual<Integer> -> AreEqualInt).
# -Cr -Co: Range- und Overflow-Pruefung an, wie die Delphi-Pakete ($R+ $Q+).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCA="$(cd "$HERE/../.." && pwd)"
FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
SHIM="$SCA/reDelphix/tools/fpc-pruefstand/DUnitX.TestFramework.pas"
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
# Unter Git-Bash muss das Arbeitsverzeichnis fuer den Windows-FPC erreichbar
# sein: nicht /tmp (das waere \tmp), sondern das Windows-Temp aus $TMP.
WORK="$(mktemp -d "$(cygpath -u "${TMP:-${TEMP:-/tmp}}")/sca_fpc_pure.XXXXXX")"
cleanup() { [ "${KEEP:-0}" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT
echo "Pruefstand: SCA=$SCA ($(git -C "$SCA" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') @ $(git -C "$SCA" rev-parse --short HEAD 2>/dev/null || echo '?'))  Arbeitsverzeichnis $WORK"

adapt() {
  tr -d '\r' < "$1" \
  | sed -e 's/System\.SysUtils/SysUtils/g' \
        -e 's/System\.Types/Types/g' \
        -e 's/System\.Math/Math/g' \
        -e 's/\[TestFixture\]//' \
        -e 's/\[Test\] *//' \
        -e 's/Assert\.AreEqual<Integer>(/Assert.AreEqualInt(/g' \
  > "$2"
}

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
  adapt "$USRC" "$SRC/$U.pas"
  adapt "$TSRC" "$SRC/$T.pas"
  cls=$(grep -oE '^  T[A-Za-z0-9_]+ = class$' "$SRC/$T.pas" | head -1 | awk '{print $1}')
  expected=$(tr -d '\r' < "$TSRC" | grep -cE '^[[:space:]]*\[Test\]')
  procs=$(grep -oE '^    procedure [A-Za-z0-9_]+;' "$SRC/$T.pas" | awk '{gsub(";","",$2); print $2}')
  got=$(printf '%s' "$procs" | grep -c .)
  echo "== $U / $T ($cls): [Test]=$expected erkannt=$got"
  if [ "$expected" != "$got" ]; then echo "Abgleich gescheitert" >&2; exit 2; fi
  {
    printf 'program runner;\n\nuses\n  SysUtils, DUnitX.TestFramework, %s;\n\n' "$T"
    printf 'type\n  TTestProc = procedure of object;\n\nvar\n  Passed, Failed : Integer;\n\n'
    printf 'procedure Run(const AName: string; AProc: TTestProc);\nbegin\n  try\n    AProc();\n    Inc(Passed);\n'
    printf '  except\n    on E: ETestPass do Inc(Passed);\n    on E: Exception do\n    begin\n      Inc(Failed);\n'
    printf "      Writeln('FAIL ', AName, ': ', E.ClassName, ': ', E.Message);\n    end;\n  end;\nend;\n\n"
    printf 'var\n  T : %s;\nbegin\n  Passed := 0;\n  Failed := 0;\n  T := %s.Create;\n  try\n' "$cls" "$cls"
    for p in $procs; do printf "    Run('%s.%s', T.%s);\n" "$T" "$p" "$p"; done
    printf "  finally\n    T.Free;\n  end;\n  Writeln('PASSED ', Passed, '  FAILED ', Failed);\n  if Failed > 0 then Halt(1);\nend.\n"
  } > "$SRC/runner.pas"
  ( cd "$SRC" && "$FPC" -Mdelphiunicode -Sh -gl -Cr -Co -vew -FEout -FUout runner.pas 2>&1 \
      | grep -vE '^(Free Pascal|Copyright|Target OS|Compiling|Linking|[0-9]+ lines compiled)' | head -60 )
  if [ -f "$OUT/runner.exe" ]; then
    "$OUT/runner.exe"; rc=$?
  else
    echo "KEIN runner.exe fuer $U"; rc=1
  fi
  echo "   exit=$rc"
  [ "$rc" -eq 0 ] || rc_all=1
done
exit $rc_all
