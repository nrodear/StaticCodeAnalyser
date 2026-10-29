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
// (PLAIN_TYPES), zaehlt als verwaltet.
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
//     umschliessende Routine (rwE30 Stufe 2),
//   * der Name steht im Code ohne Aufruf ('@Bar', 'OnX := Bar') - als
//     Methodenzeiger aendert sich sein Typ,
//   * die Methode ist virtual/dynamic/abstract/override/final, message,
//     dispid oder overload bzw. hat eine Aufrufkonvention oder external,
//   * sie steht unter published oder ohne Sichtbarkeit (eine Formdatei kann
//     sie an ein Ereignis binden), ihre Klasse implementiert ein Interface
//     aus einer anderen Unit oder eine Wurzel mit diesem Member (sie
//     koennte eine Interface-Methode sein; Interfaces dieser Datei ohne den
//     Namen sperren seit rwE30 Stufe 2 nicht), oder ihre Deklaration steht
//     nicht direkt in der Klasse,
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
  // Menue.
  R_OUT_NOT_FIRST = 'not in the light bulb - %s has a managed type and is '
    + 'not set as the first statement of %s (line %d): with "var" the '
    + 'caller''s old value can stay where "out" cleared it';
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

// Alle Koepfe mit dem Namen ALow; AUseLine: die erste Zeile, auf der der
// Name im Code ohne Aufruf steht ('@Bar', 'OnX := Bar'), 0 ohne. Nur
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
      else if (AUseLine = 0) and (After(AMap, T).Low <> '(') then
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
// Grund.
function DirectiveReason(const R: TRdxRoutine; const AName: string): string;
var
  W : string;
begin
  Result := '';
  if HasDirective(R, BOUND_DIRECTIVES, W) then
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
begin
  Result := ImplReason(AMap, AImpl, AName, IR);
  if Result <> '' then
    Exit;
  if Length(IR.Parts) < 2 then
    Exit(_(R_OUT_HEAD_UNSAFE, [AName]));
  ClassLow := IR.Parts[High(IR.Parts) - 1];
  Disp := Copy(IR.Name, 1, LastDelimiter('.', IR.Name) - 1);
  Disp := LastPart(Disp);
  if not EnclosingClass(AMap, HeadStart(AMap, ADecl.Kw), ClassLow, CH) then
    Exit(_(R_OUT_NOT_IN_CLASS, [AName, Disp]));
  if InList(CH.Vis, STREAMED_VIS) then
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
  if TRdxRoutineFixes.InterfaceMemberReason(AMap, CH.ClassTok,
       LowerCase(AName)) <> '' then
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
  const AName: string; const AOuter: TRdxRoutine): string;
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
  Result := DirectiveReason(IR, AName);
end;

// Routine: ADecl forward, AImpl mit Rumpf. Im interface-Teil (nicht in
// einem Typ) ist sie exportiert und gesperrt (R_OUT_INTERFACE, rwE29). ''
// oder der Grund.
function RoutineReason(AMap: TRdxCodeMap; const ADecl, AImpl: TRdxOutHead;
  const AName: string): string;
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
  Result := DirectiveReason(DR, AName);
  if Result = '' then
    Result := DirectiveReason(IR, AName);
end;

// Deklaration und Implementierung aus den Koepfen AHeads: '' mit dem Paar
// (AHasDecl = False: nur die Implementierung), sonst der Grund.
function PairOf(AMap: TRdxCodeMap; const AHeads: TRdxOutHeads;
  const AName: string; const AOuter: TRdxRoutine; out ADecl,
  AImpl: TRdxOutHead; out AHasDecl: Boolean): string;
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
    Result := SingleReason(AMap, AImpl, AName, AOuter);
  end
  else if (Length(Q) = 0) and (Length(U) = 2) then
  begin
    ADecl := U[0];
    AImpl := U[1];
    AHasDecl := True;
    Result := RoutineReason(AMap, ADecl, AImpl, AName);
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

// Wo im Rumpf von R wird der Parameter ALow zuerst genannt - als
// Zuweisung 'ALow := ..' auf oberster Ebene, ohne Sprung davor? '' oder der
// Grund mit der Zeile der Stelle, an der es scheitert.
function FirstAssignReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const ALow, AName, ARoutine: string): string;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  // Vor dem Rumpf (lokale Routinen, Deklarationsteil) sperrt jede Nennung.
  T := After(AMap, R.HeaderEnd);
  while (T.Low <> '') and TokBefore(T, R.Body) do
  begin
    if SameIdent(T.Low, ALow) and (Before(AMap, T).Low <> '.') then
      Exit(_(R_OUT_NOT_FIRST, [AName, ARoutine, T.Line]));
    T := After(AMap, T);
  end;
  Depth := 1;
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and TokBefore(T, R.EndTok) do
  begin
    if IsKeywordAfter(T, P) then
    begin
      if InList(T.Low, BLOCK_OPENERS) then
        Inc(Depth)
      else if (T.Low = 'end') or (T.Low = 'until') then
        Dec(Depth);
    end;
    if JumpAt(T, P) then
      Exit(_(R_OUT_NOT_FIRST, [AName, ARoutine, T.Line]));
    if SameIdent(T.Low, ALow) and (P.Low <> '.') then
    begin
      if (Depth = 1) and ((P.Low = ';') or SameTok(P, R.Body))
         and (After(AMap, T).Low = ':=') then
      begin
        // Die rechte Seite darf ihn nicht lesen ('S := S + ..').
        P := T;
        T := After(AMap, After(AMap, T));
        while (T.Low <> '') and (T.Low <> ';') and TokBefore(T, R.EndTok) do
        begin
          if SameIdent(T.Low, ALow) and (P.Low <> '.') then
            Exit(_(R_OUT_NOT_FIRST, [AName, ARoutine, T.Line]));
          P := T;
          T := After(AMap, T);
        end;
        Exit('');
      end;
      Exit(_(R_OUT_NOT_FIRST, [AName, ARoutine, T.Line]));
    end;
    P := T;
    T := After(AMap, T);
  end;
  Result := _(R_OUT_NOT_FIRST, [AName, ARoutine, R.EndTok.Line]);
end;

// Verwaltete Typen (Changes): out gibt den Wert des Aufrufers beim Aufruf
// frei, var nicht. Gleich bleibt das nur, wenn der Rumpf den Parameter als
// erste Anweisung auf oberster Ebene setzt - ohne Sprung (Exit, raise ..)
// und ohne Lesen davor; sonst bleibt mit var auf einem Weg der alte Wert
// stehen, wo out ihn leerte (rwE30 Stufe 2: mORMot mormot.lib.win7zip.pas:
// 1070 'GetPropUtf8(.. out dest: RawUtf8)' setzt dest nur bedingt, die
// Aufrufer reichen 'result' durch; ColorPreview.Parser.pas:341). Je Name
// aus ANames ('a,b'). '' oder der Hinweis (R_OUT_NOT_FIRST) - auch ohne
// lesbaren begin-Rumpf (asm).
function AssignedFirstReason(AMap: TRdxCodeMap; const AImpl: TRdxOutHead;
  const ANames, AName: string): string;
var
  R     : TRdxRoutine;
  Rest  : string;
  Comma : Integer;
begin
  if (TRdxBlocks.ReadRoutine(AMap, AImpl.Kw, R) <> '')
     or (R.Body.Low <> 'begin') then
    Exit(_(R_OUT_NOT_FIRST, [ANames, AName, AImpl.Kw.Line]));
  Result := '';
  Rest := ANames;
  while (Result = '') and (Rest <> '') do
  begin
    Comma := Pos(',', Rest);
    if Comma = 0 then
      Comma := Length(Rest) + 1;
    Result := FirstAssignReason(AMap, R, Copy(Rest, 1, Comma - 1),
      Copy(Rest, 1, Comma - 1), AName);
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
  APlan.Changes := IsManagedType(Typ);
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
  if UseLine > 0 then
    AReason := _(R_OUT_REFERENCE, [Name, UseLine])
  else
    AReason := PairOf(AMap, Heads, Name, Outer, Decl, Impl, HasDecl);
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
    APlan.Caution := AssignedFirstReason(AMap, Impl, Names, Name);
    APlan.MenuOnly := APlan.Caution <> '';
  end;
  if HasDecl then
    AddEdit(APlan.Edits, OutEdit(AMap, DeclOut));
  if Found.Low <> '' then
    AddEdit(APlan.Edits, OutEdit(AMap, Found));
  Result := True;
end;

end.
