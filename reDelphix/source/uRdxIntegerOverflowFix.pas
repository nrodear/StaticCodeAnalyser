unit uRdxIntegerOverflowFix;

// reDelphix - Editorhilfe fuer SCA137 IntegerOverflow, OHNE ToolsAPI und
// ohne Parser: 'Total := Count * Size;' wird 'Total := Int64(Count) *
// Size;' - der linke Operand bekommt den Cast, der rechte wird vom Compiler
// mit hochgestuft, die Multiplikation laeuft in 64 Bit. Das ist der Fix und
// aendert das Ergebnis, sobald das Produkt nicht mehr in 32 Bit passt
// (Kennzeichnung E2): bisher still abgeschnitten bzw. mit
// Ueberlaufpruefung (Q+) EIntOverflow.
//
// DER FUND: uIntegerOverflow ist lexisch (Regex auf dem Text ohne Strings
// und Kommentare): '<lhs> := <a> * <b>;' mit drei einfachen Bezeichnern,
// <lhs> in der Routine oder als Feld/Global mit 'Int64|UInt64|QWord'
// deklariert, <a> und <b> keine Zahl und nicht selbst so deklariert. Er
// meldet die Zeile von <lhs> (die Anweisung darf ueber Zeilen gehen) mit
// '<lhs> := <a> * <b> - product overflows in 32-bit before widening to
// Int64; cast one operand to Int64' in der Schreibweise des Quelltexts, ohne
// Spalte. Einen Typbeweis fuehrt er nicht (Kopfkommentar dort: a und b
// koennen schon Int64 sein) - und <lhs> darf hinter einem '.' stehen
// ('Self.Total', 'R.Total': die Regex beginnt an der Wortgrenze).
//
// ZWEI TEILE: die Textform prueft CastLeft am aktuellen Text (s. unten);
// den TYPBEWEIS fuehrt der Adapter der Tabelle (PlanIntegerOverflow in
// uRdxFixTable, Check der Plan-Form) ueber den Quellstellen-Dienst
// (TSourcePlaces.DeclaredTypeOf an der Zeile der Anweisung, InWithBlock)
// und gibt die Antworten an ProofReason: das Ziel muss als Int64, UInt64
// oder QWord, BEIDE Operanden als Integer oder Cardinal (samt Aliasen
// LongInt, LongWord, FixedInt, FixedUInt) bewiesen sein, und die Zeile darf
// nicht in einem with-Block liegen. Ohne Beweis keine Hilfe: ein Double
// oder Variant als Operand machte aus 'Int64(X)' einen Fehler (E2089) bzw.
// eine andere Rechnung, ein Integer-Ziel liefe mit Bereichspruefung (R+)
// in ERangeError,
// ein Funktionsaufruf ohne Klammern oder eine Property hat keinen Typ, den
// DeclaredTypeOf beweist ('' - auch das sperrt).
//
// GESPERRT schon in der Textform (lieber keine Hilfe als eine falsche):
//   - die Meldung nennt nicht drei einfache Bezeichner (auch ein Literal),
//   - die Anweisung 'lhs := a * b;' (Gross/klein egal) steht nicht oder
//     mehrfach mit Beginn auf der gemeldeten Zeile (verschoben, veraltet,
//     schon gecastet, '+ 1' dahinter) - Kommentare und Strings sind nie
//     Code (Code-Sicht), ein Kommentar zwischen den Token stoert nicht,
//   - das Ziel ist ein Pfad ('Self.Total', 'R.Total'),
//   - eine Compiler-Direktive steht in der Anweisung,
//   - die Datei deklariert einen eigenen Bezeichner 'Int64' (Typ, Konstante,
//     Variable, Routine) - der Cast hiesse dann etwas anderes.
//
// FPC-TAUGLICH: nur Textlogik (uRdxCodeMap, uRdxBufferMath, uRdxText,
// uRefactorInfo). Der Adapter steht in uRdxFixTable (Hausregel dort).

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_IO_NO_FORM = 'the message does not name an assignment "X := A * B" of '
    + 'plain identifiers';
  R_IO_MOVED = 'no statement "%s := %s * %s;" starts on the reported line';
  R_IO_MANY = 'the reported line holds "%s := %s * %s;" more than once';
  R_IO_PATH = 'the target %s is reached through a path - the help casts only '
    + 'for a plain variable';
  R_IO_DIRECTIVE = 'compiler directive inside the statement';
  R_IO_SHADOW = 'the file declares its own identifier "Int64" - the cast '
    + 'would not mean the 64-bit integer of the RTL';
  R_IO_WITH = 'the statement is inside a with block - its names can bind to '
    + 'members of the with expression';
  R_IO_TARGET_TYPE = 'the target %s is not proven Int64, UInt64 or QWord here '
    + '(type: %s)';
  R_IO_OPERAND_TYPE = '%s is not proven Integer or Cardinal here (type: %s) - '
    + 'the cast could change the computation or not compile';
  R_IO_UNKNOWN = 'unknown';

type
  // Ergebnis von CastLeft: die Ersetzung des linken Operanden und die drei
  // Namen wie im Quelltext - Left fuer den Menuetext, alle drei fuer den
  // Typbeweis des Adapters (ProofReason).
  TRdxOverflowPlan = record
    Edit   : TRdxEdit;
    Target : string;
    Left   : string;
    Right  : string;
  end;

  // Der Planer auf der Code-Sicht in der Form TRdxPlannerOf<TPlan>
  // (uRdxFixTable): True genau dann, wenn AReason = ''.
  TRdxIntegerOverflowFix = class
  public
    // SCA137: 'lhs := a * b;' auf ALine -> 'lhs := Int64(a) * b;' (s. Kopf;
    // die Textform - den Typbeweis fragt der Adapter mit ProofReason).
    class function CastLeft(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxOverflowPlan;
      out AReason: string): Boolean; static;

    // Der Typbeweis zum Plan, aus den Antworten des Quellstellen-Diensts:
    // AInWith (die Zeile liegt in einem with-Block), die deklarierten Typen
    // von Ziel und Operanden (klein, '' = unbekannt; DeclaredTypeOf). '' oder
    // der Grund.
    class function ProofReason(const APlan: TRdxOverflowPlan;
      AInWith: Boolean; const ATargetType, ALeftType,
      ARightType: string): string; static;
  end;

// Die drei Namen der Meldung ('Total := Count * Size - product overflows
// ...'); False, wenn sie nicht diese Form hat oder einer kein einfacher
// Bezeichner ist.
function ProductOf(const AMessage: string; out ATarget, ALeft,
  ARight: string): Boolean;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText;         // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_137 = 'sca137';
  KEY_ASSIGN = ' := ';
  KEY_TIMES  = ' * ';
  KEY_TAIL   = ' - product overflows';
  CAST_TYPE  = 'Int64';
  CAST_LOW   = 'int64';
  // Ziele, deren Produkt der Detektor meint.
  INT64_TYPES: array[0..2] of string = ('int64', 'uint64', 'qword');
  // Operanden, fuer die 'Int64(X)' uebersetzt und dasselbe rechnet - nur
  // breiter (Integer/Cardinal und ihre Aliase).
  INT32_TYPES: array[0..5] of string = ('integer', 'cardinal', 'longint',
    'longword', 'fixedint', 'fixeduint');
  // Ein eigener Bezeichner 'Int64' (Int64Shadowed): davor ein Routinenwort,
  // vor 'Int64 =' ein Abschnittsanfang, vor 'Int64,' ein Listenanfang.
  SHADOW_ROUTINE: array[0..1] of string = ('function', 'procedure');
  SHADOW_TYPE_PREV: array[0..2] of string = (';', 'type', 'const');
  SHADOW_LIST_PREV: array[0..3] of string = ('var', 'threadvar', ';', '(');

// Ein einfacher Bezeichner (Bezeichner-Anfang, dann Bezeichnerzeichen)?
function IsPlainIdent(const S: string): Boolean;
var
  i : Integer;
begin
  Result := (S <> '') and IsIdentStart(S[1]);
  if not Result then Exit;
  for i := 2 to Length(S) do
    if not IsIdentChar(S[i]) then
      Exit(False);
end;

function ProductOf(const AMessage: string; out ATarget, ALeft,
  ARight: string): Boolean;
var
  A, M, E : Integer;
begin
  ATarget := '';
  ALeft := '';
  ARight := '';
  A := Pos(KEY_ASSIGN, AMessage);
  M := Pos(KEY_TIMES, AMessage);
  E := Pos(KEY_TAIL, AMessage);
  Result := (A > 1) and (M > A) and (E > M);
  if not Result then Exit;
  ATarget := Copy(AMessage, 1, A - 1);
  ALeft := Copy(AMessage, A + Length(KEY_ASSIGN), M - A - Length(KEY_ASSIGN));
  ARight := Copy(AMessage, M + Length(KEY_TIMES), E - M - Length(KEY_TIMES));
  Result := IsPlainIdent(ATarget) and IsPlainIdent(ALeft)
    and IsPlainIdent(ARight);
end;

// Ein Wort, gleich ALow (klein; Gross/klein egal wie Delphi)?
function IsName(const T: TRdxToken; const ALow: string): Boolean;
begin
  Result := T.IsWord and SameIdent(T.Low, ALow);
end;

// Beginnt an T die Anweisung 'ALowTarget := ALowLeft * ALowRight;'? AA und
// AB die Operanden, AStop das ';'.
function ProductAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const ALowTarget, ALowLeft, ALowRight: string;
  out AA, AB, AStop: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  AA := Default(TRdxToken);
  AB := Default(TRdxToken);
  AStop := Default(TRdxToken);
  if not IsName(T, ALowTarget) then Exit;
  N := After(AMap, T);
  if N.Low <> ':=' then Exit;
  AA := After(AMap, N);
  if not IsName(AA, ALowLeft) then Exit;
  N := After(AMap, AA);
  if N.Low <> '*' then Exit;
  AB := After(AMap, N);
  if not IsName(AB, ALowRight) then Exit;
  AStop := After(AMap, AB);
  Result := AStop.Low = ';';
end;

// Deklariert die Datei einen eigenen Bezeichner 'Int64'? Ein Name mit ':'
// dahinter (Variable, Feld, Parameter, Property), 'Int64 =' am Anfang einer
// Typ- oder Konstantendeklaration, 'Int64,' am Anfang einer Liste (var,
// Parameter, Aufzaehlung) oder hinter procedure/function. Nicht: 'X: Int64',
// 'const C: Int64 = 0', 'TPair<Integer, Int64>' - dort ist es der Typ.
function Int64Shadowed(AMap: TRdxCodeMap): Boolean;
var
  T, P, N : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), CAST_LOW);
  while T.Low <> '' do
  begin
    if T.Low = CAST_LOW then
    begin
      P := Before(AMap, T);
      N := After(AMap, T);
      if (N.Low = ':') or InList(P.Low, SHADOW_ROUTINE)
         or ((N.Low = '=') and InList(P.Low, SHADOW_TYPE_PREV))
         or ((N.Low = ',') and InList(P.Low, SHADOW_LIST_PREV)) then
        Exit(True);
    end;
    T := NextTokenOnLineWith(AMap, T, CAST_LOW);
  end;
end;

// Der Typ fuer einen Grund: wie geliefert, '' als 'unknown'.
function TypeText(const ATypeLow: string): string;
begin
  if ATypeLow = '' then
    Result := _(R_IO_UNKNOWN)
  else
    Result := ATypeLow;
end;

{ TRdxIntegerOverflowFix }

class function TRdxIntegerOverflowFix.CastLeft(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxOverflowPlan;
  out AReason: string): Boolean;
var
  LowT, LowL, LowR    : string;
  T, A, B, S          : TRdxToken;
  HitT, HitA, HitB    : TRdxToken;
  HitS                : TRdxToken;
  n                   : Integer;
begin
  APlan := Default(TRdxOverflowPlan);
  AReason := '';
  HitT := Default(TRdxToken);
  HitA := Default(TRdxToken);
  HitB := Default(TRdxToken);
  HitS := Default(TRdxToken);
  if not ProductOf(AMessage, APlan.Target, APlan.Left, APlan.Right) then
  begin
    AReason := _(R_IO_NO_FORM);
    Exit(False);
  end;
  LowT := LowerCase(APlan.Target);
  LowL := LowerCase(APlan.Left);
  LowR := LowerCase(APlan.Right);
  n := 0;
  if (ALine >= 1) and (ALine <= AMap.LineCount) then
  begin
    T := NextToken(AMap, ALine, 1);
    while (T.Low <> '') and (T.Line = ALine) do
    begin
      if ProductAt(AMap, T, LowT, LowL, LowR, A, B, S) then
      begin
        Inc(n);
        HitT := T;
        HitA := A;
        HitB := B;
        HitS := S;
      end;
      T := After(AMap, T);
    end;
  end;
  if n = 0 then
    AReason := MsgMovedSuffix(_(R_IO_MOVED,
      [APlan.Target, APlan.Left, APlan.Right]))
  else if n > 1 then
    AReason := _(R_IO_MANY, [APlan.Target, APlan.Left, APlan.Right])
  else if Before(AMap, HitT).Low = '.' then
    AReason := _(R_IO_PATH, [APlan.Target])
  else if DirectiveBetween(AMap, HitT, HitS.Line, HitS.Col) then
    AReason := _(R_IO_DIRECTIVE)
  else if Int64Shadowed(AMap) then
    AReason := _(R_IO_SHADOW);
  if AReason <> '' then
    Exit(False);
  APlan.Target := TokText(AMap, HitT);
  APlan.Left := TokText(AMap, HitA);
  APlan.Right := TokText(AMap, HitB);
  APlan.Edit.Span := TRefactorSpan.Make(SPAN_137, HitA.Line, HitA.Col,
    HitA.Line, HitA.EndCol);
  APlan.Edit.Expected := APlan.Left;
  APlan.Edit.NewText := CAST_TYPE + '(' + APlan.Left + ')';
  Result := True;
end;

class function TRdxIntegerOverflowFix.ProofReason(
  const APlan: TRdxOverflowPlan; AInWith: Boolean; const ATargetType,
  ALeftType, ARightType: string): string;
begin
  Result := '';
  if AInWith then
    Exit(_(R_IO_WITH));
  if not InList(LowerCase(ATargetType), INT64_TYPES) then
    Exit(_(R_IO_TARGET_TYPE, [APlan.Target, TypeText(ATargetType)]));
  if not InList(LowerCase(ALeftType), INT32_TYPES) then
    Exit(_(R_IO_OPERAND_TYPE, [APlan.Left, TypeText(ALeftType)]));
  if not InList(LowerCase(ARightType), INT32_TYPES) then
    Exit(_(R_IO_OPERAND_TYPE, [APlan.Right, TypeText(ARightType)]));
end;

end.
