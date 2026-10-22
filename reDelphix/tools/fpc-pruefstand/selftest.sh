#!/usr/bin/env bash
# Selbsttest des FPC-Pruefstands build.sh (Review reDelphix R6-02, R6-03,
# R6-06, R6-09). Jeder Fall ruft build.sh mit kleinen Testunits und prueft
# Exit-Code und Ausgabe. Das build.sh vor Charge FF (4358b769) besteht
# keinen Fall: zwei Laeufe teilten runner.pas (je nach Zeitlage fremdes
# Gruen oder 'String exceeds line'), der FPC-Exit, die Testzahl, die
# Registrierung und Asserts zaehlten nicht, PRUEFSTAND_DIR gab es nicht.
#   1. zwei Laeufe zugleich im selben Checkout: jeder meldet SEINE Tests,
#      die Waechter-Unit uTestRdxBench (R6-03, Literale) laeuft mit;
#   2. FPC scheitert, obwohl runner.exe entsteht: Exit 1 (der FPC-Exit
#      zaehlt, nicht die Datei);
#   3. ein Runner mit weniger Tests, als die Testunits tragen: Exit 1;
#   4. eine Testunit ohne TDUnitX.RegisterTestFixture: Exit 2;
#   5. ein Test ohne Assert: rot (FailsOnNoAsserts wie TestInsight);
#   6. PRUEFSTAND_DIR: ein fremdes, nicht leeres Verzeichnis wird
#      abgelehnt, ein eigenes geleert und behalten;
#   7. ein Harness nach altem Muster (-Fu<Skriptverzeichnis>, bleibendes
#      -FU-Verzeichnis, die Quellen seiner .ppu sind weg): FPC bricht am
#      Grabstein ab, mit und ohne -B, statt die alte .ppu still zu nehmen;
#   8. TMPDIR im Windows-Stil mit Backslashes: der Lauf ist gruen;
#   9. die Hilfs-Unit uTestRdxTextKit (Review R6-08): jeder Lauf legt ihre
#      angepasste Kopie ab, auch wenn keine aufgerufene Testunit sie bindet;
#      als Aufrufargument Exit 2 (keine Fixture);
#  10. zwei sichtbare Fixtures und eine Detektor-Fixture in {$IFNDEF FPC}:
#      zwei Suiten, nur die sichtbaren Tests (Folgewelle B3);
#  11. {$IFDEF FPC}..{$ELSE}..{$ENDIF} um Fixtures, {$IFNDEF FPC} um einen
#      Test im Klassenrumpf;
#  12. verschachtelte Bedingung im FPC-Bereich und {$IF DEFINED(FPC)}:
#      Exit 2 vor dem Bau.
# Die Faelle 10 bis 12 kamen mit der Folgewelle B3; das build.sh davor
# bricht 10 und 11 mit "nur EINE Fixture" ab und meldet 12 mit derselben
# Meldung statt der Direktive. Ohne echten FPC (FPC=<Fake-FPC>, der nur
# runner.pas auswertet) zeigen 5 und 7 FEHLER - sie brauchen den Compiler
# bzw. einen echten Runner.
# Die Faelle 7 und 8 kamen mit der Nachbesserung der Charge FF; das build.sh
# des ersten Durchgangs (88713262) besteht sie nicht. Fall 9a besteht erst
# das build.sh mit R6-08 (davor kopierte es die Hilfs-Unit nicht).
# Die Faelle 4 und 5 laufen gegen eine Mini-SCA-Wurzel im Temp-Verzeichnis
# (SCA_ROOT) - der Checkout bleibt unberuehrt; Fall 7 liest die Grabsteine
# neben dem Skript nur.
# Aufruf: bash selftest.sh    Exit: 0 alle Faelle wie erwartet, 1 sonst.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCA="$(cd "$HERE/../../.." && pwd)"
BUILD="$HERE/build.sh"
REAL_FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rdx-pruefstand-selftest.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
bad=0

# verdict <status der pruefung: 0 = erfuellt> <fall> <log> - den Status
# vorher in eine Variable: eine $(..) im Text des Falls setzte $? zurueck.
verdict() {
  if [ "$1" -eq 0 ]; then
    echo "OK     $2"
  else
    echo "FEHLER $2"
    sed -e 's/^/       | /' "$3" | tail -8
    bad=1
  fi
}

# Summe der [Test]-Attribute der Testunits aus reDelphix\tests.
tests_of() {
  local n=0 u
  for u in "$@"; do
    n=$((n + $(tr -d '\r' < "$HERE/../../tests/$u.pas" | grep -cE '^[[:space:]]*\[Test\]')))
  done
  echo "$n"
}

# 1) zwei Laeufe zugleich im selben Checkout
A_UNITS="uTestRdxBench uTestRdxSuppress uTestRdxCodeMap"
B_UNITS="uTestRdxBufferMath"
bash "$BUILD" $A_UNITS > "$TMP/1a.txt" 2>&1 &
pa=$!
# B startet, sobald A seinen Kopf geschrieben hat (A kopiert dann gerade).
for i in $(seq 1 300); do
  grep -q '^Pruefstand:' "$TMP/1a.txt" 2>/dev/null && break
  sleep 0.1
done
bash "$BUILD" $B_UNITS > "$TMP/1b.txt" 2>&1
rb=$?
wait $pa
ra=$?
grep -qx "PASSED $(tests_of $A_UNITS)  FAILED 0" "$TMP/1a.txt" && [ $ra -eq 0 ]
ok=$?
verdict $ok "1a zwei Laeufe zugleich - Lauf A meldet seine $(tests_of $A_UNITS) Tests" "$TMP/1a.txt"
grep -qx "PASSED $(tests_of $B_UNITS)  FAILED 0" "$TMP/1b.txt" && [ $rb -eq 0 ]
ok=$?
verdict $ok "1b zwei Laeufe zugleich - Lauf B meldet seine $(tests_of $B_UNITS) Tests" "$TMP/1b.txt"

# fpc_wrapper <datei> <zeilen vor dem echten FPC> <zeilen danach>: ein
# Ersatz-FPC (FPC=<datei>), der den echten FPC aufruft.
fpc_wrapper() {
  {
    printf '#!/usr/bin/env bash\nREAL_FPC=%q\n%s\n' "$REAL_FPC" "$2"
    printf '"$REAL_FPC" "$@"\n%s\n' "$3"
  } > "$1"
}

# 2) FPC scheitert, runner.exe entsteht trotzdem
fpc_wrapper "$TMP/fpc_fails.sh" '' 'exit 1'
FPC="$TMP/fpc_fails.sh" bash "$BUILD" uTestRdxBench > "$TMP/2.txt" 2>&1
r=$?
[ $r -eq 1 ] && grep -q 'Bau gescheitert (FPC-Exit 1)' "$TMP/2.txt"
ok=$?
verdict $ok "2  FPC-Exit 1 bei vorhandenem runner.exe -> Exit 1" "$TMP/2.txt"

# 3) der Runner laesst eine Suite aus (wie ein fremder runner.pas)
fpc_wrapper "$TMP/fpc_short.sh" "sed -i '/^  RunSuite1;\$/d' runner.pas" ''
FPC="$TMP/fpc_short.sh" bash "$BUILD" uTestRdxBench uTestRdxSuppress > "$TMP/3.txt" 2>&1
r=$?
[ $r -eq 1 ] && grep -q 'Der Lauf zaehlt' "$TMP/3.txt"
ok=$?
verdict $ok "3  Runner ohne eine Suite -> Exit 1 (Abgleich mit den [Test]-Attributen)" "$TMP/3.txt"

# Mini-SCA-Wurzel fuer die Faelle 4 und 5: die Pflichtquellen des Cores,
# i18n und eine Testunit unter StaticCodeAnalyserForm\tests.
M="$TMP/sca"
mkdir -p "$M/SCA.Engine/sources/Common" "$M/SCA.Engine/sources/Infrastructure" \
         "$M/StaticCodeAnalyserForm/tests" "$M/i18n"
# uScaConfigDir steht seit dbb4c1fa in der Pflichtliste von build.sh - ohne
# die Kopie brachen 4 und 5 an "Quelle fehlt" ab statt am Gepruefen.
for u in uDetectorUtils uRefactorInfo uRefactorInfoBuilder uRefactorConcat uFindingActions uScaConfigDir; do
  cp "$SCA/SCA.Engine/sources/Common/$u.pas" "$M/SCA.Engine/sources/Common/"
done
cp "$SCA/SCA.Engine/sources/Infrastructure/uSourcePlaces.pas" "$M/SCA.Engine/sources/Infrastructure/"
cp "$SCA"/i18n/*.po "$M/i18n/"
# mini_unit <name> <rumpf des einen Tests> <initialization-Teil>
mini_unit() {
  printf 'unit %s;\n\ninterface\n\nuses\n  DUnitX.TestFramework;\n\ntype\n  [TestFixture]\n  T%s = class\n  public\n    [Test]\n    procedure One;\n  end;\n\nimplementation\n\nprocedure T%s.One;\nbegin\n%s\nend;\n\n%s\nend.\n' \
    "$1" "$1" "$1" "$2" "$3" > "$M/StaticCodeAnalyserForm/tests/$1.pas"
}

# 4) Testunit ohne Registrierung
mini_unit uTestNoReg '  Assert.IsTrue(True);' ''
SCA_ROOT="$M" bash "$BUILD" uTestNoReg > "$TMP/4.txt" 2>&1
r=$?
[ $r -eq 2 ] && grep -q 'uTestNoReg.pas: Fixture TuTestNoReg ohne TDUnitX.RegisterTestFixture' "$TMP/4.txt"
ok=$?
verdict $ok "4  Testunit ohne RegisterTestFixture -> Exit 2" "$TMP/4.txt"
rm -f "$M/StaticCodeAnalyserForm/tests/uTestNoReg.pas"

# 5) Test ohne Assert
mini_unit uTestNoAssert '  // kein Assert' \
  'initialization
  TDUnitX.RegisterTestFixture(TuTestNoAssert);
'
SCA_ROOT="$M" bash "$BUILD" uTestNoAssert > "$TMP/5.txt" 2>&1
r=$?
[ $r -eq 1 ] && grep -q 'FAIL uTestNoAssert.One: kein Assert' "$TMP/5.txt" \
  && grep -qx 'PASSED 0  FAILED 1' "$TMP/5.txt"
ok=$?
verdict $ok "5  Test ohne Assert -> rot" "$TMP/5.txt"

# 6) PRUEFSTAND_DIR
mkdir -p "$TMP/fremd"
echo bleibt > "$TMP/fremd/notiz.txt"
PRUEFSTAND_DIR="$TMP/fremd" bash "$BUILD" uTestRdxBench > "$TMP/6a.txt" 2>&1
r=$?
[ $r -eq 2 ] && [ -f "$TMP/fremd/notiz.txt" ]
ok=$?
verdict $ok "6a fremdes Verzeichnis als PRUEFSTAND_DIR -> Exit 2, nichts geloescht" "$TMP/6a.txt"
PRUEFSTAND_DIR="$TMP/eigen" bash "$BUILD" uTestRdxBench > "$TMP/6b.txt" 2>&1
r1=$?
echo alt > "$TMP/eigen/uRdxAlt.pas"
PRUEFSTAND_DIR="$TMP/eigen" bash "$BUILD" uTestRdxBench >> "$TMP/6b.txt" 2>&1
r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && [ -f "$TMP/eigen/.pruefstand" ] \
  && [ -f "$TMP/eigen/uTestRdxBench.pas" ] && [ -f "$TMP/eigen/out/runner.exe" ] \
  && [ ! -f "$TMP/eigen/uRdxAlt.pas" ]
ok=$?
verdict $ok "6b eigenes PRUEFSTAND_DIR: geleert, Kopien und runner.exe bleiben" "$TMP/6b.txt"

# Windows-Pfad fuer den FPC (ein Windows-Programm); ohne cygpath bleibt er.
winpath() {
  cygpath -w "$1" 2>/dev/null || printf '%s' "$1"
}

# 7) Harness nach altem Muster: gebaut gegen Kopien, die es nicht mehr
#    gibt (wie die Kopien neben dem Skript bis Charge FF), neu gebaut mit
#    -Fu<Skriptverzeichnis> und demselben -FU-Verzeichnis.
H="$TMP/harness"
mkdir -p "$H/out"
printf 'program h;\n\nuses\n  uRdxCodeMap;\n\nbegin\nend.\n' > "$H/h.pas"
PRUEFSTAND_DIR="$TMP/hps" bash "$BUILD" uTestRdxBench > "$TMP/7.txt" 2>&1
# Die Kopien eine Stunde zurueck - so alt ist ein alter Bau mindestens
# (FPC vergleicht die Dateizeit der Quelle mit der in der .ppu).
touch -d '1 hour ago' "$TMP/hps"/*.pas >> "$TMP/7.txt" 2>&1
( cd "$H" && "$REAL_FPC" -Mdelphiunicode -Fu"$(winpath "$TMP/hps")" -FEout -FUout h.pas ) >> "$TMP/7.txt" 2>&1
r0=$?
rm -rf "$TMP/hps"
( cd "$H" && "$REAL_FPC" -Mdelphiunicode -Fu"$(winpath "$HERE")" -FEout -FUout h.pas ) > "$TMP/7a.txt" 2>&1
r1=$?
( cd "$H" && "$REAL_FPC" -B -Mdelphiunicode -Fu"$(winpath "$HERE")" -FEout -FUout h.pas ) > "$TMP/7b.txt" 2>&1
r2=$?
[ $r0 -eq 0 ] && [ $r1 -ne 0 ] && grep -q 'uRdxCodeMap: keine Pruefstand-Kopie neben build.sh' "$TMP/7a.txt"
ok=$?
cat "$TMP/7a.txt" >> "$TMP/7.txt"
verdict $ok "7a Harness mit -Fu<Skriptverzeichnis> und alter .ppu -> Abbruch am Grabstein" "$TMP/7.txt"
[ $r0 -eq 0 ] && [ $r2 -ne 0 ] && grep -q 'uRdxCodeMap: keine Pruefstand-Kopie neben build.sh' "$TMP/7b.txt"
ok=$?
verdict $ok "7b dasselbe mit -B" "$TMP/7b.txt"

# 8) TMPDIR im Windows-Stil: '\t' in '...\tmpdir' las awk -v als Tabulator
#    ('fatal: can't redirect'), '\n' in 'C:\Users\n...' als Zeilenende.
mkdir -p "$TMP/tmpdir"
TMPDIR="$(winpath "$TMP")\\tmpdir" bash "$BUILD" uTestRdxBench > "$TMP/8.txt" 2>&1
r=$?
[ $r -eq 0 ] && grep -qx "PASSED $(tests_of uTestRdxBench)  FAILED 0" "$TMP/8.txt" \
  && [ -z "$(ls -A "$TMP/tmpdir")" ]
ok=$?
verdict $ok "8  TMPDIR mit Backslashes -> gruen, Arbeitsverzeichnis danach weg" "$TMP/8.txt"

# 9) Hilfs-Unit: die Kopie liegt im PRUEFSTAND_DIR aus Fall 6b (gebaut mit
#    uTestRdxBench, das sie nicht bindet) - angepasst wie eine Quelle.
K="$TMP/eigen/uTestRdxTextKit.pas"
[ -f "$K" ] && grep -q 'SysUtils, Classes,' "$K" && ! grep -q 'System\.SysUtils' "$K"
ok=$?
verdict $ok "9a Hilfs-Unit uTestRdxTextKit angepasst mitkopiert, ohne dass eine Testunit sie bindet" "$TMP/6b.txt"
bash "$BUILD" uTestRdxTextKit > "$TMP/9.txt" 2>&1
r=$?
[ $r -eq 2 ] && grep -q 'uTestRdxTextKit: 0 Fixture' "$TMP/9.txt"
ok=$?
verdict $ok "9b Hilfs-Unit als Aufrufargument -> Exit 2 (keine Fixture)" "$TMP/9.txt"

# Die Faelle 10 bis 12 (Folgewelle B3) laufen gegen die Mini-SCA-Wurzel;
# die Testunits liegen unter StaticCodeAnalyserForm\tests. runner.pas
# bleibt im PRUEFSTAND_DIR zum Nachlesen.
MT="$M/StaticCodeAnalyserForm/tests"

# 10) zwei sichtbare Fixtures und eine Detektor-Fixture in {$IFNDEF FPC}
#     (samt Delphi-only uses, Implementierung und Registrierung): beide
#     sichtbaren laufen, die dritte nicht; ein {$IFDEF X} im Literal und
#     ein {$IFNDEF FPC} im Kommentar schalten nichts.
cat > "$MT/uTestTwoFix.pas" <<'PAS'
unit uTestTwoFix;

// Kommentar mit {$IFNDEF FPC} - keine Direktive.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTwoFixText = class
  public
    [Test] procedure One;
    [Test]
    procedure Two;
  end;

  [TestFixture]
  TTwoFixMore = class
  public
    [Test] procedure Three;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTwoFixDetector = class
  public
    [Test] procedure DelphiOne;
    [Test] procedure DelphiTwo;
  end;
{$ENDIF}

implementation

{$IFNDEF FPC}
uses
  uNurDelphi;
{$ENDIF}

const
  SAMPLE = '{$IFDEF X} {$ENDIF}';

procedure TTwoFixText.One;
begin
  Assert.IsTrue(SAMPLE <> '');
end;

procedure TTwoFixText.Two;
begin
  Assert.IsTrue(True);
end;

procedure TTwoFixMore.Three;
begin
  Assert.IsTrue(True);
end;

{$IFNDEF FPC}
procedure TTwoFixDetector.DelphiOne;
begin
  NurDelphi;
end;

procedure TTwoFixDetector.DelphiTwo;
begin
  NurDelphi;
end;
{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTwoFixText);
  TDUnitX.RegisterTestFixture(TTwoFixMore);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTwoFixDetector);
  {$ENDIF}
end.
PAS
SCA_ROOT="$M" PRUEFSTAND_DIR="$TMP/p10" bash "$BUILD" uTestTwoFix > "$TMP/10.txt" 2>&1
r=$?
R10="$TMP/p10/runner.pas"
[ $r -eq 0 ] && grep -qx 'PASSED 3  FAILED 0' "$TMP/10.txt" \
  && [ "$(grep -c '^procedure RunSuite' "$R10")" -eq 2 ] \
  && grep -q "Run('uTestTwoFix.Two', T.Two);" "$R10" \
  && grep -q "Run('uTestTwoFix.Three', T.Three);" "$R10" \
  && ! grep -q 'TTwoFixDetector\|DelphiOne\|DelphiTwo' "$R10"
ok=$?
verdict $ok "10 zwei Fixtures + Detektor-Fixture in {\$IFNDEF FPC} -> zwei Suiten, 3 Tests" "$TMP/10.txt"

# 11) {$IFDEF FPC}..{$ELSE}..{$ENDIF} (klein geschrieben) um zwei Fixtures
#     und {$IFNDEF FPC} um einen einzelnen Test im Klassenrumpf.
cat > "$MT/uTestFpcElse.pas" <<'PAS'
unit uTestFpcElse;

interface

uses
  DUnitX.TestFramework;

type
{$ifdef fpc}
  [TestFixture]
  TFpcSide = class
  public
    [Test] procedure OnFpc;
  end;
{$else}
  [TestFixture]
  TDelphiSide = class
  public
    [Test] procedure OnDelphiOne;
    [Test] procedure OnDelphiTwo;
  end;
{$endif}

  [TestFixture]
  TBothSides = class
  public
    [Test] procedure Always;
    {$IFNDEF FPC}
    [Test] procedure DelphiOnly;
    {$ENDIF}
  end;

implementation

{$IFDEF FPC}
procedure TFpcSide.OnFpc;
begin
  Assert.IsTrue(True);
end;
{$ELSE}
procedure TDelphiSide.OnDelphiOne;
begin
  NurDelphi;
end;

procedure TDelphiSide.OnDelphiTwo;
begin
  NurDelphi;
end;
{$ENDIF}

procedure TBothSides.Always;
begin
  Assert.IsTrue(True);
end;

{$IFNDEF FPC}
procedure TBothSides.DelphiOnly;
begin
  NurDelphi;
end;
{$ENDIF}

initialization
  {$IFDEF FPC}
  TDUnitX.RegisterTestFixture(TFpcSide);
  {$ELSE}
  TDUnitX.RegisterTestFixture(TDelphiSide);
  {$ENDIF}
  TDUnitX.RegisterTestFixture(TBothSides);
end.
PAS
SCA_ROOT="$M" PRUEFSTAND_DIR="$TMP/p11" bash "$BUILD" uTestFpcElse > "$TMP/11.txt" 2>&1
r=$?
R11="$TMP/p11/runner.pas"
[ $r -eq 0 ] && grep -qx 'PASSED 2  FAILED 0' "$TMP/11.txt" \
  && grep -q "Run('uTestFpcElse.OnFpc', T.OnFpc);" "$R11" \
  && grep -q "Run('uTestFpcElse.Always', T.Always);" "$R11" \
  && ! grep -q 'TDelphiSide\|OnDelphi\|DelphiOnly' "$R11"
ok=$?
verdict $ok "11 {\$IFDEF FPC}/{\$ELSE} und {\$IFNDEF FPC} im Klassenrumpf -> 2 Tests" "$TMP/11.txt"

# 12) andere Formen brechen laut ab (Exit 2), statt falsch zu zaehlen:
#     a) eine Bedingung im {$IFNDEF FPC}-Bereich (verschachtelt),
#     b) {$IF DEFINED(FPC)} statt {$IFDEF FPC}.
# nest_unit <name> <zeilen vor der zweiten Fixture> <zeilen danach>
nest_unit() {
  printf 'unit %s;\n\ninterface\n\nuses\n  DUnitX.TestFramework;\n\ntype\n  [TestFixture]\n  T%sA = class\n  public\n    [Test] procedure One;\n  end;\n\n%s\n  [TestFixture]\n  T%sB = class\n  public\n    [Test] procedure Two;\n  end;\n%s\n\nimplementation\n\nprocedure T%sA.One;\nbegin\n  Assert.IsTrue(True);\nend;\n\nprocedure T%sB.Two;\nbegin\n  Assert.IsTrue(True);\nend;\n\ninitialization\n  TDUnitX.RegisterTestFixture(T%sA);\n  TDUnitX.RegisterTestFixture(T%sB);\nend.\n' \
    "$1" "$1" "$2" "$1" "$3" "$1" "$1" "$1" "$1" > "$MT/$1.pas"
}
nest_unit uTestNested '{$IFNDEF FPC}
  {$IFDEF MSWINDOWS}' '  {$ENDIF}
{$ENDIF}'
SCA_ROOT="$M" bash "$BUILD" uTestNested > "$TMP/12a.txt" 2>&1
r=$?
[ $r -eq 2 ] && grep -q 'uTestNested.pas:16: {\$IFDEF MSWINDOWS} in einem FPC-Bereich (verschachtelt)' "$TMP/12a.txt" \
  && ! grep -q 'FAKEFPC\|PASSED' "$TMP/12a.txt"
ok=$?
verdict $ok "12a verschachtelte Bedingung im {\$IFNDEF FPC}-Bereich -> Exit 2" "$TMP/12a.txt"
nest_unit uTestIfDefined '{$IF DEFINED(FPC)}' '{$IFEND}'
SCA_ROOT="$M" bash "$BUILD" uTestIfDefined > "$TMP/12b.txt" 2>&1
r=$?
[ $r -eq 2 ] && grep -q 'uTestIfDefined.pas:15: Direktive {\$IF DEFINED(FPC)}' "$TMP/12b.txt"
ok=$?
verdict $ok "12b {\$IF DEFINED(FPC)} -> Exit 2" "$TMP/12b.txt"

exit $bad
