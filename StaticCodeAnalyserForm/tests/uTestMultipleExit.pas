unit uTestMultipleExit;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMultipleExit = class
  public
    [Test] procedure SevenExits_Reported;
    // Schwelle 2026-07-11 von 3 auf 6 angehoben: 4-6 Exits sind idiomatische
    // Guard-Ketten (kein Smell), erst > 6 wird gemeldet.
    [Test] procedure SixExits_NotReported;
    [Test] procedure ThreeExits_NotReported;
    [Test] procedure NoExits_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Posten 180: Exits aus anonymen Methoden - vier gemessene Faelle
    [Test] procedure AnonMethodInArgument_ExitsNotCounted;
    [Test] procedure SevenOwnExitsWithArgLambda_Reported_Kontrolle;
    [Test] procedure AnonMethodAssignedWithLocals_CountsToHost_KnownLimit;
    [Test] procedure AnonMethodAssignedWithoutLocals_StaysOut;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 180: was aus anonymen Methoden zum Wirt zaehlt ------- }
//
// Der Kopfkommentar sagte, Exits in anonymen Methoden zaehlten nicht
// zum Wirt, weil anonyme Methoden eigene nkMethod-Knoten bekaemen.
// Beides an der Exe geprueft - und beides stimmt so nicht:
//
//   Lambda als ARGUMENT, 8 Exits, Wirt 0     kein Fund
//     -> es gibt keinen eigenen Knoten, sonst waere DER gemeldet
//   Lambda per ZUWEISUNG mit var-Sektion     Wirt bekommt sie
//   dieselbe Zuweisung ohne var-Sektion      Wirt bekommt sie nicht
//
// Der Unterschied ist ein Parser-Artefakt: der RHS-Scan von
// uParser2 endet am ersten ";" auf Tiefe 0, und das ist bei einer
// eigenen var-Sektion deren Semikolon - der Lambda-Rumpf wird dann
// als Rumpf des WIRTS geparst. Korpus: 74 solcher Zuweisungen in 44
// Dateien. Eigenes Paket (9015), s. Kopf von uMultipleExit.
//
// Die vier Tests halten die Matrix fest. Sie sind absichtlich
// KnownLimit-benannt, wo sie ein Artefakt pinnen, nicht ein Design.

procedure TTestMultipleExit.AnonMethodInArgument_ExitsNotCounted;
// Wirt 6 (an der Schwelle) + 2 im Argument-Lambda. Zaehlten
// sie mit, waeren es 8 und der Fund kaeme. Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Generics.Defaults, System.Generics.Collections;'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Bar(L: TList<Integer>);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar(L: TList<Integer>);'#13#10 +
  'var'#13#10 +
  '  i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  if i = 0 then Exit;'#13#10 +
  '  if i = 1 then Exit;'#13#10 +
  '  if i = 2 then Exit;'#13#10 +
  '  if i = 3 then Exit;'#13#10 +
  '  if i = 4 then Exit;'#13#10 +
  '  if i = 5 then Exit;'#13#10 +
  '  L.Sort(TComparer<Integer>.Construct('#13#10 +
  '    function(const A, B: Integer): Integer'#13#10 +
  '    begin'#13#10 +
  '      if A > B then Exit(1);'#13#10 +
  '      Exit(-1);'#13#10 +
  '    end));'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkMultipleExit),
      'Exits eines Argument-Lambdas zaehlen nicht zum Wirt');
  finally F.Free; end;
end;

procedure TTestMultipleExit.SevenOwnExitsWithArgLambda_Reported_Kontrolle;
// DIE KLAMMER zur Fixture oben: derselbe Aufbau mit einem
// eigenen Exit mehr. Gemessen: 1 - die Fixture ist also
// meldefaehig, und die 0 oben gehoert dem Lambda.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Generics.Defaults, System.Generics.Collections;'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Bar(L: TList<Integer>);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar(L: TList<Integer>);'#13#10 +
  'var'#13#10 +
  '  i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  if i = 0 then Exit;'#13#10 +
  '  if i = 1 then Exit;'#13#10 +
  '  if i = 2 then Exit;'#13#10 +
  '  if i = 3 then Exit;'#13#10 +
  '  if i = 4 then Exit;'#13#10 +
  '  if i = 5 then Exit;'#13#10 +
  '  if i = 6 then Exit;'#13#10 +
  '  L.Sort(TComparer<Integer>.Construct('#13#10 +
  '    function(const A, B: Integer): Integer'#13#10 +
  '    begin'#13#10 +
  '      if A > B then Exit(1);'#13#10 +
  '      Exit(-1);'#13#10 +
  '    end));'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkMultipleExit),
      'sieben eigene Exits werden gemeldet, Lambda hin oder her');
  finally F.Free; end;
end;

procedure TTestMultipleExit.AnonMethodAssignedWithLocals_CountsToHost_KnownLimit;
// PARSER-ARTEFAKT, Paket 9015: Wirt 5 + 2 im zugewiesenen
// Lambda MIT eigener var-Sektion. Gemessen: 1, und der
// Meldetext nennt 7 - die zwei Lambda-Exits sind im Wirt
// gelandet.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var'#13#10 +
  '  P: TProc;'#13#10 +
  '  i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  if i = 0 then Exit;'#13#10 +
  '  if i = 1 then Exit;'#13#10 +
  '  if i = 2 then Exit;'#13#10 +
  '  if i = 3 then Exit;'#13#10 +
  '  if i = 4 then Exit;'#13#10 +
  '  P := procedure'#13#10 +
  '    var k: Integer;'#13#10 +
  '    begin'#13#10 +
  '      if i = 0 then Exit;'#13#10 +
  '      if i = 1 then Exit;'#13#10 +
  '    end;'#13#10 +
  '  P;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkMultipleExit),
      'BEKANNTE GRENZE: eigene var-Sektion schiebt den Lambda-Rumpf in den Wirt');
  finally F.Free; end;
end;

procedure TTestMultipleExit.AnonMethodAssignedWithoutLocals_StaysOut;
// DIE DISKRIMINIERENDE GEGENPROBE: Zeichen fuer Zeichen
// dieselbe Fixture, nur ohne die eine var-Zeile.
// Gemessen: 0. Damit ist die 1 darueber der var-Sektion
// zuzuschreiben und nichts anderem.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var'#13#10 +
  '  P: TProc;'#13#10 +
  '  i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  if i = 0 then Exit;'#13#10 +
  '  if i = 1 then Exit;'#13#10 +
  '  if i = 2 then Exit;'#13#10 +
  '  if i = 3 then Exit;'#13#10 +
  '  if i = 4 then Exit;'#13#10 +
  '  P := procedure'#13#10 +
  '    begin'#13#10 +
  '      if i = 0 then Exit;'#13#10 +
  '      if i = 1 then Exit;'#13#10 +
  '    end;'#13#10 +
  '  P;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkMultipleExit),
      'ohne eigene Deklarationen bleibt der Lambda-Rumpf draussen');
  finally F.Free; end;
end;


procedure TTestMultipleExit.SevenExits_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  '  if D then Exit;'#13#10 +
  '  if E then Exit;'#13#10 +
  '  if F then Exit;'#13#10 +
  '  if G then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMultipleExit) >= 1,
    '7 Exits (> Schwelle 6) muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMultipleExit.SixExits_NotReported;
// Grenzfall der 2026-07-11-Schwelle: 6 Exits sind noch idiomatische Guard-Kette,
// KEIN Smell. Gegenstueck zu SevenExits_Reported.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  '  if D then Exit;'#13#10 +
  '  if E then Exit;'#13#10 +
  '  if F then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMultipleExit),
    '6 Exits sind eine idiomatische Guard-Kette, kein Smell');
  finally F.Free; end;
end;

procedure TTestMultipleExit.ThreeExits_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMultipleExit));
  finally F.Free; end;
end;

procedure TTestMultipleExit.NoExits_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMultipleExit));
  finally F.Free; end;
end;

procedure TTestMultipleExit.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  '  if D then Exit;'#13#10 +
  '  if E then Exit;'#13#10 +
  '  if F then Exit;'#13#10 +
  '  if G then Exit;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMultipleExit then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMultipleExit finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMultipleExit);

end.
