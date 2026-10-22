unit uRdxConstStringParameterFix;

// reDelphix - Editorhilfe SCA170 ConstStringParameter, OHNE ToolsAPI und
// ohne Parser (Konzept_Editorhilfen_Regelliste_2026-10-11, "bedingt"):
//   'function Hash(s: string): Integer;' -> 'function Hash(const s:
//   string): Integer;' in der Implementierung UND in jeder Deklaration
//   derselben Routine (forward, Klassenrumpf). Bei einer Gruppe 'A, B:
//   string' steht das const vor der Gruppe und gilt fuer beide Namen.
//
// BEDEUTUNGSGLEICH, wenn der Rumpf den Parameter nicht beschreibt (sonst
// uebersetzt es nicht mehr: E2064/E2197) und niemand die Routine als WERT
// benutzt (Methodenzeiger, Ereignis, Rueckruf, Property-Accessor - deren
// Typ passte danach nicht mehr). Darum nur unit-lokale Routinen: freie
// Routinen ohne Deklaration im interface-Teil, Methoden unter private bzw.
// strict private oder einer Klasse des implementation-Teils, ohne
// virtual/dynamic/override/abstract/reintroduce/message/dispid und ohne
// Interface an der Klasse (die Methode koennte ein Member sein, E2291).
// RESTRISIKO, das die Hilfe nicht sieht: aendert die Routine selbst die
// Variable, die der Aufrufer uebergibt (Feld, globale Variable), haengt
// ein const-Parameter am alten Text (kein Referenzzaehler) - der Hinweis
// der Tabelle nennt das.
//
// DER FUND: uConstStringParameter meldet auf der Zeile des Kopfworts der
// IMPLEMENTIERUNG, 'Parameter "S: string" should be declared as `const`
// ...' - der Typ ist einer von string, AnsiString, UnicodeString,
// WideString, RawByteString, ShortString. Er uebergeht Parameter mit
// const/var/out, Methoden mit virtual/override/dynamic/message/abstract/
// reintroduce (auch per Name) und Ereignishandler.
//
// SPERREN (lieber keine Hilfe als eine falsche) - zusaetzlich zu denen des
// Kopfs aus uRdxUnusedParameterFix.ReadSite (genau eine Implementierung auf
// der Zeile, lesbare Liste ohne Kommentar/Direktive/Attribut, kein asm,
// kein overload, Deklaration eindeutig und gleich benannt):
//   * die Gruppe traegt schon einen Modifizierer oder einen anderen Typ
//     als die Meldung (Zeile verschoben); eine Deklaration gruppiert anders.
//   * Deklaration im interface-Teil; Methode ausserhalb von private/strict
//     private einer Klasse des interface-Teils; Direktive s. oben;
//     Interface an der Klasse.
//   * Der Name der Routine steht in der Datei ohne Aufruf ('X(') oder mit
//     '@' davor (Wert, Ereignis, exports, Property-Accessor) - auch eine
//     gleichnamige fremde Methode sperrt (Textpruefung). Jedes {$I} in der
//     Datei (es kann die Routine als Wert nutzen).
//   * Ein Name der Gruppe wird im Bereich der Routine beschrieben: ':=',
//     'S[i] :=', '@S', oder als ganzes Argument an eine Routine gegeben,
//     die nicht als nur lesend bekannt ist (READ_ONLY_CALLS: Length, Copy,
//     Pos, Format, Add, Create ...) - ein var-/out-Parameter (Delete,
//     Insert, SetLength, ReadLn, eigene Routinen) ist am Text nicht zu
//     unterscheiden. Auch in lokalen Routinen und inaktiven Zweigen.
//
// OHNE ToolsAPI und ohne uEngineApi/uRdxFixRunner (Hausregel der Tabelle,
// uRdxFixTable): reine Textlogik, FPC-tauglich. Den Adapter fuer FIX_ROWS
// schreibt uRdxFixTable (Form TRdxPlannerOf<TRdxParamPlan>).

interface

uses
  uRdxCodeMap,              // TRdxCodeMap
  uRdxUnusedParameterFix;   // TRdxParamPlan, ReadSite

const
  // Gruende als englische msgids (die Tests pruefen sie mit _()).
  R_CS_NO_NAME = 'the message names no parameter and type';
  R_CS_MODIFIER = 'parameter "%s" already carries "%s"';
  R_CS_TYPE = 'parameter "%s" is not declared as %s';
  R_CS_GROUP = 'the declaration in line %d groups the parameter differently';
  R_CS_INTERFACE = 'the routine is declared in the interface section (line '
    + '%d) - other units can use it as a procedure value';
  R_CS_VISIBLE = 'the method is visible outside the unit (not private, class '
    + 'in the interface section) - other units can use it as a method pointer';
  R_CS_DISPATCH = 'directive %s - ancestors, descendants or the message '
    + 'dispatch share the signature';
  R_CS_IFACE = 'the class implements %s - the method can be one of its '
    + 'members';
  R_CS_INCLUDE = '{$I} include in line %d - it can use the routine as a value';
  R_CS_VALUE = '%s is used without a call in line %d (method pointer, event, '
    + 'callback, property) - its type would no longer match';
  R_CS_WRITTEN = 'parameter "%s" is written in line %d';
  R_CS_ADDRESS = 'the address of parameter "%s" is taken in line %d';
  R_CS_ARGUMENT = 'parameter "%s" is passed to %s in line %d - it can be a '
    + 'var or out parameter there';

type
  TRdxConstStringParameterFix = class
  public
    // SCA170: 'const' vor die Gruppe des Parameters der Meldung, in der
    // Implementierung und jeder Deklaration (s. Kopf). Form TRdxPlannerOf
    // (uRdxFixTable).
    class function MakeConst(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxParamPlan;
      out AReason: string): Boolean; static;
  end;

// Name und Typ aus 'Parameter "S: string" should be declared as `const`
// ...'; False ohne diese Form.
function ConstParamOf(const AMessage: string;
  out AName, AType: string): Boolean;

implementation

uses
  System.SysUtils,
  uRdxBufferMath,    // AddEdit
  uRdxBlocks,        // TRdxBlocks.HeritageOf, HasDirective
  uRdxText;          // _(), MsgMovedSuffix, MsgStaleSuffix (nie uLocalization)

const
  SPAN_170 = 'sca170';
  KEY_PARAM = 'Parameter "';
  KW_CONST = 'const ';
  // Die Typen, die der Detektor meldet.
  STRING_TYPES: array[0..5] of string = ('string', 'ansistring',
    'unicodestring', 'widestring', 'rawbytestring', 'shortstring');
  // Damit teilt die Methode ihre Signatur mit Vorfahren, Nachfahren oder
  // der Nachrichten-Verteilung.
  DISPATCH_DIRECTIVES: array[0..6] of string = ('virtual', 'dynamic',
    'override', 'abstract', 'reintroduce', 'message', 'dispid');
  PRIVATE_SECTIONS: array[0..1] of string = ('private', 'strict private');
  // Routinen der RTL bzw. Methoden, die ein string-Argument nur lesen (const
  // oder Wert) - ein ganzes Argument 'S' an sie sperrt nicht. Auch die
  // Typumwandlungen (PChar(S)); ':=' hinter der Klammer sperrt trotzdem.
  READ_ONLY_CALLS: array[0..70] of string = ('length', 'copy', 'pos',
    'posex', 'trim', 'trimleft', 'trimright', 'uppercase', 'lowercase',
    'ansiuppercase', 'ansilowercase', 'sametext', 'samestr', 'comparetext',
    'comparestr', 'ansisametext', 'ansicomparetext', 'ansicomparestr',
    'strtoint', 'strtointdef', 'strtoint64', 'strtoint64def', 'strtofloat',
    'strtofloatdef', 'strtobool', 'strtobooldef', 'trystrtoint',
    'trystrtoint64', 'trystrtofloat', 'trystrtobool', 'quotedstr',
    'ansiquotedstr', 'format', 'extractfilename', 'extractfilepath',
    'extractfiledir', 'extractfileext', 'changefileext', 'fileexists',
    'directoryexists', 'includetrailingpathdelimiter',
    'excludetrailingpathdelimiter', 'stringreplace', 'containstext',
    'containsstr', 'startstext', 'startsstr', 'endstext', 'endsstr',
    'leftstr', 'rightstr', 'midstr', 'ansipos', 'exit', 'write', 'writeln',
    'showmessage', 'create', 'add', 'indexof', 'assert', 'utf8encode',
    'pchar', 'pwidechar', 'pansichar', 'string', 'ansistring', 'utf8string',
    'unicodestring', 'widestring', 'rawbytestring');
  // Vor '(' kein Aufruf, sondern ein Ausdruck in Klammern.
  EXPR_WORDS: array[0..21] of string = ('if', 'then', 'else', 'and', 'or',
    'not', 'xor', 'div', 'mod', 'in', 'is', 'as', 'do', 'of', 'to', 'downto',
    'begin', 'until', 'while', 'repeat', 'shl', 'shr');
  // Vor '(' steht ein Ausdruck, dessen Wert gerufen wird (Prozedurvariable
  // aus Feld, Ergebnis, Zeiger, Typparameter).
  CALLED_EXPR: array[0..3] of string = (')', ']', '^', '>');
  MAX_BACK = 400;   // Token rueckwaerts bis zur Klammer eines Arguments

function ConstParamOf(const AMessage: string;
  out AName, AType: string): Boolean;
var
  Q : string;
  P : Integer;
begin
  AName := '';
  AType := '';
  Q := QuotedText(AMessage, '"');
  P := Pos(':', Q);
  if (Pos(KEY_PARAM, AMessage) = 1) and (P > 0) then
  begin
    AName := Trim(Copy(Q, 1, P - 1));
    AType := Trim(Copy(Q, P + 1, MaxInt));
  end;
  Result := (AName <> '') and (AType <> '');
end;

// 'IFoo' -> True, 'TBase' -> False: die Delphi-Konvention I +
// Grossbuchstabe (wie uRdxRoutineFixes.InterfaceStyle).
function InterfaceStyle(const S: string): Boolean;
begin
  Result := (Length(S) >= 2) and (S[1] = 'I') and CharInSet(S[2], ['A'..'Z']);
end;

// Die Gruppe der Implementierung: ohne Modifizierer, genau ein Typ-Token,
// der Typ der Meldung. '' oder der Grund.
function GroupReason(AMap: TRdxCodeMap; const ASite: TRdxParamSite;
  const AName, AType: string): string;
var
  G : TRdxParamGroup;
begin
  Result := '';
  G := ASite.List.Groups[ASite.Group];
  if G.Modifier.Low <> '' then
    Result := MsgStaleSuffix(_(R_CS_MODIFIER, [AName, TokText(AMap,
      G.Modifier)]))
  else if (G.TypeFirst.Low = '') or not SameTok(G.TypeFirst, G.TypeLast)
     or not InList(G.TypeFirst.Low, STRING_TYPES)
     or (G.TypeFirst.Low <> LowerCase(AType)) then
    Result := MsgMovedSuffix(_(R_CS_TYPE, [AName, AType]));
end;

// Gruppiert die Deklaration D genauso (gleiche Namen, kein Modifizierer,
// derselbe Typ)?
function SameGroup(const ASite: TRdxParamSite;
  const D: TRdxParamDecl): Boolean;
var
  A, B : TRdxParamGroup;
  i    : Integer;
begin
  A := ASite.List.Groups[ASite.Group];
  B := D.List.Groups[D.Group];
  Result := (Length(A.Names) = Length(B.Names)) and (B.Modifier.Low = '')
    and SameTok(B.TypeFirst, B.TypeLast)
    and (B.TypeFirst.Low = A.TypeFirst.Low);
  i := 0;
  while Result and (i < Length(A.Names)) do
  begin
    Result := SameIdent(A.Names[i].Low, B.Names[i].Low);
    Inc(i);
  end;
end;

// Directive aus DISPATCH_DIRECTIVES an Implementierung oder Deklaration?
// '' oder der Grund.
function DispatchReason(const ASite: TRdxParamSite): string;
var
  W : string;
  D : TRdxParamDecl;
begin
  Result := '';
  if HasDirective(ASite.Impl, DISPATCH_DIRECTIVES, W) then
    Exit(_(R_CS_DISPATCH, [W]));
  for D in ASite.Decls do
    if HasDirective(D.Head, DISPATCH_DIRECTIVES, W) then
      Exit(_(R_CS_DISPATCH, [W]));
end;

// Nur unit-lokal: keine Deklaration im interface-Teil; eine Methode unter
// private/strict private oder in einer Klasse des implementation-Teils,
// ohne Interface an der Klasse. '' oder der Grund.
function LocalReason(AMap: TRdxCodeMap; const ASite: TRdxParamSite): string;
var
  D       : TRdxParamDecl;
  Names   : TArray<string>;
  InImpl  : Boolean;
begin
  for D in ASite.Decls do
    if D.InInterface then
      Exit(_(R_CS_INTERFACE, [D.Head.Head.Line]));
  Result := DispatchReason(ASite);
  if (Result <> '') or not ASite.IsMethod then Exit;
  InImpl := (ASite.ImplWord.Low = '')
    or TokBefore(ASite.ImplWord, ASite.ClassHead.ClassTok);
  if not InImpl and not InList(ASite.ClassHead.Vis, PRIVATE_SECTIONS) then
    Exit(_(R_CS_VISIBLE));
  Names := TRdxBlocks.HeritageOf(AMap, ASite.ClassHead.ClassTok);
  if Length(Names) > 1 then
    Result := _(R_CS_IFACE, [Names[1]])
  else if (Length(Names) = 1) and InterfaceStyle(Names[0]) then
    Result := _(R_CS_IFACE, [Names[0]]);
end;

// Ist T der Name im Kopf der Implementierung oder einer Deklaration?
function IsHeadName(const ASite: TRdxParamSite; const T: TRdxToken): Boolean;
var
  D : TRdxParamDecl;
begin
  Result := SameTok(T, ASite.Impl.NameTok);
  for D in ASite.Decls do
    Result := Result or SameTok(T, D.Head.NameTok);
end;

// Jedes Vorkommen des Routinennamens ausser den Koepfen muss ein Aufruf
// 'X(' ohne '@' sein. '' oder der Grund.
function ValueReason(AMap: TRdxCodeMap; const ASite: TRdxParamSite): string;
var
  T       : TRdxToken;
  NameLow : string;
begin
  Result := '';
  NameLow := ASite.Impl.NameTok.Low;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if SameIdent(T.Low, NameLow) and not IsHeadName(ASite, T)
       and ((After(AMap, T).Low <> '(') or (Before(AMap, T).Low = '@')) then
      Exit(_(R_CS_VALUE, [TokText(AMap, T), T.Line]));
    T := After(AMap, T);
  end;
end;

// Die Klammer, in der das Argument T steht ('(' bzw. '['): rueckwaerts auf
// gleicher Tiefe, bis vor ein ';' oder MAX_BACK Token. Low = '' ohne.
function EnclosingOpen(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  B     : TRdxToken;
  Depth : Integer;
  n     : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  n := 0;
  B := Before(AMap, T);
  while (B.Low <> '') and (B.Low <> ';') and (n < MAX_BACK) do
  begin
    if (B.Low = ')') or (B.Low = ']') then
      Inc(Depth)
    else if (B.Low = '(') or (B.Low = '[') then
    begin
      if Depth = 0 then
        Exit(B);
      Dec(Depth);
    end;
    B := Before(AMap, B);
    Inc(n);
  end;
end;

// Das ganze Argument T (AName) einer Klammer: in '[..]' (Array-Konstruktor,
// Index) und in einem Ausdruck in Klammern frei; als Argument nur an eine
// Routine aus READ_ONLY_CALLS (ohne ':=' hinter der Klammer) oder an die
// Routine selbst (ARoutineLow). '' oder der Grund.
function ArgumentReason(AMap: TRdxCodeMap; const T: TRdxToken;
  const AName, ARoutineLow: string): string;
var
  Open, Callee : TRdxToken;
begin
  Result := '';
  Open := EnclosingOpen(AMap, T);
  if Open.Low = '[' then Exit;
  if Open.Low = '' then
    Exit(_(R_CS_ARGUMENT, [AName, '?', T.Line]));
  Callee := Before(AMap, Open);
  if Callee.IsWord and not InList(Callee.Low, EXPR_WORDS) then
  begin
    if (SameIdent(Callee.Low, ARoutineLow)
       or InList(Callee.Low, READ_ONLY_CALLS))
       and (After(AMap, MatchClose(AMap, Open)).Low <> ':=') then
      Exit;
    Exit(_(R_CS_ARGUMENT, [AName, TokText(AMap, Callee), T.Line]));
  end;
  if InList(Callee.Low, CALLED_EXPR) then
    Result := _(R_CS_ARGUMENT, [AName, Callee.Low, T.Line]);
end;

// Ein Vorkommen T des Parameters AName: beschrieben, Adresse oder ganzes
// Argument einer Routine, die schreiben kann? '' oder der Grund.
function UseReason(AMap: TRdxCodeMap; const T: TRdxToken;
  const AName, ARoutineLow: string): string;
var
  P, Last, N : TRdxToken;
begin
  Result := '';
  P := Before(AMap, T);
  if P.Low = '@' then
    Exit(_(R_CS_ADDRESS, [AName, T.Line]));
  N := After(AMap, T);
  while N.Low = '[' do
  begin
    Last := MatchClose(AMap, N);
    if Last.Low = '' then
      Exit(_(R_CS_WRITTEN, [AName, T.Line]));
    N := After(AMap, Last);
  end;
  // Zuweisung, auch als Laufvariable ('for S := ..', 'for S in ..').
  if (N.Low = ':=') or (P.Low = 'for') then
    Exit(_(R_CS_WRITTEN, [AName, T.Line]));
  if InList(P.Low, ['(', ',']) and InList(N.Low, [')', ',']) then
    Result := ArgumentReason(AMap, T, AName, ARoutineLow);
end;

// Wird ein Name der Gruppe im Bereich der Routine (hinter der Liste bis zum
// letzten ';', samt lokaler Routinen) beschrieben? 'X.S' ist ein Member,
// nicht der Parameter. '' oder der Grund.
function WriteReason(AMap: TRdxCodeMap; const ASite: TRdxParamSite): string;
var
  G       : TRdxParamGroup;
  N, T    : TRdxToken;
  Name    : string;
begin
  Result := '';
  G := ASite.List.Groups[ASite.Group];
  for N in G.Names do
  begin
    Name := TokText(AMap, N);
    T := After(AMap, ASite.List.Close);
    while (T.Low <> '') and not TokBefore(ASite.Impl.Last, T) do
    begin
      if SameIdent(T.Low, N.Low) and (Before(AMap, T).Low <> '.') then
      begin
        Result := UseReason(AMap, T, Name, ASite.Impl.NameTok.Low);
        if Result <> '' then Exit;
      end;
      T := After(AMap, T);
    end;
  end;
end;

{ TRdxConstStringParameterFix }

class function TRdxConstStringParameterFix.MakeConst(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxParamPlan;
  out AReason: string): Boolean;
var
  Site       : TRdxParamSite;
  Name, Typ  : string;
  D          : TRdxParamDecl;
  IncLine    : Integer;
  First      : TRdxToken;
begin
  APlan := Default(TRdxParamPlan);
  if not ConstParamOf(AMessage, Name, Typ) then
  begin
    AReason := _(R_CS_NO_NAME);
    Exit(False);
  end;
  APlan.Name := Name;
  AReason := TRdxUnusedParameterFix.ReadSite(AMap, ALine, Name, Site);
  if AReason = '' then
    AReason := GroupReason(AMap, Site, Name, Typ);
  if AReason = '' then
    for D in Site.Decls do
      if (AReason = '') and not SameGroup(Site, D) then
        AReason := _(R_CS_GROUP, [D.Head.Head.Line]);
  if AReason = '' then
    AReason := LocalReason(AMap, Site);
  if AReason = '' then
  begin
    IncLine := IncludeInLines(AMap, 1, AMap.LineCount);
    if IncLine > 0 then
      AReason := _(R_CS_INCLUDE, [IncLine]);
  end;
  if AReason = '' then
    AReason := ValueReason(AMap, Site);
  if AReason = '' then
    AReason := WriteReason(AMap, Site);
  Result := AReason = '';
  if not Result then Exit;
  APlan.Name := TokText(AMap, Site.NameTok);
  for D in Site.Decls do
  begin
    First := D.List.Groups[D.Group].Names[0];
    AddEdit(APlan.Edits, TRdxUnusedParameterFix.TokenEdit(AMap, First,
      KW_CONST + TokText(AMap, First), SPAN_170));
  end;
  First := Site.List.Groups[Site.Group].Names[0];
  AddEdit(APlan.Edits, TRdxUnusedParameterFix.TokenEdit(AMap, First,
    KW_CONST + TokText(AMap, First), SPAN_170));
end;

end.
