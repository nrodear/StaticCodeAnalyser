unit uRdxMoveSizeFix;

// reDelphix - Editorhilfe fuer SCA154 MoveSizeOfPointer, OHNE ToolsAPI und
// ohne Parser (reine Textlogik, laeuft auch im FPC-Pruefstand): die Laenge
// eines Einzelelement-Aufrufs wird die Groesse des Zieltyps statt der
// Zeigergroesse.
//     Move(Src^, Dst^, SizeOf(PInteger));   ->  ... SizeOf(Integer));
//     FillChar(P^, SizeOf(PDouble), 0);     ->  ... SizeOf(Double), 0);
//     ZeroMemory(P, SizeOf(PInt64));        ->  ... SizeOf(Int64));
//
// DER FUND: uMoveSizeOfPointer meldet die Zeile des Aufrufs (Move,
// FillChar, CopyMemory, ZeroMemory), keine Spalte; die Meldung nennt die
// Routine und den Zeigertyp: '<Routine>(...) uses SizeOf(<PTyp>) which is
// only pointer size ...'. Der Detektor liest lexikalisch (P + Buchstabe,
// ohne '*' an SizeOf, nicht SizeOf(erstes Argument)) - auch ueber Zeilen
// und mit beliebigen Argumenten davor.
//
// AENDERT DAS VERHALTEN (Kennzeichnung, E2): kopiert bzw. gefuellt werden
// danach SizeOf(Zieltyp) Bytes statt 4/8 - das ist der Fix.
//
// NUR EIN ELEMENT (sonst ist die gemeinte Laenge offen - ein Puffer, eine
// Zahl von Elementen, wirklich ein Zeiger): jedes Puffer-Argument ist eine
// einfache Variable in einer dieser Formen, und der Adapter BEWEIST ihren
// Typ (DeclaredTypeOf, Hausregel uRdxFixTable: Typfragen im Adapter):
//   Move/FillChar (untypisiert):    X^ mit X: PTyp,  X mit X: Zieltyp
//   CopyMemory/ZeroMemory (Pointer): X mit X: PTyp,  @X mit X: Zieltyp
// 'Move(Src, Dst, SizeOf(PInteger))' mit Src, Dst: PInteger kopiert einen
// Zeiger - dort ist die Zeigergroesse richtig, und der Typbeweis sperrt.
// Der Zeigertyp muss ein Paar der RTL mit eindeutigem Zieltyp sein
// (POINTEES: PInteger -> Integer, PByte -> Byte, PChar -> Char ...);
// PPointer, PString und eigene Typen (auch ein eigener PInteger) bekommen
// keine Hilfe.
//
// GESPERRT ausserdem: der Aufruf steht nicht genau einmal auf der Zeile,
// reicht ueber die Zeile, traegt einen Kommentar, ist qualifiziert
// ('System.Move', 'List.Move'), hat nicht die erwartete Zahl Argumente, die
// Laenge ist nicht genau 'SizeOf(PTyp)' ('SizeOf(PInteger) + 1'); die Datei
// deklariert die Routine selbst; ein 'with' davor in der Routine (ein
// Argument koennte ein Member sein - dazu fragt der Adapter InWithBlock).
//
// OHNE ToolsAPI, ohne uEngineApi: bindet nur Code-Sicht, Ersetzung und
// Texte (FPC-tauglich).

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Gruende der Ablehnung als englische msgids (Tests vergleichen mit _()).
  R_SIZE_MSG = 'the message does not name the routine and the pointer type';
  R_SIZE_PTR = '%s is not a pointer type of the RTL with one target type';
  R_SIZE_MOVED = 'no call %s(...) on the reported line';
  R_SIZE_MANY = 'the line has more than one call %s(...) - ambiguous';
  R_SIZE_QUALIFIED = '%s is qualified or a member - not the routine of the '
    + 'RTL';
  R_SIZE_LINE = 'the call %s(...) does not end on its line';
  R_SIZE_COMMENT = 'comment inside the call %s(...)';
  R_SIZE_ARGS = 'the call %s(...) does not have %d arguments';
  R_SIZE_FORM = 'the length is not just SizeOf(%s)';
  R_SIZE_BUFFER = 'argument "%s" is not one variable - whether one element '
    + 'is meant stays open';
  R_SIZE_OWN_ROUTINE = 'the file declares its own %s';
  R_SIZE_OWN_TYPE = 'the file declares its own %s - its target type is not '
    + 'that of the RTL';
  R_SIZE_WITH = 'with statement in the routine - an argument could be a '
    + 'member';
  R_SIZE_UNKNOWN = 'type of %s not proven here - it must be declared as %s';
  R_SIZE_TYPE = '%s is declared as %s, not as %s - the call does not copy '
    + 'exactly one element';

type
  // Ein Puffer-Argument des Aufrufs: der Name der Variablen (wie
  // geschrieben) und der Typ, den sie fuer EIN Element haben muss - klein
  // (Expected, Vergleich mit DeclaredTypeOf) und wie angezeigt (Shown).
  TRdxSizeOperand = record
    Name     : string;
    Expected : string;
    Shown    : string;
  end;

  TRdxMoveSizeFix = class
  public
    // SCA154: SizeOf(PTyp) im Aufruf auf ALine -> SizeOf(Zieltyp). Form
    // von TRdxMapPlanner (uRdxFixRunner). Den Typbeweis der Argumente
    // fuehrt der Adapter danach (Operands, OperandReason).
    class function PointeeSize(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Die Puffer-Argumente desselben Aufrufs mit dem Typ, den sie haben
    // muessen; False mit dem Grund wie PointeeSize.
    class function Operands(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AOperands: TArray<TRdxSizeOperand>;
      out AReason: string): Boolean; static;

    // Typbeweis (Adapter): ADeclaredType ist DeclaredTypeOf des Arguments
    // ('' unbekannt). '' oder der Grund.
    class function OperandReason(const AOperand: TRdxSizeOperand;
      const ADeclaredType: string): string; static;

    // Was nur der Adapter weiss: die Zeile liegt in einem with-Block
    // (InWithBlock). '' oder der Grund.
    class function ContextReason(AInWith: Boolean): string; static;

    // Der Zieltyp zu einem Zeigertyp der RTL ('PInteger' -> 'Integer',
    // Gross/klein egal); '' ohne Paar.
    class function PointeeOf(const APointerType: string): string; static;

    // Der Zieltyp zum Zeigertyp der Meldung - Name im Menuetext; '' ohne.
    class function TargetTypeOf(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(): in die reDelphix-Sprache, nie uLocalization

type
  // Ein Paar der RTL: Zeigertyp (klein) und Zieltyp (Schreibweise der RTL).
  TRdxPointee = record
    Ptr    : string;
    Target : string;
  end;

  // Die Routinen des Detektors: Puffer-Argumente (0-basiert), ob sie
  // Pointer sind (CopyMemory/ZeroMemory) oder untypisiert, wo die Laenge
  // steht und wie viele Argumente es sind.
  TRdxSizeRoutine = record
    Name    : string;
    Buffers : Integer;   // die ersten Buffers Argumente sind Puffer
    IsPtr   : Boolean;
    SizeArg : Integer;
    ArgCount: Integer;
  end;

  // Der gelesene Aufruf (ReadCall).
  TRdxSizeCall = record
    Routine : TRdxSizeRoutine;
    Ptr     : string;      // wie in der Meldung
    Target  : string;      // Zieltyp, Schreibweise der RTL
    PtrTok  : TRdxToken;   // das Wort im SizeOf
    Ops     : TArray<TRdxSizeOperand>;
  end;

const
  SPAN_154 = 'sca154';
  MSG_CALL_END = '(...)';
  MSG_SIZEOF   = 'SizeOf(';
  KW_SIZEOF    = 'sizeof';

  ROUTINES: array[0..3] of TRdxSizeRoutine = (
    (Name: 'Move';       Buffers: 2; IsPtr: False; SizeArg: 2; ArgCount: 3),
    (Name: 'FillChar';   Buffers: 1; IsPtr: False; SizeArg: 1; ArgCount: 3),
    (Name: 'CopyMemory'; Buffers: 2; IsPtr: True;  SizeArg: 2; ArgCount: 3),
    (Name: 'ZeroMemory'; Buffers: 1; IsPtr: True;  SizeArg: 1; ArgCount: 2)
  );

  // Zeigertypen der RTL (System; FPC gleich) mit genau einem Zieltyp, des-
  // sen Groesse NICHT die Zeigergroesse ist. Bewusst nicht: PPointer,
  // PString/PAnsiString/PUnicodeString, PInterface (Zeigergroesse - dort
  // aendert die Hilfe nichts), PVariant (verwaltet, Move ist dort ohnehin
  // falsch).
  POINTEES: array[0..20] of TRdxPointee = (
    (Ptr: 'pbyte';       Target: 'Byte'),
    (Ptr: 'pshortint';   Target: 'ShortInt'),
    (Ptr: 'pword';       Target: 'Word'),
    (Ptr: 'psmallint';   Target: 'SmallInt'),
    (Ptr: 'pinteger';    Target: 'Integer'),
    (Ptr: 'pcardinal';   Target: 'Cardinal'),
    (Ptr: 'plongint';    Target: 'LongInt'),
    (Ptr: 'plongword';   Target: 'LongWord'),
    (Ptr: 'pint64';      Target: 'Int64'),
    (Ptr: 'puint64';     Target: 'UInt64'),
    (Ptr: 'pnativeint';  Target: 'NativeInt'),
    (Ptr: 'pnativeuint'; Target: 'NativeUInt'),
    (Ptr: 'psingle';     Target: 'Single'),
    (Ptr: 'pdouble';     Target: 'Double'),
    (Ptr: 'pextended';   Target: 'Extended'),
    (Ptr: 'pcurrency';   Target: 'Currency'),
    (Ptr: 'pboolean';    Target: 'Boolean'),
    (Ptr: 'pchar';       Target: 'Char'),
    (Ptr: 'pansichar';   Target: 'AnsiChar'),
    (Ptr: 'pwidechar';   Target: 'WideChar'),
    (Ptr: 'pdatetime';   Target: 'TDateTime')
  );

  // Dahinter steht der Name in einer Deklaration (DeclaresOwnType).
  OWN_DECL_AFTER: array[0..1] of string = ('=', ':');

class function TRdxMoveSizeFix.PointeeOf(const APointerType: string): string;
var
  P   : TRdxPointee;
  Low : string;
begin
  Result := '';
  Low := LowerCase(APointerType);
  for P in POINTEES do
    if P.Ptr = Low then
      Exit(P.Target);
end;

// Routine und Zeigertyp aus der Meldung; False ohne diese Form oder fuer
// eine Routine, die der Detektor nicht meldet.
function ParseMessage(const AMessage: string; out ARoutine: TRdxSizeRoutine;
  out APtr: string): Boolean;
var
  P, Q : Integer;
  Name : string;
  R    : TRdxSizeRoutine;
  Rest : string;
begin
  Result := False;
  ARoutine := Default(TRdxSizeRoutine);
  APtr := '';
  P := Pos(MSG_CALL_END, AMessage);
  if P <= 1 then
    Exit;
  Name := Copy(AMessage, 1, P - 1);
  Q := Pos(MSG_SIZEOF, AMessage);
  if Q = 0 then
    Exit;
  Rest := Copy(AMessage, Q + Length(MSG_SIZEOF), MaxInt);
  Q := Pos(')', Rest);
  if Q <= 1 then
    Exit;
  APtr := Copy(Rest, 1, Q - 1);
  for R in ROUTINES do
    if SameText(R.Name, Name) then
    begin
      ARoutine := R;
      ARoutine.Name := Name;   // wie geschrieben (Gruende)
      Exit(True);
    end;
end;

class function TRdxMoveSizeFix.TargetTypeOf(const AMessage: string): string;
var
  R   : TRdxSizeRoutine;
  Ptr : string;
begin
  Result := '';
  if ParseMessage(AMessage, R, Ptr) then
    Result := PointeeOf(Ptr);
end;

// Der Text von AFrom bis ATo (beide auf ALine).
function SpanText(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;
begin
  Result := Copy(AMap.Raw(AFrom.Line), AFrom.Col, ATo.EndCol - AFrom.Col);
end;

// Deklariert die Datei den Namen ALow (klein) selbst - als Typ ('PInteger =
// ^TFoo') oder Variable/Parameter ('PInteger: ..')? Nicht 'X: PInteger =
// nil' (Variable mit Anfangswert, ':' davor). Private Hilfe dieser Unit.
function DeclaresOwnType(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  T : TRdxToken;
begin
  Result := True;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if (T.Low = ALow) and InList(After(AMap, T).Low, OWN_DECL_AFTER)
       and (Before(AMap, T).Low <> ':') then
      Exit;
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
  Result := False;
end;

// Steht vor ATok in seiner Routine ein 'with'? Wie in uRdxFloatEqualityFix
// (private Hilfe, ohne die Planer-Unit uRdxSimpleFixes).
function WithBefore(AMap: TRdxCodeMap; const ATok: TRdxToken): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := Before(AMap, ATok);
  while T.Low <> '' do
  begin
    if (T.Low = 'with') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(True);
    if (T.Low = 'implementation') or IsRoutineHead(AMap, T) then
      Exit;
    T := Before(AMap, T);
  end;
end;

// Ein Puffer-Argument aus den Token AToks: 'X', 'X^' (untypisiert) bzw.
// 'X', '@X' (Pointer). False fuer jede andere Form.
function ReadOperand(AMap: TRdxCodeMap; const AToks: TArray<TRdxToken>;
  AIsPtr: Boolean; const APtrLow, APtrShown, ATarget: string;
  out AOperand: TRdxSizeOperand): Boolean;
var
  NameTok : TRdxToken;
  ToPtr   : Boolean;
begin
  Result := False;
  AOperand := Default(TRdxSizeOperand);
  NameTok := Default(TRdxToken);
  case Length(AToks) of
    1:
      begin
        NameTok := AToks[0];
        ToPtr := AIsPtr;          // 'X': Pointer-Parameter -> X ist PTyp
      end;
    2:
      begin
        if (not AIsPtr) and (AToks[1].Low = '^') then
          NameTok := AToks[0]
        else if AIsPtr and (AToks[0].Low = '@') then
          NameTok := AToks[1]
        else
          Exit;
        ToPtr := not AIsPtr;      // 'X^' -> X ist PTyp, '@X' -> Zieltyp
      end;
  else
    Exit;
  end;
  if not NameTok.IsWord or (NameTok.Low = 'nil') then
    Exit;
  AOperand.Name := TokText(AMap, NameTok);
  if ToPtr then
  begin
    AOperand.Expected := APtrLow;
    AOperand.Shown := APtrShown;
  end
  else
  begin
    AOperand.Expected := LowerCase(ATarget);
    AOperand.Shown := ATarget;
  end;
  Result := True;
end;

// Den Aufruf auf ALine lesen und pruefen (alles ausser dem Typbeweis).
// '' oder der Grund.
function ReadCall(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  out ACall: TRdxSizeCall): string;
var
  T, Call, Open, Close : TRdxToken;
  Count, i, Arg, Depth : Integer;
  Args    : array of TArray<TRdxToken>;
  Size    : TArray<TRdxToken>;
  NameLow : string;
  PtrLow  : string;
  Op      : TRdxSizeOperand;
begin
  Result := '';
  ACall := Default(TRdxSizeCall);
  if not ParseMessage(AMessage, ACall.Routine, ACall.Ptr) then
    Exit(_(R_SIZE_MSG));
  ACall.Target := TRdxMoveSizeFix.PointeeOf(ACall.Ptr);
  if ACall.Target = '' then
    Exit(_(R_SIZE_PTR, [ACall.Ptr]));
  NameLow := LowerCase(ACall.Routine.Name);
  PtrLow := LowerCase(ACall.Ptr);
  if (ALine < 1) or (ALine > AMap.LineCount) then
    Exit(MsgMovedSuffix(_(R_SIZE_MOVED, [ACall.Routine.Name])));

  // Genau ein Aufruf 'Name(' auf der Zeile (Code-Sicht).
  Count := 0;
  Call := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.IsWord and (T.Low = NameLow) and (After(AMap, T).Low = '(') then
    begin
      Inc(Count);
      if Count = 1 then
        Call := T;
    end;
    T := After(AMap, T);
  end;
  if Count = 0 then
    Exit(MsgMovedSuffix(_(R_SIZE_MOVED, [ACall.Routine.Name])));
  if Count > 1 then
    Exit(_(R_SIZE_MANY, [ACall.Routine.Name]));
  if InList(Before(AMap, Call).Low, IDENT_PREFIXES) then
    Exit(_(R_SIZE_QUALIFIED, [ACall.Routine.Name]));
  Open := After(AMap, Call);
  Close := MatchClose(AMap, Open, 0);
  if (Close.Low = '') or (Close.Line <> ALine) then
    Exit(_(R_SIZE_LINE, [ACall.Routine.Name]));
  if AMap.HasComment(ALine, Open.Col, Close.Col) then
    Exit(_(R_SIZE_COMMENT, [ACall.Routine.Name]));

  // Argumente an den Kommas der obersten Ebene trennen.
  SetLength(Args, 1);
  Depth := 0;
  T := After(AMap, Open);
  while (T.Low <> '') and TokBefore(T, Close) do
  begin
    if (Depth = 0) and (T.Low = ',') then
      SetLength(Args, Length(Args) + 1)
    else
    begin
      Depth := Depth + ParenDelta(T);
      AddToken(Args[High(Args)], T);
    end;
    T := After(AMap, T);
  end;
  if (Length(Args) <> ACall.Routine.ArgCount)
     or (Length(Args[High(Args)]) = 0) then
    Exit(_(R_SIZE_ARGS, [ACall.Routine.Name, ACall.Routine.ArgCount]));

  // Die Laenge: genau 'SizeOf ( PTyp )'.
  Size := Args[ACall.Routine.SizeArg];
  if (Length(Size) <> 4) or (Size[0].Low <> KW_SIZEOF) or (Size[1].Low <> '(')
     or (Size[2].Low <> PtrLow) or (Size[3].Low <> ')') then
    Exit(_(R_SIZE_FORM, [ACall.Ptr]));
  ACall.PtrTok := Size[2];

  // Die Puffer: je eine Variable in der Form fuer EIN Element.
  for Arg := 0 to ACall.Routine.Buffers - 1 do
  begin
    if (Length(Args[Arg]) = 0)
       or not ReadOperand(AMap, Args[Arg], ACall.Routine.IsPtr, PtrLow,
         TokText(AMap, ACall.PtrTok), ACall.Target, Op) then
    begin
      if Length(Args[Arg]) = 0 then
        Exit(_(R_SIZE_ARGS, [ACall.Routine.Name, ACall.Routine.ArgCount]));
      Exit(_(R_SIZE_BUFFER, [SpanText(AMap, Args[Arg][0],
        Args[Arg][High(Args[Arg])])]));
    end;
    i := Length(ACall.Ops);
    SetLength(ACall.Ops, i + 1);
    ACall.Ops[i] := Op;
  end;

  if DeclaresRoutine(AMap, NameLow) then
    Exit(_(R_SIZE_OWN_ROUTINE, [ACall.Routine.Name]));
  if DeclaresOwnType(AMap, PtrLow) then
    Exit(_(R_SIZE_OWN_TYPE, [ACall.Ptr]));
  if WithBefore(AMap, Call) then
    Exit(_(R_SIZE_WITH));
end;

class function TRdxMoveSizeFix.PointeeSize(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  C : TRdxSizeCall;
begin
  AEdit := Default(TRdxEdit);
  AReason := ReadCall(AMap, ALine, AMessage, C);
  Result := AReason = '';
  if not Result then
    Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_154, C.PtrTok.Line, C.PtrTok.Col,
    C.PtrTok.Line, C.PtrTok.EndCol);
  AEdit.Expected := TokText(AMap, C.PtrTok);
  AEdit.NewText := C.Target;
end;

class function TRdxMoveSizeFix.Operands(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AOperands: TArray<TRdxSizeOperand>;
  out AReason: string): Boolean;
var
  C : TRdxSizeCall;
begin
  AReason := ReadCall(AMap, ALine, AMessage, C);
  Result := AReason = '';
  if Result then
    AOperands := C.Ops
  else
    AOperands := nil;
end;

class function TRdxMoveSizeFix.OperandReason(const AOperand: TRdxSizeOperand;
  const ADeclaredType: string): string;
begin
  Result := '';
  if SameText(ADeclaredType, AOperand.Expected) then
    Exit;
  if ADeclaredType = '' then
    Result := _(R_SIZE_UNKNOWN, [AOperand.Name, AOperand.Shown])
  else
    Result := _(R_SIZE_TYPE, [AOperand.Name, LowerCase(ADeclaredType),
      AOperand.Shown]);
end;

class function TRdxMoveSizeFix.ContextReason(AInWith: Boolean): string;
begin
  Result := '';
  if AInWith then
    Result := _(R_SIZE_WITH);
end;

end.
