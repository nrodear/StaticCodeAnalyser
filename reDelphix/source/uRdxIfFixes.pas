unit uRdxIfFixes;

// reDelphix - Code-Aktionen ohne Fund an einer if-Anweisung (Charge C78,
// Wettbewerbs-Todo 2026-10-23 C7/C8), OHNE ToolsAPI und ohne Parser
// (FPC-Pruefstand):
//   InvertIf  C7 "if umkehren":   if A then X else Y  ->  if not A then Y else X
//   SplitIf   C8 "if teilen":     if A and B then X   ->  if A then
//                                                           if B then X
//   MergeIf   C8 "if zusammenfuegen": die Gegenrichtung, auch mit
//             'begin if B then X; end' als einzigem then-Zweig.
// Die Waechter-Klausel (C7) steht bei SCA018 (uRdxDeepNestingFix.GuardAt),
// De Morgan und Vergleich drehen in uRdxCondFixes.
//
// DER ANWEISUNGS-LESER (ReadIf/ReadStmt): ab dem if Token fuer Token -
// Bedingung bis 'then' (Klammern ueberspringend), then-Zweig, ein 'else'
// dahinter gehoert diesem if (das innere if eines Zweigs hat es dann schon
// genommen: dangling else, Object Pascal Guide). Zweige: begin/case/try ..
// end (end-Bilanz BlockEnd), if, while/for/with .. do, repeat .. until,
// einfache Anweisung bis ';', end, else, until, finally, except auf
// Klammertiefe 0. OpenTail: der Zweig endet auf ein if ohne else (auch
// hinter do) - ein else dahinter gehoerte diesem if. Was der Leser nicht
// sicher liest - eine anonyme Methode, ein bedingter Ausdruck (Delphi 13),
// asm, eine Marke 'L:', eine Klammer, die nicht schliesst -, ist kein
// Kandidat (InvertIf, MergeIf) bzw. ein Grund (SplitIf: dort steht der
// Kandidat schon an der Bedingung fest).
//
// WANN EIN EINTRAG ENTSTEHT (Vertrag der Code-Aktionen, uRdxContextRunner):
// das Ergebnis False mit leerem AReason heisst "kein Kandidat" (kein
// Eintrag), False mit Grund "gesperrt" (ausgegraut), True "freigegeben".
//   InvertIf: Caret auf 'if' oder 'then' eines if, das eine Anweisung
//             beginnt und ein else hat.
//   SplitIf:  Caret auf einem 'and' der obersten Ebene der Bedingung eines
//             if (die Bedingung ist eine reine and-Kette).
//   MergeIf:  Caret auf 'if' oder 'then' des aeusseren if, dessen then-Zweig
//             ein if ist (direkt oder allein in begin..end).
//
// GLEICHE BEDEUTUNG:
//   InvertIf  die Bedingung laeuft wie vorher genau einmal, verneint
//             (uRdxCondExpr.NegatedTop: Vorrang voll geklammert - 'not'
//             bindet staerker als jeder Vergleich und als and/or); die
//             Zweige tauschen woertlich, mit ihren Kommentaren.
//   SplitIf / MergeIf  unter {$B-} (Vorgabe von Delphi) wertet 'A and B'
//             B nur aus, wenn A wahr ist - genau wie die Verschachtelung.
//             Unter {$B+}/{$BOOLEVAL ON} liefe B immer: gesperrt, wenn die
//             Datei den Schalter traegt (die Projektoption sieht die Hilfe
//             nicht - Entscheidungsfrage E-C78-4).
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - eine Direktive in der if-Anweisung (bedingte Kompilierung),
//   - ein Kommentar in der Bedingung (umgebaute Bedingungen verloeren ihn,
//     ein '//' schluckte die neue Klammer),
//   - InvertIf: ein leerer Zweig; der else-Zweig ist selbst ein if
//     (else-if-Kette) oder endet auf ein if ohne else - nach dem Tausch
//     nahme dieses if das neue else (dangling else),
//   - SplitIf: das if hat ein else (es muesste doppelt stehen),
//   - MergeIf: das aeussere oder das innere if hat ein else; ein Kommentar
//     zwischen den Koepfen oder um begin/end; end nicht als erstes auf
//     seiner Zeile hinter der letzten Zeile des inneren if,
//   - SplitIf/MergeIf: {$B+}; eine Zeile, die beim Ein- bzw. Ausruecken in
//     einem Block-Kommentar oder mehrzeiligen String beginnt.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap, TRdxToken

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_IF_DIRECTIVE = 'compiler directive in the if statement - conditional '
    + 'code could change its branches';
  R_IF_COND_COMMENT = 'comment in the condition - it would be lost or '
    + 'swallow the new parenthesis';
  R_IF_COND_UNREADABLE = 'the condition is not readable (multi-line string '
    + 'or comment)';
  R_IF_EMPTY_BRANCH = 'empty then or else branch';
  R_IF_ELSE_IF = 'the else branch is another if (else-if chain) - after '
    + 'the swap it would take the new else';
  R_IF_DANGLING = 'the else branch ends with an if without else - after '
    + 'the swap that if would take the new else';
  R_IF_UNREADABLE = 'the if statement is not safe to read (anonymous '
    + 'method, conditional expression, asm or label in it)';
  R_IF_SPLIT_ELSE = 'the if has an else - it would have to stand twice';
  R_IF_BOOLEVAL = 'complete boolean evaluation is switched on (line %d) - '
    + 'with it "A and B" always evaluates B';
  R_IF_INSIDE = 'line %d starts inside a block comment or multi-line '
    + 'string - indenting it would change it';
  R_IF_MERGE_OUTER_ELSE = 'the outer if has an else';
  R_IF_MERGE_INNER_ELSE = 'the inner if has an else';
  R_IF_MERGE_COMMENT = 'comment between the two if heads or around '
    + 'begin/end - it would be lost';
  R_IF_MERGE_LAYOUT = 'the end of the block does not stand first on its '
    + 'own line';

type
  TRdxStmtKind = (skEmpty, skSimple, skIf, skBlock, skLoop, skOther);

  // Eine Anweisung (ReadStmt): erstes Token, das Token dahinter und ihr
  // letztes Zeichen (Code oder String, Kommentare ausgelassen).
  TRdxStmt = record
    Kind     : TRdxStmtKind;
    First    : TRdxToken;   // Low = '' bei skEmpty
    Next     : TRdxToken;   // ';', else, end ... hinter der Anweisung
    EndLine  : Integer;
    EndCol   : Integer;     // hinter dem letzten Zeichen
    OpenTail : Boolean;     // endet auf ein if ohne else (auch hinter do)
  end;

  // Eine if-Anweisung (ReadIf); ElseTok.Low = '' ohne else.
  TRdxIfShape = record
    IfTok    : TRdxToken;
    ThenTok  : TRdxToken;
    ElseTok  : TRdxToken;
    ThenStmt : TRdxStmt;
    ElseStmt : TRdxStmt;
    Next     : TRdxToken;   // hinter der ganzen Anweisung
    EndLine  : Integer;     // letztes Zeichen der ganzen Anweisung
    EndCol   : Integer;
  end;

  TRdxIfFixes = class
  public
    // Das if am Caret: das Token an (ALine, ACol) ist 'if' oder 'then'
    // eines if, das eine Anweisung beginnt (kein bedingter Ausdruck).
    class function IfAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out AIf: TRdxToken): Boolean; static;
    // Die if-Anweisung ab AIf; '' oder der Grund (nicht lesbar).
    class function ReadIf(AMap: TRdxCodeMap; const AIf: TRdxToken;
      out AShape: TRdxIfShape): string; static;
    // C7 if umkehren (s. Kopf); AEdits: Bedingung, then- und else-Zweig.
    class function InvertIf(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out AEdits: TArray<TRdxEdit>; out AReason: string): Boolean; static;
    // C8 if am 'and' am Caret teilen.
    class function SplitIf(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out AEdit: TRdxEdit; out AReason: string): Boolean; static;
    // C8 das if am Caret mit dem inneren if zusammenfuegen.
    class function MergeIf(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out AEdit: TRdxEdit; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,  // Format
  uRefactorInfo,    // TRefactorSpan
  uRdxCondExpr,     // TRdxCondExpr, CondRootOf, ExprRootAt, CompleteBoolEvalLine
  uRdxText;         // _(): in die reDelphix-Sprache

const
  SPAN_IF = 'ctxif';
  // Tiefe der geschachtelten Anweisungen, die der Leser verfolgt.
  MAX_NEST = 64;
  // Ende einer Anweisung (als Schluesselwort, auf Klammertiefe 0).
  STMT_STOPS: array[0..4] of string = ('end', 'else', 'until', 'finally',
    'except');
  // In einer einfachen Anweisung bzw. einer Bedingung nicht lesbar
  // (anonyme Methode, bedingter Ausdruck, Strukturwoerter).
  STMT_BAN: array[0..17] of string = ('begin', 'case', 'try', 'if', 'then',
    'else', 'do', 'of', 'procedure', 'function', 'asm', 'repeat', 'while',
    'for', 'with', 'record', 'until', 'end');
  // Kopf bis 'do', dahinter eine Anweisung (Schleife bzw. with).
  LOOP_HEADS: array[0..2] of string = ('while', 'for', 'with');

function SpanOf(ALine1, ACol1, ALine2, ACol2: Integer): TRefactorSpan;
begin
  Result := TRefactorSpan.Make(SPAN_IF, ALine1, ACol1, ALine2, ACol2);
end;

function IsStop(const T, P: TRdxToken): Boolean;
begin
  Result := (T.Low = '') or (T.Low = ';')
    or (IsKeywordAfter(T, P) and InList(T.Low, STMT_STOPS));
end;

// Setzt Next und das letzte Zeichen vor Next. '' oder der Grund.
function Finish(AMap: TRdxCodeMap; const ANext: TRdxToken;
  var S: TRdxStmt): string;
var
  L, C : Integer;
begin
  Result := '';
  S.Next := ANext;
  if (ANext.Low = '') or not LastCharBefore(AMap, ANext, L, C) then
    Exit(_(R_IF_UNREADABLE));
  S.EndLine := L;
  S.EndCol := C + 1;
end;

function ReadStmt(AMap: TRdxCodeMap; const AFirst, APrev: TRdxToken;
  ADepth: Integer; out S: TRdxStmt): string; forward;

// Die if-Anweisung ab AIf (s. Kopf). '' oder der Grund.
function ReadIfFrom(AMap: TRdxCodeMap; const AIf: TRdxToken; ADepth: Integer;
  out AShape: TRdxIfShape): string;
var
  T, P, N : TRdxToken;
  Paren   : Integer;
  L, C    : Integer;
begin
  AShape := Default(TRdxIfShape);
  AShape.IfTok := AIf;
  // Bedingung bis 'then'.
  Paren := 0;
  P := AIf;
  T := After(AMap, AIf);
  while True do
  begin
    if (T.Low = '') or (T.Low = ';') then
      Exit(_(R_IF_UNREADABLE));
    if (Paren = 0) and IsKeywordAfter(T, P) and (T.Low = 'then') then
      Break;
    if IsKeywordAfter(T, P) and InList(T.Low, STMT_BAN) then
      Exit(_(R_IF_UNREADABLE));
    Inc(Paren, ParenDelta(T));
    if Paren < 0 then
      Exit(_(R_IF_UNREADABLE));
    P := T;
    T := After(AMap, T);
  end;
  if SameTok(P, AIf) then
    Exit(_(R_IF_UNREADABLE));   // keine Bedingung
  AShape.ThenTok := T;
  Result := ReadStmt(AMap, After(AMap, T), T, ADepth + 1, AShape.ThenStmt);
  if Result <> '' then
    Exit;
  N := AShape.ThenStmt.Next;
  if IsKeywordAfter(N, Before(AMap, N)) and (N.Low = 'else') then
  begin
    AShape.ElseTok := N;
    Result := ReadStmt(AMap, After(AMap, N), N, ADepth + 1, AShape.ElseStmt);
    if Result <> '' then
      Exit;
    AShape.Next := AShape.ElseStmt.Next;
  end
  else
    AShape.Next := N;
  // Das letzte Zeichen der ganzen Anweisung (ein leerer Zweig hat keines).
  if (AShape.Next.Low = '') or not LastCharBefore(AMap, AShape.Next, L, C) then
    Exit(_(R_IF_UNREADABLE));
  AShape.EndLine := L;
  AShape.EndCol := C + 1;
end;

function ReadStmt(AMap: TRdxCodeMap; const AFirst, APrev: TRdxToken;
  ADepth: Integer; out S: TRdxStmt): string;
var
  T, P, E, L, X : TRdxToken;
  Paren, Depth  : Integer;
  Sh            : TRdxIfShape;
  Body          : TRdxStmt;
  Keep          : TRdxToken;
begin
  S := Default(TRdxStmt);
  Result := '';
  if ADepth > MAX_NEST then
    Exit(_(R_IF_UNREADABLE));
  if IsStop(AFirst, APrev) then
  begin
    S.Kind := skEmpty;
    S.Next := AFirst;
    Exit;
  end;
  S.First := AFirst;
  T := AFirst;
  P := APrev;
  if IsKeywordAfter(T, P) then
  begin
    if (T.Low = 'begin') or (T.Low = 'case') or (T.Low = 'try') then
    begin
      BlockEnd(AMap, T, nil, E, L);
      if E.Low = '' then
        Exit(_(R_IF_UNREADABLE));
      if T.Low = 'begin' then
        S.Kind := skBlock
      else
        S.Kind := skOther;
      Exit(Finish(AMap, After(AMap, E), S));
    end;
    if T.Low = 'if' then
    begin
      Result := ReadIfFrom(AMap, T, ADepth, Sh);
      if Result <> '' then
        Exit;
      S.Kind := skIf;
      S.OpenTail := (Sh.ElseTok.Low = '') or Sh.ElseStmt.OpenTail;
      Exit(Finish(AMap, Sh.Next, S));
    end;
    if InList(T.Low, LOOP_HEADS) then
    begin
      Paren := 0;
      P := T;
      X := After(AMap, T);
      while True do
      begin
        if (X.Low = '') or (X.Low = ';') then
          Exit(_(R_IF_UNREADABLE));
        if (Paren = 0) and IsKeywordAfter(X, P) and (X.Low = 'do') then
          Break;
        if IsKeywordAfter(X, P) and InList(X.Low, STMT_BAN) then
          Exit(_(R_IF_UNREADABLE));
        Inc(Paren, ParenDelta(X));
        P := X;
        X := After(AMap, X);
      end;
      Result := ReadStmt(AMap, After(AMap, X), X, ADepth + 1, Body);
      if Result <> '' then
        Exit;
      S.Kind := skLoop;
      S.OpenTail := Body.OpenTail;
      Exit(Finish(AMap, Body.Next, S));
    end;
    if T.Low = 'repeat' then
    begin
      // Bis zum until derselben Ebene, dann der Ausdruck bis zum Ende.
      Depth := 0;
      P := T;
      X := After(AMap, T);
      while True do
      begin
        if X.Low = '' then
          Exit(_(R_IF_UNREADABLE));
        if IsKeywordAfter(X, P) then
        begin
          if IsEndOpener(X.Low) or (X.Low = 'repeat') then
            Inc(Depth)
          else if X.Low = 'end' then
            Dec(Depth)
          else if X.Low = 'until' then
          begin
            if Depth = 0 then
              Break;
            Dec(Depth);
          end;
        end;
        P := X;
        X := After(AMap, X);
      end;
      Paren := 0;
      P := X;
      X := After(AMap, X);
      while not ((Paren = 0) and IsStop(X, P)) do
      begin
        if X.Low = '' then
          Exit(_(R_IF_UNREADABLE));
        if IsKeywordAfter(X, P) and InList(X.Low, STMT_BAN) then
          Exit(_(R_IF_UNREADABLE));
        Inc(Paren, ParenDelta(X));
        if Paren < 0 then
          Exit(_(R_IF_UNREADABLE));
        P := X;
        X := After(AMap, X);
      end;
      S.Kind := skOther;
      Exit(Finish(AMap, X, S));
    end;
  end;
  // Eine Marke 'L: ...' liest der Leser nicht.
  if T.IsWord and (After(AMap, T).Low = ':') then
    Exit(_(R_IF_UNREADABLE));
  // Einfache Anweisung.
  Paren := 0;
  Keep := T;
  while not ((Paren = 0) and IsStop(T, P)) do
  begin
    if T.Low = '' then
      Exit(_(R_IF_UNREADABLE));
    if IsKeywordAfter(T, P) and InList(T.Low, STMT_BAN) then
      Exit(_(R_IF_UNREADABLE));
    Inc(Paren, ParenDelta(T));
    if Paren < 0 then
      Exit(_(R_IF_UNREADABLE));
    P := T;
    T := After(AMap, T);
  end;
  if SameTok(T, Keep) then
    Exit(_(R_IF_UNREADABLE));
  S.Kind := skSimple;
  Result := Finish(AMap, T, S);
end;

{ TRdxIfFixes }

class function TRdxIfFixes.IfAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AIf: TRdxToken): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  AIf := Default(TRdxToken);
  T := TokenContaining(AMap, ALine, ACol);
  if not IsKeywordAfter(T, Before(AMap, T)) then
    Exit;
  if T.Low = 'if' then
    AIf := T
  else if T.Low = 'then' then
  begin
    if FindOwner(AMap, T, IF_OWNERS, AIf) <> '' then
      Exit;
  end
  else
    Exit;
  Result := (AIf.Low = 'if') and StartsStatement(AMap, AIf);
end;

class function TRdxIfFixes.ReadIf(AMap: TRdxCodeMap; const AIf: TRdxToken;
  out AShape: TRdxIfShape): string;
begin
  Result := ReadIfFrom(AMap, AIf, 0, AShape);
end;

// Text des Bereichs (Zeilen mit #10).
function TextOf(AMap: TRdxCodeMap; ALine1, ACol1, ALine2,
  ACol2: Integer): string;
begin
  Result := RangeText(AMap, SpanOf(ALine1, ACol1, ALine2, ACol2));
end;

// Der Bereich einer nicht leeren Anweisung.
function StmtSpan(const S: TRdxStmt): TRefactorSpan;
begin
  Result := SpanOf(S.First.Line, S.First.Col, S.EndLine, S.EndCol);
end;

function MakeEdit(AMap: TRdxCodeMap; const ASpan: TRefactorSpan;
  const ANewText: string): TRdxEdit;
begin
  Result := Default(TRdxEdit);
  Result.Span := ASpan;
  Result.Expected := RangeText(AMap, ASpan);
  Result.NewText := ANewText;
end;

// Kommentar oder Direktive in der Bedingung des if (zwischen if und then)?
function CondComment(AMap: TRdxCodeMap; const AIf, AThen: TRdxToken): Boolean;
begin
  Result := CommentInRange(AMap, SpanOf(AIf.Line, AIf.EndCol, AThen.Line,
    AThen.Col));
end;

// Eine Direktive von hinter AIf bis zum Ende der Anweisung?
function DirectiveIn(AMap: TRdxCodeMap; const AShape: TRdxIfShape): Boolean;
begin
  Result := DirectiveBetween(AMap, AShape.IfTok, AShape.EndLine,
    AShape.EndCol);
end;

class function TRdxIfFixes.InvertIf(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AEdits: TArray<TRdxEdit>; out AReason: string): Boolean;
var
  IfTok        : TRdxToken;
  Sh           : TRdxIfShape;
  Expr         : TRdxCondExpr;
  Neg          : string;
  F, L         : TRdxExprTok;
  ThenText     : string;
  ElseText     : string;
begin
  Result := False;
  AEdits := nil;
  AReason := '';
  // Kein Kandidat: kein if am Caret, nicht lesbar, ohne else.
  if not IfAt(AMap, ALine, ACol, IfTok) then
    Exit;
  if (ReadIf(AMap, IfTok, Sh) <> '') or (Sh.ElseTok.Low = '') then
    Exit;
  if DirectiveIn(AMap, Sh) then
    AReason := _(R_IF_DIRECTIVE)
  else if CondComment(AMap, Sh.IfTok, Sh.ThenTok) then
    AReason := _(R_IF_COND_COMMENT)
  else if (Sh.ThenStmt.Kind = skEmpty) or (Sh.ElseStmt.Kind = skEmpty) then
    AReason := _(R_IF_EMPTY_BRANCH)
  else if Sh.ElseStmt.Kind = skIf then
    AReason := _(R_IF_ELSE_IF)
  else if Sh.ElseStmt.OpenTail then
    AReason := _(R_IF_DANGLING);
  if AReason <> '' then
    Exit;
  Expr := TRdxCondExpr.Create(AMap);
  try
    // Ein Ausdruck, den der Leser nicht kennt, bleibt als Ganzes:
    // 'not (...)' ist fuer jede Bedingung richtig.
    if Expr.ParseRoot(CondRootOf(Sh.IfTok, Sh.ThenTok)) then
      Neg := Expr.NegatedTop(Expr.Root)
    else if Expr.TokCount > 0 then
      Neg := 'not (' + TextOf(AMap, Expr.Tok(0).Line, Expr.Tok(0).Col,
        Expr.Tok(Expr.TokCount - 1).Line,
        Expr.Tok(Expr.TokCount - 1).EndCol) + ')'
    else
    begin
      AReason := _(R_IF_COND_UNREADABLE);
      Exit;
    end;
    F := Expr.Tok(0);
    L := Expr.Tok(Expr.TokCount - 1);
    ThenText := RangeText(AMap, StmtSpan(Sh.ThenStmt));
    ElseText := RangeText(AMap, StmtSpan(Sh.ElseStmt));
    AddEdit(AEdits, MakeEdit(AMap, SpanOf(F.Line, F.Col, L.Line, L.EndCol),
      Neg));
    AddEdit(AEdits, MakeEdit(AMap, StmtSpan(Sh.ThenStmt), ElseText));
    AddEdit(AEdits, MakeEdit(AMap, StmtSpan(Sh.ElseStmt), ThenText));
    Result := True;
  finally
    Expr.Free;
  end;
end;

// Die Zeilen AFrom..ATo: StartsInside? Die erste solche Zeile, sonst 0.
function InsideLine(AMap: TRdxCodeMap; AFrom, ATo: Integer): Integer;
var
  Li : Integer;
begin
  Result := 0;
  for Li := AFrom to ATo do
    if AMap.StartsInside(Li) then
      Exit(Li);
end;

class function TRdxIfFixes.SplitIf(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  T          : TRdxToken;
  Root       : TRdxExprRoot;
  Expr       : TRdxCondExpr;
  Top, k, i  : Integer;
  N          : TRdxExprNode;
  Sh         : TRdxIfShape;
  Ind, Step  : string;
  Left, Right, NewText, Line : string;
  BoolLine, Inside, LastLine : Integer;
  Lt, Rf, Rl : TRdxExprTok;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  T := TokenContaining(AMap, ALine, ACol);
  if (T.Low <> 'and') or not IsKeywordAfter(T, Before(AMap, T)) then
    Exit;
  if not ExprRootAt(AMap, T, False, Root) or (Root.Kind <> erkIf) then
    Exit;
  Expr := TRdxCondExpr.Create(AMap);
  try
    if not Expr.ParseRoot(Root) then
      Exit;
    Top := Expr.Root;
    if not Expr.IsChainOf(Top, 'and') then
      Exit;
    N := Expr.Node(Top);
    k := -1;
    for i := 0 to High(N.Ops) do
      if (Expr.Tok(N.Ops[i]).Line = T.Line)
         and (Expr.Tok(N.Ops[i]).Col = T.Col) then
        k := i;
    if k < 0 then
      Exit;
    // Kandidat: ein oberstes 'and' der Bedingung eines if.
    AReason := ReadIf(AMap, Root.Head, Sh);
    if AReason <> '' then
      Exit;
    BoolLine := CompleteBoolEvalLine(AMap);
    LastLine := Sh.EndLine;
    Inside := InsideLine(AMap, Sh.ThenTok.Line + 1, LastLine);
    if Sh.ElseTok.Low <> '' then
      AReason := _(R_IF_SPLIT_ELSE)
    else if DirectiveIn(AMap, Sh) then
      AReason := _(R_IF_DIRECTIVE)
    else if Expr.HasComment then
      AReason := _(R_IF_COND_COMMENT)
    else if BoolLine > 0 then
      AReason := _(R_IF_BOOLEVAL, [BoolLine])
    else if Sh.ThenStmt.Kind = skEmpty then
      AReason := _(R_IF_EMPTY_BRANCH)
    else if Inside > 0 then
      AReason := _(R_IF_INSIDE, [Inside]);
    if AReason <> '' then
      Exit;
    Lt := Expr.Tok(Expr.Node(N.Kids[k]).Last);
    Rf := Expr.Tok(Expr.Node(N.Kids[k + 1]).First);
    Rl := Expr.Tok(N.Last);
    Left := TextOf(AMap, Expr.Tok(N.First).Line, Expr.Tok(N.First).Col,
      Lt.Line, Lt.EndCol);
    Right := TextOf(AMap, Rf.Line, Rf.Col, Rl.Line, Rl.EndCol);
    Ind := IndentOf(AMap.Raw(Sh.IfTok.Line));
    Step := IndentStep(Ind, AMap.Raw(Sh.ThenTok.Line + 1));
    NewText := 'if ' + Left + ' then' + #10 + Ind + Step + 'if ' + Right
      + ' then' + Copy(AMap.Raw(Sh.ThenTok.Line), Sh.ThenTok.EndCol, MaxInt);
    // Die Zeilen des Zweigs eine Stufe tiefer.
    for i := Sh.ThenTok.Line + 1 to LastLine do
    begin
      Line := AMap.Raw(i);
      if not IsBlankLine(Line) then
        Line := Step + Line;
      NewText := NewText + #10 + Line;
    end;
    AEdit := MakeEdit(AMap, SpanOf(Sh.IfTok.Line, Sh.IfTok.Col, LastLine,
      Length(AMap.Raw(LastLine)) + 1), NewText);
    Result := True;
  finally
    Expr.Free;
  end;
end;

// Der Text einer Bedingung als Glied einer and-Kette: unveraendert, wenn
// sie ein Faktor oder selbst eine and-Kette ist, sonst geklammert.
function AndOperand(AMap: TRdxCodeMap; const AIf, AThen: TRdxToken): string;
var
  Expr : TRdxCondExpr;
  F, L : TRdxExprTok;
  Kind : TRdxExprKind;
begin
  Expr := TRdxCondExpr.Create(AMap);
  try
    if Expr.ParseRoot(CondRootOf(AIf, AThen)) then
    begin
      Result := Expr.Text(Expr.Root);
      Kind := Expr.Node(Expr.Root).Kind;
      if not ((Kind in [ekPrimary, ekParen, ekNot])
              or Expr.IsChainOf(Expr.Root, 'and')) then
        Result := '(' + Result + ')';
    end
    else
    begin
      F := Expr.Tok(0);
      L := Expr.Tok(Expr.TokCount - 1);
      Result := '(' + TextOf(AMap, F.Line, F.Col, L.Line, L.EndCol) + ')';
    end;
  finally
    Expr.Free;
  end;
end;

// Kann die Bedingung zwischen AIf und AThen gelesen werden (Lexer)?
function CondReadable(AMap: TRdxCodeMap; const AIf, AThen: TRdxToken): Boolean;
var
  Expr : TRdxCondExpr;
begin
  Expr := TRdxCondExpr.Create(AMap);
  try
    Expr.ParseRoot(CondRootOf(AIf, AThen));
    Result := Expr.TokCount > 0;
  finally
    Expr.Free;
  end;
end;

class function TRdxIfFixes.MergeIf(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Outer, Inner, B, EndTok, X : TRdxToken;
  Sh, ISh                    : TRdxIfShape;
  IS1                        : TRdxStmt;
  Block                      : Boolean;
  OuterInd, InnerInd, Step   : string;
  Body, Line, Tail, Head     : string;
  i, LastLine, BodyLast, Inside : Integer;
  BoolLine                   : Integer;
  Dedent                     : Boolean;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  if not IfAt(AMap, ALine, ACol, Outer) then
    Exit;
  if ReadIf(AMap, Outer, Sh) <> '' then
    Exit;
  // Das innere if: der then-Zweig selbst oder allein in begin..end.
  Block := False;
  EndTok := Default(TRdxToken);
  if Sh.ThenStmt.Kind = skIf then
    Inner := Sh.ThenStmt.First
  else if Sh.ThenStmt.Kind = skBlock then
  begin
    B := Sh.ThenStmt.First;
    if (ReadStmt(AMap, After(AMap, B), B, 1, IS1) <> '')
       or (IS1.Kind <> skIf) then
      Exit;
    X := IS1.Next;
    if X.Low = ';' then
      X := After(AMap, X);
    if not (IsKeywordAfter(X, Before(AMap, X)) and (X.Low = 'end')) then
      Exit;
    // Dieses end muss das des Blocks sein.
    if not SameTok(After(AMap, X), Sh.ThenStmt.Next) then
      Exit;
    Inner := IS1.First;
    EndTok := X;
    Block := True;
  end
  else
    Exit;
  // Kandidat.
  AReason := ReadIf(AMap, Inner, ISh);
  if AReason <> '' then
    Exit;
  BoolLine := CompleteBoolEvalLine(AMap);
  if Sh.ElseTok.Low <> '' then
    AReason := _(R_IF_MERGE_OUTER_ELSE)
  else if ISh.ElseTok.Low <> '' then
    AReason := _(R_IF_MERGE_INNER_ELSE)
  else if DirectiveIn(AMap, Sh) then
    AReason := _(R_IF_DIRECTIVE)
  else if CondComment(AMap, Sh.IfTok, Sh.ThenTok)
     or CondComment(AMap, ISh.IfTok, ISh.ThenTok) then
    AReason := _(R_IF_COND_COMMENT)
  else if CommentInRange(AMap, SpanOf(Sh.ThenTok.Line, Sh.ThenTok.EndCol,
       Inner.Line, Inner.Col))
     or (Block and CommentInRange(AMap, SpanOf(ISh.EndLine, ISh.EndCol,
       EndTok.Line, EndTok.Col))) then
    AReason := _(R_IF_MERGE_COMMENT)
  else if BoolLine > 0 then
    AReason := _(R_IF_BOOLEVAL, [BoolLine])
  else if ISh.ThenStmt.Kind = skEmpty then
    AReason := _(R_IF_EMPTY_BRANCH)
  else if Block and (not FirstOnLine(AMap, EndTok)
     or (EndTok.Line <= ISh.EndLine)) then
    AReason := _(R_IF_MERGE_LAYOUT)
  else if not CondReadable(AMap, Sh.IfTok, Sh.ThenTok)
     or not CondReadable(AMap, ISh.IfTok, ISh.ThenTok) then
    AReason := _(R_IF_COND_UNREADABLE);
  if AReason <> '' then
    Exit;
  // Ausruecken: um die Einrueckung des inneren if gegenueber dem aeusseren.
  OuterInd := IndentOf(AMap.Raw(Outer.Line));
  Step := '';
  if FirstOnLine(AMap, Inner) then
  begin
    InnerInd := IndentOf(AMap.Raw(Inner.Line));
    if (Length(InnerInd) > Length(OuterInd))
       and (Copy(InnerInd, 1, Length(OuterInd)) = OuterInd) then
      Step := Copy(InnerInd, Length(OuterInd) + 1, MaxInt);
  end;
  if Block then
    BodyLast := ISh.EndLine
  else
    BodyLast := Sh.EndLine;
  // Nur, wenn jede nicht leere Zeile die Stufe traegt.
  Dedent := Step <> '';
  for i := ISh.ThenTok.Line + 1 to BodyLast do
  begin
    Line := AMap.Raw(i);
    if not IsBlankLine(Line)
       and (Copy(Line, 1, Length(OuterInd) + Length(Step)) <> OuterInd + Step) then
      Dedent := False;
  end;
  if Dedent then
  begin
    Inside := InsideLine(AMap, ISh.ThenTok.Line + 1, BodyLast);
    if Inside > 0 then
    begin
      AReason := _(R_IF_INSIDE, [Inside]);
      Exit;
    end;
  end;
  Head := 'if ' + AndOperand(AMap, Sh.IfTok, Sh.ThenTok) + ' and '
    + AndOperand(AMap, ISh.IfTok, ISh.ThenTok) + ' then';
  // Der Rumpf: ab hinter dem inneren then bis zum Ende des inneren if (im
  // Block, dahinter der Rest der end-Zeile) bzw. bis zum Zeilenende der
  // Anweisung; Zeile fuer Zeile, die Folgezeilen ausgerueckt.
  if Block then
  begin
    Tail := Copy(AMap.Raw(EndTok.Line), EndTok.EndCol, MaxInt);
    LastLine := EndTok.Line;
  end
  else
  begin
    Tail := '';
    LastLine := Sh.EndLine;
  end;
  Body := '';
  for i := ISh.ThenTok.Line to BodyLast do
  begin
    Line := AMap.Raw(i);
    if Block and (i = BodyLast) then
      Line := Copy(Line, 1, ISh.EndCol - 1);
    if i = ISh.ThenTok.Line then
      Body := Copy(Line, ISh.ThenTok.EndCol, MaxInt)
    else
    begin
      if Dedent and not IsBlankLine(Line) then
        Line := OuterInd + Copy(Line, Length(OuterInd) + Length(Step) + 1,
          MaxInt);
      Body := Body + #10 + Line;
    end;
  end;
  AEdit := MakeEdit(AMap, SpanOf(Outer.Line, Outer.Col, LastLine,
    Length(AMap.Raw(LastLine)) + 1), Head + Body + Tail);
  Result := True;
end;

end.
