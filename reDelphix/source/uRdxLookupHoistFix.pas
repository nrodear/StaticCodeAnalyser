unit uRdxLookupHoistFix;

// reDelphix - Editorhilfe fuer SCA111 ParamByNameInLoop und SCA112
// FieldByNameInLoop (Charge QF15), OHNE ToolsAPI und ohne Parser (laeuft
// auch im FPC-Pruefstand): der Lookup kommt einmal vor die Schleife, jedes
// gleiche Vorkommen in der Schleife wird zum neuen Namen.
//     var FldAmount := Q.FieldByName('Amount');
//     while not Q.Eof do
//     begin
//       Total := Total + FldAmount.AsCurrency;
// EIN Planer fuer beide Regeln: nur die Methode, das Praefix des Namens
// (Fld/Prm) und die Liste der Sperr-Member unterscheiden sich.
//
// DER FUND (uPerfHotspots gelesen): lexikalisch, je Treffer von
// '\b\w+\.FieldByName\s*\(' bzw. ParamByName in einem Schleifenrumpf ein
// Fund auf der Zeile des Empfaengers (Kommentare entfernt, Strings
// geblankt). Rumpf: hinter dem 'begin' eines for/while-Kopfs bis zum
// passenden 'end', ohne begin bis zum naechsten ';', bei repeat bis vor das
// 'until'. Die Meldung ist fest - kein Empfaenger, kein Feldname, keine
// Spalte (Recherche-Tabelle 2026-10-11): der Planer sucht den Aufruf auf
// der Zeile selbst.
//
// ZIEL AUS DEM FUND (der Planer prueft nach, statt dem Detektor zu
// glauben): auf der Fundzeile die Aufrufe '<Name>.FieldByName(' - genau
// einer (gleiche Aufrufe zaehlen einmal), sonst Zeile verschoben bzw.
// mehrdeutig. Der Empfaenger ist ein blosser Name (nicht Self, kein
// 'X.Q', nicht als Property oder Routine der Datei deklariert), das
// Argument genau ein String-Literal auf derselben Zeile. Die Schleife ist
// die INNERSTE for/while/repeat-Schleife der innersten Routine, in deren
// Rumpf der Aufruf steht; gelesen von ihrem Schluesselwort bis zum Ende der
// Anweisung (begin..end, try/case/asm ueber die end-Bilanz, if/else,
// for/while/with, repeat..until, einfache Anweisung bis ';').
//
// UMFORMUNG: 'var <Name> := <Q>.FieldByName(<Literal>);' als eigene Zeile
// vor die Zeile der Schleife (deren Einrueckung), und jedes Vorkommen
// '<Q>.FieldByName(<gleiches Literal>)' in der Schleife - Kopf, Rumpf,
// until-Bedingung - wird zu <Name>. Ein anderes Literal (auch nur anders
// geschrieben: 'amount' statt 'Amount') bleibt stehen. Der Name: Praefix
// und der Feldname in Bezeichner-Teilen ('customer_id' -> FldCustomerId,
// nur ASCII-Buchstaben und Ziffern); kommt er in der Datei schon als
// ganzes Wort vor (auch in Kommentar oder String - strenger als noetig),
// Name2 bis Name9, sonst keine Hilfe. Die innerste Schleife: in einer
// geschachtelten steht die neue Zeile danach noch in der aeusseren, und
// der Detektor meldet sie dort erneut - ein zweiter Klick zieht sie weiter
// hinaus (Name2), wenn die aeussere Schleife es erlaubt.
//
// AENDERT DAS VERHALTEN (Kennzeichnung E2): der Lookup laeuft jetzt auch,
// wenn die Schleife nie laeuft (fehlt das Feld bzw. der Parameter, kommt
// die Ausnahme jetzt), und die Referenz wird nur einmal geholt. Schliesst
// oder oeffnet die Datenmenge sich in der Schleife neu (Felder frei) bzw.
// werden SQL oder Params neu gesetzt (Parameter neu), zeigt die Referenz
// ins Leere. Was im Text steht, sperrt die Hilfe; einen indirekten Aufruf
// (eine Methode, die Q schliesst) beweist sie nicht.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - kein bzw. mehrere verschiedene Aufrufe auf der Zeile, Empfaenger oder
//     Argument nicht in der einfachen Form, Kommentar im Aufruf,
//   - keine Routine mit begin..end-Rumpf um den Aufruf (Hauptblock,
//     initialization), unsichere Grenzen, eine Direktive in der Routine
//     (bedingter Code kann Q schliessen), 'with' (ein Name bindet dort
//     vielleicht an ein Member), 'asm' oder 'goto' in der Routine,
//   - keine Schleife um den Aufruf (Fund veraltet), eine Schleife davor,
//     die die Hilfe nicht sicher liest,
//   - die Schleife beginnt keine eigene Zeile und Anweisung in einem
//     begin..end-Block (nach 'then', 'do', 'else', in einem try-, except-,
//     finally- oder case-Teil): dort ist kein sicherer Platz fuer die
//     Deklaration,
//   - in der Schleife: eine anonyme Methode (sie liefe spaeter, mit einem
//     anderen Q), der Empfaenger anders als 'Q.Member' (zugewiesen,
//     weitergereicht, als Schleifenvariable, ueber 'X.Q' erreicht) oder
//     mit einem Sperr-Member (FIELD_RESETS bzw. PARAM_RESETS: Open, Close,
//     Active, SQL, Fields ... bzw. SQL, Params, Prepare ...),
//   - kein freier Name,
//   - eine Inline-Variable gibt es erst ab Delphi 10.3 und in FPC 3.2 gar
//     nicht: Skript-Units (uRdxCompilerTraces.ScriptReason), eine FPC-
//     Weiche in der Datei (uRdxIntroPlan.LineLooksFpcAware) und Spuren
//     aelterer Compiler (OldCompilerTrace mit FLOOR_INLINE_DECL, wie SCA014).
//     Was nur die Platte weiss (Projektdateien, Includes) und ob der
//     Empfaenger eine Variable ist (Quellstellen-Dienst), prueft der
//     Adapter in uRdxFixTable (UnknownReceiverReason).
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): die Adapter
// PlanParamByNameLoop/PlanFieldByNameLoop traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Methoden der beiden Regeln, wie sie die Gruende nennen ...
  METHOD_FIELD = 'FieldByName';
  METHOD_PARAM = 'ParamByName';
  // ... und das Praefix des neuen Namens (FldAmount, PrmId).
  PREFIX_FIELD = 'Fld';
  PREFIX_PARAM = 'Prm';

  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_LH_MOVED = 'no %s call with a receiver on the reported line';
  R_LH_MANY = 'the line has %d different %s calls - which one the finding '
    + 'means is unclear';
  R_LH_RECEIVER = 'the receiver of %s is not a plain variable name (Self, a '
    + 'qualified name or an expression)';
  R_LH_ARG = 'the argument of %s is not a single string literal on the same '
    + 'line';
  R_LH_DECLARED = '%s is declared as a property or routine in this file - it '
    + 'could return another object on each call';
  R_LH_UNKNOWN = '%s is not known here as a variable, parameter or field - it '
    + 'could be a function that returns another object on each call';
  R_LH_NO_ROUTINE = 'no routine with a begin..end body around the call';
  R_LH_BOUNDS = 'the bounds of the routine around the call are not safe to '
    + 'read';
  R_LH_ROUTINE_WORD = 'the routine contains "%s" - the helper does not move '
    + 'code there';
  R_LH_DIRECTIVE = 'compiler directive in the routine - conditional code '
    + 'could reopen %s';
  R_LH_NO_LOOP = 'no for, while or repeat loop around the call';
  R_LH_LOOP_UNREADABLE = 'the loop in line %d is not safe to read';
  R_LH_PLACE = 'the loop in line %d does not start its own line and '
    + 'statement in a begin..end block - no place for the declaration';
  R_LH_ANON = 'the loop contains an anonymous method - it could run later, '
    + 'when %s has changed';
  R_LH_RESET_FIELD = '%s in line %d can close %s or rebuild its fields - the '
    + 'reference fetched before the loop would point into the void';
  R_LH_RESET_PARAM = '%s in line %d can rebuild the parameters of %s - the '
    + 'reference fetched before the loop would point into the void';
  R_LH_BARE = '%s appears in line %d other than as "%s.Member" - assigned, '
    + 'passed on, declared or reached through another object';
  R_LH_COMMENT = 'comment inside %s in line %d';
  R_LH_NAME = 'no free name for the variable - %s and %s2 to %s9 already '
    + 'occur in the file';
  R_LH_SCRIPT = 'the file does not start with unit/program/library or has no '
    + 'implementation part (include or script?) - only the Delphi compiler '
    + 'knows inline variables';
  R_LH_FPC = 'the file has an FPC switch (line %d) - FPC 3.2 has no inline '
    + 'variables';
  R_LH_OLD = 'inline variables exist from Delphi 10.3 on - the file has '
    + 'traces of older compilers (%s, line %d)';

type
  // Ergebnis des Planers (uRdxFixTable: Plan-Form im Geruest TRdxFixFrame).
  //   Lookup    der Aufruf wie eingefuegt ('Q.FieldByName(''Amount'')') -
  //             Name im Menuetext; gesetzt, sobald der Aufruf gelesen ist
  //             (auch, wenn der Planer danach ablehnt)
  //   Receiver  der Empfaenger wie im Quelltext ('Q') - fuer die
  //             Variablen-Pruefung des Adapters
  //   Name      der neue Name (FldAmount) - fuer den Hinweis
  //   LoopLine  die Zeile der Schleife (vor dem Schreiben)
  //   Count     die ersetzten Vorkommen in der Schleife (mindestens 1)
  //   Edits     die Einfuegung vor der Schleife (ab Spalte 1 der
  //             Schleifenzeile bis hinter ihr Schluesselwort) und je
  //             Vorkommen eine Ersetzung - ein Undo-Schritt
  TRdxLookupPlan = record
    Lookup   : string;
    Receiver : string;
    Name     : string;
    LoopLine : Integer;
    Count    : Integer;
    Edits    : TArray<TRdxEdit>;
  end;

  TRdxLookupHoistFix = class
  public
    // SCA112: 'Q.FieldByName(''X'')' vor die Schleife - True, oder False
    // mit dem Grund. Form TRdxPlannerOf<TRdxLookupPlan>; die Meldung traegt
    // nichts (s. Kopf).
    class function FieldByNameLoop(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxLookupPlan;
      out AReason: string): Boolean; static;

    // SCA111: dasselbe fuer 'Q.ParamByName(''X'')'.
    class function ParamByNameLoop(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxLookupPlan;
      out AReason: string): Boolean; static;

    // Der Name zu einem Feld- bzw. Parameternamen: APrefix und die Teile
    // aus ASCII-Buchstaben und Ziffern, je mit grossem Anfang ('first name'
    // -> PrmFirstName), hoechstens 40 Zeichen davon.
    class function VarNameFor(const APrefix, AFieldName: string): string;
      static;

    // Der Grund des Adapters, wenn der Quellstellen-Dienst den Empfaenger
    // AName nicht als Variable, Parameter, Feld oder Inline-Variable kennt
    // (hier, damit die msgid in dieser Unit steht).
    class function UnknownReceiverReason(const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,        // TRefactorSpan.Make
  uRdxText,             // _(), MsgMovedSuffix, MsgStaleSuffix
  uRdxBlocks,           // TRdxBlocks.HeadBefore, TRdxRoutine, TRdxHeadStep
  uRdxTypeProof,        // TRdxTypeProof.DeclaresProperty
  uRdxIntroPlan,        // LineLooksFpcAware
  uRdxCompilerTraces;   // OldCompilerTrace, ScriptReason, FLOOR_INLINE_DECL

const
  SPAN_LOOKUP = 'lookup';
  // Hier endet die Suche nach der Routine um den Aufruf.
  UNIT_BOUNDS: array[0..6] of string = ('implementation', 'interface',
    'initialization', 'finalization', 'unit', 'program', 'library');
  // Die Schleifen.
  LOOP_WORDS: array[0..2] of string = ('for', 'while', 'repeat');
  // Davor beginnt die Schleife eine eigene Anweisung.
  LOOP_PREV: array[0..1] of string = (';', 'begin');
  // Anweisungen mit eigenem 'end' (die end-Bilanz BlockEnd liest sie).
  BLOCK_WORDS: array[0..3] of string = ('begin', 'try', 'case', 'asm');
  // Anweisungen mit Kopf bis 'do'.
  DO_WORDS: array[0..2] of string = ('for', 'while', 'with');
  // Davor endet eine Anweisung ohne ';'.
  STMT_STOPS: array[0..4] of string = ('end', 'else', 'until', 'finally',
    'except');
  // Steht eines davon auf oberster Ebene in einer einfachen Anweisung oder
  // einer until-Bedingung, liest die Hilfe sie nicht (bedingter Ausdruck
  // 'if .. then .. else', eine Struktur mitten in der Anweisung).
  STMT_BREAKERS: array[0..12] of string = ('begin', 'case', 'try', 'asm',
    'repeat', 'if', 'then', 'do', 'of', 'with', 'for', 'while', 'record');
  // Dasselbe in einem Kopf bis 'then' bzw. 'do', dazu die Enden.
  HEAD_BREAKERS: array[0..17] of string = ('begin', 'case', 'try', 'asm',
    'repeat', 'if', 'then', 'do', 'of', 'with', 'for', 'while', 'record',
    'end', 'until', 'else', 'finally', 'except');
  // Was die Hilfe in der Routine nicht liest.
  ROUTINE_BLOCKERS: array[0..2] of string = ('with', 'asm', 'goto');
  // Kein Empfaenger im Sinn der Hilfe.
  NOT_RECEIVERS: array[0..1] of string = ('self', 'inherited');
  // Member, die die Felder einer Datenmenge freigeben oder neu anlegen
  // koennen (schliessen, oeffnen, SQL/Daten/Verbindung wechseln, laden,
  // freigeben) - steht 'Q.<Member>' in der Schleife, keine Hilfe (SCA112).
  FIELD_RESETS: array[0..36] of string = ('open', 'close', 'active', 'sql',
    'fields', 'fielddefs', 'requery', 'refresh', 'free', 'destroy',
    'disposeof', 'execsql', 'execute', 'prepare', 'unprepare', 'prepared',
    'commandtext', 'tablename', 'storedprocname', 'nextrecordset',
    'opencursor', 'closecursor', 'connection', 'recordset', 'command',
    'disconnect', 'loadfromfile', 'loadfromstream', 'createdataset', 'data',
    'xmldata', 'filename', 'assign', 'copydataset', 'clonecursor', 'macros',
    'macrobyname');
  // Member, die die Parameter neu anlegen koennen (SQL, Params, Befehl,
  // Verbindung, Vorbereitung, freigeben) - SCA111. Open, Close und ExecSQL
  // lassen die Parameter stehen: genau dafuer setzt man sie in der Schleife.
  PARAM_RESETS: array[0..15] of string = ('sql', 'params', 'parameters',
    'free', 'destroy', 'disposeof', 'commandtext', 'storedprocname',
    'tablename', 'connection', 'command', 'prepare', 'unprepare', 'prepared',
    'macros', 'macrobyname');
  // So tief liest die Hilfe Anweisungen in Anweisungen ohne begin.
  MAX_NESTING = 32;
  // Name, Name2 .. Name9.
  MAX_NAME_TRIES = 9;
  // So viele Zeichen des Feldnamens nimmt der Name.
  MAX_NAME_BODY = 40;
  QUOTE = '''';

type
  // Was die beiden Regeln unterscheidet.
  TRdxLookupRule = record
    Method : string;    // 'FieldByName' (Gruende, Vergleich klein)
    Prefix : string;    // 'Fld'
    Field  : Boolean;   // FIELD_RESETS statt PARAM_RESETS
  end;

  // Ein Aufruf 'Q.FieldByName(''X'')' auf der Code-Sicht.
  TRdxLookupCall = record
    Recv   : TRdxToken;   // der Empfaenger
    Method : TRdxToken;   // FieldByName bzw. ParamByName
    Close  : TRdxToken;   // die ')'
    Lit    : string;      // das Literal wie im Quelltext, mit Quotes
    Text   : string;      // sein Inhalt ('''' als ein Quote)
  end;

  // Eine Schleife: Schluesselwort, das Token vor dem Rumpf (do bzw.
  // repeat), das letzte Token des Rumpfs (gleich BodyOpen, wenn er leer
  // ist) und das letzte Token der ganzen Anweisung.
  TRdxLoopSpan = record
    Kw       : TRdxToken;
    BodyOpen : TRdxToken;
    BodyLast : TRdxToken;
    Last     : TRdxToken;
  end;

function RuleFor(AField: Boolean): TRdxLookupRule;
begin
  Result.Field := AField;
  if AField then
  begin
    Result.Method := METHOD_FIELD;
    Result.Prefix := PREFIX_FIELD;
  end
  else
  begin
    Result.Method := METHOD_PARAM;
    Result.Prefix := PREFIX_PARAM;
  end;
end;

// Genau EIN Pascal-String-Literal 'abc' (verdoppelte Quotes darin): True
// mit dem Inhalt in AText, der nicht leer ist. Nicht: 'a' 'b', 'a'#9'b',
// '' und mehrzeilige Strings.
function LiteralText(const S: string; out AText: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  AText := '';
  if (Length(S) < 3) or (S[1] <> QUOTE) or (S[Length(S)] <> QUOTE) then
    Exit;
  i := 2;
  while i < Length(S) do
  begin
    if S[i] = QUOTE then
    begin
      if (i + 1 >= Length(S)) or (S[i + 1] <> QUOTE) then
        Exit;
      AText := AText + QUOTE;
      Inc(i, 2);
    end
    else
    begin
      AText := AText + S[i];
      Inc(i);
    end;
  end;
  Result := AText <> '';
end;

// Der Aufruf mit dem Methoden-Token AMethod: Empfaenger davor ('Q.'),
// genau ein Literal in den Klammern dahinter, alles auf einer Zeile. ''
// oder der Grund.
function ReadCall(AMap: TRdxCodeMap; const AMethod: TRdxToken;
  const ARule: TRdxLookupRule; out ACall: TRdxLookupCall): string;
var
  Dot, Open, P : TRdxToken;
  L, Seg       : string;
  c            : Integer;
begin
  Result := '';
  ACall := Default(TRdxLookupCall);
  ACall.Method := AMethod;
  Dot := Before(AMap, AMethod);
  ACall.Recv := Before(AMap, Dot);
  P := Before(AMap, ACall.Recv);
  if (Dot.Low <> '.') or not ACall.Recv.IsWord
     or InList(P.Low, IDENT_PREFIXES) or InList(ACall.Recv.Low, NOT_RECEIVERS)
     or (ACall.Recv.Line <> AMethod.Line) then
    Exit(_(R_LH_RECEIVER, [ARule.Method]));
  Open := After(AMap, AMethod);
  ACall.Close := After(AMap, Open);
  if (Open.Low <> '(') or (ACall.Close.Low <> ')')
     or (Open.Line <> AMethod.Line) or (ACall.Close.Line <> AMethod.Line) then
    Exit(_(R_LH_ARG, [ARule.Method]));
  // Zwischen den Klammern nur String und Leerraum - kein Kommentar, keine
  // Direktive (die Code-Sicht ueberspringt beide wie den String).
  L := AMap.Raw(AMethod.Line);
  for c := Open.EndCol to ACall.Close.Col - 1 do
    if not IsBlank(L[c]) and (AMap.ClassAt(AMethod.Line, c) <> 's') then
      Exit(_(R_LH_ARG, [ARule.Method]));
  Seg := Trim(Copy(L, Open.EndCol, ACall.Close.Col - Open.EndCol));
  if not LiteralText(Seg, ACall.Text) then
    Exit(_(R_LH_ARG, [ARule.Method]));
  ACall.Lit := Seg;
end;

// Der Aufruf auf der Fundzeile: je Methoden-Token mit 'Name.' davor ein
// Schluessel (Empfaenger und Literal bzw. der Grund, warum er nicht passt);
// genau ein Schluessel - '' mit dem Aufruf bzw. sein Grund -, keiner (Zeile
// verschoben) oder mehrere (mehrdeutig).
function CallOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ARule: TRdxLookupRule; out ACall: TRdxLookupCall): string;
var
  T, Dot, Recv     : TRdxToken;
  C                : TRdxLookupCall;
  Keys             : TArray<string>;
  Key, Why, First  : string;
  MethodLow        : string;
  Known            : Boolean;
  k, n             : Integer;
begin
  ACall := Default(TRdxLookupCall);
  Keys := nil;
  First := '';
  MethodLow := LowerCase(ARule.Method);
  if (ALine >= 1) and (ALine <= AMap.LineCount) then
  begin
    T := NextToken(AMap, ALine, 1);
    while (T.Low <> '') and (T.Line = ALine) do
    begin
      Dot := Before(AMap, T);
      Recv := Before(AMap, Dot);
      if (T.Low = MethodLow) and (Dot.Low = '.') and Recv.IsWord then
      begin
        Why := ReadCall(AMap, T, ARule, C);
        if Why = '' then
          Key := LowerCase(TokText(AMap, C.Recv)) + #1 + C.Lit
        else
          Key := Why;
        Known := False;
        for k := 0 to High(Keys) do
          Known := Known or (Keys[k] = Key);
        if not Known then
        begin
          AddText(Keys, Key);
          if Length(Keys) = 1 then
          begin
            First := Why;
            ACall := C;
          end;
        end;
      end;
      T := After(AMap, T);
    end;
  end;
  n := Length(Keys);
  if n = 0 then
    Result := MsgMovedSuffix(_(R_LH_MOVED, [ARule.Method]))
  else if n > 1 then
    Result := _(R_LH_MANY, [n, ARule.Method])
  else
    Result := First;
end;

// Der Empfaenger ist in der Datei als Property oder Routine deklariert?
// Dann liefert er vielleicht bei jedem Aufruf ein anderes Objekt. '' oder
// der Grund.
function DeclaredReason(AMap: TRdxCodeMap; const ARecv: string): string;
begin
  Result := '';
  if TRdxTypeProof.DeclaresProperty(AMap, ARecv)
     or DeclaresRoutine(AMap, ARecv) then
    Result := _(R_LH_DECLARED, [ARecv]);
end;

// Die innerste Routine mit begin..end-Rumpf um AAt (wie uRdxGotoExitFix):
// von AAt rueckwaerts der erste Kopf, dessen Rumpf AAt umfasst; ein Kopf
// mit unsicheren Grenzen beendet die Suche. '' oder der Grund.
function EnclosingRoutine(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): string;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  ARoutine := Default(TRdxRoutine);
  T := AAt;
  while TRdxBlocks.HeadBefore(AMap, T, UNIT_BOUNDS, S) do
  begin
    if S.Stop then
      Break;
    if S.Reason <> '' then
      Exit(_(R_LH_BOUNDS));
    if (S.Routine.Body.Low = 'begin')
       and TokBefore(S.Routine.Body, AAt)
       and TokBefore(AAt, S.Routine.EndTok) then
    begin
      ARoutine := S.Routine;
      Exit('');
    end;
  end;
  Result := _(R_LH_NO_ROUTINE);
end;

// Was im Rumpf der Routine steht, das die Hilfe nicht liest: eine
// Direktive, 'with', 'asm', 'goto'. '' oder der Grund.
function RoutineReason(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const ARecv: string): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  if DirectiveBetween(AMap, ARoutine.Body, ARoutine.EndTok.Line,
       ARoutine.EndTok.Col) then
    Exit(_(R_LH_DIRECTIVE, [ARecv]));
  P := ARoutine.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, ARoutine.EndTok) do
  begin
    if InList(T.Low, ROUTINE_BLOCKERS) and IsKeywordAfter(T, P) then
      Exit(_(R_LH_ROUTINE_WORD, [T.Low]));
    P := T;
    T := After(AMap, T);
  end;
end;

{ ---- Anweisungen lesen: das letzte Token einer Anweisung ---- }

// Endet vor T (nach APrev) eine Anweisung ohne eigenes ';'?
function IsStopAfter(const T, APrev: TRdxToken): Boolean;
begin
  Result := (T.Low = ';')
    or (InList(T.Low, STMT_STOPS) and IsKeywordAfter(T, APrev));
end;

// Eine einfache Anweisung (Zuweisung, Aufruf, raise, Inline-Deklaration)
// bzw. eine until-Bedingung ab AFirst bis vor ';' oder ein Ende auf
// oberster Klammerebene: True mit ihrem letzten Token. False bei einer
// anonymen Methode, einem Wort aus STMT_BREAKERS auf oberster Ebene,
// unpaarigen Klammern oder ohne Token.
function SimpleEnd(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  out ALast: TRdxToken): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  ALast := Default(TRdxToken);
  Depth := 0;
  P := Before(AMap, AFirst);
  T := AFirst;
  while T.Low <> '' do
  begin
    if (Depth = 0) and IsStopAfter(T, P) then
      Exit(ALast.Low <> '');
    if InList(T.Low, ROUTINE_WORDS) and IsKeywordAfter(T, P) then
      Exit;
    if (Depth = 0) and InList(T.Low, STMT_BREAKERS)
       and IsKeywordAfter(T, P) then
      Exit;
    Inc(Depth, ParenDelta(T));
    if Depth < 0 then
      Exit;
    ALast := T;
    P := T;
    T := After(AMap, T);
  end;
end;

// Das Schluesselwort AWord ('then', 'do') zum Kopf ab AKw auf oberster
// Klammerebene; False bei ';', einem Wort aus HEAD_BREAKERS davor, einer
// anonymen Methode oder ohne.
function HeadWord(AMap: TRdxCodeMap; const AKw: TRdxToken;
  const AWord: string; out ATok: TRdxToken): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  ATok := Default(TRdxToken);
  Depth := 0;
  P := AKw;
  T := After(AMap, AKw);
  while T.Low <> '' do
  begin
    if InList(T.Low, ROUTINE_WORDS) and IsKeywordAfter(T, P) then
      Exit;
    if Depth = 0 then
    begin
      if (T.Low = AWord) and IsKeywordAfter(T, P) then
      begin
        ATok := T;
        Exit(True);
      end;
      if (T.Low = ';')
         or (InList(T.Low, HEAD_BREAKERS) and IsKeywordAfter(T, P)) then
        Exit;
    end;
    Inc(Depth, ParenDelta(T));
    if Depth < 0 then
      Exit;
    P := T;
    T := After(AMap, T);
  end;
end;

// Das 'until' zum 'repeat' ARepeat (verschachtelte repeat mitgezaehlt).
function MatchUntil(AMap: TRdxCodeMap; const ARepeat: TRdxToken;
  out AUntil: TRdxToken): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  AUntil := Default(TRdxToken);
  Depth := 0;
  P := ARepeat;
  T := After(AMap, ARepeat);
  while T.Low <> '' do
  begin
    if IsKeywordAfter(T, P) then
    begin
      if T.Low = 'repeat' then
        Inc(Depth)
      else if T.Low = 'until' then
      begin
        if Depth = 0 then
        begin
          AUntil := T;
          Exit(True);
        end;
        Dec(Depth);
      end;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

function StatementEnd(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  ADepth: Integer; out ALast: TRdxToken): Boolean; forward;

// Die Anweisung hinter AOpen ('do', 'then', 'else'): ihr letztes Token -
// AOpen selbst, wenn sie leer ist ('do ;').
function BranchEnd(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  ADepth: Integer; out ALast: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, AOpen);
  if IsStopAfter(N, AOpen) then
  begin
    ALast := AOpen;
    Exit(True);
  end;
  Result := StatementEnd(AMap, N, ADepth, ALast);
end;

// Das letzte Token der Anweisung ab AFirst (ihr erstes Token): begin, try,
// case, asm ueber die end-Bilanz; if/else, for/while/with, repeat..until
// und die einfache Anweisung (SimpleEnd). False, wenn die Hilfe sie nicht
// sicher liest.
function StatementEnd(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  ADepth: Integer; out ALast: TRdxToken): Boolean;
var
  Head, X, Dummy : TRdxToken;
begin
  Result := False;
  ALast := Default(TRdxToken);
  if (AFirst.Low = '') or (ADepth > MAX_NESTING) then
    Exit;
  if not IsKeywordAfter(AFirst, Before(AMap, AFirst)) then
    Exit(SimpleEnd(AMap, AFirst, ALast));
  if InList(AFirst.Low, BLOCK_WORDS) then
  begin
    BlockEnd(AMap, AFirst, nil, ALast, Dummy);
    Exit(ALast.Low <> '');
  end;
  if AFirst.Low = 'if' then
  begin
    if not HeadWord(AMap, AFirst, 'then', Head)
       or not BranchEnd(AMap, Head, ADepth + 1, ALast) then
      Exit(False);
    X := After(AMap, ALast);
    if (X.Low = 'else') and IsKeywordAfter(X, ALast) then
      Exit(BranchEnd(AMap, X, ADepth + 1, ALast));
    Exit(True);
  end;
  if InList(AFirst.Low, DO_WORDS) then
    Exit(HeadWord(AMap, AFirst, 'do', Head)
      and BranchEnd(AMap, Head, ADepth + 1, ALast));
  if AFirst.Low = 'repeat' then
    Exit(MatchUntil(AMap, AFirst, X)
      and SimpleEnd(AMap, After(AMap, X), ALast));
  Result := SimpleEnd(AMap, AFirst, ALast);
end;

// Die Schleife ab dem Schluesselwort AKw (for, while, repeat); False, wenn
// die Hilfe sie nicht sicher liest.
function ReadLoop(AMap: TRdxCodeMap; const AKw: TRdxToken;
  out ALoop: TRdxLoopSpan): Boolean;
var
  U : TRdxToken;
begin
  ALoop := Default(TRdxLoopSpan);
  ALoop.Kw := AKw;
  if AKw.Low = 'repeat' then
  begin
    ALoop.BodyOpen := AKw;
    if not MatchUntil(AMap, AKw, U) then
      Exit(False);
    ALoop.BodyLast := Before(AMap, U);
    Exit(SimpleEnd(AMap, After(AMap, U), ALoop.Last));
  end;
  Result := HeadWord(AMap, AKw, 'do', ALoop.BodyOpen)
    and BranchEnd(AMap, ALoop.BodyOpen, 0, ALoop.BodyLast);
  ALoop.Last := ALoop.BodyLast;
end;

// Die innerste Schleife der Routine, in deren RUMPF AAt steht: die
// Schluesselwoerter zwischen Rumpfanfang und AAt, vom naechsten an
// rueckwaerts - die erste, deren Rumpf AAt umfasst, ist die innerste. Eine
// Schleife dazwischen, die die Hilfe nicht liest, sperrt (sie koennte AAt
// umfassen). '' oder der Grund.
function LoopAround(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const AAt: TRdxToken; out ALoop: TRdxLoopSpan): string;
var
  Kws  : TArray<TRdxToken>;
  T, P : TRdxToken;
  i    : Integer;
begin
  ALoop := Default(TRdxLoopSpan);
  Kws := nil;
  P := ARoutine.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, AAt) do
  begin
    if InList(T.Low, LOOP_WORDS) and IsKeywordAfter(T, P) then
      AddToken(Kws, T);
    P := T;
    T := After(AMap, T);
  end;
  for i := High(Kws) downto 0 do
  begin
    if not ReadLoop(AMap, Kws[i], ALoop) then
      Exit(_(R_LH_LOOP_UNREADABLE, [Kws[i].Line]));
    if TokBefore(ALoop.BodyOpen, AAt)
       and not TokBefore(ALoop.BodyLast, AAt) then
      Exit('');
  end;
  ALoop := Default(TRdxLoopSpan);
  Result := MsgStaleSuffix(_(R_LH_NO_LOOP));
end;

// Der Block, in dessen Anweisungsliste AKw steht: rueckwaerts der erste
// Oeffner ohne sein end bzw. until (begin, case, try, asm, record,
// repeat) oder ein finally/except auf derselben Ebene; leer ohne.
function OpenerBefore(AMap: TRdxCodeMap; const AKw: TRdxToken): TRdxToken;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := Before(AMap, AKw);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsKeywordAt(AMap, T, P) then
    begin
      if (T.Low = 'end') or (T.Low = 'until') then
        Inc(Depth)
      else if IsEndOpener(T.Low) or (T.Low = 'repeat') then
      begin
        if Depth = 0 then
          Exit(T);
        Dec(Depth);
      end
      else if (Depth = 0) and ((T.Low = 'finally') or (T.Low = 'except')) then
        Exit(T);
    end;
    T := P;
  end;
end;

// Darf die Deklaration vor die Schleife? Ihr Schluesselwort steht als
// erstes auf seiner Zeile (die nicht in einem Kommentar beginnt), beginnt
// eine Anweisung (';' oder 'begin' davor) in der Liste eines begin..end.
// '' oder der Grund.
function PlaceReason(AMap: TRdxCodeMap; const AKw: TRdxToken): string;
begin
  Result := '';
  if not FirstOnLine(AMap, AKw) or AMap.StartsInside(AKw.Line)
     or not InList(Before(AMap, AKw).Low, LOOP_PREV)
     or (OpenerBefore(AMap, AKw).Low <> 'begin') then
    Result := _(R_LH_PLACE, [AKw.Line]);
end;

// Haengt ASpan an AList an.
procedure AddSpan(var AList: TArray<TRefactorSpan>; const ASpan: TRefactorSpan);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := ASpan;
end;

// Der Sperrgrund, wenn AMemberLow die Referenz ungueltig machen kann
// (FIELD_RESETS bzw. PARAM_RESETS); sonst ''.
function ResetReason(const ARule: TRdxLookupRule; const AMemberLow,
  ACallText: string; ALine: Integer; const ARecv: string): string;
begin
  Result := '';
  if ARule.Field and InList(AMemberLow, FIELD_RESETS) then
    Result := _(R_LH_RESET_FIELD, [ACallText, ALine, ARecv])
  else if not ARule.Field and InList(AMemberLow, PARAM_RESETS) then
    Result := _(R_LH_RESET_PARAM, [ACallText, ALine, ARecv]);
end;

// Die Schleife von ihrem Schluesselwort bis zum Ende der Anweisung: jede
// Nennung des Empfaengers als 'Q.Member' mit erlaubtem Member, keine
// anonyme Methode; die Vorkommen des Aufrufs (gleiches Literal) in
// ASpans. '' oder der Grund.
function ExtentReason(AMap: TRdxCodeMap; const ALoop: TRdxLoopSpan;
  const ACall: TRdxLookupCall; const ARule: TRdxLookupRule;
  const ALookup: string; out ASpans: TArray<TRefactorSpan>): string;
var
  T, P, N, M : TRdxToken;
  Recv       : string;
  Occ        : TRdxLookupCall;
  Span       : TRefactorSpan;
begin
  Result := '';
  ASpans := nil;
  Recv := TokText(AMap, ACall.Recv);
  P := Before(AMap, ALoop.Kw);
  T := ALoop.Kw;
  while (T.Low <> '') and not TokBefore(ALoop.Last, T) do
  begin
    if InList(T.Low, ROUTINE_WORDS) and IsKeywordAfter(T, P) then
      Exit(_(R_LH_ANON, [Recv]));
    if T.IsWord and SameIdent(T.Low, ACall.Recv.Low) then
    begin
      N := After(AMap, T);
      M := After(AMap, N);
      if InList(P.Low, IDENT_PREFIXES) or (N.Low <> '.') or not M.IsWord then
        Exit(_(R_LH_BARE, [Recv, T.Line, Recv]));
      Result := ResetReason(ARule, M.Low, Recv + '.' + TokText(AMap, M),
        T.Line, Recv);
      if Result <> '' then
        Exit;
      if (M.Low = LowerCase(ARule.Method))
         and (ReadCall(AMap, M, ARule, Occ) = '') and (Occ.Lit = ACall.Lit) then
      begin
        Span := TRefactorSpan.Make(SPAN_LOOKUP, T.Line, T.Col, T.Line,
          Occ.Close.EndCol);
        if CommentInRange(AMap, Span) then
          Exit(_(R_LH_COMMENT, [ALookup, T.Line]));
        AddSpan(ASpans, Span);
      end;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Kommt ALow (klein) als ganzes Wort irgendwo in der Datei vor - auch in
// Kommentar oder String (strenger als noetig)?
function NameInFile(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  Li : Integer;
begin
  Result := False;
  for Li := 1 to AMap.LineCount do
    if HasWordNoCase(AMap.Raw(Li), ALow) then
      Exit(True);
end;

// Der freie Name: VarNameFor, sonst mit 2 bis 9 dahinter. '' oder der
// Grund.
function NameReason(AMap: TRdxCodeMap; const ARule: TRdxLookupRule;
  const ACall: TRdxLookupCall; out AName: string): string;
var
  Base : string;
  i    : Integer;
begin
  Result := '';
  Base := TRdxLookupHoistFix.VarNameFor(ARule.Prefix, ACall.Text);
  for i := 1 to MAX_NAME_TRIES do
  begin
    if i = 1 then
      AName := Base
    else
      AName := Base + IntToStr(i);
    if not NameInFile(AMap, LowerCase(AName)) then
      Exit;
  end;
  AName := '';
  Result := _(R_LH_NAME, [Base, Base, Base]);
end;

// Was eine Inline-Variable in dieser Datei verbietet: kein Compiler
// (Skript, Include), FPC, ein Delphi vor 10.3. '' oder der Grund.
function CompilerReason(AMap: TRdxCodeMap): string;
var
  Li, TraceLine : Integer;
  S             : string;
begin
  Result := '';
  if ScriptReason(AMap, '') <> '' then
    Exit(_(R_LH_SCRIPT));
  for Li := 1 to AMap.LineCount do
    if LineLooksFpcAware(AMap.Raw(Li)) then
      Exit(_(R_LH_FPC, [Li]));
  S := OldCompilerTrace(AMap, FLOOR_INLINE_DECL, TraceLine);
  if S <> '' then
    Result := _(R_LH_OLD, [S, TraceLine]);
end;

// Der Planer beider Regeln (s. Kopf).
function Hoist(AMap: TRdxCodeMap; ALine: Integer; const ARule: TRdxLookupRule;
  out APlan: TRdxLookupPlan; out AReason: string): Boolean;
var
  Call    : TRdxLookupCall;
  Routine : TRdxRoutine;
  Loop    : TRdxLoopSpan;
  Spans   : TArray<TRefactorSpan>;
  Sp      : TRefactorSpan;
  Name, L : string;
  E       : TRdxEdit;
begin
  Result := False;
  APlan := Default(TRdxLookupPlan);
  Spans := nil;
  Name := '';
  AReason := CallOnLine(AMap, ALine, ARule, Call);
  if AReason = '' then
  begin
    APlan.Receiver := TokText(AMap, Call.Recv);
    APlan.Lookup := APlan.Receiver + '.' + TokText(AMap, Call.Method) + '('
      + Call.Lit + ')';
    AReason := DeclaredReason(AMap, APlan.Receiver);
  end;
  if AReason = '' then
    AReason := EnclosingRoutine(AMap, Call.Recv, Routine);
  if AReason = '' then
    AReason := RoutineReason(AMap, Routine, APlan.Receiver);
  if AReason = '' then
    AReason := LoopAround(AMap, Routine, Call.Recv, Loop);
  if AReason = '' then
    AReason := PlaceReason(AMap, Loop.Kw);
  if AReason = '' then
    AReason := ExtentReason(AMap, Loop, Call, ARule, APlan.Lookup, Spans);
  if AReason = '' then
    AReason := NameReason(AMap, ARule, Call, Name);
  if AReason = '' then
    AReason := CompilerReason(AMap);
  if AReason <> '' then
    Exit;
  // Die Deklaration als eigene Zeile vor der Schleife: ab Spalte 1 der
  // Schleifenzeile bis hinter ihr Schluesselwort (nie ein leerer Bereich,
  // die Zeile traegt das Schluesselwort).
  L := AMap.Raw(Loop.Kw.Line);
  E.Span := TRefactorSpan.Make(SPAN_LOOKUP, Loop.Kw.Line, 1, Loop.Kw.Line,
    Loop.Kw.EndCol);
  E.Expected := Copy(L, 1, Loop.Kw.EndCol - 1);
  E.NewText := Copy(L, 1, Loop.Kw.Col - 1) + 'var ' + Name + ' := '
    + APlan.Lookup + ';' + #10 + E.Expected;
  AddEdit(APlan.Edits, E);
  for Sp in Spans do
  begin
    E.Span := Sp;
    E.Expected := RangeText(AMap, Sp);
    E.NewText := Name;
    AddEdit(APlan.Edits, E);
  end;
  APlan.Name := Name;
  APlan.LoopLine := Loop.Kw.Line;
  APlan.Count := Length(Spans);
  Result := True;
end;

{ TRdxLookupHoistFix }

class function TRdxLookupHoistFix.FieldByNameLoop(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxLookupPlan;
  out AReason: string): Boolean;
begin
  Result := Hoist(AMap, ALine, RuleFor(True), APlan, AReason);
end;

class function TRdxLookupHoistFix.ParamByNameLoop(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxLookupPlan;
  out AReason: string): Boolean;
begin
  Result := Hoist(AMap, ALine, RuleFor(False), APlan, AReason);
end;

class function TRdxLookupHoistFix.VarNameFor(const APrefix,
  AFieldName: string): string;
var
  Body : string;
  C    : Char;
  i    : Integer;
  Up   : Boolean;
begin
  Body := '';
  Up := True;
  for i := 1 to Length(AFieldName) do
  begin
    if Length(Body) >= MAX_NAME_BODY then
      Break;
    C := AFieldName[i];
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      if Up and CharInSet(C, ['a'..'z']) then
        C := Char(Ord(C) - Ord('a') + Ord('A'));
      Body := Body + C;
      Up := False;
    end
    else
      Up := True;
  end;
  Result := APrefix + Body;
end;

class function TRdxLookupHoistFix.UnknownReceiverReason(
  const AName: string): string;
begin
  Result := _(R_LH_UNKNOWN, [AName]);
end;

end.
