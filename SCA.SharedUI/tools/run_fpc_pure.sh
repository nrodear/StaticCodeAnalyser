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
# Repo; derselbe DUnitX-Shim, dieselbe Art Anpassung wie build.sh (nur
# ausserhalb von Literalen: System.SysUtils/Types/Math ohne Namensraum,
# Attribute am Zeilenanfang weg, Assert.AreEqual<Integer> -> AreEqualInt),
# und derselbe Abgleich der Testzahl mit den [Test]-Attributen (R6-02),
# aber ein eigener Runner je Unit, keine Registrierungspruefung, keine
# Grabsteine. Die Runner-Erzeugung steht damit dreimal im Baum (hier,
# reDelphix/ und VarNameProject/tools/fpc-pruefstand/build.sh) - die
# Zusammenlegung ist offen (Review Woche 2026-10-21, G10-01).
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
# Ohne Arbeitsverzeichnis abbrechen: sonst waere WORK leer, und SRC wuerde
# '/<Unit>' (Review Woche 2026-10-21, G10-01).
WORK="$(mktemp -d "$(cygpath -u "${TMP:-${TEMP:-/tmp}}")/sca_fpc_pure.XXXXXX")" \
  && [ -n "$WORK" ] && [ -d "$WORK" ] \
  || { echo "kein Arbeitsverzeichnis (mktemp/cygpath gescheitert)" >&2; exit 2; }
cleanup() { [ "${KEEP:-0}" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT
echo "Pruefstand: SCA=$SCA ($(git -C "$SCA" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') @ $(git -C "$SCA" rev-parse --short HEAD 2>/dev/null || echo '?'))  Arbeitsverzeichnis $WORK"

# adapt <quelle> <ziel>: wie adapt in reDelphix/tools/fpc-pruefstand/build.sh
# (Review R6-03) - ersetzt wird nur AUSSERHALB von String-Literalen (Felder
# mit -F"'": ungerade = Code), ein Attribut nur am Zeilenanfang. Vorher
# ersetzte sed auch in Literalen: ein Test, der 'System.SysUtils' oder
# '[Test] ' als Text prueft, sah unter FPC andere Daten als unter Delphi
# (Review Woche 2026-10-21, G10-01). Die Zeilen bleiben, FPC-Meldungen
# nennen die Zeilennummern der Quellen.
adapt() {
  awk -F"'" -v OFS="'" '
    {
      sub(/\r$/, "")
      if ($1 ~ /^[[:space:]]*\[TestFixture\]/) sub(/\[TestFixture\]/, "", $1)
      if ($1 ~ /^[[:space:]]*\[Test\]/) sub(/\[Test\] */, "", $1)
      for (i = 1; i <= NF; i += 2) {
        gsub(/System\.SysUtils/, "SysUtils", $i)
        gsub(/System\.Types/, "Types", $i)
        gsub(/System\.Math/, "Math", $i)
        gsub(/Assert\.AreEqual<Integer>\(/, "Assert.AreEqualInt(", $i)
      }
      print
    }' "$1" > "$2"
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
  # FPC schreibt erst in eine Datei: sein Exit zaehlt (das Pipe-Ende
  # verdeckte ihn, und ein alter runner.exe galt als gebaut), angezeigt
  # werden die ersten 60 Zeilen ohne Kopfzeilen - wie build.sh.
  ( cd "$SRC" && "$FPC" -Mdelphiunicode -Sh -gl -Cr -Co -vew -FEout -FUout \
      runner.pas > fpc.log 2>&1 )
  frc=$?
  tr -d '\r' < "$SRC/fpc.log" \
    | grep -vE '^(Free Pascal|Copyright|Target OS|Compiling|Linking|[0-9]+ lines compiled)' | head -60
  if [ $frc -eq 0 ] && [ -f "$OUT/runner.exe" ]; then
    "$OUT/runner.exe" > "$SRC/run.log" 2>&1; rc=$?
    tr -d '\r' < "$SRC/run.log"
    # Abgleich mit den [Test]-Attributen wie build.sh (Review R6-02): ein
    # abgebrochener Lauf ohne Zusammenfassung oder mit anderer Testzahl ist
    # nie gruen.
    summary="$(tr -d '\r' < "$SRC/run.log" | grep -E '^PASSED [0-9]+  FAILED [0-9]+$' | tail -1)"
    if [ -z "$summary" ]; then
      echo "Lauf ohne Zusammenfassung 'PASSED n  FAILED m' - abgebrochen?" >&2
      rc=1
    else
      read -r _ passed _ failed <<< "$summary"
      if [ $((passed + failed)) -ne "$expected" ]; then
        echo "Der Lauf zaehlt $((passed + failed)) Tests, $T traegt $expected [Test]-Attribute" >&2
        rc=1
      fi
    fi
  else
    echo "KEIN runner.exe fuer $U - Bau gescheitert (FPC-Exit $frc)"; rc=1
  fi
  echo "   exit=$rc"
  [ "$rc" -eq 0 ] || rc_all=1
done
exit $rc_all
