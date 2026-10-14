unit uTestRdxCleanupDetector;

// Quick-Fixes "Aufraeumen" (uRdxCleanupFixes, Charge H3a) gegen die ECHTEN
// Detektoren (nur Delphi, reDelphix.Test): Parser, uCommentedOutCode
// (SCA070) bzw. uUnusedLocal (SCA053), TSourcePlaces und
// TRdxFixTable.FixFor - derselbe Einstieg wie im Anbieter. Je Fall meldet
// der Detektor, die Hilfe plant aus dem Fund (Art, Zeile, Meldung), die
// Ersetzung wird angewandt - und derselbe Detektor meldet danach nichts
// mehr. Dazu das Katalog-Beispiel von SCA053 (aus 'bad' wird genau 'good')
// und die Sperren an echten Funden (for var, resourcestring, Kopfkommentar,
// Absichtsmarker, Mehrzeilenstring, with, Attribut).
//
// Das Katalog-Beispiel von SCA070 ('// X := 42;' und '// if Active then
// Process;' untereinander) meldet der Detektor NICHT: zwei benachbarte
// '//'-Zeilen gelten ihm als Doku-Block (FP-Schutz 1 in uCommentedOutCode)
// - der Rundlauf nimmt deshalb eigene Faelle. Eigene Fixture-Unit statt
// einer zehnten in uTestRdxSimpleFixesDetector (Charge H3, je Teil eine
// Testunit).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCleanupDetector = class
  public
    [Test] procedure Sca070_LineComments_RoundTrip;
    [Test] procedure Sca070_BlockContent_RoundTrip;
    [Test] procedure Sca070_ProseStays_RoundTrip;
    [Test] procedure Sca070_BehindCode_RoundTrip;
    [Test] procedure Sca070_HeaderComment_NoHelp;
    [Test] procedure Sca070_Todo_NoHelp;
    [Test] procedure Sca070_MultiLineString_NoHelp;
    [Test] procedure Sca053_RoundTrip;
    [Test] procedure Sca053_Groups_RoundTrip;
    [Test] procedure Sca053_CatalogExample;
    [Test] procedure Sca053_InlineVar_RoundTrip;
    [Test] procedure Sca053_ForVar_NoHelp;
    [Test] procedure Sca053_Resourcestring_NoHelp;
    [Test] procedure Sca053_With_RoundTrip;
    [Test] procedure Sca053_Attribute_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2, uMethodd12, uSCAConsts, uRuleCatalog,
  uCommentedOutCode, uUnusedLocal,
  uEngineApi, uRdxBufferMath, uRdxRecipeRunner, uRdxFixTable;

type
  // Was die Hilfe aus einem Fund liest - wie der Anbieter aus TLeakFinding.
  TSeen = record
    Line : Integer;
    Msg  : string;
  end;

// ---- Helfer (wie uTestRdxSimpleFixesDetector) ----

function Join(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

function InImplementation(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', AText, 'end.']);
end;

function WriteTemp(const ASource: string): string;
var
  SL : TStringList;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_cleanup_' + GUIDToString(TGUID.NewGuid) + '.pas';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    SL.SaveToFile(Result);
  finally
    SL.Free;
  end;
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
var
  Path    : string;
  Parser  : TParser2;
  Root    : TAstNode;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
  n       : Integer;
begin
  Result := nil;
  Path := WriteTemp(ASource);
  Results := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(Path);
      try
        if AKind = fkCommentedOutCode then
          TCommentedOutCodeDetector.AnalyzeUnit(Root, Path, Results)
        else
          TUnusedLocalDetector.AnalyzeUnit(Root, Path, Results);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    SetLength(Result, Results.Count);
    n := 0;
    for F in Results do
      if F.Kind = AKind then
      begin
        Result[n].Line := F.LineInt;
        Result[n].Msg  := F.Message;
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    Results.Free;
    DeleteFile(Path);
  end;
end;

// Die Hilfe fuer EINEN Fund ueber den Einstieg des Anbieters.
function PlanFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen; out AEdits: TArray<TRdxEdit>; out AReason: string): Boolean;
var
  SL      : TStringList;
  Places  : TSourcePlaces;
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  Assert.IsTrue(TRdxFixTable.Handles(AKind), 'FixFor kennt die Art');
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  Finding := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, AKind);
  try
    SL.Text := ASource;
    Assert.IsTrue(Places.OpenSource('t.pas', ASource), 'OpenSource');
    O := TRdxFixTable.FixFor(Places, SL, Finding,
      TRdxRecipeRunner.UsesNamesOf(Places));
  finally
    Finding.Free;
    Places.Free;
    SL.Free;
  end;
  AEdits  := O.Edits;
  AReason := O.Reason;
  Result  := O.Enabled;
end;

// Schreibt wie der Editor: alle Ersetzungen gegen denselben Puffer geprueft.
function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, AEdits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet (wie der Benutzer es
// taete), bis der Detektor schweigt. Der Detektor muss mindestens einmal
// melden - sonst prueft der Fall nichts.
function FixAll(const ASource: string; AKind: TFindingKind): string;
const
  MAX_PASSES = 10;
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
  Pass   : Integer;
begin
  Result := ASource;
  Assert.IsTrue(Length(Detect(ASource, AKind)) > 0, 'der Detektor meldet');
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result, AKind);
    if Length(Seen) = 0 then Exit;
    Assert.IsTrue(PlanFix(Result, AKind, Seen[0], Edits, Reason),
      Format('Zeile %d: %s', [Seen[0].Line, Reason]));
    Result := Apply(Result, Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Seen := Detect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Assert.IsFalse(PlanFix(ASource, AKind, Seen[0], Edits, Reason), 'keine Hilfe');
  Assert.IsTrue(Pos(AReasonPart, Reason) > 0, Reason);
end;

// Der Rumpf einer Routine P in einer Unit.
function InProc(const ALines: array of string): string;
begin
  Result := InImplementation(Join(['procedure P;', 'begin']) + #13#10
    + Join(ALines) + #13#10 + 'end;');
end;

function Snip(const AExample: string): string;
begin
  Result := StringReplace(AExample, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

{ ---- SCA070 ---- }

procedure TTestRdxCleanupDetector.Sca070_LineComments_RoundTrip;
begin
  // Zwei einzelne '//'-Zeilen (nicht benachbart - sonst haelt der Detektor
  // sie fuer einen Doku-Block): beide Zeilen gehen.
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    FixAll(InProc(['  Foo;', '  // X := 1;', '  Bar;', '  //Baz := 2;']),
      fkCommentedOutCode));
end;

procedure TTestRdxCleanupDetector.Sca070_BlockContent_RoundTrip;
begin
  // Der Fund zeigt auf die Inhaltszeilen; der leere Kommentar geht mit.
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    FixAll(InProc(['  Foo;', '  {', '    X := 1;', '    Y := 2;', '  }',
      '  Bar;']), fkCommentedOutCode));
end;

procedure TTestRdxCleanupDetector.Sca070_ProseStays_RoundTrip;
begin
  // Nur die gemeldete Region geht - die Prosa davor und dahinter hat der
  // Detektor nicht als Code gemeldet.
  Assert.AreEqual(InProc(['  { Alte Fassung:', '    noch offen }', '  Foo;']),
    FixAll(InProc(['  { Alte Fassung:', '    X := 1;', '    noch offen }',
      '  Foo;']), fkCommentedOutCode));
end;

procedure TTestRdxCleanupDetector.Sca070_BehindCode_RoundTrip;
begin
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    FixAll(InProc(['  Foo;   { X := 1; }', '  Bar;']), fkCommentedOutCode));
end;

procedure TTestRdxCleanupDetector.Sca070_HeaderComment_NoHelp;
begin
  AssertNoHelp(Join(['{ Beispiel:', '  X := 1;', '}', 'unit t;', 'interface',
    'implementation', 'end.']), fkCommentedOutCode, 'Kopfkommentar');
end;

procedure TTestRdxCleanupDetector.Sca070_Todo_NoHelp;
begin
  AssertNoHelp(InProc(['  { TODO X := 1; }', '  Foo;']), fkCommentedOutCode,
    'TODO');
end;

procedure TTestRdxCleanupDetector.Sca070_MultiLineString_NoHelp;
begin
  // Der Detektor kennt die Mehrzeilenstrings von Delphi 12 nicht und meldet
  // '{ ... }' darin (Korpus: Alcinoe-Shader) - die Code-Sicht weiss es.
  AssertNoHelp(InProc(['  S := ''''''', '    { X := 1; }', '    '''''';']),
    fkCommentedOutCode, 'steht kein Kommentar');
end;

{ ---- SCA053 ---- }

procedure TTestRdxCleanupDetector.Sca053_RoundTrip;
begin
  // Einzeldeklaration mit '//'-Kommentar und eine Section, die leer wird.
  Assert.AreEqual(InImplementation(Join(['procedure P;', 'var',
    '  A: Integer;', 'begin', '  A := 1;', 'end;', 'procedure Q;', 'begin',
    'end;'])),
    FixAll(InImplementation(Join(['procedure P;', 'var', '  A: Integer;',
      '  X: TObject;   // alt', 'begin', '  A := 1;', 'end;', 'procedure Q;',
      'var', '  Y: Integer;', 'begin', 'end;'])), fkUnusedLocalVar));
end;

procedure TTestRdxCleanupDetector.Sca053_Groups_RoundTrip;
begin
  // Erstes, mittleres und letztes Element einer Gruppe, auch ueber Zeilen.
  Assert.AreEqual(InImplementation(Join(['procedure P;', 'var',
    '  B, D: Integer;', '  E: string;', 'begin', '  B := D;', '  E := '''';',
    'end;'])),
    FixAll(InImplementation(Join(['procedure P;', 'var',
      '  A, B, C, D, F: Integer;', '  E,', '  G: string;', 'begin', '  B := D;',
      '  E := '''';', 'end;'])), fkUnusedLocalVar));
end;

procedure TTestRdxCleanupDetector.Sca053_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkUnusedLocalVar);
  Assert.AreEqual(InImplementation('procedure P;' + #13#10
    + Snip(Meta.GoodExample)),
    FixAll(InImplementation('procedure P;' + #13#10 + Snip(Meta.BadExample)),
      fkUnusedLocalVar));
end;

procedure TTestRdxCleanupDetector.Sca053_InlineVar_RoundTrip;
begin
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    FixAll(InProc(['  Foo;', '  var X: Integer;', '  Bar;']),
      fkUnusedLocalVar));
end;

procedure TTestRdxCleanupDetector.Sca053_ForVar_NoHelp;
begin
  // Der Detektor meldet die Laufvariable (Korpus: 75 von 757 Funden).
  AssertNoHelp(InProc(['  for var I := 1 to 3 do', '    Foo;']),
    fkUnusedLocalVar, 'for var');
end;

procedure TTestRdxCleanupDetector.Sca053_Resourcestring_NoHelp;
begin
  // Der Detektor liest eine resourcestring-Section hinter der var-Section
  // als Variable 'resourcestring' (Korpus: 17 Funde, gexperts).
  AssertNoHelp(InImplementation(Join(['procedure P;', 'var', '  A: Integer;',
    'resourcestring', '  SFoo = ''foo'';', 'begin', '  A := 1;', '  Foo(SFoo);',
    'end;'])), fkUnusedLocalVar, 'Schluesselwort');
end;

procedure TTestRdxCleanupDetector.Sca053_With_RoundTrip;
begin
  // Ein with im Gueltigkeitsbereich sperrt nicht (die Variable kommt nirgends
  // vor, with kann sie nicht binden) - Fund weg, Section leer, var geht mit.
  Assert.AreEqual(InImplementation(Join(['procedure P(L: TList);', 'begin',
    '  with L do', '    Clear;', 'end;'])),
    FixAll(InImplementation(Join(['procedure P(L: TList);', 'var',
      '  X: Integer;', 'begin', '  with L do', '    Clear;', 'end;'])),
      fkUnusedLocalVar));
end;

procedure TTestRdxCleanupDetector.Sca053_Attribute_NoHelp;
begin
  // Ob der Detektor X oder den Namen im Attribut meldet (Korpus: 'unsafe'
  // aus '[unsafe] LAnimation') - die Hilfe lehnt beides ab.
  AssertNoHelp(InImplementation(Join(['procedure P;', 'var',
    '  [Weak] X: IInterface;', 'begin', 'end;'])), fkUnusedLocalVar,
    'Attribut');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCleanupDetector);

end.
