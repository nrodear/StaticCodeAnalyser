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
  uAstNode, uSCAConsts, uMethodd12, uSQLInjectionScore;

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

class function TSQLInjectionDetector.IsAssignRisk(
  const Name, RHS: string): Boolean;
var
  NameLow, RHSLow : string;
  Kw              : string;
begin
  Result  := False;
  NameLow := Name.ToLower;
  RHSLow  := RHS.ToLower;

  // Konkatenation ist Pflicht
  if Pos('+', RHSLow) = 0 then Exit;

  // H1: bekannte SQL-Property im Ziel-Namen
  for Kw in SQL_PROPS do
    if Pos(Kw, NameLow) > 0 then Exit(True);

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

  // Keine Konkatenation → kein Risiko
  if Pos('+', Low) = 0 then Exit;

  // SQL-Aufruf-Methode im Call-Namen
  for Kw in SQL_CALL_METHODS do
    if Pos(Kw, Low) > 0 then Exit(True);

  // SQL-Schlüsselwort als Stringliteral im Argument
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
