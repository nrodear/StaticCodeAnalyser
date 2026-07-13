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
//
// FP-Gates (2026-07-04, Real-World-Audit Sektion 3.1, Prio 1 -
// Const/Literal-Dataflow):
//   * const-derived-variable: konkatenierte Variable wird in der Routine
//     NUR aus String-Literalen zugewiesen -> kein Fund (IsConstDerivedLocal)
//   * int-format-concat: Format()-Maske nur mit %d/%u/%x-Platzhaltern bzw.
//     Format-Familie mit ausschliesslich Integer-/Literal-Argumenten ->
//     kein Fund (IsIntOnlyFormatArg / AreFormatArgsInjectionSafe)
//   * const-concat: Format-Familie mit reinen Literal-Argumenten
//     (Seed-Daten) -> kein Fund (AreFormatArgsInjectionSafe)
//
// FP-Gates (2026-07-05, Real-World-Audit Prio 6 - ORM/SQL-Builder):
//   * orm-sql-builder: mORMot-Inline-Binding ':(%):' im Format-Literal ->
//     Werte werden von ExtractInlineParameters als Parameter GEBUNDEN,
//     nicht roh substituiert -> kein Fund (Gate in IsFormatSqlRisk)
//   * orm-sql-builder / sql-builder-api: Konkat-Term bzw. Format-Argument
//     ist ein ORM-Schema-Metadatum (Table.SqlTableName, TableMap.fTableName,
//     BlobField^.NameUtf8, ...) oder ein kompletter Quoting-Helfer-Aufruf
//     (GetFieldNameForSQL(...)) -> kein Fund (IsOrmMetaIdent / IsOrmMetaPath
//     / IsSafeSqlHelperCall)
//   * sql-builder-api: Folge-Arrays der Format-Familie (FormatSql(Fmt,
//     Args, Params)) sind gebundene ?-Parameter -> nur das ERSTE [..]-Array
//     wird als %-Substitution geprueft (AreFormatArgsInjectionSafe)

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
    class function IsAssignRisk(MethodNode: TAstNode;
      const Name, RHS: string): Boolean; static;
    class function IsCallRisk(MethodNode: TAstNode;
      const CallName: string): Boolean; static;
    // Negativ-Gate fuer die LOSEN Heuristiken (Keyword-Substring + Format):
    // True wenn der Call/das Ziel eine bekannte Nicht-SQL-Senke ist -
    // Log-Funktionen (LogMsg/LogMsgError/OutputDebugString), UI-Ausgaben
    // (ShowMessage/MessageDlg/StatusBar.Panels[].Text/.Caption/.Hint),
    // WriteLn, raise. Diese tragen oft englische Prosa, die mit SQL-Verben
    // ('Update '/'Create '/'Exec ') beginnt -> sonst Massen-FP.
    class function IsNonSqlSink(const Text: string): Boolean; static;
    // H3: Format-Familie mit SQL-Keyword im Format-String + %-Placeholder.
    // mORMot-Pattern: ExecuteFmt('SELECT * FROM % WHERE id=%', [tbl, id]) -
    // strukturelle Injection ueber Tabellenname, kein '+' im Code -> H1/H2
    // uebersehen das. Severity = lsError, gleiche Kind wie sonstige SQL-Risks.
    class function IsFormatSqlRisk(MethodNode: TAstNode;
      const CallName: string): Boolean; static;
    // True wenn ein SQL_KW im Text vorkommt. Sonderfall 'call': der Windows-
    // Batch-Befehl  call "pfad"  (z.B. BuildLogStats RunMSBuild:
    // Format('call "%s"', [...])) kollidiert mit dem SQL-Stored-Proc-CALL.
    // Folgt auf 'call ' ein " -> Shell-Befehl (SQL nutzt fuer Werte '...' nie
    // "..."), kein SQL. Echtes  CALL proc  / 'call '+proc bleibt erkannt.
    class function HasSqlKwHit(const Hay: string): Boolean; static;
    // Prosa-Gate fuer prosa-prone SQL-Verben (CREATE/DROP/ALTER/TRUNCATE/
    // DELETE/UPDATE/WITH): englische Saetze beginnen oft mit diesen Verben
    // ('Create file '/'Delete directory '/'update one field'/Check(...,'with
    // spaces')). Echtes SQL hat nach dem Verb IMMER eine rigide Fortsetzung
    // (Objekt-Keyword TABLE/VIEW/FROM..., ' SET ', ' AS ') ODER endet am Verb
    // ('CREATE ' + x) ODER %-Placeholder. True = Prosa, kein SQL. Andere
    // Verben (select/insert/exec/merge/replace/grant/revoke/call) haben
    // Identifier-/flexible Fortsetzung und werden NICHT gegatet.
    class function IsKeywordProse(const Hay, Kw: string;
      KwPos: Integer): Boolean; static;
    // True wenn der String '+' AUSSERHALB von Stringliteralen enthaelt
    // (also echte Konkatenation mit Bezeichner/Variable). 'x'+'y' allein
    // ist kein Risiko, das ist nur Multi-Line-Stringliteral-Aufbau.
    class function HasNonLiteralPlus(const S: string): Boolean; static;
    // True wenn JEDES '+' im RHS unmittelbar auf ein String-Literal oder
    // einen Aufruf einer safe-cast-Funktion folgt. Whitelist:
    //   IntToStr, Int64ToStr, FormatInt, GetEnumName  (numerisch)
    //   QuotedStr, QuotedSQL, QuotedStrJSON, SQLVarToText  (escape'd)
    // Dann ist die Konkatenation injection-sicher trotz '+'-Operator.
    // MethodNode wird fuer die lokalen Dataflow-Gates gebraucht (const-
    // derived-Variablen, Format-Masken) und darf nil sein (dann greifen
    // nur die kontextfreien Pruefungen).
    class function AllConcatTermsSafe(MethodNode: TAstNode;
      const RHS: string): Boolean; static;
    // True wenn S ausschliesslich aus String-Literalen, Char-Codes
    // (#13, #$1B), '+'-Konkatenation und Whitespace besteht - also ein
    // zur Compile-Zeit fixer String, den kein Angreifer beeinflussen kann.
    class function IsPureLiteralText(const S: string): Boolean; static;
    // FP-Gate (2026-07-04): const-derived-variable - True wenn der
    // Bezeichner in dieser Routine AUSSCHLIESSLICH aus String-Literalen
    // zugewiesen wird (if/else ueber geschlossene Literalmenge, z.B.
    // lTimestampType := 'DATETIME2'|'DATETIME'|'TIMESTAMP', DMVC
    // activerecord_showcase MainFormU) ODER eine lokale Konstante mit
    // Literal-Wert ist. Solche Werte kann kein externer Input erreichen.
    class function IsConstDerivedLocal(MethodNode: TAstNode;
      const IdentLow: string): Boolean; static;
    // FP-Gate (2026-07-04): int-format-concat - True wenn die Format-
    // Maske ausschliesslich Integer-Platzhalter (%d/%u/%x, inkl. Index/
    // Breite/Praezision wie %0:d, %-8d, %*.2d) enthaelt. Solche Masken
    // koennen nur Ziffern erzeugen - kein Injection-Vektor.
    class function IsIntFormatMask(const Mask: string): Boolean; static;
    // Extrahiert das ERSTE Argument eines Format-Aufrufs (ab der
    // oeffnenden Klammer an Position OpenParen in RHS) und prueft es via
    // IsIntFormatMask. Nur statisch bekannte Masken (reine Literal-/
    // Konkat-Ketten) gelten als sicher; Variablen-Masken -> False.
    class function IsIntOnlyFormatArg(const RHS: string;
      OpenParen: Integer): Boolean; static;
    // FP-Gate (2026-07-04): int-format-concat + const-concat (Format-
    // Familie H3) - True wenn JEDES Element des ERSTEN [..]-Argument-Arrays
    // ab StartAt entweder String-/Zahl-Literal oder ein lokal als Integer
    // deklarierter Bezeichner ist (seit 2026-07-05 auch ORM-Metadaten-
    // Pfade und Quoting-Helfer-Aufrufe; Folge-Arrays = gebundene
    // ?-Parameter werden ignoriert). Integer koennen keine SQL-Syntax
    // injizieren; Literale sind Entwickler-kontrolliert (Seed-INSERTs wie
    // mORMot dmvc-ai server.pas ['ACME', ..., 5]). String-VARIABLEN
    // (RawUtf8-Parameter, api.impl CreateCustomer) bleiben Risiko.
    class function AreFormatArgsInjectionSafe(MethodNode: TAstNode;
      const CallLow: string; StartAt: Integer): Boolean; static;
    class function IsSafeFormatArgElement(MethodNode: TAstNode;
      const ElemLow: string): Boolean; static;
    // FP-Gate (2026-07-05): orm-sql-builder / sql-builder-api - True wenn
    // IdentLow ein bekannter ORM-Schema-Metadaten-Name ist (RTTI-/Mapping-
    // Properties wie SqlTableName/RowIDFieldName/NameUtf8, DMVC
    // TableMap.fTableName/SequenceName). Solche Werte stammen aus Compile-
    // Zeit-Metadaten der ORM-Frameworks, nicht aus externem Input. Bewusst
    // ENGE Whole-Name-Liste aus dem Real-World-Korpus (ORM_META_IDENTS).
    class function IsOrmMetaIdent(const IdentLow: string): Boolean; static;
    // True wenn ElemLow ein reiner Bezeichner-/Member-Pfad ist (a.b^.c,
    // Index-Zugriffe [..] erlaubt, keine Calls/Operatoren) dessen LETZTE
    // Komponente ein ORM-Schema-Metadatum ist - z.B. props.SqlTableName,
    // BlobField^.NameUtf8, Model.TableProps[i].Props.SqlTableName.
    class function IsOrmMetaPath(const ElemLow: string): Boolean; static;
    // True wenn ElemLow ein KOMPLETTER Aufruf eines Quoting-/Escape-/
    // Cast-Helfers ist ('getfieldnameforsql(seq)') - SAFE_CASTS bzw. die
    // quote*/escape*/get*forsql-Konvention (dieselben Regeln wie fuer
    // Konkat-Terme in AllConcatTermsSafe, hier fuer Format-Argumente).
    class function IsSafeSqlHelperCall(const ElemLow: string): Boolean; static;
    // True wenn NameLow der NAME eines Quoting-/Escape-/Cast-Helfers ist:
    // SAFE_CASTS (QuotedStr/...) bzw. die quote*/escape*/get*forsql-Konvention.
    // Zentral fuer bare Calls UND Member-Pfad-Call-Endungen in
    // AllConcatTermsSafe (Recharakterisierung after30 2026-07-12).
    class function IsSafeSqlHelperName(const NameLow: string): Boolean; static;
    // True wenn IdentLow als Parameter/lokale Variable der Routine mit
    // Integer-Typ deklariert ist (Modifier out/var/const werden gestrippt).
    class function IsLocalIntegerIdent(MethodNode: TAstNode;
      const IdentLow: string): Boolean; static;
    class function IsIntTypeName(const TypeLow: string): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, LongMethod, MultipleExit, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Properties/Felder die SQL-Text enthalten. Liste 2026-06-18 erweitert
  // (Audit_ErrorDetectors E-1 P1): Index-Form sql.strings[N] / commandtext.strings[N]
  // war Lücke gegen TStringList-Style-Setup.
  SQL_PROPS: array[0..8] of string = (
    'sql.text', '.sql.', 'commandtext', 'sqltext',
    'sqlcommand', 'query.sql', '.sql:=',
    'sql.strings[', 'commandtext.strings['
  );

  // SQL-DML/DDL-Schlüsselwörter als Stringliteral-Anfang. Quote als erstes
  // Zeichen heisst der Match muss am Literal-Anfang stehen - Doku-Strings
  // wie 'Code: SELECT * ...' bleiben unbeflaggt (kein fuehrendes Quote).
  // 2026-06-18 erweitert (Audit_ErrorDetectors E-1 P1):
  //   * MERGE/TRUNCATE/CREATE/ALTER  - DDL/DML mit gleichem Injection-Vektor
  //   * WITH                          - CTE (Statement startet WITH ... AS SELECT)
  //   * CALL                          - Stored-Procedure-Aufruf
  //   * GRANT/REVOKE                  - DCL, Privilege-Eskalation
  //   * REPLACE                       - MySQL/MariaDB UPSERT-Variante
  SQL_KW: array[0..14] of string = (
    '''select ', '''insert ', '''update ', '''delete ',
    '''exec ',   '''drop ',
    '''merge ',  '''truncate ', '''create ', '''alter ',
    '''with ',   '''call ',
    '''grant ',  '''revoke ',   '''replace '
  );

  // SQL-Aufruf-Methoden die SQL-Text als Argument nehmen. 2026-06-18
  // erweitert um MacroByName().AsRaw fuer TFDQuery-Macros (Audit E-1 P1):
  // Macros werden VOR dem SQL-Parse 1:1 substituiert - gleicher Injection-
  // Vektor wie Concat in SQL.Text.
  SQL_CALL_METHODS: array[0..7] of string = (
    'sql.add(', 'execsql(', 'execquery(', 'execproc(',
    'open(', 'commandtext',
    'macrobyname(', '.asraw'
  );

  // FP-Gate (2026-07-05): orm-sql-builder / sql-builder-api (Real-World-
  // Audit Prio 6). ORM-Schema-Metadaten-Namen: Properties/Felder/Parameter,
  // deren Wert aus Compile-Zeit-Mapping-Metadaten der ORM-Frameworks stammt:
  //   * mORMot TOrmProperties: SqlTableName, SqlTableRetrieveBlobFields,
  //     SqlTableUpdateBlobFields (mormot.orm.sqlite3 RetrieveBlobFields/
  //     UpdateBlobFields, mormot.orm.storage TRestStorage.Create)
  //   * mORMot ExternalDB-Mapping: fTableName, RowIDFieldName,
  //     TableSimpleFields, InsertSet (mormot.orm.sql ComputeSql)
  //   * mORMot RTTI-Props: NameUtf8 (BlobField^.NameUtf8)
  //   * DMVC ActiveRecord: TableMap.fTableName (SQLGenerators.MSSQL),
  //     SequenceName aus [MVCTable]-Attributen (SQLGenerators.PostgreSQL)
  // Match: WHOLE Name der letzten Pfad-Komponente - bewusst eng, damit
  // App-Variablen (code/city/lFilter...) NIE matchen.
  ORM_META_IDENTS: array[0..8] of string = (
    'sqltablename', 'ftablename', 'rowidfieldname',
    'sqltableretrieveblobfields', 'sqltableupdateblobfields',
    'tablesimplefields', 'insertset', 'nameutf8', 'sequencename'
  );

  // Safe-cast-/Escape-Funktionen: Output ist garantiert numerisch bzw.
  // SQL-escaped. Genutzt fuer Konkat-Terme (AllConcatTermsSafe) und seit
  // 2026-07-05 auch fuer komplette Format-Argumente (IsSafeSqlHelperCall);
  // dafuer aus AllConcatTermsSafe hierher gehoben (Liste unveraendert).
  SAFE_CASTS: array[0..7] of string = (
    'inttostr', 'int64tostr', 'formatint', 'getenumname',
    'quotedstr', 'quotedsql', 'quotedstrjson', 'sqlvartotext'
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

function IsScreamingSnakeConst(const S: string): Boolean;
// SCREAMING_SNAKE_CASE-Bezeichner (TEST_TABLE_REFRESHABLE, MAX_ROWS) sind per
// Delphi-Konvention Compile-Zeit-Konstanten - kein extern beeinflussbarer Wert,
// also injection-sicher als Konkat-Term. Verlangt mind. einen Unterstrich +
// ausschliesslich Grossbuchstaben/Ziffern/Unterstriche + mind. einen Buchstaben.
// FP-Klasse 'constant-concat' (Real-World-FP-Audit 2026-07-10, EntGen-Tests).
var
  i : Integer;
  hasUnderscore, hasAlpha : Boolean;
begin
  Result := False;
  if Length(S) < 2 then Exit;
  hasUnderscore := False;
  hasAlpha      := False;
  for i := 1 to Length(S) do
    case S[i] of
      'A'..'Z': hasAlpha := True;
      '0'..'9': ;
      '_':      hasUnderscore := True;
    else
      Exit;  // Kleinbuchstabe/anderes Zeichen -> kein SCREAMING_SNAKE_CASE
    end;
  Result := hasUnderscore and hasAlpha;
end;

function IsWellKnownEolConst(const IdentLow: string): Boolean;
// RTL-/Konvention-EOL-Konstanten (System.sLineBreak, sCRLF, CRLF) sind Compile-
// Zeit-Zeilenumbruch-Strings - kein extern beeinflussbarer Wert -> injection-
// sicher als Konkat-Term ('SELECT ...' + sLineBreak + Indent + ...). Konservativ:
// nur eindeutige Namen; kurze 'cr'/'lf'/'eol' bewusst NICHT (koennten lokale
// Variablen sein). FP-Klasse 'eol-const-concat' (Recharakterisierung after30).
begin
  Result := (IdentLow = 'slinebreak') or (IdentLow = 'scrlf') or
            (IdentLow = 'crlf');
end;

class function TSQLInjectionDetector.IsSafeSqlHelperName(
  const NameLow: string): Boolean;
// Sanitizer-Namenskonvention (DMVC/mORMot): SAFE_CASTS (QuotedStr/QuotedSQL/...)
// bzw. quote*/escape*/get*forsql. NUR der NAME (nicht der volle Call) - fuer
// bare Calls und Member-Pfad-Endungen in AllConcatTermsSafe wiederverwendet.
var
  s : string;
begin
  Result := False;
  if NameLow = '' then Exit;
  for s in SAFE_CASTS do
    if NameLow = s then Exit(True);
  Result := NameLow.StartsWith('quote')
         or NameLow.StartsWith('escape')
         or (NameLow.StartsWith('get') and NameLow.EndsWith('forsql'));
end;

class function TSQLInjectionDetector.AllConcatTermsSafe(MethodNode: TAstNode;
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
//
// SAFE_CASTS steht seit 2026-07-05 im Unit-const-Block (auch von
// IsSafeSqlHelperCall genutzt).
var
  Stripped : string;
  i, j, p  : Integer;
  inStr    : Boolean;
  c        : Char;
  ident    : string;
  IdentOrig: string;
  isSafe   : Boolean;
  LastComp : string;
  PathOk   : Boolean;
  Depth    : Integer;
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
            CharInSet(Stripped[j], ['a'..'z', 'A'..'Z', '_', '0'..'9']) do
        Inc(j);
      ident := LowerCase(Copy(Stripped, p, j - p));
      // Original-Case fuer die SCREAMING_SNAKE-Const-Heuristik (Stripped ist
      // positionsgleich zu RHS, nur ge-lowert / Literale geleert).
      IdentOrig := Copy(RHS, p, j - p);
      if ident = '' then
      begin
        // Position war ein gestripptes Literal -> ok.
        Inc(i);
        Continue;
      end;
      // Identifier vorhanden - muss safe-cast-Funktionsaufruf sein.
      // Pflicht: '(' direkt nach (ggf. Whitespace) dem Identifier.
      while (j <= Length(Stripped)) and (Stripped[j] <= ' ') do Inc(j);
      // FP-Gate (2026-07-05): orm-sql-builder / sql-builder-api - Member-
      // Pfad hinter '+', dessen LETZTE Komponente ein ORM-Schema-Metadatum
      // ist ('select rowid from ' + Table.SqlTableName, mormot.orm.sqlite3
      // TableMaxID; 'INSERT INTO ' + TableMap.fTableName, DMVC
      // SQLGenerators.MSSQL). Metadaten stammen aus Compile-Zeit-Mapping,
      // kein externer Input. Pfad ohne Metadaten-Endung bleibt unsicher.
      if (j <= Length(Stripped)) and CharInSet(Stripped[j], ['.', '^', '[']) then
      begin
        LastComp := ident;
        PathOk   := True;
        while (j <= Length(Stripped)) and PathOk do
        begin
          case Stripped[j] of
            '^':
              Inc(j);
            '.':
              begin
                Inc(j);
                p := j;
                while (j <= Length(Stripped)) and
                      CharInSet(Stripped[j], ['a'..'z', '0'..'9', '_']) do
                  Inc(j);
                if j = p then
                  PathOk := False // '.' ohne Identifier -> kein Member-Pfad
                else
                  LastComp := Copy(Stripped, p, j - p);
              end;
            '[':
              begin
                // Index-Zugriff: Inhalt irrelevant (der SELEKTIERTE Wert
                // bleibt das durch den Property-Namen bestimmte Metadatum),
                // nur balanciert konsumieren.
                Depth := 1;
                Inc(j);
                while (j <= Length(Stripped)) and (Depth > 0) do
                begin
                  if Stripped[j] = '[' then
                    Inc(Depth)
                  else if Stripped[j] = ']' then
                    Dec(Depth);
                  Inc(j);
                end;
                if Depth > 0 then
                  PathOk := False; // unbalanciert -> unklar, kein Gate
              end;
          else
            Break; // Pfad-Ende (Whitespace/Operator/Klammer)
          end;
        end;
        if PathOk and IsOrmMetaIdent(LastComp) then
        begin
          i := j; // Pfad (inkl. Index-Inhalt) ueberspringen
          Continue;
        end;
        // Kein Metadaten-Pfad: wie vor 2026-07-05 zaehlt der FUEHRENDE
        // Identifier - const-derived-Gate (2026-07-04) bleibt fuer Formen
        // wie lVar[i] / lVar.ToLower einer Literal-Variablen erhalten.
        if PathOk and IsConstDerivedLocal(MethodNode, ident) then
        begin
          i := j;
          Continue;
        end;
        // Recharakterisierung after30 (2026-07-12): Sanitizer-Helfer-CALL als
        // LETZTE Pfad-Komponente (Conn.QuoteIdent(x) / Obj.GetTableNameForSQL(..))
        // ist ebenso sicher wie ein barer Sanitizer-Call (unten) - der Helfer
        // escaped den Input. Pflicht: '(' folgt direkt -> Aufruf, keine Property.
        // TP-Risiko identisch zur bereits vertrauten bare-Call-Konvention.
        if PathOk and (j <= Length(Stripped)) and (Stripped[j] = '(')
           and IsSafeSqlHelperName(LastComp) then
        begin
          i := j;
          Continue;
        end;
        Exit(False); // Member-Pfad ohne Metadaten-Endung -> unsicher
      end;
      if (j > Length(Stripped)) or (Stripped[j] <> '(') then
      begin
        // FP-Gate (2026-07-04): const-derived-variable - bare Identifier
        // ist doch sicher, wenn er in dieser Routine ausschliesslich aus
        // String-Literalen zugewiesen wird bzw. lokale Literal-Konstante
        // ist (geschlossene Wertemenge, kein externer Input erreichbar).
        // FP-Gate (2026-07-05): orm-sql-builder - ODER der Identifier ist
        // ein bares ORM-Schema-Metadatum (with-Scope: 'FROM ' + SqlTableName).
        // FP-Gate (Recharakterisierung after30 2026-07-13): ODER eine bekannte
        // EOL-Konstante (sLineBreak/CRLF) - Compile-Zeit-Zeilenumbruch, kein Input.
        if not (IsConstDerivedLocal(MethodNode, ident)
                or IsOrmMetaIdent(ident)
                or IsWellKnownEolConst(ident)
                or IsScreamingSnakeConst(IdentOrig)) then
          Exit(False); // bare Identifier -> Variable, unsicher
        Inc(i);
        Continue;
      end;
      // SAFE_CASTS bzw. Schema-Sanitizer-Konvention (Get<X>ForSql / Quote<X> /
      // Escape<X>) - DMVC/mORMot Schema-Builder, kein User-Input-Concat. Seit
      // 2026-07-12 in IsSafeSqlHelperName zentralisiert (verhaltensidentisch,
      // auch vom Member-Pfad-Zweig oben genutzt).
      isSafe := IsSafeSqlHelperName(ident);
      // FP-Gate (2026-07-04): int-format-concat - Format(...) dessen Maske
      // nur Integer-Platzhalter (%d/%u/%x) traegt, kann nur Ziffern
      // erzeugen (DMVC PeopleModuleU: 'ORDER BY ... ' +
      // Format('ROWS %d to %d', [StartRec, EndRec])) -> injection-sicher.
      // Stripped ist positionsgleich zu RHS, j zeigt auf das '(' des Calls.
      if (not isSafe) and (ident = 'format') then
        isSafe := IsIntOnlyFormatArg(RHS, j);
      if not isSafe then Exit(False); // andere Funktion -> unsicher
    end;
    Inc(i);
  end;
  Result := True;
end;

class function TSQLInjectionDetector.IsPureLiteralText(
  const S: string): Boolean;
// True wenn S nur aus String-Literalen, Char-Codes (#13 / #$1B), '+' und
// Whitespace besteht. Bezeichner, Aufrufe oder andere Operatoren -> False.
var
  i, L : Integer;
  c    : Char;
begin
  Result := False;
  L := Length(S);
  i := 1;
  while i <= L do
  begin
    c := S[i];
    if c = '''' then
    begin
      // String-Literal bis zum schliessenden Quote konsumieren ('' = Escape).
      Inc(i);
      while i <= L do
      begin
        if S[i] = '''' then
        begin
          if (i < L) and (S[i + 1] = '''') then
            Inc(i, 2)
          else
            Break;
        end
        else
          Inc(i);
      end;
      if i > L then Exit; // unterminiertes Literal -> unklar, kein Gate
      Inc(i);             // schliessendes Quote
    end
    else if c = '#' then
    begin
      Inc(i);
      if (i <= L) and (S[i] = '$') then Inc(i);
      while (i <= L) and CharInSet(S[i], ['0'..'9', 'a'..'f', 'A'..'F']) do
        Inc(i);
    end
    else if (c = '+') or (c <= ' ') then
      Inc(i)
    else
      Exit; // Bezeichner/Call/sonstiger Operator -> nicht rein literal
  end;
  Result := True;
end;

class function TSQLInjectionDetector.IsConstDerivedLocal(MethodNode: TAstNode;
  const IdentLow: string): Boolean;
// FP-Gate (2026-07-04): const-derived-variable (Real-World-Audit 3.1).
// Lokaler Definitions-Walk: sind ALLE Zuweisungen an den Bezeichner in
// dieser Routine reine Literal-Expressions (bzw. ist er eine lokale
// Konstante mit Literal-Wert), kann kein Angreifer den Wert beeinflussen
// -> die Konkatenation ist injection-sicher. Konservativ: eine einzige
// nicht-literale Zuweisung (oder gar keine sichtbare Definition, z.B.
// Parameter/Feld) schaltet das Gate ab.
var
  Nodes : TList<TAstNode>;
  N     : TAstNode;
  Sec   : TAstNode;
  i     : Integer;
  Found : Boolean;
  eqPos : Integer;
begin
  Result := False;
  if (MethodNode = nil) or (IdentLow = '') then Exit;
  Found := False;

  // 1) Lokale const-Deklaration mit Literal-Wert. Der Parser emittiert
  //    nkConstSection mit nkField-Kindern, TypeRef = 'TypeName=Wert' bzw.
  //    '=Wert' (s. ParseVarLikeSection / uFormatMismatch-Konsument).
  Nodes := MethodNode.FindAll(nkConstSection);
  try
    for Sec in Nodes do
      for i := 0 to Sec.Children.Count - 1 do
      begin
        N := Sec.Children[i];
        if N.Kind <> nkField then Continue;
        if not SameText(Trim(N.Name), IdentLow) then Continue;
        eqPos := Pos('=', N.TypeRef);
        if (eqPos > 0)
           and IsPureLiteralText(Copy(N.TypeRef, eqPos + 1, MaxInt)) then
          Found := True
        else
          Exit; // Konstante mit nicht-literalem/unbekanntem Wert
      end;
  finally
    Nodes.Free;
  end;

  // 2) Alle Zuweisungen an den Bezeichner muessen reine Literal-RHS sein
  //    (if/else ueber geschlossene Literalmenge zaehlt: jede Branch-
  //    Zuweisung ist ein eigener nkAssign-Knoten).
  Nodes := MethodNode.FindAll(nkAssign);
  try
    for N in Nodes do
    begin
      if not SameText(Trim(N.Name), IdentLow) then Continue;
      if not IsPureLiteralText(N.TypeRef) then
        Exit; // mind. eine nicht-literale Zuweisung -> Gate greift nicht
      Found := True;
    end;
  finally
    Nodes.Free;
  end;

  Result := Found;
end;

class function TSQLInjectionDetector.IsOrmMetaIdent(
  const IdentLow: string): Boolean;
// FP-Gate (2026-07-05): orm-sql-builder / sql-builder-api - WHOLE-Name-
// Match gegen die enge Korpus-Liste ORM_META_IDENTS (s. const-Block).
var
  S : string;
begin
  Result := False;
  for S in ORM_META_IDENTS do
    if IdentLow = S then
      Exit(True);
end;

class function TSQLInjectionDetector.IsOrmMetaPath(
  const ElemLow: string): Boolean;
// FP-Gate (2026-07-05): orm-sql-builder / sql-builder-api - Format-Argument
// als reiner Bezeichner-/Member-Pfad: fuehrender Identifier, danach nur
// '.'-Member, '^'-Deref und balancierte [..]-Indizes. Die LETZTE Komponente
// entscheidet (props.SqlTableName, BlobField^.NameUtf8,
// Model.TableProps[i].Props.SqlTableName). Alles andere (Calls, Operatoren,
// Whitespace auf Top-Level) -> False, Fund bleibt.
var
  i, L, p : Integer;
  Depth   : Integer;
  LastComp: string;
begin
  Result := False;
  L := Length(ElemLow);
  if (L = 0) or not CharInSet(ElemLow[1], ['a'..'z', '_']) then Exit;
  i := 1;
  p := i;
  while (i <= L) and CharInSet(ElemLow[i], ['a'..'z', '0'..'9', '_']) do
    Inc(i);
  LastComp := Copy(ElemLow, p, i - p);
  while i <= L do
  begin
    case ElemLow[i] of
      '^':
        Inc(i);
      '.':
        begin
          Inc(i);
          p := i;
          while (i <= L) and
                CharInSet(ElemLow[i], ['a'..'z', '0'..'9', '_']) do
            Inc(i);
          if i = p then Exit; // '.' ohne Identifier -> kein Member-Pfad
          LastComp := Copy(ElemLow, p, i - p);
        end;
      '[':
        begin
          // Index-Inhalt irrelevant (Property-Name bestimmt den Wert),
          // nur balanciert konsumieren.
          Depth := 1;
          Inc(i);
          while (i <= L) and (Depth > 0) do
          begin
            if ElemLow[i] = '[' then
              Inc(Depth)
            else if ElemLow[i] = ']' then
              Dec(Depth);
            Inc(i);
          end;
          if Depth > 0 then Exit; // unbalanciert -> unklar, kein Gate
        end;
    else
      Exit; // Operator/Call/Whitespace -> kein reiner Member-Pfad
    end;
  end;
  Result := IsOrmMetaIdent(LastComp);
end;

class function TSQLInjectionDetector.IsSafeSqlHelperCall(
  const ElemLow: string): Boolean;
// FP-Gate (2026-07-05): sql-builder-api - Format-Argument ist KOMPLETT ein
// Aufruf eines Quoting-/Escape-/Cast-Helfers, z.B. DMVC SQLGenerators
// Format('SELECT %s.NEXTVAL...', [GetFieldNameForSQL(SequenceName), ...]).
// Der Helfer sanitisiert beliebigen Input -> Argumentinhalt irrelevant
// (gleiche Konvention wie fuer Konkat-Terme in AllConcatTermsSafe:
// SAFE_CASTS bzw. quote*/escape*/get*forsql).
var
  i, L, j : Integer;
  Depth   : Integer;
  InStr   : Boolean;
  ident   : string;
  S       : string;
begin
  Result := False;
  L := Length(ElemLow);
  i := 1;
  while (i <= L) and CharInSet(ElemLow[i], ['a'..'z', '0'..'9', '_']) do
    Inc(i);
  ident := Copy(ElemLow, 1, i - 1);
  if (ident = '') or (i > L) or (ElemLow[i] <> '(')
     or (ElemLow[L] <> ')') then
    Exit;
  // Review-Fix (2026-07-05, tp-loss): die schliessende Klammer am Element-
  // Ende muss die des HELFER-Aufrufs sein. Ohne Balance-Check galt auch
  // 'quotedstr(a) + userinput + inttostr(b)' als komplett-safe, weil das
  // Element mit 'quotedstr(' beginnt und zufaellig auf ')' endet.
  // Depth-Scan (string-aware): faellt die Tiefe VOR dem letzten Zeichen
  // auf 0, folgt nach dem Helfer-Call noch etwas -> kein reiner Call.
  Depth := 0;
  InStr := False;
  for j := i to L do
  begin
    if ElemLow[j] = '''' then InStr := not InStr;
    if InStr then Continue;
    if ElemLow[j] = '(' then Inc(Depth)
    else if ElemLow[j] = ')' then
    begin
      Dec(Depth);
      if (Depth = 0) and (j < L) then Exit;   // Call endet vor Element-Ende
    end;
  end;
  if Depth <> 0 then Exit;                    // unbalanciert -> nicht safe
  for S in SAFE_CASTS do
    if ident = S then
      Exit(True);
  Result := ident.StartsWith('quote')
    or ident.StartsWith('escape')
    or (ident.StartsWith('get') and ident.EndsWith('forsql'));
end;

class function TSQLInjectionDetector.IsIntFormatMask(
  const Mask: string): Boolean;
// FP-Gate (2026-07-04): int-format-concat - Maske mit ausschliesslich
// %d/%u/%x-Platzhaltern (inkl. Index-/Breiten-/Praezisions-Spezifikation)
// kann nur Ziffern/Hex-Ziffern erzeugen. '%%' ist Escape (fixes '%').
// Bare '%' (mORMot FormatUtf8-Generic) oder %s/%f/%g etc. -> False.
var
  i, L : Integer;
begin
  Result := False;
  L := Length(Mask);
  i := 1;
  while i <= L do
  begin
    if Mask[i] = '%' then
    begin
      Inc(i);
      if i > L then Exit; // '%' am Maskenende -> unklar
      if Mask[i] = '%' then
      begin
        Inc(i);
        Continue; // '%%' -> literales Prozentzeichen
      end;
      // Index/Breite/Praezision: [0-9 : - . *]
      while (i <= L) and CharInSet(Mask[i], ['0'..'9', ':', '-', '.', '*']) do
        Inc(i);
      if i > L then Exit;
      if not CharInSet(Mask[i], ['d', 'D', 'u', 'U', 'x', 'X']) then Exit;
      Inc(i);
    end
    else
      Inc(i);
  end;
  Result := True;
end;

class function TSQLInjectionDetector.IsIntOnlyFormatArg(const RHS: string;
  OpenParen: Integer): Boolean;
// Sammelt das ERSTE Argument des Format-Aufrufs (Literal-Konkat-Kette) ab
// der oeffnenden Klammer ein und prueft es via IsIntFormatMask. Sobald ein
// Nicht-Literal-Anteil (Variable, Call) in der Maske steckt, ist sie nicht
// statisch bekannt -> False (konservativ, Fund bleibt).
var
  i     : Integer;
  inStr : Boolean;
  Mask  : string;
  c     : Char;
begin
  Result := False;
  if (OpenParen < 1) or (OpenParen > Length(RHS))
     or (RHS[OpenParen] <> '(') then Exit;
  Mask  := '';
  inStr := False;
  i := OpenParen + 1;
  while i <= Length(RHS) do
  begin
    c := RHS[i];
    if inStr then
    begin
      if c = '''' then
      begin
        if (i < Length(RHS)) and (RHS[i + 1] = '''') then
        begin
          Mask := Mask + '''';
          Inc(i, 2);
          Continue;
        end;
        inStr := False;
      end
      else
        Mask := Mask + c;
    end
    else if c = '''' then
      inStr := True
    else if (c = ',') or (c = ')') then
      Break // Ende des ersten Arguments
    else if c = '#' then
    begin
      // Char-Code-Literal (#13, #$1B): fester Text, platzhalter-neutral.
      Inc(i);
      if (i <= Length(RHS)) and (RHS[i] = '$') then Inc(i);
      while (i <= Length(RHS))
            and CharInSet(RHS[i], ['0'..'9', 'a'..'f', 'A'..'F']) do
        Inc(i);
      Continue;
    end
    else if (c <> '+') and (c > ' ') then
      Exit; // Nicht-Literal-Anteil -> Maske nicht statisch bekannt
    Inc(i);
  end;
  Result := (Mask <> '') and IsIntFormatMask(Mask);
end;

class function TSQLInjectionDetector.IsIntTypeName(
  const TypeLow: string): Boolean;
// Integer-artige Typnamen (inkl. mORMot TID = Int64-Alias). Bewusst nur
// exakte Matches - 'TMyIntegerList' o.ae. darf NICHT als Integer gelten.
begin
  Result :=
    (TypeLow = 'integer') or (TypeLow = 'cardinal') or
    (TypeLow = 'int64') or (TypeLow = 'longint') or
    (TypeLow = 'longword') or (TypeLow = 'smallint') or
    (TypeLow = 'shortint') or (TypeLow = 'byte') or
    (TypeLow = 'word') or (TypeLow = 'nativeint') or
    (TypeLow = 'nativeuint') or (TypeLow = 'uint64') or
    (TypeLow = 'uint32') or (TypeLow = 'int32') or
    (TypeLow = 'dword') or (TypeLow = 'tid') or
    (TypeLow = 'ptrint') or (TypeLow = 'ptruint');
end;

class function TSQLInjectionDetector.IsLocalIntegerIdent(
  MethodNode: TAstNode; const IdentLow: string): Boolean;
// Loest IdentLow gegen die Parameter-/LocalVar-Deklarationen der Routine
// auf. Nicht gefunden oder Nicht-Integer-Typ -> False (konservativ).
var
  Lst     : TList<TAstNode>;
  N       : TAstNode;
  NameLow : string;
  Kind    : TNodeKind;
begin
  Result := False;
  if (MethodNode = nil) or (IdentLow = '') then Exit;
  for Kind in [nkParam, nkLocalVar] do
  begin
    Lst := MethodNode.FindAll(Kind);
    try
      for N in Lst do
      begin
        NameLow := N.Name.ToLower;
        // Parameter-Modifier abstreifen ('const code' -> 'code')
        for var Mod_ in ['out ', 'var ', 'const '] do
          if NameLow.StartsWith(Mod_) then
            NameLow := Copy(NameLow, Length(Mod_) + 1, MaxInt);
        if Trim(NameLow) = IdentLow then
          Exit(IsIntTypeName(Trim(N.TypeRef.ToLower)));
      end;
    finally
      Lst.Free;
    end;
  end;
end;

class function TSQLInjectionDetector.IsSafeFormatArgElement(
  MethodNode: TAstNode; const ElemLow: string): Boolean;
// Element eines Format-Argument-Arrays (lowercase, getrimmt):
//   * String-/Char-Literal  -> sicher (Entwickler-kontrolliert, Seed-Daten)
//   * Zahlen-Literal        -> sicher (nur Ziffern im Output)
//   * true/false            -> sicher
//   * reiner Bezeichner     -> nur sicher wenn lokal als Integer deklariert
//   * alles andere (Calls, Member-Zugriffe, Ausdruecke) -> unsicher
var
  i : Integer;
begin
  Result := False;
  if ElemLow = '' then Exit(True); // leeres Array [] ist trivial sicher

  if (ElemLow[1] = '''') or (ElemLow[1] = '#') then
    Exit(IsPureLiteralText(ElemLow));

  if CharInSet(ElemLow[1], ['0'..'9', '-', '$']) then
  begin
    for i := 2 to Length(ElemLow) do
      if not CharInSet(ElemLow[i], ['0'..'9', '.', '$', '+', '-',
                                    'a'..'f', 'x']) then
        Exit;
    Exit(True);
  end;

  if (ElemLow = 'true') or (ElemLow = 'false') then Exit(True);

  // FP-Gate (2026-07-05): sql-builder-api - kompletter Quoting-/Escape-
  // Helfer-Aufruf als Element (GetFieldNameForSQL(Seq), QuotedStr(x)).
  if IsSafeSqlHelperCall(ElemLow) then Exit(True);
  // FP-Gate (2026-07-05): orm-sql-builder / sql-builder-api - Bezeichner/
  // Member-Pfad dessen letzte Komponente ein ORM-Schema-Metadatum ist
  // (props.SqlTableName, BlobField^.NameUtf8, bare SqlTableName im
  // with-Scope). Enge Whole-Name-Liste, s. ORM_META_IDENTS.
  if IsOrmMetaPath(ElemLow) then Exit(True);

  for i := 1 to Length(ElemLow) do
    if not CharInSet(ElemLow[i], ['a'..'z', '0'..'9', '_']) then Exit;
  Result := IsLocalIntegerIdent(MethodNode, ElemLow);
end;

class function TSQLInjectionDetector.AreFormatArgsInjectionSafe(
  MethodNode: TAstNode; const CallLow: string; StartAt: Integer): Boolean;
// FP-Gate (2026-07-04): int-format-concat / const-concat fuer die Format-
// Familie (H3): scannt ab StartAt (hinter dem '(' der Format-Funktion)
// das ERSTE [..]-Argument-Array und prueft jedes Element via
// IsSafeFormatArgElement. Kein Array gefunden -> False (Fund bleibt).
// Seit 2026-07-05 (sql-builder-api) werden Folge-Arrays ignoriert -
// FormatSql(Fmt, Args, Params)-Params sind gebundene ?-Parameter.
var
  i, L     : Integer;
  inStr    : Boolean;
  Depth    : Integer;
  IdxDepth : Integer;
  Elem     : string;
  FoundArr : Boolean;
  InArr    : Boolean;
  c        : Char;

  // Review-Fix (2026-07-05, tp-loss): '[' zaehlt nur dann als Beginn des
  // Argument-Arrays, wenn das letzte Nicht-Whitespace-Zeichen davor '('
  // oder ',' ist (Scan-Beginn zaehlt als '('). Alles andere - z.B.
  // 'Tables[i]' in einer konkat-gebauten Maske - ist ein INDEX-Ausdruck;
  // der wurde vorher faelschlich als Args-Array konsumiert, wodurch der
  // Folge-Array-Break das ECHTE [..]-Array nie mehr prueft (Fund weg).
  function IsArgsArrayStart(APos: Integer): Boolean;
  var
    k: Integer;
  begin
    k := APos - 1;
    while (k >= StartAt) and CharInSet(CallLow[k], [' ', #9]) do
      Dec(k);
    Result := (k < StartAt) or CharInSet(CallLow[k], ['(', ',']);
  end;

  function FlushElem: Boolean;
  begin
    Result := IsSafeFormatArgElement(MethodNode, Trim(Elem));
    Elem := '';
  end;

begin
  Result := False;
  L := Length(CallLow);
  if (StartAt < 1) or (StartAt > L) then Exit;
  inStr    := False;
  InArr    := False;
  Depth    := 0;
  IdxDepth := 0;
  FoundArr := False;
  Elem     := '';
  i := StartAt;
  while i <= L do
  begin
    c := CallLow[i];
    if inStr then
    begin
      // ''-Escape toggelt zweimal - fuer das Scannen unschaedlich.
      if c = '''' then inStr := False;
      if InArr then Elem := Elem + c;
      Inc(i);
      Continue;
    end;
    if IdxDepth > 0 then
    begin
      // Index-Ausdruck (kein Args-Array) balanciert ueberspringen.
      case c of
        '''': inStr := True;
        '[' : Inc(IdxDepth);
        ']' : Dec(IdxDepth);
      end;
      Inc(i);
      Continue;
    end;
    case c of
      '''':
        begin
          inStr := True;
          if InArr then Elem := Elem + c;
        end;
      '[':
        if not InArr then
        begin
          if IsArgsArrayStart(i) then
          begin
            InArr    := True;
            FoundArr := True;
            Depth    := 0;
            Elem     := '';
          end
          else
            IdxDepth := 1;   // z.B. Tables[i] im Masken-Konkat
        end
        else
        begin
          Inc(Depth);
          Elem := Elem + c;
        end;
      ']':
        if InArr then
        begin
          if Depth > 0 then
          begin
            Dec(Depth);
            Elem := Elem + c;
          end
          else
          begin
            if (Trim(Elem) <> '') and (not FlushElem) then Exit;
            // Elem/InArr-Reset hier entfernt: FlushElem leert Elem bereits und
            // das folgende Break beendet die Schleife -> tote Zuweisungen (H2077).
            // FP-Gate (2026-07-05): sql-builder-api - nur das ERSTE
            // [..]-Array traegt %-Substitutions-Argumente; Folge-Arrays
            // der mORMot-APIs (FormatSql(Fmt, Args, Params) in
            // mormot.orm.sqlite3 RetrieveBlobFields) sind gebundene
            // ?-Parameter und landen NIE im SQL-Text.
            Break;
          end;
        end;
      '(':
        if InArr then
        begin
          Inc(Depth);
          Elem := Elem + c;
        end;
      ')':
        if InArr then
        begin
          if Depth > 0 then Dec(Depth);
          Elem := Elem + c;
        end;
      ',':
        if InArr then
        begin
          if Depth = 0 then
          begin
            if not FlushElem then Exit;
          end
          else
            Elem := Elem + c;
        end;
    else
      if InArr then Elem := Elem + c;
    end;
    Inc(i);
  end;
  Result := FoundArr;
end;

class function TSQLInjectionDetector.IsNonSqlSink(const Text: string): Boolean;
// Real-World 2026-06-26: 10 FPs durch SQL-Verb-Prosa in Nicht-SQL-Aufrufen
// (cnwizards CnDebugger.LogMsg('Update Feed...'), ShowMessage(Format('Create
// %d...')), ALWebSpider StatusBar2.Panels[0].Text := 'Update Href...').
// SINK_NAMES per WholeWord (callee-Identifier), SINK_TOKENS per Substring
// (haben natuerliche Grenzen '.'/'[' bzw. matchen 'StatusBar2').
const
  SINK_NAMES : array[0..15] of string = (
    'logmsg', 'logmsgerror', 'logmsgwarning', 'logfmt',
    'logwarning', 'logerror', 'loginfo', 'logdebug',
    'showmessage', 'showmessagefmt', 'messagedlg', 'messagebox',
    'outputdebugstring', 'writeln', 'codesite', 'raise'
  );
  SINK_TOKENS : array[0..3] of string = (
    '.caption', '.hint', 'statusbar', '.panels['
  );
var
  Low : string;
  S   : string;
begin
  Result := True;
  Low := Text.ToLower;
  for S in SINK_NAMES do
    if TDetectorUtils.ContainsWholeWordLower(S, Low) then Exit;
  for S in SINK_TOKENS do
    if Pos(S, Low) > 0 then Exit;
  Result := False;
end;

class function TSQLInjectionDetector.IsAssignRisk(MethodNode: TAstNode;
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
  if AllConcatTermsSafe(MethodNode, RHS) then Exit;

  // H1: bekannte SQL-Property im Ziel-Namen.
  // Wortgrenzen-Pruefung: 'commandtext' soll nicht 'mycommandtextra' matchen.
  // Patterns mit '.'/':' enthalten haben durch die Trennzeichen schon natuerliche
  // Grenzen, fuer die anderen brauchen wir den WholeWord-Helper.
  for Kw in SQL_PROPS do
    if TDetectorUtils.ContainsWholeWordLower(Kw, NameLow) then Exit(True);

  // H2: SQL-Schlüsselwort als ERSTES Literal im RHS (Position 1).
  // Nur wenn der RHS direkt mit dem SQL-Keyword beginnt – verhindert
  // false positives wenn SQL-Code als Dokumentations-String vorkommt.
  // Prosa-Gate: 'Create file '/'Delete directory ' = englische Prosa, kein
  // SQL (jcl makedist FP, s. IsKeywordProse).
  for Kw in SQL_KW do
    if (Pos(Kw, RHSLow) = 1) and not IsKeywordProse(RHSLow, Kw, 1) then
      Exit(True);
end;

class function TSQLInjectionDetector.IsKeywordProse(const Hay, Kw: string;
  KwPos: Integer): Boolean;
// Hay ist lower-case. Kw = getroffenes SQL_KW inkl. fuehrendem Quote
// ('''create '). KwPos = 1-basierte Pos von Kw in Hay (zeigt auf das Quote).
const
  OBJ_KW : array[0..27] of string = (
    'table', 'view', 'index', 'database', 'schema', 'procedure', 'proc',
    'function', 'trigger', 'sequence', 'domain', 'role', 'user', 'type',
    'tablespace', 'synonym', 'package', 'event', 'aggregate', 'operator',
    'column', 'constraint', 'temporary', 'temp', 'unique', 'materialized',
    'global', 'from'
  );
var
  i, p    : Integer;
  RestLit : string;
  Lead    : string;
  FirstW  : string;
  Obj     : string;
begin
  Result := False;
  // Nur prosa-prone Verben gaten - alle anderen unveraendert als SQL werten.
  if not ((Kw = '''create ') or (Kw = '''drop ') or (Kw = '''alter ')
       or (Kw = '''truncate ') or (Kw = '''delete ') or (Kw = '''update ')
       or (Kw = '''with ')) then
    Exit;

  // Rest des aktuellen String-Literals nach dem Verb (bis schliessendem ').
  i := KwPos + Length(Kw);
  p := i;
  while (i <= Length(Hay)) and (Hay[i] <> '''') do Inc(i);
  RestLit := Copy(Hay, p, i - p);

  Lead := TrimLeft(RestLit);
  // Verb war letztes Literal-Token ('CREATE ' + x) -> echtes SQL (Concat-Risk).
  if Lead = '' then Exit;
  // Direkt %-Placeholder ('CREATE %INDEX ...', mORMot FormatUtf8) -> SQL.
  if Lead[1] = '%' then Exit;

  // Verb-spezifische rigide Fortsetzung.
  if Kw = '''with ' then
  begin
    // CTE: WITH <name> AS ( ... ). Ohne ' as '/' as(' -> Prosa ('with spaces').
    if (Pos(' as ', ' ' + RestLit + ' ') > 0)
       or (Pos(' as(', ' ' + RestLit) > 0) then Exit;
    Exit(True);
  end;
  if Kw = '''update ' then
  begin
    // UPDATE <table> SET ... Ohne ' set ' -> Prosa ('update one field ...').
    if Pos(' set ', ' ' + RestLit + ' ') > 0 then Exit;
    Exit(True);
  end;

  // create/drop/alter/truncate/delete: erstes Wort muss SQL-Objekt-Keyword
  // sein (delete -> 'from' ist enthalten). Sonst Prosa ('Create file ').
  p := 1;
  while (p <= Length(Lead))
        and CharInSet(Lead[p], ['a'..'z', '0'..'9', '_']) do Inc(p);
  FirstW := Copy(Lead, 1, p - 1);
  for Obj in OBJ_KW do
    if FirstW = Obj then Exit;
  Result := True;
end;

class function TSQLInjectionDetector.HasSqlKwHit(const Hay: string): Boolean;
var
  Kw : string;
  P  : Integer;
begin
  Result := False;
  for Kw in SQL_KW do
  begin
    P := Pos(Kw, Hay);
    if P <= 0 then Continue;
    // Sonder-Gate 'call': Windows-Batch  call "pfad"  ist KEIN SQL. Signal:
    // direkt auf 'call ' folgt " (SQL nutzt fuer Werte '...' nie "..."). Echtes
    // SQL  CALL proc  (Identifier folgt) / 'call '+proc bleiben erkannt.
    if (Kw = '''call ') and (P + Length(Kw) <= Length(Hay))
       and (Hay[P + Length(Kw)] = '"') then
      Continue;
    // Prosa-Gate: 'Create file '/'Delete directory '/'with spaces'/'update
    // one field' sind englische Saetze, kein SQL (s. IsKeywordProse).
    if IsKeywordProse(Hay, Kw, P) then Continue;
    Exit(True);
  end;
end;

class function TSQLInjectionDetector.IsCallRisk(MethodNode: TAstNode;
  const CallName: string): Boolean;
var
  Low      : string;
  LowNoLit : string;
  Kw       : string;
begin
  Result := False;
  Low    := CallName.ToLower;

  // Konkatenation muss ausserhalb Literalen sein (s. IsAssignRisk).
  if not HasNonLiteralPlus(CallName) then Exit;

  // Whitelist: alle Konkat-Terme sind String-Literale oder safe-cast-Calls
  // (IntToStr, QuotedStr, ...) -> injection-sicher trotz '+'.
  if AllConcatTermsSafe(MethodNode, CallName) then Exit;

  // SQL-Aufruf-Methode im Call-Namen. Patterns enden auf '(' was natuerliche
  // rechte Grenze ist; links muss aber Wortgrenze her - 'open(' soll nicht
  // 'reopen(' matchen. Match auf String-Literal-BEFREITEM Text: eine echte
  // Methode steht nie IN einem Literal. Sonst matcht z.B. Dev-Cpp
  // RegisterDDEServer(...,'[Open("%1")]') faelschlich 'open(' im DDE-Kommando.
  LowNoLit := TDetectorUtils.StripStringLiterals(CallName).ToLower;
  for Kw in SQL_CALL_METHODS do
    if TDetectorUtils.ContainsWholeWordLower(Kw, LowNoLit) then Exit(True);

  // Keyword-Substring-Zweig: faengt SQL-Builder OHNE bekannte Exec-Methode
  // (z.B. Alcinoe SelectData('SELECT '+...)). ABER Log-/UI-Aufrufe tragen
  // dieselben fuehrenden Verben -> Nicht-SQL-Senke hier ausschliessen
  // (LogMsg/ShowMessage/...). Der Exec-Methoden-Zweig oben bleibt ungated,
  // damit ein echtes ExecSQL mit Sink-Wort im Text nicht verloren geht.
  if IsNonSqlSink(CallName) then Exit;
  // SQL-Schlüsselwort als Stringliteral im Argument (Patterns mit fuehrendem '
  // sind selbst-abgrenzend, brauchen kein WholeWord). 'call'-Sonder-Gate s.
  // HasSqlKwHit (Batch call "pfad" != SQL).
  if HasSqlKwHit(Low) then Exit(True);
end;

class function TSQLInjectionDetector.IsFormatSqlRisk(MethodNode: TAstNode;
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
  FnIdx : Integer;
begin
  Result := False;
  // Nicht-SQL-Senke (ShowMessage(Format('Create %d ...')), LogFmt(...)) raus:
  // gleiche Verb-Prosa-Kollision wie im Keyword-Zweig.
  if IsNonSqlSink(CallName) then Exit;
  Low := CallName.ToLower;
  for Fn in FORMAT_FNS do
  begin
    FnIdx := Pos(Fn, Low);
    if FnIdx <= 0 then Continue;
    // Argument-Bereich = alles nach dem '(' der Format-Funktion
    var ArgsLow := Copy(Low, FnIdx + Length(Fn), MaxInt);
    // Mindestens ein SQL-Keyword als Literal PLUS ein '%' (Placeholder; ohne ->
    // statischer SQL-String ohne Substitution -> kein Risiko). 'call'-Sonder-
    // Gate (Batch call "pfad" != SQL) s. HasSqlKwHit.
    if HasSqlKwHit(ArgsLow) and (Pos('%', ArgsLow) > 0) then
    begin
      // FP-Gate (2026-07-05): orm-sql-builder - mORMot-Inline-Binding: das
      // Muster ':(%):' im Format-Literal kennzeichnet Werte, die von
      // ExtractInlineParameters als GEBUNDENE Parameter extrahiert werden
      // ('UPDATE % SET %=:(%): WHERE RowID=:(%):', mormot.orm.sqlite3
      // MainEngineUpdateField u.v.a.); die uebrigen %-Platzhalter dieser
      // Framework-Statements sind RTTI-Tabellen-/Feldnamen (vertrauenswuerdig).
      // Bewusst PAUSCHAL (jeder ':(%):'-Site gated den Call): ein bare '%'
      // fuer einen RawUtf8-Feldnamen ist lexikalisch NICHT von einem rohen
      // User-Wert unterscheidbar - eine positionale Auswertung erzeugte FPs
      // auf legitimem ORM-Code (Test SQL_ExecuteFmtInlineBoundValue). Rohe
      // %-Substitution OHNE ':(...):' (api.impl.pas CreateCustomer/Update-
      // Customer, echter Korpus-TP) bleibt ein Fund. Bekannte, bewusst
      // akzeptierte Luecke: ':(%):' gemischt mit einem rohen User-Wert an
      // einem bare '%' - im Korpus ohne Beleg.
      if Pos(':(%):', ArgsLow) > 0 then
        Continue;
      // FP-Gate (2026-07-04): int-format-concat / const-concat - wenn ALLE
      // Argument-Array-Elemente Literale oder lokal deklarierte Integer-
      // Bezeichner sind (ExecuteFmt('...RowID=%', [id]) bzw. Seed-INSERT
      // mit ['ACME', ..., 5]), kann die %-Substitution keine SQL-Syntax
      // injizieren -> kein Fund. String-VARIABLEN (RawUtf8-Parameter wie
      // api.impl CreateCustomer/UpdateCustomer) bleiben als Risiko stehen.
      if not AreFormatArgsInjectionSafe(MethodNode, Low,
        FnIdx + Length(Fn)) then
        Exit(True);
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
    F.SetKind(fkSQLInjection);
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
      // Zuweisungs-ZIEL als Nicht-SQL-Senke ausschliessen (StatusBar.Panels[]
      // .Text / Label.Caption := 'Update ...' + x). Echte SQL-Ziele
      // (SQL.Text/CommandText) tragen keinen Sink-Token -> H1 feuert weiter.
      if not IsNonSqlSink(N.Name) then
        if IsAssignRisk(MethodNode, N.Name, N.TypeRef)
           or IsFormatSqlRisk(MethodNode, N.TypeRef) then
          Report(N.Name, N.TypeRef, N.Line);
  finally
    Assigns.Free;
  end;

  // nkCall: Query.SQL.Add('SELECT ' + VarName) ODER
  //         ExecuteFmt('SELECT * FROM %', [tbl])  (H3 / mORMot-Style)
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
      if IsCallRisk(MethodNode, N.Name)
         or IsFormatSqlRisk(MethodNode, N.Name) then
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
