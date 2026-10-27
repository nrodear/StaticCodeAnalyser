unit uRdxCondExpr;

// reDelphix - Ausdrucks-Leser der Code-Aktionen C7/C8 (if umkehren, De
// Morgan, Vergleich drehen, if teilen/zusammenfuegen; Charge C78,
// 2026-10-27), OHNE ToolsAPI und ohne Parser (FPC-Pruefstand).
//
// LEXER: liest einen Zeichenbereich der Code-Sicht (TRdxCodeMap) - anders
// als der Token-Leser von uRdxCodeMap auch die Literale: ein String bzw.
// ein Zeichen-Literal ('a'#13'b', #$0D) ist EIN Token (Low = ''''), eine
// Zahl ($FF, 1.5e3, %101, &17, 1_000) eines. Ein Kommentar oder eine
// Direktive im Bereich setzt HasComment (die Aktionen lehnen dann ab: ein
// Kommentar ginge beim Umbau verloren, ein '//' schluckte eine Klammer);
// eine Zeile, die in einem Block-Kommentar oder mehrzeiligen String
// beginnt, beendet das Lesen (nicht lesbar).
//
// PARSER: der Vorrang von Delphi (Object Pascal Guide, "Operator
// Precedence"): not/@/Vorzeichen binden am staerksten, dann * / div mod and
// shl shr as, dann + - or xor, zuletzt = <> < > <= >= in is. Ein Vergleich
// steht darum nur als ganzer Ausdruck oder in einer Klammer. Knoten:
//   ekPrimary  Name mit Nachsaetzen (.X, (..), [..], ^), Literal, nil,
//              Mengenkonstruktor [..] (Opaque); Calls nennt jeden Namen vor
//              einer Klammer (Aufruf oder Typumwandlung, wie im Quelltext
//              geschrieben) und 'inherited'
//   ekParen    ( Ausdruck )
//   ekNot      not Faktor
//   ekUnary    @, -, + vor einem Faktor
//   ekChain    Glieder mit Operatoren EINER Vorrangstufe (Ops: die Token)
//   ekRel      Vergleich (OpTok), zwei Seiten
// Was der Leser nicht kennt - ein bedingter Ausdruck (Delphi 13: 'if' im
// Ausdruck), eine anonyme Methode, Typparameter ('TList<T>' liest er als
// Vergleich und scheitert am zweiten '>'), ':' in Argumenten -, laesst
// Parse scheitern: die Aktionen bieten dann nichts an.
//
// WURZEL AM CARET (ExprRootAt): von einem Token rueckwaerts bis zum Kopf des
// Ausdrucks - 'if' (bis 'then', nur wenn das if eine Anweisung beginnt),
// 'while' (bis 'do'), 'until' bzw. ':=' (bis ';', end, else, until,
// finally, except) -, ueber Klammern hinweg; ein ',' oder ein anderes
// Schluesselwort auf derselben Klammerebene beendet die Suche ohne Wurzel.
//
// NEGATION (NegatedTop, NegatedFactor): 'not F' -> F, ein einfacher
// Operand (ekPrimary, ekParen) X -> 'not X', sonst 'not (A)'. Ganz oben
// (if umkehren) faellt eine Klammer um F weg, und 'P = nil' wird 'P <> nil'
// (und umgekehrt) - nur mit nil: bei Gleitkomma (NaN), Mengen, Variant-Null
// und Operator-Ueberladungen ist 'not (A = B)' nicht beweisbar 'A <> B'.
// ANNAHME (wie SCA018, uRdxDeepNestingFix): 'not' wirkt logisch - fuer
// Boolean immer, fuer ByteBool/WordBool/LongBool unter FPC belegt
// (Mikroprobe Charge C78), unter Delphi Entscheidungsfrage E-C78-1.

interface

uses
  uRefactorInfo,   // TRefactorSpan
  uRdxCodeMap;     // TRdxCodeMap, TRdxToken

type
  TRdxExprTokKind = (etWord, etNumber, etString, etSymbol);

  // Ein Token des Ausdrucks; EndCol zeigt hinter das letzte Zeichen.
  TRdxExprTok = record
    Kind : TRdxExprTokKind;
    Line : Integer;
    Col  : Integer;
    EndCol : Integer;
    Low  : string;   // klein; Literal: ''''
  end;

  TRdxExprKind = (ekPrimary, ekParen, ekNot, ekUnary, ekChain, ekRel);

  // Ein Knoten; First/Last/OpTok/Ops sind Token-Indizes, Kids/Parent
  // Knoten-Indizes (-1 = keiner).
  TRdxExprNode = record
    Kind   : TRdxExprKind;
    First  : Integer;
    Last   : Integer;
    OpTok  : Integer;
    Kids   : TArray<Integer>;
    Ops    : TArray<Integer>;
    Parent : Integer;
    Calls  : TArray<string>;
    Opaque : Boolean;
  end;

  TRdxExprRootKind = (erkNone, erkIf, erkWhile, erkUntil, erkAssign);

  // Der Ausdruck, in dem ein Token steht (ExprRootAt): Kopf und Ende als
  // Code-Token, dazwischen der Zeichenbereich [From, To).
  TRdxExprRoot = record
    Kind     : TRdxExprRootKind;
    Head     : TRdxToken;
    Stop     : TRdxToken;
    FromLine : Integer;
    FromCol  : Integer;
    ToLine   : Integer;
    ToCol    : Integer;
  end;

  TRdxCondExpr = class
  private
    FMap     : TRdxCodeMap;
    FToks    : TArray<TRdxExprTok>;
    FNodes   : TArray<TRdxExprNode>;
    FPos     : Integer;
    FRoot    : Integer;
    FComment : Boolean;
    FFailed  : Boolean;
    procedure AddTok(AKind: TRdxExprTokKind; ALine, ACol, AEndCol: Integer;
      const ALow: string);
    function Lex(AFromLine, AFromCol, AToLine, AToCol: Integer): Boolean;
    function Cur: string;
    function CurKind: TRdxExprTokKind;
    function AtEnd: Boolean;
    function AddNode(AKind: TRdxExprKind; AFirst, ALast: Integer): Integer;
    procedure AddKid(ANode, AKid: Integer);
    function Fail: Integer;
    function ParseExpr: Integer;
    function ParseSimple: Integer;
    function ParseTerm: Integer;
    function ParseFactor: Integer;
    function ParsePrimary: Integer;
    function ParseList(ANode: Integer; const AClose: string): Boolean;
    procedure Postfix(ANode: Integer);
  public
    constructor Create(AMap: TRdxCodeMap);
    // Liest den Bereich [AFrom, ATo) - True, wenn er genau EIN Ausdruck ist.
    function Parse(AFromLine, AFromCol, AToLine, AToCol: Integer): Boolean;
    // Dasselbe fuer den Bereich einer Wurzel.
    function ParseRoot(const ARoot: TRdxExprRoot): Boolean;
    // Zahl der gelesenen Token.
    function TokCount: Integer;
    // Das Token AIndex (0-basiert, < TokCount).
    function Tok(AIndex: Integer): TRdxExprTok;
    // Zahl der Knoten nach Parse.
    function NodeCount: Integer;
    // Der Knoten AIndex (0-basiert, < NodeCount).
    function Node(AIndex: Integer): TRdxExprNode;
    // Der Wurzelknoten nach Parse; -1 ohne.
    property Root: Integer read FRoot;
    // Kommentar oder Direktive im gelesenen Bereich.
    property HasComment: Boolean read FComment;
    // Das Token, das (ALine, ACol) enthaelt oder direkt davor endet; -1.
    function TokenAt(ALine, ACol: Integer): Integer;
    // Der Knoten, dessen Operator ATok ist (ekChain: eines der Ops, ekRel:
    // OpTok, ekNot/ekUnary: First); -1.
    function OwnerOfOp(ATok: Integer): Integer;
    // Text des Knotens, woertlich (Zeilen mit #10).
    function Text(ANode: Integer): string;
    // Bereich des Knotens (EndCol hinter dem letzten Zeichen).
    function Span(ANode: Integer; const ARole: string): TRefactorSpan;
    // Operator des Kettenglieds AIndex (0-basiert, zwischen Kid AIndex und
    // AIndex + 1) bzw. eines ekRel ('' sonst).
    function OpOf(ANode: Integer; AIndex: Integer = 0): string;
    // ekChain, deren Operatoren alle AOp sind.
    function IsChainOf(ANode: Integer; const AOp: string): Boolean;
    // Ein einfacher Operand: ekPrimary oder ekParen.
    function IsOperand(ANode: Integer): Boolean;
    // Die Negation als FAKTOR (De Morgan): 'not F' -> F (auch in
    // Klammern: '(not F)' -> F), Operand X -> '(not X)', sonst '(not (A))'.
    function NegatedFactor(ANode: Integer): string;
    // Die Negation fuer den ganzen Ausdruck einer Bedingung (if umkehren):
    // 'not (C)' -> 'C', 'not F' -> 'F', Operand -> 'not X', 'P = nil' ->
    // 'P <> nil' (und umgekehrt), sonst 'not (A)'.
    function NegatedTop(ANode: Integer): string;
    // Der Knoten unter allen Klammern um ANode (ekParen -> sein Inhalt).
    function Unwrapped(ANode: Integer): Integer;
  end;

// Die Wurzel des Ausdrucks, in dem AAt steht (s. Kopf, WURZEL AM CARET);
// AWithAssign: auch die rechte Seite einer Zuweisung. False ohne.
function ExprRootAt(AMap: TRdxCodeMap; const AAt: TRdxToken;
  AWithAssign: Boolean; out ARoot: TRdxExprRoot): Boolean;

// Die Bedingung eines if als Bereich: von hinter AIf bis vor AThen.
function CondRootOf(const AIf, AThen: TRdxToken): TRdxExprRoot;

// Steht in der Datei eine Direktive, die die vollstaendige Auswertung
// boolescher Ausdruecke einschaltet ({$B+}, {$BOOLEVAL ON})? Die Zeile,
// sonst 0.
function CompleteBoolEvalLine(AMap: TRdxCodeMap): Integer;

implementation

uses
  System.SysUtils;   // LowerCase, Trim, CharInSet

const
  SPAN_EXPR = 'cond';
  // So weit sucht ExprRootAt rueckwaerts nach dem Kopf (Token).
  MAX_ROOT_TOKENS = 400;
  REL_OPS: array[0..5] of string = ('=', '<>', '<', '>', '<=', '>=');
  REL_WORDS: array[0..1] of string = ('in', 'is');
  ADD_OPS: array[0..3] of string = ('+', '-', 'or', 'xor');
  MUL_OPS: array[0..7] of string = ('*', '/', 'div', 'mod', 'and', 'shl',
    'shr', 'as');
  // Woerter, die keinen Operanden beginnen (der Rest ist ein Name).
  NOT_PRIMARY: array[0..40] of string = ('and', 'or', 'xor', 'not', 'div',
    'mod', 'shl', 'shr', 'in', 'is', 'as', 'if', 'then', 'else', 'while',
    'do', 'for', 'to', 'downto', 'repeat', 'until', 'case', 'of', 'begin',
    'end', 'with', 'try', 'except', 'finally', 'raise', 'var', 'const',
    'procedure', 'function', 'out', 'type', 'array', 'record', 'goto',
    'asm', 'class');
  // Ende eines Ausdrucks hinter until bzw. := (ExprRootAt).
  EXPR_STOPS: array[0..4] of string = ('end', 'else', 'until', 'finally',
    'except');
  // Schluesselwoerter, die IN einem Ausdruck stehen duerfen.
  EXPR_WORDS: array[0..12] of string = ('and', 'or', 'xor', 'not', 'div',
    'mod', 'shl', 'shr', 'in', 'is', 'as', 'nil', 'inherited');

{ Hilfen }

function InArr(const S: string; const A: array of string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(A) to High(A) do
    if A[i] = S then
      Exit(True);
end;

function IsHex(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F', '_']);
end;

{ TRdxCondExpr }

constructor TRdxCondExpr.Create(AMap: TRdxCodeMap);
begin
  inherited Create;
  FMap := AMap;
  FRoot := -1;
end;

procedure TRdxCondExpr.AddTok(AKind: TRdxExprTokKind; ALine, ACol,
  AEndCol: Integer; const ALow: string);
var
  T : TRdxExprTok;
begin
  T.Kind := AKind;
  T.Line := ALine;
  T.Col := ACol;
  T.EndCol := AEndCol;
  T.Low := ALow;
  SetLength(FToks, Length(FToks) + 1);
  FToks[High(FToks)] := T;
end;

function TRdxCondExpr.Lex(AFromLine, AFromCol, AToLine,
  AToCol: Integer): Boolean;
var
  Li, c, Last, Start : Integer;
  S                  : string;
  K                  : Char;
begin
  Result := False;
  FToks := nil;
  FComment := False;
  for Li := AFromLine to AToLine do
  begin
    // Eine Zeile in einem Block-Kommentar oder mehrzeiligen String: nicht
    // lesbar (die Klassen enden mit der Zeile, der Text nicht).
    if (Li > AFromLine) and FMap.StartsInside(Li) then
    begin
      // Keine halben Token: TokCount = 0 heisst "nicht lesbar".
      FToks := nil;
      Exit;
    end;
    S := FMap.Raw(Li);
    c := 1;
    if Li = AFromLine then
      c := AFromCol;
    Last := Length(S);
    if Li = AToLine then
      Last := AToCol - 1;
    while c <= Last do
    begin
      K := FMap.ClassAt(Li, c);
      if K = 'k' then
      begin
        FComment := True;
        Inc(c);
        Continue;
      end;
      if (K <> 's') and IsBlank(S[c]) then
      begin
        Inc(c);
        Continue;
      end;
      Start := c;
      if (K = 's') or (S[c] = '#') then
      begin
        // Ein Literal: Strings und #-Zeichen ohne Luecke.
        while c <= Last do
        begin
          if FMap.ClassAt(Li, c) = 's' then
            Inc(c)
          else if S[c] = '#' then
          begin
            Inc(c);
            if (c <= Last) and (S[c] = '$') then
            begin
              Inc(c);
              while (c <= Last) and IsHex(S[c]) do
                Inc(c);
            end
            else
              while (c <= Last) and CharInSet(S[c], ['0'..'9']) do
                Inc(c);
          end
          else
            Break;
        end;
        AddTok(etString, Li, Start, c, '''');
      end
      else if IsIdentStart(S[c])
         or ((S[c] = '&') and (c < Last) and IsIdentStart(S[c + 1])) then
      begin
        Inc(c);
        while (c <= Last) and IsIdentChar(S[c]) do
          Inc(c);
        AddTok(etWord, Li, Start, c, LowerCase(Copy(S, Start, c - Start)));
      end
      else if CharInSet(S[c], ['0'..'9'])
         or ((S[c] = '$') and (c < Last) and IsHex(S[c + 1]))
         or ((S[c] = '%') and (c < Last) and CharInSet(S[c + 1], ['0', '1']))
         or ((S[c] = '&') and (c < Last) and CharInSet(S[c + 1], ['0'..'7'])) then
      begin
        if CharInSet(S[c], ['$', '%', '&']) then
        begin
          Inc(c);
          while (c <= Last) and IsHex(S[c]) do
            Inc(c);
        end
        else
        begin
          while (c <= Last) and CharInSet(S[c], ['0'..'9', '_']) do
            Inc(c);
          if (c < Last) and (S[c] = '.') and CharInSet(S[c + 1], ['0'..'9']) then
          begin
            Inc(c);
            while (c <= Last) and CharInSet(S[c], ['0'..'9', '_']) do
              Inc(c);
          end;
          if (c <= Last) and CharInSet(S[c], ['e', 'E']) then
          begin
            Inc(c);
            if (c <= Last) and CharInSet(S[c], ['+', '-']) then
              Inc(c);
            while (c <= Last) and CharInSet(S[c], ['0'..'9']) do
              Inc(c);
          end;
        end;
        AddTok(etNumber, Li, Start, c, LowerCase(Copy(S, Start, c - Start)));
      end
      else
      begin
        if (c < Last) and ((Copy(S, c, 2) = ':=') or (Copy(S, c, 2) = '<>')
           or (Copy(S, c, 2) = '<=') or (Copy(S, c, 2) = '>=')
           or (Copy(S, c, 2) = '..')) then
          Inc(c, 2)
        else
          Inc(c);
        AddTok(etSymbol, Li, Start, c, Copy(S, Start, c - Start));
      end;
    end;
  end;
  Result := Length(FToks) > 0;
end;

function TRdxCondExpr.Cur: string;
begin
  if FPos <= High(FToks) then
    Result := FToks[FPos].Low
  else
    Result := '';
end;

function TRdxCondExpr.CurKind: TRdxExprTokKind;
begin
  if FPos <= High(FToks) then
    Result := FToks[FPos].Kind
  else
    Result := etSymbol;
end;

function TRdxCondExpr.AtEnd: Boolean;
begin
  Result := FPos > High(FToks);
end;

function TRdxCondExpr.AddNode(AKind: TRdxExprKind; AFirst,
  ALast: Integer): Integer;
var
  N : TRdxExprNode;
begin
  N := Default(TRdxExprNode);
  N.Kind := AKind;
  N.First := AFirst;
  N.Last := ALast;
  N.OpTok := -1;
  N.Parent := -1;
  SetLength(FNodes, Length(FNodes) + 1);
  FNodes[High(FNodes)] := N;
  Result := High(FNodes);
end;

procedure TRdxCondExpr.AddKid(ANode, AKid: Integer);
begin
  SetLength(FNodes[ANode].Kids, Length(FNodes[ANode].Kids) + 1);
  FNodes[ANode].Kids[High(FNodes[ANode].Kids)] := AKid;
  FNodes[AKid].Parent := ANode;
end;

function TRdxCondExpr.Fail: Integer;
begin
  FFailed := True;
  Result := -1;
end;

function TRdxCondExpr.ParseExpr: Integer;
var
  L, R, Op, N : Integer;
begin
  L := ParseSimple;
  if L < 0 then
    Exit(-1);
  if not AtEnd and (((CurKind = etSymbol) and InArr(Cur, REL_OPS))
     or ((CurKind = etWord) and InArr(Cur, REL_WORDS))) then
  begin
    Op := FPos;
    Inc(FPos);
    R := ParseSimple;
    if R < 0 then
      Exit(-1);
    N := AddNode(ekRel, FNodes[L].First, FNodes[R].Last);
    FNodes[N].OpTok := Op;
    AddKid(N, L);
    AddKid(N, R);
    Exit(N);
  end;
  Result := L;
end;

function TRdxCondExpr.ParseSimple: Integer;
var
  First, N, K : Integer;
begin
  First := ParseTerm;
  if First < 0 then
    Exit(-1);
  if AtEnd or not InArr(Cur, ADD_OPS) or (CurKind = etString) then
    Exit(First);
  N := AddNode(ekChain, FNodes[First].First, FNodes[First].Last);
  AddKid(N, First);
  while not AtEnd and InArr(Cur, ADD_OPS) and (CurKind <> etString) do
  begin
    SetLength(FNodes[N].Ops, Length(FNodes[N].Ops) + 1);
    FNodes[N].Ops[High(FNodes[N].Ops)] := FPos;
    Inc(FPos);
    K := ParseTerm;
    if K < 0 then
      Exit(-1);
    AddKid(N, K);
    FNodes[N].Last := FNodes[K].Last;
  end;
  Result := N;
end;

function TRdxCondExpr.ParseTerm: Integer;
var
  First, N, K : Integer;
begin
  First := ParseFactor;
  if First < 0 then
    Exit(-1);
  if AtEnd or not InArr(Cur, MUL_OPS) or (CurKind = etString) then
    Exit(First);
  N := AddNode(ekChain, FNodes[First].First, FNodes[First].Last);
  AddKid(N, First);
  while not AtEnd and InArr(Cur, MUL_OPS) and (CurKind <> etString) do
  begin
    SetLength(FNodes[N].Ops, Length(FNodes[N].Ops) + 1);
    FNodes[N].Ops[High(FNodes[N].Ops)] := FPos;
    Inc(FPos);
    K := ParseFactor;
    if K < 0 then
      Exit(-1);
    AddKid(N, K);
    FNodes[N].Last := FNodes[K].Last;
  end;
  Result := N;
end;

function TRdxCondExpr.ParseFactor: Integer;
var
  Op, K, N : Integer;
  Kind     : TRdxExprKind;
begin
  if AtEnd then
    Exit(Fail);
  if ((CurKind = etWord) and (Cur = 'not'))
     or ((CurKind = etSymbol) and ((Cur = '@') or (Cur = '-') or (Cur = '+'))) then
  begin
    Op := FPos;
    if Cur = 'not' then
      Kind := ekNot
    else
      Kind := ekUnary;
    Inc(FPos);
    K := ParseFactor;
    if K < 0 then
      Exit(-1);
    N := AddNode(Kind, Op, FNodes[K].Last);
    FNodes[N].OpTok := Op;
    AddKid(N, K);
    Exit(N);
  end;
  Result := ParsePrimary;
end;

// Liest Ausdruecke, getrennt durch ',', bis AClose; jeder wird Kind von
// ANode. FPos steht danach hinter AClose.
function TRdxCondExpr.ParseList(ANode: Integer; const AClose: string): Boolean;
var
  K : Integer;
begin
  Result := False;
  if Cur = AClose then
  begin
    FNodes[ANode].Last := FPos;
    Inc(FPos);
    Exit(True);
  end;
  repeat
    K := ParseExpr;
    if K < 0 then
      Exit;
    AddKid(ANode, K);
    if Cur = ',' then
      Inc(FPos)
    else
      Break;
  until AtEnd;
  if AtEnd or (Cur <> AClose) or (CurKind <> etSymbol) then
    Exit;
  FNodes[ANode].Last := FPos;
  Inc(FPos);
  Result := True;
end;

// Nachsaetze eines Operanden: .Name, (Argumente), [Indizes], ^.
procedure TRdxCondExpr.Postfix(ANode: Integer);
var
  Name : string;
begin
  while not AtEnd and not FFailed and (CurKind = etSymbol) do
  begin
    if Cur = '.' then
    begin
      Inc(FPos);
      if AtEnd or (CurKind <> etWord) then
      begin
        Fail;
        Exit;
      end;
      FNodes[ANode].Last := FPos;
      Inc(FPos);
    end
    else if Cur = '(' then
    begin
      Name := '?';
      if FToks[FPos - 1].Kind = etWord then
        Name := Copy(FMap.Raw(FToks[FPos - 1].Line), FToks[FPos - 1].Col,
          FToks[FPos - 1].EndCol - FToks[FPos - 1].Col);
      SetLength(FNodes[ANode].Calls, Length(FNodes[ANode].Calls) + 1);
      FNodes[ANode].Calls[High(FNodes[ANode].Calls)] := Name;
      Inc(FPos);
      if not ParseList(ANode, ')') then
      begin
        Fail;
        Exit;
      end;
    end
    else if Cur = '[' then
    begin
      Inc(FPos);
      if not ParseList(ANode, ']') then
      begin
        Fail;
        Exit;
      end;
    end
    else if Cur = '^' then
    begin
      FNodes[ANode].Last := FPos;
      Inc(FPos);
    end
    else
      Break;
  end;
end;

function TRdxCondExpr.ParsePrimary: Integer;
var
  N, K : Integer;
begin
  if AtEnd then
    Exit(Fail);
  case CurKind of
    etString, etNumber:
      begin
        N := AddNode(ekPrimary, FPos, FPos);
        Inc(FPos);
        Postfix(N);
      end;
    etWord:
      begin
        if InArr(Cur, NOT_PRIMARY) then
          Exit(Fail);
        N := AddNode(ekPrimary, FPos, FPos);
        if Cur = 'inherited' then
        begin
          SetLength(FNodes[N].Calls, 1);
          FNodes[N].Calls[0] := 'inherited';
          Inc(FPos);
          if not AtEnd and (CurKind = etWord) and not InArr(Cur, NOT_PRIMARY) then
          begin
            FNodes[N].Last := FPos;
            Inc(FPos);
          end;
        end
        else
          Inc(FPos);
        Postfix(N);
      end;
  else
    if Cur = '(' then
    begin
      N := AddNode(ekParen, FPos, FPos);
      Inc(FPos);
      K := ParseExpr;
      if (K < 0) or AtEnd or (Cur <> ')') then
        Exit(Fail);
      AddKid(N, K);
      FNodes[N].Last := FPos;
      Inc(FPos);
      Postfix(N);
    end
    else if Cur = '[' then
    begin
      // Mengenkonstruktor: die Glieder ('..' trennt nur Bereiche) - als
      // Ganzes ein Operand.
      N := AddNode(ekPrimary, FPos, FPos);
      FNodes[N].Opaque := True;
      Inc(FPos);
      while not AtEnd and (Cur <> ']') do
      begin
        K := ParseExpr;
        if K < 0 then
          Exit(-1);
        AddKid(N, K);
        if (Cur = ',') or (Cur = '..') then
          Inc(FPos)
        else
          Break;
      end;
      if AtEnd or (Cur <> ']') then
        Exit(Fail);
      FNodes[N].Last := FPos;
      Inc(FPos);
    end
    else
      Exit(Fail);
  end;
  if FFailed then
    Exit(-1);
  Result := N;
end;

function TRdxCondExpr.Parse(AFromLine, AFromCol, AToLine,
  AToCol: Integer): Boolean;
begin
  FNodes := nil;
  FRoot := -1;
  FPos := 0;
  FFailed := False;
  Result := False;
  if not Lex(AFromLine, AFromCol, AToLine, AToCol) then
    Exit;
  FRoot := ParseExpr;
  if FFailed or (FRoot < 0) or not AtEnd then
  begin
    FRoot := -1;
    Exit;
  end;
  Result := True;
end;

function TRdxCondExpr.ParseRoot(const ARoot: TRdxExprRoot): Boolean;
begin
  Result := Parse(ARoot.FromLine, ARoot.FromCol, ARoot.ToLine, ARoot.ToCol);
end;

function TRdxCondExpr.TokCount: Integer;
begin
  Result := Length(FToks);
end;

function TRdxCondExpr.Tok(AIndex: Integer): TRdxExprTok;
begin
  Result := FToks[AIndex];
end;

function TRdxCondExpr.NodeCount: Integer;
begin
  Result := Length(FNodes);
end;

function TRdxCondExpr.Node(AIndex: Integer): TRdxExprNode;
begin
  Result := FNodes[AIndex];
end;

function TRdxCondExpr.TokenAt(ALine, ACol: Integer): Integer;
var
  i : Integer;
begin
  // Erst das Token, das die Spalte enthaelt, dann eines, das direkt davor
  // endet (Caret hinter einem Wort).
  for i := 0 to High(FToks) do
    if (FToks[i].Line = ALine) and (FToks[i].Col <= ACol)
       and (ACol < FToks[i].EndCol) then
      Exit(i);
  for i := 0 to High(FToks) do
    if (FToks[i].Line = ALine) and (FToks[i].EndCol = ACol) then
      Exit(i);
  Result := -1;
end;

function TRdxCondExpr.OwnerOfOp(ATok: Integer): Integer;
var
  i, j : Integer;
begin
  for i := 0 to High(FNodes) do
  begin
    case FNodes[i].Kind of
      ekRel, ekNot, ekUnary:
        if FNodes[i].OpTok = ATok then
          Exit(i);
      ekChain:
        for j := 0 to High(FNodes[i].Ops) do
          if FNodes[i].Ops[j] = ATok then
            Exit(i);
    else
      ;   // ekPrimary/ekParen tragen keinen Operator
    end;
  end;
  Result := -1;
end;

function TRdxCondExpr.Span(ANode: Integer; const ARole: string): TRefactorSpan;
var
  F, L : TRdxExprTok;
begin
  F := FToks[FNodes[ANode].First];
  L := FToks[FNodes[ANode].Last];
  Result := TRefactorSpan.Make(ARole, F.Line, F.Col, L.Line, L.EndCol);
end;

function TRdxCondExpr.Text(ANode: Integer): string;
begin
  Result := RangeText(FMap, Span(ANode, SPAN_EXPR));
end;

function TRdxCondExpr.OpOf(ANode: Integer; AIndex: Integer): string;
begin
  Result := '';
  case FNodes[ANode].Kind of
    ekRel:
      Result := FToks[FNodes[ANode].OpTok].Low;
    ekChain:
      if (AIndex >= 0) and (AIndex <= High(FNodes[ANode].Ops)) then
        Result := FToks[FNodes[ANode].Ops[AIndex]].Low;
  else
    ;   // die anderen Arten: kein Operator, Result bleibt ''
  end;
end;

function TRdxCondExpr.IsChainOf(ANode: Integer; const AOp: string): Boolean;
var
  i : Integer;
begin
  Result := (ANode >= 0) and (FNodes[ANode].Kind = ekChain);
  if not Result then
    Exit;
  for i := 0 to High(FNodes[ANode].Ops) do
    if FToks[FNodes[ANode].Ops[i]].Low <> AOp then
      Exit(False);
end;

function TRdxCondExpr.IsOperand(ANode: Integer): Boolean;
begin
  Result := FNodes[ANode].Kind in [ekPrimary, ekParen];
end;

function TRdxCondExpr.Unwrapped(ANode: Integer): Integer;
begin
  Result := ANode;
  while FNodes[Result].Kind = ekParen do
    Result := FNodes[Result].Kids[0];
end;

function TRdxCondExpr.NegatedFactor(ANode: Integer): string;
var
  U : Integer;
begin
  // '(not A)' wird 'A': durch die Klammern hindurch.
  U := Unwrapped(ANode);
  if FNodes[U].Kind = ekNot then
    Result := Text(FNodes[U].Kids[0])
  else if IsOperand(ANode) then
    Result := '(not ' + Text(ANode) + ')'
  else
    Result := '(not (' + Text(ANode) + '))';
end;

// Ein einzelnes Token 'nil'?
function IsNil(AExpr: TRdxCondExpr; ANode: Integer): Boolean;
var
  N : TRdxExprNode;
begin
  N := AExpr.Node(ANode);
  Result := (N.Kind = ekPrimary) and (N.First = N.Last)
    and (AExpr.Tok(N.First).Low = 'nil');
end;

function TRdxCondExpr.NegatedTop(ANode: Integer): string;
var
  N    : TRdxExprNode;
  L, R : Integer;
  Op   : string;
begin
  N := FNodes[ANode];
  case N.Kind of
    ekNot:
      Exit(Text(Unwrapped(N.Kids[0])));
    ekPrimary, ekParen:
      Exit('not ' + Text(ANode));
    ekRel:
      begin
        L := N.Kids[0];
        R := N.Kids[1];
        Op := FToks[N.OpTok].Low;
        if ((Op = '=') or (Op = '<>'))
           and ((IsNil(Self, L) and IsOperand(R))
             or (IsNil(Self, R) and IsOperand(L))) then
        begin
          if Op = '=' then
            Op := '<>'
          else
            Op := '=';
          Exit(Text(L) + ' ' + Op + ' ' + Text(R));
        end;
      end;
  else
    ;   // ekChain/ekUnary: geklammert verneint, s. u.
  end;
  Result := 'not (' + Text(ANode) + ')';
end;

{ Wurzel am Caret }

function CondRootOf(const AIf, AThen: TRdxToken): TRdxExprRoot;
begin
  Result := Default(TRdxExprRoot);
  Result.Kind := erkIf;
  Result.Head := AIf;
  Result.Stop := AThen;
  Result.FromLine := AIf.Line;
  Result.FromCol := AIf.EndCol;
  Result.ToLine := AThen.Line;
  Result.ToCol := AThen.Col;
end;

// Ist T ein Schluesselwort, das in einem Ausdruck nicht stehen kann?
function IsBoundary(const T, P: TRdxToken): Boolean;
begin
  Result := IsKeywordAfter(T, P) and InList(T.Low, RESERVED)
    and not InArr(T.Low, EXPR_WORDS);
end;

function ExprRootAt(AMap: TRdxCodeMap; const AAt: TRdxToken;
  AWithAssign: Boolean; out ARoot: TRdxExprRoot): Boolean;
var
  T, P, H : TRdxToken;
  Depth, n : Integer;
  Want     : string;
begin
  Result := False;
  ARoot := Default(TRdxExprRoot);
  // Rueckwaerts zum Kopf.
  Depth := 0;
  H := Default(TRdxToken);
  T := Before(AMap, AAt);
  n := 0;
  while (T.Low <> '') and (n < MAX_ROOT_TOKENS) do
  begin
    Inc(n);
    P := Before(AMap, T);
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      Dec(Depth);
      if Depth < 0 then
        Depth := 0;   // eine Klammer um AAt: weiter aussen suchen
    end
    else if Depth = 0 then
    begin
      if IsKeywordAfter(T, P)
         and ((T.Low = 'if') or (T.Low = 'while') or (T.Low = 'until')) then
      begin
        H := T;
        Break;
      end;
      if T.Low = ':=' then
      begin
        if AWithAssign then
          H := T;
        Break;
      end;
      if (T.Low = ';') or (T.Low = ',') or (T.Low = ':')
         or IsBoundary(T, P) then
        Break;
    end;
    T := P;
  end;
  if H.Low = '' then
    Exit;
  if H.Low = 'if' then
  begin
    ARoot.Kind := erkIf;
    Want := 'then';
    // Ein if, das keine Anweisung beginnt, ist ein bedingter Ausdruck.
    if not StartsStatement(AMap, H) then
      Exit;
  end
  else if H.Low = 'while' then
  begin
    ARoot.Kind := erkWhile;
    Want := 'do';
  end
  else if H.Low = 'until' then
  begin
    ARoot.Kind := erkUntil;
    Want := '';
  end
  else
  begin
    ARoot.Kind := erkAssign;
    Want := '';
  end;
  // Vorwaerts zum Ende; AAt muss davor liegen.
  Depth := 0;
  P := H;
  T := After(AMap, H);
  n := 0;
  while (T.Low <> '') and (n < MAX_ROOT_TOKENS) do
  begin
    Inc(n);
    if (T.Low = '(') or (T.Low = '[') then
      Inc(Depth)
    else if (T.Low = ')') or (T.Low = ']') then
    begin
      Dec(Depth);
      if Depth < 0 then
        Exit;
    end
    else if Depth = 0 then
    begin
      if Want <> '' then
      begin
        if IsKeywordAfter(T, P) and (T.Low = Want) then
          Break;
        if (T.Low = ';') or IsBoundary(T, P) then
          Exit;
      end
      else
      begin
        if (T.Low = ';')
           or (IsKeywordAfter(T, P) and InArr(T.Low, EXPR_STOPS)) then
          Break;
        if IsBoundary(T, P) then
          Exit;
      end;
    end;
    P := T;
    T := After(AMap, T);
  end;
  if (T.Low = '') or (n >= MAX_ROOT_TOKENS) or not TokBefore(AAt, T) then
    Exit;
  ARoot.Head := H;
  ARoot.Stop := T;
  ARoot.FromLine := H.Line;
  ARoot.FromCol := H.EndCol;
  ARoot.ToLine := T.Line;
  ARoot.ToCol := T.Col;
  Result := True;
end;

function CompleteBoolEvalLine(AMap: TRdxCodeMap): Integer;
var
  Li, c : Integer;
  S, U  : string;
begin
  Result := 0;
  for Li := 1 to AMap.LineCount do
  begin
    S := AMap.Raw(Li);
    if Pos('{$', S) = 0 then
      Continue;
    U := UpperCase(S);
    for c := 1 to Length(S) - 1 do
      if (S[c] = '{') and (S[c + 1] = '$') and AMap.DirectiveStartsAt(Li, c) then
      begin
        // {$B+}, {$B+,R-}, {$R-,B+}, {$BOOLEVAL ON}
        if (Pos('$B+', U) > 0) or (Pos(',B+', U) > 0)
           or (Pos('BOOLEVAL ON', U) > 0) then
          Exit(Li);
      end;
  end;
end;

end.
