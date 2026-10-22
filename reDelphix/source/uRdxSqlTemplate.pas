unit uRdxSqlTemplate;

// reDelphix - Rezept 5.2: die parametrisierte SQL-Vorlage zu SCA003
// (Charge S1, 2026-10-15; bis dahin TRdxRecipes.BuildSqlTemplate). Reine
// Textlogik ohne ToolsAPI - laeuft im FPC-Pruefstand. Die Vorlage geht nur
// in die Zwischenablage, geschrieben wird nichts.
//
// SCHNITT (Review Woche G01-03): diese Unit liest den SQL-Text der Kette
// (Maskierungen, Parameternamen, der Leser) und setzt die Vorlage
// zusammen. Die Fakten am Pascal-Quelltext - Konstanten-Beweis
// (SqlConstOf), FireDAC-/ADO-Nachweis, die Kette Q.SQL.Add - rechnet
// uRdxSqlFacts (AddSqlFacts) in die Anfrage; BuildSqlTemplate fragt den
// Quelltext nie. Die Punkte 2 und 3 unten gelten fuer beide Units.
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
//        nehmen dort Parameter - aber nur fuer IntToStr(x): ein anderer
//        Operand ist in Pascal ein Text, MySQL bindet ihn als 'LIMIT ''10'''
//        (Syntaxfehler; Gegen-Review S1, Verdacht b). TOP, FIRST und SKIP
//        nicht: SQL Server verlangt TOP (@n) mit Klammern, Access/Jet nur
//        eine Zahl, Firebird FIRST (?) mit Klammern.
//    Alles andere lehnt ab, mit dem Wort davor im Grund - Bezeichner-
//    Positionen (FROM, JOIN, INTO, UPDATE, TABLE, ORDER BY, GROUP BY,
//    Spalten- und SELECT-Liste, Funktionsargumente: ein Argument kann
//    eine Spalte sein), ein nackter Operand in einer Join-Bedingung (ON:
//    'a.id = ' + X ist meist eine Spalte; IntToStr(x), QuotedStr(x) und ein
//    SQL-String sind Werte - Minor 1), ein Operand, der an einem Bezeichner
//    klebt ('col_' + X, X + '_tmp', 'tbl.' + X), in einem gequoteten Namen
//    oder einem SQL-Kommentar steht. Eine Anweisung, die mit CREATE, ALTER,
//    DROP, TRUNCATE, RENAME, COMMENT, GRANT oder REVOKE beginnt, hat keine
//    Parameter (DDL/DCL); ebenso ein prozeduraler Block (BEGIN, DECLARE,
//    Firebird EXECUTE BLOCK). Diese Sperre gilt fuer den REST des Texts,
//    auch hinter ';' - dort beginnt der Rumpf einer Prozedur oder eines
//    Triggers, keine neue Anweisung (Major 2). Sonst muss die Anweisung
//    mit einem DML-Wort beginnen (SELECT, INSERT, UPDATE, DELETE, MERGE,
//    WITH, REPLACE, UPSERT) oder - als Bruchstueck ('Q.SQL.Add(..)', 'S :=
//    S + ..') - mit einer Klausel (WHERE, AND, OR, HAVING, VALUES, LIMIT,
//    OFFSET, FROM, JOIN ...); sonst ist nicht sichtbar, ob ein '=' einen
//    Wert erwartet ('ENGINE=' in einem CREATE TABLE, 'SET NAMES'). Ein
//    '?' im Text (positionaler Platzhalter) mischt sich nicht mit
//    benannten - abgelehnt (Verdacht c).
//    Ein Operand IN einem SQL-String ('.. LIKE ''%' + X + '%''') macht
//    den GANZEN String zum Parameter, sein Wert ist der zusammengesetzte
//    Ausdruck ('%' + X + '%'); die Position des Strings entscheidet wie
//    oben. N'..' (nationaler String) zaehlt wie '..', ein '::typ'
//    (PostgreSQL-Cast) darf hinter dem Wert stehen (Minor 10). Ein
//    Operand bzw. SQL-String allein in IN (...) bzw. VALUES (...) kann eine
//    ganze Liste sein ('1,2,3', ''' + X + ''' mit X = '1'',''2') -
//    abgelehnt, ausser IntToStr(x) und QuotedStr(x): sie ergeben genau
//    EINEN Wert (Minor 1 und 10).
//    Ein Wert ausserhalb eines Strings: IntToStr(x), QuotedStr(x) und
//    AnsiQuotedStr(x, '''') binden x selbst (QuotedStr setzte die Quotes,
//    die der Parameter nicht braucht; IntToStr macht aus einer Zahl einen
//    Text). Ein schon maskierter Wert (Review FB, R2-06): verdoppelt ein
//    Operand IN einem SQL-String die Apostrophe (StringReplace(x, '''',
//    '''''', [rfReplaceAll]), ReplaceStr/ReplaceText, x.Replace(..), auch
//    Trim(x).Replace(..)), ist sein Wert x; jeder andere Aufruf mit 'quote'
//    oder 'escape' im Namen (EscapeString, QuotedStr im String,
//    AnsiQuotedStr(x, '"'), auch ohne Klammern als Glied hinter einem
//    Punkt: x.QuotedString) und jedes andere Literal mit Apostroph im
//    Operanden (StringReplace ohne rfReplaceAll, x.Replace(..).Trim)
//    sperrt - der Parameter truege die Maskierung in die Daten. Den Inhalt
//    einer Variable sieht die Vorlage nicht.
//    Ein Zeilenkommentar ('-- ..') endet am Zeilenende - auch an
//    sLineBreak/LineEnding zwischen zwei Literalen (Minor 10).
// 2. Konstanten. Ein Operand, der am Quelltext als untypisierte Konstante
//    nachgewiesen ist (SqlConstOf - ein Name in GROSSBUCHSTABEN beweist
//    nichts), wird nie Parameter. Ist ihr Wert ein einfaches String-
//    Literal, LIEST die Vorlage ihn mit (Position, Strings, Platzhalter),
//    in der Vorlage bleibt aber ihr NAME stehen ('.. FROM ' + TBL + '
//    WHERE id = :Id'; Gegen-Review S1, Major 1 - bis dahin kam der Wert in
//    den Text, und die Vorlage verlor die Konstante). Oeffnet oder
//    schliesst ihr Wert einen SQL-String, der Parameter wird, muesste die
//    Vorlage die Konstante zerschneiden - abgelehnt. Ohne einfachen Wert
//    bleibt sie als stehender Ausdruck; steht sie im Code direkt vor oder
//    hinter einem Operanden, ist nicht sichtbar, wo der Wert beginnt bzw.
//    endet - abgelehnt (sonst wanderte ' AND active = ' + '1' in den Wert
//    des Parameters). sLineBreak/LineEnding bleiben als
//    Verkettung und gelten als Leerraum, das Ziel selbst ('S := S + ..')
//    bleibt stehen. Bleibt kein Operand: keine Vorlage, "nur Konstanten".
//    Sichtbar (Minor 5) ist eine Konstante der Unit ab ihrer Deklaration -
//    aber nicht in einer Methode einer Klasse, die Member von ausserhalb
//    der Datei erbt (class(TForm), Helper): dort bindet ein geerbtes Member
//    gleichen Namens ('Name' aus TComponent) vor der Unit-Konstante (Review
//    FB, R2-05) -, eine lokale bis zum Ende IHRER Routine (auch einer
//    verschachtelten), eine Klassen- bzw. Record-Konstante nur in den
//    Methoden dieser Klasse (Kopf 'TKlasse.Methode'). Den Beweis verwerfen
//    jede andere
//    Deklaration des Namens, auch eine Inline-Variable ('var X := ..',
//    'for var X in ..', Blocker), 'on X: E do' und eine Inline-Konstante
//    im Rumpf (sie gilt nur in ihrem Block). Die Routinen- und Typgrenzen
//    rechnet AddSqlFacts einmal je Anfrage (Minor 6).
// 3. Ziel. Query-Objekt (Glied .SQL/.CommandText): ParamByName-Zeilen; ist
//    das Objekt in der Datei ueberall als TADOQuery, TADOCommand,
//    TADODataSet oder TADOStoredProc deklariert und nennen die uses
//    Data.Win.ADODB bzw. ADODB (AdoObjectProven), '.Parameters.ParamByName'
//    - die ADO-Klassen haben kein ParamByName (Minor 11). Nicht
//    nachweisbar (Objekt aus einem Datenmodul, einer anderen Unit): wie
//    bisher ParamByName - bei ADO von Hand '.Parameters.' einfuegen.
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
//    Kette (Major 2, Verdacht a): bei 'Q.SQL.Add(..)' liest AddSqlFacts
//    die frueheren Q.SQL.Add-Zeilen derselben Routine bis zu Q.SQL.Clear
//    bzw. Q.SQL.Text := (ChainWith) - die Vorlage liest sie stumm vor dem
//    eigenen Text: sie bestimmen Anweisungsart und DDL-Sperre mit ('CREATE
//    VIEW v AS' in der Zeile davor). Ihre Platzhalter und die der
//    spaeteren Q.SQL.Add-Zeilen sind vergeben. Nicht gesehen: eine
//    fruehere Anweisung auf derselben Zeile, with-Bloecke, andere
//    Schreibweisen (SQL.Insert, Assign, ein Puffer 'S := S + ..') - dort
//    endet die Kette. Zwei noch nicht umgestellte Zeilen koennen denselben
//    Namen vorschlagen (AId und FId -> :Id); ist die erste Vorlage
//    eingefuegt, sieht die zweite ihren Platzhalter.
// 4. Namen (SqlParamName) aus dem Operanden: AColumnTypes -> ColumnTypes,
//    FId -> Id, Edit1.Text -> Edit1Text, IntToStr(Id) -> Id (der erste
//    Pfad, der kein Aufrufkopf ist); A/F vor einem Wort mit Grossbuchstabe
//    faellt weg (ADOQuery1 bleibt); nur Buchstaben, Ziffern, '_' - ein
//    Name mit Zeichen ueber ASCII ('Groesse' mit sz) wird pN (Minor 3);
//    hoechstens MAX_NAME Zeichen, auch mit Nummer (Minor 2); ein SQL-Wort
//    (Oracle-reserviert und SQL-92-Kern, RESERVED_NAMES) bekommt ein 'p'
//    davor (Oracle: ORA-01745 bei :date, :rows, :start ...); Ersatz pN.
//    Kollisionen mit vorhandenen Platzhaltern und untereinander bekommen
//    2, 3, ... angehaengt. Die vorhandenen liest SqlPlaceholders nach den
//    Regeln von SCA199 (uParamNameScan): '::' (PostgreSQL-Cast), ':=',
//    ':1', ':new.', ein ':' direkt hinter einem Bezeichner, ')' oder ']'
//    sind keine.

interface

uses
  uRdxRecipes;     // TRdxPart(s), Literal-Codec, Query-Objekt des Ziels

type
  // Was am Quelltext ueber einen Operanden bewiesen ist (SqlConstOf).
  TRdxSqlConstKind = (
    sckNone,      // keine Konstante (oder nicht nachgewiesen)
    sckLiteral,   // untypisierte Konstante, Wert ein einfaches String-
                  // Literal: wird mitgelesen, der Name bleibt stehen
    sckKept);     // untypisierte Konstante mit anderem Wert: bleibt Verkettung

  TRdxSqlConst = record
    Kind  : TRdxSqlConstKind;
    Value : string;   // sckLiteral: der Wert (dekodiert)
  end;
  TRdxSqlConsts = TArray<TRdxSqlConst>;

  // Wie die Werte an die Parameter kommen (Kopf der Unit, Punkt 3).
  TRdxSqlBinding = (
    sbByTarget,         // Query-Objekt: X.ParamByName(..) (Q.SQL.Add)
    sbFireDacExecSql,   // X.ExecSQL(SQL, [Werte]) - FireDAC nachgewiesen
    sbAdoParameters);   // X.Parameters.ParamByName(..) - ADO nachgewiesen

  // Die Anfrage an BuildSqlTemplate. Parts in Quelltext-Reihenfolge,
  // Parts[0] darf ROLE_TARGET sein. Die Fakten am Quelltext (Consts,
  // Binding, Prefix, ChainNames) setzt AddSqlFacts (uRdxSqlFacts) aus
  // PartLines (Zeile je Part), InWith (die Anweisung steht in einem
  // with-Block: kein Name ist bewiesen) und UsesNames; ohne sie gilt kein
  // Operand als Konstante, kein Aufruf als FireDAC, kein Objekt als ADO,
  // und es gibt keine Kette.
  TRdxSqlRequest = record
    Target     : string;
    IsCall     : Boolean;
    Parts      : TRdxParts;
    Indent     : string;     // Einrueckung jeder Zeile, Tabs bleiben Tabs
    PartLines  : TArray<Integer>;
    InWith     : Boolean;
    UsesNames  : TArray<string>;
    Consts     : TRdxSqlConsts;   // je Part (gleicher Index)
    Binding    : TRdxSqlBinding;
    // Kette 'Q.SQL.Add' (Kopf der Unit, Punkt 3): der SQL-Text der
    // frueheren Zeilen, je mit Zeilenende - stumm vor dem eigenen Text
    // gelesen; und die Platzhalter der Kette (klein), die kein neuer Name
    // treffen darf.
    Prefix     : string;
    ChainNames : TArray<string>;
  end;

  TRdxSqlTemplate = record
    Text       : string;    // die Vorlage (Zeilen mit sLineBreak)
    Reason     : string;    // bei False
    Params     : Integer;   // Parameter in der Vorlage
    ConstsRead : Integer;   // Konstanten, deren Wert mitgelesen wurde
  end;

// Rezept 5.2 (Kopf der Unit). False mit Grund in AResult.Reason.
function BuildSqlTemplate(const AReq: TRdxSqlRequest;
  out AResult: TRdxSqlTemplate): Boolean;
// Hinweis fuer das Menue: 'n Parameter[, k Konstante(n) mitgelesen],
// nichts wird geschrieben'.
function SqlHintOf(const AResult: TRdxSqlTemplate): string;
// Parametername aus einem Operanden (Kopf der Unit, Punkt 4); '' ohne
// verwertbaren Bezeichner.
function SqlParamName(const AExpr: string): string;
// Die Platzhalter im SQL-Text (klein, Regeln von SCA199).
function SqlPlaceholders(const ASql: string): TArray<string>;
// Der SQL-Text einer Pascal-Verkettung (Argument von Q.SQL.Add, Wert von
// Q.SQL.Text :=) in der Form, die BuildSqlTemplate in AReq.Prefix liest:
// Literale dekodiert, sLineBreak/LineEnding als Zeilenende, jeder andere
// Term als Marke eines stehenden Ausdrucks (Kopf der Unit, Punkt 3).
// AddSqlFacts (uRdxSqlFacts) baut daraus die Kette.
function SqlChainTextOf(const ARaw: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,    // PosEx (CommentEnd)
  uRefactorInfo,      // ROLE_TARGET, ROLE_LITERAL, ROLE_OPERAND
  uRdxCodeMap;        // IsIdentChar, InList, AddText ...

const
  // Gruende - deutsch ohne Umlaute wie in den Nachbar-Units (Statustext).
  R_NAMES = 'Tabellen-/Spaltennamen und DDL lassen sich nicht '
    + 'parametrisieren - Namen pruefen/Whitelist';
  R_OPERAND     = 'Operand ''%s'' ';
  R_DDL         = 'DDL/DCL (%s ...): ' + R_NAMES;
  R_BLOCK       = 'prozeduraler Block (%s ...) - Parameter einer Anweisung '
    + 'gelten darin nicht; von Hand';
  R_JOIN_ON     = R_OPERAND + 'steht in einer Join-Bedingung (ON) - dort '
    + 'ist meist eine Spalte gemeint. ' + R_NAMES;
  R_LIMIT_TEXT  = R_OPERAND + 'hinter %s ist ein Text - MySQL setzt ihn als '
    + 'String ein (''10'' statt 10, Syntaxfehler); nur IntToStr(x) bindet eine '
    + 'Zahl';
  R_CUT         = R_OPERAND + 'steht in einem SQL-String, den eine Konstante '
    + 'oder eine fruehere Zeile der Kette oeffnet bzw. schliesst - die '
    + 'Vorlage muesste sie zerschneiden; von Hand';
  R_QMARK       = 'der SQL-Text traegt einen positionalen Platzhalter ''?'' - '
    + 'benannte Parameter mischen sich damit nicht; von Hand';
  // R_NOT_VALUE, R_AFTER_EXPR: das zweite %s ist TokShown (ein Wort in
  // Quotes oder 'einer Zahl', 'einem Ausdruck ..').
  R_NOT_VALUE   = R_OPERAND + 'steht hinter %s - dort erwartet SQL '
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
  R_AFTER_EXPR  = R_OPERAND + 'folgt direkt auf %s - ob dort ein Wert '
    + 'steht, ist nicht sichtbar';
  R_BEFORE_EXPR = R_OPERAND + 'steht direkt vor ''%s'' - ob der Wert dort '
    + 'endet, ist nicht sichtbar';
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
  // Review FB, R2-06: ein schon maskierter Wert ('O''Brien' bzw. mit
  // Quotes) truege die Maskierung in die Daten des Parameters.
  R_ESCAPED     = R_OPERAND + 'ist schon fuer SQL-Text maskiert (%s) - ein '
    + 'Parameter braucht den Rohwert; Maskierung entfernen, von Hand';

  // Maskierungs-Formen (R2-06): ersetzen ALLE Vorkommen (StrUtils) - mit
  // '''' -> '''''' verdoppeln sie die Apostrophe.
  REPLACE_ALL_FUNCS: array[0..3] of string = ('replacestr', 'ansireplacestr',
    'replacetext', 'ansireplacetext');
  // Argumente der Maskierungs-Formen (DoubledQuotesInner).
  ARGS_STRING_REPLACE = 4;   // StringReplace(x, '''', '''''', [rfReplaceAll])
  ARGS_REPLACE_STR    = 3;   // ReplaceStr(x, '''', '''''')
  ARGS_HELPER_REPLACE = 2;   // x.Replace('''', '''''')
  ARGS_HELPER_REPLACE_FLAGS = 3;   // x.Replace('''', '''''', [rfReplaceAll])
  // Was R_ESCAPED in der Klammer nennt, wenn kein maskierender Aufruf es
  // ist (EscapeMarkOf; Nachpruefung R2-06).
  MARK_DOUBLED       = 'verdoppelte Apostrophe';
  MARK_QUOTE_LITERAL = 'Literal mit Apostroph';
  // Zeichen eines #-Codes hinter dem '#' ('#39', '#$27').
  CHAR_CODE_CHARS = ['$', '0'..'9', 'A'..'F', 'a'..'f'];
  // Davor darf QuotedStr/AnsiQuotedStr stehen (wie CallArg).
  SYSUTILS_QUALIFIERS: array[0..2] of string = ('', 'sysutils',
    'system.sysutils');

  // Erste Woerter einer Anweisung (Kopf der Unit, Punkt 1).
  DDL_HEADS: array[0..7] of string = ('create', 'alter', 'drop', 'truncate',
    'rename', 'comment', 'grant', 'revoke');
  // Beginnt ein prozeduraler Block (Firebird 'EXECUTE BLOCK' ueber
  // BLOCK_AFTER_EXECUTE): auch er sperrt den Rest des Texts (Major 2).
  BLOCK_HEADS: array[0..1] of string = ('begin', 'declare');
  HEAD_EXECUTE = 'execute';
  WORD_BLOCK   = 'block';
  // Diese Woerter beenden eine Join-Bedingung (ON) bzw. beginnen sie.
  CLAUSE_WORDS: array[0..19] of string = ('on', 'where', 'join', 'inner',
    'left', 'right', 'full', 'cross', 'group', 'order', 'having', 'union',
    'limit', 'offset', 'set', 'values', 'select', 'from', 'returning',
    'using');
  CLAUSE_ON = 'on';
  // Dahinter nimmt SQL nur eine Zahl (Verdacht b).
  NUMBER_AFTER: array[0..1] of string = ('limit', 'offset');
  // Ein Buchstabe direkt vor einem String: N'..' (nationaler String).
  NATIONAL_PREFIX = 'n';
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
  // Als Parametername nicht ohne 'p' davor (Oracle ORA-01745 - die
  // reservierten Woerter von Oracle, dazu der SQL-92-Kern und die Woerter
  // der Liste bis Charge SQc; Gegen-Review S1, Minor 2).
  RESERVED_NAMES: array[0..161] of string = ('access', 'add', 'all', 'alter',
    'and', 'any', 'as', 'asc', 'audit', 'begin', 'between', 'both', 'by',
    'case', 'cast', 'char', 'check', 'cluster', 'collate', 'column',
    'comment', 'compress', 'connect', 'constraint', 'create', 'cross',
    'current', 'current_date', 'current_time', 'current_timestamp',
    'current_user', 'date', 'day', 'decimal', 'declare', 'default', 'delete',
    'desc', 'distinct', 'double', 'drop', 'else', 'end', 'escape', 'except',
    'exclusive', 'exists', 'false', 'fetch', 'file', 'first', 'float', 'for',
    'foreign', 'from', 'full', 'grant', 'group', 'having', 'hour',
    'identified', 'immediate', 'in', 'increment', 'index', 'initial', 'inner',
    'insert', 'integer', 'intersect', 'interval', 'into', 'is', 'join', 'key',
    'leading', 'left', 'level', 'like', 'limit', 'lock', 'long', 'maxextents',
    'minus', 'minute', 'mlslabel', 'mode', 'modify', 'month', 'natural',
    'next', 'noaudit', 'nocompress', 'not', 'nowait', 'null', 'number', 'of',
    'offline', 'offset', 'on', 'online', 'only', 'option', 'or', 'order',
    'outer', 'pctfree', 'position', 'primary', 'prior', 'public', 'raw',
    'references', 'rename', 'resource', 'revoke', 'right', 'row', 'rowid',
    'rownum', 'rows', 'second', 'select', 'session', 'set', 'share', 'size',
    'smallint', 'some', 'start', 'successful', 'synonym', 'sysdate', 'table',
    'then', 'time', 'timestamp', 'to', 'trailing', 'trigger', 'true', 'type',
    'uid', 'union', 'unique', 'unknown', 'update', 'user', 'using',
    'validate', 'value', 'values', 'varchar', 'varchar2', 'view', 'when',
    'whenever', 'where', 'with', 'year', 'zone');
  // Kommentarzeile vor ParamByName, wenn das Ziel ein String-Puffer ist.
  BIND_COMMENT = '// Parameter binden: ';
  // Vor dem Token eines stehenden Ausdrucks (TakeKept): kein SQL-Wort
  // trifft es, der Grund zeigt den Ausdruck (R_AFTER_EXPR). Allein steht es
  // im Text der Kette fuer einen Ausdruck einer frueheren Zeile (AppendTerm,
  // StepCode) - dessen Text kennt der Leser nicht.
  KEPT_MARK = #1;
  // Die Token eines Werts (PushTok): eine Zahl, ein SQL-String, ein
  // Platzhalter. Mit #2 davor trifft sie kein SQL-Wort ('WHERE n = ..'),
  // der Grund nennt sie in Worten (TokShown).
  TOK_NUMBER      = #2'n';
  TOK_STRING      = #2's';
  TOK_PLACEHOLDER = #2'v';
  SHOWN_NUMBER      = 'einer Zahl';
  SHOWN_STRING      = 'einem SQL-String';
  SHOWN_PLACEHOLDER = 'einem Platzhalter';
  SHOWN_CHAIN_EXPR  = 'einem Ausdruck einer frueheren Zeile';
  // Head einer Anweisung, die nicht mit einem Wort beginnt.
  HEAD_UNKNOWN = '?';
  MAX_NAME  = 30;    // Zeichen eines Parameternamens (Oracle: 30)
  // Zeichen eines Parameternamens im SQL-Text (TParams.ParseSQL).
  NAME_CHARS = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  // 'FId': A/F, Grossbuchstabe, Kleinbuchstabe - erst ab drei Zeichen ist
  // ein Praefix vor einem Wort zu erkennen (WithoutPrefix).
  MIN_PREFIXED = 3;
  MAX_SHOWN = 40;    // so viel vom Operanden im Grund

  // Davor steht ParamByName beim nachgewiesenen ADO-Objekt (QueryPrefixOf;
  // den Nachweis fuehrt AdoObjectProven in uRdxSqlFacts).
  ADO_PARAMETERS = 'Parameters.';

type
  // ---- die Kette als Segmente ----

  TSqlSegKind = (skText, skOperand, skKept, skConst, skChain);

  // Ein Stueck der Kette fuer den Leser: SQL-Text (Literale, zusammen-
  // gelegt), ein Operand (wird Parameter oder lehnt ab), ein Ausdruck, der
  // stehen bleibt (Konstante ohne einfachen Wert, sLineBreak - dann Blank
  // -, das Ziel selbst bei 'S := S + ..'), eine Konstante mit einfachem
  // Wert (Text ihr Wert - mitgelesen -, Expr ihr Name - ausgegeben) oder
  // die frueheren Zeilen der Kette (nur gelesen, Kopf der Unit, Punkt 3).
  TSqlSeg = record
    Kind  : TSqlSegKind;
    Text  : string;     // skText/skConst/skChain: SQL-Text; sonst Pascal
    Expr  : string;     // skConst: der Name der Konstante
    Blank : Boolean;    // skKept: gilt im SQL als Leerraum
  end;
  TSqlSegs = TArray<TSqlSeg>;

  TSqlSegCount = record
    Terms      : Integer;   // Literal- und Operanden-Parts bisher
    All        : Integer;   // Operanden-Parts
    Ops        : Integer;   // davon Operanden (keine Konstante, kein Ziel)
    Consts     : Integer;   // davon Konstanten (auch sLineBreak)
    ConstsRead : Integer;   // davon Konstanten mit mitgelesenem Wert
  end;

  // ---- der Leser ----

  // Ein Stueck der Ausgabe: SQL-Text oder ein Pascal-Ausdruck; Tail ist
  // bei einem Ausdruck das letzte SQL-Zeichen zur Laufzeit (eine Konstante:
  // das letzte ihres Werts), #0 unbekannt - davon haengt ab, ob ein
  // Platzhalter ein Leerzeichen davor braucht (AddParam).
  TSqlPiece = record
    IsExpr : Boolean;   // Pascal-Ausdruck statt SQL-Text
    Text   : string;
    Tail   : Char;
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
  // das Token davor), das erste Wort der Anweisung (Head), die Sperre fuer
  // den Rest des Texts (Lock), die letzte Klausel und - waehrend ein
  // SQL-String offen ist - dessen Umfeld und Inhalt. Mute: der Leser liest
  // den Wert einer Konstante bzw. die Kette - ohne Ausgabe.
  TSqlScan = record
    Segs      : TSqlSegs;
    Mode      : TSqlLexMode;
    NameEnd   : Char;            // lmName: das schliessende Zeichen
    Tok       : TSqlTok3;
    Openers   : TArray<string>;
    Head      : string;          // '' = noch kein Wort in dieser Anweisung
    Lock      : string;          // DDL-/Block-Kopf, gross; '' = keine Sperre
    Clause    : string;          // letztes Klausel-Wort (CLAUSE_WORDS)
    QMarks    : Integer;         // '?' im Code
    LastCh    : Char;            // letztes SQL-Zeichen (Klebeprobe)
    Mute      : Boolean;
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
    StrMuted  : Boolean;         // geoeffnet in einer Konstante / der Kette
    StrParts  : TArray<string>;  // Wert als Pascal-Stuecke
    StrBuf    : string;          // Text seit dem letzten Stueck
    StrFirst  : string;          // erster Operand im String ('' = keiner)
    Reason    : string;
  end;

{ ---- kleine Helfer ---- }

function CharAt(const S: string; AIndex: Integer): Char;
begin
  if (AIndex >= 1) and (AIndex <= Length(S)) then
    Result := S[AIndex]
  else
    Result := #0;
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

// Hinter das String-Literal ab AText[i] (ein Quote; '' sind zwei Literale).
procedure SkipLiteral(const AText: string; var i: Integer);
begin
  Inc(i);
  while (i <= Length(AText)) and (AText[i] <> '''') do
    Inc(i);
  Inc(i);
end;

{ ---- Maskierte Werte (Review FB, R2-06) ----
  Ein Operand, der seinen Wert schon fuer SQL-Text maskiert, darf nicht
  woertlich Parameter werden: 'StringReplace(X, '''', '''''', ..)' in einem
  SQL-String bzw. 'AnsiQuotedStr(X, '''')' als Wert truegen O''Brien bzw.
  'O''Brien' in die Daten. Die gleichwertigen Formen binden X selbst (auch
  hinter einem Aufruf: 'Trim(X).Replace(..)' bindet Trim(X)), sofern X
  nicht selbst maskiert. Sonst sperrt (EscapeMarkOf) jeder Aufruf mit
  'quote' oder 'escape' im Namen - mit Klammern oder als Glied hinter einem
  Punkt auch ohne ('X.QuotedString', TStringHelper) - und jedes Literal mit
  einem Apostroph im Operanden: wer '''' schreibt, baut SQL-String-Syntax
  ('StringReplace(X, '''', '''''', [])' nur fuer das erste Vorkommen,
  'X.Replace(..).Trim', Format('''%s''', [X]); Nachpruefung R2-06). Nicht
  sichtbar: der Inhalt einer Variable und Konstanten als Argumente
  ('StringReplace(X, Q, QQ, ..)') - die Vorlage folgt keinem Datenfluss. }

// Die Argumente der Klammergruppe ab AText[AOpen] ('('), getrennt an
// Kommata auf oberster Ebene ausserhalb von Strings; False, wenn die
// Gruppe nicht genau am Ende von AText schliesst ('Foo(a).Bar(b)').
function TopLevelArgs(const AText: string; AOpen: Integer;
  out AArgs: TArray<string>): Boolean;
var
  i, Depth, Start : Integer;
begin
  AArgs := nil;
  Depth := 0;
  Start := AOpen + 1;
  i := AOpen;
  while i <= Length(AText) do
  begin
    if AText[i] = '''' then
    begin
      SkipLiteral(AText, i);
      Continue;
    end;
    if CharInSet(AText[i], ['(', '[']) then
      Inc(Depth)
    else if CharInSet(AText[i], [')', ']']) then
      Dec(Depth)
    else if (AText[i] = ',') and (Depth = 1) then
    begin
      AddText(AArgs, Trim(Copy(AText, Start, i - Start)));
      Start := i + 1;
    end;
    if Depth = 0 then
      Break;
    Inc(i);
  end;
  Result := i = Length(AText);
  if Result then
    AddText(AArgs, Trim(Copy(AText, Start, i - Start)));
end;

// Die '(' der LETZTEN Klammergruppe auf oberster Ebene, wenn AText mit
// ihr endet ('Trim(X).Replace(a, b)': die hinter Replace); 0 sonst.
// Strings zaehlen nicht.
function FinalGroupOpen(const AText: string): Integer;
var
  i, Depth : Integer;
begin
  Result := 0;
  Depth := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    if AText[i] = '''' then
    begin
      SkipLiteral(AText, i);
      Continue;
    end;
    if CharInSet(AText[i], ['(', '[']) then
    begin
      if (Depth = 0) and (AText[i] = '(') then
        Result := i;
      Inc(Depth);
    end
    else if CharInSet(AText[i], [')', ']']) then
      Dec(Depth);
    Inc(i);
  end;
  if (Depth <> 0) or (CharAt(AText, Length(AText)) <> ')') then
    Result := 0;
end;

// AText = '[Empfaenger.]Kopf(a, b, ..)' - Kopf ist der Name vor der
// letzten Klammergruppe (FinalGroupOpen), klein; AQual der Text vor dem
// '.' davor ('' ohne: 'SysUtils' bei 'SysUtils.QuotedStr(x)', 'Trim(X)' bei
// 'Trim(X).Replace(..)' - bis zur Nachpruefung R2-06 galt die ERSTE '(',
// und 'Trim(X).Replace(..)' war keine Form); die Argumente (TopLevelArgs).
// False, wenn AText nicht so endet oder vor dem Kopf etwas anderes als ein
// '.' steht.
function CallParts(const AText: string; out AQual, AHead: string;
  out AArgs: TArray<string>): Boolean;
var
  T, Before : string;
  Open, P   : Integer;
begin
  Result := False;
  AQual := '';
  AHead := '';
  AArgs := nil;
  T := Trim(AText);
  Open := FinalGroupOpen(T);
  if Open < 2 then Exit;
  Before := TrimRight(Copy(T, 1, Open - 1));
  P := Length(Before);
  while (P > 0) and IsIdentChar(Before[P]) do
    Dec(P);
  AHead := LowerCase(Copy(Before, P + 1, MaxInt));
  Before := TrimRight(Copy(Before, 1, P));
  if CharAt(Before, Length(Before)) = '.' then
    AQual := TrimRight(Copy(Before, 1, Length(Before) - 1))
  else if Before <> '' then
    Exit;   // 'not Foo(..)', '@Foo(..)': kein Aufruf als ganzer Operand
  Result := (AHead <> '') and TopLevelArgs(T, Open, AArgs);
end;

// Ist AText ein Empfaenger ohne Operator auf oberster Ebene ('Trim(X)',
// 'Edit1.Text')? Ein Leerraum dort trennt Terme ('A - B.Replace(..)':
// der Empfaenger ist nur B) - dann keine Form.
function IsReceiverText(const AText: string): Boolean;
var
  i, Depth : Integer;
begin
  Result := AText <> '';
  Depth := 0;
  i := 1;
  while Result and (i <= Length(AText)) do
  begin
    if AText[i] = '''' then
    begin
      SkipLiteral(AText, i);
      Continue;
    end;
    if CharInSet(AText[i], ['(', '[']) then
      Inc(Depth)
    else if CharInSet(AText[i], [')', ']']) then
      Dec(Depth)
    else if (Depth = 0) and IsBlank(AText[i]) then
      Result := False;
    Inc(i);
  end;
end;

// Nennt das Flags-Argument rfReplaceAll (alle Vorkommen)?
function HasReplaceAll(const AFlags: string): Boolean;
begin
  Result := Pos('rfreplaceall', LowerCase(AFlags)) > 0;
end;

// Ist ASource das Literal AValue (dekodiert, ''''/#39 gleich)?
function IsLiteralOf(const ASource, AValue: string): Boolean;
var
  V : string;
begin
  Result := TRdxRecipes.DecodeLiteral(ASource, V) and (V = AValue);
end;

// QuotedStr(x) bzw. AnsiQuotedStr(x, '''') - x in Apostrophen (Kopf der
// Unit, Punkt 1), bloss oder mit SysUtils davor: True mit AInner = x.
// AnsiQuotedStr mit einem anderen Zeichen ('"') ist ein Name oder ein
// Dialekt - keine Form.
function QuoteCallInner(const AText: string; out AInner: string): Boolean;
var
  Qual, Head : string;
  Args       : TArray<string>;
begin
  AInner := '';
  Result := CallParts(AText, Qual, Head, Args)
    and InList(LowerCase(Qual), SYSUTILS_QUALIFIERS)
    and (((Head = 'quotedstr') and (Length(Args) = 1))
      or ((Head = 'ansiquotedstr') and (Length(Args) = 2)
        and IsLiteralOf(Args[1], '''')))
    and (Args[0] <> '');
  if Result then
    AInner := Args[0];
end;

// Verdoppelt AText die Apostrophe von x - StringReplace(x, '''', '''''',
// [rfReplaceAll ..]), ReplaceStr/ReplaceText(x, '''', ''''''), x.Replace(
// '''', '''''') bzw. x.Replace('''', '''''', [rfReplaceAll ..]), x auch ein
// Aufruf ('Trim(X).Replace(..)')? True mit AInner = x. In einem SQL-String
// ist der Wert dann x (R2-06). Ohne rfReplaceAll verdoppeln StringReplace
// und x.Replace(.., []) nur das erste Vorkommen - keine Form.
function DoubledQuotesInner(const AText: string; out AInner: string): Boolean;
var
  Qual, Head : string;
  Args       : TArray<string>;
  First      : Integer;   // Index des Arguments '''' (dahinter '''''')
begin
  AInner := '';
  Result := False;
  if not CallParts(AText, Qual, Head, Args) then Exit;
  if (Head = 'stringreplace') and (Length(Args) = ARGS_STRING_REPLACE)
     and HasReplaceAll(Args[High(Args)]) then
    First := 1
  else if InList(Head, REPLACE_ALL_FUNCS)
     and (Length(Args) = ARGS_REPLACE_STR) then
    First := 1
  else if (Head = 'replace') and IsReceiverText(Qual)
     and ((Length(Args) = ARGS_HELPER_REPLACE)
       or ((Length(Args) = ARGS_HELPER_REPLACE_FLAGS)
         and HasReplaceAll(Args[High(Args)]))) then
    First := 0   // x.Replace(..): der Empfaenger ist x
  else
    Exit;
  if not IsLiteralOf(Args[First], '''')
     or not IsLiteralOf(Args[First + 1], '''''') then
    Exit;
  if First = 0 then
    AInner := Qual
  else
    AInner := Args[0];
  Result := AInner <> '';
end;

// Das Zeichen vor AText[AAt], Leerraum uebersprungen; #0 am Anfang.
function CharBefore(const AText: string; AAt: Integer): Char;
var
  i : Integer;
begin
  i := AAt - 1;
  while (i >= 1) and IsBlank(AText[i]) do
    Dec(i);
  Result := CharAt(AText, i);
end;

// Der erste Aufruf in AText (ausserhalb von Strings), dessen Name 'quote'
// oder 'escape' traegt, wie geschrieben; '' ohne. Aufruf heisst: ein Name
// vor '(' oder ein Glied hinter '.' - auch ohne Klammern, so ruft Delphi
// eine Methode ohne Argumente ('Edit1.Text.QuotedString', TStringHelper;
// Nachpruefung R2-06 - bis dahin galt nur 'Name('). Ein Feld oder eine
// Property gleichen Musters ('Obj.QuoteChar') sperrt mit, vorsichtig. Ein
// blosser Name ohne Klammern ist eine Variable: ihren Inhalt sieht die
// Vorlage nicht.
function EscapeCallIn(const AText: string): string;
var
  i, Start : Integer;
  W        : string;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
    if AText[i] = '''' then
      SkipLiteral(AText, i)
    else if IsIdentStart(AText[i]) then
    begin
      Start := i;
      while (i <= Length(AText)) and IsIdentChar(AText[i]) do
        Inc(i);
      W := Copy(AText, Start, i - Start);
      if ((CharAt(AText, SkipBlanks(AText, i)) = '(')
          or (CharBefore(AText, Start) = '.'))
         and ((Pos('quote', LowerCase(W)) > 0)
           or (Pos('escape', LowerCase(W)) > 0)) then
        Exit(W);
    end
    else
      Inc(i);
end;

// Ein Literal-Stueck ab AText[i] - ein '..'-Teil oder ein #-Code; i rueckt
// dahinter. True, wenn es einen Apostroph traegt: '' im Teil ('''',
// 'it''s') bzw. der Code #39/#$27.
function LiteralPieceHasQuote(const AText: string; var i: Integer): Boolean;
var
  Start : Integer;
  Value : string;
begin
  Start := i;
  Inc(i);
  if AText[Start] = '''' then
  begin
    while (i <= Length(AText)) and (AText[i] <> '''') do
      Inc(i);
    Result := CharAt(AText, i + 1) = '''';
    Inc(i);
    Exit;
  end;
  while (i <= Length(AText)) and CharInSet(AText[i], CHAR_CODE_CHARS) do
    Inc(i);
  Result := TRdxRecipes.DecodeLiteral(Copy(AText, Start, i - Start), Value)
    and (Pos('''', Value) > 0);
end;

// Traegt ein Literal in AText einen Apostroph (LiteralPieceHasQuote)?
// (Nachpruefung R2-06)
function HasQuoteLiteral(const AText: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  i := 1;
  while not Result and (i <= Length(AText)) do
    if CharInSet(AText[i], ['''', '#']) then
      Result := LiteralPieceHasQuote(AText, i)
    else
      Inc(i);
end;

// Was AText fuer SQL-Text maskiert: der Name eines maskierenden Aufrufs
// (EscapeCallIn), MARK_DOUBLED fuer die Verdoppel-Formen
// (DoubledQuotesInner), MARK_QUOTE_LITERAL fuer jedes andere Literal mit
// Apostroph (HasQuoteLiteral); '' ohne. Der Grund nennt es (R_ESCAPED).
function EscapeMarkOf(const AText: string): string;
var
  Inner : string;
begin
  Result := EscapeCallIn(AText);
  if Result <> '' then Exit;
  if DoubledQuotesInner(AText, Inner) then
    Result := MARK_DOUBLED
  else if HasQuoteLiteral(AText) then
    Result := MARK_QUOTE_LITERAL;
end;

// Ein Operand IN einem SQL-String: sein Wert im Parameter (AValue) und ''
// - oder die Maskierung, die sperrt. Verdoppelt er die Apostrophe
// (DoubledQuotesInner), ist der Wert das Argument x, sofern x nicht
// selbst maskiert ('StringReplace(QuotedStr(X), ..)'); sonst sperrt jede
// Maskierung (EscapeMarkOf).
function InStringEscape(const AText: string; out AValue: string): string;
var
  Inner : string;
begin
  AValue := AText;
  if not DoubledQuotesInner(AText, Inner) then
    Exit(EscapeMarkOf(AText));
  Result := EscapeMarkOf(Inner);
  if Result = '' then
    AValue := Inner;
end;

// Der Wert eines Operanden ausserhalb eines Strings: IntToStr(x),
// QuotedStr(x) und AnsiQuotedStr(x, '''') binden x (Kopf der Unit, Punkt 1).
function UnwrapValue(const AText: string): string;
var
  Inner : string;
begin
  Result := AText;
  if CallArg(AText, 'IntToStr', Inner) or QuoteCallInner(AText, Inner) then
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
    AddText(Result, ReadIdent(AText, i));
    while CharAt(AText, i) = '[' do
      SkipIndex(AText, i);
    if (CharAt(AText, i) <> '.') or not IsIdentStart(CharAt(AText, i + 1)) then
      Exit;
    Inc(i);
  until False;
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

// Traegt S ein Zeichen ueber ASCII?
function HasNonAscii(const S: string): Boolean;
var
  i : Integer;
begin
  for i := 1 to Length(S) do
    if S[i] > #127 then
      Exit(True);
  Result := False;
end;

// Die Glieder ohne 'Self' aneinander, das erste ohne A/F-Praefix; nur
// Zeichen eines Parameternamens. '' bei einem Zeichen ueber ASCII: aus
// 'Groesse' mit sz wurde ':Gre' (Gegen-Review S1, Minor 3) - dann pN.
function NameOfPath(const AParts: TArray<string>): string;
var
  Segs : TArray<string>;
  i    : Integer;
begin
  Segs := nil;
  for i := 0 to High(AParts) do
    if not SameText(AParts[i], 'self') then
      if Length(Segs) = 0 then
        AddText(Segs, WithoutPrefix(AParts[i]))
      else
        AddText(Segs, AParts[i]);
  Result := JoinWith(Segs, '');
  if HasNonAscii(Result) then
    Exit('');
  Result := NameCharsOf(Result);
end;

function SqlParamName(const AExpr: string): string;
begin
  Result := NameOfPath(FirstValuePath(AExpr));
  if Result = '' then Exit;
  if CharInSet(Result[1], ['0'..'9'])
     or InList(LowerCase(Result), RESERVED_NAMES) then
    Result := 'p' + Result;
  // Erst danach kuerzen: das 'p' zaehlt mit (Minor 2).
  Result := Copy(Result, 1, MAX_NAME);
end;

// ABase oder - schon vergeben - ABase2, ABase3 ...; ohne ABase pN. Mit
// Nummer hoechstens MAX_NAME Zeichen (Minor 2): die Nummer ersetzt das
// Ende.
function UniqueName(const ABase: string; const AUsed: TArray<string>;
  AIndex: Integer): string;
var
  Base, Num : string;
  k         : Integer;
begin
  Base := ABase;
  if Base = '' then
    Base := 'p' + IntToStr(AIndex);
  Result := Base;
  k := 2;
  while InList(LowerCase(Result), AUsed) do
  begin
    Num := IntToStr(k);
    Result := Copy(Base, 1, MAX_NAME - Length(Num)) + Num;
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
  ASegs[n].Expr  := '';
  ASegs[n].Blank := ABlank;
end;

// Eine Konstante mit einfachem Wert: AValue wird gelesen, AName steht in
// der Vorlage (Kopf der Unit, Punkt 2).
procedure AddConstSeg(var ASegs: TSqlSegs; const AValue, AName: string);
begin
  AddSeg(ASegs, skConst, AValue, False);
  ASegs[High(ASegs)].Expr := AName;
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
  // Ein leerer Wert ('') traegt nichts zum Lesen bei - er bleibt als
  // stehender Ausdruck.
  if (C.Kind = sckLiteral) and (C.Value <> '') then
  begin
    AddConstSeg(ASegs, C.Value, Txt);
    Inc(ACount.ConstsRead);
  end
  else if C.Kind <> sckNone then
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

// Traegt das Segment SQL-Text zum Lesen (Literal, Wert einer Konstante,
// die Kette)?
function IsSqlSeg(const ASeg: TSqlSeg): Boolean;
begin
  Result := ASeg.Kind in [skText, skConst, skChain];
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
      if IsSqlSeg(ASegs[i]) then
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

// SQL-Text in die Ausgabe - nicht, waehrend der Leser den Wert einer
// Konstante oder die Kette liest (Mute).
procedure EmitText(var S: TSqlScan; const AText: string);
var
  n : Integer;
begin
  if (AText = '') or S.Mute then Exit;
  n := Length(S.Pieces);
  if (n > 0) and not S.Pieces[n - 1].IsExpr then
    S.Pieces[n - 1].Text := S.Pieces[n - 1].Text + AText
  else
  begin
    SetLength(S.Pieces, n + 1);
    S.Pieces[n].IsExpr := False;
    S.Pieces[n].Text   := AText;
    S.Pieces[n].Tail   := #0;
  end;
end;

// Ein Pascal-Ausdruck in die Ausgabe; ATail sein letztes SQL-Zeichen zur
// Laufzeit (#0 unbekannt).
procedure EmitExpr(var S: TSqlScan; const AExpr: string; ATail: Char);
var
  n : Integer;
begin
  n := Length(S.Pieces);
  SetLength(S.Pieces, n + 1);
  S.Pieces[n].IsExpr := True;
  S.Pieces[n].Text   := AExpr;
  S.Pieces[n].Tail   := ATail;
end;

// Letztes SQL-Zeichen der Ausgabe zur Laufzeit: das des letzten Texts bzw.
// der Tail eines Ausdrucks; #0 unbekannt oder am Anfang.
function OutLast(const S: TSqlScan): Char;
var
  n : Integer;
begin
  Result := #0;
  n := Length(S.Pieces);
  if n = 0 then Exit;
  if S.Pieces[n - 1].IsExpr then
    Result := S.Pieces[n - 1].Tail
  else
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

// Eine neue Anweisung hinter ';' - die Sperre (Lock) bleibt (Major 2).
procedure NewStatement(var S: TSqlScan);
begin
  S.Head := '';
  S.Clause := '';
  S.Openers := nil;
  S.Tok[2] := '';
  S.Tok[1] := '';
  S.Tok[0] := ';';
end;

// Setzt die Sperre fuer den Rest des Texts, wenn das erste Wort AHead
// einer Anweisung DDL/DCL oder einen prozeduralen Block beginnt (Kopf der
// Unit, Punkt 1).
procedure LockByHead(var S: TSqlScan; const AHead: string);
begin
  if (S.Lock = '') and (InList(AHead, DDL_HEADS) or InList(AHead, BLOCK_HEADS)) then
    S.Lock := UpperCase(AHead);
end;

// Dasselbe fuer das zweite Wort von Firebirds 'EXECUTE BLOCK'.
procedure LockByExecuteBlock(var S: TSqlScan; const AWord: string);
begin
  if (S.Lock = '') and (S.Head = HEAD_EXECUTE) and (S.Tok[0] = HEAD_EXECUTE)
     and (AWord = WORD_BLOCK) then
    S.Lock := UpperCase(HEAD_EXECUTE + ' ' + WORD_BLOCK);
end;

{ ---- Urteile ---- }

// Die Sperre fuer den Rest des Texts als Grund; '' ohne.
function LockReason(const S: TSqlScan): string;
begin
  Result := '';
  if S.Lock = '' then Exit;
  if InList(LowerCase(S.Lock), DDL_HEADS) then
    Result := Format(R_DDL, [S.Lock])
  else
    Result := Format(R_BLOCK, [S.Lock]);
end;

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

// Duerfen die (bis zu zwei) Zeichen AFollow hinter einem Wert stehen - ein
// Folger wie oben oder der PostgreSQL-Cast '::' (Minor 10)?
function FollowsValue(const AFollow: string): Boolean;
begin
  Result := IsValueFollower(CharAt(AFollow, 1)) or (Copy(AFollow, 1, 2) = '::');
end;

// Klebt ein Operand hinter C an einem Bezeichner ('col_', 'tbl.', '@', ':')?
function GluesAfter(C: Char): Boolean;
begin
  Result := IsIdentChar(C) or CharInSet(C, ['.', '@', ':', '$', '#']);
end;

// IntToStr(x) bzw. QuotedStr(x)/AnsiQuotedStr(x, ''''): genau EIN Wert
// (eine Zahl bzw. ein SQL-String) - keine Liste, keine Spalte (Minor 1 und
// 10).
function IsOneValue(const AOperand: string): Boolean;
var
  Inner : string;
begin
  Result := CallArg(AOperand, 'IntToStr', Inner)
    or QuoteCallInner(AOperand, Inner);
end;

// Ein Lauf im Code, dessen Wert schon maskiert ist (R2-06): ein einzelnes
// QuotedStr(x)/AnsiQuotedStr(x, '''') bindet x (UnwrapValue), sofern x
// nicht selbst maskiert ('QuotedStr(StringReplace(X, ..))'); sonst sperrt
// jedes Glied mit einer Maskierung (EscapeMarkOf). '' oder der Grund.
function EscapedRunReason(const S: TSqlScan; AFirst, ALast: Integer): string;
var
  k           : Integer;
  Mark, Inner : string;
begin
  Result := '';
  for k := AFirst to ALast do
  begin
    if (AFirst = ALast) and QuoteCallInner(S.Segs[k].Text, Inner) then
      Mark := EscapeMarkOf(Inner)
    else
      Mark := EscapeMarkOf(S.Segs[k].Text);
    if Mark <> '' then
      Exit(Format(R_ESCAPED, [Shown(S.Segs[k].Text), Mark]));
  end;
end;

// Ein Token, wie ihn ein Grund zeigt: ein Wort bzw. Zeichen in Quotes
// (''from''), ein stehender Ausdruck mit seinem Text, die Marken eines
// Werts und der Ausdruck einer frueheren Zeile der Kette in Worten - die
// Marken selbst sind fuer den Leser bedeutungslos.
function TokShown(const ATok: string): string;
begin
  if ATok = TOK_NUMBER then
    Result := SHOWN_NUMBER
  else if ATok = TOK_STRING then
    Result := SHOWN_STRING
  else if ATok = TOK_PLACEHOLDER then
    Result := SHOWN_PLACEHOLDER
  else if ATok = KEPT_MARK then
    Result := SHOWN_CHAIN_EXPR
  else if Copy(ATok, 1, 1) = KEPT_MARK then
    Result := '''' + Shown(Copy(ATok, 2, MaxInt)) + ''''
  else
    Result := '''' + ATok + '''';
end;

// Die Urteile ueber die Position eines Werts: Anfang, Wert-Kontext,
// Anweisungsart (die Sperre fuer DDL prueft LockReason davor). '' oder der
// Grund.
function ValueReason(const ATok: TSqlTok3; const AOpener, AHead,
  AOperand: string): string;
var
  Head : string;
begin
  Result := '';
  if ATok[0] = '' then
    Exit(Format(R_AT_START, [Shown(AOperand)]));
  if Copy(ATok[0], 1, 1) = KEPT_MARK then
    Exit(Format(R_AFTER_EXPR, [Shown(AOperand), TokShown(ATok[0])]));
  if not IsValueContext(ATok, AOpener) then
    Exit(Format(R_NOT_VALUE, [Shown(AOperand), TokShown(ATok[0])]));
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
  AddText(S.Used, LowerCase(P.Name));
  if IsIdentChar(OutLast(S)) then
    EmitText(S, ' ');
  EmitText(S, ':' + P.Name);
  PushTok(S, TOK_PLACEHOLDER);
  S.LastCh := 'v';
end;

{ ---- Was hinter einer Stelle steht ---- }

// Die ersten ACount SQL-Zeichen ab Segment ASeg: Text (auch der Wert einer
// Konstante), ein Leerraum-Ausdruck als ' ', ein anderer Ausdruck oder
// Operand als 'x' (klebt) und Schluss; kuerzer am Ende (CharAt -> #0).
function CharsFrom(const S: TSqlScan; ASeg, ACount: Integer): string;
var
  SB : TStringBuilder;
  k  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    k := ASeg;
    while (SB.Length < ACount) and (k <= High(S.Segs)) do
    begin
      if IsSqlSeg(S.Segs[k]) then
        SB.Append(Copy(S.Segs[k].Text, 1, ACount - SB.Length))
      else if S.Segs[k].Blank then
        SB.Append(' ')
      else
      begin
        SB.Append('x');
        Break;
      end;
      Inc(k);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Erstes Zeichen ab Segment ASeg, das kein Leerraum ist (')' bei der
// ganzen Liste); 'x' fuer einen Ausdruck, #0 am Ende.
function NextNonBlank(const S: TSqlScan; ASeg: Integer): Char;
var
  k : Integer;
  T : string;
begin
  for k := ASeg to High(S.Segs) do
    if IsSqlSeg(S.Segs[k]) then
    begin
      T := TrimLeft(S.Segs[k].Text);
      if T <> '' then
        Exit(T[1]);
    end
    else if not S.Segs[k].Blank then
      Exit('x');
  Result := #0;
end;

// Die zwei Zeichen hinter T[i] - ueber das Ende von T in die folgenden
// Segmente (ab ASeg + 1).
function FollowAt(const S: TSqlScan; const T: string; i, ASeg: Integer): string;
begin
  Result := Copy(T, i + 1, 2);
  if Length(Result) < 2 then
    Result := Result + CharsFrom(S, ASeg + 1, 2 - Length(Result));
end;

// Das erste Zeichen hinter T[i], das kein Leerraum ist (NextNonBlank).
function SolidAt(const S: TSqlScan; const T: string; i, ASeg: Integer): Char;
var
  Rest : string;
begin
  Rest := TrimLeft(Copy(T, i + 1, MaxInt));
  if Rest <> '' then
    Result := Rest[1]
  else
    Result := NextNonBlank(S, ASeg + 1);
end;

{ ---- SQL-Strings ---- }

// Steht direkt vor dem Quote ein N (N'..', nationaler String; Minor 10),
// das als eigenes Wort im letzten Text-Stueck der Ausgabe liegt? Dann
// zaehlt das Wort davor als Position, und das N faellt mit dem String weg,
// wenn er Parameter wird.
function NationalPrefix(const S: TSqlScan): Boolean;
var
  L : string;
begin
  Result := False;
  if (S.Tok[0] <> NATIONAL_PREFIX) or not CharInSet(S.LastCh, ['n', 'N'])
     or S.Mute or (S.StrLen <= 0) then
    Exit;
  L := S.Pieces[S.StrCount - 1].Text;
  Result := CharInSet(L[S.StrLen], ['n', 'N']);
end;

procedure OpenString(var S: TSqlScan);
begin
  S.StrCount := Length(S.Pieces);
  S.StrLen := -1;
  if (S.StrCount > 0) and not S.Pieces[S.StrCount - 1].IsExpr then
    S.StrLen := Length(S.Pieces[S.StrCount - 1].Text);
  S.StrTok := S.Tok;
  if NationalPrefix(S) then
  begin
    Dec(S.StrLen);
    S.StrTok[0] := S.Tok[1];
    S.StrTok[1] := S.Tok[2];
    S.StrTok[2] := '';
  end;
  S.StrOpener := TopOpener(S);
  S.StrHead   := S.Head;
  S.StrMuted  := S.Mute;
  S.StrParts  := nil;
  S.StrBuf    := '';
  S.StrFirst  := '';
  S.Mode := lmString;
  EmitText(S, '''');
end;

// Der Text seit dem letzten Stueck als Literal in den Wert des Strings -
// ueber 255 Elemente geteilt wie in SqlExprOf (R2-02).
procedure FlushStrBuf(var S: TSqlScan);
begin
  if S.StrBuf <> '' then
    AddText(S.StrParts, SplitLongLiteral(
      TRdxRecipes.EncodeLiteral(S.StrBuf)));
  S.StrBuf := '';
end;

// Ist der Wert des Strings genau IntToStr(x) - EIN Wert, auch allein in
// einer Liste?
function SoleIntToStr(const AParts: TArray<string>): Boolean;
var
  Inner : string;
begin
  Result := (Length(AParts) = 1) and CallArg(AParts[0], 'IntToStr', Inner);
end;

// Darf der String mit Operand Parameter werden? AFollow: die zwei Zeichen
// hinter dem schliessenden Quote, ASolid das erste, das kein Leerraum ist.
// '' oder der Grund.
function StringReason(const S: TSqlScan; const AFollow: string;
  ASolid: Char): string;
begin
  Result := LockReason(S);
  if Result = '' then
    Result := ValueReason(S.StrTok, S.StrOpener, S.StrHead, S.StrFirst);
  if Result <> '' then Exit;
  if S.Mute or S.StrMuted then
    Exit(Format(R_CUT, [Shown(S.StrFirst)]));
  if not FollowsValue(AFollow) then
    Exit(Format(R_GLUED, [Shown(S.StrFirst)]));
  if InList(S.StrTok[0], NUMBER_AFTER) then
    Exit(Format(R_LIMIT_TEXT, [Shown(S.StrFirst), UpperCase(S.StrTok[0])]));
  // ''' + X + ''' allein in IN (..)/VALUES (..): X kann '1'',''2' sein
  // wie der nackte Operand (Minor 1).
  if (S.StrTok[0] = '(') and (ASolid = ')') and not SoleIntToStr(S.StrParts) then
    Result := Format(R_WHOLE_LIST, [Shown(S.StrFirst), UpperCase(S.StrOpener)]);
end;

// Der String schliesst (AFollow, ASolid: was dahinter steht, StringReason).
// Ohne Operand ein gewoehnliches Literal; mit Operand wird er EIN
// Parameter, wenn er an einer Wert-Position steht.
procedure CloseString(var S: TSqlScan; const AFollow: string; ASolid: Char);
begin
  S.Mode := lmCode;
  S.LastCh := '''';
  if S.StrFirst = '' then
  begin
    EmitText(S, '''');
    PushTok(S, TOK_STRING);
    Exit;
  end;
  FlushStrBuf(S);
  S.Reason := StringReason(S, AFollow, ASolid);
  if S.Reason <> '' then Exit;
  CutOutput(S);
  AddParam(S, S.StrFirst, JoinWith(S.StrParts, ' + '));
end;

// Ein Zeichen im String. Liest der Leser stumm (Wert einer Konstante, die
// Kette), steht das Zeichen schon in deren Namen - nicht im Wert.
function StepString(var S: TSqlScan; const T: string; i, ASeg: Integer): Integer;
begin
  Result := i + 1;
  if T[i] <> '''' then
  begin
    EmitText(S, T[i]);
    if not S.Mute then
      S.StrBuf := S.StrBuf + T[i];
  end
  else if CharAt(T, i + 1) = '''' then
  begin
    EmitText(S, '''''');
    if not S.Mute then
      S.StrBuf := S.StrBuf + '''';
    Result := i + 2;
  end
  else
    CloseString(S, FollowAt(S, T, i, ASeg), SolidAt(S, T, i, ASeg));
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
    PushTok(S, TOK_NUMBER);   // eine Zahl ist ein Wert
    Exit;
  end;
  while IsIdentChar(CharAt(T, Result)) or (CharAt(T, Result) = '$') do
    Inc(Result);
  W := Copy(T, i, Result - i);
  EmitText(S, W);
  W := LowerCase(W);
  if S.Head = '' then
  begin
    S.Head := W;
    LockByHead(S, W);
  end
  else
    LockByExecuteBlock(S, W);
  if InList(W, CLAUSE_WORDS) then
    S.Clause := W;
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
    AddText(S.Found, Nm);
  EmitText(S, Copy(T, i, Result - i));
  PushTok(S, TOK_PLACEHOLDER);
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
    AddText(S.Openers, S.Tok[0]);
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
  begin
    // Ein positionaler Platzhalter (Verdacht c) - BuildSqlTemplate lehnt
    // ab, wenn benannte dazukaemen.
    if Op = '?' then
      Inc(S.QMarks);
    PushTok(S, Op);
  end;
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
  // Der Ausdruck einer frueheren Zeile der Kette (AppendTerm): ein Token
  // wie ein stehender Ausdruck - ein Operand direkt dahinter lehnt
  // ValueReason ab (R_AFTER_EXPR), statt hinter dem Wort davor zu landen.
  if C = KEPT_MARK then
    PushTok(S, KEPT_MARK)
  else if C <= ' ' then
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
  AddText(S.Found, LowerCase(Copy(T, i + 1, j - i - 1)));
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

// Das letzte Segment des Laufs ab ASeg: Operanden ohne SQL-Text dazwischen
// sind EIN Wert ('IntToStr(A) + B'). Ein stehender Ausdruck beendet den
// Lauf - ein Leerraum-Ausdruck trennt, eine Konstante ohne lesbaren Wert
// lehnt BareReason ab (KeptBehind): im Lauf wanderte sie aus dem SQL-Text
// in die Daten des Parameters (Kopf der Unit, Punkt 2).
function RunEnd(const S: TSqlScan; ASeg: Integer): Integer;
begin
  Result := ASeg;
  while (Result < High(S.Segs)) and (S.Segs[Result + 1].Kind = skOperand) do
    Inc(Result);
end;

// Steht direkt hinter dem Lauf (bis ALast) ein stehender Ausdruck, der kein
// Leerraum ist - eine Konstante ohne lesbaren Wert? Ob der Wert dort endet,
// ist nicht sichtbar: ' AND active = ' + '1' gehoert in den SQL-Text.
function KeptBehind(const S: TSqlScan; ALast: Integer): Boolean;
begin
  Result := (ALast < High(S.Segs)) and not IsSqlSeg(S.Segs[ALast + 1])
    and not S.Segs[ALast + 1].Blank;
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
    AddText(Items, S.Segs[k].Text);
  Result := JoinWith(Items, ' + ');
end;

// Darf der Lauf AFirst..ALast im Code Parameter werden? '' oder der Grund
// (Kopf der Unit, Punkt 1).
function BareReason(const S: TSqlScan; AFirst, ALast: Integer): string;
var
  Op, Inner : string;
  Single    : Boolean;
begin
  Op := S.Segs[AFirst].Text;
  Single := (AFirst = ALast) and IsOneValue(Op);
  Result := LockReason(S);
  if Result <> '' then Exit;
  if GluesAfter(S.LastCh) then
    Exit(Format(R_GLUED, [Shown(Op)]));
  Result := ValueReason(S.Tok, TopOpener(S), S.Head, Op);
  if Result <> '' then Exit;
  if KeptBehind(S, ALast) then
    Exit(Format(R_BEFORE_EXPR, [Shown(Op), Shown(S.Segs[ALast + 1].Text)]));
  if not FollowsValue(CharsFrom(S, ALast + 1, 2)) then
    Exit(Format(R_GLUED, [Shown(Op)]));
  if InList(S.Tok[0], NUMBER_AFTER)
     and not ((AFirst = ALast) and CallArg(Op, 'IntToStr', Inner)) then
    Exit(Format(R_LIMIT_TEXT, [Shown(Op), UpperCase(S.Tok[0])]));
  if (S.Clause = CLAUSE_ON) and not Single then
    Exit(Format(R_JOIN_ON, [Shown(Op)]));
  if (S.Tok[0] = '(') and (NextNonBlank(S, ALast + 1) = ')') and not Single then
    Exit(Format(R_WHOLE_LIST, [Shown(Op), UpperCase(TopOpener(S))]));
  Result := EscapedRunReason(S, AFirst, ALast);
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
// Stueck seines Werts. Verdoppelt der Operand die Apostrophe ('''' ->
// '''''', die Maskierung fuer SQL-Text), ist sein Wert im Parameter das
// Argument selbst - auch der Name kommt dann daher ('X.Replace(..)' ->
// :X); jede andere Maskierung (QuotedStr, EscapeString, X.QuotedString,
// ein Literal mit Apostroph) sperrt (Review FB, R2-06; InStringEscape).
procedure TakeInString(var S: TSqlScan; const ASeg: TSqlSeg);
var
  Value, Mark : string;
begin
  FlushStrBuf(S);
  Value := ASeg.Text;
  if ASeg.Kind = skOperand then
  begin
    Mark := InStringEscape(ASeg.Text, Value);
    if Mark <> '' then
      S.Reason := Format(R_ESCAPED, [Shown(ASeg.Text), Mark]);
    if S.StrFirst = '' then
      S.StrFirst := Value;
  end;
  AddText(S.StrParts, Value);
  EmitExpr(S, ASeg.Text, #0);
end;

// Ein stehender Ausdruck. sLineBreak/LineEnding (Blank) beenden einen
// Zeilenkommentar ('-- alle' + sLineBreak + 'WHERE ..'; Minor 10).
procedure TakeKept(var S: TSqlScan; const ASeg: TSqlSeg);
begin
  if S.Mode = lmString then
  begin
    TakeInString(S, ASeg);
    Exit;
  end;
  if ASeg.Blank then
    EmitExpr(S, ASeg.Text, #10)
  else
    EmitExpr(S, ASeg.Text, #0);
  if (S.Mode = lmLineComment) and ASeg.Blank then
    S.Mode := lmCode;
  if (S.Mode = lmCode) and not ASeg.Blank then
    PushTok(S, KEPT_MARK + ASeg.Text);
  if S.Mode = lmCode then
    S.LastCh := ' ';
end;

// Liest das Segment ASeg ohne Ausgabe (der Wert einer Konstante, die
// Kette).
procedure ReadMuted(var S: TSqlScan; ASeg: Integer);
begin
  S.Mute := True;
  ScanText(S, ASeg);
  S.Mute := False;
end;

// Eine Konstante mit einfachem Wert: ihr NAME in die Ausgabe (im String
// ein Stueck seines Werts), ihr Wert wird stumm gelesen (Kopf der Unit,
// Punkt 2).
procedure TakeConst(var S: TSqlScan; ASeg: Integer);
var
  Seg : TSqlSeg;
begin
  Seg := S.Segs[ASeg];
  if S.Mode = lmString then
  begin
    FlushStrBuf(S);
    AddText(S.StrParts, Seg.Expr);
  end;
  EmitExpr(S, Seg.Expr, Seg.Text[Length(Seg.Text)]);
  ReadMuted(S, ASeg);
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
    case S.Segs[k].Kind of
      skText  : ScanText(S, k);
      skKept  : TakeKept(S, S.Segs[k]);
      skConst : TakeConst(S, k);
      skChain : ReadMuted(S, k);
    else
      k := TakeOperandSeg(S, k);
    end;
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
// geschrieben, mit ' + ' verbunden. Ein Text-Stueck traegt die Literale
// mehrerer Kettenglieder - ueber 255 Elemente teilt es SplitLongLiteral
// (E2056 bis Delphi 11; Review FB R2-02).
function SqlExprOf(const APieces: TArray<TSqlPiece>): string;
var
  i     : Integer;
  Items : TArray<string>;
begin
  Items := nil;
  for i := 0 to High(APieces) do
    if APieces[i].IsExpr then
      AddText(Items, APieces[i].Text)
    else if APieces[i].Text <> '' then
      AddText(Items, SplitLongLiteral(
        TRdxRecipes.EncodeLiteral(APieces[i].Text)));
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
    AddText(Items, AParams[i].Value);
  Result := JoinWith(Items, ', ');
end;

function StatementOf(const AReq: TRdxSqlRequest; const ASql: string): string;
begin
  if AReq.IsCall then
    Result := Trim(AReq.Target) + '(' + ASql + ');'
  else
    Result := Trim(AReq.Target) + ' := ' + ASql + ';';
end;

// Wovor 'ParamByName' beim Query-Objekt steht: 'Q.' bzw. bei ADO
// 'Q.Parameters.' (Minor 11).
function QueryPrefixOf(const AReq: TRdxSqlRequest): string;
begin
  Result := TRdxRecipes.QueryObjectOf(Trim(AReq.Target)) + '.';
  if AReq.Binding = sbAdoParameters then
    Result := Result + ADO_PARAMETERS;
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
      AReq.Indent, QueryPrefixOf(AReq))
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

// Die Kette APrefix als erstes Segment vor ASegs.
function ChainSegs(const APrefix: string; const ASegs: TSqlSegs): TSqlSegs;
var
  i : Integer;
begin
  SetLength(Result, Length(ASegs) + 1);
  Result[0] := Default(TSqlSeg);
  Result[0].Kind := skChain;
  Result[0].Text := APrefix;
  for i := 0 to High(ASegs) do
    Result[i + 1] := ASegs[i];
end;

function BuildSqlTemplate(const AReq: TRdxSqlRequest;
  out AResult: TRdxSqlTemplate): Boolean;
var
  S        : TSqlScan;
  Count    : TSqlSegCount;
  Existing : TArray<string>;
  Name     : string;
begin
  Result := False;
  AResult := Default(TRdxSqlTemplate);
  S := Default(TSqlScan);
  AResult.Reason := SegsOf(AReq, S.Segs, Count);
  if AResult.Reason <> '' then Exit;
  // Die frueheren Zeilen der Kette liest der Leser zuerst - stumm.
  if AReq.Prefix <> '' then
    S.Segs := ChainSegs(AReq.Prefix, S.Segs);
  Existing := SqlPlaceholders(PlainSqlOf(S.Segs));
  S.Used := Copy(Existing, 0, Length(Existing));
  for Name in AReq.ChainNames do
    AddText(S.Used, LowerCase(Name));
  ScanSegs(S);
  AResult.Reason := S.Reason;
  if (AResult.Reason = '') and (S.QMarks > 0) then
    AResult.Reason := R_QMARK;
  if AResult.Reason = '' then
    AResult.Reason := ComposeTemplate(AReq, S, Existing, AResult.Text);
  if AResult.Reason <> '' then Exit;
  AResult.Params     := Length(S.Params);
  AResult.ConstsRead := Count.ConstsRead;
  Result := True;
end;

function SqlHintOf(const AResult: TRdxSqlTemplate): string;
begin
  Result := Format('%d Parameter', [AResult.Params]);
  if AResult.ConstsRead > 0 then
    Result := Result + Format(', %d Konstante(n) mitgelesen',
      [AResult.ConstsRead]);
  Result := Result + ', nichts wird geschrieben';
end;

{ ---- Die Kette als SQL-Text (Kopf der Unit, Punkt 3) ----
  Kodierer und Leser der Marke KEPT_MARK bleiben in EINER Unit: AppendTerm
  schreibt sie fuer einen Ausdruck einer frueheren Zeile, StepCode liest
  sie als Token. Die Kette selbst (welche Zeilen dazugehoeren) sucht
  uRdxSqlFacts am Quelltext. }

// Hinter das String- bzw. Zeichen-Literal ab ARaw[i] ('..', '#13', '#$0A',
// auch aneinander: 'a'#13#10'b').
function LiteralRunEnd(const ARaw: string; i: Integer): Integer;
begin
  Result := i;
  while Result <= Length(ARaw) do
    if ARaw[Result] = '''' then
      SkipLiteral(ARaw, Result)
    else if ARaw[Result] = '#' then
    begin
      Inc(Result);
      if CharAt(ARaw, Result) = '$' then
        Inc(Result);
      while CharInSet(CharAt(ARaw, Result), ['0'..'9', 'A'..'F', 'a'..'f']) do
        Inc(Result);
    end
    else
      Break;
end;

// Hinter den Term ab ARaw[i]: bis zum '+' auf Klammertiefe 0 (Strings
// zaehlen nicht) bzw. zum Ende.
function TermEnd(const ARaw: string; i: Integer): Integer;
var
  Depth : Integer;
begin
  Result := i;
  Depth := 0;
  while Result <= Length(ARaw) do
    if ARaw[Result] = '''' then
      SkipLiteral(ARaw, Result)
    else
    begin
      if CharInSet(ARaw[Result], ['(', '[']) then
        Inc(Depth)
      else if CharInSet(ARaw[Result], [')', ']']) then
        Dec(Depth)
      else if (ARaw[Result] = '+') and (Depth <= 0) then
        Exit;
      Inc(Result);
    end;
end;

// Hinter einen Kommentar ab ARaw[i] ('{..}', '(*..*)', '//' bis zum
// Zeilenende); i selbst, wenn dort keiner beginnt.
function CommentEnd(const ARaw: string; i: Integer): Integer;
var
  P : Integer;
begin
  Result := i;
  if ARaw[i] = '{' then
    P := PosEx('}', ARaw, i) + 1
  else if Copy(ARaw, i, 2) = '(*' then
    P := PosEx('*)', ARaw, i) + 2
  else if Copy(ARaw, i, 2) = '//' then
    P := PosEx(#10, ARaw, i) + 1
  else
    Exit;
  if P <= i + 1 then
    P := Length(ARaw) + 1;
  Result := P;
end;

// Der SQL-Text eines Terms ab ARaw[i] in ASB; liefert die Stelle dahinter.
function AppendTerm(ASB: TStringBuilder; const ARaw: string; i: Integer): Integer;
var
  Value : string;
begin
  if CharInSet(ARaw[i], ['''', '#']) then
  begin
    Result := LiteralRunEnd(ARaw, i);
    if TRdxRecipes.DecodeLiteral(Copy(ARaw, i, Result - i), Value) then
      ASB.Append(Value)
    else
      ASB.Append(KEPT_MARK);
    Exit;
  end;
  Result := TermEnd(ARaw, i);
  if InList(LowerCase(Trim(Copy(ARaw, i, Result - i))), LINE_BREAK_NAMES) then
    ASB.Append(#13#10)
  else
    ASB.Append(KEPT_MARK);
end;

// Der SQL-Text einer Pascal-Verkettung ARaw (Argument von Q.SQL.Add, Wert
// von Q.SQL.Text :=): Literale dekodiert, sLineBreak als Zeilenende,
// jeder andere Term als KEPT_MARK - ein Ausdruck, der stehen bleibt (der
// Leser kennt seinen Text nicht; StepCode liest ihn als Token, am Anfang
// setzt er keine Anweisungsart).
function SqlChainTextOf(const ARaw: string): string;
var
  SB   : TStringBuilder;
  i, j : Integer;
begin
  SB := TStringBuilder.Create;
  try
    i := 1;
    while i <= Length(ARaw) do
    begin
      j := CommentEnd(ARaw, i);
      if j > i then
        i := j
      else if (ARaw[i] <= ' ') or (ARaw[i] = '+') then
        Inc(i)
      else
        i := AppendTerm(SB, ARaw, i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
