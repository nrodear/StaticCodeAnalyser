#!/usr/bin/env bash
# FPC-Pruefstand fuer die RefactorInfo-/SourcePlaces-Units des SCA-Cores und
# die Rezepte des Moduls reDelphix.
# Aufruf: build.sh <testunit> [<testunit> ...]
#   Testunits kommen aus StaticCodeAnalyser\StaticCodeAnalyserForm\tests
#   oder - wenn dort vorhanden - aus reDelphix\tests.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCA="/d/git-demos/delphi/StaticCodeAnalyser"
RDX="$(cd "$HERE/../.." && pwd)"
FPC="/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe"
OUT="$HERE/out"
mkdir -p "$OUT"
rm -f "$OUT"/*.ppu "$OUT"/*.o "$OUT"/runner.exe

# --- 1) echte ScanCodeLine in einen Stub-uDetectorUtils uebernehmen ---------
SRC="$SCA/SCA.Engine/sources/Common/uDetectorUtils.pas"
{
  printf 'unit uDetectorUtils;\n\ninterface\n\nuses\n  SysUtils, StrUtils;\n\ntype\n'
  printf '  TCommentScanState = record\n    InBraceComment : Boolean;\n    InParenComment : Boolean;\n  end;\n\n'
  printf '  TDetectorUtils = class\n  public\n'
  printf '    class function ScanCodeLine(const Line: string; var State: TCommentScanState;\n'
  printf "      out LineCommentCol: Integer; FillCh: Char = '~';\n"
  printf '      AKeepColumns: Boolean = False): string; static;\n  end;\n\nimplementation\n\n'
  awk '/^class function TDetectorUtils\.ScanCodeLine/ {p=1}
       p && /^class (function|procedure) TDetectorUtils\./ && !/ScanCodeLine/ {p=0}
       p {print}' "$SRC" | tr -d '\r'
  printf '\nend.\n'
} > "$HERE/uDetectorUtils.pas"

# --- 2) echte Units + Tests kopieren und fuer FPC 3.2.2 anpassen ------------
adapt() {
  tr -d '\r' < "$1" \
  | sed -e 's/System\.SysUtils/SysUtils/g' \
        -e 's/System\.Classes/Classes/g' \
        -e 's/System\.Hash/HashStub/g' \
        -e 's/System\.StrUtils/StrUtils/g' \
        -e 's/System\.SyncObjs/SyncObjs/g' \
        -e 's/System\.IOUtils/IOUtils/g' \
        -e 's/System\.Generics\.Collections/Generics.Collections/g' \
        -e 's/\[TestFixture\]//' \
        -e 's/\[Test\] *//' \
        -e 's/Assert\.AreEqual<Integer>(/Assert.AreEqualInt(/g' \
  > "$2"
}
for u in uRefactorInfo uRefactorInfoBuilder uRefactorConcat uFindingActions; do
  adapt "$SCA/SCA.Engine/sources/Common/$u.pas" "$HERE/$u.pas"
done
[ -f "$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas" ] && \
  adapt "$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas" "$HERE/uSourcePlaces.pas"
# Modul reDelphix: nur die ToolsAPI-freien Units (Rezepte, Scope-Tabelle).
for u in uRdxRecipes uRdxScopeTable uRdxBufferMath; do
  [ -f "$RDX/source/$u.pas" ] && adapt "$RDX/source/$u.pas" "$HERE/$u.pas"
done

# --- 3) Runner erzeugen ------------------------------------------------------
{
  printf 'program runner;\n\nuses\n  SysUtils, DUnitX.TestFramework'
  for t in "$@"; do printf ',\n  %s' "$t"; done
  printf ';\n\ntype\n  TTestProc = procedure of object;\n\nvar\n  Passed, Failed : Integer;\n\n'
  printf 'procedure Run(const AName: string; AProc: TTestProc);\nbegin\n  try\n    AProc();\n    Inc(Passed);\n'
  printf '  except\n    on E: ETestPass do Inc(Passed);\n    on E: Exception do\n    begin\n      Inc(Failed);\n'
  printf "      Writeln('FAIL ', AName, ': ', E.ClassName, ': ', E.Message);\n    end;\n  end;\nend;\n\n"
  n=0
  for t in "$@"; do
    src="$SCA/StaticCodeAnalyserForm/tests/$t.pas"
    [ -f "$RDX/tests/$t.pas" ] && src="$RDX/tests/$t.pas"
    adapt "$src" "$HERE/$t.pas"
    cls=$(grep -oE '^  T[A-Za-z0-9_]+ = class$' "$HERE/$t.pas" | head -1 | awk '{print $1}')
    n=$((n+1))
    printf 'procedure RunSuite%d;\nvar\n  T : %s;\nbegin\n  T := %s.Create;\n  try\n' "$n" "$cls" "$cls"
    grep -oE '^    procedure [A-Za-z0-9_]+;' "$HERE/$t.pas" | awk '{gsub(";","",$2); print $2}' | while read -r p; do
      printf "    Run('%s.%s', T.%s);\n" "$t" "$p" "$p"
    done
    printf '  finally\n    T.Free;\n  end;\nend;\n\n'
  done
  printf 'begin\n  Passed := 0;\n  Failed := 0;\n'
  i=0
  for t in "$@"; do i=$((i+1)); printf '  RunSuite%d;\n' "$i"; done
  printf "  Writeln('PASSED ', Passed, '  FAILED ', Failed);\n  if Failed > 0 then Halt(1);\nend.\n"
} > "$HERE/runner.pas"

# --- 4) bauen und laufen lassen ----------------------------------------------
cd "$HERE" || exit 2
"$FPC" -Mdelphiunicode -Sh -gl -vew -FEout -FUout runner.pas 2>&1 \
  | grep -vE '^(Free Pascal|Copyright|Target OS|Compiling|Linking|[0-9]+ lines compiled)' | head -60
if [ -f "$OUT/runner.exe" ]; then
  "$OUT/runner.exe"
  echo "runner exit=$?"
else
  echo "KEIN runner.exe - Bau gescheitert"
  exit 1
fi
