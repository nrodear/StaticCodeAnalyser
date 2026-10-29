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
//     koennte) - Overload, gleichnamige Methoden anderer Klassen,
//     Deklaration oder Implementierung fehlt,
//   * der Name steht im Code ohne Aufruf ('@Bar', 'OnX := Bar') - als
//     Methodenzeiger aendert sich sein Typ,
//   * die Methode ist virtual/dynamic/abstract/override/final, message,
//     dispid oder overload bzw. hat eine Aufrufkonvention oder external,
//   * sie steht unter published oder ohne Sichtbarkeit (eine Formdatei kann
//     sie an ein Ereignis binden), ihre Klasse implementiert Interfaces
//     (sie koennte eine Interface-Methode sein), oder ihre Deklaration
//     steht nicht direkt in der Klasse,
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
  R_OUT_VISIBLE = 'the method is visible outside the unit (not private, '
    + 'class in the interface section) - other units can use it as a method '
    + 'pointer';

type
  // Ergebnis des Planers (uRdxFixTable: Plan-Form im Geruest TRdxFixFrame).
  //   Name     der Parameter (Menuetext) - schon gesetzt, wenn der Planer
  //            danach ablehnt
  //   Changes  verwalteter oder unbekannter Typ: aendert das Verhalten (E2)
  //   Edits    je Kopf das 'out' durch 'var', in der Reihenfolge der Datei
  TRdxOutPlan = record
    Name    : string;
    Changes : Boolean;
    Edits   : TArray<TRdxEdit>;
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
  uRdxBlocks;       // TRdxBlocks, HeadStart, HasDirective, EnclosingClass

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
// Name im Code ohne Aufruf steht ('@Bar', 'OnX := Bar'), 0 ohne.
function HeadsNamed(AMap: TRdxCodeMap; const ALow: string;
  out AUseLine: Integer): TRdxOutHeads;
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
    if T.Low = ALow then
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
  Heritage       : TArray<string>;
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
  Heritage := TRdxBlocks.HeritageOf(AMap, CH.ClassTok);
  if (Length(Heritage) > 1)
     or ((Length(Heritage) = 1) and LooksLikeInterfaceName(Heritage[0])) then
    Exit(_(R_OUT_INTERFACES, [Disp, AName]));
  if TRdxBlocks.MethodDecl(AMap, HeadStart(AMap, ADecl.Kw), DR) <> '' then
    Exit(_(R_OUT_HEAD_UNSAFE, [AName]));
  Result := DirectiveReason(DR, AName);
  if Result = '' then
    Result := DirectiveReason(IR, AName);
end;

// Routine ohne eigene Deklaration: nur AImpl mit Rumpf, keine Include-
// Datei. Steht der einzige Kopf in einem Typ, ist er die Methode eines
// interface-Typs (oder einer Klasse ohne Implementierung hier). '' oder der
// Grund.
function SingleReason(AMap: TRdxCodeMap; const AImpl: TRdxOutHead;
  const AName: string): string;
var
  IR : TRdxRoutine;
begin
  if InsideTypeBody(AMap, HeadStart(AMap, AImpl.Kw)) then
    Exit(_(R_OUT_IN_TYPE, [AName]));
  Result := ImplReason(AMap, AImpl, AName, IR);
  if Result <> '' then
    Exit;
  if Length(AllIncludes(AMap)) > 0 then
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
  const AName: string; out ADecl, AImpl: TRdxOutHead;
  out AHasDecl: Boolean): string;
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
    Result := SingleReason(AMap, AImpl, AName);
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
  APlan.Name := TokText(AMap, After(AMap, OutTok));
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
  Heads := HeadsNamed(AMap, Own.Name.Low, UseLine);
  if UseLine > 0 then
    AReason := _(R_OUT_REFERENCE, [Name, UseLine])
  else
    AReason := PairOf(AMap, Heads, Name, Decl, Impl, HasDecl);
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
  if HasDecl then
    AddEdit(APlan.Edits, OutEdit(AMap, DeclOut));
  if Found.Low <> '' then
    AddEdit(APlan.Edits, OutEdit(AMap, Found));
  Result := True;
end;

end.
