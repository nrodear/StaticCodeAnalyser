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
//   * FP-Fix 2026-07-25 (Doku-Quickwins 2026-07-25): DUnitX-Auto-
//     Discovery fuehrt published-Methoden auch OHNE [Test]-Attribut aus
//     -> Fixture mit >=1 published-Prozedur wird NICHT geflagt.
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
  // FP-Fix 2026-07-25 (Doku-Quickwins 2026-07-25): DUnitX-Auto-Discovery
  // fuehrt published-Methoden auch OHNE [Test]-Attribut aus. Fixtures mit
  // mindestens einer published-Prozedur/-Funktion sind also keine Zombies
  // und werden nicht mehr geflagt (8 FPs im Real-World-Korpus; echte
  // Zombie-Fixtures haben gar keine published-Sektion).
  PUBLISHED_RE   = '^\s*published\b';
  VISIBILITY_RE  = '^\s*(strict\s+)?(private|protected|public)\b';
  PUB_PROC_RE    = '^\s*(class\s+)?(procedure|function)\s+[A-Za-z_]';

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
  RePublished, ReVisibility, RePubProc : TRegEx;
  InFixture   : Boolean;
  FixtureLine : Integer;
  HasTest     : Boolean;
  InheritsCustom : Boolean;
  InPublished      : Boolean;  // aktuell in einer published-Sektion?
  HasPublishedProc : Boolean;  // Fixture hat >=1 published-Methode
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
    RePublished   := TRegEx.Create(PUBLISHED_RE,  [roIgnoreCase]);
    ReVisibility  := TRegEx.Create(VISIBILITY_RE, [roIgnoreCase]);
    RePubProc     := TRegEx.Create(PUB_PROC_RE,   [roIgnoreCase]);
    InFixture       := False;
    FixtureLine     := 0;
    HasTest         := False;
    InheritsCustom  := False;
    InPublished      := False;
    HasPublishedProc := False;
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
            InPublished      := False;
            HasPublishedProc := False;
          end;
        end
        else
        begin
          // Innerhalb Fixture-Klasse: nach [Test]/[TestCase]/[TestMethod]
          // suchen.
          if ReTest.IsMatch(Code) then HasTest := True;
          // FP-Fix 2026-07-25 (Doku-Quickwins 2026-07-25): published-
          // Sektions-Tracking. `published` oeffnet die Sektion, jedes
          // andere Sichtbarkeits-Keyword schliesst sie. Eine procedure/
          // function-Deklaration INNERHALB einer published-Sektion zaehlt
          // als DUnitX-auto-discovered Test -> Fixture ist kein Zombie.
          if RePublished.IsMatch(Code) then
            InPublished := True
          else if ReVisibility.IsMatch(Code) then
            InPublished := False;
          if InPublished and RePubProc.IsMatch(Code) then
            HasPublishedProc := True;
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
          if (not HasTest) and (not InheritsCustom) and
             (not HasPublishedProc) then
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
