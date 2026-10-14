unit uTestRdxResultFixesDetector;

// Quick-Fixes "Ergebnis und Konstruktoren" (uRdxResultFixes, Charge H5)
// gegen die ECHTEN Detektoren (nur Delphi, reDelphix.Test): Parser,
// uConstructorWithoutInherited (SCA096), uDestructorWithoutInherited
// (SCA097), uRoutineResultAssigned (SCA121), uManagedResultUninit (SCA196),
// TSourcePlaces und TRdxFixTable.FixFor - derselbe Einstieg wie im
// Anbieter. Je Fall meldet der Detektor, die Hilfe plant aus dem Fund, die
// Ersetzung wird angewandt - und derselbe Detektor meldet danach nichts
// mehr. Dazu die Katalog-Beispiele (SCA097: aus 'bad' wird genau 'good';
// SCA096: 'good' zeigt 'inherited;' - bei direktem TObject-Erben setzt die
// Hilfe 'inherited Create;'; SCA121: 'good' schreibt die Logik um, die
// Hilfe initialisiert), Menuetext und Kennzeichnung je Variante, die
// uses-Ergaenzung fuer VarClear und Funde, die die Hilfe ablehnt.
//
// Ohne Delphi gegengeprueft (Charge H5): dieselben Quellen mit der CLI-Exe
// gescannt und ueber den FPC-Planer (Korpus-Harness) behoben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxResultFixesDetector = class
  public
    [Test] procedure Sca096_TObject_RoundTrip;
    [Test] procedure Sca096_CatalogExample;
    [Test] procedure Sca096_Override_MarkedWithCaption;
    [Test] procedure Sca096_OtherParent_NoHelp;
    [Test] procedure Sca097_CatalogExample;
    [Test] procedure Sca097_TObject_Unmarked;
    [Test] procedure Sca097_NoOverride_NoHelp;
    [Test] procedure Sca121_CatalogExample;
    [Test] procedure Sca121_Outcome_MarkedWithCaption;
    [Test] procedure Sca121_Script_NoHelp;
    [Test] procedure Sca196_String_RoundTrip;
    [Test] procedure Sca196_TArray_RoundTrip;
    [Test] procedure Sca196_Variant_AddsUses;
    [Test] procedure Sca196_Outcome_MarkedWithCaption;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uConstructorWithoutInherited, uDestructorWithoutInherited,
  uRoutineResultAssigned, uManagedResultUninit,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // CaptionFor
  uTestRdxDetectorKit;   // TSeen, Join, Detect-/Plan-/Apply-Helfer

// ---- Helfer ----

// Der Verteiler fuer den echten Detektor der Art AKind (TDetectorRun).
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkConstructorWithoutInherited:
      TConstructorWithoutInheritedDetector.AnalyzeUnit(Root, Path, Results);
    fkDestructorWithoutInherited:
      TDestructorWithoutInheritedDetector.AnalyzeUnit(Root, Path, Results);
    fkRoutineResultUnassigned:
      TRoutineResultAssignedDetector.AnalyzeUnit(Root, Path, Results);
  else
    TManagedResultUninitDetector.AnalyzeUnit(Root, Path, Results);
  end;
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_res_', ASource, AKind, RunDetector);
end;

// Fund fuer Fund, bis der Detektor schweigt. Der Detektor muss mindestens
// einmal melden - sonst prueft der Fall nichts.
function FixAll(const ASource: string; AKind: TFindingKind): string;
begin
  Assert.IsTrue(Length(Detect(ASource, AKind)) > 0, 'der Detektor meldet');
  Result := FixAllWith(ASource, AKind, Detect);
end;

procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
begin
  AssertNoHelpWith(ASource, AKind, AReasonPart, Detect);
end;

// Die Hilfe fuer den einen Fund der Art AKind.
function OutcomeOf(const ASource: string; AKind: TFindingKind): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource, AKind);
  Assert.AreEqual<Integer>(1, Length(Seen), 'genau ein Fund');
  Result := PlanFixIn(ASource, 't.pas', AKind, Seen[0]);
end;

// Eine Unit mit den Typen ATypes (interface) und dem Text AImpl
// (implementation, Zeilen mit CRLF).
function InUnit(const ATypes: array of string; const AImpl: string): string;
begin
  Result := Join(['unit t;', '', 'interface', '', 'type']) + #13#10
    + Join(ATypes) + #13#10 + Join(['', 'implementation', '']) + #13#10
    + AImpl + #13#10 + Join(['', 'end.']);
end;

// Eine Unit ohne Typen mit dem Text AImpl.
function InPlainUnit(const AImpl: string): string;
begin
  Result := Join(['unit t;', '', 'interface', '', 'implementation', ''])
    + #13#10 + AImpl + #13#10 + Join(['', 'end.']);
end;

// Die Klasse TFoo mit Feld FX und Konstruktor Create (Katalog SCA096).
function FooCtorTypes(const AHeritage, ADecl: string): TArray<string>;
begin
  Result := TArray<string>.Create('  TFoo = ' + AHeritage, '    FX: Integer;',
    '  public', '    ' + ADecl, '  end;');
end;

// Eine Funktion F mit Rueckgabetyp AType, die Result vor der ersten
// Zuweisung liest (SCA196).
function Collector(const AType, AAppend: string): string;
begin
  Result := InPlainUnit(Join(['function F(const A: array of string): '
    + AType + ';', 'var', '  I: Integer;', 'begin',
    '  for I := 0 to High(A) do', '    Result := Result + ' + AAppend + ';',
    'end;']));
end;

{ ---- SCA096 ---- }

procedure TTestRdxResultFixesDetector.Sca096_TObject_RoundTrip;
var
  Impl : string;
begin
  Impl := Join(['constructor TFoo.Create;', 'begin', '  FX := 1;', 'end;']);
  Assert.AreEqual(InUnit(FooCtorTypes('class', 'constructor Create;'),
    Join(['constructor TFoo.Create;', 'begin', '  inherited Create;',
    '  FX := 1;', 'end;'])),
    FixAll(InUnit(FooCtorTypes('class', 'constructor Create;'), Impl),
      fkConstructorWithoutInherited));
end;

procedure TTestRdxResultFixesDetector.Sca096_CatalogExample;
var
  Meta : TRuleMeta;
begin
  // 'good' zeigt 'inherited;' - die Hilfe schreibt bei direktem TObject-
  // Erben 'inherited Create;' (nacktes inherited reichte Parameter weiter).
  Meta := TRuleCatalog.GetRuleCanonical(fkConstructorWithoutInherited);
  Assert.IsTrue(Pos('inherited;', Meta.GoodExample) > 0, Meta.GoodExample);
  Assert.AreEqual(InUnit(FooCtorTypes('class', 'constructor Create;'),
    StringReplace(CatalogText(Meta.GoodExample), 'inherited;',
      'inherited Create;', [])),
    FixAll(InUnit(FooCtorTypes('class', 'constructor Create;'),
      CatalogText(Meta.BadExample)), fkConstructorWithoutInherited));
end;

procedure TTestRdxResultFixesDetector.Sca096_Override_MarkedWithCaption;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  Src := InUnit(['  TBase = class', '    constructor Create(A: Integer); virtual;',
    '  end;', '  TFoo = class(TBase)',
    '    constructor Create(A: Integer); override;',
    '  end;'], Join(['constructor TBase.Create(A: Integer);', 'begin',
    '  inherited Create;', 'end;', '', 'constructor TFoo.Create(A: Integer);',
    'begin', '  Log(A);', 'end;']));
  O := OutcomeOf(Src, fkConstructorWithoutInherited);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'aendert Verhalten');
  Assert.AreEqual('Call inherited first in the constructor (changes behavior)',
    TRdxFixTable.CaptionFor(fkConstructorWithoutInherited, O));
  Assert.IsTrue(Pos('Elternkonstruktor', O.Hint) > 0, O.Hint);
  Assert.AreEqual(StringReplace(Src, '  Log(A);', '  inherited;'#13#10'  Log(A);',
    []), FixAll(Src, fkConstructorWithoutInherited));
end;

procedure TTestRdxResultFixesDetector.Sca096_OtherParent_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Welcher Elternkonstruktor laufen soll, ist Entwurf.
  AssertNoHelp(InUnit(FooCtorTypes('class(TComponent)',
    'constructor Make(A: Integer);'), Join(['constructor TFoo.Make(A: Integer);',
    'begin', '  FX := A;', 'end;'])), fkConstructorWithoutInherited, 'Entwurf');
  // Direkter TObject-Erbe: bedeutungsgleich, nicht gekennzeichnet.
  O := OutcomeOf(InUnit(FooCtorTypes('class', 'constructor Create;'),
    Join(['constructor TFoo.Create;', 'begin', '  FX := 1;', 'end;'])),
    fkConstructorWithoutInherited);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsFalse(O.ChangesBehavior, 'TObject.Create ist leer');
  Assert.AreEqual('Call inherited Create first in the constructor',
    TRdxFixTable.CaptionFor(fkConstructorWithoutInherited, O));
end;

{ ---- SCA097 ---- }

procedure TTestRdxResultFixesDetector.Sca097_CatalogExample;
var
  Meta  : TRuleMeta;
  Types : TArray<string>;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkDestructorWithoutInherited);
  Types := TArray<string>.Create('  TFoo = class(TComponent)',
    '    FBar: TObject;', '  public', '    destructor Destroy; override;',
    '  end;');
  Assert.AreEqual(InUnit(Types, CatalogText(Meta.GoodExample)),
    FixAll(InUnit(Types, CatalogText(Meta.BadExample)),
      fkDestructorWithoutInherited));
end;

procedure TTestRdxResultFixesDetector.Sca097_TObject_Unmarked;
var
  O : TRdxFixOutcome;
begin
  O := OutcomeOf(InUnit(['  TFoo = class', '    FBar: TObject;', '  public',
    '    destructor Destroy; override;', '  end;'],
    Join(['destructor TFoo.Destroy;', 'begin', '  FBar.Free;', 'end;'])),
    fkDestructorWithoutInherited);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsFalse(O.ChangesBehavior, 'TObject.Destroy ist leer');
  Assert.AreEqual('Call inherited last in the destructor',
    TRdxFixTable.CaptionFor(fkDestructorWithoutInherited, O));
  Assert.IsTrue(Pos('TObject.Destroy ist leer', O.Hint) > 0, O.Hint);
end;

procedure TTestRdxResultFixesDetector.Sca097_NoOverride_NoHelp;
begin
  AssertNoHelp(InUnit(['  TFoo = class(TComponent)', '  public',
    '    destructor Destroy;', '  end;'], Join(['destructor TFoo.Destroy;',
    'begin', '  Log(''x'');', 'end;'])), fkDestructorWithoutInherited,
    'kein override');
end;

{ ---- SCA121 ---- }

procedure TTestRdxResultFixesDetector.Sca121_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
begin
  // 'good' schreibt die Logik um - die Hilfe initialisiert nur, fuer
  // Integer mit dem Literal 0 (Charge H5c: Default(T) nur, wo kein Literal
  // passt).
  Meta := TRuleCatalog.GetRuleCanonical(fkRoutineResultUnassigned);
  Bad := CatalogText(Meta.BadExample);
  Assert.AreEqual(InPlainUnit(StringReplace(Bad, 'begin'#13#10,
    'begin'#13#10'  Result := 0;'#13#10, [])),
    FixAll(InPlainUnit(Bad), fkRoutineResultUnassigned));
end;

procedure TTestRdxResultFixesDetector.Sca121_Outcome_MarkedWithCaption;
var
  O : TRdxFixOutcome;
begin
  O := OutcomeOf(InPlainUnit(Join(['function F(A: Integer): Integer;', 'begin',
    '  Log(A);', 'end;'])), fkRoutineResultUnassigned);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'aendert Verhalten');
  Assert.AreEqual('Initialize Result with 0 (changes behavior)',
    TRdxFixTable.CaptionFor(fkRoutineResultUnassigned, O));
end;

procedure TTestRdxResultFixesDetector.Sca121_Script_NoHelp;
begin
  // xEdit-Skript ('unit' ohne implementation): Default() kennt der
  // Interpreter nicht.
  AssertNoHelp(Join(['unit UserScript;', '', 'function Initialize: integer;',
    'begin', '  Log(''x'');', 'end;', '', 'end.']), fkRoutineResultUnassigned,
    'ohne implementation-Teil');
end;

{ ---- SCA196 ---- }

procedure TTestRdxResultFixesDetector.Sca196_String_RoundTrip;
var
  Src : string;
begin
  Src := Collector('string', 'A[I]');
  Assert.AreEqual(StringReplace(Src, 'begin'#13#10,
    'begin'#13#10'  Result := '''';'#13#10, []),
    FixAll(Src, fkManagedResultUninit));
end;

procedure TTestRdxResultFixesDetector.Sca196_TArray_RoundTrip;
var
  Src : string;
begin
  Src := Collector('TArray<string>', '[A[I]]');
  Assert.AreEqual(StringReplace(Src, 'begin'#13#10,
    'begin'#13#10'  Result := nil;'#13#10, []),
    FixAll(Src, fkManagedResultUninit));
end;

procedure TTestRdxResultFixesDetector.Sca196_Variant_AddsUses;
var
  Src : string;
  O   : TRdxFixOutcome;
  New : string;
begin
  // VarClear braucht unter FPC die Unit Variants - sie kommt in uses.
  Src := Join(['unit t;', '', 'interface', '', 'implementation', '',
    'uses', '  System.SysUtils;', '',
    'function Sum(const A: array of Integer): Variant;',
    'var', '  I: Integer;', 'begin', '  for I := 0 to High(A) do',
    '    Result := Result + A[I];', 'end;', '', 'end.']);
  O := OutcomeOf(Src, fkManagedResultUninit);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Anweisung und uses');
  Assert.IsTrue(Pos('+ uses System.Variants', O.Hint) > 0, O.Hint);
  New := FixAll(Src, fkManagedResultUninit);
  Assert.IsTrue(Pos('System.SysUtils, System.Variants;', New) > 0, New);
  Assert.IsTrue(Pos('begin'#13#10'  VarClear(Result);'#13#10, New) > 0, New);
end;

procedure TTestRdxResultFixesDetector.Sca196_Outcome_MarkedWithCaption;
var
  O : TRdxFixOutcome;
begin
  O := OutcomeOf(Collector('string', 'A[I]'), fkManagedResultUninit);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'aendert Verhalten');
  Assert.AreEqual('Initialize Result first: Result := '''' (changes behavior)',
    TRdxFixTable.CaptionFor(fkManagedResultUninit, O));
  Assert.IsTrue(Pos('alten Inhalt', O.Hint) > 0, O.Hint);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxResultFixesDetector);

end.
