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
#   beide Wurzeln und das Arbeitsverzeichnis. Eine fehlende Quelle bricht
#   ab, statt still eine alte Kopie zu uebersetzen.
# Arbeitsverzeichnis: jeder Lauf kopiert, erzeugt und baut in einem EIGENEN
#   Verzeichnis (Kopien, Stubs, runner.pas, out/) - zwei Laeufe im selben
#   Checkout stoeren sich nicht (Review reDelphix R6-02: ein zweiter Lauf
#   loeschte die Kopien des ersten, der uebersetzte dann dessen runner.pas
#   und meldete fremde Tests als eigenes Gruen). Vorgabe: ein frisches
#   Verzeichnis unter TMPDIR, nach dem Lauf geloescht. PRUEFSTAND_DIR=<pfad>
#   nimmt stattdessen dieses Verzeichnis und laesst es stehen - fuer einen
#   Korpus-Harness, der gegen die angepassten Units baut (fpc -Fu<pfad>).
#   Das Skript verwaltet es ganz (Marke .pruefstand): ein vorhandenes, nicht
#   leeres Verzeichnis ohne Marke lehnt es ab, eins mit Marke leert es.
#   Ein TMPDIR im Windows-Stil ('C:\Users\..') wird wie PRUEFSTAND_DIR zum
#   POSIX-Pfad (cd && pwd) - awk wertete die Backslashes sonst als Escapes.
# Grabsteine: bis Charge FF lagen die Kopien NEBEN dem Skript, und
#   Korpus-Harnesse bauten mit -Fu<Skriptverzeichnis> und einem bleibenden
#   -FU-Verzeichnis. Findet FPC zu einer .ppu im -FU keine Quelle mehr,
#   nimmt es die .ppu still - auch mit -B -, und der Harness prueft alten
#   Planer-Code. Darum loescht das Skript solche Kopien und legt je
#   kopierter Unit einen Grabstein ab (<unit>.pas mit {$FATAL ...}): seine
#   Dateizeit weicht von der in der alten .ppu ab, FPC uebersetzt ihn und
#   bricht mit dem Hinweis auf PRUEFSTAND_DIR ab (Nachbesserung FF). Ein
#   Harness baut deshalb so (je Bau ein leeres -FU-Verzeichnis):
#     PRUEFSTAND_DIR=<eigen> bash build.sh <testunit>
#     fpc -Mdelphiunicode -Fu<eigen> -FU<frisch> -FE<frisch> harness.pas
#   Der Runner selbst laeuft im Skriptverzeichnis (Tests suchen Daten des
#   Checkouts von dort aus).
# Anpassung fuer FPC 3.2.2 (adapt): System.SysUtils -> SysUtils & Co.,
#   Assert.AreEqual<Integer>( -> Assert.AreEqualInt( und [TestFixture]/
#   [Test] am Zeilenanfang weg - alles nur AUSSERHALB von String-Literalen:
#   ein Test, der einen qualifizierten Unitnamen oder ein Attribut als Text
#   prueft, sieht unter FPC dieselben Daten wie unter Delphi (Review R6-03;
#   bis dahin wurde aus dem Literal 'System.Classes' 'Classes' und aus
#   '    [Test]' '    '). Die Zeilen bleiben, FPC-Meldungen nennen die
#   Zeilennummern der Quellen.
# Runner: genau EINE Fixture je Testunit mit einfachen [Test]-Methoden. Ein
#   Test ohne Assert ist rot - wie unter TestInsight und reDelphix.Test
#   (FailsOnNoAsserts = True, Review R6-09).
# Exit: 0 alle Tests gruen; 1 Test rot, Bau gescheitert (FPC-Exit) oder der
#   Lauf zaehlt nicht genau so viele Tests, wie die Testunits [Test]-
#   Attribute tragen; 2 Aufruf- oder Quellfehler, auch wenn die Zahl der
#   [Test]-Attribute einer Testunit nicht zur Zahl der erkannten
#   Testmethoden passt (der Runner liesse sonst Tests still aus) oder eine
#   Testunit - aufgerufen oder in reDelphix\tests - eine Fixture nicht mit
#   TDUnitX.RegisterTestFixture anmeldet (ein DUnitX-Runner mit UseRTTI =
#   False liesse sie still aus, Review R6-06).
# Je Arbeitsschritt EIN awk-Aufruf ueber alle Dateien: ein Prozessstart
# kostet unter Git Bash 50 ms und mehr.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RDX="$(cd "$HERE/../.." && pwd)"
SCA="$(cd "${SCA_ROOT:-$RDX/..}" 2>/dev/null && pwd)"
# FPC=<pfad> ueberschreibt den Compiler; fehlt er, ist das ein Umgebungs-
# fehler (Exit 2), kein gescheiterter Bau (Review reDelphiX nach Bereichen
# 2026-10-10, Nit 54).
FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
MARK=.pruefstand
if [ $# -eq 0 ]; then
  echo "Aufruf: build.sh <testunit> [<testunit> ...]" >&2
  exit 2
fi
if [ ! -x "$FPC" ]; then
  echo "FPC nicht gefunden: $FPC (FPC=<pfad> setzen)" >&2
  exit 2
fi
if [ -z "$SCA" ] || [ ! -d "$SCA/SCA.Engine/sources" ]; then
  echo "SCA-Wurzel nicht gefunden: ${SCA_ROOT:-$RDX/..}" >&2
  exit 2
fi

# Bricht ab, wenn eine Pflichtquelle fehlt.
need() {
  if [ ! -f "$1" ]; then
    echo "Quelle fehlt: $1" >&2
    exit 2
  fi
}

# --- 0) Arbeitsverzeichnis ---------------------------------------------------
if [ -n "${PRUEFSTAND_DIR:-}" ]; then
  if [ -d "$PRUEFSTAND_DIR" ] && [ ! -f "$PRUEFSTAND_DIR/$MARK" ] \
     && [ -n "$(ls -A "$PRUEFSTAND_DIR" 2>/dev/null)" ]; then
    echo "PRUEFSTAND_DIR=$PRUEFSTAND_DIR ist nicht leer und kein Pruefstand-Verzeichnis (Marke $MARK fehlt) - ein leeres oder neues Verzeichnis angeben" >&2
    exit 2
  fi
  mkdir -p "$PRUEFSTAND_DIR" || exit 2
  WORK="$(cd "$PRUEFSTAND_DIR" && pwd)"
  find "$WORK" -mindepth 1 -delete || exit 2
  : > "$WORK/$MARK"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/rdx-pruefstand.XXXXXX")" || exit 2
  trap 'cd "$HERE" && rm -rf "$WORK"' EXIT
  WORK="$(cd "$WORK" && pwd)" || exit 2
fi
OUT="$WORK/out"
mkdir -p "$OUT" || exit 2
BRANCH="$(git -C "$SCA" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
REV="$(git -C "$SCA" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "Pruefstand: SCA=$SCA ($BRANCH @ $REV)  RDX=$RDX  Arbeitsverzeichnis=$WORK"
# Neben dem Skript liegen die eingecheckten Stubs (uParser2, uAstNode,
# HashStub, DUnitX ...) und - genau nach den Mustern der .gitignore -
# Kopien frueherer Laeufe bzw. Grabsteine: diese weg (die Grabsteine
# kommen in Schritt 2 neu), nur die Stubs ins Arbeitsverzeichnis.
OLD=()
STUBS=()
for f in "$HERE"/*.pas "$HERE"/*.inc; do
  [ -e "$f" ] || continue
  case "${f##*/}" in
    uDetectorUtils.pas|uRefactor*.pas|uSourcePlaces.pas|uFindingActions.pas|uRdx*.pas|uRdx*.inc|uTest*.pas|runner.pas)
      OLD+=("$f") ;;
    *) STUBS+=("$f") ;;
  esac
done
rm -rf "$HERE/out" ${OLD[@]+"${OLD[@]}"}
cp "${STUBS[@]}" "$WORK/" || exit 2
need "$WORK/DUnitX.TestFramework.pas"
need "$WORK/uLocalization.pas"

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
} > "$WORK/uDetectorUtils.pas"

# --- 2) echte Units + Tests kopieren und fuer FPC 3.2.2 anpassen ------------
# adapt <zielverzeichnis> <datei> ...: je Datei eine Kopie gleichen Namens.
# Felder mit -F"'": ungerade = ausserhalb eines String-Literals ('' im
# Literal ergibt ein leeres Feld dazwischen, das nichts zu ersetzen hat).
# Ein Attribut steht nur am Zeilenanfang, also im ersten Feld. Das
# Zielverzeichnis kommt ueber die Umgebung: awk -v wertet Backslashes im
# Wert als Escapes ('C:\Users\..\tmp' -> '\t' wird ein Tabulator).
adapt() {
  local dir="$1"
  shift
  ADAPT_DIR="$dir" awk -F"'" -v OFS="'" '
    BEGIN { dir = ENVIRON["ADAPT_DIR"] }
    FNR == 1 {
      if (out != "") close(out)
      out = FILENAME
      sub(/^.*[\/\\]/, "", out)
      out = dir "/" out
    }
    {
      sub(/\r$/, "")
      if ($1 ~ /^[[:space:]]*\[TestFixture\]/) sub(/\[TestFixture\]/, "", $1)
      if ($1 ~ /^[[:space:]]*\[Test\]/) sub(/\[Test\] */, "", $1)
      for (i = 1; i <= NF; i += 2) {
        gsub(/System\.SysUtils/, "SysUtils", $i)
        gsub(/System\.Classes/, "Classes", $i)
        gsub(/System\.Hash/, "HashStub", $i)
        gsub(/System\.StrUtils/, "StrUtils", $i)
        gsub(/System\.SyncObjs/, "SyncObjs", $i)
        gsub(/System\.IOUtils/, "IOUtils", $i)
        gsub(/System\.Generics\.Collections/, "Generics.Collections", $i)
        gsub(/Assert\.AreEqual<Integer>\(/, "Assert.AreEqualInt(", $i)
      }
      print > out
    }
    END { if (out != "") close(out) }' "$@"
}
UNITS=()
for u in uRefactorInfo uRefactorInfoBuilder uRefactorConcat uFindingActions; do
  need "$SCA/SCA.Engine/sources/Common/$u.pas"
  UNITS+=("$SCA/SCA.Engine/sources/Common/$u.pas")
done
need "$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas"
UNITS+=("$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas")
# Modul reDelphix: nur die ToolsAPI-freien Units (Rezepte, Scope-Tabelle).
# Fehlt eine, scheitern nur die Tests, die sie brauchen - deshalb Warnung.
# FPC sucht Units nur im Arbeitsverzeichnis - eine neue Unit muss in diese
# Liste.
for u in uRdxText uRdxRecipes uRdxPaths uRdxScopeTable uRdxBufferMath uRdxCodeMap uRdxBlocks uRdxSuppress uRdxSimpleFixes uRdxStructFixes uRdxLineFixes uRdxRaiseFixes uRdxDeclFixes uRdxFlowFixes uRdxRoutineFixes uRdxCleanupFixes uRdxTryFixes uRdxResultFixes uRdxSqlTemplate uRdxIntroPlan uRdxIntroEdits uRdxRtlTypes uRdxCompilerTraces uRdxMagicFixes; do
  if [ -f "$RDX/source/$u.pas" ]; then
    UNITS+=("$RDX/source/$u.pas")
  else
    echo "WARNUNG: $RDX/source/$u.pas fehlt - Testunits, die $u brauchen, scheitern beim Bau" >&2
  fi
done
adapt "$WORK" "${UNITS[@]}" || exit 2
# Grabsteine (s. Kopf): je kopierter Unit und fuer uDetectorUtils eine
# Quelle neben dem Skript, an der FPC sofort mit dem Hinweis abbricht.
for u in uDetectorUtils.pas "${UNITS[@]##*/}"; do
  u="${u%.pas}"
  printf '%s\n' \
    "{ Grabstein von build.sh: die angepassten Kopien liegen im Arbeitsverzeichnis des Laufs (Kopf von build.sh). }" \
    "{\$FATAL $u: keine Pruefstand-Kopie neben build.sh - PRUEFSTAND_DIR=<eigen> bash build.sh <testunit>, dann fpc -Fu<eigen> mit frischem -FU}" \
    "unit $u;" "" "interface" "" "implementation" "" "end." > "$HERE/$u.pas" || exit 2
done
# Die erzeugte Typliste (uRdxRtlTypes.inc, {$I} in uRdxRtlTypes) kommt als
# Kopie mit - FPC sucht Include-Dateien neben der Unit.
need "$RDX/source/uRdxRtlTypes.inc"
tr -d '\r' < "$RDX/source/uRdxRtlTypes.inc" > "$WORK/uRdxRtlTypes.inc"
# Sprache (Entscheid E29, Charge C0): uRdxText uebersetzt ueber den
# eingecheckten Stub uLocalization.pas (die echte Unit uebersetzt unter FPC
# 3.2.2 nicht). Der Stub liest die ECHTEN i18n/*.po neben dem Runner
# (out/i18n/ - wie <Modul>\i18n\<lang>.po der echten Unit), frisch je Lauf:
# eine deutsche Erwartung prueft so zugleich die msgid in i18n/de.po.
need "$SCA/i18n/de.po"
mkdir -p "$OUT/i18n"
cp "$SCA"/i18n/*.po "$OUT/i18n/"

# --- 3) Testunits finden und pruefen -----------------------------------------
SRCS=()
for t in "$@"; do
  src="$SCA/StaticCodeAnalyserForm/tests/$t.pas"
  [ -f "$RDX/tests/$t.pas" ] && src="$RDX/tests/$t.pas"
  if [ ! -f "$src" ]; then
    echo "Testunit $t.pas weder in $RDX/tests noch in $SCA/StaticCodeAnalyserForm/tests" >&2
    exit 2
  fi
  SRCS+=("$src")
done

# Registrierung: je Datei die [TestFixture]-Klassen ohne
# TDUnitX.RegisterTestFixture(<Klasse>) - Ausgabe 'name.pas: klasse ...'.
mapfile -t REGFILES < <(printf '%s\n' "${SRCS[@]}" "$RDX"/tests/uTest*.pas | sort -u)
UNREG="$(awk '
  function flush(   i, miss) {
    miss = ""
    for (i = 1; i <= n; i++)
      if (!(cls[i] in reg)) miss = miss " " cls[i]
    if (miss != "") print file ":" miss
  }
  FNR == 1 {
    if (NR > 1) flush()
    file = FILENAME; sub(/^.*[\/\\]/, "", file); n = 0; want = 0
    split("", cls); split("", reg)
  }
  { sub(/\r$/, "") }
  /^[[:space:]]*\[TestFixture/ { want = 1; next }
  want && match($0, /^[[:space:]]*T[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*class/) {
    s = substr($0, RSTART, RLENGTH)
    sub(/^[[:space:]]*/, "", s)
    sub(/[[:space:]]*=.*$/, "", s)
    cls[++n] = s
    want = 0
  }
  match($0, /RegisterTestFixture\([[:space:]]*T[A-Za-z0-9_]+/) {
    s = substr($0, RSTART, RLENGTH)
    sub(/^RegisterTestFixture\([[:space:]]*/, "", s)
    reg[s] = 1
  }
  END { if (NR > 0) flush() }' "${REGFILES[@]}")"
if [ -n "$UNREG" ]; then
  while IFS= read -r line; do
    echo "${line%%:*}: Fixture${line#*:} ohne TDUnitX.RegisterTestFixture im initialization-Teil - ein DUnitX-Runner mit UseRTTI = False liesse sie still aus" >&2
  done <<< "$UNREG"
  exit 2
fi

# Der Runner kennt genau EINE Fixture mit einfachen [Test]-Methoden: eine
# zweite Fixture oder [Setup]/[TearDown]/[TestCase] liefe hier still anders
# als unter DUnitX (Review reDelphiX nach Bereichen 2026-10-10, Nit 55).
# Ausgabe je Datei: 'fixtures sonderattribut tests'.
mapfile -t STATS < <(awk '
  function flush() { print fix, bad, tests }
  FNR == 1 { if (NR > 1) flush(); fix = 0; bad = 0; tests = 0 }
  { sub(/\r$/, "") }
  /^[[:space:]]*\[TestFixture/ { fix++ }
  /\[(Setup|TearDown|SetupFixture|TearDownFixture)\]|\[TestCase/ { bad = 1 }
  /^[[:space:]]*\[Test\]/ { tests++ }
  END { if (NR > 0) flush() }' "${SRCS[@]}")
if [ ${#STATS[@]} -ne ${#SRCS[@]} ]; then
  echo "Testunits ohne Inhalt? ${#SRCS[@]} Dateien, ${#STATS[@]} gelesen" >&2
  exit 2
fi
EXPECTED=()
for k in "${!SRCS[@]}"; do
  read -r fixtures bad tests <<< "${STATS[$k]}"
  if [ "$fixtures" != "1" ] || [ "$bad" != "0" ]; then
    echo "$(basename "${SRCS[$k]}" .pas): $fixtures Fixture(s) oder [Setup]/[TearDown]/[TestCase] - der Pruefstand-Runner kann nur EINE Fixture mit einfachen [Test]-Methoden" >&2
    exit 2
  fi
  EXPECTED+=("$tests")
done
adapt "$WORK" "${SRCS[@]}" || exit 2
COPIES=()
for src in "${SRCS[@]}"; do COPIES+=("$WORK/${src##*/}"); done

# Je angepasster Testunit die Fixture-Klasse ('C name') und die Methoden
# '    procedure Name;' ('P name'), eingeleitet von 'F datei'.
declare -A CLS PROCS
current=""
while read -r kind name; do
  case "$kind" in
    F) current="$name" ;;
    C) CLS[$current]="$name" ;;
    P) PROCS[$current]="${PROCS[$current]:-} $name" ;;
  esac
done < <(awk '
  FNR == 1 { f = FILENAME; sub(/^.*[\/\\]/, "", f); sub(/\.pas$/, "", f); print "F", f; c = 0 }
  !c && /^  T[A-Za-z0-9_]+ = class$/ { print "C", $1; c = 1 }
  /^    procedure [A-Za-z0-9_]+;/ { p = $2; sub(/;.*$/, "", p); print "P", p }' \
  "${COPIES[@]}")

# --- 4) Runner erzeugen ------------------------------------------------------
# Laeuft in der aktuellen Shell (Gruppe, keine Subshell): ein exit hier
# beendet das Skript, Meldungen gehen deshalb nach stderr; total zaehlt die
# [Test]-Attribute aller Testunits fuer den Abgleich mit dem Lauf.
total=0
{
  printf 'program runner;\n\nuses\n  SysUtils, DUnitX.TestFramework, uRdxText'
  for t in "$@"; do printf ',\n  %s' "$t"; done
  printf ';\n\n'
  cat <<'PAS'
type
  TTestProc = procedure of object;

var
  Passed, Failed : Integer;

// Ein Test ohne Assert ist rot (AssertCalls zaehlt der Stub
// DUnitX.TestFramework) - wie TestInsight und reDelphix.Test.
procedure Run(const AName: string; AProc: TTestProc);
begin
  AssertCalls := 0;
  try
    AProc();
    if AssertCalls > 0 then
      Inc(Passed)
    else
    begin
      Inc(Failed);
      Writeln('FAIL ', AName, ': kein Assert (FailsOnNoAsserts)');
    end;
  except
    on E: ETestPass do Inc(Passed);
    on E: Exception do
    begin
      Inc(Failed);
      Writeln('FAIL ', AName, ': ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

PAS
  for k in "${!SRCS[@]}"; do
    t="${SRCS[$k]##*/}"
    t="${t%.pas}"
    cls="${CLS[$t]:-}"
    procs="${PROCS[$t]:-}"
    # Abgleich: jede [Test]-Methode muss als '    procedure Name;' erkannt
    # sein, sonst fehlte ihr Run()-Aufruf und der Lauf meldete trotzdem gruen.
    got=0
    for p in $procs; do got=$((got + 1)); done
    if [ -z "$cls" ] || [ "${EXPECTED[$k]}" != "$got" ]; then
      echo "$t: Fixture-Klasse '${cls:-?}', [Test]-Attribute ${EXPECTED[$k]}, erkannte Testmethoden $got - Abbruch" >&2
      exit 2
    fi
    total=$((total + got))
    printf 'procedure RunSuite%d;\nvar\n  T : %s;\nbegin\n  T := %s.Create;\n  try\n' "$((k + 1))" "$cls" "$cls"
    for p in $procs; do
      printf "    Run('%s.%s', T.%s);\n" "$t" "$p" "$p"
    done
    printf '  finally\n    T.Free;\n  end;\nend;\n\n'
  done
  printf 'begin\n  Passed := 0;\n  Failed := 0;\n'
  # Die reDelphix-Texte deutsch wie in reDelphix.Test.dpr: die Erwartungen
  # der Tests sind deutsch, und redelphix.ini bzw. %APPDATA% bleiben aus
  # dem Lauf heraus (uRdxText liest mit Override keine ini).
  printf "  SetRdxLanguageOverride('de');\n"
  for k in "${!SRCS[@]}"; do printf '  RunSuite%d;\n' "$((k + 1))"; done
  printf "  Writeln('PASSED ', Passed, '  FAILED ', Failed);\n  if Failed > 0 then Halt(1);\nend.\n"
} > "$WORK/runner.pas"

# --- 5) bauen und laufen lassen ----------------------------------------------
# FPC schreibt erst in eine Datei: der Exit-Code zaehlt (ein Pipe-Ende
# verdeckte ihn), angezeigt werden die ersten 60 Zeilen ohne Kopfzeilen.
cd "$WORK" || exit 2
"$FPC" -Mdelphiunicode -Sh -gl -vew -FEout -FUout runner.pas > fpc.log 2>&1
frc=$?
tr -d '\r' < fpc.log \
  | grep -vE '^(Free Pascal|Copyright|Target OS|Compiling|Linking|[0-9]+ lines compiled)' | head -60
if [ $frc -ne 0 ] || [ ! -f "$OUT/runner.exe" ]; then
  echo "KEIN runner.exe - Bau gescheitert (FPC-Exit $frc)"
  exit 1
fi
# Der Runner laeuft im Skriptverzeichnis wie bis Charge FF: Tests suchen
# Daten des Checkouts vom Arbeitsverzeichnis des Prozesses aus aufwaerts
# (uTestRdxRecipes: data\unitscopes.txt); geschrieben wird dort nichts,
# Tests schreiben nach TEMP.
( cd "$HERE" && "$OUT/runner.exe" ) > "$WORK/run.log" 2>&1
rc=$?
tr -d '\r' < "$WORK/run.log"
echo "runner exit=$rc"
# Abgleich mit den [Test]-Attributen: ein fremdes oder abgebrochenes
# Ergebnis (anderer runner.exe, Absturz vor der Zusammenfassung) ist nie
# gruen (Review R6-02).
summary="$(tr -d '\r' < "$WORK/run.log" | grep -E '^PASSED [0-9]+  FAILED [0-9]+$' | tail -1)"
if [ -z "$summary" ]; then
  echo "Lauf ohne Zusammenfassung 'PASSED n  FAILED m' - abgebrochen?" >&2
  [ $rc -ne 0 ] && exit $rc
  exit 1
fi
read -r _ passed _ failed <<< "$summary"
if [ $((passed + failed)) -ne "$total" ]; then
  echo "Der Lauf zaehlt $((passed + failed)) Tests, die Testunits tragen $total [Test]-Attribute - das Ergebnis gehoert nicht zu diesem Aufruf" >&2
  exit 1
fi
exit $rc
