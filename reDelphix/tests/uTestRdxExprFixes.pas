unit uTestRdxExprFixes;

// Editorhilfen aus dem uQuickFix-Umzug (Beschluss 2026-10-09): die Planer
// SCA066 (leere Klammern), SCA072 (Vergleich mit True/False) und SCA084
// (Assigned + nil) aus uRdxSimpleFixes auf Text - ohne Parser, ohne
// Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand). Die Faelle der
// alten uTestQuickFix sind dabei, dazu die Fallen, an denen der alte
// Anbieter die Bedeutung aenderte (Vorrang, Ausdruckskontext, Pfade).
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxExprFixes = class
  public
    // ---- SCA066 ----
    [Test] procedure Sca066_Variants;
    [Test] procedure Sca066_Refusals;
    [Test] procedure Sca066_OwnFunction_Refused;
    // Gegen-Review 2026-10-10: welche Namen der Laeufer pruefen muss.
    [Test] procedure Sca066_CalleeAndTarget;
    // Review R3-02 (Charge FC): eine Property mit Prozedurtyp - auch hinter
    // einem Pfad - bekommt keine Hilfe; Felder und Methoden schon.
    [Test] procedure Sca066_PropertyCall_Refused;
    // ---- SCA072 ----
    [Test] procedure Sca072_Variants;
    [Test] procedure Sca072_Refusals;
    // ---- SCA084 ----
    [Test] procedure Sca084_Variants;
    [Test] procedure Sca084_Refusals;
    [Test] procedure DeclaredTypeKind_Kinds;
    [Test] procedure TypeKinds_ResolvedProceduralPointerLike;
    // Review R3-03 (Charge FC): die Fragen an die ganze Datei lesen nur noch
    // die Zeilen, die den Namen nennen - mit demselben Ergebnis, auch wenn
    // Schluesselwort und Name auf verschiedenen Zeilen stehen.
    [Test] procedure DeclarationQueries_LineFilter;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxSimpleFixes,
  uTestRdxTextKit;   // Join, Apply

// ---- Helfer ----

// Eine Zeile in einer kleinen Unit (Zeile 4).
function InUnit(const ALine: string): string;
begin
  Result := Join(['unit u;', 'implementation', 'procedure P;', ALine, 'end.']);
end;

// Die Meldung der Detektoren: 'at column N'.
function AtColumn(ACol: Integer): string;
begin
  Result := Format('Finding at column %d - test.', [ACol]);
end;

type
  // Was ein Planer liefert: der neue Text ('' bei Ablehnung), der Operand
  // X (SCA072/SCA084) und der Grund.
  TFixResult = record
    Text   : string;
    Name   : string;   // SCA066: Callee
    Target : string;   // SCA066: links von ':='
    Reason : string;
  end;

// Ein Planer ('E' SCA066, 'B' SCA072, sonst SCA084) auf einer Quelle.
function Fix(AKind: Char; const ASource: string; ALine, ACol: Integer): TFixResult;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Call : TRdxCallEdit;
  Plan : TRdxOperandEdit;
  Ok   : Boolean;
begin
  Result := Default(TFixResult);
  Plan := Default(TRdxOperandEdit);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    case AKind of
      'E':
        begin
          Ok := TRdxExprFixes.EmptyArgs(Map, ALine, AtColumn(ACol), Call,
            Result.Reason);
          Plan.Edit := Call.Edit;
          Plan.Name := Call.Callee;
          Result.Target := Call.Target;
        end;
      'B':
        Ok := TRdxExprFixes.RedundantBool(Map, ALine, AtColumn(ACol), Plan,
          Result.Reason);
    else
      Ok := TRdxExprFixes.AssignedNil(Map, ALine, AtColumn(ACol), Plan,
        Result.Reason);
    end;
    if Ok then
    begin
      Result.Name := Plan.Name;
      Result.Text := Apply(ASource, [Plan.Edit]);
    end;
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Zeile der Tabelle als Zeile 4 ergibt AWant.
procedure CheckFixed(AKind: Char; const ALine, ACol, AWant: string);
var
  F : TFixResult;
begin
  F := Fix(AKind, InUnit(ALine), 4, StrToInt(ACol));
  Assert.AreEqual(InUnit(AWant), F.Text, ALine + ': ' + F.Reason);
end;

// Eine Zeile der Tabelle als Zeile 4 wird abgelehnt, AWant steht im Grund.
procedure CheckRefused(AKind: Char; const ALine, ACol, AWant: string);
var
  F : TFixResult;
begin
  F := Fix(AKind, InUnit(ALine), 4, StrToInt(ACol));
  Assert.AreEqual('', F.Text, ALine);
  Assert.IsTrue(Pos(AWant, F.Reason) > 0, ALine + ': ' + F.Reason);
end;

// ---- SCA066 ----

procedure TTestRdxExprFixes.Sca066_Variants;
const
  CASES: array[0..18, 0..2] of string = (
    ('  DoStuff();', '10', '  DoStuff;'),
    ('  Obj.Refresh();', '14', '  Obj.Refresh;'),
    ('  Self.Obj.Refresh ( ) ;', '20', '  Self.Obj.Refresh ;'),
    ('  inherited Create();', '19', '  inherited Create;'),
    ('  if Ok then Close();', '19', '  if Ok then Close;'),
    ('  X := Now();', '11', '  X := Now;'),
    ('  if Done() then Exit;', '10', '  if Done then Exit;'),
    ('  while More() do Step;', '13', '  while More do Step;'),
    ('  begin Init() end;', '13', '  begin Init end;'),
    ('  1: Reset();', '11', '  1: Reset;'),
    ('  Foo(); // weg', '6', '  Foo; // weg'),
    ('  if Done()then Exit;', '10', '  if Done then Exit;'),
    ('  begin Init()end;', '13', '  begin Init end;'),
    ('procedure Foo();', '14', 'procedure Foo;'),
    ('function TFoo.Bar(): Integer;', '18', 'function TFoo.Bar: Integer;'),
    ('procedure Foo(); overload;', '14', 'procedure Foo; overload;'),
    // initialization/finalization stehen seit Charge R8 in STATEMENT_PREV
    // (uRdxCodeMap): die erste Anweisung des Abschnitts und die Zuweisung
    // dort galten bis dahin als "Teil eines Ausdrucks" bzw. "keine
    // einfache Variable" (Gegen-Review R8, Major 3).
    ('initialization Foo();', '19', 'initialization Foo;'),
    ('initialization B := Foo();', '24', 'initialization B := Foo;'),
    // Der Selektor eines case ist ordinal - wie if/while (Review Woche
    // G07-21; bis dahin 'Teil eines Ausdrucks ... als Zeiger').
    ('  case GetKind() of', '15', '  case GetKind of'));
var
  i : Integer;
begin
  for i := 0 to High(CASES) do
    CheckFixed('E', CASES[i, 0], CASES[i, 1], CASES[i, 2]);
end;

procedure TTestRdxExprFixes.Sca066_Refusals;
const
  CASES: array[0..13, 0..2] of string = (
    ('  X := Foo() + 1;', '11', 'Ausdrucks'),
    ('  Bar(Foo());', '10', 'Ausdrucks'),
    ('  if Assigned(GetObj()) then Exit;', '21', 'Ausdrucks'),
    ('  X := Foo().Bar;', '11', 'Ausdrucks'),
    ('  F()();', '4', 'Ausdrucks'),
    ('  Arr[0]();', '9', 'kein blosser Name'),
    ('  Foo( { leer } );', '6', 'nur Leerraum'),
    ('  Foo(X);', '6', 'nur Leerraum'),
    ('  Foo {x} ();', '11', 'nur Leerraum'),
    ('  S := ''Foo()'';', '12', 'nicht mehr'),
    ('  X := TFoo<T>.Create();', '22', 'kein blosser Name'),
    ('  Obj.OnIdle();', '13', 'Ereignis'),
    ('  var P := GetProc();', '19', 'einfache Variable'),
    ('  Self.P := GetProc();', '20', 'einfache Variable'));
var
  i : Integer;
  F : TFixResult;
begin
  for i := 0 to High(CASES) do
    CheckRefused('E', CASES[i, 0], CASES[i, 1], CASES[i, 2]);
  F := Fix('E', InUnit('  Foo();'), 4, 0);
  Assert.AreEqual('', F.Text, 'ohne Spalte');
  Assert.IsTrue(Pos('Spalte', F.Reason) > 0, F.Reason);
end;

procedure TTestRdxExprFixes.Sca066_OwnFunction_Refused;
var
  F   : TFixResult;
  Src : string;
begin
  // In der Funktion Foo meint ein blosses 'Foo' ihr Ergebnis.
  Src := Join(['unit u;', 'implementation', 'function Foo: Integer;', 'begin',
    '  Result := Foo();', 'end;', 'end.']);
  F := Fix('E', Src, 5, 16);
  Assert.AreEqual('', F.Text);
  Assert.IsTrue(Pos('Ergebnis', F.Reason) > 0, F.Reason);
  // Auch in einer lokalen Funktion.
  Src := Join(['unit u;', 'implementation', 'procedure Outer;',
    '  function Inner: Integer;', '  begin', '    Result := Inner();', '  end;',
    'begin', 'end;', 'end.']);
  F := Fix('E', Src, 6, 20);
  Assert.AreEqual('', F.Text);
  Assert.IsTrue(Pos('Ergebnis', F.Reason) > 0, F.Reason);
  // Qualifiziert ist es immer der Aufruf.
  Src := Join(['unit u;', 'implementation', 'function TFoo.Foo: Integer;', 'begin',
    '  Result := Self.Foo();', 'end;', 'end.']);
  F := Fix('E', Src, 5, 21);
  Assert.AreEqual(StringReplace(Src, 'Self.Foo()', 'Self.Foo', []), F.Text,
    F.Reason);
end;

// ---- SCA072 ----

procedure TTestRdxExprFixes.Sca072_Variants;
const
  CASES: array[0..10, 0..3] of string = (
    ('  if IsActive = True then ;', '15', '  if IsActive then ;', 'IsActive'),
    ('  if IsActive <> False then ;', '15', '  if IsActive then ;', 'IsActive'),
    ('  if IsDone = False then Exit;', '13', '  if not IsDone then Exit;', 'IsDone'),
    ('  while Closed <> True do Step;', '16', '  while not Closed do Step;', 'Closed'),
    ('  B := X = True;', '10', '  B := X;', 'X'),
    ('  Exit(X = False);', '10', '  Exit(not X);', 'X'),
    ('  if (A = True) and B then', '9', '  if (A) and B then', 'A'),
    ('  if IsActive = True then WriteLn(''a = True'');', '15', '  if IsActive then WriteLn(''a = True'');', 'IsActive'),
    ('  if X=TRUE then', '7', '  if X then', 'X'),
    ('  until Ready = True;', '15', '  until Ready;', 'Ready'),
    // Im initialization-Abschnitt (Gegen-Review R8, Major 3): SCA072 liest
    // das Token VOR dem Operanden (OPERAND_STARTS, hier ':='), nicht
    // STATEMENT_PREV - die Zeile pinnt, dass der Abschnitt kein Hindernis
    // ist.
    ('initialization B := X = True;', '23', 'initialization B := X;', 'X'));
var
  i : Integer;
  F : TFixResult;
begin
  for i := 0 to High(CASES) do
  begin
    F := Fix('B', InUnit(CASES[i, 0]), 4, StrToInt(CASES[i, 1]));
    Assert.AreEqual(InUnit(CASES[i, 2]), F.Text, CASES[i, 0] + ': ' + F.Reason);
    Assert.AreEqual(CASES[i, 3], F.Name, 'Operand fuer die Typpruefung');
  end;
  // 'then' erst in der Folgezeile.
  F := Fix('B', Join(['unit u;', 'implementation', 'procedure P;',
    '  if X = True', '    then Exit;', 'end.']), 4, 8);
  Assert.AreEqual(Join(['unit u;', 'implementation', 'procedure P;',
    '  if X', '    then Exit;', 'end.']), F.Text, F.Reason);
end;

procedure TTestRdxExprFixes.Sca072_Refusals;
const
  CASES: array[0..10, 0..2] of string = (
    ('  if A and X = True then', '14', 'bindet'),
    ('  if X = True and Y then', '8', 'bindet'),
    ('  if not X = False then', '12', 'bindet'),
    ('  if Obj.Active = True then', '17', 'Pfad'),
    ('  if Self.FDone = False then', '17', 'Pfad'),
    ('  if F(1) = True then', '11', 'kein blosser Name'),
    ('  if X {a} = True then', '12', 'Kommentar'),
    ('  X := Y;', '6', 'nicht mehr'),
    ('  if X >= True then', '9', 'nicht mehr'),
    ('  if X = Truely then', '8', 'nicht mehr'),
    ('  WriteLn(''X = True'');', '14', 'nicht mehr'));
var
  i : Integer;
begin
  for i := 0 to High(CASES) do
    CheckRefused('B', CASES[i, 0], CASES[i, 1], CASES[i, 2]);
end;

// ---- SCA084 ----

procedure TTestRdxExprFixes.Sca084_Variants;
const
  CASES: array[0..5, 0..2] of string = (
    ('  if Assigned(Obj) and (Obj <> nil) then ;', '6', '  if Assigned(Obj) then ;'),
    ('  if (Obj <> nil) and Assigned(Obj) then ;', '6', '  if Assigned(Obj) then ;'),
    ('  if ASSIGNED ( Obj ) and ( obj<>NIL ) then', '6', '  if ASSIGNED ( Obj ) then'),
    ('  Ok := A and Assigned(Obj) and (Obj <> nil);', '15', '  Ok := A and Assigned(Obj);'),
    ('  if Assigned(Obj) and (Obj <> nil) and Obj.Ready then', '6', '  if Assigned(Obj) and Obj.Ready then'),
    ('  if(Obj <> nil) and Assigned(Obj) then', '5', '  if Assigned(Obj) then'));
var
  i : Integer;
begin
  for i := 0 to High(CASES) do
  begin
    CheckFixed('A', CASES[i, 0], CASES[i, 1], CASES[i, 2]);
    Assert.AreEqual('obj', LowerCase(Fix('A', InUnit(CASES[i, 0]), 4,
      StrToInt(CASES[i, 1])).Name), 'Operand fuer die Typpruefung');
  end;
end;

procedure TTestRdxExprFixes.Sca084_Refusals;
const
  CASES: array[0..7, 0..2] of string = (
    ('  if not Assigned(Obj) and (Obj <> nil) then', '10', '"not"'),
    ('  if not (Obj <> nil) and Assigned(Obj) then', '10', '"not"'),
    ('  if Assigned(Obj) and Obj <> nil then', '6', 'Klammern'),
    ('  if Assigned(Obj) and (Other <> nil) then', '6', 'Klammern'),
    ('  if Assigned(Obj) and {x} (Obj <> nil) then', '6', 'Kommentar'),
    ('  if Self.Assigned(Obj) and (Obj <> nil) then', '11', 'qualifiziert'),
    ('  if Boolean(Obj <> nil) and Assigned(Obj) then', '13', '"boolean"'),
    ('  if System.Assigned(Obj) and (Obj <> nil) then', '13', 'qualifiziert'));
var
  i : Integer;
  F : TFixResult;
begin
  for i := 0 to High(CASES) do
    CheckRefused('A', CASES[i, 0], CASES[i, 1], CASES[i, 2]);
  // Ueber zwei Zeilen: keine Hilfe.
  F := Fix('A', Join(['unit u;', 'implementation', 'procedure P;',
    '  if Assigned(Obj) and', '    (Obj <> nil) then', 'end.']), 4, 6);
  Assert.AreEqual('', F.Text);
  Assert.IsTrue(Pos('einer Zeile', F.Reason) > 0, F.Reason);
end;

procedure TTestRdxExprFixes.Sca066_CalleeAndTarget;
const
  // Zeile, Callee, Target
  CASES: array[0..4, 0..2] of string = (
    ('  X := Now();', 'Now', 'X'),
    ('  Result := Foo();', 'Foo', 'Result'),
    ('  Obj.Refresh();', '', ''),
    ('  inherited Create();', '', ''),
    ('  if Done() then Exit;', 'Done', ''));
var
  i : Integer;
  F : TFixResult;
begin
  for i := 0 to High(CASES) do
  begin
    F := Fix('E', InUnit(CASES[i, 0]), 4, Pos('()', CASES[i, 0]));
    Assert.IsTrue(F.Text <> '', CASES[i, 0] + ': ' + F.Reason);
    Assert.AreEqual(CASES[i, 1], F.Name, 'Callee: ' + CASES[i, 0]);
    Assert.AreEqual(CASES[i, 2], F.Target, 'Target: ' + CASES[i, 0]);
  end;
end;

// Der Dialog des Pruefer-Falls R3-02 (Alcinoe.FMX.Dialogs.pas:1767/1768):
// Properties mit 'reference to' bzw. 'of object' und ihre Felder; ARoutine
// ist der Kopf der Routine, deren einzige Anweisung ALine ist (Zeile 18).
function DialogUnit(const ARoutine, ALine: string): string;
begin
  Result := Join(['unit u;', 'interface', 'type',
    '  TRefProc = reference to procedure;',
    '  TObjProc = procedure of object;',
    '  TDlg = class',
    '  private',
    '    FRefProc: TRefProc;',
    '    FObjProc: TObjProc;',
    '  public',
    '    property RefProc: TRefProc read FRefProc write FRefProc;',
    '    property ObjProc: TObjProc read FObjProc;',
    '    procedure Run;',
    '  end;',
    'implementation',
    ARoutine,
    'begin',
    ALine,
    'end;',
    'end.']);
end;

procedure TTestRdxExprFixes.Sca066_PropertyCall_Refused;
const
  SHOW = 'procedure Show(Dlg: TDlg);';
  // Property hinter einem Pfad ('reference to', 'of object') bzw. als
  // blosser Name in einer Methode der Klasse.
  REFUSED: array[0..2, 0..1] of string = (
    (SHOW, '  if Assigned(Dlg.RefProc) then Dlg.RefProc()'),
    (SHOW, '  Dlg.ObjProc();'),
    ('procedure TDlg.Run;', '  RefProc();'));
  // Feld mit Prozedurtyp (Delphi ruft eine Variable ohne () auf - DocWiki,
  // RTL 'FProc;') und Methode: weiter Hilfen.
  OFFERED: array[0..1, 0..1] of string = (
    ('  Dlg.FRefProc();', '  Dlg.FRefProc;'),
    ('  Dlg.Run();', '  Dlg.Run;'));
  EVENTS: array[0..1] of string = ('  Dlg.FOnRun();', '  Dlg.OnIdle();');
var
  i : Integer;
  F : TFixResult;
begin
  // Bis Charge FC lieferte der Planer hier 'OK callee= target=' - der
  // Laeufer prueft dann nichts mehr (CallReason), die Zeile wurde
  // '.. then Dlg.RefProc', und ob Delphi das aufruft, ist nicht belegt.
  for i := 0 to High(REFUSED) do
  begin
    F := Fix('E', DialogUnit(REFUSED[i, 0], REFUSED[i, 1]), 18,
      Pos('()', REFUSED[i, 1]));
    Assert.AreEqual('', F.Text, REFUSED[i, 1]);
    Assert.IsTrue(Pos('als Property deklariert', F.Reason) > 0,
      REFUSED[i, 1] + ': ' + F.Reason);
  end;
  for i := 0 to High(OFFERED) do
  begin
    F := Fix('E', DialogUnit(SHOW, OFFERED[i, 0]), 18, Pos('()', OFFERED[i, 0]));
    Assert.AreEqual(DialogUnit(SHOW, OFFERED[i, 1]), F.Text,
      OFFERED[i, 0] + ': ' + F.Reason);
  end;
  // Ein Ereignisname bleibt gesperrt; ob Feld oder Property, sieht der
  // Planer ohne Typ nicht - der Grund nennt beides (Nachpruefung FC: bis
  // dahin nannte er jede solche Sperre eine Ereignis-Property, im Korpus
  // sind es aber alle Felder wie 'FOnChange()').
  for i := 0 to High(EVENTS) do
  begin
    F := Fix('E', DialogUnit(SHOW, EVENTS[i]), 18, Pos('()', EVENTS[i]));
    Assert.AreEqual('', F.Text, EVENTS[i]);
    Assert.IsTrue(Pos('als Feld ruft Delphi es ohne () auf', F.Reason) > 0,
      EVENTS[i] + ': ' + F.Reason);
    Assert.IsTrue(Pos('als Property ist das nicht belegt', F.Reason) > 0,
      EVENTS[i] + ': ' + F.Reason);
  end;
end;

procedure TTestRdxExprFixes.DeclaredTypeKind_Kinds;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',
      'type',
      '  TRec = record end;',
      '  TPk = packed record end;',
      '  TCb = procedure of object;',
      '  TFn = function: Integer;',
      '  TRef = reference to procedure;',
      '  TCls = class end;',
      '  TFactory<T> = reference to function: T;',
      '  TLookup = TFn;',
      '  // TGone = record',
      '  [Attr] TAttr = class end;',
      '  generic TGen<T> = class end;',
      'var',
      '  GBmp: TBitmap = nil;',
      'implementation',
      'procedure P(X: TControl = nil; Y: Vcl.Graphics.TCanvas = nil);',
      'begin',
      '  if TImage = Sender.ClassType then Exit;',
      '  Ok := TPanel = AClass;',
      'end;',
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    // Variable bzw. Parameter mit Anfangswert: keine Deklaration des Typs
    // (Charge R10 - vorher kam 'nil' heraus).
    Assert.AreEqual('', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tbitmap'), 'var mit nil');
    Assert.AreEqual('', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tcontrol'), 'Default-Parameter');
    Assert.AreEqual('', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tcanvas'), 'qualifiziert');
    Assert.AreEqual('record', TRdxSimpleFixes.DeclaredTypeKind(Map, 'TRec'));
    Assert.AreEqual('record', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tpk'), 'packed');
    Assert.AreEqual('procedure', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tcb'));
    Assert.AreEqual('function', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tfn'));
    Assert.AreEqual('reference', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tref'));
    Assert.AreEqual('class', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tcls'));
    Assert.AreEqual('', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tgone'), 'Kommentar');
    Assert.AreEqual('', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tlist'), 'andere Unit');
    Assert.AreEqual('reference', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tfactory'),
      'generische Parameter uebersprungen');
    Assert.AreEqual('tfn', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tlookup'), 'Alias');
    // Review Woche G07-21: eine Deklaration nur hinter ';', 'type', einem
    // Attribut oder FPC-'generic' - ein Yoda-Vergleich ist keine (bis dahin
    // 'sender' bzw. 'aclass').
    Assert.AreEqual('class', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tattr'),
      'hinter einem Attribut');
    Assert.AreEqual('class', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tgen'),
      'FPC generic');
    Assert.AreEqual('', TRdxSimpleFixes.DeclaredTypeKind(Map, 'timage'),
      'Yoda-Vergleich hinter if');
    Assert.AreEqual('', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tpanel'),
      'Yoda-Vergleich hinter :=');
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxExprFixes.TypeKinds_ResolvedProceduralPointerLike;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',
      'type',
      '  TObjFunc = function: TObject;',
      '  TLookup = TObjFunc;',
      '  TFactory<T> = reference to function: T;',
      '  TCls = class end;',
      '  TClsAlias = TCls;',
      '  PRec = ^TRec;',
      '  TRec = record end;',
      '  TName = string;',
      '  TMyList = TStringList;',
      'implementation',
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    Assert.AreEqual('function', TRdxExprFixes.ResolvedTypeKind(Map, 'tlookup'),
      'Alias auf Funktionstyp');
    Assert.AreEqual('class', TRdxExprFixes.ResolvedTypeKind(Map, 'tclsalias'));
    Assert.AreEqual('string', TRdxExprFixes.ResolvedTypeKind(Map, 'tname'));
    Assert.AreEqual('tstringlist', TRdxExprFixes.ResolvedTypeKind(Map, 'tmylist'),
      'Alias auf einen Typ einer anderen Unit: dessen Name');
    Assert.IsTrue(TRdxExprFixes.ProceduralType(Map, 'tlookup'), 'Alias');
    Assert.IsTrue(TRdxExprFixes.ProceduralType(Map, 'tfactory'), 'generisch');
    Assert.IsTrue(TRdxExprFixes.ProceduralType(Map, 'func'), 'Spring4D Func<T>');
    Assert.IsTrue(TRdxExprFixes.ProceduralType(Map, 'tnotifyevent'), 'nach Name');
    Assert.IsFalse(TRdxExprFixes.ProceduralType(Map, 'tcls'));
    Assert.IsFalse(TRdxExprFixes.ProceduralType(Map, 'integer'));
    Assert.IsTrue(TRdxExprFixes.PointerLikeType(Map, 'tclsalias'), 'Klasse ueber Alias');
    Assert.IsTrue(TRdxExprFixes.PointerLikeType(Map, 'prec'), 'Zeigertyp');
    Assert.IsTrue(TRdxExprFixes.PointerLikeType(Map, 'tobject'));
    Assert.IsFalse(TRdxExprFixes.PointerLikeType(Map, 'trec'), 'Record');
    Assert.IsFalse(TRdxExprFixes.PointerLikeType(Map, 'tlookup'), 'Funktionstyp');
    // E27 (Charge R10): TStringList steht in der Liste der Delphi-Quellen
    // (uRdxRtlTypes) - bewiesen, auch ueber den Alias TMyList dieser Unit;
    // ein Kundentyp einer anderen Unit bleibt unbewiesen.
    Assert.IsTrue(TRdxExprFixes.PointerLikeType(Map, 'tstringlist'),
      'andere Unit, RTL-Klasse (E27)');
    Assert.IsTrue(TRdxExprFixes.PointerLikeType(Map, 'tmylist'),
      'Alias auf eine RTL-Klasse (E27)');
    Assert.IsFalse(TRdxExprFixes.PointerLikeType(Map, 'tchromium'),
      'Kundentyp einer anderen Unit: nicht bewiesen');
    Assert.IsFalse(TRdxExprFixes.PointerLikeType(Map, 'tname'), 'string-Alias');
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxExprFixes.DeclarationQueries_LineFilter;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  // Dieselben Antworten wie der Lauf ueber jedes Token bis Charge FC - die
  // Faelle, an denen ein Vorfilter je Zeile scheitern koennte: Schluessel-
  // wort und Name auf verschiedenen Zeilen, Kette ueber Zeilen, Name nur im
  // Kommentar oder als Teil eines laengeren Namens, zwei Nennungen auf
  // einer Zeile (erst Aufruf, dann Kopf), der erste Treffer zaehlt.
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',
      'interface',
      'type',
      '  TSplit',
      '    = class',
      '    procedure',
      '      Spread;',
      '    procedure Spreadsheet;',
      '    property Items: TList read FItems; // property Ghost',
      '  end;',
      'var',
      '  V: TLate = nil;',
      'type',
      '  TLate = record end;',
      'implementation',
      'procedure TSplit.',
      '  Chained;',
      'begin',
      'end;',
      'procedure Q; begin Two.Go; end; procedure Go;',
      'begin',
      'end;',
      'procedure Q2; begin Two.Hop; end;',
      'procedure Hop;',
      'begin',
      'end;',
      '// Later: der Typ folgt',
      'type',
      '  Later = record end;',
      '  TEq=class(TObject)end;',
      'procedure(*c*)Glued;',
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'Spread'),
      'Name auf der Zeile hinter dem Schluesselwort');
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'SPREAD'), 'Gross/klein');
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'Chained'),
      'Kette ueber zwei Zeilen');
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'Go'),
      'zweite Nennung auf der Zeile');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresRoutine(Map, 'Sheet'),
      'nur Teil eines laengeren Namens');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresRoutine(Map, 'Two'), 'Aufruf-Pfad');
    Assert.IsTrue(TRdxSimpleFixes.DeclaresProperty(Map, 'Items'));
    Assert.IsFalse(TRdxSimpleFixes.DeclaresProperty(Map, 'Ghost'),
      'nur im Kommentar');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresProperty(Map, ''), 'leerer Name');
    Assert.AreEqual('class', TRdxSimpleFixes.DeclaredTypeKind(Map, 'tsplit'),
      '"=" auf der Folgezeile');
    Assert.AreEqual('record', TRdxSimpleFixes.DeclaredTypeKind(Map, 'TLate'),
      'Variable mit Anfangswert davor, Typ dahinter');
    // Nachpruefung R3-03: der Vorfilter sucht den Namen als WORT, ohne
    // Kopie der Zeile, und springt ueber Zeilen ohne Token. Die Grenze
    // ist jedes Zeichen, das kein Bezeichnerzeichen ist - nicht nur
    // Leerraum ('=' dahinter, Kommentar-Ende davor) -, und die Zeile, auf
    // der das naechste Token liegt, zaehlt selbst (Kopf auf der Folgezeile
    // eines Aufrufs, Typ hinter einer Zeile ohne den Namen).
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'Hop'),
      'Kopf auf der Zeile des naechsten Tokens');
    Assert.AreEqual('record', TRdxSimpleFixes.DeclaredTypeKind(Map, 'Later'),
      'Name erst im Kommentar, dann eine Zeile ohne ihn');
    Assert.AreEqual('class', TRdxSimpleFixes.DeclaredTypeKind(Map, 'TEq'),
      '"=" direkt hinter dem Namen');
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'Glued'),
      'Kommentar-Ende direkt vor dem Namen');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresRoutine(Map, 'Glue'),
      'Teil eines Namens');
  finally
    Map.Free;
    SL.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxExprFixes);

end.
