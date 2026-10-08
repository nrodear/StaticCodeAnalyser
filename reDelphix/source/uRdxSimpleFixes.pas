unit uRdxSimpleFixes;

// reDelphix - Editorhilfen Stufe 2a (Konzept_Editorhilfen_2026-10-08,
// Nico 2026-10-09): SCA075 class(TObject) -> class, SCA085 Free/nil ->
// FreeAndNil, SCA126 X = nil -> not Assigned(X). OHNE ToolsAPI: aus den
// Zeilen der Datei werden gepruefte Ersetzungen (TRdxEdit), die
// uRdxEditor.ReplaceSpans in EINEM Undo-Schritt schreibt.
//
// GRUNDSATZ: lieber keine Hilfe als eine falsche. Jeder Planer prueft die
// Fundstelle mit derselben Grammatik wie der Detektor und lehnt mit einem
// Grund ab, sobald etwas nicht eindeutig ist (Analyse-Workflow
// editorhilfen-2a-analyse, 2026-10-09). Bezeichner, Schluesselwoerter und
// Leerraum bleiben in der Schreibweise des Puffers.
//
// Vorbild fuer SCA085 war der eingefrorene uQuickFix (Core) - mit zwei
// bewussten Unterschieden: die nil-Zeile wird mit entfernt (dort blieb sie
// stehen), und die Stelle wird auf der Code-Sicht verankert (dort konnte
// ein nicht verankerter Ausdruck 'X.Free;' in einem Kommentar umschreiben).

interface

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxBufferMath;

type
  // Zeichenklassen einer Datei, spaltentreu: 'c' Code, 's' String-Literal,
  // 'k' Kommentar oder Direktive ({...}, (*...*), //...). Block-Kommentare
  // werden ueber Zeilen verfolgt, Strings enden mit der Zeile.
  TRdxCodeMap = class
  private
    FLines   : TStrings;
    FClass   : TArray<string>;
    FSlash   : TArray<Integer>;   // je Zeile: Spalte des '//'-Kommentars, 0 = keiner
    // Zustand nur waehrend des Aufbaus (Create): die Zeile, ihre Klassen
    // und was gerade offen ist.
    FText    : string;
    FKinds   : string;
    FInBrace : Boolean;
    FInParen : Boolean;
    FInStr   : Boolean;
    // Je ein Schritt ab Spalte j der Zeile FText; liefern die Spalte dahinter.
    function StepComment(j: Integer): Integer;
    function StepString(j: Integer): Integer;
    function StepCode(ALineIdx, j: Integer): Integer;
  public
    constructor Create(ALines: TStrings);
    // Zahl der Zeilen der Datei.
    function LineCount: Integer;
    // Rohzeile ALine (1-basiert), '' ausserhalb.
    function Raw(ALine: Integer): string;
    // Klasse des Zeichens (ALine, ACol); ' ' ausserhalb der Zeile.
    function ClassAt(ALine, ACol: Integer): Char;
    // True, wenn (ALine, ACol) Code ist - kein String, kein Kommentar.
    function IsCode(ALine, ACol: Integer): Boolean;
    // Kommentar oder Direktive in ALine zwischen AFrom..ATo.
    function HasComment(ALine, AFrom, ATo: Integer): Boolean;
    // String, Kommentar oder Direktive in ALine zwischen AFrom..ATo.
    function HasNonCode(ALine, AFrom, ATo: Integer): Boolean;
    // Spalte, an der in ALine ein '//'-Kommentar BEGINNT (aus Code heraus,
    // nicht in einem String, {...} oder (*...*)); 0 = keiner.
    function LineCommentCol(ALine: Integer): Integer;
  end;

  // Ein Code-Token: Bezeichner/Schluesselwort (klein in Low), Zahl, oder
  // ein Satzzeichen (':=', '<>', '<=', '>=', '..' als eines).
  TRdxToken = record
    Line : Integer;
    Col  : Integer;   // erstes Zeichen
    Len  : Integer;
    Low  : string;    // klein geschrieben
    function IsWord: Boolean;
    function EndCol: Integer;   // hinter dem letzten Zeichen
  end;

  // Wie ein SCA126-Anker endet: Bedingung (if/while/case bis then/do/of)
  // oder Anweisung (bis ';' bzw. end/else/until/except/finally).
  TRdxNilAnchor = (naCondition, naStatement);

  // Wo eine SCA126-Anweisung beginnt (TSourcePlaces.NodesAt) und was der
  // Detektor dort gezaehlt hat.
  TRdxNilSite = record
    Line     : Integer;
    Col      : Integer;
    Anchor   : TRdxNilAnchor;
    NodeText : string;   // Name bzw. TypeRef des AST-Knotens
  end;

  // Ergebnis von TRdxNilFix.NilComparison.
  TRdxNilPlan = record
    Edits    : TArray<TRdxEdit>;
    Operands : TArray<string>;   // je Ersetzung der Operand X (Typpruefung)
    Reason   : string;           // warum keine Hilfe
  end;

  // SCA075 und SCA085: eine bzw. zwei Zeilen, ohne Parser.
  TRdxSimpleFixes = class
  public
    // SCA075: 'class(TObject)' an der Spalte aus der Meldung ('at column
    // N') -> 'class'. Die leere Kurzform 'class(TObject);' wird zu
    // 'class end;' - nie 'class;' (das waere eine Vorwaertsdeklaration).
    class function ExplicitTObject(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA085: 'X.Free;' (Zeile ALine) + 'X := nil;' (naechste Zeile) ->
    // 'FreeAndNil(X);', die nil-Zeile entfaellt. AName = X wie im Puffer.
    // Typ und uses prueft der Aufrufer (braucht den Quellstellen-Dienst).
    class function FreeAndNilFix(AMap: TRdxCodeMap; ALine: Integer;
      out AEdits: TArray<TRdxEdit>; out AName: string;
      out AReason: string): Boolean; static;
  end;

  // SCA126: X = nil -> not Assigned(X), X <> nil -> Assigned(X).
  TRdxNilFix = class
  public
    // Alle nil-Vergleiche der Anweisung an ASite werden zu Assigned(). Die
    // Zahl der Vergleiche im Code muss zu ASite.NodeText passen (dort hat
    // der Detektor gezaehlt) - alle oder keiner.
    class function NilComparison(AMap: TRdxCodeMap; const ASite: TRdxNilSite;
      out APlan: TRdxNilPlan): Boolean; static;

    // Zahl der nil-Vergleiche in einem AST-Knotentext - dieselbe Regel wie
    // uNilComparison.ContainsNilCompare, aber alle Vorkommen gezaehlt.
    class function CountNilComparisons(const AText: string): Integer; static;

    // Grund, warum 'Assigned(AOperand)' fuer diesen Operanden nicht sicher
    // dasselbe ist wie der Vergleich mit nil; '' = kein Einwand. ATypeLow
    // ist der deklarierte, nackte Typname (DeclaredTypeOf), '' wenn
    // unbekannt. Gesperrt: Ereignis-/Getter-Namen (ein Methoden- oder
    // Funktionszeiger: '= nil' ruft auf, Assigned() prueft den Zeiger),
    // Prozedur-, String-, Variant-, Array- und Mengentypen.
    class function NilOperandRisk(const AOperand, ATypeLow: string): string; static;
  end;

implementation

uses
  System.StrUtils;   // PosEx, EndsText

const
  MAX_REGION_LINES = 25;
  SPAN_075 = 'sca075';
  SPAN_085 = 'sca085';
  SPAN_126 = 'sca126';
  R_TOBJECT_MOVED = 'class(TObject) steht nicht mehr an der gemeldeten Stelle';
  R_FREE_MOVED    = 'X.Free; steht nicht mehr an der gemeldeten Stelle';
  R_NOT_NIL_LINE  = 'die naechste Zeile ist nicht "X := nil;"';

function IsIdentStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsBlank(C: Char): Boolean;
begin
  Result := CharInSet(C, [' ', #9]);
end;

// Erste Spalte ab AFrom, die kein Leerzeichen/Tab ist (Length + 1 am Ende).
function SkipBlanks(const S: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(S)) and IsBlank(S[Result]) do
    Inc(Result);
end;

// Steht ab S[AAt] das Wort AWord (Gross/Klein egal, rechts kein
// Bezeichnerzeichen)?
function WordAt(const S: string; AAt: Integer; const AWord: string): Boolean;
var
  n : Integer;
begin
  n := Length(AWord);
  Result := SameText(Copy(S, AAt, n), AWord)
    and ((AAt + n > Length(S)) or not IsIdentChar(S[AAt + n]));
end;

{ TRdxCodeMap }

constructor TRdxCodeMap.Create(ALines: TStrings);
var
  i, j : Integer;
begin
  inherited Create;
  FLines := ALines;
  SetLength(FClass, ALines.Count);
  SetLength(FSlash, ALines.Count);
  FInBrace := False;
  FInParen := False;
  for i := 0 to ALines.Count - 1 do
  begin
    FText  := ALines[i];
    FKinds := '';
    SetLength(FKinds, Length(FText));
    FInStr := False;
    j := 1;
    while j <= Length(FText) do
      if FInBrace or FInParen then
        j := StepComment(j)
      else if FInStr then
        j := StepString(j)
      else
        j := StepCode(i, j);
    FClass[i] := FKinds;
  end;
  FText  := '';
  FKinds := '';
end;

function TRdxCodeMap.StepComment(j: Integer): Integer;
begin
  FKinds[j] := 'k';
  Result := j + 1;
  if FInBrace then
  begin
    if FText[j] = '}' then FInBrace := False;
  end
  else if (FText[j] = '*') and (j < Length(FText)) and (FText[j + 1] = ')') then
  begin
    FKinds[j + 1] := 'k';
    FInParen := False;
    Result := j + 2;
  end;
end;

function TRdxCodeMap.StepString(j: Integer): Integer;
begin
  FKinds[j] := 's';
  Result := j + 1;
  if FText[j] <> '''' then Exit;
  if (j < Length(FText)) and (FText[j + 1] = '''') then
  begin
    FKinds[j + 1] := 's';   // verdoppeltes '' im String
    Result := j + 2;
  end
  else
    FInStr := False;
end;

function TRdxCodeMap.StepCode(ALineIdx, j: Integer): Integer;
var
  n, k : Integer;
begin
  n := Length(FText);
  Result := j + 1;
  if FText[j] = '''' then
  begin
    FKinds[j] := 's';
    FInStr := True;
  end
  else if (FText[j] = '/') and (j < n) and (FText[j + 1] = '/') then
  begin
    // Zeilenkommentar: der Rest der Zeile.
    FSlash[ALineIdx] := j;
    for k := j to n do
      FKinds[k] := 'k';
    Result := n + 1;
  end
  else if FText[j] = '{' then
  begin
    FKinds[j] := 'k';
    FInBrace := True;
  end
  else if (FText[j] = '(') and (j < n) and (FText[j + 1] = '*') then
  begin
    FKinds[j] := 'k';
    FKinds[j + 1] := 'k';
    FInParen := True;
    Result := j + 2;
  end
  else
    FKinds[j] := 'c';
end;

function TRdxCodeMap.LineCount: Integer;
begin
  Result := FLines.Count;
end;

function TRdxCodeMap.Raw(ALine: Integer): string;
begin
  if (ALine < 1) or (ALine > FLines.Count) then
    Exit('');
  Result := FLines[ALine - 1];
end;

function TRdxCodeMap.ClassAt(ALine, ACol: Integer): Char;
begin
  Result := ' ';
  if (ALine < 1) or (ALine > Length(FClass)) then Exit;
  if (ACol < 1) or (ACol > Length(FClass[ALine - 1])) then Exit;
  Result := FClass[ALine - 1][ACol];
end;

function TRdxCodeMap.IsCode(ALine, ACol: Integer): Boolean;
begin
  Result := ClassAt(ALine, ACol) = 'c';
end;

function TRdxCodeMap.HasComment(ALine, AFrom, ATo: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := AFrom to ATo do
    if ClassAt(ALine, i) = 'k' then
      Exit(True);
end;

function TRdxCodeMap.HasNonCode(ALine, AFrom, ATo: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := AFrom to ATo do
    if CharInSet(ClassAt(ALine, i), ['k', 's']) then
      Exit(True);
end;

function TRdxCodeMap.LineCommentCol(ALine: Integer): Integer;
begin
  Result := 0;
  if (ALine >= 1) and (ALine <= Length(FSlash)) then
    Result := FSlash[ALine - 1];
end;

{ TRdxToken }

function TRdxToken.IsWord: Boolean;
begin
  Result := (Low <> '') and IsIdentStart(Low[1]);
end;

function TRdxToken.EndCol: Integer;
begin
  Result := Col + Len;
end;

{ ---- Token-Lesen auf der Code-Sicht ---- }

// Das Token, das an (ALine, ACol) beginnt (Code vorausgesetzt).
function TokenAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  L    : string;
  j    : Integer;
  Two  : string;
begin
  Result := Default(TRdxToken);
  Result.Line := ALine;
  Result.Col  := ACol;
  L := AMap.Raw(ALine);
  if IsIdentStart(L[ACol]) then
  begin
    j := ACol;
    while (j <= Length(L)) and IsIdentChar(L[j]) and AMap.IsCode(ALine, j) do
      Inc(j);
    Result.Len := j - ACol;
  end
  else if CharInSet(L[ACol], ['0'..'9']) then
  begin
    j := ACol;
    while (j <= Length(L)) and IsIdentChar(L[j]) do Inc(j);
    Result.Len := j - ACol;
  end
  else
  begin
    Two := Copy(L, ACol, 2);
    if ((Two = ':=') or (Two = '<>') or (Two = '<=') or (Two = '>=')
        or (Two = '..')) and AMap.IsCode(ALine, ACol + 1) then
      Result.Len := 2
    else
      Result.Len := 1;
  end;
  Result.Low := LowerCase(Copy(L, ACol, Result.Len));
end;

// Naechstes Code-Token ab (ALine, ACol) einschliesslich - ueber Leerraum,
// Strings, Kommentare und Zeilen hinweg; Low = '' am Dateiende.
function NextToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  Li, Co : Integer;
begin
  Li := ALine;
  Co := ACol;
  while Li <= AMap.LineCount do
  begin
    while Co <= Length(AMap.Raw(Li)) do
    begin
      if AMap.IsCode(Li, Co) and not IsBlank(AMap.Raw(Li)[Co]) then
        Exit(TokenAt(AMap, Li, Co));
      Inc(Co);
    end;
    Inc(Li);
    Co := 1;
  end;
  Result := Default(TRdxToken);
end;

// Token unmittelbar nach ATok.
function After(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := NextToken(AMap, ATok.Line, ATok.EndCol);
end;

// Das Token, das an (ALine, ACol) ENDET (Code, kein Leerraum).
function TokenEndingAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  L : string;
  S : Integer;
begin
  L := AMap.Raw(ALine);
  if IsIdentChar(L[ACol]) then
  begin
    S := ACol;
    while (S > 1) and IsIdentChar(L[S - 1]) and AMap.IsCode(ALine, S - 1) do
      Dec(S);
    Exit(TokenAt(AMap, ALine, S));
  end;
  // Zwei-Zeichen-Operator, der hier endet?
  if (ACol > 1) and AMap.IsCode(ALine, ACol - 1) then
  begin
    Result := TokenAt(AMap, ALine, ACol - 1);
    if Result.Len = 2 then Exit;
  end;
  Result := TokenAt(AMap, ALine, ACol);
end;

// Vorheriges Code-Token vor (ALine, ACol) ausschliesslich.
function PrevToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  Li, Co : Integer;
  L      : string;
begin
  Li := ALine;
  Co := ACol - 1;
  while Li >= 1 do
  begin
    L := AMap.Raw(Li);
    if Co > Length(L) then Co := Length(L);
    while Co >= 1 do
    begin
      if AMap.IsCode(Li, Co) and not IsBlank(L[Co]) then
        Exit(TokenEndingAt(AMap, Li, Co));
      Dec(Co);
    end;
    Dec(Li);
    Co := MaxInt;
  end;
  Result := Default(TRdxToken);
end;

// Vor ATok.
function Before(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := PrevToken(AMap, ATok.Line, ATok.Col);
end;

function IsKeyword(const ALow: string): Boolean;
const
  // Reservierte Woerter, die keinen Operanden beginnen koennen. NICHT
  // darin: Exit, Assert, Free ... - das sind Routinen; 'Exit(' ist eine
  // Aufrufklammer, keine Gruppe.
  KEYWORDS: array[0..37] of string = (
    'and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as',
    'if', 'then', 'else', 'while', 'do', 'for', 'to', 'downto', 'repeat',
    'until', 'case', 'of', 'begin', 'end', 'with', 'try', 'except',
    'finally', 'raise', 'nil', 'var', 'const', 'procedure', 'function',
    'inherited', 'out', 'type');
var
  K : string;
begin
  for K in KEYWORDS do
    if ALow = K then Exit(True);
  Result := False;
end;

{ ---- SCA075 ---- }

// 'at column N' aus der Meldung; 0 = nicht vorhanden.
function ColumnFromMessage(const AMessage: string): Integer;
const
  KEY = 'at column ';
var
  p, i : Integer;
begin
  Result := 0;
  p := Pos(KEY, AMessage);
  if p = 0 then Exit;
  i := p + Length(KEY);
  while (i <= Length(AMessage)) and CharInSet(AMessage[i], ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(AMessage[i]) - Ord('0');
    Inc(i);
  end;
end;

// Dieselbe Grammatik wie der Detektor (uExplicitTObjectInheritance): ab
// ACol 'class', Leerraum, '(', Leerraum, 'TObject', Leerraum, ')'.
// ACloseCol = Spalte der ')'.
function MatchClassTObject(const L: string; ACol: Integer;
  out ACloseCol: Integer): Boolean;
var
  j : Integer;
begin
  Result := False;
  ACloseCol := 0;
  if not WordAt(L, ACol, 'class') or ((ACol > 1) and IsIdentChar(L[ACol - 1])) then
    Exit;
  j := SkipBlanks(L, ACol + 5);
  if (j > Length(L)) or (L[j] <> '(') then Exit;
  j := SkipBlanks(L, j + 1);
  if not WordAt(L, j, 'TObject') then Exit;
  j := SkipBlanks(L, j + 7);
  if (j > Length(L)) or (L[j] <> ')') then Exit;
  ACloseCol := j;
  Result := True;
end;

class function TRdxSimpleFixes.ExplicitTObject(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L        : string;
  Col      : Integer;
  CloseCol : Integer;
  Next     : TRdxToken;
  NewText  : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := ColumnFromMessage(AMessage);
  L := AMap.Raw(ALine);
  if (Col < 1) or (Col + 4 > Length(L)) then
  begin
    AReason := 'Spalte fehlt in der Meldung';
    Exit;
  end;
  if not MatchClassTObject(L, Col, CloseCol) then
  begin
    AReason := R_TOBJECT_MOVED;
    Exit;
  end;
  if AMap.HasNonCode(ALine, Col, CloseCol) then
  begin
    AReason := 'class(TObject) liegt in einem Kommentar oder String';
    Exit;
  end;
  // Was folgt auf die Klammer? 'class' bleibt in der Schreibweise des Puffers.
  NewText := Copy(L, Col, 5);
  Next := NextToken(AMap, ALine, CloseCol + 1);
  if Next.Low = ';' then
    // Leere Kurzform: 'class;' waere eine Vorwaertsdeklaration (E2086).
    NewText := NewText + ' end'
  else if Next.Low = 'end' then
  begin
    if (CloseCol < Length(L)) and IsIdentChar(L[CloseCol + 1]) then
      NewText := NewText + ' ';     // 'class(TObject)end;' -> 'class end;'
  end
  else if (Next.Line = ALine) and (Next.Low <> '') then
  begin
    // 'class(TObject) procedure P; end;' wuerde zu 'class procedure ...' -
    // liest sich als Klassenmethode. Lieber keine Hilfe.
    AReason := 'Klassenrumpf beginnt in derselben Zeile';
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_075, ALine, Col, ALine, CloseCol + 1);
  AEdit.Expected := Copy(L, Col, CloseCol - Col + 1);
  AEdit.NewText  := NewText;
  Result := True;
end;

{ ---- SCA085 ---- }

// 'X . Free ;' ab AColX (X ein Bezeichner): Ende von X, Ende von 'Free'
// und die Spalte des ';'.
function MatchFreeCall(const L: string; AColX: Integer;
  out ANameEnd, AFreeEnd, ASemiCol: Integer): Boolean;
var
  j : Integer;
begin
  Result := False;
  ANameEnd := 0;
  AFreeEnd := 0;
  ASemiCol := 0;
  if (AColX > Length(L)) or not IsIdentStart(L[AColX]) then Exit;
  j := AColX;
  while (j <= Length(L)) and IsIdentChar(L[j]) do Inc(j);
  ANameEnd := j;
  if (j > Length(L)) or (L[j] <> '.') then Exit;
  j := SkipBlanks(L, j + 1);
  if not WordAt(L, j, 'Free') then Exit;
  AFreeEnd := j + 4;
  j := SkipBlanks(L, AFreeEnd);
  if (j > Length(L)) or (L[j] <> ';') then Exit;
  ASemiCol := j;
  Result := True;
end;

// Zeile ALine: erste Anweisung 'X.Free;' - wie
// uFreeAndNilHint.ExtractFreeReceiver, aber auf der Code-Sicht -, dahinter
// hoechstens ein //-Kommentar, und nicht allein hinter then/else/do oder
// einer case-Marke. '' oder der Grund.
function CheckFreeLine(AMap: TRdxCodeMap; ALine: Integer;
  out AColX, ANameEnd, AFreeEnd: Integer): string;
var
  L       : string;
  SemiCol : Integer;
  Rest    : string;
  Prev    : TRdxToken;
begin
  Result := '';
  L := AMap.Raw(ALine);
  AColX := 1;
  while (AColX <= Length(L)) and (IsBlank(L[AColX]) or not AMap.IsCode(ALine, AColX)) do
    Inc(AColX);
  if not MatchFreeCall(L, AColX, ANameEnd, AFreeEnd, SemiCol) then
    Exit(R_FREE_MOVED);
  if AMap.HasNonCode(ALine, AColX, SemiCol) then
    Exit('Kommentar im Ausdruck X.Free;');
  // Hinter dem ';' nur noch Leerraum oder ein //-Kommentar: weiterer Code
  // liefe sonst NACH dem nil (Reihenfolge), ein {-Kommentar oder eine
  // Direktive koennte die nil-Zeile umschliessen.
  Rest := Trim(Copy(L, SemiCol + 1, MaxInt));
  if (Rest <> '') and (Copy(Rest, 1, 2) <> '//') then
    Exit('hinter X.Free; steht noch etwas');
  // X.Free; als einzige Anweisung hinter then/else/do/case-Marke: dann
  // wuerde das bisher unbedingte ':= nil' bedingt.
  Prev := PrevToken(AMap, ALine, AColX);
  if (Prev.Low = 'then') or (Prev.Low = 'else') or (Prev.Low = 'do')
     or (Prev.Low = ':') then
    Result := Format('X.Free; ist die Anweisung hinter "%s" - das nil wuerde bedingt',
      [Prev.Low]);
end;

// Die nil-Zeile N: genau 'X := nil;' (';' optional) mit X = AName.
// '' oder der Grund.
function CheckNilLine(const N, AName: string): string;
var
  k : Integer;
begin
  k := SkipBlanks(N, 1);
  if not WordAt(N, k, AName) then Exit(R_NOT_NIL_LINE);
  k := SkipBlanks(N, k + Length(AName));
  if Copy(N, k, 2) <> ':=' then Exit(R_NOT_NIL_LINE);
  k := SkipBlanks(N, k + 2);
  if not WordAt(N, k, 'nil') then Exit(R_NOT_NIL_LINE);
  k := SkipBlanks(N, k + 3);
  if (k <= Length(N)) and (N[k] = ';') then
    k := SkipBlanks(N, k + 1);
  if k <= Length(N) then
    Exit('hinter X := nil steht noch etwas');
  Result := '';
end;

class function TRdxSimpleFixes.FreeAndNilFix(AMap: TRdxCodeMap;
  ALine: Integer; out AEdits: TArray<TRdxEdit>; out AName: string;
  out AReason: string): Boolean;
var
  L, N                   : string;
  ColX, NameEnd, FreeEnd : Integer;
begin
  Result := False;
  AEdits := nil;
  AName := '';
  // Die nil-Zeile wird samt Zeilenende entfernt - dahinter muss eine
  // Zeile stehen (in einer Unit immer, mindestens 'end.').
  if (ALine < 1) or (ALine + 2 > AMap.LineCount) then
  begin
    AReason := 'keine Zeile hinter der nil-Zuweisung';
    Exit;
  end;
  AReason := CheckFreeLine(AMap, ALine, ColX, NameEnd, FreeEnd);
  if AReason <> '' then Exit;
  L := AMap.Raw(ALine);
  // Zeile i+1: genau 'X := nil;', ohne Kommentar.
  N := AMap.Raw(ALine + 1);
  if AMap.HasNonCode(ALine + 1, 1, Length(N)) then
  begin
    AReason := 'Kommentar oder String in der nil-Zeile';
    Exit;
  end;
  AReason := CheckNilLine(N, Copy(L, ColX, NameEnd - ColX));
  if AReason <> '' then Exit;

  AName := Copy(L, ColX, NameEnd - ColX);
  SetLength(AEdits, 2);
  // E1: 'X.Free' -> 'FreeAndNil(X)'; ';' und ein Kommentar bleiben stehen.
  AEdits[0].Span := TRefactorSpan.Make(SPAN_085, ALine, ColX, ALine, FreeEnd);
  AEdits[0].Expected := Copy(L, ColX, FreeEnd - ColX);
  AEdits[0].NewText  := 'FreeAndNil(' + AName + ')';
  // E2: die nil-Zeile samt Zeilenende.
  AEdits[1].Span := TRefactorSpan.Make(SPAN_085, ALine + 1, 1, ALine + 2, 1);
  AEdits[1].Expected := N + #10;
  AEdits[1].NewText  := '';
  Result := True;
end;

{ ---- SCA126: Zaehlen wie der Detektor ---- }

// String-Literale durch Leerzeichen ersetzt, klein geschrieben.
function BlankStrings(const AText: string): string;
var
  i     : Integer;
  InStr : Boolean;
begin
  Result := AText;
  InStr := False;
  for i := 1 to Length(Result) do
    if Result[i] = '''' then
    begin
      InStr := not InStr;
      Result[i] := ' ';
    end
    else if InStr then
      Result[i] := ' ';
  Result := LowerCase(Result);
end;

// 'nil' an S[p] als ganzes Wort?
function IsNilWordAt(const S: string; p: Integer): Boolean;
begin
  Result := ((p = 1) or not IsIdentChar(S[p - 1]))
    and ((p + 3 > Length(S)) or not IsIdentChar(S[p + 3]));
end;

// Rechts vom 'nil' an S[p] ein '=' oder '<>' (Yoda)? Nur Leerzeichen
// zaehlen als Abstand - der Knotentext hat keine anderen.
function NilComparedRight(const S: string; p: Integer): Boolean;
var
  q : Integer;
begin
  q := p + 3;
  while (q <= Length(S)) and (S[q] = ' ') do Inc(q);
  Result := (q <= Length(S)) and ((S[q] = '=') or (Copy(S, q, 2) = '<>'));
end;

// Links vom 'nil' an S[p] ein '=' (ohne ':', '<', '>' davor) oder '<>'?
function NilComparedLeft(const S: string; p: Integer): Boolean;
var
  q : Integer;
begin
  q := p - 1;
  while (q >= 1) and (S[q] = ' ') do Dec(q);
  if q < 1 then Exit(False);
  if S[q] = '=' then
    Result := (q = 1) or not CharInSet(S[q - 1], [':', '<', '>'])
  else
    Result := (S[q] = '>') and (q > 1) and (S[q - 1] = '<');
end;

class function TRdxNilFix.CountNilComparisons(const AText: string): Integer;
var
  S : string;
  p : Integer;
begin
  // Wie uNilComparison.ContainsNilCompare: String-Literale weg, klein,
  // 'nil' als ganzes Wort mit einem Vergleich rechts oder links.
  Result := 0;
  S := BlankStrings(AText);
  p := Pos('nil', S);
  while p > 0 do
  begin
    if IsNilWordAt(S, p) and (NilComparedRight(S, p) or NilComparedLeft(S, p)) then
      Inc(Result);
    p := PosEx('nil', S, p + 3);
  end;
end;

{ ---- SCA126: Operanden ---- }

type
  TNilCompare = record
    NilTok  : TRdxToken;
    OpTok   : TRdxToken;   // '=' bzw. '<>'; Low = '' -> kein Vergleich
    Yoda    : Boolean;
    First   : TRdxToken;   // erstes Token des Operanden
    Last    : TRdxToken;   // letztes Token des Operanden
  end;

  // Ein Schritt beim Lesen eines Operanden nach links.
  TRdxStep = (stMore, stDone, stFail);

// Ende einer Klammergruppe ab dem oeffnenden Token (gleiche Klammerart);
// Low = '' wenn nicht gefunden.
function MatchForward(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
var
  Depth : Integer;
  T     : TRdxToken;
  Close : string;
begin
  if AOpen.Low = '(' then Close := ')' else Close := ']';
  Depth := 0;
  T := AOpen;
  while T.Low <> '' do
  begin
    if T.Low = AOpen.Low then Inc(Depth)
    else if T.Low = Close then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(T);
    end;
    if T.Line > AOpen.Line + MAX_REGION_LINES then Break;
    T := After(AMap, T);
  end;
  Result := Default(TRdxToken);
end;

function MatchBackward(AMap: TRdxCodeMap; const AClose: TRdxToken): TRdxToken;
var
  Depth : Integer;
  T     : TRdxToken;
  Open  : string;
begin
  if AClose.Low = ')' then Open := '(' else Open := '[';
  Depth := 0;
  T := AClose;
  while T.Low <> '' do
  begin
    if T.Low = AClose.Low then Inc(Depth)
    else if T.Low = Open then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(T);
    end;
    if T.Line < AClose.Line - MAX_REGION_LINES then Break;
    T := Before(AMap, T);
  end;
  Result := Default(TRdxToken);
end;

function IsOperandWord(const ATok: TRdxToken): Boolean;
begin
  Result := ATok.IsWord and not IsKeyword(ATok.Low);
end;

// Kann hinter ATok eine Aufruf-Klammer folgen ('F(..)', 'A[..](..)',
// '(..)(..)')?
function IsCallable(const ATok: TRdxToken): Boolean;
begin
  Result := IsOperandWord(ATok) or (ATok.Low = ')') or (ATok.Low = ']');
end;

// T steht auf ')' bzw. ']': ueber die Gruppe nach links.
function StepLeftOverGroup(AMap: TRdxCodeMap; var T: TRdxToken;
  var AFirst: TRdxToken): TRdxStep;
var
  Open, P : TRdxToken;
begin
  Open := MatchBackward(AMap, T);
  if Open.Low = '' then Exit(stFail);
  P := Before(AMap, Open);
  // '(..)' ohne Namen davor ist eine Gruppe: dort beginnt der Operand.
  if (Open.Low = '(') and not (IsCallable(P) or (P.Low = '^')) then
  begin
    AFirst := Open;
    Exit(stDone);
  end;
  T := P;
  Result := stMore;
end;

// Ein Schritt nach links ueber '^', eine Klammergruppe oder 'Name' bzw.
// '.Name'.
function StepLeft(AMap: TRdxCodeMap; var T: TRdxToken;
  var AFirst: TRdxToken): TRdxStep;
var
  P : TRdxToken;
begin
  if T.Low = '^' then
  begin
    T := Before(AMap, T);
    Exit(stMore);
  end;
  if (T.Low = ')') or (T.Low = ']') then
    Exit(StepLeftOverGroup(AMap, T, AFirst));
  if not IsOperandWord(T) then
    Exit(stFail);
  P := Before(AMap, T);
  if P.Low <> '.' then
  begin
    AFirst := T;
    Exit(stDone);
  end;
  T := Before(AMap, P);
  Result := stMore;
end;

// Operand LINKS vom Operator: Bezeichnerkette mit '.', '^', [..], (..).
function OperandBefore(AMap: TRdxCodeMap; const AOp: TRdxToken;
  out AFirst, ALast: TRdxToken): Boolean;
var
  T    : TRdxToken;
  Step : TRdxStep;
begin
  ALast := Before(AMap, AOp);
  AFirst := Default(TRdxToken);
  T := ALast;
  repeat
    Step := StepLeft(AMap, T, AFirst);
  until Step <> stMore;
  Result := Step = stDone;
end;

// Ein Suffix rechts von T ('.Name', '^', '[..]', '(..)' hinter Name oder
// Gruppe): T rueckt darauf vor. False = der Operand endet bei T.
function StepRight(AMap: TRdxCodeMap; var T: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  Result := True;
  if (N.Low = '.') and IsOperandWord(After(AMap, N)) then
    T := After(AMap, N)
  else if N.Low = '^' then
    T := N
  else if (N.Low = '[') or ((N.Low = '(') and IsCallable(T)) then
    T := MatchForward(AMap, N)
  else
    Result := False;
end;

// Operand RECHTS vom Operator (Yoda: nil = X).
function OperandAfter(AMap: TRdxCodeMap; const AOp: TRdxToken;
  out AFirst, ALast: TRdxToken): Boolean;
var
  T     : TRdxToken;
  Moved : Boolean;
begin
  AFirst := After(AMap, AOp);
  ALast := Default(TRdxToken);
  T := AFirst;
  if T.Low = '(' then
    T := MatchForward(AMap, T)
  else if not IsOperandWord(T) then
    Exit(False);
  Moved := True;
  while Moved and (T.Low <> '') do
    Moved := StepRight(AMap, T);
  ALast := T;
  Result := T.Low <> '';
end;

// Darf vor einem Vergleichsglied stehen? Alles andere ('@', 'not' ohne
// Klammer, Rechenzeichen, ein weiterer Vergleich) macht die Grenze des
// Operanden unklar - dann keine Hilfe.
function IsLeftBoundary(const ATok: TRdxToken): Boolean;
begin
  Result := (ATok.Low = '(') or (ATok.Low = ',') or (ATok.Low = '[')
    or (ATok.Low = ':=') or (ATok.Low = 'if') or (ATok.Low = 'while')
    or (ATok.Low = 'case') or (ATok.Low = 'and') or (ATok.Low = 'or')
    or (ATok.Low = 'xor');
end;

// Darf hinter einem Vergleichsglied stehen?
function IsRightBoundary(const ATok: TRdxToken): Boolean;
begin
  Result := (ATok.Low = ')') or (ATok.Low = ',') or (ATok.Low = ']')
    or (ATok.Low = ';') or (ATok.Low = 'then') or (ATok.Low = 'do')
    or (ATok.Low = 'of') or (ATok.Low = 'and') or (ATok.Low = 'or')
    or (ATok.Low = 'xor') or (ATok.Low = 'end') or (ATok.Low = 'else')
    or (ATok.Low = 'until') or (ATok.Low = 'except') or (ATok.Low = 'finally');
end;

// Text zwischen zwei Tokens derselben Zeile (Rohtext).
function TextBetween(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken): string;
begin
  Result := Copy(AMap.Raw(AFirst.Line), AFirst.Col, ALast.EndCol - AFirst.Col);
end;

// Ohne Leerraum, klein - fuer den Vergleich mit dem Bereichstext.
function Squeezed(const AText: string): string;
begin
  Result := LowerCase(StringReplace(StringReplace(AText, ' ', '',
    [rfReplaceAll]), #9, '', [rfReplaceAll]));
end;

{ ---- SCA126: die Anweisung lesen ---- }

type
  // Was NilComparison ueber die Anweisung sammelt.
  TNilScan = record
    StartTok : TRdxToken;
    EndTok   : TRdxToken;
    Cmps     : TArray<TNilCompare>;
    Count    : Integer;   // belegte Eintraege in Cmps
    Region   : string;    // Tokens ohne Leerraum, klein (SCA084-Probe)
  end;

  // Ein Vergleich als Ersetzung.
  TNilSpan = record
    First   : TRdxToken;
    Last    : TRdxToken;
    NewText : string;
  end;

// Beginnt an ASite noch die gemeldete Anweisung (Code; bei einer
// Bedingung das Schluesselwort if/while/case)?
function StartsStatement(AMap: TRdxCodeMap; const ASite: TRdxNilSite): Boolean;
var
  Low : string;
begin
  if not AMap.IsCode(ASite.Line, ASite.Col) then Exit(False);
  if ASite.Anchor <> naCondition then Exit(True);
  Low := TokenAt(AMap, ASite.Line, ASite.Col).Low;
  Result := (Low = 'if') or (Low = 'while') or (Low = 'case');
end;

// Endet der Bereich bei T (auf Klammertiefe 0)? Bedingung bis
// then/do/of, Anweisung bis ';' oder end/else/until/except/finally.
function IsRegionEnd(const T: TRdxToken; AAnchor: TRdxNilAnchor): Boolean;
begin
  if AAnchor = naCondition then
    Result := (T.Low = 'then') or (T.Low = 'do') or (T.Low = 'of')
  else
    Result := (T.Low = ';') or (T.Low = 'end') or (T.Low = 'else')
      or (T.Low = 'until') or (T.Low = 'except') or (T.Low = 'finally');
end;

function DepthDelta(const T: TRdxToken): Integer;
begin
  if (T.Low = '(') or (T.Low = '[') then
    Result := 1
  else if (T.Low = ')') or (T.Low = ']') then
    Result := -1
  else
    Result := 0;
end;

// Ein 'nil' im Bereich: ein Vergleich (ACmp.OpTok gesetzt), keiner
// (ACmp.OpTok.Low = '', etwa nil als Argument) - '' - oder ein Grund.
function ReadComparison(AMap: TRdxCodeMap; const ANil: TRdxToken;
  out ACmp: TNilCompare): string;
var
  Prev : TRdxToken;
begin
  Result := '';
  ACmp := Default(TNilCompare);
  ACmp.NilTok := ANil;
  Prev := Before(AMap, ANil);
  if (Prev.Low = '=') or (Prev.Low = '<>') then
  begin
    ACmp.OpTok := Prev;
    if not OperandBefore(AMap, Prev, ACmp.First, ACmp.Last) then
      Result := 'Operand vor dem Vergleich nicht eindeutig';
    Exit;
  end;
  ACmp.OpTok := After(AMap, ANil);
  if (ACmp.OpTok.Low <> '=') and (ACmp.OpTok.Low <> '<>') then
  begin
    ACmp.OpTok := Default(TRdxToken);
    Exit;
  end;
  ACmp.Yoda := True;
  if not OperandAfter(AMap, ACmp.OpTok, ACmp.First, ACmp.Last) then
    Result := 'Operand hinter dem Vergleich nicht eindeutig';
end;

// Ein Token des Bereichs aufnehmen: Vergleiche sammeln, anonyme Methoden
// sperren (dort mischen sich Anweisungen in den Ausdruck). '' oder Grund.
function TakeToken(AMap: TRdxCodeMap; const T: TRdxToken;
  var AScan: TNilScan): string;
var
  C : TNilCompare;
begin
  Result := '';
  if T.Low = 'begin' then
    Exit('anonyme Methode in der Anweisung');
  if T.Low <> 'nil' then Exit;
  Result := ReadComparison(AMap, T, C);
  if (Result <> '') or (C.OpTok.Low = '') then Exit;
  if AScan.Count = Length(AScan.Cmps) then
    SetLength(AScan.Cmps, 2 * AScan.Count + 4);
  AScan.Cmps[AScan.Count] := C;
  Inc(AScan.Count);
end;

// Den Bereich der Anweisung ab ASite lesen. '' oder der Grund.
function ScanStatement(AMap: TRdxCodeMap; const ASite: TRdxNilSite;
  out AScan: TNilScan): string;
var
  T     : TRdxToken;
  Depth : Integer;
  SB    : TStringBuilder;
begin
  Result := '';
  AScan := Default(TNilScan);
  AScan.StartTok := TokenAt(AMap, ASite.Line, ASite.Col);
  T := AScan.StartTok;
  if ASite.Anchor = naCondition then
    T := After(AMap, T);   // das Schluesselwort if/while/case selbst
  Depth := 0;
  SB := TStringBuilder.Create;
  try
    while (T.Low <> '') and (T.Line <= ASite.Line + MAX_REGION_LINES) do
    begin
      SB.Append(T.Low);
      if (Depth = 0) and IsRegionEnd(T, ASite.Anchor) then
      begin
        AScan.EndTok := T;
        Break;
      end;
      Inc(Depth, DepthDelta(T));
      Result := TakeToken(AMap, T, AScan);
      if Result <> '' then Exit;
      T := After(AMap, T);
    end;
    AScan.Region := SB.ToString;
  finally
    SB.Free;
  end;
  SetLength(AScan.Cmps, AScan.Count);
  if AScan.EndTok.Low = '' then
    Result := 'Ende der Anweisung nicht gefunden';
end;

// Kommentar oder Direktive im Bereich AFirst..ALast? Der Detektor sieht
// sie nicht, eine Ersetzung koennte sie zerreissen.
function RegionHasComment(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken): Boolean;
var
  i : Integer;
begin
  if AFirst.Line = ALast.Line then
    Exit(AMap.HasComment(AFirst.Line, AFirst.Col, ALast.Col));
  Result := False;
  for i := AFirst.Line to ALast.Line do
    if AMap.HasComment(i, 1, Length(AMap.Raw(i))) then
      Exit(True);
end;

// Eine Klammer, die GENAU den Vergleich umschliesst, geht mit:
//   not (X = nil)  -> Assigned(X)        not (X <> nil) -> not Assigned(X)
//   (X <> nil) and -> Assigned(X) and    (keine Aufruf-/Index-Klammer,
//   kein '.', '[', '^' dahinter)
// AFlipped ist ASpan.NewText mit umgekehrter Bedeutung - das, was mit dem
// 'not' davor herauskommt.
procedure WidenOverGroup(AMap: TRdxCodeMap; const AFlipped: string;
  var ASpan: TNilSpan);
var
  OpenT, CloseT, Outer, Behind : TRdxToken;
begin
  OpenT  := Before(AMap, ASpan.First);
  CloseT := After(AMap, ASpan.Last);
  if (OpenT.Low <> '(') or (CloseT.Low <> ')') or (OpenT.Line <> CloseT.Line)
     or (OpenT.Line <> ASpan.First.Line) then
    Exit;
  Outer := Before(AMap, OpenT);
  if (Outer.Low = 'not') and (Outer.Line = OpenT.Line) then
  begin
    ASpan.First   := Outer;
    ASpan.Last    := CloseT;
    ASpan.NewText := AFlipped;
    Exit;
  end;
  Behind := After(AMap, CloseT);
  if not IsCallable(Outer) and (Behind.Low <> '.') and (Behind.Low <> '[')
     and (Behind.Low <> '^') then
  begin
    ASpan.First := OpenT;
    ASpan.Last  := CloseT;
  end;
end;

// Die Ersetzung fuer einen Vergleich. '' oder der Grund.
function PlanComparison(AMap: TRdxCodeMap; const ACmp: TNilCompare;
  const ARegion: string; out AEdit: TRdxEdit; out AOperand: string): string;
var
  Span     : TNilSpan;
  Positive : Boolean;
  Flipped  : string;
begin
  AEdit := Default(TRdxEdit);
  AOperand := '';
  if ACmp.First.Line <> ACmp.Last.Line then
    Exit('Operand ueber mehrere Zeilen');
  AOperand := TextBetween(AMap, ACmp.First, ACmp.Last);
  // Schon Assigned(X) in derselben Anweisung: das ist SCA084
  // (AssignedAndAssignedNil) - dessen Hilfe statt 'Assigned(X) and Assigned(X)'.
  if Pos('assigned(' + Squeezed(AOperand) + ')', ARegion) > 0 then
    Exit('Assigned(X) steht schon in der Anweisung (SCA084)');
  Positive := ACmp.OpTok.Low = '<>';
  Span := Default(TNilSpan);
  if ACmp.Yoda then
  begin
    Span.First := ACmp.NilTok;
    Span.Last  := ACmp.Last;
  end
  else
  begin
    Span.First := ACmp.First;
    Span.Last  := ACmp.NilTok;
  end;
  if Span.First.Line <> Span.Last.Line then
    Exit('Vergleich ueber mehrere Zeilen');
  if not IsLeftBoundary(Before(AMap, Span.First))
     or not IsRightBoundary(After(AMap, Span.Last)) then
    Exit(Format('Grenze des Vergleichs unklar ("%s %s ... %s")',
      [Before(AMap, Span.First).Low, Span.First.Low, After(AMap, Span.Last).Low]));
  // '<>' -> Assigned(X), '=' -> not Assigned(X); Flipped ist das Gegenteil.
  Span.NewText := 'Assigned(' + AOperand + ')';
  Flipped := 'not ' + Span.NewText;
  if not Positive then
  begin
    Flipped := Span.NewText;
    Span.NewText := 'not ' + Span.NewText;
  end;
  WidenOverGroup(AMap, Flipped, Span);
  AEdit.Span := TRefactorSpan.Make(SPAN_126, Span.First.Line, Span.First.Col,
    Span.Last.Line, Span.Last.EndCol);
  AEdit.Expected := Copy(AMap.Raw(Span.First.Line), Span.First.Col,
    Span.Last.EndCol - Span.First.Col);
  AEdit.NewText  := Span.NewText;
  Result := '';
end;

class function TRdxNilFix.NilComparison(AMap: TRdxCodeMap;
  const ASite: TRdxNilSite; out APlan: TRdxNilPlan): Boolean;
var
  Expected : Integer;
  Scan     : TNilScan;
  i        : Integer;
begin
  Result := False;
  APlan := Default(TRdxNilPlan);
  Expected := CountNilComparisons(ASite.NodeText);
  if Expected = 0 then
  begin
    APlan.Reason := 'kein nil-Vergleich im Fund';
    Exit;
  end;
  if not StartsStatement(AMap, ASite) then
  begin
    APlan.Reason := 'Anweisung steht nicht mehr an der gemeldeten Stelle';
    Exit;
  end;
  APlan.Reason := ScanStatement(AMap, ASite, Scan);
  if APlan.Reason <> '' then Exit;
  if Length(Scan.Cmps) <> Expected then
  begin
    APlan.Reason := Format('Code und Fund passen nicht zusammen (%d statt %d Vergleiche)',
      [Length(Scan.Cmps), Expected]);
    Exit;
  end;
  if RegionHasComment(AMap, Scan.StartTok, Scan.EndTok) then
  begin
    APlan.Reason := 'Kommentar oder Direktive in der Anweisung';
    Exit;
  end;
  SetLength(APlan.Edits, Length(Scan.Cmps));
  SetLength(APlan.Operands, Length(Scan.Cmps));
  for i := 0 to High(Scan.Cmps) do
  begin
    APlan.Reason := PlanComparison(AMap, Scan.Cmps[i], Scan.Region,
      APlan.Edits[i], APlan.Operands[i]);
    if APlan.Reason <> '' then
    begin
      APlan.Edits := nil;
      APlan.Operands := nil;
      Exit;
    end;
  end;
  Result := True;
end;

{ ---- SCA126: Operanden-Pruefung ---- }

// Letzter Bezeichner, wenn AText mit einem endet ('Self.FOnChange' ->
// 'FOnChange'); '' bei ')', ']' oder '^' am Ende - dort wird ein Ergebnis
// verglichen, kein blosser Bezeichner.
function TrailingIdent(const AText: string): string;
var
  i : Integer;
  S : string;
begin
  S := TrimRight(AText);
  i := Length(S);
  while (i >= 1) and IsIdentChar(S[i]) do
    Dec(i);
  Result := Copy(S, i + 1, MaxInt);
  if (Result <> '') and not IsIdentStart(Result[1]) then
    Result := '';
end;

// 'OnChange', 'FOnChange' (Ereignis) bzw. 'GetItem' (Getter): ein
// Grossbuchstabe hinter dem Praefix, sonst waere 'Online' ein Ereignis.
function HasCapPrefix(const AIdent, APrefix: string): Boolean;
var
  n : Integer;
begin
  n := Length(APrefix);
  Result := (Length(AIdent) > n) and (Copy(AIdent, 1, n) = APrefix)
    and CharInSet(AIdent[n + 1], ['A'..'Z']);
end;

class function TRdxNilFix.NilOperandRisk(const AOperand,
  ATypeLow: string): string;
const
  // Genau diese Namen. 'tmethod' ist der Record hinter 'of object'.
  RISKY_TYPES: array[0..17] of string = (
    'string', 'ansistring', 'unicodestring', 'widestring', 'shortstring',
    'rawbytestring', 'utf8string', 'variant', 'olevariant', 'array', 'set',
    'procedure', 'function', 'reference', 'tmethod', 'tthreadmethod',
    'tpredicate', 'tthreadprocedure');
  // Endungen von Prozedurtypen (TNotifyEvent, TProc, TFunc, ...). NICHT
  // 'handler' oder 'method': TIdIOHandler, TRttiMethod sind Klassen.
  RISKY_SUFFIXES: array[0..5] of string = (
    'event', 'proc', 'func', 'callback', 'procedure', 'function');
  TYPE_RISK = '%s ist vom Typ %s - Assigned() ist dafuer nicht sicher gleichwertig';
var
  Ident : string;
  T     : string;
begin
  Result := '';
  Ident := TrailingIdent(AOperand);
  if (Ident <> '') and (HasCapPrefix(Ident, 'On') or HasCapPrefix(Ident, 'FOn')
     or HasCapPrefix(Ident, 'Get')) then
    Exit(Format('%s sieht nach Ereignis oder Funktion aus - Assigned() prueft '
      + 'dann den Zeiger, nicht das Ergebnis', [Ident]));
  if ATypeLow = '' then Exit;
  for T in RISKY_TYPES do
    if ATypeLow = T then
      Exit(Format(TYPE_RISK, [AOperand, ATypeLow]));
  for T in RISKY_SUFFIXES do
    if (Length(ATypeLow) > Length(T)) and EndsText(T, ATypeLow) then
      Exit(Format(TYPE_RISK, [AOperand, ATypeLow]));
end;

end.
