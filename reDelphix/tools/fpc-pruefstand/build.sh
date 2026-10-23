#!/usr/bin/env bash
# FPC-Pruefstand fuer die RefactorInfo-/SourcePlaces-Units des SCA-Cores und
# die Rezepte des Moduls reDelphix.
# Aufruf: build.sh <testunit> [<testunit> ...]
#   Testunits kommen aus <SCA>\StaticCodeAnalyserForm\tests
#   oder - wenn dort vorhanden - aus reDelphix\tests.
#   Die Hilfs-Unit der Testunits (reDelphix\tests\uTestRdxTextKit: Join,
#   Apply, LineOf, WriteText, Temp-Verzeichnisse - keine Fixture, Review
#   R6-08) kopiert und passt jeder Lauf mit an wie eine Quelle; sie ist
#   kein Aufrufargument.
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
# Bausteine: Anpassung der Quellen, Fixture-Erkennung, Runner, Bau und
#   Abgleich der Testzahl kommen aus tools/fpc_runner_lib.sh im
#   Wurzelverzeichnis DIESES Checkouts (auch bei SCA_ROOT) - gemeinsam mit
#   SCA.SharedUI/tools/run_fpc_pure.sh und VarNameProject (Review Woche
#   2026-10-21, G10-01; Folgewelle A7, Umstellung B3). Hier bleibt, was nur
#   diesen Pruefstand betrifft: Quellen und Unit-Liste, Stubs, Grabsteine,
#   Registrierungspruefung, Sprache des Laufs.
# Anpassung fuer FPC 3.2.2 (fpc_adapt): System.SysUtils -> SysUtils & Co.,
#   System.Hash -> HashStub (FPC_ADAPT_EXTRA), Assert.AreEqual<Integer>( ->
#   Assert.AreEqualInt( und [TestFixture]/[Test] am Zeilenanfang weg -
#   alles nur AUSSERHALB von String-Literalen: ein Test, der einen
#   qualifizierten Unitnamen oder ein Attribut als Text prueft, sieht unter
#   FPC dieselben Daten wie unter Delphi (Review R6-03; bis dahin wurde aus
#   dem Literal 'System.Classes' 'Classes' und aus '    [Test]' '    ').
#   Die Zeilen bleiben, FPC-Meldungen nennen die Zeilennummern der Quellen.
# Runner: je FPC-sichtbarer Fixture einer Testunit eine RunSuite, nur
#   einfache [Test]-Methoden. Sichtbar heisst: nicht in {$IFNDEF FPC}..
#   {$ENDIF} bzw. im {$ELSE}-Teil von {$IFDEF FPC} (nur diese einfache,
#   nicht verschachtelte Form; jede andere Bedingungs-Direktive ausserhalb
#   von Literalen und Kommentaren bricht mit Exit 2 ab). So laufen
#   Testunits mit Text-Fixture und Delphi-only Detektor-Fixture (Folgewelle
#   B3). Ein Test ohne Assert ist rot - wie unter TestInsight und
#   reDelphix.Test (FailsOnNoAsserts = True, Review R6-09).
# Exit: 0 alle Tests gruen; 1 Test rot, Bau gescheitert (FPC-Exit) oder der
#   Lauf zaehlt nicht genau so viele Tests, wie die Testunits sichtbare
#   [Test]-Attribute tragen; 2 Aufruf- oder Quellfehler, auch wenn die Zahl
#   der sichtbaren [Test]-Attribute einer Testunit nicht zur Zahl der
#   erkannten Testmethoden passt (der Runner liesse sonst Tests still aus),
#   eine Testunit eine unbekannte Bedingungs-Direktive traegt oder eine
#   Testunit - aufgerufen oder in reDelphix\tests - eine Fixture nicht mit
#   TDUnitX.RegisterTestFixture anmeldet (ein DUnitX-Runner mit UseRTTI =
#   False liesse sie still aus, Review R6-06).
# Je Arbeitsschritt moeglichst EIN awk-Aufruf ueber alle Dateien: ein
# Prozessstart kostet unter Git Bash 50 ms und mehr (die Fixture-Erkennung
# braucht einen je Testunit).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RDX="$(cd "$HERE/../.." && pwd)"
SCA="$(cd "${SCA_ROOT:-$RDX/..}" 2>/dev/null && pwd)"
# FPC=<pfad> ueberschreibt den Compiler; fehlt er, ist das ein Umgebungs-
# fehler (Exit 2), kein gescheiterter Bau (Review reDelphiX nach Bereichen
# 2026-10-10, Nit 54).
FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
LIB="$(cd "$RDX/.." && pwd)/tools/fpc_runner_lib.sh"
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
if [ ! -f "$LIB" ]; then
  echo "Bausteine fehlen: $LIB" >&2
  exit 2
fi
# shellcheck source=../../../tools/fpc_runner_lib.sh
. "$LIB"

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
    uDetectorUtils.pas|uRefactor*.pas|uSourcePlaces.pas|uFindingActions.pas|uScaConfigDir.pas|uSCAConsts.pas|uRdx*.pas|uRdx*.inc|uTest*.pas|runner.pas)
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
# adapt <zielverzeichnis> <datei> ...: fpc_adapt der Bausteine, dazu
# System.Hash -> HashStub (der eingecheckte Stub neben dem Skript).
adapt() {
  FPC_ADAPT_EXTRA='System.Hash=HashStub' fpc_adapt "$@"
}
UNITS=()
# uSCAConsts gehoert NICHT hierher: die Planer-Testunits der Chargen Q/R
# binden sie nur hinter {$IFNDEF FPC} (Hygiene H2) - FPC hat sie nie
# uebersetzt, ein Lauf haengt so nicht an einer ungeprueften Unit.
for u in uRefactorInfo uRefactorInfoBuilder uRefactorConcat uFindingActions uScaConfigDir; do
  need "$SCA/SCA.Engine/sources/Common/$u.pas"
  UNITS+=("$SCA/SCA.Engine/sources/Common/$u.pas")
done
need "$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas"
UNITS+=("$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas")
# Modul reDelphix: nur die ToolsAPI-freien Units (Rezepte, Scope-Tabelle).
# Fehlt eine, scheitern nur die Tests, die sie brauchen - deshalb Warnung.
# FPC sucht Units nur im Arbeitsverzeichnis - eine neue Unit muss in diese
# Liste. Von den Planer-Units stehen nur die neun hier, deren Testunits
# im FPC-sichtbaren Teil ohne uRdxFixTable/uRdxRecipeRunner/Detektor
# auskommen (Folgewelle B3, README "Pruefen"): die sieben der Chargen Q/R
# (uRdxCategoryArgFix .. uRdxTrailingCommaFix), dazu seit Charge A3/A4
# uRdxLoopBoundFix (SCA203) und uRdxInheritedEmptyFix (SCA125).
for u in uRdxText uRdxRecipes uRdxPaths uRdxScopeTable uRdxBufferMath uRdxCodeMap uRdxBlocks uRdxSuppress uRdxSimpleFixes uRdxStructFixes uRdxLineFixes uRdxRaiseFixes uRdxDeclFixes uRdxFlowFixes uRdxRoutineFixes uRdxCleanupFixes uRdxTryFixes uRdxResultFixes uRdxSqlTemplate uRdxIntroPlan uRdxIntroEdits uRdxRtlTypes uRdxCompilerTraces uRdxMagicFixes uRdxTypeProof uRdxTrySpan uRdxHandOver uRdxInheritedFixes uRdxSqlFacts uRdxCategoryArgFix uRdxEmptyBlockFix uRdxEmptyExceptFix uRdxGotoExitFix uRdxNativeIntFix uRdxParensFix uRdxTrailingCommaFix uRdxLoopBoundFix uRdxInheritedEmptyFix; do
  if [ -f "$RDX/source/$u.pas" ]; then
    UNITS+=("$RDX/source/$u.pas")
  else
    echo "WARNUNG: $RDX/source/$u.pas fehlt - Testunits, die $u brauchen, scheitern beim Bau" >&2
  fi
done
# Die Hilfs-Unit der Testunits (Review R6-08: bis dahin je Testunit eine
# Kopie von Join, Apply, LineOf ...) kommt bei JEDEM Lauf mit, unabhaengig
# von den aufgerufenen Testunits - FPC uebersetzt sie nur, wenn eine sie
# bindet. Sie hat keine Fixture: die Registrierungspruefung in Schritt 3
# sieht in ihr keine Klasse (wie in uTestRdxDetectorKit), als
# Aufrufargument scheitert sie an "genau EINE Fixture" (Exit 2).
need "$RDX/tests/uTestRdxTextKit.pas"
UNITS+=("$RDX/tests/uTestRdxTextKit.pas")
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

# Je Testunit die angepasste Kopie und ihre FPC-sichtbaren Fixtures
# (fpc_fixtures): eine Fixture in {$IFNDEF FPC}..{$ENDIF} - etwa die
# Detektor-Fixture neben der Text-Fixture einer Planer-Testunit - zaehlt
# und laeuft nicht, jede sichtbare bekommt ihre RunSuite. Keine sichtbare
# Fixture, ein sichtbares [Setup]/[TearDown]/[TestCase] (liefe hier still
# anders als unter DUnitX, Review reDelphiX nach Bereichen 2026-10-10,
# Nit 55) oder eine andere Bedingungs-Direktive als die einfache FPC-Form
# (lieber laut als falsch gezaehlt): Exit 2. Alle Testunits werden
# geprueft, bevor runner.pas entsteht: ein Abbruch laesst keinen halben
# Runner im Arbeitsverzeichnis.
adapt "$WORK" "${SRCS[@]}" || exit 2
SUITES=()
total=0
for k in "${!SRCS[@]}"; do
  t="${SRCS[$k]##*/}"
  t="${t%.pas}"
  fpc_fixtures "${SRCS[$k]}" "$WORK/$t.pas" || exit 2
  # Abgleich: jede sichtbare [Test]-Methode muss als '    procedure Name;'
  # im Rumpf einer sichtbaren Fixture erkannt sein, sonst fehlte ihr
  # Run()-Aufruf und der Lauf meldete trotzdem gruen.
  classes=""
  while read -r cls _; do
    [ -n "$cls" ] && classes="${classes:+$classes }$cls"
  done <<< "$FPC_FIXTURES"
  if [[ " $classes " == *" ? "* ]] || [ "$FPC_EXPECTED" != "$FPC_GOT" ]; then
    echo "$t: Fixture-Klasse '$classes', [Test]-Attribute $FPC_EXPECTED, erkannte Testmethoden $FPC_GOT - Abbruch" >&2
    exit 2
  fi
  while read -r line; do
    [ -n "$line" ] && SUITES+=("$t $line")
  done <<< "$FPC_FIXTURES"
  total=$((total + FPC_GOT))
done

# --- 4) Runner erzeugen ------------------------------------------------------
# Je sichtbarer Fixture eine RunSuite (Run('<testunit>.<methode>', ..)).
# total zaehlt die sichtbaren [Test]-Attribute aller Testunits fuer den
# Abgleich mit dem Lauf. Ein Test ohne Assert ist rot
# (FPC_RUNNER_NOASSERT_FAILS, Review R6-09).
{
  FPC_RUNNER_NOASSERT_FAILS=1 fpc_runner_head uRdxText "$@"
  for k in "${!SUITES[@]}"; do
    # shellcheck disable=SC2086 # '<testunit> <klasse> <methode> ...'
    fpc_runner_suite "$((k + 1))" ${SUITES[$k]}
  done
  # Die reDelphix-Texte deutsch wie in reDelphix.Test.dpr: die Erwartungen
  # der Tests sind deutsch, und redelphix.ini bzw. %APPDATA% bleiben aus
  # dem Lauf heraus (uRdxText liest mit Override keine ini).
  fpc_runner_main "${#SUITES[@]}" "SetRdxLanguageOverride('de');"
} > "$WORK/runner.pas"

# --- 5) bauen und laufen lassen ----------------------------------------------
# fpc_build: der FPC-Exit zaehlt (ein Pipe-Ende verdeckte ihn), angezeigt
# werden die ersten 60 Zeilen ohne Kopfzeilen.
fpc_build "$WORK" "" || exit 1
# Der Runner laeuft im Skriptverzeichnis wie bis Charge FF: Tests suchen
# Daten des Checkouts vom Arbeitsverzeichnis des Prozesses aus aufwaerts
# (uTestRdxRecipes: data\unitscopes.txt); geschrieben wird dort nichts,
# Tests schreiben nach TEMP.
# fpc_run_check: ein fremdes oder abgebrochenes Ergebnis (anderer
# runner.exe, Absturz vor der Zusammenfassung) ist nie gruen (Review
# R6-02), und jeder Exit des Runners ungleich 0 wird 1 (Vertrag im Kopf:
# 0/1/2) - ein Absturz endet sonst mit FPCs Laufzeitfehler-Code (216
# Zugriffsverletzung, 217 unbehandelte Ausnahme), und ein Aufrufer, der 1 =
# rot von 2 = Aufruffehler trennt, ordnete den Lauf falsch ein (Review Woche
# 2026-10-21, G10-21). Der Code selbst steht in 'runner exit='.
cd "$HERE" || exit 2
fpc_run_check "$OUT/runner.exe" "$WORK/run.log" "$total" \
  "die Testunits tragen $total [Test]-Attribute - das Ergebnis gehoert nicht zu diesem Aufruf" rc \
  || exit 1
exit 0
