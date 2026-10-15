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
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uCommentedOutCode, uUnusedLocal,
  uTestRdxDetectorKit,   // TSeen, Detect-/Plan-/FixAll-Helfer (Charge H3c)
  uTestRdxTextKit;       // Join

// ---- Helfer (die gemeinsamen seit Charge H3c in uTestRdxDetectorKit) ----

function InImplementation(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', AText, 'end.']);
end;

// Der Verteiler fuer den echten Detektor der Art AKind (TDetectorRun).
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  if AKind = fkCommentedOutCode then
    TCommentedOutCodeDetector.AnalyzeUnit(Root, Path, Results)
  else
    TUnusedLocalDetector.AnalyzeUnit(Root, Path, Results);
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_cleanup_', ASource, AKind, RunDetector);
end;

// Fund fuer Fund, bis der Detektor schweigt. Der Detektor muss mindestens
// einmal melden - sonst prueft der Fall nichts.
function FixAll(const ASource: string; AKind: TFindingKind): string;
begin
  Assert.IsTrue(Length(Detect(ASource, AKind)) > 0, 'der Detektor meldet');
  Result := FixAllWith(ASource, AKind, Detect);
end;

// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
begin
  AssertNoHelpWith(ASource, AKind, AReasonPart, Detect);
end;

// Der Rumpf einer Routine P in einer Unit.
function InProc(const ALines: array of string): string;
begin
  Result := InImplementation(Join(['procedure P;', 'begin']) + #13#10
    + Join(ALines) + #13#10 + 'end;');
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
    + CatalogText(Meta.GoodExample)),
    FixAll(InImplementation('procedure P;' + #13#10
      + CatalogText(Meta.BadExample)), fkUnusedLocalVar));
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
