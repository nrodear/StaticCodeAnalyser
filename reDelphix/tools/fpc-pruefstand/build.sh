#!/usr/bin/env bash
# FPC-Pruefstand fuer die RefactorInfo-/SourcePlaces-Units des SCA-Cores und
# die Rezepte des Moduls reDelphix.
# Aufruf: build.sh <testunit> [<testunit> ...]
#   Testunits kommen aus <SCA>\StaticCodeAnalyserForm\tests
#   oder - wenn dort vorhanden - aus reDelphix\tests.
# Pfadregel: <SCA> ist der Checkout, in dem dieses Skript liegt (das
#   Verzeichnis ueber reDelphix). Core, Rezepte und Tests kommen so immer
#   aus EINEM Stand, auch in einem Worktree oder zweiten Klon.
#   SCA_ROOT=<pfad> ueberschreibt das bewusst; die Kopfzeile des Laufs nennt
#   beide Wurzeln. Kopien eines frueheren Laufs loescht das Skript vor dem
#   Kopieren - eine fehlende Quelle bricht ab, statt still die alte Kopie zu
#   uebersetzen.
# Exit: 0 alle Tests gruen; 1 Test rot oder Bau gescheitert; 2 Aufruf- oder
#   Quellfehler, auch wenn die Zahl der [Test]-Attribute einer Testunit nicht
#   zur Zahl der erkannten Testmethoden passt (der Runner liesse sonst Tests
#   still aus).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RDX="$(cd "$HERE/../.." && pwd)"
SCA="$(cd "${SCA_ROOT:-$RDX/..}" 2>/dev/null && pwd)"
FPC="/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe"
OUT="$HERE/out"
if [ $# -eq 0 ]; then
  echo "Aufruf: build.sh <testunit> [<testunit> ...]" >&2
  exit 2
fi
if [ -z "$SCA" ] || [ ! -d "$SCA/SCA.Engine/sources" ]; then
  echo "SCA-Wurzel nicht gefunden: ${SCA_ROOT:-$RDX/..}" >&2
  exit 2
fi
BRANCH="$(git -C "$SCA" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
REV="$(git -C "$SCA" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "Pruefstand: SCA=$SCA ($BRANCH @ $REV)  RDX=$RDX"
mkdir -p "$OUT"
rm -f "$OUT"/*.ppu "$OUT"/*.o "$OUT"/runner.exe
# Kopien eines frueheren Laufs weg - genau die Muster der .gitignore; die
# eingecheckten Stubs (uParser2, uAstNode, HashStub, DUnitX ...) bleiben.
rm -f "$HERE"/uDetectorUtils.pas "$HERE"/uRefactor*.pas "$HERE"/uSourcePlaces.pas \
      "$HERE"/uFindingActions.pas "$HERE"/uRdx*.pas "$HERE"/uTest*.pas "$HERE"/runner.pas

# Bricht ab, wenn eine Pflichtquelle fehlt.
need() {
  if [ ! -f "$1" ]; then
    echo "Quelle fehlt: $1" >&2
    exit 2
  fi
}

# --- 1) echte ScanCodeLine in einen Stub-uDetectorUtils uebernehmen ---------
SRC="$SCA/SCA.Engine/sources/Common/uDetectorUtils.pas"
need "$SRC"
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
  need "$SCA/SCA.Engine/sources/Common/$u.pas"
  adapt "$SCA/SCA.Engine/sources/Common/$u.pas" "$HERE/$u.pas"
done
need "$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas"
adapt "$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas" "$HERE/uSourcePlaces.pas"
# Modul reDelphix: nur die ToolsAPI-freien Units (Rezepte, Scope-Tabelle).
# Fehlt eine, scheitern nur die Tests, die sie brauchen - deshalb Warnung.
for u in uRdxRecipes uRdxScopeTable uRdxBufferMath uRdxSuppress uRdxSimpleFixes; do
  if [ -f "$RDX/source/$u.pas" ]; then
    adapt "$RDX/source/$u.pas" "$HERE/$u.pas"
  else
    echo "WARNUNG: $RDX/source/$u.pas fehlt - Testunits, die $u brauchen, scheitern beim Bau" >&2
  fi
done

# --- 3) Runner erzeugen ------------------------------------------------------
# Laeuft in der aktuellen Shell (Gruppe, keine Subshell): ein exit hier
# beendet das Skript, Meldungen gehen deshalb nach stderr.
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
    if [ ! -f "$src" ]; then
      echo "Testunit $t.pas weder in $RDX/tests noch in $SCA/StaticCodeAnalyserForm/tests" >&2
      exit 2
    fi
    adapt "$src" "$HERE/$t.pas"
    cls=$(grep -oE '^  T[A-Za-z0-9_]+ = class$' "$HERE/$t.pas" | head -1 | awk '{print $1}')
    # Abgleich: jede [Test]-Methode muss als '    procedure Name;' erkannt
    # sein, sonst fehlte ihr Run()-Aufruf und der Lauf meldete trotzdem gruen.
    expected=$(tr -d '\r' < "$src" | grep -cE '^[[:space:]]*\[Test\]')
    procs=$(grep -oE '^    procedure [A-Za-z0-9_]+;' "$HERE/$t.pas" | awk '{gsub(";","",$2); print $2}')
    got=$(printf '%s' "$procs" | grep -c .)
    if [ -z "$cls" ] || [ "$expected" != "$got" ]; then
      echo "$t: Fixture-Klasse '${cls:-?}', [Test]-Attribute $expected, erkannte Testmethoden $got - Abbruch" >&2
      exit 2
    fi
    n=$((n+1))
    printf 'procedure RunSuite%d;\nvar\n  T : %s;\nbegin\n  T := %s.Create;\n  try\n' "$n" "$cls" "$cls"
    for p in $procs; do
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
  rc=$?
  echo "runner exit=$rc"
  exit $rc
else
  echo "KEIN runner.exe - Bau gescheitert"
  exit 1
fi
