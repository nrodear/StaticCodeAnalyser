unit uConcatToFormat;

// AST-basierter Refactoring-Hint: "Convert concatenation -> Format()".
//
// Erkennt String-Konkatenationen wie
//   'Hallo ' + Name + ', du bist ' + IntToStr(Age) + ' Jahre alt'
// und schlaegt vor, sie in einen Format/FormatUtf8-Aufruf umzuwandeln:
//   Format('Hallo %s, du bist %d Jahre alt', [Name, IntToStr(Age)])
//
// Pendant zu ReSharpers "Convert concatenation to interpolation /
// string.Format" (Punkt 2.5 in ReDelphix/todo.md).
//
// Heuristik (konservativ, um False-Positives zu vermeiden):
//
//   1. nkAssign.TypeRef enthaelt >=2 echte (Non-Literal-)'+' Operatoren.
//      Ein einzelnes 'Hello ' + Name ist zwar konvertierbar, aber meist
//      Idiom-Code; erst ab Ketten mit drei Termen wird das Refactoring
//      wirklich lohnenswert. Schwelle ist `MIN_NON_LITERAL_PLUS`.
//
//   2. Mindestens ein nicht-Literal-Term ist Bestandteil der Kette
//      (sonst ist es reine Multiline-Literal-Konkatenation - kein
//      Format-Kandidat).
//
//   3. SQL-Kontext wird explizit ausgeklammert (uSQLInjection schreibt
//      dort schon einen Befund). Daher: LHS-Name enthaelt SQL-Property
//      ('.sql.text', '.commandtext', ...) -> Skip.
//
//   4. Kein Treffer wenn RHS bereits 'format(' / 'formatutf8(' enthaelt.
//
// Befund-Schweregrad: lsWarning. Roter Stripe im IDE-Editor entsteht
// ueber uIDELineHighlighter (SeverityAccent ergibt ACCENT_WARNING ~
// Amber). Wer einen echten roten Balken will, kann unten `EMIT_SEVERITY`
// auf `lsError` setzen (ACCENT_ERROR = sattes Rot).
//
// Die Logik laeuft - analog zu uSQLInjection - auf der flachen TypeRef-
// String-Repraesentation des RHS (der Parser flacht arithmetische
// Ausdruecke in einen Token-String ab, statt einen echten Expression-
// Tree zu bauen).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConcatToFormatDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Mindestanzahl echter (= Non-Literal-)'+' Operatoren, damit der Hint
    // ausgeloest wird. 2 entspricht der Kette 'a' + x + 'b' + y - drei
    // Terme, klares Format-Kandidat.
    const MIN_NON_LITERAL_PLUS = 2;

    // Default-Severity. Steuert die Farbe des IDE-Balkens:
    //   lsError   -> ACCENT_ERROR   (sattes Rot)
    //   lsWarning -> ACCENT_WARNING (Amber/Orange)
    //   lsHint    -> ACCENT_HINT    (Gruen)
    const EMIT_SEVERITY = lsWarning;

    // Zaehlt '+' Operatoren ausserhalb von String-Literalen.
    // Liefert ausserdem in OutHasLiteral / OutHasNonLiteral zurueck, ob
    // mindestens ein literaler bzw. nicht-literaler Term vorkam.
    class procedure ScanConcat(const S: string;
      out PlusCount: Integer; out HasLiteral, HasNonLiteral: Boolean); static;

    // True wenn LHS-Name auf einen SQL-Property-Zugriff zeigt - dann
    // ist uSQLInjection zustaendig und wir wollen keinen Doppelbefund.
    class function IsSqlContext(const Lhs: string): Boolean; static;

    // True wenn RHS bereits 'format(' / 'formatutf8(' / 'formatstring('
    // enthaelt - dann braucht der User keinen Refactor-Hint mehr.
    class function AlreadyUsesFormat(const RHS: string): Boolean; static;
  end;

implementation

const
  SQL_LHS_HINTS: array[0..5] of string = (
    '.sql.text', '.sql.', '.commandtext', '.sqltext',
    '.sqlcommand', '.sql:='
  );

  // Lower-Case-Marker. Wortgrenze ist nicht zwingend, weil der Suffix '('
  // bereits abgrenzt.
  FORMAT_MARKERS: array[0..2] of string = (
    'format(', 'formatutf8(', 'formatstring('
  );

{ ---- Helpers ---- }

class procedure TConcatToFormatDetector.ScanConcat(const S: string;
  out PlusCount: Integer; out HasLiteral, HasNonLiteral: Boolean);
//
// Token-Scanner:
//   - Wir laufen Zeichen fuer Zeichen durch S
//   - In-String wird per Single-Quote Toggle gefuehrt (mit ''-Escape)
//   - '+' ausserhalb eines Strings ist ein Konkat-Operator -> PlusCount++
//   - Fuer jeden gefundenen '+' pruefen wir, ob die "Nachbar-Seite"
//     ein Literal ('...') oder ein anderer Token ist - daraus ergeben
//     sich HasLiteral / HasNonLiteral.
//
// HasLiteral / HasNonLiteral sind sticky (einmal True, bleibt True).
//
var
  i, j     : Integer;
  inStr    : Boolean;
  c        : Char;
  prev, nxt: Char;
begin
  PlusCount     := 0;
  HasLiteral    := False;
  HasNonLiteral := False;
  inStr := False;
  i := 1;
  while i <= Length(S) do
  begin
    c := S[i];
    if c = '''' then
    begin
      // ''-Escape innerhalb des Strings
      if inStr and (i < Length(S)) and (S[i + 1] = '''') then
      begin
        Inc(i, 2);
        Continue;
      end;
      inStr := not inStr;
    end
    else if (not inStr) and (c = '+') then
    begin
      // Nachbarn (Whitespace ueberspringen)
      prev := #0;
      for j := i - 1 downto 1 do
        if S[j] > ' ' then begin prev := S[j]; Break; end;
      nxt := #0;
      for j := i + 1 to Length(S) do
        if S[j] > ' ' then begin nxt := S[j]; Break; end;

      Inc(PlusCount);
      if prev = '''' then HasLiteral := True
      else if prev <> #0 then HasNonLiteral := True;
      if nxt = '''' then HasLiteral := True
      else if nxt <> #0 then HasNonLiteral := True;
    end;
    Inc(i);
  end;
end;

class function TConcatToFormatDetector.IsSqlContext(const Lhs: string): Boolean;
var
  Low : string;
  Kw  : string;
begin
  Result := False;
  Low := Lhs.ToLower;
  for Kw in SQL_LHS_HINTS do
    if Pos(Kw, Low) > 0 then Exit(True);
end;

class function TConcatToFormatDetector.AlreadyUsesFormat(
  const RHS: string): Boolean;
var
  Low : string;
  M   : string;
begin
  Result := False;
  Low := RHS.ToLower;
  for M in FORMAT_MARKERS do
    if Pos(M, Low) > 0 then Exit(True);
end;

{ ---- Public API ---- }

class procedure TConcatToFormatDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure Report(const Target: string; PlusCount, Line: Integer);
  var
    F : TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(Line);
    F.MissingVar := Format('Concat (%d x ''+'') -> Format(...) %s',
                           [PlusCount, Target]);
    F.SetKind(fkConcatToFormat);
    Results.Add(F);
  end;

var
  Assigns       : TList<TAstNode>;
  N             : TAstNode;
  PlusCount     : Integer;
  HasLiteral    : Boolean;
  HasNonLiteral : Boolean;
begin
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      // SQL-Property -> uSQLInjection ist zustaendig
      if IsSqlContext(N.Name) then Continue;
      // Bereits ein Format-Call drin -> kein Hint
      if AlreadyUsesFormat(N.TypeRef) then Continue;

      ScanConcat(N.TypeRef, PlusCount, HasLiteral, HasNonLiteral);
      if PlusCount < MIN_NON_LITERAL_PLUS then Continue;
      // Mindestens ein Literal und ein Non-Literal-Term in der Kette
      if not (HasLiteral and HasNonLiteral) then Continue;

      Report(N.Name, PlusCount, N.Line);
    end;
  finally
    Assigns.Free;
  end;
end;

class procedure TConcatToFormatDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
