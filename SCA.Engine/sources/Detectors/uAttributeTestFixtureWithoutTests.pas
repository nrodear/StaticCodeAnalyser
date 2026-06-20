unit uAttributeTestFixtureWithoutTests;

// Detektor: Klasse mit `[TestFixture]`-Attribute aber kein `[Test]`-
// Method drin.
//
// Pattern (Test-Hygiene):
//   [TestFixture]
//   TFooTests = class
//   public
//     procedure Setup;             // <-- kein [Test], kein [Setup]
//     procedure DoSomething;       // <-- kein [Test]
//   end;
//   // Zombie-Fixture: TestInsight sieht die Klasse, fuehrt aber nichts aus.
//
// Erkennung (file-text-scan, simple state-machine):
//   * State pro File: aktuelles Klassen-Fenster (zwischen
//     `[TestFixture]`-Line und Klasse-`end;`).
//   * Pro Zeile: pruefen ob `[TestFixture]` (oeffnet Window), `class`-
//     Decl (markiert Klassen-Start mit Line), `end;` mit korrektem
//     Indent (schliesst Klasse), `[Test]` (markiert Test-Vorhanden).
//   * Beim Schliessen: wenn TestVorhanden=False -> Finding auf
//     `[TestFixture]`-Line.
//
// FP-Risiken:
//   * `[SetupFixture]`-only Klassen (preparieren Shared-State) waeren
//     legitim aber wuerden geflagt. Akzeptiert - der User kann
//     suppressen.
//   * Verschachtelte/inline-Klassen wuerden den Indent-Heuristic-
//     scope-Check verwirren - selten in der Praxis.
//
// Severity: lsWarning, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAttributeTestFixtureWithoutTestsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

const
  TESTFIXTURE_RE = '\[TestFixture\b';
  TEST_RE        = '\[Test(\b|\(|\s*\])';
  CLASS_END_RE   = '^\s*end\s*;\s*$';
  CLASS_DECL_RE  = '\bclass\b';

class procedure TAttributeTestFixtureWithoutTestsDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Code        : string;
  State       : TCommentScanState;
  Dummy       : Integer;
  ReFixture, ReTest, ReEnd, ReClass : TRegEx;
  InFixture   : Boolean;
  FixtureLine : Integer;
  HasTest     : Boolean;
  F           : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    State       := Default(TCommentScanState);
    ReFixture   := TRegEx.Create(TESTFIXTURE_RE, [roIgnoreCase]);
    ReTest      := TRegEx.Create(TEST_RE,        [roIgnoreCase]);
    ReEnd       := TRegEx.Create(CLASS_END_RE,   [roIgnoreCase]);
    ReClass     := TRegEx.Create(CLASS_DECL_RE,  [roIgnoreCase]);
    InFixture   := False;
    FixtureLine := 0;
    HasTest     := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Dummy);

      try
        if not InFixture then
        begin
          if ReFixture.IsMatch(Code) then
          begin
            InFixture   := True;
            FixtureLine := i + 1;
            HasTest     := False;
          end;
        end
        else
        begin
          // Innerhalb Fixture-Klasse: nach [Test] suchen, oder Klassen-Ende.
          if ReTest.IsMatch(Code) then HasTest := True;
        end;
      except
        Continue;
      end;
      if InFixture then
      begin
        // Heuristic: `end;` an Zeilen-Anfang (= Klassen-/Record-Ende
        // auf Top-Level, nicht innerhalb method).
        if ReEnd.IsMatch(Lines[i]) then
        begin
          if not HasTest then
          begin
            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := '';
            F.LineNumber := IntToStr(FixtureLine);
            F.MissingVar := '[TestFixture] class has no [Test] method ' +
                            '(zombie fixture). TestInsight sees the class ' +
                            'but executes nothing.';
            F.SetKind(fkAttributeTestFixtureWithoutTests);
            Results.Add(F);
          end;
          InFixture := False;
        end;
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
