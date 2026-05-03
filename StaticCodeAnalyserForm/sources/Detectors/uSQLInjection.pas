unit uSQLInjection;

// AST-basierter SQL-Injection-Detektor (Sonar-Regel #4).
//
// Erkennt SQL-Befehle, die durch String-Konkatenation (+) aufgebaut werden,
// statt parametrisierte Queries zu verwenden.
//
// Zwei Erkennungs-Heuristiken:
//
//   H1 – SQL-Property-Zuweisung:
//        nkAssign.Name enthält bekannte SQL-Property-Namen
//        (sql, commandtext, sqltext, ...) UND TypeRef enthält '+'
//
//   H2 – SQL-Schlüsselwort in Literal:
//        nkAssign.TypeRef enthält ein SQL-Statement-Schlüsselwort
//        als Stringliteral ('select, 'insert, ...) UND '+'
//
// Schweregrad: lsError (Blocker)
//
// Hinweis: Calls wie Query.SQL.Add('SELECT '+var) werden über die
// nkCall.Name-Prüfung erfasst, da ParsePrimary die Argumente einschließt.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uSQLInjectionScore, uDetectorUtils;

type
  TSQLInjectionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function IsAssignRisk(const Name, RHS: string): Boolean; static;
    class function IsCallRisk(const CallName: string): Boolean; static;
    // True wenn der String '+' AUSSERHALB von Stringliteralen enthaelt
    // (also echte Konkatenation mit Bezeichner/Variable). 'x'+'y' allein
    // ist kein Risiko, das ist nur Multi-Line-Stringliteral-Aufbau.
    class function HasNonLiteralPlus(const S: string): Boolean; static;
  end;

implementation

const
  // Properties/Felder die SQL-Text enthalten
  SQL_PROPS: array[0..6] of string = (
    'sql.text', '.sql.', 'commandtext', 'sqltext',
    'sqlcommand', 'query.sql', '.sql:='
  );

  // SQL-DML/DDL-Schlüsselwörter als Stringliteral-Anfang
  SQL_KW: array[0..5] of string = (
    '''select ', '''insert ', '''update ', '''delete ',
    '''exec ', '''drop '
  );

  // SQL-Aufruf-Methoden die SQL-Text als Argument nehmen
  SQL_CALL_METHODS: array[0..5] of string = (
    'sql.add(', 'execsql(', 'execquery(', 'execproc(',
    'open(', 'commandtext'
  );

{ ---- Heuristiken ---- }

class function TSQLInjectionDetector.HasNonLiteralPlus(
  const S: string): Boolean;
// Findet ein '+' welches NICHT zwischen zwei Stringliteralen steht.
//
//   'a'+'b'    -> reine Literal-Konkat, kein Risiko (False)
//   'a'+x      -> Variable-Konkat, Risiko (True)
//   x+'a'      -> Variable-Konkat, Risiko (True)
//   'a'+f()    -> Funktionsaufruf-Konkat, Risiko (True)
//
// Algorithmus: zeichenweise durch S, '+' nur ausserhalb von Stringliteralen
// melden, und dabei pruefen ob unmittelbar davor UND danach (ignorierend
// Whitespace) ein "'" steht. Wenn beide Seiten Quote -> reine Literal-Konkat
// (kein Risiko). Sonst Variable-Konkat -> Risiko.
var
  i, j     : Integer;
  inStr    : Boolean;
  c        : Char;
  prev, nxt: Char;
begin
  Result := False;
  inStr  := False;
  i := 1;
  while i <= Length(S) do
  begin
    c := S[i];
    if c = '''' then
    begin
      // Doppeltes '' innerhalb eines Strings = escaped Quote, weiter im String
      if inStr and (i < Length(S)) and (S[i + 1] = '''') then
      begin
        Inc(i, 2);
        Continue;
      end;
      inStr := not inStr;
    end
    else if (not inStr) and (c = '+') then
    begin
      // Pruefe Nachbarn (Whitespace ueberspringen)
      prev := #0;
      for j := i - 1 downto 1 do
        if S[j] > ' ' then begin prev := S[j]; Break; end;
      nxt := #0;
      for j := i + 1 to Length(S) do
        if S[j] > ' ' then begin nxt := S[j]; Break; end;

      // Beide Seiten Quote -> Literal-Konkat ueberspringen.
      // Sonst -> Variable-Konkat erkannt.
      if (prev <> '''') or (nxt <> '''') then
        Exit(True);
    end;
    Inc(i);
  end;
end;

class function TSQLInjectionDetector.IsAssignRisk(
  const Name, RHS: string): Boolean;
var
  NameLow, RHSLow : string;
  Kw              : string;
begin
  Result  := False;
  NameLow := Name.ToLower;
  RHSLow  := RHS.ToLower;

  // Konkatenation ist Pflicht - aber NUR ausserhalb von Stringliteralen.
  // 'CREATE TABLE...'+'(...)' ist reine Literal-Konkatenation, kein Risiko.
  if not HasNonLiteralPlus(RHS) then Exit;

  // H1: bekannte SQL-Property im Ziel-Namen.
  // Wortgrenzen-Pruefung: 'commandtext' soll nicht 'mycommandtextra' matchen.
  // Patterns mit '.'/':' enthalten haben durch die Trennzeichen schon natuerliche
  // Grenzen, fuer die anderen brauchen wir den WholeWord-Helper.
  for Kw in SQL_PROPS do
    if TDetectorUtils.ContainsWholeWordLower(Kw, NameLow) then Exit(True);

  // H2: SQL-Schlüsselwort als ERSTES Literal im RHS (Position 1).
  // Nur wenn der RHS direkt mit dem SQL-Keyword beginnt – verhindert
  // false positives wenn SQL-Code als Dokumentations-String vorkommt.
  for Kw in SQL_KW do
    if Pos(Kw, RHSLow) = 1 then Exit(True);
end;

class function TSQLInjectionDetector.IsCallRisk(
  const CallName: string): Boolean;
var
  Low : string;
  Kw  : string;
begin
  Result := False;
  Low    := CallName.ToLower;

  // Konkatenation muss ausserhalb Literalen sein (s. IsAssignRisk).
  if not HasNonLiteralPlus(CallName) then Exit;

  // SQL-Aufruf-Methode im Call-Namen. Patterns enden auf '(' was natuerliche
  // rechte Grenze ist; links muss aber Wortgrenze her - 'open(' soll nicht
  // 'reopen(' matchen.
  for Kw in SQL_CALL_METHODS do
    if TDetectorUtils.ContainsWholeWordLower(Kw, Low) then Exit(True);

  // SQL-Schlüsselwort als Stringliteral im Argument (Patterns mit fuehrendem '
  // sind selbst-abgrenzend, brauchen kein WholeWord)
  for Kw in SQL_KW do
    if Pos(Kw, Low) > 0 then Exit(True);
end;

{ ---- Öffentliche API ---- }

class procedure TSQLInjectionDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure Report(const Target, RHS: string; Line: Integer);
  var
    F             : TLeakFinding;
    Estimate      : TFixEstimate;
    DisplayTarget : string;
    ParenPos      : Integer;
  begin
    // Aufrufe wie Query.SQL.Add('SELECT '+x) → nur 'Query.SQL.Add()' zeigen
    ParenPos := Pos('(', Target);
    if ParenPos > 0 then
      DisplayTarget := Copy(Target, 1, ParenPos - 1) + '()'
    else
      DisplayTarget := Target;

    Estimate     := TSQLFixScorer.Estimate(RHS);
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(Line);
    F.MissingVar := DisplayTarget + '  [' + TSQLFixScorer.FormatShort(Estimate) + ']';
    F.Severity   := lsError;
    F.Kind       := fkSQLInjection;
    Results.Add(F);
  end;

var
  Assigns : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  N       : TAstNode;
begin
  // nkAssign: SQL.Text := 'SELECT * FROM ' + VarName
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
      if IsAssignRisk(N.Name, N.TypeRef) then
        Report(N.Name, N.TypeRef, N.Line);
  finally
    Assigns.Free;
  end;

  // nkCall: Query.SQL.Add('SELECT ' + VarName)
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
      if IsCallRisk(N.Name) then
        Report(N.Name, N.Name, N.Line);
  finally
    Calls.Free;
  end;
end;

class procedure TSQLInjectionDetector.AnalyzeUnit(UnitNode: TAstNode;
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
