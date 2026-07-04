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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TAttributeTestFixtureWithoutTestsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

const
  TESTFIXTURE_RE = '\[TestFixture\b';
  // FP-Fix 2026-06-21: `[TestCase(...)]` und `[TestMethod]` zaehlen auch als
  // Test-Marker (DUnitX: TestCase = parameterisierter Test). Vorher hat
  // `\[Test\b` `[TestCase` nicht gematched -> skia4delphi Svg-Tests false-
  // positive als zombie-fixture erkannt.
  TEST_RE        = '\[(Test|TestCase|TestMethod)\b';
  CLASS_END_RE   = '^\s*end\s*;\s*$';
  CLASS_DECL_RE  = '\bclass\b';

class procedure TAttributeTestFixtureWithoutTestsDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Code        : string;
  State       : TCommentScanState;
  Dummy       : Integer;
  ReFixture, ReTest, ReEnd, ReClass, ReInheritFrom : TRegEx;
  InFixture   : Boolean;
  FixtureLine : Integer;
  HasTest     : Boolean;
  InheritsCustom : Boolean;
  F           : TLeakFinding;
const
  // Inheritance von diesen Basen zaehlt als "kein vererbtes [Test]
  // moeglich" - alles andere koennte vererbte Tests haben.
  BASE_NOT_INHERITING : array[0..3] of string = (
    'tobject', 'tinterfacedobject', 'tpersistent', 'exception');
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    State       := Default(TCommentScanState);
    ReFixture   := TRegEx.Create(TESTFIXTURE_RE, [roIgnoreCase]);
    ReTest      := TRegEx.Create(TEST_RE,        [roIgnoreCase]);
    ReEnd       := TRegEx.Create(CLASS_END_RE,   [roIgnoreCase]);
    ReClass     := TRegEx.Create(CLASS_DECL_RE,  [roIgnoreCase]);
    // class(BaseName) - Capture-Group BaseName.
    ReInheritFrom := TRegEx.Create('\bclass\s*\(\s*([A-Za-z_]\w*)',
      [roIgnoreCase]);
    InFixture       := False;
    FixtureLine     := 0;
    HasTest         := False;
    InheritsCustom  := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Dummy);

      try
        if not InFixture then
        begin
          // FP-Fix 2026-06-21: nur als Fixture-Open werten wenn die Zeile
          // tatsaechlich eine Attribute-Position ist (vermeidet z.B.
          // Kommentar-Strings oder String-Konstanten die `[TestFixture]`
          // erwaehnen).
          if ReFixture.IsMatch(Code) and
             TDetectorUtils.IsLikelyAttributePosition(Lines, i) then
          begin
            InFixture      := True;
            FixtureLine    := i + 1;
            HasTest        := False;
            InheritsCustom := False;
          end;
        end
        else
        begin
          // Innerhalb Fixture-Klasse: nach [Test]/[TestCase]/[TestMethod]
          // suchen.
          if ReTest.IsMatch(Code) then HasTest := True;
          // Inheritance-Pruefung: `TFoo = class(TBaseClass)`. Wenn
          // TBaseClass NICHT in BASE_NOT_INHERITING -> der Sub-Class
          // koennte vererbte Test-Methoden haben.
          // FP-Fix 2026-06-21: delphimvcframework TActiveRecordTests
          // hatten [Test] in der abstrakten Base - die konkreten
          // DB-Subklassen `[TestFixture] T...Firebird = class(TBase)`
          // wurden faelschlich als zombie geflagged.
          var MI := ReInheritFrom.Match(Code);
          if MI.Success and (MI.Groups.Count >= 2) then
          begin
            var BaseLow := LowerCase(MI.Groups[1].Value);
            var IsKnownBase := False;
            for var B in BASE_NOT_INHERITING do
              if B = BaseLow then begin IsKnownBase := True; Break; end;
            if not IsKnownBase then InheritsCustom := True;
          end;
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
          if (not HasTest) and (not InheritsCustom) then
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
