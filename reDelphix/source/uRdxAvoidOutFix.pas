unit uRdxAvoidOutFix;

// reDelphix - Editorhilfe fuer SCA086 AvoidOut, OHNE ToolsAPI und ohne
// Parser: der gemeldete 'out'-Parameter wird ein 'var'-Parameter - in der
// Deklaration UND in der Implementierung, in EINEM Schritt (zwei
// Ersetzungen wie bei SCA164/SCA147).
//
// DER FUND (uAvoidOut gelesen): je Zeile das erste 'out' in einer Klammer
// derselben Zeile, dahinter ein Name und - sonst kein Fund - ein Typ
// (untypisiertes 'out Obj' meldet er nicht). Gemeldet werden Deklaration
// und Implementierung, beide mit der Spalte des 'out' ('at column N').
// Nicht gemeldet: Koepfe mit Aufrufkonvention oder external (stdcall,
// safecall, cdecl ...), override (samt Implementierung), Prozedur- und
// Funktionstypen hinter ':' oder '='. Gemeldet werden dagegen Methoden
// eines interface-Typs, 'reference to' und virtuelle Methoden.
//
// BEDEUTUNG: fuer einfache Typen (Integer, Boolean, Double, Pointer,
// Klassen der RTL wie TObject ...) behandelt Delphi 'out' wie 'var' -
// bedeutungsgleich. Fuer verwaltete Typen (string, Interface, dynamisches
// Array, Variant, Record mit solchen Feldern) gibt 'out' den Wert des
// Aufrufers beim Aufruf frei, 'var' nicht - liest die Routine den
// Parameter, bevor sie ihn setzt, sieht sie danach den alten Wert. Der Plan
// sagt es (Changes); jeder Typ, den die Hilfe nicht als einfach kennt
// (PLAIN_TYPES, seit rwE31 Stufe 3 auch einfache Typen der Datei:
// LocalPlainType), zaehlt als verwaltet.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   * kein 'out' an der Spalte (verschoben), untypisiert, kein Routinenkopf
//     um die Klammer (Prozedurtyp, anonyme Methode, 'reference to'),
//     Operator,
//   * die Koepfe dieses Namens in der Datei sind nicht genau ein Paar
//     Deklaration + Implementierung (Methode: Kopf in der Klasse und
//     'TFoo.Bar'; Routine: Kopf im interface-Teil bzw. forward und Rumpf;
//     oder nur der Rumpf - dann ohne Include-Datei, die ihn deklarieren
//     koennte; eines im Kopf der Unit traegt nur Direktiven) - Overload,
//     gleichnamige Methoden anderer Klassen, Deklaration oder
//     Implementierung fehlt; bei einer lokalen Routine zaehlt nur ihre
//     umschliessende Routine (rwE30 Stufe 2); bei den Overloads einer
//     freien Routine nur die mit derselben Zahl von Parametern (rwE31
//     Stufe 3, SameCountHeads),
//   * der Name steht im Code ohne Aufruf ('@Bar', 'OnX := Bar'; nicht als
//     eigene Anweisung 'then Bar;') - als Methodenzeiger aendert sich sein
//     Typ,
//   * die Methode ist virtual/dynamic/abstract/override/final, message,
//     dispid oder overload bzw. hat eine Aufrufkonvention oder external,
//   * sie steht unter published oder ohne Sichtbarkeit (eine Formdatei kann
//     sie an ein Ereignis binden), ihre Klasse implementiert ein Interface
//     aus einer anderen Unit oder eine Wurzel mit diesem Member (sie
//     koennte eine Interface-Methode sein; Interfaces dieser Datei ohne den
//     Namen sperren seit rwE30 Stufe 2 nicht), oder ihre Deklaration steht
//     nicht direkt in der Klasse bzw. (seit rwE31 Stufe 3) im record- oder
//     object-Typ,
//   * die Deklaration einer Routine steht in einem Typ (Methode eines
//     interface-Typs u. a.),
//   * der andere Kopf traegt das 'out' nicht genau so ('out A, B: T'),
//   * die Routine ist im interface-Teil deklariert bzw. die Methode ist
//     ausserhalb der Unit sichtbar (Klasse im interface-Teil, nicht private/
//     strict private): eine andere Unit kann sie als Prozedur- bzw.
//     Methodenwert nehmen, dort passte der Typ nicht mehr (E2009) - die
//     Hilfe liest nur diese Datei (Realwelt-Test rwE29: mORMot
//     mormot.core.data.pas:948 '_BCI_ObjArray', in mormot.core.json als
//     'fCompare[true] := _BCI_ObjArray' an TRttiCompare zugewiesen; dieselbe
//     Sperre wie SCA170, uRdxConstStringParameterFix.LocalReason).
// Aufrufer in anderen Units bleiben uebersetzbar (out und var verlangen
// beide eine Variable) - sie gibt es nur fuer exportierte Routinen, und die
// sperrt die Hilfe.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanAvoidOut (Form TRdxFixPlanner, Geruest TRdxFixFrame mit dem Plan)
// traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_OUT_MOVED = 'no "out" parameter at the reported column';
  R_OUT_UNTYPED = 'untyped "out" parameter - "var" would mean something '
    + 'else';
  R_OUT_NOT_ROUTINE = 'the parameter list belongs to a procedural type or '
    + 'an anonymous method - its signature is a contract';
  R_OUT_OPERATOR = 'operator - its signature is fixed';
  R_OUT_HEADS = '%d routine headers named %s in this file - overload or '
    + 'ambiguous';
  R_OUT_NO_DECL = 'the declaration of %s is not in this file';
  R_OUT_NO_IMPL = 'the implementation of %s is not in this file';
  R_OUT_NOT_IN_CLASS = '%s is not declared directly in class %s';
  R_OUT_DIRECTIVE = '%s is "%s" - other code depends on its exact signature';
  R_OUT_PUBLISHED = '%s is in the published or default section of %s - a '
    + 'form file may bind it to an event';
  R_OUT_INTERFACES = 'class %s implements interfaces - %s could implement '
    + 'an interface method';
  R_OUT_IN_TYPE = '%s is declared inside a type - its signature is a '
    + 'contract';
  R_OUT_REFERENCE = '%s is used without a call in line %d (method '
    + 'pointer?) - its type would change';
  R_OUT_MISMATCH = 'the other header of %s has no matching "out %s"';
  R_OUT_INCLUDE = 'the file includes other files - they could declare %s';
  R_OUT_HEAD_UNSAFE = 'the header of %s is not safe to read';
  // Realwelt-Test rwE29: wortgleich mit SCA170 (uRdxConstStringParameterFix
  // R_CS_INTERFACE/R_CS_VISIBLE) - dieselbe msgid, dieselbe Uebersetzung.
  R_OUT_INTERFACE = 'the routine is declared in the interface section (line '
    + '%d) - other units can use it as a procedure value';
  // rwE30 Stufe 2 (AssignedFirstReason): der Hinweis einer Hilfe nur im
  // Menue. Seit Fix-Runde 4 nach rwE32 (Kastri DW.EXIF.Win.pas:102
  // 'apropitem hat einen verwalteten Typ' - PPropertyItem ist ein Zeiger,
  // den die Hilfe nur nicht kennt): "verwaltet ODER unbekannt", der Typ in
  // Klammern, der Name wie im Text. %s Parameter, %s Typ, %s Routine, %d
  // Zeile.
  R_OUT_NOT_FIRST = 'not in the light bulb - %s has a managed type or one '
    + 'the quick fix does not know (%s) and is not set as the first '
    + 'statement of %s (line %d): with "var" the caller''s old value can '
    + 'stay where "out" cleared it';
  R_OUT_VISIBLE = 'the method is visible outside the unit (not private, '
    + 'class in the interface section) - other units can use it as a method '
    + 'pointer';

type
  // Ergebnis des Planers (uRdxFixTable: Plan-Form im Geruest TRdxFixFrame).
  //   Name     der Parameter (Menuetext) - schon gesetzt, wenn der Planer
  //            danach ablehnt
  //   Changes  verwalteter oder unbekannter Typ: aendert das Verhalten (E2)
  //   Edits    je Kopf das 'out' durch 'var', in der Reihenfolge der Datei
  //   MenuOnly verwalteter Typ, und der Rumpf setzt den Parameter nicht als
  //            erste Anweisung (AssignedFirstReason, rwE30 Stufe 2): die
  //            Hilfe steht nur im Menue (TRdxFixOutcome.MenuOnly), Caution
  //            ist ihr Hinweis (uebersetzt)
  TRdxOutPlan = record
    Name     : string;
    Changes  : Boolean;
    Edits    : TArray<TRdxEdit>;
    MenuOnly : Boolean;
    Caution  : string;
  end;

  TRdxAvoidOutFix = class
  public
    // SCA086: der Plan zum Fund auf ALine (Spalte aus der Meldung) - True,
    // oder False mit dem Grund. Form TRdxPlannerOf<TRdxOutPlan>.
    class function OutToVar(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxOutPlan;
      out AReason: string): Boolean; static;

    // Ist ATypeText ('string', 'System.Integer', 'array of Byte') ein Typ,
    // fuer den 'out' und 'var' sich unterscheiden? False nur fuer die
    // bekannten einfachen Typen (PLAIN_TYPES); Gross/klein und Leerraum
    // egal.
    class function IsManagedType(const ATypeText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks,       // TRdxBlocks, HeadStart, HasDirective, EnclosingClass,
                    // InsideTypeBody, IncludesUpTo
  uRdxRoutineFixes; // InterfaceMemberReason (wie SCA147)

const
  SPAN_086 = 'sca086';
  KW_OUT = 'out';
  NEW_WORD = 'var';
  // Davor steht ein Parameter am Anfang: '(' oder ';'.
  PARAM_PREV: array[0..1] of string = ('(', ';');
  // Direktiven, die die Signatur an andere Stellen binden: Hierarchie,
  // Botschaften, Overload, Aufrufkonvention, Bindung nach aussen.
  BOUND_DIRECTIVES: array[0..16] of string = ('virtual', 'dynamic',
    'abstract', 'override', 'final', 'message', 'dispid', 'overload',
    'stdcall', 'safecall', 'cdecl', 'pascal', 'winapi', 'varargs',
    'external', 'export', 'vectorcall');
  // Dieselben ohne 'overload' - fuer eine freie Routine, deren Overloads in
  // dieser Datei eine andere Zahl von Parametern haben (DirectiveReason).
  DIR_OVERLOAD = 'overload';
  ROUTINE_BOUND: array[0..15] of string = ('virtual', 'dynamic',
    'abstract', 'override', 'final', 'message', 'dispid', 'stdcall',
    'safecall', 'cdecl', 'pascal', 'winapi', 'varargs', 'external', 'export',
    'vectorcall');
  FORWARD_WORD: array[0..0] of string = ('forward');
  // Sichtbarkeiten, unter denen eine Formdatei die Methode binden kann - ''
  // ist der Abschnitt ohne Wort (published in TPersistent-Erben).
  STREAMED_VIS: array[0..1] of string = ('published', '');
  // Sichtbarkeiten, die eine Methode nur in dieser Unit zeigen.
  PRIVATE_VIS: array[0..1] of string = ('private', 'strict private');
  // Typen, fuer die 'out' und 'var' gleich sind (klein, ohne 'system.').
  PLAIN_TYPES: array[0..47] of string = ('integer', 'cardinal', 'shortint',
    'smallint', 'longint', 'int64', 'uint64', 'byte', 'word', 'longword',
    'dword', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8',
    'uint16', 'uint32', 'boolean', 'bytebool', 'wordbool', 'longbool',
    'char', 'ansichar', 'widechar', 'single', 'double', 'extended', 'real',
    'real48', 'currency', 'comp', 'pointer', 'pchar', 'pansichar',
    'pwidechar', 'tdatetime', 'tdate', 'ttime', 'thandle', 'hwnd',
    'tobject', 'tclass', 'tpoint', 'trect', 'tsize', 'tguid');
  SYSTEM_PREFIX = 'system.';
  // So viele Koepfe liest OuterOf rueckwaerts hoechstens.
  MAX_OUTER_STEPS = 400;
  // AssignedFirstReason: Bloecke mit eigenem end bzw. until ...
  BLOCK_OPENERS: array[0..4] of string = ('begin', 'try', 'case', 'asm',
    'repeat');
  // ... und Spruenge aus dem Rumpf.
  JUMP_WORDS: array[0..5] of string = ('exit', 'raise', 'goto', 'break',
    'continue', 'halt');
  // StatementCall: davor beginnt eine Anweisung (bzw. ';'), dahinter endet
  // sie.
  CALL_PREV: array[0..7] of string = ('begin', 'then', 'else', 'do', 'try',
    'finally', 'except', 'repeat');
  CALL_NEXT: array[0..5] of string = (';', 'end', 'else', 'until', 'except',
    'finally');
  // LocalPlainType: so tief folgt die Hilfe Typen der Datei; davor steht
  // die Deklaration 'Name = ..'.
  MAX_TYPE_DEPTH = 3;
  TYPE_DECL_PREV: array[0..1] of string = ('type', ';');
  // PlainRecordBody (rwE32 Stufe 4, mormot.crypt.secure.pas:597): Abschnitte
  // und Methoden eines record- oder object-Typs tragen keine Daten ...
  RECORD_SECTIONS: array[0..4] of string = ('private', 'protected', 'public',
    'published', 'strict');
  MEMBER_HEADS: array[0..4] of string = ('procedure', 'function',
    'constructor', 'destructor', 'property');
  // ... auch nicht die Direktiven hinter ihrem ';' ('inline;', 'overload;',
  // 'message WM_X;', 'default;').
  MEMBER_DIRECTIVES: array[0..20] of string = ('inline', 'overload',
    'static', 'virtual', 'dynamic', 'abstract', 'override', 'reintroduce',
    'final', 'cdecl', 'stdcall', 'register', 'pascal', 'safecall', 'winapi',
    'message', 'deprecated', 'platform', 'experimental', 'default',
    'assembler');
  // SetsFirst: hier endet eine Zuweisung ohne ';' (RhsClean) ...
  BRANCH_STOPS: array[0..1] of string = ('else', 'end');
  // ... und das darf die Bedingung eines if nicht tragen (IfSets): eine
  // Struktur, eine anonyme Methode, einen bedingten Ausdruck.
  NOT_IN_CONDITION: array[0..7] of string = ('begin', 'case', 'try', 'asm',
    'repeat', 'procedure', 'function', 'if');

type
  // Ein Routinenkopf mit dem gesuchten Namen.
  TRdxOutHead = record
    Kw   : TRdxToken;   // das Routinenwort
    Name : TRdxToken;   // das letzte Glied des Namens
    Qual : Boolean;     // 'TFoo.Bar' - die Implementierung einer Methode
  end;
  TRdxOutHeads = TArray<TRdxOutHead>;

class function TRdxAvoidOutFix.IsManagedType(const ATypeText: string): Boolean;
var
  T : string;
begin
  T := Squeezed(ATypeText);   // uRdxCodeMap: ohne Leerzeichen und Tabs, klein
  if Copy(T, 1, Length(SYSTEM_PREFIX)) = SYSTEM_PREFIX then
    Delete(T, 1, Length(SYSTEM_PREFIX));
  Result := not InList(T, PLAIN_TYPES);
end;

// Das 'out' an (ALine, ACol) am Anfang eines Parameters: '' oder der Grund.
function OutAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AOut: TRdxToken): string;
var
  P : TRdxToken;
begin
  Result := MsgMovedSuffix(_(R_OUT_MOVED));
  AOut := Default(TRdxToken);
  if (ALine < 1) or (ALine > AMap.LineCount)
     or not AMap.IsCode(ALine, ACol) then
    Exit;
  AOut := TokenAt(AMap, ALine, ACol);
  if (AOut.Low <> KW_OUT) or (AOut.Col <> ACol) then
    Exit;
  P := Before(AMap, AOut);
  if IsKeywordAfter(AOut, P) and InList(P.Low, PARAM_PREV) then
    Result := '';
end;

// Die Namen hinter AOut bis zum ':' (klein, mit ',' verbunden: 'a,b') und
// der Typ dahinter bis ';', '=' bzw. ')' auf Klammertiefe 0 (die Token
// klein ohne Trenner: 'arrayofbyte'). False ohne Typ.
function ReadParam(AMap: TRdxCodeMap; const AOut: TRdxToken;
  out ANames, AType: string): Boolean;
var
  T     : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  ANames := '';
  AType := '';
  T := After(AMap, AOut);
  while T.IsWord do
  begin
    ANames := ANames + T.Low;
    T := After(AMap, T);
    if T.Low <> ',' then
      Break;
    ANames := ANames + ',';
    T := After(AMap, T);
  end;
  if (ANames = '') or (T.Low <> ':') then
    Exit;
  Depth := 0;
  T := After(AMap, T);
  while T.Low <> '' do
  begin
    if (T.Low = '(') or (T.Low = '[') or (T.Low = '<') then
      Inc(Depth)
    else if (T.Low = ')') or (T.Low = ']') or (T.Low = '>') then
    begin
      if Depth = 0 then
        Break;
      Dec(Depth);
    end
    else if (Depth = 0) and ((T.Low = ';') or (T.Low = '=')) then
      Break;
    AType := AType + T.Low;
    T := After(AMap, T);
  end;
  Result := AType <> '';
end;

// Die '(' der Parameterliste um AOut (rueckwaerts auf Klammertiefe 0); Low
// = '' ohne - auch, wenn davor ein begin oder end steht (kein Kopf).
function ListOpen(AMap: TRdxCodeMap; const AOut: TRdxToken): TRdxToken;
var
  T     : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := Before(AMap, AOut);
  while T.Low <> '' do
  begin
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      if Depth = 0 then
      begin
        if T.Low = '(' then
          Result := T;
        Exit;
      end;
      Dec(Depth);
    end
    else if (Depth = 0) and ((T.Low = 'begin') or (T.Low = 'end')) then
      Exit;
    T := Before(AMap, T);
  end;
end;

// Das Routinenwort vor dem Namens-Token AName ('procedure TFoo<T>.Bar' ->
// 'procedure'), rueckwaerts ueber die Kette wie uRdxCodeMap.DeclaresAfter;
// AQual: der Name ist qualifiziert.
function KeywordBefore(AMap: TRdxCodeMap; const AName: TRdxToken;
  out AQual: Boolean): TRdxToken;
var
  K, Open : TRdxToken;
begin
  AQual := False;
  K := Before(AMap, AName);
  while K.Low = '.' do
  begin
    AQual := True;
    K := Before(AMap, K);   // das Glied vor dem '.' - oder seine '>'
    if K.Low = '>' then
    begin
      Open := OpenAngleBefore(AMap, K);
      if Open.Low = '' then
        Exit(Default(TRdxToken));
      K := Before(AMap, Open);
    end;
    K := Before(AMap, K);
  end;
  Result := K;
end;

// Ist AName das Namens-Token eines Routinenkopfs? Dann AHead.
function HeadAt(AMap: TRdxCodeMap; const AName: TRdxToken;
  out AHead: TRdxOutHead): Boolean;
begin
  AHead := Default(TRdxOutHead);
  AHead.Name := AName;
  AHead.Kw := KeywordBefore(AMap, AName, AHead.Qual);
  Result := (AHead.Kw.Low <> '') and IsRoutineHead(AMap, AHead.Kw)
    and SameTok(NameAfter(AMap, AHead.Kw), AName);
end;

// Der Kopf zur Parameterliste AOpen; False fuer eine Liste ohne Namen davor
// (Prozedurtyp, anonyme Methode, 'reference to').
function HeadOfList(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  out AHead: TRdxOutHead): Boolean;
var
  B, Open : TRdxToken;
begin
  AHead := Default(TRdxOutHead);
  B := Before(AMap, AOpen);
  if B.Low = '>' then
  begin
    Open := OpenAngleBefore(AMap, B);
    if Open.Low = '' then
      Exit(False);
    B := Before(AMap, Open);
  end;
  Result := B.IsWord and not InList(B.Low, ROUTINE_WORDS)
    and HeadAt(AMap, B, AHead);
end;

// Steht der Name T allein als Anweisung ('then Bar;', 'begin Bar end',
// die Marke eines case-Zweigs '1: Bar;') - der Aufruf einer Ueberladung ohne
// Parameter, kein Methodenzeiger (rwE31 Stufe 3: jcl
// JclStringConversions.pas:1290 'then FlagInvalidSequence;', :2299
// 'SurrogateLowStart..SurrogateLowEnd: FlagInvalidSequence;')? Hinter ':'
// stuende sonst nur ein Typ - auch kein Methodenzeiger.
function StatementCall(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  P : TRdxToken;
begin
  P := Before(AMap, T);
  Result := InList(After(AMap, T).Low, CALL_NEXT)
    and ((P.Low = ';') or (P.Low = ':') or (InList(P.Low, CALL_PREV)
         and IsKeywordAfter(P, Before(AMap, P))));
end;

// Alle Koepfe mit dem Namen ALow; AUseLine: die erste Zeile, auf der der
// Name im Code ohne Aufruf steht ('@Bar', 'OnX := Bar'; nicht als eigene
// Anweisung, StatementCall), 0 ohne. Nur
// zwischen AFrom und ATo (beide eingeschlossen), wenn AFrom.Low <> '' - der
// Bereich einer Routine, die die gesuchte lokal deklariert.
function HeadsNamed(AMap: TRdxCodeMap; const ALow: string;
  const AFrom, ATo: TRdxToken; out AUseLine: Integer): TRdxOutHeads;
var
  T : TRdxToken;
  H : TRdxOutHead;
  n : Integer;
begin
  Result := nil;
  AUseLine := 0;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if (T.Low = ALow) and ((AFrom.Low = '')
       or (not TokBefore(T, AFrom) and not TokBefore(ATo, T))) then
    begin
      if HeadAt(AMap, T, H) then
      begin
        n := Length(Result);
        SetLength(Result, n + 1);
        Result[n] := H;
      end
      else if (AUseLine = 0) and (After(AMap, T).Low <> '(')
         and not StatementCall(AMap, T) then
        AUseLine := T.Line;
    end;
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Das 'out' vor den Namen ANames (ReadParam) in der Parameterliste von
// AHead; Low = '' ohne Liste (AHasList = False) oder wenn die Liste es nicht
// genau einmal traegt.
function OutInHead(AMap: TRdxCodeMap; const AHead: TRdxOutHead;
  const ANames: string; out AHasList: Boolean): TRdxToken;
var
  T, Open, Close : TRdxToken;
  Names, Typ     : string;
  Count          : Integer;
begin
  Result := Default(TRdxToken);
  T := After(AMap, AHead.Name);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  AHasList := T.Low = '(';
  if not AHasList then
    Exit;
  Open := T;
  Close := MatchClose(AMap, Open);
  if Close.Low = '' then
    Exit;
  Count := 0;
  T := After(AMap, Open);
  while (T.Low <> '') and TokBefore(T, Close) do
  begin
    if (T.Low = KW_OUT) and InList(Before(AMap, T).Low, PARAM_PREV)
       and ReadParam(AMap, T, Names, Typ) and (Names = ANames) then
    begin
      Inc(Count);
      Result := T;
    end;
    T := After(AMap, T);
  end;
  if Count <> 1 then
    Result := Default(TRdxToken);
end;

// Das Schluesselwort 'implementation' der Unit; Low = '' ohne.
function ImplementationTok(AMap: TRdxCodeMap): TRdxToken;
var
  T : TRdxToken;
begin
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'implementation');
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(T);
    T := NextTokenOnLineWith(AMap, T, 'implementation');
  end;
  Result := T;
end;

// Eine Direktive, die die Signatur bindet (BOUND_DIRECTIVES): '' oder der
// Grund. AOverloadOk (nur freie Routinen, rwE31 Stufe 3): 'overload' bindet
// nicht - die anderen Overloads dieser Datei haben eine andere Zahl von
// Parametern (OutToVar, SameCountHeads); die Umstellung macht keine zwei
// Koepfe gleich.
function DirectiveReason(const R: TRdxRoutine; const AName: string;
  AOverloadOk: Boolean = False): string;
var
  W : string;
begin
  Result := '';
  if AOverloadOk then
  begin
    if HasDirective(R, ROUTINE_BOUND, W) then
      Result := _(R_OUT_DIRECTIVE, [AName, W]);
  end
  else if HasDirective(R, BOUND_DIRECTIVES, W) then
    Result := _(R_OUT_DIRECTIVE, [AName, W]);
end;

// Die Implementierung AImpl mit Rumpf: '' oder der Grund; ihre Grenzen in
// AR.
function ImplReason(AMap: TRdxCodeMap; const AImpl: TRdxOutHead;
  const AName: string; out AR: TRdxRoutine): string;
begin
  Result := '';
  if TRdxBlocks.ReadRoutine(AMap, AImpl.Kw, AR) <> '' then
    Result := _(R_OUT_HEAD_UNSAFE, [AName])
  else if AR.Body.Low = '' then
    Result := _(R_OUT_NO_IMPL, [AName]);
end;

// Methode: ADecl in der Klasse, AImpl 'TFoo.Bar'. '' oder der Grund.
function MethodReason(AMap: TRdxCodeMap; const ADecl, AImpl: TRdxOutHead;
  const AName: string): string;
var
  IR, DR         : TRdxRoutine;
  ClassLow, Disp : string;
  CH             : TRdxClassHead;
  Impl           : TRdxToken;
  IsRecord       : Boolean;
begin
  Result := ImplReason(AMap, AImpl, AName, IR);
  if Result <> '' then
    Exit;
  if Length(IR.Parts) < 2 then
    Exit(_(R_OUT_HEAD_UNSAFE, [AName]));
  ClassLow := IR.Parts[High(IR.Parts) - 1];
  Disp := Copy(IR.Name, 1, LastDelimiter('.', IR.Name) - 1);
  Disp := LastPart(Disp);
  // Auch Methoden eines record- oder object-Typs (rwE31 Stufe 3: Kastri
  // DW.Exif.Win.pas:102 'TGdip = record' mit 'class function .. static',
  // mORMot 'TSynSystemTime' mit {$ifdef}-Kopf record/object). Sie haben
  // keine published-Methodentabelle und implementieren kein Interface;
  // ausserhalb der Unit sichtbar sperrt wie bei Klassen.
  IsRecord := False;
  if not EnclosingClass(AMap, HeadStart(AMap, ADecl.Kw), ClassLow, CH) then
  begin
    IsRecord := EnclosingRecord(AMap, HeadStart(AMap, ADecl.Kw), ClassLow,
      CH);
    if not IsRecord then
      Exit(_(R_OUT_NOT_IN_CLASS, [AName, Disp]));
  end;
  if not IsRecord and InList(CH.Vis, STREAMED_VIS) then
    Exit(_(R_OUT_PUBLISHED, [AName, Disp]));
  Impl := ImplementationTok(AMap);
  if (Impl.Low <> '') and TokBefore(CH.ClassTok, Impl)
     and not InList(CH.Vis, PRIVATE_VIS) then
    Exit(_(R_OUT_VISIBLE));
  // Interfaces der Klasse: nur eines aus einer anderen Unit (direkt oder
  // als Vorfahr eines Interfaces dieser Datei) bzw. eine Wurzel mit einem
  // Member dieses Namens sperrt - wie bei SCA147 (InterfaceMemberReason).
  // Ein Interface dieser Datei mit einem Member gleichen Namens waere ein
  // weiterer Kopf, und PairOf sperrte schon (rwE30 Stufe 2:
  // delphimvcframework MVCFramework.DotEnv.pas:96, MVCFramework.Utils.pas:62,
  // TemplatePro.pas:757 - alle Interfaces in derselben Unit, ohne die
  // Methode).
  if not IsRecord and (TRdxRoutineFixes.InterfaceMemberReason(AMap,
       CH.ClassTok, LowerCase(AName)) <> '') then
    Exit(_(R_OUT_INTERFACES, [Disp, AName]));
  if TRdxBlocks.MethodDecl(AMap, HeadStart(AMap, ADecl.Kw), DR) <> '' then
    Exit(_(R_OUT_HEAD_UNSAFE, [AName]));
  Result := DirectiveReason(DR, AName);
  if Result = '' then
    Result := DirectiveReason(IR, AName);
end;

// Routine ohne eigene Deklaration: nur AImpl mit Rumpf, keine Include-
// Datei, die sie deklarieren koennte. Steht der einzige Kopf in einem Typ,
// ist er die Methode eines interface-Typs (oder einer Klasse ohne
// Implementierung hier). Includes im Kopf der Unit (vor interface bzw.
// vor uses) tragen nur Direktiven (IncludesUpTo; rwE30 Stufe 2: cnwizards
// CnIDEVersion.pas:331 'CnWizards.inc', jcl JclGraphics.pas:5302
// 'jcl.inc', mORMot test.core.data.pas:1332 'mormot.defines.inc'). Eine
// lokale Routine (AOuter.Head.Low <> '': ihre umschliessende Routine)
// deklariert nur ein Include in AOuter. '' oder der Grund.
function SingleReason(AMap: TRdxCodeMap; const AImpl: TRdxOutHead;
  const AName: string; const AOuter: TRdxRoutine;
  AOverloadOk: Boolean): string;
var
  IR      : TRdxRoutine;
  Include : Boolean;
begin
  if InsideTypeBody(AMap, HeadStart(AMap, AImpl.Kw)) then
    Exit(_(R_OUT_IN_TYPE, [AName]));
  Result := ImplReason(AMap, AImpl, AName, IR);
  if Result <> '' then
    Exit;
  if AOuter.Head.Low <> '' then
    Include := IncludeInLines(AMap, AOuter.Head.Line, AOuter.Last.Line) > 0
  else
    Include := Length(IncludesUpTo(AMap, AMap.LineCount)) > 0;
  if Include then
    Exit(_(R_OUT_INCLUDE, [AName]));
  Result := DirectiveReason(IR, AName, AOverloadOk);
end;

// Routine: ADecl forward, AImpl mit Rumpf. Im interface-Teil (nicht in
// einem Typ) ist sie exportiert und gesperrt (R_OUT_INTERFACE, rwE29). ''
// oder der Grund.
function RoutineReason(AMap: TRdxCodeMap; const ADecl, AImpl: TRdxOutHead;
  const AName: string; AOverloadOk: Boolean): string;
var
  IR, DR : TRdxRoutine;
  Impl   : TRdxToken;
  W      : string;
begin
  Result := ImplReason(AMap, AImpl, AName, IR);
  if Result <> '' then
    Exit;
  Impl := ImplementationTok(AMap);
  if (Impl.Low <> '') and TokBefore(ADecl.Kw, Impl) then
  begin
    if InsideTypeBody(AMap, HeadStart(AMap, ADecl.Kw)) then
      Exit(_(R_OUT_IN_TYPE, [AName]));
    Exit(_(R_OUT_INTERFACE, [ADecl.Kw.Line]));
  end
  else
  begin
    if TRdxBlocks.ReadRoutine(AMap, ADecl.Kw, DR) <> '' then
      Exit(_(R_OUT_HEAD_UNSAFE, [AName]));
    // Zwei Rumpfe gleichen Namens (lokale Routinen) - kein Paar.
    if (DR.Body.Low <> '') or not HasDirective(DR, FORWARD_WORD, W) then
      Exit(_(R_OUT_HEADS, [2, AName]));
  end;
  Result := DirectiveReason(DR, AName, AOverloadOk);
  if Result = '' then
    Result := DirectiveReason(IR, AName, AOverloadOk);
end;

// Deklaration und Implementierung aus den Koepfen AHeads: '' mit dem Paar
// (AHasDecl = False: nur die Implementierung), sonst der Grund.
// AOverloadOk: s. DirectiveReason (nur Routinen).
function PairOf(AMap: TRdxCodeMap; const AHeads: TRdxOutHeads;
  const AName: string; const AOuter: TRdxRoutine; AOverloadOk: Boolean;
  out ADecl, AImpl: TRdxOutHead; out AHasDecl: Boolean): string;
var
  Q, U : TRdxOutHeads;
  H    : TRdxOutHead;
begin
  ADecl := Default(TRdxOutHead);
  AImpl := Default(TRdxOutHead);
  AHasDecl := False;
  Q := nil;
  U := nil;
  for H in AHeads do
    if H.Qual then
    begin
      SetLength(Q, Length(Q) + 1);
      Q[High(Q)] := H;
    end
    else
    begin
      SetLength(U, Length(U) + 1);
      U[High(U)] := H;
    end;
  if (Length(Q) = 1) and (Length(U) = 1) then
  begin
    ADecl := U[0];
    AImpl := Q[0];
    AHasDecl := True;
    Result := MethodReason(AMap, ADecl, AImpl, AName);
  end
  else if (Length(Q) = 0) and (Length(U) = 1) then
  begin
    AImpl := U[0];
    Result := SingleReason(AMap, AImpl, AName, AOuter, AOverloadOk);
  end
  else if (Length(Q) = 0) and (Length(U) = 2) then
  begin
    ADecl := U[0];
    AImpl := U[1];
    AHasDecl := True;
    Result := RoutineReason(AMap, ADecl, AImpl, AName, AOverloadOk);
  end
  else if (Length(Q) = 1) and (Length(U) = 0) then
    Result := _(R_OUT_NO_DECL, [AName])
  else
    Result := _(R_OUT_HEADS, [Length(AHeads), AName]);
end;

// Die Ersetzung 'out' -> 'var' an AOut.
function OutEdit(AMap: TRdxCodeMap; const AOut: TRdxToken): TRdxEdit;
begin
  Result := Default(TRdxEdit);
  Result.Span := TRefactorSpan.Make(SPAN_086, AOut.Line, AOut.Col, AOut.Line,
    AOut.EndCol);
  Result.Expected := TokText(AMap, AOut);
  Result.NewText := NEW_WORD;
end;

// Das 'out' im Kopf AHead: am gemeldeten Kopf AOwn das gemeldete AOut,
// sonst das passende (OutInHead). '' mit dem Token in AFound (Low = '': die
// Implementierung wiederholt die Parameterliste nicht - dort ist nichts zu
// tun), sonst der Grund.
function OutOfHead(AMap: TRdxCodeMap; const AHead, AOwn: TRdxOutHead;
  const AOut: TRdxToken; const ANames, AName, AParam: string;
  AIsImpl: Boolean; out AFound: TRdxToken): string;
var
  HasList : Boolean;
begin
  Result := '';
  if SameTok(AHead.Kw, AOwn.Kw) then
  begin
    AFound := AOut;
    Exit;
  end;
  AFound := OutInHead(AMap, AHead, ANames, HasList);
  if (AFound.Low = '') and (HasList or not AIsImpl) then
    Result := _(R_OUT_MISMATCH, [AName, AParam]);
end;

// Ist ALow (klein) an T ein Sprung aus dem Rumpf - exit, raise, goto,
// break, continue, halt (nicht hinter '.')?
function JumpAt(const T, APrev: TRdxToken): Boolean;
begin
  Result := IsKeywordAfter(T, APrev) and InList(T.Low, JUMP_WORDS);
end;

// Die rechte Seite der Zuweisung an AName ('ALow := ..') bis zum ';', else
// oder end auf Klammertiefe 0 bzw. bis AStop: liest sie ALow nicht ('S := S
// + ..')? Dann True und ANext ist das Token dahinter; sonst False und ALine
// die Zeile des Lesens. Das else eines bedingten Ausdrucks (Delphi 13:
// 'S := if C then A else B', Review Gruppe M) gehoert zur rechten Seite.
function RhsClean(AMap: TRdxCodeMap; const AName, AStop: TRdxToken;
  const ALow: string; out ANext: TRdxToken; out ALine: Integer): Boolean;
var
  X, P         : TRdxToken;
  Paren, Conds : Integer;
begin
  Result := False;
  ALine := AName.Line;
  Paren := 0;
  Conds := 0;
  P := After(AMap, AName);
  X := After(AMap, P);
  while (X.Low <> '') and TokBefore(X, AStop) do
  begin
    if (X.Low = '(') or (X.Low = '[') then
      Inc(Paren)
    else if ((X.Low = ')') or (X.Low = ']')) and (Paren > 0) then
      Dec(Paren)
    else if (Paren = 0) and (X.Low = 'if') and IsKeywordAfter(X, P) then
      Inc(Conds)
    else if (Paren = 0) and (Conds > 0) and (X.Low = 'else')
       and IsKeywordAfter(X, P) then
      Dec(Conds)
    else if (Paren = 0) and ((X.Low = ';') or (IsKeywordAfter(X, P)
       and InList(X.Low, BRANCH_STOPS))) then
      Break;
    if SameIdent(X.Low, ALow) and (P.Low <> '.') then
    begin
      ALine := X.Line;
      Exit;
    end;
    P := X;
    X := After(AMap, X);
  end;
  ANext := X;
  Result := True;
end;

function IfSets(AMap: TRdxCodeMap; const AIf, AStop: TRdxToken;
  const ALow: string; out ANext: TRdxToken; out ALine: Integer): Boolean;
  forward;

// Die Anweisungsliste ab AFrom bis vor AStop (AFrom folgt auf ihr begin):
// setzt sie den Parameter ALow, bevor sie ihn liest oder springt? rwE30
// Stufe 2: eine Zuweisung 'ALow := ..' am Anfang einer Anweisung auf
// oberster Ebene, davor kein Sprung (exit, raise ..) und keine Nennung;
// seit rwE31 Stufe 3 auch ein if, dessen then- UND else-Zweig ihn so setzt
// (IfSets; delphimvcframework MVCFramework.Utils.pas:62). True mit ADone
// (das Token hinter dem, was ihn setzt); sonst False mit ALine (die Zeile,
// an der es scheitert).
function SetsFirst(AMap: TRdxCodeMap; const AFrom, AStop: TRdxToken;
  const ALow: string; out ADone: TRdxToken; out ALine: Integer): Boolean;
var
  T, P, Opener : TRdxToken;
  Depth        : Integer;
  Start        : Boolean;
begin
  Result := False;
  ADone := Default(TRdxToken);
  ALine := AStop.Line;
  Depth := 1;
  Opener := Before(AMap, AFrom);
  P := Opener;
  T := AFrom;
  while (T.Low <> '') and TokBefore(T, AStop) do
  begin
    Start := (Depth = 1) and ((P.Low = ';') or SameTok(P, Opener));
    if IsKeywordAfter(T, P) then
    begin
      if InList(T.Low, BLOCK_OPENERS) then
        Inc(Depth)
      else if (T.Low = 'end') or (T.Low = 'until') then
        Dec(Depth);
    end;
    if JumpAt(T, P) then
    begin
      ALine := T.Line;
      Exit;
    end;
    if Start and (T.Low = 'if') and IsKeywordAfter(T, P)
       and IfSets(AMap, T, AStop, ALow, ADone, ALine) then
      Exit(True);
    if SameIdent(T.Low, ALow) and (P.Low <> '.') then
    begin
      if Start and (After(AMap, T).Low = ':=') then
        Exit(RhsClean(AMap, T, AStop, ALow, ADone, ALine));
      ALine := T.Line;
      Exit;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Ein Zweig hinter then bzw. else ab AFirst: ein Block 'begin .. end', der
// ALow zuerst setzt (SetsFirst), oder die eine Zuweisung 'ALow := ..'
// (RhsClean). True mit ANext (das Token hinter dem Zweig).
function BranchSets(AMap: TRdxCodeMap; const AFirst, AStop: TRdxToken;
  const ALow: string; out ANext: TRdxToken; out ALine: Integer): Boolean;
var
  E, L, Done : TRdxToken;
begin
  Result := False;
  ANext := Default(TRdxToken);
  ALine := AFirst.Line;
  if (AFirst.Low = 'begin')
     and IsKeywordAfter(AFirst, Before(AMap, AFirst)) then
  begin
    if (BlockEnd(AMap, AFirst, nil, E, L) <> '') or (E.Low = '')
       or not TokBefore(E, AStop)
       or not SetsFirst(AMap, After(AMap, AFirst), E, ALow, Done, ALine) then
      Exit;
    ANext := After(AMap, E);
    Exit(True);
  end;
  if SameIdent(AFirst.Low, ALow) and (After(AMap, AFirst).Low = ':=') then
    Result := RhsClean(AMap, AFirst, AStop, ALow, ANext, ALine);
end;

// 'if <Bedingung> then <Zweig> else <Zweig>' ab AIf: die Bedingung nennt
// ALow nicht (und traegt keine Struktur - anonyme Methode, bedingter
// Ausdruck), beide Zweige setzen ihn (BranchSets). True mit ANext (das
// Token hinter dem else-Zweig).
function IfSets(AMap: TRdxCodeMap; const AIf, AStop: TRdxToken;
  const ALow: string; out ANext: TRdxToken; out ALine: Integer): Boolean;
var
  T, P  : TRdxToken;
  Paren : Integer;
begin
  Result := False;
  ANext := Default(TRdxToken);
  ALine := AIf.Line;
  Paren := 0;
  P := AIf;
  T := After(AMap, AIf);
  while (T.Low <> '') and TokBefore(T, AStop) do
  begin
    if (T.Low = '(') or (T.Low = '[') then
      Inc(Paren)
    else if ((T.Low = ')') or (T.Low = ']')) and (Paren > 0) then
      Dec(Paren)
    else if IsKeywordAfter(T, P) and (Paren = 0) and (T.Low = 'then') then
      Break;
    if (SameIdent(T.Low, ALow) and (P.Low <> '.'))
       or (IsKeywordAfter(T, P) and InList(T.Low, NOT_IN_CONDITION)) then
    begin
      ALine := T.Line;
      Exit;
    end;
    P := T;
    T := After(AMap, T);
  end;
  if T.Low <> 'then' then Exit;
  if not BranchSets(AMap, After(AMap, T), AStop, ALow, T, ALine) then Exit;
  if (T.Low <> 'else') or not IsKeywordAfter(T, Before(AMap, T)) then
  begin
    ALine := AIf.Line;
    Exit;
  end;
  Result := BranchSets(AMap, After(AMap, T), AStop, ALow, ANext, ALine);
end;

// Wo im Rumpf von R wird der Parameter ALow zuerst genannt - setzt der
// Rumpf ihn, bevor er ihn liest oder springt (SetsFirst)? Eine Direktive
// davor ({$IFDEF} um die Zuweisung, rwE31 Stufe 3: jcl
// JclStringConversions.pas:407 - im anderen Zweig nur raise) laesst einen
// Weg offen. '' oder der Grund mit der Zeile der Stelle, an der es
// scheitert.
function FirstAssignReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const ALow, AName, AType, ARoutine: string): string;
var
  T, Done : TRdxToken;
  Li      : Integer;
begin
  // Vor dem Rumpf (lokale Routinen, Deklarationsteil) sperrt jede Nennung.
  T := After(AMap, R.HeaderEnd);
  while (T.Low <> '') and TokBefore(T, R.Body) do
  begin
    if SameIdent(T.Low, ALow) and (Before(AMap, T).Low <> '.') then
      Exit(_(R_OUT_NOT_FIRST, [AName, AType, ARoutine, T.Line]));
    T := After(AMap, T);
  end;
  if not SetsFirst(AMap, After(AMap, R.Body), R.EndTok, ALow, Done, Li) then
    Exit(_(R_OUT_NOT_FIRST, [AName, AType, ARoutine, Li]));
  if Done.Low = '' then
    Done := R.EndTok;
  if DirectiveBetween(AMap, R.Body, Done.Line, Done.Col) then
    Exit(_(R_OUT_NOT_FIRST, [AName, AType, ARoutine, Done.Line]));
  Result := '';
end;

// Das erste Glied der Liste AList ('A, B' -> 'A'), AList ohne es ('B').
function NextListItem(var AList: string): string;
var
  Comma : Integer;
begin
  Comma := Pos(',', AList);
  if Comma = 0 then
    Comma := Length(AList) + 1;
  Result := Copy(AList, 1, Comma - 1);
  Delete(AList, 1, Comma);
end;

// Verwaltete Typen (Changes): out gibt den Wert des Aufrufers beim Aufruf
// frei, var nicht. Gleich bleibt das nur, wenn der Rumpf den Parameter als
// erste Anweisung auf oberster Ebene setzt - ohne Sprung (Exit, raise ..)
// und ohne Lesen davor; sonst bleibt mit var auf einem Weg der alte Wert
// stehen, wo out ihn leerte (rwE30 Stufe 2: mORMot mormot.lib.win7zip.pas:
// 1070 'GetPropUtf8(.. out dest: RawUtf8)' setzt dest nur bedingt, die
// Aufrufer reichen 'result' durch; ColorPreview.Parser.pas:341). Je Name
// aus ANames ('a,b'). '' oder der Hinweis (R_OUT_NOT_FIRST) - auch ohne
// lesbaren begin-Rumpf (asm). Der Hinweis nennt die Namen wie im Text
// (ADisplay, ParamNames: 'A, B' - bis Fix-Runde 4 nach rwE32 klein:
// 'apropitem') und den Typ ATypeText.
function AssignedFirstReason(AMap: TRdxCodeMap; const AImpl: TRdxOutHead;
  const ANames, ADisplay, ATypeText, AName: string): string;
var
  R           : TRdxRoutine;
  Rest, Shown : string;
  Comma       : Integer;
begin
  if (TRdxBlocks.ReadRoutine(AMap, AImpl.Kw, R) <> '')
     or (R.Body.Low <> 'begin') then
    Exit(_(R_OUT_NOT_FIRST, [ADisplay, ATypeText, AName, AImpl.Kw.Line]));
  Result := '';
  Rest := ANames;
  Shown := ADisplay;
  while (Result = '') and (Rest <> '') do
  begin
    Comma := Pos(',', Rest);
    if Comma = 0 then
      Comma := Length(Rest) + 1;
    Result := FirstAssignReason(AMap, R, Copy(Rest, 1, Comma - 1),
      Trim(NextListItem(Shown)), ATypeText, AName);
    Delete(Rest, 1, Comma);
  end;
end;

// Die Namen hinter AOut bis zum ':' wie im Text, mit ', ' verbunden ('out
// Header, Payload: T' -> 'Header, Payload'): der Menuetext nennt jeden
// Parameter, den die Ersetzung trifft (rwE30 Stufe 2, Fragwuerdig:
// MVCFramework.JWT.pas:698, IndyDirectSingleFlushTestU.pas:260 - bis dahin
// nur der erste).
function ParamNames(AMap: TRdxCodeMap; const AOut: TRdxToken): string;
var
  T : TRdxToken;
begin
  T := After(AMap, AOut);
  Result := TokText(AMap, T);
  T := After(AMap, T);
  while T.Low = ',' do
  begin
    T := After(AMap, T);
    if not T.IsWord then Break;
    Result := Result + ', ' + TokText(AMap, T);
    T := After(AMap, T);
  end;
end;

// Der Typ hinter dem ':' der Parameter ab AOut wie im Text (ReadParam
// liest ihn klein ohne Trenner): Woerter mit einem Leerzeichen getrennt,
// sonst ohne ('array of Byte', 'System.UnicodeString', 'TArray<Integer>').
function ParamTypeText(AMap: TRdxCodeMap; const AOut: TRdxToken): string;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := '';
  T := After(AMap, AOut);
  while (T.Low <> '') and (T.Low <> ':') and (T.Low <> ';')
     and (T.Low <> ')') do
    T := After(AMap, T);
  if T.Low <> ':' then
    Exit;
  Depth := 0;
  P := T;
  T := After(AMap, T);
  while T.Low <> '' do
  begin
    if (T.Low = '(') or (T.Low = '[') or (T.Low = '<') then
      Inc(Depth)
    else if (T.Low = ')') or (T.Low = ']') or (T.Low = '>') then
    begin
      if Depth = 0 then
        Break;
      Dec(Depth);
    end
    else if (Depth = 0) and ((T.Low = ';') or (T.Low = '=')) then
      Break;
    if (Result <> '') and T.IsWord and P.IsWord then
      Result := Result + ' ';
    Result := Result + TokText(AMap, T);
    P := T;
    T := After(AMap, T);
  end;
end;

// Ist der Kopf ab AKw eine lokale Routine - steht er im Deklarationsteil
// einer Routine (zwischen ihrem Kopf und ihrem begin)? Dann AOuter. Von AKw
// rueckwaerts ueber die Koepfe (TRdxBlocks.HeadBefore) bis zum Abschnitt der
// Unit, hoechstens MAX_OUTER_STEPS Koepfe (sonst: nicht lokal - die Sperren
// fuer die ganze Datei bleiben).
function OuterOf(AMap: TRdxCodeMap; const AKw: TRdxToken;
  out AOuter: TRdxRoutine): Boolean;
var
  T, Head : TRdxToken;
  Step    : TRdxHeadStep;
  n       : Integer;
begin
  Result := False;
  AOuter := Default(TRdxRoutine);
  Head := HeadStart(AMap, AKw);
  T := Head;
  n := 0;
  while (n < MAX_OUTER_STEPS)
     and TRdxBlocks.HeadBefore(AMap, T, UNIT_BOUNDS, Step) do
  begin
    Inc(n);
    if Step.Stop then Exit;
    if (Step.Reason = '') and (Step.Routine.Body.Low <> '')
       and TokBefore(Step.Routine.Head, Head)
       and TokBefore(Head, Step.Routine.Body) then
    begin
      AOuter := Step.Routine;
      Exit(True);
    end;
  end;
end;

{ ---- rwE31 Stufe 3: Typen der Datei, Overloads freier Routinen ---- }

function LocalPlainType(AMap: TRdxCodeMap; const ATypeLow: string;
  ADepth: Integer): Boolean; forward;

// Ist der Typ ATypeLow (ein Wort, klein) einfach - kein verwalteter Typ
// (PLAIN_TYPES) oder ein einfacher Typ der Datei (LocalPlainType)?
function PlainTypeName(AMap: TRdxCodeMap; const ATypeLow: string;
  ADepth: Integer): Boolean;
begin
  Result := not TRdxAvoidOutFix.IsManagedType(ATypeLow)
    or LocalPlainType(AMap, ATypeLow, ADepth + 1);
end;

// Ab dem Kopfwort AKw einer Methode bzw. Property (MEMBER_HEADS) bis
// hinter das ';' auf Klammertiefe 0 und die Direktiven dahinter
// (MEMBER_DIRECTIVES, nicht als Feld 'static: T'): das Token danach. Low =
// '' bei einem Schluesselwort, das dort nicht steht (begin, end, record,
// case - unlesbar).
function SkipMember(AMap: TRdxCodeMap; const AKw: TRdxToken): TRdxToken;
var
  T, N  : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := After(AMap, AKw);
  while T.Low <> '' do
  begin
    if (T.Low = '(') or (T.Low = '[') then
      Inc(Depth)
    else if ((T.Low = ')') or (T.Low = ']')) and (Depth > 0) then
      Dec(Depth)
    else if (Depth = 0) and InList(T.Low, ['begin', 'end', 'record',
       'case']) then
      Exit
    else if (Depth = 0) and (T.Low = ';') then
    begin
      T := After(AMap, T);
      N := After(AMap, T);
      if not InList(T.Low, MEMBER_DIRECTIVES) or (N.Low = ':')
         or (N.Low = ',') then
        Exit(T);
    end;
    T := After(AMap, T);
  end;
end;

// Der Rumpf 'record .. end' bzw. 'object .. end' ab ARecord: nur Felder
// 'A, B: T;' einfacher Typen (PlainTypeName), auch statische Arrays
// 'array[..] of T'; seit rwE32 Stufe 4 (mORMot mormot.crypt.secure.pas:597
// TSynHasher) auch Abschnitte (private, public ..), Methoden und
// Properties (SkipMember) - sie tragen keine Daten. Kein Variantenteil,
// kein 'class var'/'class operator' (ein Initialize/Finalize macht den
// Record verwaltet), kein var/const/type im Rumpf, kein Vorfahr
// 'object(TBase)' (dann False: unbekannt).
function PlainRecordBody(AMap: TRdxCodeMap; const ARecord: TRdxToken;
  ADepth: Integer): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := After(AMap, ARecord);
  while T.Low <> '' do
  begin
    if T.Low = 'end' then
      Exit(True);
    if InList(T.Low, RECORD_SECTIONS) then
    begin
      T := After(AMap, T);
      Continue;
    end;
    if T.Low = 'class' then
    begin
      T := After(AMap, T);
      if not InList(T.Low, MEMBER_HEADS) then Exit;   // class var, operator
    end;
    if InList(T.Low, MEMBER_HEADS) then
    begin
      T := SkipMember(AMap, T);
      if T.Low = '' then Exit;
      Continue;
    end;
    while T.IsWord do
    begin
      T := After(AMap, T);
      if T.Low <> ',' then
        Break;
      T := After(AMap, T);
    end;
    if T.Low <> ':' then Exit;
    T := After(AMap, T);
    if T.Low = 'array' then
    begin
      T := After(AMap, T);
      if T.Low <> '[' then Exit;
      T := AfterClose(AMap, T);
      if T.Low <> 'of' then Exit;
      T := After(AMap, T);
    end;
    if not T.IsWord or not PlainTypeName(AMap, T.Low, ADepth) then Exit;
    T := After(AMap, T);
    if T.Low = 'end' then
      Exit(True);
    if T.Low <> ';' then Exit;
    T := After(AMap, T);
  end;
end;

// rwE31 Stufe 3 (mORMot test.core.data.pas:1332 'out Range: TRange' mit
// 'TRange = record Min, Max: Integer; end;' in derselben Unit): ist
// ATypeLow ein Typ, den die Datei genau einmal als 'Name = ..' hinter type
// bzw. ';' deklariert, und einfach - Aufzaehlung '(..)', Menge, Zeiger '^',
// ein Record nur aus einfachen Feldern (PlainRecordBody) oder ein anderer
// Name fuer einen einfachen Typ? Dann sind out und var gleich. Sonst (auch
// bei mehr als einer Deklaration, $IFDEF-Zwilling) False - unbekannt.
function LocalPlainType(AMap: TRdxCodeMap; const ATypeLow: string;
  ADepth: Integer): Boolean;
var
  T, N, Decl : TRdxToken;
  Count      : Integer;
begin
  Result := False;
  if (ADepth > MAX_TYPE_DEPTH) or (ATypeLow = '')
     or not IsIdentStart(ATypeLow[1]) or (Pos('.', ATypeLow) > 0)
     or (Pos('<', ATypeLow) > 0) then
    Exit;
  Count := 0;
  Decl := Default(TRdxToken);
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ATypeLow);
  while T.Low <> '' do
  begin
    if (T.Low = ATypeLow) and (After(AMap, T).Low = '=')
       and InList(Before(AMap, T).Low, TYPE_DECL_PREV) then
    begin
      Inc(Count);
      Decl := After(AMap, After(AMap, T));
    end;
    T := NextTokenOnLineWith(AMap, T, ATypeLow);
  end;
  if Count <> 1 then Exit;
  if Decl.Low = 'type' then
    Decl := After(AMap, Decl);
  if Decl.Low = 'packed' then
    Decl := After(AMap, Decl);
  if (Decl.Low = '(') or (Decl.Low = '^') or (Decl.Low = 'set') then
    Exit(True);
  if (Decl.Low = 'record') or (Decl.Low = 'object') then
  begin
    // Der Kopf doppelt in zwei Zweigen ('{$ifdef X} TFoo = record {$else}
    // TFoo = object {$endif}', mORMot; rwE32 Stufe 4,
    // mormot.crypt.secure.pas:590/592): der zweite zaehlte nicht (davor
    // steht 'record', nicht ';'), sein Rumpf ist der beider.
    N := After(AMap, Decl);
    if (N.Low = ATypeLow) and (After(AMap, N).Low = '=')
       and DirectiveBetween(AMap, Decl, N.Line, N.Col) then
    begin
      Decl := After(AMap, After(AMap, N));
      if Decl.Low = 'packed' then
        Decl := After(AMap, Decl);
      if (Decl.Low <> 'record') and (Decl.Low <> 'object') then
        Exit;
    end;
    Exit(PlainRecordBody(AMap, Decl, ADepth));
  end;
  N := After(AMap, Decl);
  Result := Decl.IsWord and (N.Low = ';')
    and PlainTypeName(AMap, Decl.Low, ADepth);
end;

// Die Zahl der Parameter im Kopf AHead ('(var A, B: T; C: U)' -> 3); 0
// ohne Liste, -1, wenn die Liste nicht zu lesen ist.
function ParamCount(AMap: TRdxCodeMap; const AHead: TRdxOutHead): Integer;
var
  T, Close : TRdxToken;
  Depth    : Integer;
  Typed    : Boolean;
begin
  T := After(AMap, AHead.Name);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low <> '(' then
    Exit(0);
  Close := MatchClose(AMap, T);
  if Close.Low = '' then
    Exit(-1);
  T := After(AMap, T);
  if SameTok(T, Close) then
    Exit(0);
  Result := 1;
  Depth := 0;
  Typed := False;
  while (T.Low <> '') and TokBefore(T, Close) do
  begin
    if (T.Low = '(') or (T.Low = '[') or (Typed and (T.Low = '<')) then
      Inc(Depth)
    else if ((T.Low = ')') or (T.Low = ']') or (Typed and (T.Low = '>')))
       and (Depth > 0) then
      Dec(Depth)
    else if Depth = 0 then
    begin
      if T.Low = ':' then
        Typed := True
      else if T.Low = ';' then
      begin
        Inc(Result);
        Typed := False;
      end
      else if (T.Low = ',') and not Typed then
        Inc(Result);
    end;
    T := After(AMap, T);
  end;
end;

// rwE31 Stufe 3 (jcl JclStringConversions.pas:407, vier lokale Overloads
// 'FlagInvalidSequence'): traegt die freie Routine AOwn 'overload', bleiben
// von AHeads die Koepfe mit ihrer Zahl von Parametern (ParamCount) - dann
// True, wenn andere wegfielen. Ein Overload mit derselben Zahl laesst
// AHeads ganz (PairOf sperrt: mehrdeutig); nur andere Zahlen machen die
// Umstellung sicher - kein Kopf wird einem anderen gleich.
function SameCountHeads(AMap: TRdxCodeMap; const AOwn: TRdxOutHead;
  var AHeads: TRdxOutHeads): Boolean;
var
  R     : TRdxRoutine;
  W     : string;
  n, k  : Integer;
  Group : TRdxOutHeads;
begin
  Result := False;
  if AOwn.Qual or (Length(AHeads) < 2)
     or (TRdxBlocks.ReadRoutine(AMap, AOwn.Kw, R) <> '')
     or not HasDirective(R, [DIR_OVERLOAD], W) then
    Exit;
  n := ParamCount(AMap, AOwn);
  if n < 0 then Exit;
  Group := nil;
  for k := 0 to High(AHeads) do
  begin
    if AHeads[k].Qual then Exit;
    if ParamCount(AMap, AHeads[k]) = n then
    begin
      SetLength(Group, Length(Group) + 1);
      Group[High(Group)] := AHeads[k];
    end;
  end;
  if Length(Group) < Length(AHeads) then
  begin
    AHeads := Group;
    Result := True;
  end;
end;

// Traegt einer der Koepfe AHeads keine Parameter (ParamCount = 0)?
function HasParamlessHead(AMap: TRdxCodeMap;
  const AHeads: TRdxOutHeads): Boolean;
var
  H : TRdxOutHead;
begin
  Result := False;
  for H in AHeads do
    if ParamCount(AMap, H) = 0 then
      Exit(True);
end;

class function TRdxAvoidOutFix.OutToVar(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxOutPlan;
  out AReason: string): Boolean;
var
  Col, UseLine   : Integer;
  OutTok, Open   : TRdxToken;
  DeclOut, Found : TRdxToken;
  Names, Typ     : string;
  Name           : string;
  Own, Decl, Impl : TRdxOutHead;
  Heads          : TRdxOutHeads;
  HasDecl        : Boolean;
  Outer          : TRdxRoutine;
  OverloadOk     : Boolean;
begin
  Result := False;
  APlan := Default(TRdxOutPlan);
  Col := ColumnFromMessage(AMessage);
  if Col <= 0 then
  begin
    AReason := MsgNoColumn;
    Exit;
  end;
  AReason := OutAt(AMap, ALine, Col, OutTok);
  if AReason <> '' then
    Exit;
  if not ReadParam(AMap, OutTok, Names, Typ) then
  begin
    AReason := _(R_OUT_UNTYPED);
    Exit;
  end;
  APlan.Name := ParamNames(AMap, OutTok);
  // Ein Record, eine Aufzaehlung ... der Datei kann einfach sein (rwE31
  // Stufe 3, LocalPlainType).
  APlan.Changes := IsManagedType(Typ) and not LocalPlainType(AMap, Typ, 0);
  Open := ListOpen(AMap, OutTok);
  if Open.Low = '' then
  begin
    AReason := MsgMovedSuffix(_(R_OUT_MOVED));
    Exit;
  end;
  if not HeadOfList(AMap, Open, Own) then
  begin
    AReason := _(R_OUT_NOT_ROUTINE);
    Exit;
  end;
  if Own.Kw.Low = 'operator' then
  begin
    AReason := _(R_OUT_OPERATOR);
    Exit;
  end;
  Name := TokText(AMap, Own.Name);
  // Gebrauch ohne Aufruf, dann das Paar der Koepfe (der gemeldete ist einer
  // davon).
  Heads := HeadsNamed(AMap, Own.Name.Low, Default(TRdxToken),
    Default(TRdxToken), UseLine);
  // Eine lokale Routine sieht nur ihre umschliessende Routine - dort zaehlen
  // Koepfe, Gebrauch und Includes (rwE30 Stufe 2: skia4delphi
  // FMX.Skia.Canvas.pas:636/767/1470 drei lokale 'TryGetVMT' in drei
  // Routinen; jvcl JvLinkLabelTextHandler.pas:455 'GetWidth'). Gefragt nur,
  // wenn die ganze Datei sperrte - HeadBefore liest Routine fuer Routine.
  Outer := Default(TRdxRoutine);
  if not Own.Qual and ((Length(Heads) > 1) or (UseLine > 0)
     or (Length(IncludesUpTo(AMap, AMap.LineCount)) > 0))
     and OuterOf(AMap, Own.Kw, Outer) then
    Heads := HeadsNamed(AMap, Own.Name.Low, Outer.Head, Outer.Last, UseLine);
  // Overloads einer freien Routine: nur die mit ihrer Zahl von Parametern
  // (SameCountHeads, rwE31 Stufe 3).
  OverloadOk := SameCountHeads(AMap, Own, Heads);
  // Der Name ohne Klammern kann der Aufruf einer Ueberladung ohne
  // Parameter sein (rwE32 Stufe 4: jvcl dpp_PascalParser.pas:80/417 'p :=
  // GetToken;' ruft 'function GetToken: PTokenInfo; overload;') - dann
  // nennt der Grund, was das Paar sperrt (Overload, Sichtbarkeit ...).
  // Sperrt das Paar nicht, bleibt R_OUT_REFERENCE: ein Methodenzeiger auf
  // die gemeldete Ueberladung ist nicht ausgeschlossen.
  AReason := '';
  if (UseLine = 0) or HasParamlessHead(AMap, Heads) then
    AReason := PairOf(AMap, Heads, Name, Outer, OverloadOk, Decl, Impl,
      HasDecl);
  if (AReason = '') and (UseLine > 0) then
    AReason := _(R_OUT_REFERENCE, [Name, UseLine]);
  if AReason <> '' then
    Exit;
  DeclOut := Default(TRdxToken);
  if HasDecl then
  begin
    AReason := OutOfHead(AMap, Decl, Own, OutTok, Names, Name, APlan.Name,
      False, DeclOut);
    if AReason <> '' then
      Exit;
  end;
  AReason := OutOfHead(AMap, Impl, Own, OutTok, Names, Name, APlan.Name,
    True, Found);
  if AReason <> '' then
    Exit;
  // Verwaltet und nicht zuerst gesetzt: die Hilfe gilt (gekennzeichnet),
  // aber nur im Menue - wie weit der alte Wert reicht, entscheiden die
  // Aufrufer (rwE30 Stufe 2: mormot.lib.win7zip.pas:1070 reicht 'result'
  // durch; Fragwuerdig ColorPreview.Parser.pas:341, MVCFramework.JWT.pas:
  // 698 - verhaltensaendernd und in der Gluehbirne).
  if APlan.Changes then
  begin
    APlan.Caution := AssignedFirstReason(AMap, Impl, Names, APlan.Name,
      ParamTypeText(AMap, OutTok), Name);
    APlan.MenuOnly := APlan.Caution <> '';
  end;
  if HasDecl then
    AddEdit(APlan.Edits, OutEdit(AMap, DeclOut));
  if Found.Low <> '' then
    AddEdit(APlan.Edits, OutEdit(AMap, Found));
  Result := True;
end;

end.
