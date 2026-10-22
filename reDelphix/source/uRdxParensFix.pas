unit uRdxParensFix;

// reDelphix - Editorhilfe an EINER Zeile, OHNE ToolsAPI und ohne Parser:
//   SCA094 RedundantParentheses: '((X))' -> '(X)' - das INNERE Paar faellt
//          weg. Der Detektor meldet nur '((' ws X ws '))' mit einem
//          Bezeichner, einer Zahl oder einem String-Literal als X, nie mit
//          '.', '[' oder '(' dahinter; die Spalte der Meldung ist die des
//          aeusseren '('.
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Das
// aeussere Paar bleibt, also bleibt jede Vorrangbindung gleich; die Hilfe
// verlangt zusaetzlich, dass das aeussere Paar KEINE Struktur ist:
//   * Aufruf- oder Typecast-Klammer mit einem Bezeichner als X: '(X)' ist
//     ein Ausdruck, 'X' eine Variable (var-Parameter, Overload, Cast als
//     Wert oder als Variable) - keine Hilfe. Mit einem Literal als X ist
//     der Unterschied weg, dann hilft sie.
//   * Typisierte Array-/Record-Konstante: dort sind Klammern Struktur
//     ('= ((1))', ': ((1))', ', ((1))', Zeilenanfang) - keine Hilfe, ebenso
//     nach '(' (dreifache Klammer) und nach '='.
//   * Eine Klammer um einen Vergleich ('(a = b) and c') meldet der Detektor
//     nie - X ist immer ein einzelnes Token.
// Hilfe nur nach einem Operator (:=, +, -, *, /, <>, <=, >=) oder einem
// Schluesselwort (if, while, until, and, or, xor, not, div, mod, shl, shr,
// in, case, to, downto).

interface

uses
  System.Classes,       // TStrings
  uEngineApi,           // TSourcePlaces
  uMethodd12,           // TLeakFinding
  uRdxBufferMath,       // TRdxEdit
  uRdxCodeMap,          // TRdxCodeMap
  uRdxRecipeRunner;     // TRdxFixOutcome

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_PAREN_MOVED = 'no "((X))" at the reported place';
  R_PAREN_COMMENT = 'comment inside the parentheses';
  R_PAREN_CHAIN = 'followed by ".", "[" or "(" - the parentheses belong to '
    + 'a chain';
  R_PAREN_LINESTART = 'the parentheses start the line - they could belong '
    + 'to a multi-line constant';
  R_PAREN_CALL = 'the outer parenthesis belongs to a call or cast - "(X)" '
    + 'is an expression, "X" a variable';
  R_PAREN_STRUCT = 'the outer parenthesis could belong to a constant '
    + '(array, record) or to a comparison';

type
  // Der Planer von SCA094 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxParensFix = class
  public
    // SCA094: an der Spalte aus der Meldung ('at column N') '((X))' mit X
    // Bezeichner, Zahl oder String; NewText = '(X)' (X unveraendert).
    class function DoubleParens(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Der Planer der Tabelle (TRdxFixPlanner, uRdxFixTable) fuer SCA094.
function PlanRedundantParens(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache (E29), nie uLocalization
  uRdxFixRunner;    // MapFix

const
  SPAN_094 = 'sca094';
  // Davor ist '(' keine Struktur: Operatoren und Schluesselwoerter.
  SAFE_PREV_OPS: array[0..7] of string = (':=', '+', '-', '*', '/', '<>',
    '<=', '>=');
  SAFE_PREV_WORDS: array[0..14] of string = ('if', 'while', 'until', 'and',
    'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'case', 'to',
    'downto');

// Das Ende des Operanden ab AFrom wie im Detektor: Bezeichner, Zahl bzw.
// Hex-Zahl ('$') oder String-Literal. AEnd = Spalte dahinter, ALiteral =
// keine Variable, AString = String-Literal. False, wenn keiner dasteht.
function ScanOperand(const L: string; AFrom: Integer; out AEnd: Integer;
  out ALiteral, AString: Boolean): Boolean;
var
  j : Integer;
begin
  Result := False;
  ALiteral := False;
  AString := False;
  AEnd := AFrom;
  if (AFrom < 1) or (AFrom > Length(L)) then Exit;
  j := AFrom;
  if IsIdentStart(L[j]) then
  begin
    while (j <= Length(L)) and IsIdentChar(L[j]) do Inc(j);
    Result := True;
  end
  else if CharInSet(L[j], ['0'..'9', '$']) then
  begin
    if L[j] = '$' then Inc(j);
    while (j <= Length(L)) and IsIdentChar(L[j]) do Inc(j);
    ALiteral := True;
    Result := j > AFrom;
  end
  else if L[j] = '''' then
  begin
    Inc(j);
    while j <= Length(L) do
    begin
      if L[j] <> '''' then
        Inc(j)
      else if (j < Length(L)) and (L[j + 1] = '''') then
        Inc(j, 2)
      else
        Break;
    end;
    // Das schliessende Quote muss da sein.
    Result := (j <= Length(L)) and (L[j] = '''');
    if Result then Inc(j);
    ALiteral := True;
    AString := True;
  end;
  AEnd := j;
end;

// Steht vor der Klammer an Spalte ACol ein Zeichen, das sie als Gruppe
// ausweist? '' oder der Grund.
function PrevReason(AMap: TRdxCodeMap; ALine, ACol: Integer;
  ALiteral: Boolean): string;
var
  Prev : TRdxToken;
begin
  Result := '';
  Prev := PrevToken(AMap, ALine, ACol);
  if (Prev.Low = '') or (Prev.Line <> ALine) then
    Result := _(R_PAREN_LINESTART)
  else if InList(Prev.Low, SAFE_PREV_OPS) or InList(Prev.Low, SAFE_PREV_WORDS) then
    Exit
  else if Prev.IsWord or (Prev.Low = ')') or (Prev.Low = ']')
     or (Prev.Low = '>') or (Prev.Low = '^') then
  begin
    // Aufruf, Cast oder Indexzugriff: mit einem Literal als X egal.
    if not (Prev.IsWord and ALiteral) then
      Result := _(R_PAREN_CALL);
  end
  else
    Result := _(R_PAREN_STRUCT);
end;

class function TRdxParensFix.DoubleParens(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  L                     : string;
  Col, J, OpEnd, E, K   : Integer;
  Literal, IsString     : Boolean;
  Fits                  : Boolean;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := ColumnFromMessage(AMessage);
  if Col <= 0 then
  begin
    AReason := MsgNoColumn;
    Exit;
  end;
  L := AMap.Raw(ALine);
  J := SkipBlanks(L, Col + 2);
  OpEnd := 1;
  Literal := False;
  IsString := False;
  Fits := (Col + 1 <= Length(L)) and (L[Col] = '(') and (L[Col + 1] = '(')
    and AMap.IsCode(ALine, Col) and AMap.IsCode(ALine, Col + 1)
    and ScanOperand(L, J, OpEnd, Literal, IsString);
  E := SkipBlanks(L, OpEnd);
  Fits := Fits and (E + 1 <= Length(L)) and (L[E] = ')') and (L[E + 1] = ')')
    and AMap.IsCode(ALine, E) and AMap.IsCode(ALine, E + 1);
  if not Fits then
  begin
    AReason := MsgMovedSuffix(_(R_PAREN_MOVED));
    Exit;
  end;
  // Heute unerreichbar (Test Sca094_Comment_NoHelp: diese Eingaben enden
  // schon als "verschoben"): ScanOperand liest nur Bezeichner-, Zahl- oder
  // String-Zeichen, jeder Kommentaroeffner bricht ihn ab oder verhindert
  // das '))'. Die Wache bleibt fuer den Tag, an dem der Operand breiter
  // wird (qualifizierte Namen, Ausdruecke).
  if (IsString and AMap.HasComment(ALine, J, OpEnd - 1))
     or (not IsString and AMap.HasNonCode(ALine, J, OpEnd - 1)) then
  begin
    AReason := _(R_PAREN_COMMENT);
    Exit;
  end;
  K := E + 2;
  if (K <= Length(L)) and CharInSet(L[K], ['.', '[', '(']) then
  begin
    AReason := _(R_PAREN_CHAIN);
    Exit;
  end;
  AReason := PrevReason(AMap, ALine, Col, Literal);
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_094, ALine, Col, ALine, K);
  AEdit.Expected := Copy(L, Col, K - Col);
  AEdit.NewText := '(' + Copy(L, J, OpEnd - J) + ')';
  Result := True;
end;

function PlanRedundantParens(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxParensFix.DoubleParens);
end;

end.
