unit uTestRdxSimpleFixes;

// Editorhilfen Stufe 2a: die drei Planer aus uRdxSimpleFixes auf Text -
// ohne Parser, ohne Detektor (laeuft in reDelphix.Test UND im
// FPC-Pruefstand). Jeder Fall prueft den Text NACH der Ersetzung
// (PlanByteEdits + ApplyByteEdits, CRLF wie im Editor) bzw. die Ablehnung.
// Die Faelle stammen aus dem Analyse-Workflow editorhilfen-2a-analyse
// (2026-10-09): je Regel die gemeldeten Varianten und die Fallen.
//
// SCA126 bekommt die Knoten-Angaben (Spalte, Art, Knotentext) hier von
// Hand - im Anbieter liefert sie TSourcePlaces.NodesAt. Die Gegenprobe mit
// dem echten Detektor steht in uTestRdxSimpleFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSimpleFixes = class
  public
    // ---- SCA075 ----
    [Test] procedure Sca075_Variants;
    [Test] procedure Sca075_EmptyShortForm_BecomesClassEnd;
    [Test] procedure Sca075_OnlyTheReportedOccurrence;
    [Test] procedure Sca075_Refusals;
    // ---- SCA085 ----
    [Test] procedure Sca085_Variants;
    [Test] procedure Sca085_CommentTrap_UsesCodeOccurrence;
    [Test] procedure Sca085_Refusals;
    // ---- SCA126 ----
    [Test] procedure Sca126_Conditions;
    [Test] procedure Sca126_Statements;
    [Test] procedure Sca126_Parentheses;
    [Test] procedure Sca126_MultiLineCondition;
    [Test] procedure Sca126_Refusals;
    [Test] procedure Sca126_CountMatchesDetectorRule;
    [Test] procedure Sca126_OperandRisk;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxSimpleFixes;

// ---- Helfer ----

function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
  Ok    : Boolean;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Ok := PlanByteEdits(Bytes, AEdits, Plan, Err);
  Assert.IsTrue(Ok, Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Zeilen mit CRLF verbunden (TStringBuilder: string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// SCA075 auf einer Zeile: liefert den neuen Text der ganzen Quelle oder
// '' bei Ablehnung (AReason).
function Fix075(const ASource: string; ALine, ACol: Integer;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxSimpleFixes.ExplicitTObject(Map, ALine,
         Format('`class(TObject)` at column %d - drop the parens', [ACol]), E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

function Fix085(const ASource: string; ALine: Integer; out AReason: string): string;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Edits : TArray<TRdxEdit>;
  Name_ : string;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxSimpleFixes.FreeAndNilFix(Map, ALine, Edits, Name_, AReason) then
      Result := Apply(ASource, Edits);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Knoten-Angaben eines SCA126-Funds (im Anbieter aus NodesAt).
function At(ALine, ACol: Integer; AAnchor: TRdxNilAnchor;
  const ANodeText: string): TRdxNilSite;
begin
  Result.Line     := ALine;
  Result.Col      := ACol;
  Result.Anchor   := AAnchor;
  Result.NodeText := ANodeText;
end;

function Fix126(const ASource: string; const ASite: TRdxNilSite;
  out AReason: string): string;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Plan : TRdxNilPlan;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxNilFix.NilComparison(Map, ASite, Plan) then
      Result := Apply(ASource, Plan.Edits);
    AReason := Plan.Reason;
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Zeile in einer kleinen Unit (Zeile 4).
function InUnit(const ALine: string): string;
begin
  Result := Join(['unit u;', 'implementation', 'procedure P;', ALine,
    'end.']);
end;

// ---- SCA075 ----

procedure TTestRdxSimpleFixes.Sca075_Variants;
const
  CASES: array[0..5, 0..1] of string = (
    ('  TFoo = class(TObject)', '  TFoo = class'),
    ('  TFoo = class ( TObject )', '  TFoo = class'),
    ('  TFoo = class'#9'('#9'TObject'#9')', '  TFoo = class'),
    ('  TFoo = CLASS(tobject)', '  TFoo = CLASS'),
    ('  TFoo = class(TObject) // Basis', '  TFoo = class // Basis'),
    ('type TFoo = class(TObject)end;', 'type TFoo = class end;'));
var
  i : Integer;
  R : string;
begin
  for i := 0 to High(CASES) do
    Assert.AreEqual(InUnit(CASES[i, 1]),
      Fix075(InUnit(CASES[i, 0]), 4, Pos('lass', LowerCase(CASES[i, 0])) - 1, R),
      Format('Fall %d: %s', [i, R]));
end;

procedure TTestRdxSimpleFixes.Sca075_EmptyShortForm_BecomesClassEnd;
var
  R : string;
begin
  // 'class;' waere eine Vorwaertsdeklaration - die Hilfe schreibt 'class end'.
  Assert.AreEqual(InUnit('  EFoo = class end;'),
    Fix075(InUnit('  EFoo = class(TObject);'), 4, 10, R), R);
  // ';' erst in der Folgezeile
  Assert.AreEqual(Join(['unit u;', 'implementation', 'procedure P;',
      '  EFoo = class end', '  ;', 'end.']),
    Fix075(Join(['unit u;', 'implementation', 'procedure P;',
      '  EFoo = class(TObject)', '  ;', 'end.']), 4, 10, R), R);
end;

procedure TTestRdxSimpleFixes.Sca075_OnlyTheReportedOccurrence;
var
  R   : string;
  Src : string;
begin
  // Ein Vorkommen im Kommentar davor bleibt stehen.
  Src := '  { class(TObject) } TFoo = class(TObject)';
  Assert.AreEqual(InUnit('  { class(TObject) } TFoo = class'),
    Fix075(InUnit(Src), 4, 29, R), R);
  // Generic: das zweite 'class' ist das gemeldete.
  Src := '  TFoo<T: class> = class(TObject)';
  Assert.AreEqual(InUnit('  TFoo<T: class> = class'),
    Fix075(InUnit(Src), 4, 20, R), R);
  // Umlaut vor der Stelle: Spalten in UTF-16-Einheiten.
  Src := '  T' + #$00C4 + 'rger = class(TObject)';
  Assert.AreEqual(InUnit('  T' + #$00C4 + 'rger = class'),
    Fix075(InUnit(Src), 4, Pos('class', Src), R), R);
end;

procedure TTestRdxSimpleFixes.Sca075_Refusals;
var
  R : string;
begin
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject) procedure P; end;'), 4, 10, R),
    'Rumpf in derselben Zeile');
  Assert.IsTrue(R <> '');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject, IFoo)'), 4, 10, R),
    'nie class(IFoo)');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TComponent)'), 4, 10, R),
    'Puffer geaendert');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject)'), 4, 11, R),
    'falsche Spalte');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject)'), 4, 0, R),
    'keine Spalte in der Meldung');
end;

// ---- SCA085 ----

function FreeNil(const AFree, ANil: string): string;
begin
  Result := Join(['unit u;', 'procedure P;', 'begin', AFree, ANil, 'end;', 'end.']);
end;

function FreeOnly(const AFree: string): string;
begin
  Result := Join(['unit u;', 'procedure P;', 'begin', AFree, 'end;', 'end.']);
end;

procedure TTestRdxSimpleFixes.Sca085_Variants;
var
  R : string;
begin
  Assert.AreEqual(FreeOnly('  FreeAndNil(L);'),
    Fix085(FreeNil('  L.Free;', '  L := nil;'), 4, R), R);
  Assert.AreEqual(FreeOnly('  FreeAndNil(fObj);'),
    Fix085(FreeNil('  fObj.Free;', '  FOBJ := NIL;'), 4, R), 'Gross/Klein: ' + R);
  Assert.AreEqual(FreeOnly('  FreeAndNil(L) ;'),
    Fix085(FreeNil('  L. Free ;', '  L:=nil'), 4, R), 'Leerraum, ohne ";": ' + R);
  Assert.AreEqual(FreeOnly('  FreeAndNil(L); // weg'),
    Fix085(FreeNil('  L.Free; // weg', '  L := nil;'), 4, R), 'Kommentar bleibt: ' + R);
end;

procedure TTestRdxSimpleFixes.Sca085_CommentTrap_UsesCodeOccurrence;
var
  R   : string;
  Src : string;
begin
  // Das 'Old.Free;' im Kommentar darf NICHT umgeschrieben werden (der
  // alte uQuickFix tat genau das).
  Src := Join(['unit u;', 'procedure P;', 'begin', '  { alt',
    '  Old.Free; }  L.Free;', '  L := nil;', 'end;', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'procedure P;', 'begin', '  { alt',
    '  Old.Free; }  FreeAndNil(L);', 'end;', 'end.']), Fix085(Src, 5, R), R);
end;

procedure TTestRdxSimpleFixes.Sca085_Refusals;
const
  // Zeile vor X.Free; - das nil wuerde bedingt
  GUARDS: array[0..4] of string = ('  if FOwns then', '  else',
    '  with FData do', '  for I := 0 to 1 do', '  1:');
var
  R   : string;
  Src : string;
  i   : Integer;
begin
  for i := 0 to High(GUARDS) do
  begin
    Src := Join(['unit u;', 'procedure P;', 'begin', GUARDS[i], '    X.Free;',
      '  X := nil;', 'end;', 'end.']);
    Assert.AreEqual('', Fix085(Src, 5, R), GUARDS[i]);
    Assert.IsTrue(Pos('bedingt', R) > 0, R);
  end;
  Assert.AreEqual('', Fix085(FreeNil('  X.Free; Log(''x'');', '  X := nil;'), 4, R),
    'Code nach Free;');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free; {$IFDEF A}', '  X := nil;'), 4, R),
    'Direktive nach Free;');
  Assert.AreEqual('', Fix085(FreeNil('  X{owned}.Free;', '  X := nil;'), 4, R),
    'Kommentar im Ausdruck');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;', '  X := nil; Y := 0;'), 4, R),
    'Code nach nil');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;', '  Y := nil;'), 4, R),
    'andere Variable');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;', '  X := nil; // weg'), 4, R),
    'Kommentar in der nil-Zeile');
  Assert.AreEqual('', Fix085(Join(['  X.Free;', '  X := nil;']), 1, R),
    'nil-Zeile ist die letzte');
  Assert.AreEqual('', Fix085(FreeNil('  DoSomething;', '  X := nil;'), 4, R),
    'kein Free');
end;

// ---- SCA126 ----

procedure TTestRdxSimpleFixes.Sca126_Conditions;
var
  R : string;
begin
  Assert.AreEqual(InUnit('  if not Assigned(Obj) then Exit;'),
    Fix126(InUnit('  if Obj = nil then Exit;'), At(4, 3, naCondition, 'Obj = nil'), R), R);
  Assert.AreEqual(InUnit('  if Assigned(Obj) then Obj.Free;'),
    Fix126(InUnit('  if Obj<>NIL then Obj.Free;'), At(4, 3, naCondition, 'Obj <> NIL'), R), R);
  Assert.AreEqual(InUnit('  if not Assigned(Obj) then Exit;'),
    Fix126(InUnit('  if nil = Obj then Exit;'), At(4, 3, naCondition, 'nil = Obj'), R),
    'Yoda: ' + R);
  Assert.AreEqual(InUnit('  while Assigned(x) do x := x.Next;'),
    Fix126(InUnit('  while x <> nil do x := x.Next;'), At(4, 3, naCondition, 'x<>nil'), R), R);
  Assert.AreEqual(InUnit('  if not Assigned(TFoo(Sender)) then'),
    Fix126(InUnit('  if TFoo(Sender) = nil then'), At(4, 3, naCondition, 'TFoo ( Sender ) = nil'), R),
    'Typecast: ' + R);
  Assert.AreEqual(InUnit('  if not Assigned(P^) then'),
    Fix126(InUnit('  if P^ = nil then'), At(4, 3, naCondition, 'P ^ = nil'), R), R);
  Assert.AreEqual(InUnit('  if Assigned(Self.FList) then'),
    Fix126(InUnit('  if Self.FList <> nil then'), At(4, 3, naCondition, 'Self . FList <> nil'), R), R);
  // Kommentar und String hinter dem Bereich bleiben unberuehrt
  Assert.AreEqual(InUnit('  if not Assigned(X) then ShowMessage(''X = nil''); // X <> nil'),
    Fix126(InUnit('  if X = nil then ShowMessage(''X = nil''); // X <> nil'), At(4, 3,
      naCondition, 'X = nil'), R), R);
end;

procedure TTestRdxSimpleFixes.Sca126_Statements;
var
  R : string;
begin
  Assert.AreEqual(InUnit('  B := not Assigned(Obj);'),
    Fix126(InUnit('  B := Obj = nil;'), At(4, 3, naStatement, 'Obj = nil'), R), R);
  Assert.AreEqual(InUnit('  Exit(Assigned(FItems[I]));'),
    Fix126(InUnit('  Exit(FItems[I] <> nil);'), At(4, 3, naStatement, 'FItems [] <> nil'), R), R);
  Assert.AreEqual(InUnit('  Assert(Assigned(Owner), ''x'');'),
    Fix126(InUnit('  Assert(Owner <> nil, ''x'');'), At(4, 3, naStatement,
      'Assert(Owner <> nil, x)'), R), R);
end;

procedure TTestRdxSimpleFixes.Sca126_Parentheses;
var
  R : string;
begin
  Assert.AreEqual(InUnit('  if Assigned(A) and Assigned(B) then'),
    Fix126(InUnit('  if (A <> nil) and (B <> nil) then'), At(4, 3, naCondition,
      '( A <> nil ) and ( B <> nil )'), R), R);
  Assert.AreEqual(InUnit('  if not Assigned(x) or not Assigned(y) then'),
    Fix126(InUnit('  if (nil = x) or (nil = y) then'), At(4, 3, naCondition,
      '( nil = x ) or ( nil = y )'), R), R);
  Assert.AreEqual(InUnit('  if Assigned(Obj) then'),
    Fix126(InUnit('  if not (Obj = nil) then'), At(4, 3, naCondition, 'not ( Obj = nil )'), R),
    'doppelte Verneinung: ' + R);
  Assert.AreEqual(InUnit('  if not Assigned(Obj) then'),
    Fix126(InUnit('  if not (Obj <> nil) then'), At(4, 3, naCondition, 'not ( Obj <> nil )'), R), R);
  Assert.AreEqual(InUnit('  S := (not Assigned(Obj)).ToString;'),
    Fix126(InUnit('  S := (Obj = nil).ToString;'), At(4, 3, naStatement, '(Obj = nil).ToString'), R),
    'Klammer vor "." bleibt: ' + R);
  Assert.AreEqual(InUnit('  Foo(not Assigned(X));'),
    Fix126(InUnit('  Foo(X = nil);'), At(4, 3, naStatement, 'Foo(X = nil)'), R),
    'Aufrufklammer bleibt: ' + R);
end;

procedure TTestRdxSimpleFixes.Sca126_MultiLineCondition;
var
  R : string;
begin
  Assert.AreEqual(Join(['unit u;', 'implementation', 'procedure P;',
      '  if Assigned(A) and', '     Assigned(B) then', 'end.']),
    Fix126(Join(['unit u;', 'implementation', 'procedure P;',
      '  if (A <> nil) and', '     (B <> nil) then', 'end.']), At(4, 3, naCondition,
      '( A <> nil ) and ( B <> nil )'), R), R);
end;

procedure TTestRdxSimpleFixes.Sca126_Refusals;
var
  R : string;
begin
  Assert.AreEqual('', Fix126(InUnit('  Exit(''Value <> nil'');'), At(4, 3, naStatement,
    'Value <> nil'), R), 'Fehlalarm im String');
  Assert.IsTrue(Pos('passen nicht', R) > 0, R);
  Assert.AreEqual('', Fix126(InUnit('  if X {c} = nil then'), At(4, 3, naCondition,
    'X = nil'), R), 'Kommentar im Bereich');
  Assert.AreEqual('', Fix126(InUnit('  if Assigned(X) and (X <> nil) then'), At(4, 3,
    naCondition, 'Assigned ( X ) and ( X <> nil )'), R), 'SCA084');
  Assert.IsTrue(Pos('SCA084', R) > 0, R);
  Assert.AreEqual('', Fix126(InUnit('  TThread.Queue(nil, procedure begin if F <> nil then F.Close; end);'),
    At(4, 3, naStatement, 'TThread.Queue(nil, procedure begin if F <> nil then F.Close; end)'), R),
    'anonyme Methode');
  Assert.AreEqual('', Fix126(InUnit('  if Obj = nil then Exit;'), At(4, 6, naCondition,
    'Obj = nil'), R), 'Spalte zeigt nicht auf if');
  Assert.AreEqual('', Fix126(InUnit('  X := nil;'), At(4, 3, naStatement, 'nil'), R),
    'kein Vergleich im Fund');
  Assert.AreEqual('', Fix126(InUnit('  if @FOnGet = nil then'), At(4, 3, naCondition,
    '@ FOnGet = nil'), R), '@-Operand');
end;

procedure TTestRdxSimpleFixes.Sca126_CountMatchesDetectorRule;
begin
  Assert.AreEqual<Integer>(1, TRdxNilFix.CountNilComparisons('x = nil'));
  Assert.AreEqual<Integer>(1, TRdxNilFix.CountNilComparisons('x<>nil'));
  Assert.AreEqual<Integer>(1, TRdxNilFix.CountNilComparisons('nil = x'));
  Assert.AreEqual<Integer>(2, TRdxNilFix.CountNilComparisons('( x <> nil ) and ( y <> nil )'));
  Assert.AreEqual<Integer>(0, TRdxNilFix.CountNilComparisons('x := nil'));
  Assert.AreEqual<Integer>(0, TRdxNilFix.CountNilComparisons('x <= nil'));
  Assert.AreEqual<Integer>(0, TRdxNilFix.CountNilComparisons('''x = nil'''));
  Assert.AreEqual<Integer>(0, TRdxNilFix.CountNilComparisons('nilable = 1'));
end;

procedure TTestRdxSimpleFixes.Sca126_OperandRisk;
begin
  // kein Einwand: Objekte, Felder, Pfade, Typecasts, unbekannter Typ
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('FList', 'tlist'));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('Obj', ''));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('Self.FOwner', ''));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('FItems[I]', ''));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('TFoo(Sender)', ''));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('P', 'pchar'));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('Intf', 'iinterface'));
  // Klassen mit Endungen, die nach Prozedurtyp klingen koennten
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('FIOHandler', 'tidiohandler'));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('LMethod', 'trttimethod'));
  // 'Online', 'Getaway': kein Grossbuchstabe hinter dem Praefix
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('FOnline', ''));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('Getaway', ''));
  // Ereignis- und Getter-Namen, auch am Ende eines Pfads
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('FOnChange', ''));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('OnClick', ''));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('Button.OnClick', ''));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('Obj.GetOwner', ''));
  // Typen: Prozedur, String, Variant, Array
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('F', 'tnotifyevent'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('F', 'tproc'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('F', 'tfunc'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('F', 'procedure'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('F', 'reference'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('F', 'tmethod'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('S', 'string'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('V', 'variant'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('A', 'array'));
  Assert.AreNotEqual('', TRdxNilFix.NilOperandRisk('F', 'tmycallback'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixes);

end.
