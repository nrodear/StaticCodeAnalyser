unit uRdxCondFixes;

// reDelphix - Code-Aktionen ohne Fund an einem Ausdruck (Charge C78,
// Wettbewerbs-Todo 2026-10-23 C8), OHNE ToolsAPI und ohne Parser
// (FPC-Pruefstand); der Ausdrucks-Leser ist uRdxCondExpr.
//
//   DeMorgan     Caret auf 'and'/'or' bzw. auf 'not' vor '( ... )':
//                  not (A and B)   ->  (not A) or (not B)
//                  not (A or B)    ->  (not A) and (not B)
//                und zurueck, wenn die Kette nicht schon unter 'not ( )'
//                steht:
//                  A and B         ->  not ((not A) or (not B))
//                  (not A) or (not B)  ->  not (A and B)
//                Jedes Glied wird ein Faktor (uRdxCondExpr.NegatedFactor:
//                'not F' -> F, sonst '(not X)' bzw. '(not (X))'); das
//                Ergebnis steht in Klammern, ausser es fuellt den ganzen
//                Ausdruck oder eine Klammer allein.
//   FlipCompare  Caret auf '=', '<>', '<', '>', '<=', '>=':
//                  Index < List.Count  ->  List.Count > Index
//                ('<' <-> '>', '<=' <-> '>=', '=' und '<>' bleiben).
//
// WO: De Morgan nur in der Bedingung von if, while und until und nur auf
// boolescher Ebene - die Kette und alle Knoten ueber ihr sind Klammern,
// 'not' oder and/or/xor-Ketten. Steht sie in einem Vergleich, einem
// Argument oder in Arithmetik ('(Flags and Mask) <> 0'), ist sie bitweise:
// kein Eintrag (mit gemischten Breiten waere De Morgan dort nicht gleich).
// Vergleich drehen dazu auf der rechten Seite einer Zuweisung.
//
// GLEICHE BEDEUTUNG:
//   DeMorgan     dieselben Glieder in derselben Reihenfolge; unter {$B-}
//                endet die Auswertung am selben Glied (not (A and B) ist
//                wahr, sobald A falsch ist - (not A) or ... ebenso), unter
//                {$B+} laufen beide ganz. ANNAHME 'not' logisch (Kopf von
//                uRdxCondExpr, E-C78-1).
//   FlipCompare  ein Vergleich ist gespiegelt gleich (auch fuer Gleitkomma
//                mit NaN, Mengen - '<=' Teilmenge ist '>=' Obermenge -,
//                Strings). Die Seiten werden in anderer Reihenfolge
//                ausgewertet: darum keine Klammer-Aufrufe auf einer Seite
//                (ausser den reinen Intrinsics PURE_CALLS, wenn die Datei
//                keine gleichnamige Routine deklariert), kein 'as', kein
//                'inherited'. ANNAHME (E-C78-3): ein Property-Zugriff ohne
//                Klammern ('List.Count') ist seiteneffektfrei.
//
// GESPERRT: ein Kommentar oder eine Direktive im umgebauten Bereich (er
// ginge verloren); De Morgan: eine Kette mit gemischten Operatoren
// ('A or B xor C'); Vergleich drehen: s. oben.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_CF_COMMENT = 'comment or directive in the expression - it would be lost';
  R_CF_MIXED = 'the chain mixes "%s" and "%s" - De Morgan needs one operator';

type
  TRdxCondFixes = class
  public
    // C8 De Morgan am Caret (s. Kopf); AOp: 'and' bzw. 'or' der Kette.
    // False mit leerem AReason: kein Kandidat.
    class function DeMorgan(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out AEdit: TRdxEdit; out AOp, AReason: string): Boolean; static;
  end;

implementation

uses
  uRefactorInfo,    // TRefactorSpan
  uRdxCondExpr,     // TRdxCondExpr, ExprRootAt
  uRdxText;         // _(): in die reDelphix-Sprache

const
  SPAN_COND = 'ctxcond';
  BOOL_OPS: array[0..2] of string = ('and', 'or', 'xor');

function InArr(const S: string; const A: array of string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(A) to High(A) do
    if A[i] = S then
      Exit(True);
end;

// Alle Operatoren der Kette sind and/or/xor.
function IsBoolChain(AExpr: TRdxCondExpr; ANode: Integer): Boolean;
var
  N : TRdxExprNode;
  i : Integer;
begin
  N := AExpr.Node(ANode);
  Result := N.Kind = ekChain;
  if not Result then
    Exit;
  for i := 0 to High(N.Ops) do
    if not InArr(AExpr.Tok(N.Ops[i]).Low, BOOL_OPS) then
      Exit(False);
end;

// Steht ANode auf boolescher Ebene: jeder Knoten darueber ist Klammer,
// 'not' oder eine and/or/xor-Kette?
function OnBoolLevel(AExpr: TRdxCondExpr; ANode: Integer): Boolean;
var
  P : Integer;
begin
  Result := True;
  P := AExpr.Node(ANode).Parent;
  while P >= 0 do
  begin
    if not ((AExpr.Node(P).Kind in [ekParen, ekNot]) or IsBoolChain(AExpr, P)) then
      Exit(False);
    P := AExpr.Node(P).Parent;
  end;
end;

// Die Glieder von AChain, je verneint, mit AJoin verbunden.
function NegatedItems(AExpr: TRdxCondExpr; AChain: Integer;
  const AJoin: string): string;
var
  N : TRdxExprNode;
  i : Integer;
begin
  N := AExpr.Node(AChain);
  Result := '';
  for i := 0 to High(N.Kids) do
  begin
    if i > 0 then
      Result := Result + ' ' + AJoin + ' ';
    Result := Result + AExpr.NegatedFactor(N.Kids[i]);
  end;
end;

class function TRdxCondFixes.DeMorgan(AMap: TRdxCodeMap; ALine,
  ACol: Integer; out AEdit: TRdxEdit; out AOp, AReason: string): Boolean;
var
  T          : TRdxToken;
  Root       : TRdxExprRoot;
  Expr       : TRdxCondExpr;
  Ti, N, C, P, Target, i : Integer;
  IsForward    : Boolean;
  Op, Dual, Other, NewText : string;
  Span       : TRefactorSpan;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AOp := '';
  AReason := '';
  T := TokenContaining(AMap, ALine, ACol);
  if not IsKeywordAfter(T, Before(AMap, T))
     or not ((T.Low = 'and') or (T.Low = 'or') or (T.Low = 'not')) then
    Exit;
  if not ExprRootAt(AMap, T, False, Root) then
    Exit;
  Expr := TRdxCondExpr.Create(AMap);
  try
    if not Expr.ParseRoot(Root) then
      Exit;
    Ti := Expr.TokenAt(T.Line, T.Col);
    if Ti < 0 then
      Exit;
    N := Expr.OwnerOfOp(Ti);
    if N < 0 then
      Exit;
    // Die Kette C und was ersetzt wird (Target).
    if Expr.Node(N).Kind = ekNot then
    begin
      P := Expr.Node(N).Kids[0];
      if Expr.Node(P).Kind <> ekParen then
        Exit;
      C := Expr.Node(P).Kids[0];
      IsForward := True;
      Target := N;
    end
    else if Expr.Node(N).Kind = ekChain then
    begin
      C := N;
      P := Expr.Node(C).Parent;
      IsForward := (P >= 0) and (Expr.Node(P).Kind = ekParen)
        and (Expr.Node(P).Parent >= 0)
        and (Expr.Node(Expr.Node(P).Parent).Kind = ekNot);
      if IsForward then
        Target := Expr.Node(P).Parent
      else
        Target := C;
    end
    else
      Exit;
    if not IsBoolChain(Expr, C) or not OnBoolLevel(Expr, C) then
      Exit;
    Op := Expr.OpOf(C, 0);
    if (Op <> 'and') and (Op <> 'or') then
      Exit;
    // Kandidat.
    AOp := Op;
    Other := '';
    for i := 1 to High(Expr.Node(C).Ops) do
      if Expr.OpOf(C, i) <> Op then
        Other := Expr.OpOf(C, i);
    Span := Expr.Span(Target, SPAN_COND);
    if Other <> '' then
      AReason := _(R_CF_MIXED, [Op, Other])
    else if CommentInRange(AMap, Span) then
      AReason := _(R_CF_COMMENT);
    if AReason <> '' then
      Exit;
    if Op = 'and' then
      Dual := 'or'
    else
      Dual := 'and';
    if IsForward then
    begin
      NewText := NegatedItems(Expr, C, Dual);
      // Klammern, ausser das Ergebnis fuellt den Ausdruck bzw. eine
      // Klammer allein.
      P := Expr.Node(Target).Parent;
      if (P >= 0) and (Expr.Node(P).Kind <> ekParen) then
        NewText := '(' + NewText + ')';
    end
    else
      NewText := 'not (' + NegatedItems(Expr, C, Dual) + ')';
    AEdit.Span := Span;
    AEdit.Expected := RangeText(AMap, Span);
    AEdit.NewText := NewText;
    Result := True;
  finally
    Expr.Free;
  end;
end;


end.
