unit uRdxSqlTemplate;

// reDelphix - Rezept 5.2: die parametrisierte SQL-Vorlage zu SCA003
// (Charge S1, 2026-10-15; bis dahin TRdxRecipes.BuildSqlTemplate). Reine
// Textlogik ohne ToolsAPI - laeuft im FPC-Pruefstand. Die Vorlage geht nur
// in die Zwischenablage, geschrieben wird nichts.
//
// ANLASS (Nico, IDE-Test 2026-10-14): aus
//   FConn.ExecSQL('CREATE TABLE ' + TEST_TABLE_SOFTDEL + ' (' +
//     '  id BIGSERIAL PRIMARY KEY, ' + AColumnTypes + ')');
// wurde 'CREATE TABLE :p1 (  id BIGSERIAL PRIMARY KEY, :p2)' samt
// '// <Query>.ParamByName(''p1'')...'. Jeder Operand wurde blind ':pN' -
// falsch, denn SQL-Parameter tragen nur WERTE (nie Tabellen-/Spaltennamen,
// Spaltendefinitionen oder DDL), eine Konstante ist kein Injection-Risiko,
// ohne Query-Objekt liefe der eingefuegte Aufruf mit ungebundenen
// Parametern in einen Laufzeitfehler, und 'p1' sagt nichts.
//
// WAS GILT
//
// 1. Position. Der SQL-Text vor jedem Operanden wird lexikalisch gelesen
//    (Strings '..', gequotete Namen "..", `..`, [..], Kommentare -- und
//    /* */). Ein Operand wird nur dort Parameter, wo SQL einen WERT
//    erwartet:
//      * hinter =, <>, !=, <, >, <=, >=, LIKE, ILIKE, BETWEEN und dem AND
//        eines BETWEEN ('BETWEEN v AND x'),
//      * als Element einer IN (...)- bzw. VALUES (...)-Liste (hinter '('
//        oder ','),
//      * hinter LIMIT und OFFSET: MySQL (vorbereitete Anweisung),
//        PostgreSQL, SQLite, Firebird 4 und SQL Server (OFFSET .. ROWS)
//        nehmen dort Parameter. TOP, FIRST und SKIP nicht: SQL Server
//        verlangt TOP (@n) mit Klammern, Access/Jet nur eine Zahl,
//        Firebird FIRST (?) mit Klammern.
//    Alles andere lehnt ab, mit dem Wort davor im Grund - Bezeichner-
//    Positionen (FROM, JOIN, INTO, UPDATE, TABLE, ORDER BY, GROUP BY,
//    Spalten- und SELECT-Liste, Funktionsargumente: ein Argument kann
//    eine Spalte sein), ein Operand, der an einem Bezeichner klebt
//    ('col_' + X, X + '_tmp', 'tbl.' + X), in einem gequoteten Namen oder
//    einem SQL-Kommentar steht. Eine Anweisung, die mit CREATE, ALTER,
//    DROP, TRUNCATE, RENAME, COMMENT, GRANT oder REVOKE beginnt, hat keine
//    Parameter (DDL/DCL). Sonst muss sie mit einem DML-Wort beginnen
//    (SELECT, INSERT, UPDATE, DELETE, MERGE, WITH, REPLACE, UPSERT) oder -
//    als Bruchstueck ('Q.SQL.Add(..)', 'S := S + ..') - mit einer Klausel
//    (WHERE, AND, OR, HAVING, VALUES, LIMIT, OFFSET, FROM, JOIN ...); sonst
//    ist nicht sichtbar, ob ein '=' einen Wert erwartet ('ENGINE=' in
//    einem CREATE TABLE, 'SET NAMES').
//    Ein Operand IN einem SQL-String ('.. LIKE ''%' + X + '%''') macht
//    den GANZEN String zum Parameter, sein Wert ist der zusammengesetzte
//    Ausdruck ('%' + X + '%'); die Position des Strings entscheidet wie
//    oben. Ein Operand allein in IN (...) bzw. VALUES (...) kann eine
//    ganze Liste sein ('1,2,3') - abgelehnt, ausser IntToStr(x).
//    Ein Wert ausserhalb eines Strings: IntToStr(x) und QuotedStr(x)
//    binden x selbst (QuotedStr setzte die Quotes, die der Parameter
//    nicht braucht; IntToStr macht aus einer Zahl einen Text).
// 2. Konstanten. Ein Operand, der am Quelltext als untypisierte Konstante
//    der Unit oder der Routine nachgewiesen ist (SqlConstOf - ein Name in
//    GROSSBUCHSTABEN beweist nichts), wird nie Parameter: mit einfachem
//    String-Literal als Wert kommt der Wert in den SQL-Text, sonst bleibt
//    die Verkettung stehen. sLineBreak/LineEnding bleiben als Verkettung
//    und gelten als Leerraum, das Ziel selbst ('S := S + ..') bleibt
//    stehen. Bleibt kein Operand: keine Vorlage, "nur Konstanten".
// 3. Ziel. Query-Objekt (Glied .SQL/.CommandText): ParamByName-Zeilen.
//    'X.ExecSQL(..)' nur, wenn die Unit FireDAC.Comp.Client nutzt UND X in
//    der Datei ueberall als TFDConnection deklariert ist
//    (FireDacConnectionProven): dann die Overload
//    TFDConnection.ExecSQL(const ASQL: String; const AParams: array of
//    Variant) - die Werte in der Reihenfolge der Parameter; traegt der
//    Text schon einen Platzhalter, ist die Reihenfolge unklar (abgelehnt).
//    Ein String-Puffer ('S := ..'): Kommentarzeilen '// Parameter binden:
//    ParamByName(..).Value := ..;' - wer S ausfuehrt, bindet. Jeder andere
//    Aufruf (Connection.Query(..), AddQuery(..), ExecSQL ohne Beweis)
//    fuehrt den Text sofort aus und bindet nichts: abgelehnt, die
//    Vorlage liefe mit ungebundenen Parametern in einen Laufzeitfehler.
// 4. Namen (SqlParamName) aus dem Operanden: AColumnTypes -> ColumnTypes,
//    FId -> Id, Edit1.Text -> Edit1Text, IntToStr(Id) -> Id (der erste
//    Pfad, der kein Aufrufkopf ist); A/F vor einem Wort mit Grossbuchstabe
//    faellt weg (ADOQuery1 bleibt); nur Buchstaben, Ziffern, '_'; hoechstens
//    MAX_NAME Zeichen; ein SQL-Wort bekommt ein 'p' davor (Oracle: ORA-01745
//    bei :date, :level ...); Ersatz pN. Kollisionen mit vorhandenen
//    Platzhaltern und untereinander bekommen 2, 3, ... angehaengt. Die
//    vorhandenen liest SqlPlaceholders nach den Regeln von SCA199
//    (uParamNameScan): '::' (PostgreSQL-Cast), ':=', ':1', ':new.', ein
//    ':' direkt hinter einem Bezeichner, ')' oder ']' sind keine.

interface

uses
  System.SysUtils,
  uRefactorInfo,   // ROLE_TARGET, ROLE_LITERAL, ROLE_OPERAND
  uRdxRecipes,     // TRdxPart(s), Literal-Codec, Query-Objekt des Ziels
  uRdxCodeMap;     // TRdxCodeMap: die Nachweise am Quelltext

type
  // Was am Quelltext ueber einen Operanden bewiesen ist (SqlConstOf).
  TRdxSqlConstKind = (
    sckNone,      // keine Konstante (oder nicht nachgewiesen)
    sckLiteral,   // untypisierte Konstante, Wert ein einfaches String-Literal
    sckKept);     // untypisierte Konstante mit anderem Wert: bleibt Verkettung

  TRdxSqlConst = record
    Kind  : TRdxSqlConstKind;
    Value : string;   // sckLiteral: der Wert (dekodiert)
  end;
  TRdxSqlConsts = TArray<TRdxSqlConst>;

  // Wie die Werte bei einem AUFRUF als Ziel an die Parameter kommen.
  TRdxSqlBinding = (
    sbByTarget,         // nur ein Query-Objekt-Aufruf (Q.SQL.Add) bindet
    sbFireDacExecSql);  // X.ExecSQL(SQL, [Werte]) - FireDAC nachgewiesen

  // Die Anfrage an BuildSqlTemplate. Parts in Quelltext-Reihenfolge,
  // Parts[0] darf ROLE_TARGET sein. Die Fakten am Quelltext (Consts,
  // Binding) setzt AddSqlFacts aus PartLines (Zeile je Part), InWith (die
  // Anweisung steht in einem with-Block: kein Name ist bewiesen) und
  // UsesNames; ohne sie gilt kein Operand als Konstante und kein Aufruf
  // als FireDAC.
  TRdxSqlRequest = record
    Target    : string;
    IsCall    : Boolean;
    Parts     : TRdxParts;
    Indent    : string;     // Einrueckung jeder Zeile, Tabs bleiben Tabs
    PartLines : TArray<Integer>;
    InWith    : Boolean;
    UsesNames : TArray<string>;
    Consts    : TRdxSqlConsts;   // je Part (gleicher Index)
    Binding   : TRdxSqlBinding;
  end;

  TRdxSqlTemplate = record
    Text    : string;    // die Vorlage (Zeilen mit sLineBreak)
    Reason  : string;    // bei False
    Params  : Integer;   // Parameter in der Vorlage
    Inlined : Integer;   // Konstanten, deren Wert in den SQL-Text kam
  end;

// Rezept 5.2 (Kopf der Unit). False mit Grund in AResult.Reason.
function BuildSqlTemplate(const AReq: TRdxSqlRequest;
  out AResult: TRdxSqlTemplate): Boolean;
// Hinweis fuer das Menue: 'n Parameter[, k Konstante(n) im Text], nichts
// wird geschrieben'.
function SqlHintOf(const AResult: TRdxSqlTemplate): string;
// Setzt AReq.Consts (je Operand SqlConstOf an seiner Zeile, nicht im
// with-Block) und AReq.Binding (FireDacConnectionProven bei einem Aufruf
// ausserhalb eines with-Blocks).
procedure AddSqlFacts(AMap: TRdxCodeMap; var AReq: TRdxSqlRequest);
// Ist AName (ein blosser Bezeichner) an ALine eine Konstante? Jede
// Deklaration des Namens in der Datei muss eine untypisierte Konstante
// sein ('Name = Wert;' in einer const-Section; ein Parameter, eine
// Variable, ein Feld, eine typisierte Konstante, ein Typ oder eine Routine
// gleichen Namens irgendwo in der Datei - auch im inaktiven $IFDEF-Zweig -
// verwirft den Beweis); gilt muss eine, die vor ALine steht und dort
// sichtbar ist: auf Unit-Ebene ueberall danach, in einer Routine nur bis zu
// deren Ende. Mehrere sichtbare mit verschiedenem Wert: sckKept.
function SqlConstOf(AMap: TRdxCodeMap; const AName: string;
  ALine: Integer): TRdxSqlConst;
// True, wenn die uses-Klauseln FireDAC.Comp.Client nennen und AReceiver
// (ein Bezeichner, 'Self.' davor erlaubt) in der Datei mindestens einmal
// und nur als TFDConnection deklariert ist (Feld, Variable, Parameter,
// Property).
function FireDacConnectionProven(AMap: TRdxCodeMap;
  const AUsesNames: TArray<string>; const AReceiver: string): Boolean;
// 'FConn' aus 'FConn.ExecSQL', sonst ''.
function ExecSqlReceiverOf(const ATarget: string): string;
// Parametername aus einem Operanden (Kopf der Unit, Punkt 4); '' ohne
// verwertbaren Bezeichner.
function SqlParamName(const AExpr: string): string;
// Die Platzhalter im SQL-Text (klein, Regeln von SCA199).
function SqlPlaceholders(const ASql: string): TArray<string>;

implementation

uses
  System.StrUtils,    // PosEx
  uRdxRoutineFixes;   // ReadRoutine: Grenzen der Routinen (lokale Konstanten)

const
  // Gruende - deutsch ohne Umlaute wie in den Nachbar-Units (Statustext).
  R_NAMES = 'Tabellen-/Spaltennamen und DDL lassen sich nicht '
    + 'parametrisieren - Namen pruefen/Whitelist';
  R_OPERAND     = 'Operand ''%s'' ';
  R_DDL         = 'DDL/DCL (%s ...): ' + R_NAMES;
  R_NOT_VALUE   = R_OPERAND + 'steht hinter ''%s'' - dort erwartet SQL '
    + 'keinen Wert. ' + R_NAMES;
  R_AT_START    = R_OPERAND + 'steht am Anfang des SQL-Texts - kein Wert. '
    + R_NAMES;
  R_GLUED       = R_OPERAND + 'ist Teil eines Bezeichners. ' + R_NAMES;
  R_QUOTED_NAME = R_OPERAND + 'steht in einem gequoteten Namen. ' + R_NAMES;
  R_IN_COMMENT  = R_OPERAND + 'steht in einem SQL-Kommentar - keine Vorlage';
  R_WHOLE_LIST  = R_OPERAND + 'ist die ganze %s-Liste - ein Parameter ist '
    + 'EIN Wert, keine Liste';
  R_HEAD        = 'Anweisungsart unbekannt (''%s'') - ob ''%s'' ein Wert '
    + 'ist, ist nicht sichtbar';
  R_AFTER_EXPR  = R_OPERAND + 'folgt direkt auf ''%s'' - ob dort ein Wert '
    + 'steht, ist nicht sichtbar';
  R_NO_SQL_TEXT = 'kein SQL-Text in der Kette - die Anweisung entsteht '
    + 'anderswo (Format, Funktion, Editor-Inhalt), keine Vorlage';
  R_ONLY_CONST  = 'nur Konstanten - kein Injection-Risiko';
  R_OPEN_STRING = 'SQL-String um ''%s'' schliesst nicht - keine Vorlage';
  R_NO_CHANNEL  = '%s() bindet keine Parameter (keine FireDAC-Verbindung '
    + 'nachgewiesen) - Query-Objekt mit ParamByName verwenden';
  R_PLACEHOLDER = 'der SQL-Text traegt schon den Platzhalter :%s - die '
    + 'Reihenfolge der Werte fuer ExecSQL ist unklar';
  R_ARGUMENT    = 'Aufruf mit mehreren Argumenten - keine Vorlage';
  R_NO_OPERAND  = 'kein Operand in der Kette';
  R_LITERAL     = 'Literal nicht lesbar: ';

  // Erste Woerter einer Anweisung (Kopf der Unit, Punkt 1).
  DDL_HEADS: array[0..7] of string = ('create', 'alter', 'drop', 'truncate',
    'rename', 'comment', 'grant', 'revoke');
  DML_HEADS: array[0..7] of string = ('select', 'insert', 'update', 'delete',
    'merge', 'with', 'replace', 'upsert');
  CLAUSE_HEADS: array[0..16] of string = ('where', 'and', 'or', 'having',
    'values', 'limit', 'offset', 'from', 'join', 'inner', 'left', 'right',
    'full', 'cross', 'union', 'order', 'group');
  // Hinter diesen Token erwartet SQL einen Wert.
  VALUE_AFTER: array[0..11] of string = ('=', '<>', '!=', '<', '>', '<=',
    '>=', 'like', 'ilike', 'between', 'limit', 'offset');
  // Listen, deren Elemente Werte sind - das Token vor der '('.
  LIST_OPENERS: array[0..1] of string = ('in', 'values');
  // Zeilenumbruch-Konstanten der RTL: im SQL Leerraum.
  LINE_BREAK_NAMES: array[0..3] of string = ('slinebreak', 'system.slinebreak',
    'lineending', 'system.lineending');
  // Als Parametername nicht ohne 'p' davor (SQL-Woerter; Oracle ORA-01745).
  RESERVED_NAMES: array[0..37] of string = ('access', 'all', 'and', 'as',
    'asc', 'between', 'by', 'comment', 'date', 'desc', 'distinct', 'file',
    'from', 'group', 'in', 'index', 'is', 'key', 'level', 'like', 'limit',
    'mode', 'not', 'null', 'number', 'offset', 'or', 'order', 'select', 'set',
    'size', 'table', 'time', 'timestamp', 'type', 'uid', 'user', 'where');
  // Kommentarzeile vor ParamByName, wenn das Ziel ein String-Puffer ist.
  BIND_COMMENT = '// Parameter binden: ';
  // Vor dem Token eines stehenden Ausdrucks (TakeKept): kein SQL-Wort
  // trifft es, der Grund zeigt den Ausdruck (R_AFTER_EXPR).
  KEPT_MARK = #1;
  // Head einer Anweisung, die nicht mit einem Wort beginnt.
  HEAD_UNKNOWN = '?';
  MAX_NAME  = 30;    // Zeichen eines Parameternamens (Oracle: 30)
  // Zeichen eines Parameternamens im SQL-Text (TParams.ParseSQL).
  NAME_CHARS = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  // 'FId': A/F, Grossbuchstabe, Kleinbuchstabe - erst ab drei Zeichen ist
  // ein Praefix vor einem Wort zu erkennen (WithoutPrefix).
  MIN_PREFIXED = 3;
  MAX_SHOWN = 40;    // so viel vom Operanden im Grund
  // Obergrenze der Token-Laeufe am Quelltext (Schutz vor Endlosschleifen).
  MAX_WALK  = 200000;

  // Deklarationen am Quelltext (SqlConstOf, FireDacConnectionProven).
  // Davor beginnt 'Name:' bzw. 'Name, ..:' eine Deklaration (Variable,
  // Feld, Parameter, typisierte Konstante; auch eine Marke oder ein
  // case-Zweig hinter ';' zaehlt - das macht den Beweis nur vorsichtiger).
  DECL_LEADS: array[0..18] of string = (';', 'var', 'const', 'threadvar',
    '(', ',', ')', 'out', 'constref', ']', 'private', 'protected', 'public',
    'published', 'automated', 'strict', 'record', 'class', 'object');
  // Davor beginnt 'Name =' eine Konstante oder einen Typ.
  CONST_LEADS: array[0..2] of string = (';', 'const', ']');
  // Rueckwaerts von einer Deklaration: hier beginnt ihre Section.
  SECTION_STOPS: array[0..14] of string = ('const', 'var', 'type',
    'threadvar', 'resourcestring', 'label', 'begin', 'interface',
    'implementation', 'initialization', 'finalization', 'program',
    'library', 'unit', 'uses');
  FIREDAC_CLIENT = 'FireDAC.Comp.Client';
  FIREDAC_CONNECTION: array[0..1] of string = ('tfdconnection',
    'firedac.comp.client.tfdconnection');
  EXEC_SQL = '.execsql';

type
  // ---- die Kette als Segmente ----

  TSqlSegKind = (skText, skOperand, skKept);

  // Ein Stueck der Kette fuer den Leser: SQL-Text (Literale und eingesetzte
  // Konstanten, zusammengelegt), ein Operand (wird Parameter oder lehnt ab)
  // oder ein Ausdruck, der stehen bleibt (Konstante ohne einfachen Wert,
  // sLineBreak - dann Blank -, das Ziel selbst bei 'S := S + ..').
  TSqlSeg = record
    Kind  : TSqlSegKind;
    Text  : string;     // skText: SQL-Text; sonst Pascal-Quelltext
    Blank : Boolean;    // skKept: gilt im SQL als Leerraum
  end;
  TSqlSegs = TArray<TSqlSeg>;

  TSqlSegCount = record
    Terms   : Integer;   // Literal- und Operanden-Parts bisher
    All     : Integer;   // Operanden-Parts
    Ops     : Integer;   // davon Operanden (keine Konstante, kein Ziel)
    Consts  : Integer;   // davon Konstanten (auch sLineBreak)
    Inlined : Integer;   // davon Konstanten mit Wert im SQL-Text
  end;

  // ---- der Leser ----

  TSqlPiece = record
    IsExpr : Boolean;   // Pascal-Ausdruck statt SQL-Text
    Text   : string;
  end;

  TSqlParam = record
    Name  : string;
    Value : string;   // Pascal-Ausdruck
  end;

  TSqlLexMode = (lmCode, lmString, lmName, lmLineComment, lmBlockComment);
  // Die letzten drei Token, [0] zuletzt.
  TSqlTok3 = array[0..2] of string;

  // Zustand des Lesers ueber die Segmente (ScanSegs): die Ausgabe in
  // Stuecken, die Parameter, die letzten Token, die offenen Klammern (je
  // das Token davor), das erste Wort der Anweisung (Head) und - waehrend
  // ein SQL-String offen ist - dessen Umfeld und Inhalt.
  TSqlScan = record
    Segs      : TSqlSegs;
    Mode      : TSqlLexMode;
    NameEnd   : Char;            // lmName: das schliessende Zeichen
    Tok       : TSqlTok3;
    Openers   : TArray<string>;
    Head      : string;          // '' = noch kein Wort in dieser Anweisung
    LastCh    : Char;            // letztes SQL-Zeichen (Klebeprobe)
    Pieces    : TArray<TSqlPiece>;
    Params    : TArray<TSqlParam>;
    Used      : TArray<string>;  // vergebene und vorhandene Namen, klein
    Found     : TArray<string>;  // Platzhalter im Text, klein
    // der offene SQL-String
    StrCount  : Integer;         // Zahl der Stuecke beim Oeffnen
    StrLen    : Integer;         // Laenge des letzten Text-Stuecks; -1 keins
    StrTok    : TSqlTok3;
    StrOpener : string;
    StrHead   : string;
    StrParts  : TArray<string>;  // Wert als Pascal-Stuecke
    StrBuf    : string;          // Text seit dem letzten Stueck
    StrFirst  : string;          // erster Operand im String ('' = keiner)
    Reason    : string;
  end;

  // ---- Deklarationen am Quelltext ----

  TSqlDeclKind = (dkConst, dkTyped, dkOther);

  TSqlDecl = record
    Kind : TSqlDeclKind;
    Line : Integer;
    Text : string;   // dkConst: Quelltext des Werts; dkTyped: Typ (klein)
  end;
  TSqlDecls = TArray<TSqlDecl>;

  TSqlLineRange = record
    First : Integer;
    Last  : Integer;
  end;

{ ---- kleine Helfer ---- }

function CharAt(const S: string; AIndex: Integer): Char;
begin
  if (AIndex >= 1) and (AIndex <= Length(S)) then
    Result := S[AIndex]
  else
    Result := #0;
end;

procedure AppendTo(var AList: TArray<string>; const S: string);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := S;
end;

function JoinWith(const AItems: TArray<string>; const ASep: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AItems) do
    begin
      if i > 0 then
        SB.Append(ASep);
      SB.Append(AItems[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Der Operand, wie ihn ein Grund zeigt: hoechstens MAX_SHOWN Zeichen.
function Shown(const AOperand: string): string;
begin
  Result := AOperand;
  if Length(Result) > MAX_SHOWN then
    Result := Copy(Result, 1, MAX_SHOWN) + '...';
end;

// S ohne Leerraum, klein - Vergleichsform fuer Ziel und Operand (vorab
// bemessen statt verkettet, SCA110).
function Squeezed(const S: string): string;
var
  i, n : Integer;
begin
  SetLength(Result, Length(S));
  n := 0;
  for i := 1 to Length(S) do
    if S[i] > ' ' then
    begin
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
  Result := LowerCase(Result);
end;

// Nur die Zeichen eines Parameternamens (Buchstaben, Ziffern, '_').
function NameCharsOf(const S: string): string;
var
  i, n : Integer;
begin
  SetLength(Result, Length(S));
  n := 0;
  for i := 1 to Length(S) do
    if CharInSet(S[i], NAME_CHARS) then
    begin
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
end;

// Steht ab AText[AAt] ('(') eine Klammergruppe, die genau am Ende von AText
// schliesst und auf oberster Ebene kein ',' traegt? Strings zaehlen nicht.
function IsSoleArgGroup(const AText: string; AAt: Integer): Boolean;
var
  i, Depth : Integer;
  InStr    : Boolean;
begin
  Result := False;
  Depth := 0;
  InStr := False;
  for i := AAt to Length(AText) do
    if AText[i] = '''' then
      InStr := not InStr
    else if InStr then
      Continue
    else if AText[i] = '(' then
      Inc(Depth)
    else if AText[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(i = Length(AText));
    end
    else if (AText[i] = ',') and (Depth = 1) then
      Exit;
end;

// 'Name(x)' bzw. 'SysUtils.Name(x)' mit genau einem Argument: True und das
// Argument; sonst False.
function CallArg(const AText, AFunc: string; out AInner: string): Boolean;
var
  T, Low : string;
  i      : Integer;
begin
  AInner := '';
  T := Trim(AText);
  Low := LowerCase(T);
  if Copy(Low, 1, 16) = 'system.sysutils.' then
    Delete(T, 1, 16)
  else if Copy(Low, 1, 9) = 'sysutils.' then
    Delete(T, 1, 9);
  Result := SameText(Copy(T, 1, Length(AFunc)), AFunc);
  if not Result then Exit;
  i := Length(AFunc) + 1;
  while (i <= Length(T)) and (T[i] <= ' ') do
    Inc(i);
  Result := (CharAt(T, i) = '(') and IsSoleArgGroup(T, i);
  if Result then
    AInner := Trim(Copy(T, i + 1, Length(T) - i - 1));
  Result := Result and (AInner <> '');
end;

// Der Wert eines Operanden ausserhalb eines Strings: IntToStr(x) und
// QuotedStr(x) binden x (Kopf der Unit, Punkt 1).
function UnwrapValue(const AText: string): string;
var
  Inner : string;
begin
  Result := AText;
  if CallArg(AText, 'IntToStr', Inner) or CallArg(AText, 'QuotedStr', Inner) then
    Result := Inner;
end;

{ ---- Parameternamen ---- }

// Hinter das ']' zum '[' an AText[i]; i rueckt dahinter.
procedure SkipIndex(const AText: string; var i: Integer);
var
  Depth : Integer;
begin
  Depth := 0;
  repeat
    if AText[i] = '[' then
      Inc(Depth)
    else if AText[i] = ']' then
      Dec(Depth);
    Inc(i);
  until (Depth = 0) or (i > Length(AText));
end;

// Ein Glied ab AText[i] ('&' davor gehoert dazu); i rueckt dahinter.
function ReadIdent(const AText: string; var i: Integer): string;
var
  Start : Integer;
begin
  if CharAt(AText, i) = '&' then
    Inc(i);
  Start := i;
  while IsIdentChar(CharAt(AText, i)) do
    Inc(i);
  Result := Copy(AText, Start, i - Start);
end;

// Ab AText[i] einen Pfad lesen: Glieder mit '.', ein Index '[..]' faellt
// weg; i rueckt dahinter.
function ReadPath(const AText: string; var i: Integer): TArray<string>;
begin
  Result := nil;
  repeat
    AppendTo(Result, ReadIdent(AText, i));
    while CharAt(AText, i) = '[' do
      SkipIndex(AText, i);
    if (CharAt(AText, i) <> '.') or not IsIdentStart(CharAt(AText, i + 1)) then
      Exit;
    Inc(i);
  until False;
end;

// Hinter das String-Literal ab AText[i] (ein Quote; '' sind zwei Literale).
procedure SkipLiteral(const AText: string; var i: Integer);
begin
  Inc(i);
  while (i <= Length(AText)) and (AText[i] <> '''') do
    Inc(i);
  Inc(i);
end;

function StartsPath(const AText: string; i: Integer): Boolean;
begin
  Result := IsIdentStart(AText[i])
    or ((AText[i] = '&') and IsIdentStart(CharAt(AText, i + 1)));
end;

// Der erste Pfad in AExpr, der kein Aufrufkopf ist ('Edit1.Text' aus
// 'Trim(Edit1.Text)', 'x' aus '''%'' + x'); ohne einen solchen der erste
// Aufrufkopf; leer ohne Pfad. Strings werden uebersprungen.
function FirstValuePath(const AExpr: string): TArray<string>;
var
  i     : Integer;
  Path  : TArray<string>;
  Spare : TArray<string>;
begin
  Spare := nil;
  i := 1;
  while i <= Length(AExpr) do
    if AExpr[i] = '''' then
      SkipLiteral(AExpr, i)
    else if StartsPath(AExpr, i) then
    begin
      Path := ReadPath(AExpr, i);
      if CharAt(AExpr, SkipBlanks(AExpr, i)) <> '(' then
        Exit(Path);
      if Length(Spare) = 0 then
        Spare := Path;
    end
    else
      Inc(i);
  Result := Spare;
end;

// A bzw. F vor einem Wort mit Grossbuchstaben faellt weg ('AColumnTypes' ->
// 'ColumnTypes', 'FId' -> 'Id'); ein Kuerzel bleibt ('ADOQuery1').
function WithoutPrefix(const ASegment: string): string;
begin
  Result := ASegment;
  if (Length(Result) >= MIN_PREFIXED) and CharInSet(Result[1], ['A', 'F'])
     and CharInSet(Result[2], ['A'..'Z']) and CharInSet(Result[3], ['a'..'z']) then
    Delete(Result, 1, 1);
end;

// Die Glieder ohne 'Self' aneinander, das erste ohne A/F-Praefix; nur
// Zeichen eines Parameternamens.
function NameOfPath(const AParts: TArray<string>): string;
var
  Segs : TArray<string>;
  i    : Integer;
begin
  Segs := nil;
  for i := 0 to High(AParts) do
    if not SameText(AParts[i], 'self') then
      if Length(Segs) = 0 then
        AppendTo(Segs, WithoutPrefix(AParts[i]))
      else
        AppendTo(Segs, AParts[i]);
  Result := NameCharsOf(JoinWith(Segs, ''));
end;

function SqlParamName(const AExpr: string): string;
begin
  Result := NameOfPath(FirstValuePath(AExpr));
  if Result = '' then Exit;
  if CharInSet(Result[1], ['0'..'9']) then
    Result := 'p' + Result;
  Result := Copy(Result, 1, MAX_NAME);
  if InList(LowerCase(Result), RESERVED_NAMES) then
    Result := 'p' + Result;
end;

// ABase oder - schon vergeben - ABase2, ABase3 ...; ohne ABase pN.
function UniqueName(const ABase: string; const AUsed: TArray<string>;
  AIndex: Integer): string;
var
  Base : string;
  k    : Integer;
begin
  Base := ABase;
  if Base = '' then
    Base := 'p' + IntToStr(AIndex);
  Result := Base;
  k := 2;
  while InList(LowerCase(Result), AUsed) do
  begin
    Result := Base + IntToStr(k);
    Inc(k);
  end;
end;

{ ---- Segmente ---- }

procedure AddSeg(var ASegs: TSqlSegs; AKind: TSqlSegKind; const AText: string;
  ABlank: Boolean);
var
  n : Integer;
begin
  n := Length(ASegs);
  if AKind = skText then
  begin
    if AText = '' then Exit;
    // Literal und eingesetzte Konstante sind EIN SQL-Text.
    if (n > 0) and (ASegs[n - 1].Kind = skText) then
    begin
      ASegs[n - 1].Text := ASegs[n - 1].Text + AText;
      Exit;
    end;
  end;
  SetLength(ASegs, n + 1);
  ASegs[n].Kind  := AKind;
  ASegs[n].Text  := AText;
  ASegs[n].Blank := ABlank;
end;

function ConstAt(const AReq: TRdxSqlRequest; AIndex: Integer): TRdxSqlConst;
begin
  if AIndex <= High(AReq.Consts) then
    Result := AReq.Consts[AIndex]
  else
    Result := Default(TRdxSqlConst);
end;

procedure TakeOperandPart(const AReq: TRdxSqlRequest; AIndex: Integer;
  var ASegs: TSqlSegs; var ACount: TSqlSegCount);
var
  Txt : string;
  C   : TRdxSqlConst;
begin
  Inc(ACount.All);
  Txt := TRdxRecipes.CollapseCode(Trim(AReq.Parts[AIndex].Text));
  C := ConstAt(AReq, AIndex);
  if C.Kind <> sckNone then
    Inc(ACount.Consts);
  if C.Kind = sckLiteral then
  begin
    AddSeg(ASegs, skText, C.Value, False);
    Inc(ACount.Inlined);
  end
  else if C.Kind = sckKept then
    AddSeg(ASegs, skKept, Txt, False)
  else if InList(LowerCase(Txt), LINE_BREAK_NAMES) then
  begin
    AddSeg(ASegs, skKept, Txt, True);
    Inc(ACount.Consts);
  end
  // 'S := S + ..': das Ziel als ERSTER Term ist der bisherige Text. Weiter
  // hinten ('S := ''INSERT INTO '' + S') ist es ein Operand wie jeder.
  else if not AReq.IsCall and (ACount.Terms = 0)
     and (Squeezed(Txt) = Squeezed(AReq.Target)) then
    AddSeg(ASegs, skKept, Txt, False)
  else
  begin
    AddSeg(ASegs, skOperand, Txt, False);
    Inc(ACount.Ops);
  end;
end;

// Ein Part als Segment; '' oder der Grund.
function TakePart(const AReq: TRdxSqlRequest; AIndex: Integer;
  var ASegs: TSqlSegs; var ACount: TSqlSegCount): string;
var
  P     : TRdxPart;
  Value : string;
begin
  Result := '';
  P := AReq.Parts[AIndex];
  if P.Role = ROLE_TARGET then Exit;
  if P.Role = ROLE_LITERAL then
  begin
    if not TRdxRecipes.DecodeLiteral(P.Text, Value) then
      Exit(R_LITERAL + TRdxRecipes.CollapseWhitespace(P.Text));
    AddSeg(ASegs, skText, Value, False);
  end
  else if P.Role = ROLE_OPERAND then
    TakeOperandPart(AReq, AIndex, ASegs, ACount)
  else
    Exit(R_ARGUMENT);
  Inc(ACount.Terms);
end;

// Die SQL-Texte der Kette, Ausdruecke als ein Leerzeichen - die Vorlage
// fuer SqlPlaceholders vor dem eigentlichen Lesen (ein Name darf auch
// keinen Platzhalter treffen, der erst HINTER dem Operanden steht).
function PlainSqlOf(const ASegs: TSqlSegs): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ASegs) do
      if ASegs[i].Kind = skText then
        SB.Append(ASegs[i].Text)
      else
        SB.Append(' ');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SegsOf(const AReq: TRdxSqlRequest; out ASegs: TSqlSegs;
  out ACount: TSqlSegCount): string;
var
  i : Integer;
begin
  Result := '';
  ASegs := nil;
  ACount := Default(TSqlSegCount);
  for i := 0 to High(AReq.Parts) do
  begin
    Result := TakePart(AReq, i, ASegs, ACount);
    if Result <> '' then Exit;
  end;
  if (ACount.All = 0) or ((ACount.Ops = 0) and (ACount.Consts = 0)) then
    Result := R_NO_OPERAND
  else if ACount.Ops = 0 then
    Result := R_ONLY_CONST
  else if Trim(PlainSqlOf(ASegs)) = '' then
    Result := R_NO_SQL_TEXT;   // FormatUtf8(..), Memo.Text + #13#10
end;

{ ---- Ausgabe ---- }

procedure EmitText(var S: TSqlScan; const AText: string);
var
  n : Integer;
begin
  if AText = '' then Exit;
  n := Length(S.Pieces);
  if (n > 0) and not S.Pieces[n - 1].IsExpr then
    S.Pieces[n - 1].Text := S.Pieces[n - 1].Text + AText
  else
  begin
    SetLength(S.Pieces, n + 1);
    S.Pieces[n].IsExpr := False;
    S.Pieces[n].Text   := AText;
  end;
end;

procedure EmitExpr(var S: TSqlScan; const AExpr: string);
var
  n : Integer;
begin
  n := Length(S.Pieces);
  SetLength(S.Pieces, n + 1);
  S.Pieces[n].IsExpr := True;
  S.Pieces[n].Text   := AExpr;
end;

// Letztes Zeichen der Ausgabe, #0 hinter einem Ausdruck oder am Anfang.
function OutLast(const S: TSqlScan): Char;
var
  n : Integer;
begin
  Result := #0;
  n := Length(S.Pieces);
  if (n > 0) and not S.Pieces[n - 1].IsExpr then
    Result := CharAt(S.Pieces[n - 1].Text, Length(S.Pieces[n - 1].Text));
end;

// Die Ausgabe auf den Stand beim Oeffnen eines Strings zurueck.
procedure CutOutput(var S: TSqlScan);
begin
  SetLength(S.Pieces, S.StrCount);
  if S.StrLen >= 0 then
    S.Pieces[S.StrCount - 1].Text := Copy(S.Pieces[S.StrCount - 1].Text, 1,
      S.StrLen);
end;

{ ---- Token ---- }

// Ein Token der Anweisung. Beginnt sie mit etwas anderem als einem Wort
// (ausser '(' und einem stehenden Ausdruck - dem bisherigen Text, einer
// Konstanten), ist ihre Art unbekannt: '?select=' + X ist eine URL.
procedure PushTok(var S: TSqlScan; const ATok: string);
begin
  if (S.Head = '') and (ATok <> '(') and (Copy(ATok, 1, 1) <> KEPT_MARK) then
    S.Head := HEAD_UNKNOWN;
  S.Tok[2] := S.Tok[1];
  S.Tok[1] := S.Tok[0];
  S.Tok[0] := ATok;
end;

function TopOpener(const S: TSqlScan): string;
begin
  Result := '';
  if Length(S.Openers) > 0 then
    Result := S.Openers[High(S.Openers)];
end;

procedure NewStatement(var S: TSqlScan);
begin
  S.Head := '';
  S.Openers := nil;
  S.Tok[2] := '';
  S.Tok[1] := '';
  S.Tok[0] := ';';
end;

{ ---- Urteile ---- }

function IsValueContext(const ATok: TSqlTok3; const AOpener: string): Boolean;
begin
  Result := InList(ATok[0], VALUE_AFTER)
    or ((ATok[0] = 'and') and (ATok[2] = 'between'))
    or (((ATok[0] = '(') or (ATok[0] = ',')) and InList(AOpener, LIST_OPENERS));
end;

// Darf C hinter einem Wert stehen (Leerraum, Ende, Klammer zu, Komma,
// Operator)?
function IsValueFollower(C: Char): Boolean;
begin
  Result := (C <= ' ') or CharInSet(C, [')', ',', ';', '=', '<', '>', '!',
    '+', '-', '*', '/', '|', '%']);
end;

// Klebt ein Operand hinter C an einem Bezeichner ('col_', 'tbl.', '@', ':')?
function GluesAfter(C: Char): Boolean;
begin
  Result := IsIdentChar(C) or CharInSet(C, ['.', '@', ':', '$', '#']);
end;

// Die Urteile ueber die Position eines Werts: DDL, Anfang, Wert-Kontext,
// Anweisungsart. '' oder der Grund.
function ValueReason(const ATok: TSqlTok3; const AOpener, AHead,
  AOperand: string): string;
var
  Head : string;
begin
  Result := '';
  if InList(AHead, DDL_HEADS) then
    Exit(Format(R_DDL, [UpperCase(AHead)]));
  if ATok[0] = '' then
    Exit(Format(R_AT_START, [Shown(AOperand)]));
  if Copy(ATok[0], 1, 1) = KEPT_MARK then
    Exit(Format(R_AFTER_EXPR, [Shown(AOperand),
      Shown(Copy(ATok[0], 2, MaxInt))]));
  if not IsValueContext(ATok, AOpener) then
    Exit(Format(R_NOT_VALUE, [Shown(AOperand), ATok[0]]));
  if InList(AHead, DML_HEADS) or InList(AHead, CLAUSE_HEADS) then Exit;
  Head := AHead;
  if Head = '' then
    Head := HEAD_UNKNOWN;
  Result := Format(R_HEAD, [Head, Shown(AOperand)]);
end;

{ ---- Parameter ---- }

procedure AddParam(var S: TSqlScan; const AFirst, AValue: string);
var
  P : TSqlParam;
begin
  P.Name  := UniqueName(SqlParamName(AFirst), S.Used, Length(S.Params) + 1);
  P.Value := AValue;
  SetLength(S.Params, Length(S.Params) + 1);
  S.Params[High(S.Params)] := P;
  AppendTo(S.Used, LowerCase(P.Name));
  if IsIdentChar(OutLast(S)) then
    EmitText(S, ' ');
  EmitText(S, ':' + P.Name);
  PushTok(S, 'v');
  S.LastCh := 'v';
end;

{ ---- SQL-Strings ---- }

procedure OpenString(var S: TSqlScan);
begin
  S.StrCount := Length(S.Pieces);
  S.StrLen := -1;
  if (S.StrCount > 0) and not S.Pieces[S.StrCount - 1].IsExpr then
    S.StrLen := Length(S.Pieces[S.StrCount - 1].Text);
  S.StrTok    := S.Tok;
  S.StrOpener := TopOpener(S);
  S.StrHead   := S.Head;
  S.StrParts  := nil;
  S.StrBuf    := '';
  S.StrFirst  := '';
  S.Mode := lmString;
  EmitText(S, '''');
end;

procedure FlushStrBuf(var S: TSqlScan);
begin
  if S.StrBuf <> '' then
    AppendTo(S.StrParts, TRdxRecipes.EncodeLiteral(S.StrBuf));
  S.StrBuf := '';
end;

// Erstes SQL-Zeichen ab Segment ASeg: Text -> sein erstes Zeichen,
// Leerraum-Ausdruck -> ' ', ein anderer Ausdruck oder Operand -> 'x'
// (klebt), Ende -> #0.
function SegStart(const S: TSqlScan; ASeg: Integer): Char;
begin
  if ASeg > High(S.Segs) then
    Result := #0
  else if S.Segs[ASeg].Kind = skText then
    Result := S.Segs[ASeg].Text[1]
  else if (S.Segs[ASeg].Kind = skKept) and S.Segs[ASeg].Blank then
    Result := ' '
  else
    Result := 'x';
end;

// Der String schliesst (AFollower: das Zeichen dahinter). Ohne Operand ein
// gewoehnliches Literal; mit Operand wird er EIN Parameter, wenn er an
// einer Wert-Position steht.
procedure CloseString(var S: TSqlScan; AFollower: Char);
begin
  S.Mode := lmCode;
  S.LastCh := '''';
  if S.StrFirst = '' then
  begin
    EmitText(S, '''');
    PushTok(S, 's');
    Exit;
  end;
  FlushStrBuf(S);
  S.Reason := ValueReason(S.StrTok, S.StrOpener, S.StrHead, S.StrFirst);
  if (S.Reason = '') and not IsValueFollower(AFollower) then
    S.Reason := Format(R_GLUED, [Shown(S.StrFirst)]);
  if S.Reason <> '' then Exit;
  CutOutput(S);
  AddParam(S, S.StrFirst, JoinWith(S.StrParts, ' + '));
end;

function StepString(var S: TSqlScan; const T: string; i, ASeg: Integer): Integer;
var
  Follower : Char;
begin
  Result := i + 1;
  if T[i] <> '''' then
  begin
    EmitText(S, T[i]);
    S.StrBuf := S.StrBuf + T[i];
  end
  else if CharAt(T, i + 1) = '''' then
  begin
    EmitText(S, '''''');
    S.StrBuf := S.StrBuf + '''';
    Result := i + 2;
  end
  else
  begin
    Follower := CharAt(T, i + 1);
    if i = Length(T) then
      Follower := SegStart(S, ASeg + 1);
    CloseString(S, Follower);
  end;
end;

{ ---- Code, Namen, Kommentare ---- }

function TakeWord(var S: TSqlScan; const T: string; i: Integer): Integer;
var
  W : string;
begin
  Result := i;
  if CharInSet(T[i], ['0'..'9']) then
  begin
    while CharInSet(CharAt(T, Result), ['0'..'9', '.']) or IsIdentChar(CharAt(T, Result)) do
      Inc(Result);
    EmitText(S, Copy(T, i, Result - i));
    PushTok(S, 'n');   // eine Zahl ist ein Wert
    Exit;
  end;
  while IsIdentChar(CharAt(T, Result)) or (CharAt(T, Result) = '$') do
    Inc(Result);
  W := Copy(T, i, Result - i);
  EmitText(S, W);
  W := LowerCase(W);
  if S.Head = '' then
    S.Head := W;
  PushTok(S, W);
end;

// ':' im Code: '::' (Cast) und ':=' als Token, ':name' als Platzhalter
// (Regeln von SCA199), sonst ':' allein.
function TakeColon(var S: TSqlScan; const T: string; i: Integer): Integer;
var
  Nx : Char;
  Nm : string;
begin
  Nx := CharAt(T, i + 1);
  if (Nx = ':') or (Nx = '=') then
  begin
    EmitText(S, ':' + Nx);
    PushTok(S, ':' + Nx);
    Exit(i + 2);
  end;
  if not IsIdentStart(Nx) or IsIdentChar(S.LastCh)
     or CharInSet(S.LastCh, [')', ']']) then
  begin
    EmitText(S, ':');
    PushTok(S, ':');
    Exit(i + 1);
  end;
  Result := i + 1;
  while IsIdentChar(CharAt(T, Result)) do
    Inc(Result);
  Nm := LowerCase(Copy(T, i + 1, Result - i - 1));
  if not (((Nm = 'new') or (Nm = 'old')) and (CharAt(T, Result) = '.')) then
    AppendTo(S.Found, Nm);
  EmitText(S, Copy(T, i, Result - i));
  PushTok(S, 'v');
end;

function TakePunct(var S: TSqlScan; const T: string; i: Integer): Integer;
var
  Op : string;
begin
  Result := i + 1;
  if CharInSet(T[i], ['<', '>', '=', '!']) then
    while CharInSet(CharAt(T, Result), ['<', '>', '=']) do
      Inc(Result);
  Op := Copy(T, i, Result - i);
  EmitText(S, Op);
  if Op = '(' then
  begin
    AppendTo(S.Openers, S.Tok[0]);
    PushTok(S, Op);
  end
  else if Op = ')' then
  begin
    if Length(S.Openers) > 0 then
      SetLength(S.Openers, Length(S.Openers) - 1);
    PushTok(S, Op);
  end
  else if Op = ';' then
    NewStatement(S)
  else
    PushTok(S, Op);
end;

function OpenMode(var S: TSqlScan; AMode: TSqlLexMode; const AOpen: string;
  i: Integer): Integer;
begin
  S.Mode := AMode;
  EmitText(S, AOpen);
  Result := i + Length(AOpen);
end;

function StepCode(var S: TSqlScan; const T: string; i: Integer): Integer;
var
  C : Char;
begin
  C := T[i];
  Result := i + 1;
  if C <= ' ' then
    EmitText(S, C)
  else if Copy(T, i, 2) = '--' then
    Result := OpenMode(S, lmLineComment, '--', i)
  else if Copy(T, i, 2) = '/*' then
    Result := OpenMode(S, lmBlockComment, '/*', i)
  else if C = '''' then
    OpenString(S)
  else if CharInSet(C, ['"', '`', '[']) then
  begin
    S.NameEnd := C;
    if C = '[' then
      S.NameEnd := ']';
    Result := OpenMode(S, lmName, C, i);
  end
  else if IsIdentStart(C) or CharInSet(C, ['0'..'9']) then
    Result := TakeWord(S, T, i)
  else if C = ':' then
    Result := TakeColon(S, T, i)
  else
    Result := TakePunct(S, T, i);
  if S.Mode = lmCode then
    S.LastCh := T[Result - 1];
end;

// ':name' in einem SQL-Kommentar: Data.DB, ADO und IBX legen auch ihn als
// Parameter an (SCA199, uParamNameScan) - ein neuer Name darf ihn nicht
// treffen.
procedure NoteCommentPlaceholder(var S: TSqlScan; const T: string; i: Integer);
var
  j : Integer;
begin
  if (T[i] <> ':') or not IsIdentStart(CharAt(T, i + 1))
     or IsIdentChar(CharAt(T, i - 1)) or (CharAt(T, i - 1) = ':') then
    Exit;
  j := i + 1;
  while IsIdentChar(CharAt(T, j)) do
    Inc(j);
  AppendTo(S.Found, LowerCase(Copy(T, i + 1, j - i - 1)));
end;

// Name, Zeilen- oder Block-Kommentar: Zeichen uebernehmen bis zum Ende.
function StepOther(var S: TSqlScan; const T: string; i: Integer): Integer;
begin
  Result := i + 1;
  if S.Mode <> lmName then
    NoteCommentPlaceholder(S, T, i);
  if (S.Mode = lmBlockComment) and (Copy(T, i, 2) = '*/') then
  begin
    EmitText(S, '*/');
    S.Mode := lmCode;
    S.LastCh := ' ';
    Exit(i + 2);
  end;
  EmitText(S, T[i]);
  if (S.Mode = lmName) and (T[i] = S.NameEnd) then
  begin
    S.Mode := lmCode;
    S.LastCh := T[i];
    PushTok(S, T[i]);
  end
  else if (S.Mode = lmLineComment) and CharInSet(T[i], [#10, #13]) then
  begin
    S.Mode := lmCode;
    S.LastCh := ' ';
  end;
end;

procedure ScanText(var S: TSqlScan; ASeg: Integer);
var
  T : string;
  i : Integer;
begin
  T := S.Segs[ASeg].Text;
  i := 1;
  while (i <= Length(T)) and (S.Reason = '') do
    if S.Mode = lmCode then
      i := StepCode(S, T, i)
    else if S.Mode = lmString then
      i := StepString(S, T, i, ASeg)
    else
      i := StepOther(S, T, i);
end;

{ ---- Operanden ---- }

// Das letzte Segment des Laufs ab ASeg: Operanden und stehende Ausdruecke
// ohne SQL-Text dazwischen sind EIN Wert (ein Leerraum-Ausdruck trennt).
function RunEnd(const S: TSqlScan; ASeg: Integer): Integer;
begin
  Result := ASeg;
  while (Result < High(S.Segs)) and (S.Segs[Result + 1].Kind <> skText)
    and not S.Segs[Result + 1].Blank do
    Inc(Result);
end;

function RunValue(const S: TSqlScan; AFirst, ALast: Integer): string;
var
  k     : Integer;
  Items : TArray<string>;
begin
  if AFirst = ALast then
    Exit(UnwrapValue(S.Segs[AFirst].Text));
  Items := nil;
  for k := AFirst to ALast do
    AppendTo(Items, S.Segs[k].Text);
  Result := JoinWith(Items, ' + ');
end;

// Erstes Zeichen hinter dem Lauf, das kein Leerraum ist (')' bei der
// ganzen Liste).
function NextNonBlank(const S: TSqlScan; ASeg: Integer): Char;
var
  k : Integer;
  T : string;
begin
  for k := ASeg to High(S.Segs) do
    if S.Segs[k].Kind = skText then
    begin
      T := TrimLeft(S.Segs[k].Text);
      if T <> '' then
        Exit(T[1]);
    end
    else if not S.Segs[k].Blank then
      Exit('x');
  Result := #0;
end;

function BareReason(const S: TSqlScan; AFirst, ALast: Integer): string;
var
  Op, Inner : string;
begin
  Op := S.Segs[AFirst].Text;
  if InList(S.Head, DDL_HEADS) then
    Exit(Format(R_DDL, [UpperCase(S.Head)]));
  if GluesAfter(S.LastCh) then
    Exit(Format(R_GLUED, [Shown(Op)]));
  Result := ValueReason(S.Tok, TopOpener(S), S.Head, Op);
  if Result <> '' then Exit;
  if not IsValueFollower(SegStart(S, ALast + 1)) then
    Exit(Format(R_GLUED, [Shown(Op)]));
  if (S.Tok[0] = '(') and (NextNonBlank(S, ALast + 1) = ')')
     and not ((AFirst = ALast) and CallArg(Op, 'IntToStr', Inner)) then
    Result := Format(R_WHOLE_LIST, [Shown(Op), UpperCase(TopOpener(S))]);
end;

// Ein Operand im Code: mit seinem Lauf EIN Wert. Liefert das letzte
// Segment des Laufs.
function TakeBareRun(var S: TSqlScan; ASeg: Integer): Integer;
begin
  Result := RunEnd(S, ASeg);
  S.Reason := BareReason(S, ASeg, Result);
  if S.Reason = '' then
    AddParam(S, S.Segs[ASeg].Text, RunValue(S, ASeg, Result));
end;

// Ein Operand oder stehender Ausdruck in einem offenen SQL-String: ein
// Stueck seines Werts.
procedure TakeInString(var S: TSqlScan; const ASeg: TSqlSeg);
begin
  FlushStrBuf(S);
  AppendTo(S.StrParts, ASeg.Text);
  if (ASeg.Kind = skOperand) and (S.StrFirst = '') then
    S.StrFirst := ASeg.Text;
  EmitExpr(S, ASeg.Text);
end;

procedure TakeKept(var S: TSqlScan; const ASeg: TSqlSeg);
begin
  if S.Mode = lmString then
  begin
    TakeInString(S, ASeg);
    Exit;
  end;
  EmitExpr(S, ASeg.Text);
  if (S.Mode = lmCode) and not ASeg.Blank then
    PushTok(S, KEPT_MARK + ASeg.Text);
  if S.Mode = lmCode then
    S.LastCh := ' ';
end;

function TakeOperandSeg(var S: TSqlScan; ASeg: Integer): Integer;
begin
  Result := ASeg;
  case S.Mode of
    lmCode   : Result := TakeBareRun(S, ASeg);
    lmString : TakeInString(S, S.Segs[ASeg]);
    lmName   : S.Reason := Format(R_QUOTED_NAME, [Shown(S.Segs[ASeg].Text)]);
  else
    S.Reason := Format(R_IN_COMMENT, [Shown(S.Segs[ASeg].Text)]);
  end;
end;

procedure ScanSegs(var S: TSqlScan);
var
  k : Integer;
begin
  k := 0;
  while (k <= High(S.Segs)) and (S.Reason = '') do
  begin
    if S.Segs[k].Kind = skText then
      ScanText(S, k)
    else if S.Segs[k].Kind = skKept then
      TakeKept(S, S.Segs[k])
    else
      k := TakeOperandSeg(S, k);
    Inc(k);
  end;
  if (S.Reason = '') and (S.Mode = lmString) and (S.StrFirst <> '') then
    S.Reason := Format(R_OPEN_STRING, [Shown(S.StrFirst)]);
end;

function SqlPlaceholders(const ASql: string): TArray<string>;
var
  S : TSqlScan;
begin
  S := Default(TSqlScan);
  AddSeg(S.Segs, skText, ASql, False);
  ScanSegs(S);
  Result := S.Found;
end;

{ ---- die Vorlage ---- }

// Der SQL-Ausdruck aus den Stuecken: Text als Literal, Ausdruecke wie
// geschrieben, mit ' + ' verbunden.
function SqlExprOf(const APieces: TArray<TSqlPiece>): string;
var
  i     : Integer;
  Items : TArray<string>;
begin
  Items := nil;
  for i := 0 to High(APieces) do
    if APieces[i].IsExpr then
      AppendTo(Items, APieces[i].Text)
    else if APieces[i].Text <> '' then
      AppendTo(Items, TRdxRecipes.EncodeLiteral(APieces[i].Text));
  if Length(Items) = 0 then
    Result := ''''''
  else
    Result := JoinWith(Items, ' + ');
end;

// Je Parameter eine Zeile 'APrefixParamByName(''Name'').Value := Wert;'.
function BindLines(const AParams: TArray<TSqlParam>;
  const AIndent, APrefix: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AParams) do
      SB.Append(sLineBreak + AIndent + APrefix + 'ParamByName('
        + TRdxRecipes.EncodeLiteral(AParams[i].Name) + ').Value := '
        + AParams[i].Value + ';');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function ValuesOf(const AParams: TArray<TSqlParam>): string;
var
  i     : Integer;
  Items : TArray<string>;
begin
  Items := nil;
  for i := 0 to High(AParams) do
    AppendTo(Items, AParams[i].Value);
  Result := JoinWith(Items, ', ');
end;

function StatementOf(const AReq: TRdxSqlRequest; const ASql: string): string;
begin
  if AReq.IsCall then
    Result := Trim(AReq.Target) + '(' + ASql + ');'
  else
    Result := Trim(AReq.Target) + ' := ' + ASql + ';';
end;

// Die Vorlage nach dem Ziel (Kopf der Unit, Punkt 3). '' oder der Grund.
function ComposeTemplate(const AReq: TRdxSqlRequest; const S: TSqlScan;
  const AExisting: TArray<string>; out AText: string): string;
var
  Target, Sql : string;
begin
  Result := '';
  AText := '';
  Target := Trim(AReq.Target);
  Sql := SqlExprOf(S.Pieces);
  if TRdxRecipes.HasQueryObject(Target) then
    AText := AReq.Indent + StatementOf(AReq, Sql) + BindLines(S.Params,
      AReq.Indent, TRdxRecipes.QueryObjectOf(Target) + '.')
  else if not AReq.IsCall then
    AText := AReq.Indent + StatementOf(AReq, Sql) + BindLines(S.Params,
      AReq.Indent, BIND_COMMENT)
  else if AReq.Binding <> sbFireDacExecSql then
    Result := Format(R_NO_CHANNEL, [Target])
  else if Length(AExisting) > 0 then
    Result := Format(R_PLACEHOLDER, [AExisting[0]])
  else
    AText := AReq.Indent + Target + '(' + Sql + ', [' + ValuesOf(S.Params)
      + ']);';
end;

function BuildSqlTemplate(const AReq: TRdxSqlRequest;
  out AResult: TRdxSqlTemplate): Boolean;
var
  S        : TSqlScan;
  Count    : TSqlSegCount;
  Existing : TArray<string>;
begin
  Result := False;
  AResult := Default(TRdxSqlTemplate);
  S := Default(TSqlScan);
  AResult.Reason := SegsOf(AReq, S.Segs, Count);
  if AResult.Reason <> '' then Exit;
  Existing := SqlPlaceholders(PlainSqlOf(S.Segs));
  S.Used := Copy(Existing, 0, Length(Existing));
  ScanSegs(S);
  AResult.Reason := S.Reason;
  if AResult.Reason = '' then
    AResult.Reason := ComposeTemplate(AReq, S, Existing, AResult.Text);
  if AResult.Reason <> '' then Exit;
  AResult.Params  := Length(S.Params);
  AResult.Inlined := Count.Inlined;
  Result := True;
end;

function SqlHintOf(const AResult: TRdxSqlTemplate): string;
begin
  Result := Format('%d Parameter', [AResult.Params]);
  if AResult.Inlined > 0 then
    Result := Result + Format(', %d Konstante(n) im Text', [AResult.Inlined]);
  Result := Result + ', nichts wird geschrieben';
end;

{ ---- Deklarationen am Quelltext ---- }

// Naechste Spalte ab AFrom, an der ALow (klein) als ganzes Wort im Code
// steht; 0 ohne.
function WordCol(AMap: TRdxCodeMap; ALine: Integer; const ALow: string;
  AFrom: Integer): Integer;
var
  L : string;
  c : Integer;
begin
  Result := 0;
  L := LowerCase(AMap.Raw(ALine));
  c := PosEx(ALow, L, AFrom);
  while c > 0 do
  begin
    if AMap.IsCode(ALine, c) and not IsIdentChar(CharAt(L, c - 1))
       and not IsIdentChar(CharAt(L, c + Length(ALow))) then
      Exit(c);
    c := PosEx(ALow, L, c + 1);
  end;
end;

// Der Typ hinter ':' - ein Pfad ('TFDConnection', 'FireDAC.Comp.Client.
// TFDConnection'), klein; sonst das erste Token ('array', '^').
function TypeAfter(AMap: TRdxCodeMap; const AColon: TRdxToken): string;
var
  T, D  : TRdxToken;
  Parts : TArray<string>;
begin
  T := After(AMap, AColon);
  Result := T.Low;
  if not T.IsWord then Exit;
  Parts := nil;
  AppendTo(Parts, T.Low);
  D := After(AMap, T);
  while (D.Low = '.') and After(AMap, D).IsWord do
  begin
    T := After(AMap, D);
    AppendTo(Parts, T.Low);
    D := After(AMap, T);
  end;
  Result := JoinWith(Parts, '.');
end;

// 'Name:' bzw. 'Name, B, C:' hinter einem DECL_LEADS-Token: dkTyped mit
// dem Typ. False bei allem anderen (Argumente 'F(A, Name)').
function TypedDeclAt(AMap: TRdxCodeMap; const P, N: TRdxToken;
  var D: TSqlDecl): Boolean;
var
  C     : TRdxToken;
  Steps : Integer;
begin
  Result := False;
  if not InList(P.Low, DECL_LEADS) then Exit;
  C := N;
  Steps := 0;
  while (C.Low = ',') and (Steps < MAX_WALK) do
  begin
    C := After(AMap, C);
    if not C.IsWord then Exit;
    C := After(AMap, C);
    Inc(Steps);
  end;
  if C.Low <> ':' then Exit;
  D.Kind := dkTyped;
  D.Text := TypeAfter(AMap, C);
  Result := True;
end;

// Das Wort, das die Section um ANameTok eroeffnet (const, var, type ...):
// rueckwaerts ueber die Eintraege davor, Klammern zaehlen; '(' innerhalb
// einer offenen Klammer, '' ohne.
function SectionOf(AMap: TRdxCodeMap; const ANameTok: TRdxToken): string;
var
  T, P  : TRdxToken;
  Paren : Integer;
  n     : Integer;
begin
  Result := '';
  Paren := 0;
  T := Before(AMap, ANameTok);
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Exit;
    P := Before(AMap, T);
    if T.Low = ')' then
      Inc(Paren)
    else if T.Low = '(' then
    begin
      Dec(Paren);
      if Paren < 0 then Exit('(');
    end
    else if (Paren = 0) and IsKeywordAfter(T, P)
       and (InList(T.Low, SECTION_STOPS) or IsRoutineHeadAfter(T, P)) then
      Exit(T.Low);
    T := P;
  end;
end;

// Text der Zeilen ab (ALine1, ACol1) bis vor (ALine2, ACol2).
function RawBetween(AMap: TRdxCodeMap; ALine1, ACol1, ALine2,
  ACol2: Integer): string;
var
  Lines : TArray<string>;
  L     : Integer;
begin
  if ALine1 = ALine2 then
    Exit(Copy(AMap.Raw(ALine1), ACol1, ACol2 - ACol1));
  Lines := nil;
  AppendTo(Lines, Copy(AMap.Raw(ALine1), ACol1, MaxInt));
  for L := ALine1 + 1 to ALine2 - 1 do
    AppendTo(Lines, AMap.Raw(L));
  AppendTo(Lines, Copy(AMap.Raw(ALine2), 1, ACol2 - 1));
  Result := JoinWith(Lines, sLineBreak);
end;

// Der Quelltext des Werts hinter '=' bis vor das ';' auf Klammertiefe 0
// (Strings sind keine Token); '' ohne ';'.
function ValueTextAfter(AMap: TRdxCodeMap; const AEq: TRdxToken): string;
var
  T     : TRdxToken;
  Depth : Integer;
  n     : Integer;
begin
  Result := '';
  Depth := 0;
  T := After(AMap, AEq);
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Exit;
    if (T.Low = '(') or (T.Low = '[') then
      Inc(Depth)
    else if (T.Low = ')') or (T.Low = ']') then
      Dec(Depth)
    else if (T.Low = ';') and (Depth = 0) then
      Exit(Trim(RawBetween(AMap, AEq.Line, AEq.EndCol, T.Line, T.Col)));
    T := After(AMap, T);
  end;
end;

// 'Name =': Konstante (const-Section), sonst Typ, Aufzaehlungswert oder
// resourcestring (dkOther); False bei einem Vergleich im Code.
function EqualsDeclAt(AMap: TRdxCodeMap; const T, P, N: TRdxToken;
  var D: TSqlDecl): Boolean;
begin
  Result := True;
  if (P.Low = '(') or (P.Low = ',') or (P.Low = 'type') then
    D.Kind := dkOther
  else if not InList(P.Low, CONST_LEADS) then
    Result := False
  else if SectionOf(AMap, T) = 'const' then
  begin
    D.Kind := dkConst;
    D.Text := ValueTextAfter(AMap, N);
  end
  else
    D.Kind := dkOther;
end;

// Ist das Wort T (der gesuchte Name) eine Deklaration? D: welche.
function DeclAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out D: TSqlDecl): Boolean;
var
  P, N : TRdxToken;
begin
  D := Default(TSqlDecl);
  D.Line := T.Line;
  P := Before(AMap, T);
  if P.Low = '&' then
    P := Before(AMap, P);
  if (P.Low = '.') or (P.Low = '@') then
    Exit(False);   // Member eines anderen Ausdrucks, Adresse
  N := After(AMap, T);
  Result := True;
  if InList(P.Low, ROUTINE_WORDS) or (P.Low = 'property') then
    D.Kind := dkOther
  else if (N.Low = ':') or (N.Low = ',') then
    Result := TypedDeclAt(AMap, P, N, D)
  else if N.Low = '=' then
    Result := EqualsDeclAt(AMap, T, P, N, D)
  else
    Result := False;
end;

procedure AddDecl(var ADecls: TSqlDecls; var ACount: Integer;
  const D: TSqlDecl);
begin
  if ACount = Length(ADecls) then
    SetLength(ADecls, ACount * 2 + 4);
  ADecls[ACount] := D;
  Inc(ACount);
end;

function DeclsOf(AMap: TRdxCodeMap; const AName: string): TSqlDecls;
var
  Low   : string;
  L     : Integer;
  c     : Integer;
  D     : TSqlDecl;
  Count : Integer;
begin
  Result := nil;
  Count := 0;
  Low := LowerCase(AName);
  for L := 1 to AMap.LineCount do
  begin
    c := WordCol(AMap, L, Low, 1);
    while c > 0 do
    begin
      if DeclAt(AMap, TokenAt(AMap, L, c), D) then
        AddDecl(Result, Count, D);
      c := WordCol(AMap, L, Low, c + Length(Low));
    end;
  end;
  SetLength(Result, Count);
end;

// Erstes Token hinter 'implementation' (Unit), sonst das erste der Datei
// (Programm, Bibliothek).
function BodyStart(AMap: TRdxCodeMap): TRdxToken;
var
  T, P : TRdxToken;
  n    : Integer;
begin
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  Result := T;
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Exit;
    if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      Exit(After(AMap, T));
    P := T;
    T := After(AMap, T);
  end;
end;

// Die Zeilen der Routinen mit Rumpf ab BodyStart (Kopf bis letztes ';');
// lokale Routinen liegen in ihnen.
procedure AddRange(var ARanges: TArray<TSqlLineRange>; var ACount: Integer;
  const R: TRdxRoutine);
begin
  if ACount = Length(ARanges) then
    SetLength(ARanges, ACount * 2 + 8);
  ARanges[ACount].First := R.Head.Line;
  ARanges[ACount].Last  := R.Last.Line;
  Inc(ACount);
end;

function RoutineRanges(AMap: TRdxCodeMap): TArray<TSqlLineRange>;
var
  T, P  : TRdxToken;
  R     : TRdxRoutine;
  n     : Integer;
  Count : Integer;
begin
  Result := nil;
  Count := 0;
  T := BodyStart(AMap);
  P := Before(AMap, T);
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Break;
    if IsRoutineHeadAfter(T, P)
       and (TRdxRoutineFixes.ReadRoutine(AMap, T, R) = '')
       and (R.Body.Low <> '') then
    begin
      AddRange(Result, Count, R);
      T := R.Last;
    end;
    P := T;
    T := After(AMap, T);
  end;
  SetLength(Result, Count);
end;

// Gilt eine Konstante aus ADeclLine an AUseLine? Davor deklariert und - in
// einer Routine - nicht hinter deren Ende.
function Visible(ADeclLine, AUseLine: Integer;
  const ARanges: TArray<TSqlLineRange>): Boolean;
var
  i : Integer;
begin
  Result := ADeclLine < AUseLine;
  if not Result then Exit;
  for i := 0 to High(ARanges) do
    if (ADeclLine >= ARanges[i].First) and (ADeclLine <= ARanges[i].Last) then
      Exit(AUseLine <= ARanges[i].Last);
end;

// Ein Wert, wenn alle sichtbaren Konstanten dasselbe einfache Literal
// tragen; sonst sckKept.
function ConstOfValues(const AValues: TArray<string>): TRdxSqlConst;
var
  i     : Integer;
  Value : string;
begin
  Result := Default(TRdxSqlConst);
  Result.Kind := sckKept;
  for i := 0 to High(AValues) do
  begin
    if not TRdxRecipes.DecodeLiteral(AValues[i], Value) or (AValues[i] = '') then
      Exit;
    if (i > 0) and (Value <> Result.Value) then
      Exit;
    Result.Value := Value;
  end;
  Result.Kind := sckLiteral;
end;

function SqlConstOf(AMap: TRdxCodeMap; const AName: string;
  ALine: Integer): TRdxSqlConst;
var
  Decls  : TSqlDecls;
  Ranges : TArray<TSqlLineRange>;
  Values : TArray<string>;
  i      : Integer;
begin
  Result := Default(TRdxSqlConst);
  if not Assigned(AMap) or not TRdxRecipes.IsPlainIdent(Trim(AName)) then Exit;
  Decls := DeclsOf(AMap, Trim(AName));
  if Length(Decls) = 0 then Exit;
  for i := 0 to High(Decls) do
    if Decls[i].Kind <> dkConst then Exit;
  Ranges := RoutineRanges(AMap);
  Values := nil;
  for i := 0 to High(Decls) do
    if Visible(Decls[i].Line, ALine, Ranges) then
      AppendTo(Values, Decls[i].Text);
  if Length(Values) > 0 then
    Result := ConstOfValues(Values);
end;

function ExecSqlReceiverOf(const ATarget: string): string;
var
  T : string;
begin
  Result := '';
  T := Trim(ATarget);
  if (Length(T) > Length(EXEC_SQL))
     and (LowerCase(Copy(T, Length(T) - Length(EXEC_SQL) + 1, MaxInt)) = EXEC_SQL) then
    Result := Copy(T, 1, Length(T) - Length(EXEC_SQL));
end;

function FireDacConnectionProven(AMap: TRdxCodeMap;
  const AUsesNames: TArray<string>; const AReceiver: string): Boolean;
var
  Name      : string;
  Decls     : TSqlDecls;
  i         : Integer;
  HasClient : Boolean;
begin
  Result := False;
  Name := Trim(AReceiver);
  if SameText(Copy(Name, 1, 5), 'self.') then
    Delete(Name, 1, 5);
  if not Assigned(AMap) or not TRdxRecipes.IsPlainIdent(Name) then Exit;
  HasClient := False;
  for i := 0 to High(AUsesNames) do
    HasClient := HasClient or SameText(Trim(AUsesNames[i]), FIREDAC_CLIENT);
  if not HasClient then Exit;
  Decls := DeclsOf(AMap, Name);
  if Length(Decls) = 0 then Exit;
  for i := 0 to High(Decls) do
    if (Decls[i].Kind <> dkTyped) or not InList(Decls[i].Text, FIREDAC_CONNECTION) then
      Exit;
  Result := True;
end;

procedure AddSqlFacts(AMap: TRdxCodeMap; var AReq: TRdxSqlRequest);
var
  i : Integer;
begin
  SetLength(AReq.Consts, Length(AReq.Parts));
  for i := 0 to High(AReq.Parts) do
    if (AReq.Parts[i].Role = ROLE_OPERAND) and not AReq.Parts[i].InWith
       and not AReq.InWith and (i <= High(AReq.PartLines)) then
      AReq.Consts[i] := SqlConstOf(AMap, AReq.Parts[i].Text, AReq.PartLines[i]);
  if AReq.IsCall and not AReq.InWith
     and FireDacConnectionProven(AMap, AReq.UsesNames,
       ExecSqlReceiverOf(AReq.Target)) then
    AReq.Binding := sbFireDacExecSql;
end;

end.
