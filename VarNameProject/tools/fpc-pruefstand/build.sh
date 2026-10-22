#!/usr/bin/env bash
# FPC-Pruefstand fuer die ToolsAPI-freien Units von VarNameProject
# (source/uVnpPlan.pas, source/uVnpEdits.pas) und ihre DUnitX-Testunits
# (tests/uTestVnp*.pas) - dieselben Tests, die tests/VarNameProject.Test.dpr
# in Delphi faehrt, hier ohne IDE (FPC 3.2.2, i386-win32). Muster:
# reDelphix/tools/fpc-pruefstand, aber eigenstaendig (VarNameProject haengt
# weder an SCA.Engine noch an reDelphix).
# Aufruf: build.sh [<testunit> ...]   ohne Argument: alle tests/uTestVnp*.pas
# WORK=<ordner> legt Kopien, runner.pas und out/ dort ab (Vorgabe: work/
#   neben diesem Skript) - so stoeren sich zwei Laeufe nicht.
# FPC=<pfad> ueberschreibt den Compiler.
# Exit: 0 alle Tests gruen; 1 Test rot oder Bau gescheitert; 2 Aufruf- oder
#   Quellfehler, auch wenn die Zahl der [Test]-Attribute einer Testunit
#   nicht zur Zahl der erkannten Testmethoden passt (der Runner liesse sonst
#   Tests still aus).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VNP="$(cd "$HERE/../.." && pwd)"
FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe}"
WORK="${WORK:-$HERE/work}"
if [ ! -x "$FPC" ]; then
  echo "FPC nicht gefunden: $FPC (FPC=<pfad> setzen)" >&2
  exit 2
fi
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

# Fuer FPC 3.2.2 anpassen: Namensraeume, DUnitX-Attribute, generisches
# AreEqual<Integer> (der Shim kennt AreEqualInt).
# Nur AUSSERHALB von String-Literalen (Felder mit -F"'": ungerade = Code),
# ein Attribut nur am Zeilenanfang - wie adapt in reDelphix/tools/
# fpc-pruefstand/build.sh (Review R6-03). Vorher ersetzte sed auch in
# Literalen: ein Test mit 'System.SysUtils' oder '[Test] ' im Text sah
# unter FPC andere Daten als unter Delphi (Review Woche 2026-10-21, G10-01).
adapt() {
  awk -F"'" -v OFS="'" '
    {
      sub(/\r$/, "")
      if ($1 ~ /^[[:space:]]*\[TestFixture\]/) sub(/\[TestFixture\]/, "", $1)
      if ($1 ~ /^[[:space:]]*\[Test\]/) sub(/\[Test\] */, "", $1)
      for (i = 1; i <= NF; i += 2) {
        gsub(/System\.SysUtils/, "SysUtils", $i)
        gsub(/System\.Classes/, "Classes", $i)
        gsub(/System\.StrUtils/, "StrUtils", $i)
        gsub(/System\.Generics\.Collections/, "Generics.Collections", $i)
        gsub(/Assert\.AreEqual<Integer>\(/, "Assert.AreEqualInt(", $i)
      }
      print
    }' "$1" > "$2"
}

for u in uVnpPlan uVnpEdits; do
  if [ ! -f "$VNP/source/$u.pas" ]; then
    echo "Quelle fehlt: $VNP/source/$u.pas" >&2
    exit 2
  fi
  adapt "$VNP/source/$u.pas" "$WORK/$u.pas"
done
cp "$HERE/DUnitX.TestFramework.pas" "$WORK/" || exit 2

# Runner erzeugen. Laeuft in der aktuellen Shell (Gruppe, keine Subshell):
# ein exit hier beendet das Skript, Meldungen gehen deshalb nach stderr.
{
  printf 'program runner;\n\nuses\n  SysUtils, DUnitX.TestFramework'
  for t in "$@"; do printf ',\n  %s' "$t"; done
  printf ';\n\ntype\n  TTestProc = procedure of object;\n\nvar\n  Passed, Failed : Integer;\n\n'
  printf 'procedure Run(const AName: string; AProc: TTestProc);\nbegin\n  try\n    AProc();\n    Inc(Passed);\n'
  printf '  except\n    on E: ETestPass do Inc(Passed);\n    on E: Exception do\n    begin\n      Inc(Failed);\n'
  printf "      Writeln('FAIL ', AName, ': ', E.ClassName, ': ', E.Message);\n    end;\n  end;\nend;\n\n"
  n=0
  for t in "$@"; do
    src="$VNP/tests/$t.pas"
    if [ ! -f "$src" ]; then
      echo "Testunit fehlt: $src" >&2
      exit 2
    fi
    # Der Runner kennt genau EINE Fixture mit einfachen [Test]-Methoden:
    # eine zweite Fixture oder [Setup]/[TearDown]/[TestCase] liefe hier
    # still anders als unter DUnitX.
    fixtures=$(tr -d '\r' < "$src" | grep -cE '^[[:space:]]*\[TestFixture')
    if [ "$fixtures" != "1" ] \
       || tr -d '\r' < "$src" | grep -qE '\[(Setup|TearDown|SetupFixture|TearDownFixture)\]|\[TestCase'; then
      echo "$t: $fixtures Fixture(s) oder [Setup]/[TearDown]/[TestCase] - der Runner kann nur EINE Fixture mit einfachen [Test]-Methoden" >&2
      exit 2
    fi
    adapt "$src" "$WORK/$t.pas"
    cls=$(grep -oE '^  T[A-Za-z0-9_]+ = class$' "$WORK/$t.pas" | head -1 | awk '{print $1}')
    # Abgleich: jede [Test]-Methode muss als '    procedure Name;' erkannt
    # sein, sonst fehlte ihr Run()-Aufruf und der Lauf meldete trotzdem gruen.
    expected=$(tr -d '\r' < "$src" | grep -cE '^[[:space:]]*\[Test\]')
    procs=$(grep -oE '^    procedure [A-Za-z0-9_]+;' "$WORK/$t.pas" | awk '{gsub(";","",$2); print $2}')
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
} > "$WORK/runner.pas"

# FPC schreibt erst in eine Datei: sein Exit zaehlt (das Pipe-Ende verdeckte
# ihn), angezeigt werden die ersten 60 Zeilen ohne Kopfzeilen. Jeder Exit
# des Runners ungleich 0 wird 1 (Vertrag oben: 0/1/2) - ein Absturz endete
# sonst mit FPCs Laufzeitfehler-Code 216/217. Wie reDelphix/tools/
# fpc-pruefstand/build.sh (Review Woche 2026-10-21, G10-01/G10-21).
cd "$WORK" || exit 2
"$FPC" -Mdelphiunicode -Sh -gl -vew -FEout -FUout runner.pas > fpc.log 2>&1
frc=$?
tr -d '\r' < fpc.log \
  | grep -vE '^(Free Pascal|Copyright|Target OS|Compiling|Linking|[0-9]+ lines compiled)' | head -60
if [ $frc -ne 0 ] || [ ! -f "$WORK/out/runner.exe" ]; then
  echo "KEIN runner.exe - Bau gescheitert (FPC-Exit $frc)"
  exit 1
fi
"$WORK/out/runner.exe"
rc=$?
echo "runner exit=$rc"
[ $rc -ne 0 ] && exit 1
exit 0
