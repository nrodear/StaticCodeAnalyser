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
    // Review Quick-Fix-Units 2026-10-14 (Blocker): Prozedurtyp derselben
    // Unit, Pfad-Operanden nur mit bewiesenem Feld.
    [Test] procedure Sca126_ProcTypeOfOwnUnit;
    [Test] procedure Sca126_PathOperands;
    // Semantik-Gegen-Review 2026-10-14 (Major, Charge R8): der positive
    // Beweis wie bei SCA084 - ein Typ einer anderen Unit bleibt ohne Hilfe.
    [Test] procedure Sca126_ForeignType_NotProven;
    // Entscheid E27 (Nico 2026-10-14, Charge R10): Klassen und Interfaces
    // der Delphi-Quellen gelten als bewiesen (uRdxRtlTypes), Kundentypen
    // nicht; die eigene Unit behaelt das letzte Wort.
    [Test] procedure Sca126_RtlType_Proven;
    [Test] procedure RtlTypes_Lookup;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxSimpleFixes, uRdxRtlTypes;

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
  // NilOperandRisk prueft NUR Namen: kein Einwand bei Objekten, Feldern,
  // Pfaden, Typecasts und unbekanntem Typ. Ob ein Pfad oder ein Typ ohne
  // Beweis durchgeht, entscheidet NilOperandReason (Sca126_PathOperands).
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
  // System.SyncObjs: TEvent und TSimpleEvent sind Klassen, keine Ereignisse
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('FDone', 'tevent'));
  Assert.AreEqual('', TRdxNilFix.NilOperandRisk('FDone', 'tsimpleevent'));
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

// Die Pruefung mit Blick in die Datei ASource (NilOperandReason).
function ReasonIn(const ASource, AOperand, ATypeLow: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxNilFix.NilOperandReason(Map, AOperand, ATypeLow);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// FieldTypeOf auf der Datei ASource.
function FieldTypeIn(const ASource, AName: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxSimpleFixes.FieldTypeOf(Map, AName);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Unit mit Feldern verschiedener Art (Zeile 4 ff.).
function FieldUnit: string;
begin
  Result := Join(['unit u;', 'interface', 'type',
    '  TObjFactory = function: TObject;',
    '  TLookup = TObjFactory;',
    '  TNode = class(TObject)',
    '    Next: TNode;',
    '    FMaker: TObjFactory;',
    '    [Weak] FOwner: TObject;',
    '    FA, FB: TChromium;',   // Kundentyp aus einer anderen Unit (bis E27: TList)
    '    procedure Run(First: Integer);',
    '    property Count: Integer read FCount;',
    '  end;',
    '  TRec = record',
    '    Data: Pointer;',
    '    Name: string;',
    '  end;',
    'implementation',
    'procedure P;',
    'var',
    '  First: Boolean;',
    '  Last: TObject;',
    'begin',
    'end;',
    'end.']);
end;

procedure TTestRdxNilFix.Sca126_ProcTypeOfOwnUnit;
var
  R : string;
begin
  // 'TObjFactory = function: TObject' derselben Unit: '= nil' riefe die
  // Funktion auf, Assigned() nicht - der Typname allein verraet es nicht.
  R := ReasonIn(FieldUnit, 'FMaker', 'tobjfactory');
  Assert.IsTrue(Pos('Prozedurtyp', R) > 0, R);
  Assert.IsTrue(Pos('tobjfactory', R) > 0, R);
  // Auch ueber einen Alias.
  Assert.IsTrue(Pos('Prozedurtyp', ReasonIn(FieldUnit, 'F', 'tlookup')) > 0,
    'Alias');
  // Eine Klasse derselben Unit geht; ein Kundentyp einer anderen Unit
  // (TChromium) ist nicht bewiesen - bis Charge R8 ging er durch
  // (Sca126_ForeignType_NotProven); eine RTL-Klasse wie TList ist es seit
  // E27 (Sca126_RtlType_Proven).
  Assert.AreEqual('', ReasonIn(FieldUnit, 'N', 'tnode'));
  R := ReasonIn(FieldUnit, 'L', 'tchromium');
  Assert.IsTrue(Pos('nicht als Klasse', R) > 0, 'Fremdtyp: ' + R);
  // Die Namensregeln von NilOperandRisk gelten weiter.
  Assert.AreNotEqual('', ReasonIn(FieldUnit, 'FOnChange', 'tnotifyevent'));
  Assert.AreNotEqual('', ReasonIn(FieldUnit, 'S', 'string'));
end;

procedure TTestRdxNilFix.Sca126_PathOperands;
var
  R : string;
begin
  // Ein Pfad, der auf ')', ']' oder '^' endet, vergleicht ein Ergebnis.
  // BEWUSSTE LUECKE, hier nur GEPINNT (Gegen-Review R8, Verdacht): fuer
  // diese Operanden gibt es keinen Typbeweis - 'FItems[I]' koennte ein
  // Element eines Arrays von Funktionszeigern sein, 'TFoo(Sender)' ein
  // Cast auf einen Funktionstyp. Der Test haelt den Bestand fest, nicht
  // seine Richtigkeit; ob die Luecke schliesst, entscheidet Nico.
  Assert.AreEqual('', ReasonIn(FieldUnit, 'FItems[I]', ''));
  Assert.AreEqual('', ReasonIn(FieldUnit, 'TFoo(Sender)', ''));
  Assert.AreEqual('', ReasonIn(FieldUnit, 'P^', ''));
  // Das letzte Glied als Feld bewiesen: Klasse (auch mit Attribut) oder
  // Record; ein Feld der Gruppe 'FA, FB: TChromium' ist als Feld bewiesen,
  // sein Typ TChromium aber nicht (Kundentyp, andere Unit) - keine Hilfe
  // (Charge R8; bis E27 stand hier TList).
  Assert.AreEqual('', ReasonIn(FieldUnit, 'P.Next', ''));
  Assert.AreEqual('', ReasonIn(FieldUnit, 'Self.FOwner', ''));
  Assert.IsTrue(Pos('nicht als Klasse', ReasonIn(FieldUnit, 'Obj.FB', '')) > 0,
    'Feldgruppe mit Fremdtyp');
  Assert.AreEqual('', ReasonIn(FieldUnit, 'R.Data', ''));
  // Nicht bewiesen: eine Methode ohne Argumente wuerde von '= nil'
  // aufgerufen, Assigned() pruefte nur den Methodenzeiger.
  R := ReasonIn(FieldUnit, 'List.First', '');
  Assert.IsTrue(Pos('nicht als Feld bewiesen', R) > 0, R);
  Assert.IsTrue(Pos('First', R) > 0, 'das Glied steht im Grund: ' + R);
  Assert.AreNotEqual('', ReasonIn(FieldUnit, 'Obj.ClassParent', ''),
    'Methode aus TObject');
  Assert.AreNotEqual('', ReasonIn(FieldUnit, 'Obj.Count', ''), 'Property');
  Assert.AreNotEqual('', ReasonIn(FieldUnit, 'Obj.Last', ''),
    'lokale Variable ist kein Feld');
  // Ein bewiesenes Feld geht durch dieselben Typpruefungen.
  Assert.IsTrue(Pos('Prozedurtyp', ReasonIn(FieldUnit, 'Obj.FMaker', '')) > 0,
    'Feld mit Prozedurtyp');
  Assert.AreNotEqual('', ReasonIn(FieldUnit, 'R.Name', ''), 'string-Feld');
  // Ein blosser Bezeichner ohne Typ ist nicht bewiesen.
  R := ReasonIn(FieldUnit, 'Obj', '');
  Assert.IsTrue(Pos('nicht bewiesen', R) > 0, R);
  // FieldTypeOf selbst: Typwort, qualifiziert, mehrdeutig.
  Assert.AreEqual('tnode', FieldTypeIn(FieldUnit, 'Next'));
  Assert.AreEqual('tobject', FieldTypeIn(FieldUnit, 'FOwner'));
  Assert.AreEqual('tchromium', FieldTypeIn(FieldUnit, 'FA'));
  Assert.AreEqual('', FieldTypeIn(FieldUnit, 'First'), 'Parameter und lokal');
  Assert.AreEqual('', FieldTypeIn(FieldUnit, 'Count'), 'Property');
  Assert.AreEqual('tobject', FieldTypeIn(Join(['unit u;', 'interface', 'type',
    '  TA = class FX: System.TObject; end;', '  TB = class FX: TObject; end;',
    'implementation', 'end.']), 'FX'), 'qualifiziert, zweimal gleich');
  Assert.AreEqual('', FieldTypeIn(Join(['unit u;', 'interface', 'type',
    '  TA = class FX: TObject; end;', '  TB = class FX: TProc; end;',
    'implementation', 'end.']), 'FX'), 'mehrdeutig');
  Assert.AreEqual('^', FieldTypeIn(Join(['unit u;', 'interface', 'type',
    '  TA = record FX: ^Integer; end;', 'implementation', 'end.']), 'FX'),
    'Zeigertyp');
  Assert.AreEqual('', FieldTypeIn(Join(['unit u;', 'interface', 'type',
    '  TA = class;', '  TB<T: record> = class', '    procedure Q(FX: T);',
    '  end;', 'implementation', 'end.']), 'FX'),
    'Vorwaertsdeklaration und Einschraenkung oeffnen keinen Rumpf');
end;

// Eine Unit, die ihre Typen von anderswo bezieht - und eigene daneben.
function ForeignUnit: string;
begin
  Result := Join(['unit u;', 'interface', 'uses uFactories;', 'type',
    '  TNode = class(TObject)',
    '    FMaker: TObjFactory;',   // aus uFactories: dort 'function: TObject'
    '    Next: TNode;',
    '  end;',
    '  PNode = ^TNode;',
    '  INode = interface end;',
    '  TAlias = TNode;',
    'implementation',
    'end.']);
end;

procedure TTestRdxNilFix.Sca126_ForeignType_NotProven;
var
  R : string;
begin
  // 'uses uFactories; FMaker: TObjFactory' mit 'TObjFactory = function:
  // TObject' DORT: der Name verraet nichts, die Deklaration steht nicht in
  // dieser Unit - 'if FMaker = nil' als 'if not Assigned(FMaker)' aenderte
  // den Sinn. Darum der positive Beweis (PointerLikeType) wie bei SCA084.
  R := ReasonIn(ForeignUnit, 'FMaker', 'tobjfactory');
  Assert.IsTrue(Pos('nicht als Klasse', R) > 0, R);
  Assert.IsTrue(Pos('tobjfactory', R) > 0, 'der Typ steht im Grund: ' + R);
  // Auch ueber den Pfad: das Feld ist bewiesen, sein Typ nicht.
  Assert.IsTrue(Pos('nicht als Klasse', ReasonIn(ForeignUnit, 'Obj.FMaker', '')) > 0,
    'Pfad auf ein Feld mit Fremdtyp');
  // Bewiesen: TObject, Pointer, IInterface, Klasse/Interface/Zeiger dieser
  // Unit, ein Alias darauf.
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'O', 'tobject'));
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'P', 'pointer'));
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'I', 'iinterface'));
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'N', 'tnode'));
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'PN', 'pnode'));
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'IN', 'inode'));
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'A', 'talias'));
  Assert.AreEqual('', ReasonIn(ForeignUnit, 'N.Next', ''), 'Feld mit Klasse der Unit');
end;

// Eine Unit mit Fremdtypen der RTL/VCL und eines Kunden - und RTL-Namen,
// die sie selbst anders deklariert (Charge R10, E27).
function RtlUnit: string;
begin
  Result := Join(['unit u;', 'interface',
    'uses System.Classes, Vcl.Forms, uCef;', 'type',
    '  TStrAlias = TStringList;',          // Alias auf eine RTL-Klasse
    '  TList = record X: Integer; end;',   // RTL-Name, hier ein Record
    '  TStream = function: TObject;',      // RTL-Name, hier ein Funktionstyp
    '  TFoo = class(TObject)',
    '    FList: TStringList;',
    '    FDriver: TChromium;',             // aus uCef: Kundentyp
    '    procedure Paint(C: TCanvas = nil);',
    '  end;',
    'implementation',
    'var',
    '  GBmp: TBitmap = nil;',              // kein 'TBitmap = nil'-Typ
    'end.']);
end;

procedure TTestRdxNilFix.Sca126_RtlType_Proven;
var
  R : string;
begin
  // E27: 'FList: TStringList' aus System.Classes - diese Unit beweist es
  // nicht, die Liste der Delphi-Quellen (uRdxRtlTypes) schon. Generische
  // Argumente und Unit-Praefixe stoeren den Beweis nicht.
  Assert.AreEqual('', ReasonIn(RtlUnit, 'FList', 'tstringlist'));
  Assert.AreEqual('', ReasonIn(RtlUnit, 'FForm', 'tform'), 'Vcl.Forms');
  Assert.AreEqual('', ReasonIn(RtlUnit, 'FItems', 'tlist<tobject>'), 'generisch');
  Assert.AreEqual('', ReasonIn(RtlUnit, 'FQual', 'system.classes.tstringlist'),
    'qualifiziert');
  Assert.AreEqual('', ReasonIn(RtlUnit, 'S', 'istream'), 'Interface aus Winapi.ActiveX');
  Assert.AreEqual('', ReasonIn(RtlUnit, 'A', 'tstralias'),
    'Alias dieser Unit auf eine RTL-Klasse');
  Assert.AreEqual('', ReasonIn(RtlUnit, 'Obj.FList', ''), 'Pfad auf ein Feld mit RTL-Klasse');
  // 'GBmp: TBitmap = nil' und 'C: TCanvas = nil' deklarieren keinen Typ
  // (DeclaredTypeKind las bis R10 'nil' als Art - die Liste kam nie dran).
  Assert.AreEqual('', ReasonIn(RtlUnit, 'GBmp', 'tbitmap'), 'var mit Anfangswert');
  Assert.AreEqual('', ReasonIn(RtlUnit, 'C', 'tcanvas'), 'Default-Parameter');
  // Kundentypen bleiben ohne Hilfe - streng wie bisher.
  R := ReasonIn(RtlUnit, 'FDriver', 'tchromium');
  Assert.IsTrue(Pos('nicht als Klasse', R) > 0, R);
  Assert.IsTrue(Pos('tchromium', R) > 0, 'der Typ steht im Grund: ' + R);
  Assert.IsTrue(Pos('nicht als Klasse', ReasonIn(RtlUnit, 'F', 'tobjfactory')) > 0,
    'Kundentyp');
  // Einen RTL-Namen, den DIESE Unit anders deklariert, entscheidet die
  // Unit: ein Funktionstyp 'TStream' sperrt, ein Record 'TList' bleibt
  // unbewiesen - die Liste ueberstimmt die Deklaration nicht.
  Assert.IsTrue(Pos('Prozedurtyp', ReasonIn(RtlUnit, 'F', 'tstream')) > 0,
    'Funktionstyp mit RTL-Namen');
  Assert.IsTrue(Pos('nicht als Klasse', ReasonIn(RtlUnit, 'L', 'tlist')) > 0,
    'Record mit RTL-Namen');
  // Die Namensregeln (NilOperandRisk) laufen vor der Liste.
  Assert.AreNotEqual('', ReasonIn(RtlUnit, 'FOnChange', 'tnotifyevent'));
  Assert.AreNotEqual('', ReasonIn(RtlUnit, 'S', 'string'));
end;

procedure TTestRdxNilFix.RtlTypes_Lookup;
begin
  // Drin: Klassen und Interfaces der RTL, VCL, FMX, Winapi; generische
  // Argumente und Unit-Praefixe fallen weg.
  Assert.IsTrue(IsRtlClassOrInterface('tstringlist'));
  Assert.IsTrue(IsRtlClassOrInterface('iinterface'));
  Assert.IsTrue(IsRtlClassOrInterface('tform'), 'Vcl.Forms');
  Assert.IsTrue(IsRtlClassOrInterface('tcontrol'), 'auch in FMX.Controls');
  Assert.IsTrue(IsRtlClassOrInterface('idispatch'), 'Winapi.ActiveX');
  Assert.IsTrue(IsRtlClassOrInterface('tlist<integer>'), 'generische Argumente');
  Assert.IsTrue(IsRtlClassOrInterface('system.classes.tlist'), 'Unit-Praefix');
  Assert.IsTrue(IsRtlClassOrInterface('TStringList'), 'Grossschreibung schadet nicht');
  // NICHT drin: was kein Beweis fuer "Klasse oder Interface" ist.
  Assert.IsFalse(IsRtlClassOrInterface('tnotifyevent'), 'Methodenzeiger');
  Assert.IsFalse(IsRtlClassOrInterface('tproc'), 'reference to');
  Assert.IsFalse(IsRtlClassOrInterface('tthreadmethod'), 'procedure of object');
  Assert.IsFalse(IsRtlClassOrInterface('tclass'), 'class of');
  Assert.IsFalse(IsRtlClassOrInterface('pchar'), 'Zeigertyp');
  Assert.IsFalse(IsRtlClassOrInterface('tmethod'), 'Record');
  Assert.IsFalse(IsRtlClassOrInterface('tobjfactory'), 'Kundentyp');
  Assert.IsFalse(IsRtlClassOrInterface('tchromium'), 'Kundentyp (CEF)');
  Assert.IsFalse(IsRtlClassOrInterface('record'), 'Typwort');
  Assert.IsFalse(IsRtlClassOrInterface(''), 'leer');
  Assert.IsFalse(IsRtlClassOrInterface('system.classes.'), 'Praefix ohne Namen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxNilFix);

end.
