# shellcheck shell=bash
# Gemeinsame Bausteine der FPC-Pruefstaende (DUnitX-Testunits ohne IDE unter
# FPC 3.2.2 laufen lassen) - zum Einbinden mit 'source', nicht zum Aufruf.
#
# WARUM (Review Woche 2026-10-21, G10-01; Folgewelle A7): die Runner-
# Erzeugung stand dreimal im Baum (reDelphix/tools/fpc-pruefstand/build.sh,
# VarNameProject/tools/fpc-pruefstand/build.sh, SCA.SharedUI/tools/
# run_fpc_pure.sh), und die Kopien liefen auseinander: die Lehren R6-02
# (Testzahl gegen die [Test]-Attribute) und R6-03 (Anpassung nur ausserhalb
# von String-Literalen) kamen nicht in jede. Hier steht jede Regel einmal.
# Die Skripte behalten, was nur sie betrifft: Quellen, Arbeitsverzeichnis,
# Stubs, Grabsteine, Registrierungspruefung, Sprache des Laufs.
#
# Nutzer: SCA.SharedUI/tools/run_fpc_pure.sh, VarNameProject/tools/
# fpc-pruefstand/build.sh, reDelphix/tools/fpc-pruefstand/build.sh (seit
# Folgewelle B3).
#
# Vertrag der Funktionen: keine ruft exit - sie melden Fehler auf stderr
# und geben 1 (rot/gescheitert) oder 2 (Aufruf-/Quellfehler) zurueck; der
# Aufrufer entscheidet ('|| exit 2'). Sie erwarten FPC (Pfad zum Compiler)
# in der Umgebung.

# fpc_adapt <zielverzeichnis> <datei> ...: je Datei eine fuer FPC 3.2.2
# angepasste Kopie gleichen Namens. Ersetzt wird nur AUSSERHALB von String-
# Literalen (Felder mit -F"'": ungerade = Code; '' im Literal ergibt ein
# leeres Feld dazwischen, das nichts zu ersetzen hat; Review R6-03), ein
# Attribut nur am Zeilenanfang, also im ersten Feld:
# - System.<Unit> -> <Unit> fuer SysUtils, Classes, Types, Math, StrUtils,
#   SyncObjs, IOUtils, Generics.Collections (FPC 3.2.2 kennt keine
#   Namensraeume der RTL; eine Quelle ohne diese Units bleibt gleich);
# - FPC_ADAPT_EXTRA (Umgebung): weitere Paare 'alt=neu', durch Leerzeichen
#   getrennt, woertlich ersetzt (reDelphix: 'System.Hash=HashStub');
# - [TestFixture] und [Test] am Zeilenanfang weg;
# - Assert.AreEqual<Integer>( -> Assert.AreEqualInt( (der Shim kennt das
#   generische AreEqual nicht).
# Die Zeilen bleiben, FPC-Meldungen nennen die Zeilennummern der Quellen;
# CR am Zeilenende faellt weg. Das Zielverzeichnis kommt ueber die Umgebung:
# awk -v wertet Backslashes im Wert als Escapes ('C:\Users\..\tmp' -> '\t'
# wird ein Tabulator).
fpc_adapt() {
  local dir="$1"
  shift
  ADAPT_DIR="$dir" ADAPT_EXTRA="${FPC_ADAPT_EXTRA:-}" awk -F"'" -v OFS="'" '
    function literal(s, from, to,   r, p) {
      r = ""
      while ((p = index(s, from)) > 0) {
        r = r substr(s, 1, p - 1) to
        s = substr(s, p + length(from))
      }
      return r s
    }
    BEGIN {
      dir = ENVIRON["ADAPT_DIR"]
      nx = split(ENVIRON["ADAPT_EXTRA"], pairs, " ")
      for (k = 1; k <= nx; k++) {
        eq = index(pairs[k], "=")
        xfrom[k] = substr(pairs[k], 1, eq - 1)
        xto[k] = substr(pairs[k], eq + 1)
      }
    }
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
        gsub(/System\.Types/, "Types", $i)
        gsub(/System\.Math/, "Math", $i)
        gsub(/System\.StrUtils/, "StrUtils", $i)
        gsub(/System\.SyncObjs/, "SyncObjs", $i)
        gsub(/System\.IOUtils/, "IOUtils", $i)
        gsub(/System\.Generics\.Collections/, "Generics.Collections", $i)
        for (k = 1; k <= nx; k++)
          if (xfrom[k] != "") $i = literal($i, xfrom[k], xto[k])
        gsub(/Assert\.AreEqual<Integer>\(/, "Assert.AreEqualInt(", $i)
      }
      print > out
    }
    END { if (out != "") close(out) }' "$@"
}

# fpc_fixture_info <quelle> <angepasste kopie>: setzt FPC_CLS (die Klasse
# der Fixture), FPC_PROCS (die Methoden '    procedure Name;' der Kopie,
# durch Zeilenwechsel getrennt), FPC_GOT (ihre Zahl) und FPC_EXPECTED (die
# [Test]-Attribute der Quelle). Der Runner kennt genau EINE Fixture mit
# einfachen [Test]-Methoden: eine zweite Fixture oder [Setup]/[TearDown]/
# [TestCase] liefe hier still anders als unter DUnitX (Review reDelphiX nach
# Bereichen 2026-10-10, Nit 55) - dann Meldung und 2. Den Abgleich
# FPC_GOT gegen FPC_EXPECTED macht der Aufrufer (seine Meldung).
fpc_fixture_info() {
  local src="$1" copy="$2" name fixtures
  name="$(basename "$src" .pas)"
  fixtures=$(tr -d '\r' < "$src" | grep -cE '^[[:space:]]*\[TestFixture')
  if [ "$fixtures" != "1" ] \
     || tr -d '\r' < "$src" | grep -qE '\[(Setup|TearDown|SetupFixture|TearDownFixture)\]|\[TestCase'; then
    echo "$name: $fixtures Fixture(s) oder [Setup]/[TearDown]/[TestCase] - der Runner kann nur EINE Fixture mit einfachen [Test]-Methoden" >&2
    return 2
  fi
  FPC_CLS=$(grep -oE '^  T[A-Za-z0-9_]+ = class$' "$copy" | head -1 | awk '{print $1}')
  FPC_EXPECTED=$(tr -d '\r' < "$src" | grep -cE '^[[:space:]]*\[Test\]')
  FPC_PROCS=$(grep -oE '^    procedure [A-Za-z0-9_]+;' "$copy" | awk '{gsub(";","",$2); print $2}')
  FPC_GOT=$(printf '%s' "$FPC_PROCS" | grep -c .)
  return 0
}

# fpc_runner_head <unit> ...: Kopf von runner.pas - program, uses (SysUtils,
# DUnitX.TestFramework und die genannten Units), TTestProc, die Zaehler und
# Run(). Mit FPC_RUNNER_NOASSERT_FAILS=1 ist ein Test ohne Assert rot (der
# Shim zaehlt AssertCalls - wie TestInsight und reDelphix.Test); ohne
# zaehlt er als gruen.
fpc_runner_head() {
  local u
  printf 'program runner;\n\nuses\n  SysUtils, DUnitX.TestFramework'
  for u in "$@"; do printf ',\n  %s' "$u"; done
  printf ';\n\ntype\n  TTestProc = procedure of object;\n\nvar\n  Passed, Failed : Integer;\n\n'
  if [ "${FPC_RUNNER_NOASSERT_FAILS:-0}" = "1" ]; then
    printf '%s\n' \
      '// Ein Test ohne Assert ist rot (AssertCalls zaehlt der Stub' \
      '// DUnitX.TestFramework) - wie TestInsight und reDelphix.Test.' \
      'procedure Run(const AName: string; AProc: TTestProc);' \
      'begin' \
      '  AssertCalls := 0;' \
      '  try' \
      '    AProc();' \
      '    if AssertCalls > 0 then' \
      '      Inc(Passed)' \
      '    else' \
      '    begin' \
      '      Inc(Failed);' \
      "      Writeln('FAIL ', AName, ': kein Assert (FailsOnNoAsserts)');" \
      '    end;'
  else
    printf 'procedure Run(const AName: string; AProc: TTestProc);\nbegin\n  try\n    AProc();\n    Inc(Passed);\n'
  fi
  printf '  except\n    on E: ETestPass do Inc(Passed);\n    on E: Exception do\n    begin\n      Inc(Failed);\n'
  printf "      Writeln('FAIL ', AName, ': ', E.ClassName, ': ', E.Message);\n    end;\n  end;\nend;\n\n"
}

# fpc_runner_suite <n> <testunit> <klasse> <methode> ...: die Prozedur
# RunSuite<n> - eine Instanz der Fixture, je Methode ein Run('<testunit>.
# <methode>', ...).
fpc_runner_suite() {
  local n="$1" t="$2" cls="$3" p
  shift 3
  printf 'procedure RunSuite%d;\nvar\n  T : %s;\nbegin\n  T := %s.Create;\n  try\n' "$n" "$cls" "$cls"
  for p in "$@"; do
    printf "    Run('%s.%s', T.%s);\n" "$t" "$p" "$p"
  done
  printf '  finally\n    T.Free;\n  end;\nend;\n\n'
}

# fpc_runner_main <n> [<anweisung>]: Hauptprogramm - Zaehler auf 0, die
# Anweisung (etwa "SetRdxLanguageOverride('de');"), RunSuite1..<n>, die
# Zusammenfassung 'PASSED n  FAILED m', Halt(1) bei rotem Test.
fpc_runner_main() {
  local n="$1" pre="${2:-}" k
  printf 'begin\n  Passed := 0;\n  Failed := 0;\n'
  [ -n "$pre" ] && printf '  %s\n' "$pre"
  for ((k = 1; k <= n; k++)); do printf '  RunSuite%d;\n' "$k"; done
  printf "  Writeln('PASSED ', Passed, '  FAILED ', Failed);\n  if Failed > 0 then Halt(1);\nend.\n"
}

# fpc_build <verzeichnis> <name fuer die Meldung> [<schalter> ...]:
# uebersetzt <verzeichnis>/runner.pas nach <verzeichnis>/out (-Mdelphiunicode
# -Sh -gl, die Schalter, -vew). FPC schreibt erst in fpc.log: sein Exit
# zaehlt (ein Pipe-Ende verdeckte ihn, und ein alter runner.exe galt als
# gebaut); angezeigt werden die ersten 60 Zeilen ohne Kopfzeilen. 0 =
# gebaut, sonst Meldung und 1.
fpc_build() {
  local dir="$1" what="$2" frc
  shift 2
  ( cd "$dir" && "$FPC" -Mdelphiunicode -Sh -gl "$@" -vew -FEout -FUout \
      runner.pas > fpc.log 2>&1 )
  frc=$?
  tr -d '\r' < "$dir/fpc.log" \
    | grep -vE '^(Free Pascal|Copyright|Target OS|Compiling|Linking|[0-9]+ lines compiled)' | head -60
  if [ $frc -ne 0 ] || [ ! -f "$dir/out/runner.exe" ]; then
    echo "KEIN runner.exe${what:+ fuer $what} - Bau gescheitert (FPC-Exit $frc)"
    return 1
  fi
  return 0
}

# fpc_run_check <runner.exe> <logdatei> <erwartete tests> <meldung> [rc]:
# laesst den Runner im aktuellen Verzeichnis laufen, zeigt seine Ausgabe
# (mit 'rc' als 5. Argument danach 'runner exit=<code>') und setzt
# FPC_RUN_RC auf seinen Exit. Ein Lauf ohne Zusammenfassung 'PASSED n
# FAILED m' (Absturz) oder mit einer anderen Testzahl als den [Test]-
# Attributen (fremdes Ergebnis) ist nie gruen (Review R6-02) - Meldung
# 'Der Lauf zaehlt <x> Tests, <meldung>'. 0 nur, wenn beides stimmt und der
# Runner mit 0 endet, sonst 1 (nie 216/217 - Vertrag 0/1/2, G10-21).
fpc_run_check() {
  local exe="$1" log="$2" expected="$3" msg="$4" summary passed failed
  "$exe" > "$log" 2>&1
  FPC_RUN_RC=$?
  tr -d '\r' < "$log"
  [ "${5:-}" = "rc" ] && echo "runner exit=$FPC_RUN_RC"
  summary="$(tr -d '\r' < "$log" | grep -E '^PASSED [0-9]+  FAILED [0-9]+$' | tail -1)"
  if [ -z "$summary" ]; then
    echo "Lauf ohne Zusammenfassung 'PASSED n  FAILED m' - abgebrochen?" >&2
    return 1
  fi
  read -r _ passed _ failed <<< "$summary"
  if [ $((passed + failed)) -ne "$expected" ]; then
    echo "Der Lauf zaehlt $((passed + failed)) Tests, $msg" >&2
    return 1
  fi
  [ "$FPC_RUN_RC" -eq 0 ] || return 1
  return 0
}
