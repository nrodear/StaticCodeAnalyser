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
    // H3: Format-Familie mit SQL-Keyword im Format-String + %-Placeholder.
    // mORMot-Pattern: ExecuteFmt('SELECT * FROM % WHERE id=%', [tbl, id]) -
    // strukturelle Injection ueber Tabellenname, kein '+' im Code -> H1/H2
    // uebersehen das. Severity = lsError, gleiche Kind wie sonstige SQL-Risks.
    class function IsFormatSqlRisk(const CallName: string): Boolean; static;
    // True wenn der String '+' AUSSERHALB von Stringliteralen enthaelt
    // (also echte Konkatenation mit Bezeichner/Variable). 'x'+'y' allein
    // ist kein Risiko, das ist nur Multi-Line-Stringliteral-Aufbau.
    class function HasNonLiteralPlus(const S: string): Boolean; static;
    // True wenn JEDES '+' im RHS unmittelbar auf ein String-Literal oder
    // einen Aufruf einer safe-cast-Funktion folgt. Whitelist:
    //   IntToStr, Int64ToStr, FormatInt, GetEnumName  (numerisch)
    //   QuotedStr, QuotedSQL, QuotedStrJSON, SQLVarToText  (escape'd)
    // Dann ist die Konkatenation injection-sicher trotz '+'-Operator.
    class function AllConcatTermsSafe(const RHS: string): Boolean; static;
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

class function TSQLInjectionDetector.AllConcatTermsSafe(
  const RHS: string): Boolean;
// Strippt alle String-Literale (mit ''-Escape-Handling) raus, dann an
// jedem '+' den nachfolgenden Token (Identifier/Whitespace) extrahieren.
// Wenn der Token entweder leer (Literal-Position) oder Aufruf einer
// safe-cast-Funktion ist -> sicher. Sonst (bare Identifier oder anderer
// Funktionsaufruf) -> unsicher.
//
// Beispiele:
//   ' WHERE ID=' + IntToStr(aID)            -> True
//   ' WHERE NAME=' + QuotedStr(s) + ' OR'   -> True
//   ' WHERE NAME=' + name                   -> False (bare Identifier)
//   ' WHERE NAME=' + Format('%s',[name])    -> False (kein safe-cast)
const
  SAFE_CASTS : array[0..7] of string = (
    'inttostr', 'int64tostr', 'formatint', 'getenumname',
    'quotedstr', 'quotedsql', 'quotedstrjson', 'sqlvartotext'
  );
var
  Stripped : string;
  i, j, p  : Integer;
  inStr    : Boolean;
  c        : Char;
  ident    : string;
  s        : string;
  isSafe   : Boolean;
begin
  // 1) String-Literale durch Leerzeichen ersetzen (Position erhalten).
  //    '' innerhalb eines Strings ist Escape-Quote, weiter im String.
  Stripped := RHS;
  inStr := False;
  i := 1;
  while i <= Length(Stripped) do
  begin
    c := Stripped[i];
    if c = '''' then
    begin
      if inStr and (i < Length(Stripped)) and (Stripped[i + 1] = '''') then
      begin
        Stripped[i] := ' ';
        Stripped[i + 1] := ' ';
        Inc(i, 2);
        Continue;
      end;
      Stripped[i] := ' ';
      inStr := not inStr;
    end
    else if inStr then
      Stripped[i] := ' ';
    Inc(i);
  end;
  Stripped := Stripped.ToLower;

  // 2) An jedem '+' den nachfolgenden Token extrahieren und pruefen.
  i := 1;
  while i <= Length(Stripped) do
  begin
    if Stripped[i] = '+' then
    begin
      // Whitespace nach '+' skippen.
      j := i + 1;
      while (j <= Length(Stripped)) and (Stripped[j] <= ' ') do Inc(j);
      // Identifier extrahieren.
      p := j;
      while (j <= Length(Stripped)) and
            CharInSet(Stripped[j], ['a'..'z', '_', '0'..'9']) do
        Inc(j);
      ident := Copy(Stripped, p, j - p);
      if ident = '' then
      begin
        // Position war ein gestripptes Literal -> ok.
        Inc(i);
        Continue;
      end;
      // Identifier vorhanden - muss safe-cast-Funktionsaufruf sein.
      // Pflicht: '(' direkt nach (ggf. Whitespace) dem Identifier.
      while (j <= Length(Stripped)) and (Stripped[j] <= ' ') do Inc(j);
      if (j > Length(Stripped)) or (Stripped[j] <> '(') then
        Exit(False); // bare Identifier -> Variable, unsicher
      isSafe := False;
      for s in SAFE_CASTS do
        if ident = s then begin isSafe := True; Break; end;
      if not isSafe then Exit(False); // andere Funktion -> unsicher
    end;
    Inc(i);
  end;
  Result := True;
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

  // Whitelist: alle Konkat-Terme sind String-Literale oder safe-cast-Calls
  // (IntToStr, QuotedStr, ...) -> injection-sicher trotz '+'.
  if AllConcatTermsSafe(RHS) then Exit;

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

  // Whitelist: alle Konkat-Terme sind String-Literale oder safe-cast-Calls
  // (IntToStr, QuotedStr, ...) -> injection-sicher trotz '+'.
  if AllConcatTermsSafe(CallName) then Exit;

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

class function TSQLInjectionDetector.IsFormatSqlRisk(
  const CallName: string): Boolean;
// Pattern: <FormatFn>(<SqlKeyword-Literal mit %>, [args])
// FormatFn ist eine der bekannten Format-/Exec-Familien (Format, FormatUtf8,
// FormatSQL, ExecuteFmt, RunSQL, QuerySingle, QueryInt). SQL_KW (', select,
// 'insert, ...) muss im Call-Name vorkommen UND mindestens ein '%' (Format-
// Placeholder) - reiner statischer SQL-String ohne Placeholder waere safe.
const
  FORMAT_FNS: array[0..6] of string = (
    'format(', 'formatutf8(', 'formatsql(', 'executefmt(',
    'runsql(', 'querysingle(', 'queryint('
  );
var
  Low : string;
  Fn  : string;
  Kw  : string;
  FnIdx, KwIdx, PctIdx : Integer;
begin
  Result := False;
  Low := CallName.ToLower;
  for Fn in FORMAT_FNS do
  begin
    FnIdx := Pos(Fn, Low);
    if FnIdx <= 0 then Continue;
    // Argument-Bereich = alles nach dem '(' der Format-Funktion
    var ArgsLow := Copy(Low, FnIdx + Length(Fn), MaxInt);
    // Mindestens ein SQL-Keyword als Literal im Format-String
    for Kw in SQL_KW do
    begin
      KwIdx := Pos(Kw, ArgsLow);
      if KwIdx <= 0 then Continue;
      // Plus mindestens ein '%' im Argument-Bereich. Wenn keiner ->
      // statischer SQL-String ohne Substitution -> kein Risiko.
      PctIdx := Pos('%', ArgsLow);
      if PctIdx > 0 then Exit(True);
    end;
  end;
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
  // nkAssign: SQL.Text := 'SELECT * FROM ' + VarName ODER
  //           s := FormatUtf8('SELECT * FROM %', [tbl])  (H3 / mORMot-Style)
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
      if IsAssignRisk(N.Name, N.TypeRef) or IsFormatSqlRisk(N.TypeRef) then
        Report(N.Name, N.TypeRef, N.Line);
  finally
    Assigns.Free;
  end;

  // nkCall: Query.SQL.Add('SELECT ' + VarName) ODER
  //         ExecuteFmt('SELECT * FROM %', [tbl])  (H3 / mORMot-Style)
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
      if IsCallRisk(N.Name) or IsFormatSqlRisk(N.Name) then
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
