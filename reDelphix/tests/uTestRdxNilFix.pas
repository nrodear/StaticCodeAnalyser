unit uTestRdxNilFix;

// Editorhilfen Stufe 2a, SCA126 (X = nil -> not Assigned(X)): der Planer
// TRdxNilFix aus uRdxSimpleFixes auf Text - ohne Parser, ohne Detektor
// (laeuft in reDelphix.Test UND im FPC-Pruefstand). Die Knoten-Angaben
// (Spalte, Art, Knotentext) kommen hier von Hand - im Anbieter liefert sie
// TSourcePlaces.NodesAt. Abgespalten aus uTestRdxSimpleFixes (SCA138).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxNilFix = class
  public
    [Test] procedure Sca126_Conditions;
    [Test] procedure Sca126_Statements;
    [Test] procedure Sca126_Parentheses;
    [Test] procedure Sca126_MultiLineCondition;
    [Test] procedure Sca126_Refusals;
    [Test] procedure Sca126_CountMatchesDetectorRule;
    [Test] procedure Sca126_OperandRisk;
    // Review Editorhilfen 2a (2026-10-09)
    [Test] procedure Sca126_CallParensStay;
    [Test] procedure Sca126_NotBeforeSelectorStays;
    [Test] procedure Sca126_NestedComparisons_Refused;
    [Test] procedure Sca126_OddQuoteNodeText;
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

// Eine Zeile in einer kleinen Unit (Zeile 4).
function InUnit(const ALine: string): string;
begin
  Result := Join(['unit u;', 'implementation', 'procedure P;', ALine,
    'end.']);
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

// ---- SCA126 ----

procedure TTestRdxNilFix.Sca126_Conditions;
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

procedure TTestRdxNilFix.Sca126_Statements;
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

procedure TTestRdxNilFix.Sca126_Parentheses;
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

procedure TTestRdxNilFix.Sca126_MultiLineCondition;
var
  R : string;
begin
  Assert.AreEqual(Join(['unit u;', 'implementation', 'procedure P;',
      '  if Assigned(A) and', '     Assigned(B) then', 'end.']),
    Fix126(Join(['unit u;', 'implementation', 'procedure P;',
      '  if (A <> nil) and', '     (B <> nil) then', 'end.']), At(4, 3, naCondition,
      '( A <> nil ) and ( B <> nil )'), R), R);
end;

procedure TTestRdxNilFix.Sca126_Refusals;
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

procedure TTestRdxNilFix.Sca126_CountMatchesDetectorRule;
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

procedure TTestRdxNilFix.Sca126_CallParensStay;
var
  R : string;
begin
  // Nach 'From<T>' und 'P^' ist die Klammer ein Aufruf, keine Gruppe.
  Assert.AreEqual(InUnit('  V := TValue.From<Boolean>(not Assigned(FObj));'),
    Fix126(InUnit('  V := TValue.From<Boolean>(FObj = nil);'),
      At(4, 3, naStatement, 'TValue.From<Boolean>(FObj = nil)'), R), R);
  Assert.AreEqual(InUnit('  P^(Assigned(X));'),
    Fix126(InUnit('  P^(X <> nil);'), At(4, 3, naStatement, 'P^(X <> nil)'), R), R);
  // Gruppe nach '=' bzw. in einer Gruppe faellt weg.
  Assert.AreEqual(InUnit('  B := C = Assigned(X);'),
    Fix126(InUnit('  B := C = (X <> nil);'), At(4, 3, naStatement, 'C = ( X <> nil )'), R), R);
end;

procedure TTestRdxNilFix.Sca126_NotBeforeSelectorStays;
var
  R : string;
begin
  // not (X = nil).ToInteger ist not((X = nil).ToInteger) - das 'not'
  // gehoert nicht zum Vergleich.
  Assert.AreEqual(InUnit('  I := not (not Assigned(Obj)).ToInteger;'),
    Fix126(InUnit('  I := not (Obj = nil).ToInteger;'),
      At(4, 3, naStatement, 'not ( Obj = nil ) . ToInteger'), R), R);
end;

procedure TTestRdxNilFix.Sca126_NestedComparisons_Refused;
var
  R : string;
begin
  Assert.AreEqual('', Fix126(InUnit('  if Find(X = nil) = nil then'),
    At(4, 3, naCondition, 'Find ( X = nil ) = nil'), R));
  Assert.IsTrue(Pos('verschachtelt', R) > 0, R);
end;

procedure TTestRdxNilFix.Sca126_OddQuoteNodeText;
var
  R : string;
begin
  // ParseIfStmt verdoppelt das Quote im Literal nicht: der Knotentext
  // traegt ''' statt '''' - dahinter zaehlt er nichts mehr.
  Assert.AreEqual<Integer>(1, TRdxNilFix.CountNilComparisons(
    '( P = nil ) or ( C = '''''' ) or ( Q = nil )'));
  Assert.AreEqual(
    InUnit('  if not Assigned(P) or (C = '''''''') or not Assigned(Q) then'),
    Fix126(InUnit('  if (P = nil) or (C = '''''''') or (Q = nil) then'),
      At(4, 3, naCondition, '( P = nil ) or ( C = '''''' ) or ( Q = nil )'), R), R);
end;

procedure TTestRdxNilFix.Sca126_OperandRisk;
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
  TDUnitX.RegisterTestFixture(TTestRdxNilFix);

end.
