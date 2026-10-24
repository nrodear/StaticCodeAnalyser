unit uRdxExceptionNameFix;

// reDelphix - Editorhilfe fuer SCA118 ExceptionName, OHNE ToolsAPI und ohne
// Parser: die Exception-Klasse 'MyError = class(Exception)' heisst danach
// 'EMyError', und mit ihr jeder Verweis im Code der Datei ('raise
// MyError.Create', 'on E: MyError do', 'class(MyError)', 'class of
// MyError'). Kommentare und Strings sieht die Code-Sicht nicht als Code -
// ein Kommentar darf den alten Namen behalten; ein String-Literal mit dem
// Namen sperrt (s. unten).
//
// DER FUND: uNamingExt meldet auf der Zeile des Klassennamens (nkClass,
// Zeile des Namens-Tokens), die Meldung nennt den Namen zweimal:
// 'Exception class MyError should start with ''E'' prefix (...).
// Suggested: EMyError'. Der Planer liest den Namen vor ' should start'.
//
// DER NEUE NAME ist 'E' + der Name mit grossem Anfangsbuchstaben
// ('MyError' -> 'EMyError', 'myError' -> 'EMyError'). Der Vorschlag des
// Detektors ('E' + Name) traefe bei 'error' die Form 'Eerror', die der
// Detektor weiter meldet ('E' + mehr als drei Kleinbuchstaben, MAX_LOWER_TAG
// in uNamingExt) - der Grossbuchstabe macht die Hilfe endgueltig. Ein
// Klassen-'T' vor einem Wort ('TMyError': T, Gross-, Kleinbuchstabe)
// ersetzt das 'E' ('EMyError' statt 'ETMyError'); ein Akronym bleibt
// ('TCPError' -> 'ETCPError').
//
// BEDEUTUNGSGLEICH, weil die Klasse nur in dieser Datei sichtbar ist und
// JEDER Verweis darauf mit umbenannt wird:
//   - die Deklaration steht hinter 'implementation' (oder in einem Programm
//     bzw. einer Bibliothek, Datei beginnt mit 'program'/'library') - eine
//     Klasse im interface-Teil koennen andere Units nennen, das beweist die
//     Datei nicht;
//   - der neue Name kommt im Code der Datei nicht vor (Gross/klein egal):
//     sonst bindet ein Verweis auf ein importiertes 'EMyError' danach an
//     die eigene Klasse;
//   - alle Verweise stehen HINTER der Deklaration (ein Verweis davor meint
//     einen anderen Typ, etwa einen importierten gleichen Namens; auch eine
//     forward-Deklaration 'MyError = class;' davor sperrt);
//   - die Umbenennung ist gleichfoermig: auch ein gleichnamiger lokaler
//     Bezeichner (Variable, Parameter) heisst danach 'EMyError' - in der
//     Datei bleiben alle Bindungen, wie sie waren.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - keine Deklaration 'Name = class' auf der Zeile (verschoben) oder
//     mehrere, die Klasse steht vor 'implementation' (bzw. die Datei hat
//     keines - eine Include-Datei),
//   - Kommentar oder Direktive in der Deklaration 'Name = class(..)',
//   - ein {$I} im implementation-Teil (das Include kann den Namen nennen),
//   - eine Direktive irgendwo in der Datei nennt den alten oder den neuen
//     Namen ('{$IF Declared(MyError)}'),
//   - ein String-Literal nennt den alten Namen (ClassName-Vergleich,
//     FindClass, RTTI),
//   - ein Verweis mit Punkt davor ('X.MyError': Member eines fremden Typs
//     oder Qualifizierung - ob er die Klasse meint, weiss die Datei nicht),
//     'MyError :=' (benanntes Argument), ein 'with' davor in derselben
//     Routine (der Name koennte ein Member des with-Ausdrucks sein),
//   - Zeichen ausserhalb A-Z, a-z, 0-9, '_' im Namen (Umlaute: die
//     Code-Sicht senkt nur ASCII, ein Verweis in anderer Schreibweise ginge
//     verloren), ein Name, der schon den Praefix traegt (Fund veraltet),
//     ein neuer Name, der ein Schluesselwort ist ('Except').
// GRENZE (nicht pruefbar ohne Projektwissen): eine Methode einer Klasse,
// deren Vorfahr in einer anderen Unit ein Member gleichen Namens traegt,
// sieht dort unter dem alten Namen das Member - nach der Umbenennung die
// eigene Klasse. Eine Exception-Klasse mit dem Namen eines geerbten
// Members ist selten; der Compiler meldet den Fall meist (der Aufruf
// passt nicht mehr).
//
// MEHRERE ERSETZUNGEN je Fund (wie SCA164/SCA147, uRdxRoutineFixes): je
// Verweis eine, in EINEM Undo-Schritt. Den Adapter fuer die Tabelle
// (TRdxFixFrame mit eigener Plan-Form) schreibt uRdxFixTable; diese Unit
// ist reine Textlogik (Code-Sicht, uRdxText) und bindet nichts vom
// Quellstellen-Dienst - sie laeuft auch im FPC-Pruefstand.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_EXC_FORM = 'the message does not name the exception class';
  R_EXC_NON_ASCII = 'the class name "%s" contains characters outside A-Z, '
    + 'a-z, 0-9 and "_" - the help cannot find every spelling of it';
  R_EXC_STALE = 'the class "%s" already carries the "E" prefix';
  R_EXC_SHAPE = 'the new name "%s" would still not start with "E" and a '
    + 'capital letter';
  R_EXC_KEYWORD = 'the new name "%s" is a reserved word';
  R_EXC_MOVED = 'no declaration "%s = class" on the reported line';
  R_EXC_MANY = 'the line declares "%s" more than once';
  R_EXC_NOT_LOCAL = 'the class is declared before "implementation" - other '
    + 'units may use its name';
  R_EXC_COMMENT = 'comment or compiler directive in the declaration of "%s"';
  R_EXC_INCLUDE = 'include file in the implementation part (line %d) - it '
    + 'may use the class name';
  R_EXC_TAKEN = 'the name "%s" already occurs in the code of the file';
  R_EXC_DIRECTIVE = 'a compiler directive names "%s"';
  R_EXC_STRING = 'a string literal names "%s" (ClassName, FindClass, RTTI)';
  R_EXC_BEFORE = '"%s" is used on line %d before its declaration - there it '
    + 'means another type';
  R_EXC_QUALIFIED = 'qualified use ".%s" on line %d - it may name a member '
    + 'of another type';
  R_EXC_NAMED_ARG = '"%s :=" on line %d - a named argument or an assignment';
  R_EXC_WITH = 'with statement before the use on line %d - "%s" could be a '
    + 'member of the with expression';

type
  // Ergebnis des Planers: alle Ersetzungen (EIN Undo-Schritt) und der neue
  // Name fuer den Menuetext ('Rename ... to %s') - schon gesetzt, wenn der
  // Planer erst spaeter ablehnt. OldName: der Name aus der Meldung.
  TRdxExceptionNamePlan = record
    Edits   : TArray<TRdxEdit>;
    OldName : string;
    Name    : string;
  end;

  TRdxExceptionNameFix = class
  public
    // SCA118: die Klasse der Meldung auf ALine in 'E' + Name umbenennen,
    // mit allen Verweisen der Datei (s. Kopf). Die Form von
    // TRdxPlannerOf<TRdxExceptionNamePlan> (uRdxFixTable).
    class function RenameClass(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxExceptionNamePlan;
      out AReason: string): Boolean; static;
    // Der Klassenname aus der Meldung ('Exception class X should start
    // ...'); '' ohne diese Form.
    class function ClassNameOf(const AMessage: string): string; static;
    // 'E' + AName mit grossem ASCII-Anfangsbuchstaben, ohne ein
    // Klassen-'T' vor einem Wort ('TMyError' -> 'EMyError'); '' fuer ''.
    class function PrefixedName(const AName: string): string; static;
    // Die Praefix-Form des Detektors (uNamingExt.HasExceptionPrefixShape):
    // 'E' + Grossbuchstabe oder Ziffer, oder 'E' + bis zu drei
    // Kleinbuchstaben + Grossbuchstabe oder Ziffer.
    class function HasPrefixShape(const AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxBlocks,       // TRdxBlocks.HeadBefore (die Routine um einen Verweis)
  uRdxText;         // _(), MsgMovedSuffix, MsgStaleSuffix

const
  SPAN_118 = 'sca118';
  KEY_HEAD = 'Exception class ';
  KEY_TAIL = ' should start';
  // Wie uNamingExt.MAX_LOWER_TAG.
  MAX_LOWER_TAG = 3;
  // Schluesselwoerter, die mit 'E' beginnen - 'E' + Name darf keines sein.
  E_KEYWORDS: array[0..3] of string = ('else', 'end', 'except', 'exports');
  // Woerter zwischen 'class' und der Vorfahrenliste.
  CLASS_MODS: array[0..1] of string = ('abstract', 'sealed');
  // Hier endet die Suche nach einem 'with' davor (WithReason).
  WITH_STOPS: array[0..4] of string = ('implementation', 'initialization',
    'finalization', 'program', 'library');
  // Die erste Zeile einer Datei ohne 'implementation', deren Typen keine
  // andere Unit sieht.
  LOCAL_FILES: array[0..1] of string = ('program', 'library');
  KW_IMPL = 'implementation';

// Nur ASCII-Bezeichnerzeichen, erstes keine Ziffer.
function IsAsciiName(const S: string): Boolean;
var
  i : Integer;
begin
  Result := (S <> '') and not CharInSet(S[1], ['0'..'9']);
  for i := 1 to Length(S) do
    if not CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(False);
end;

class function TRdxExceptionNameFix.HasPrefixShape(
  const AName: string): Boolean;
var
  i, TagLen : Integer;
begin
  Result := False;
  if (Length(AName) < 2) or (AName[1] <> 'E') then Exit;
  if CharInSet(AName[2], ['A'..'Z', '0'..'9']) then Exit(True);
  if not CharInSet(AName[2], ['a'..'z']) then Exit;
  i := 2;
  while (i <= Length(AName)) and CharInSet(AName[i], ['a'..'z']) do
    Inc(i);
  TagLen := i - 2;
  if (TagLen > MAX_LOWER_TAG) or (i > Length(AName)) then Exit;
  Result := CharInSet(AName[i], ['A'..'Z', '0'..'9']);
end;

class function TRdxExceptionNameFix.ClassNameOf(
  const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(KEY_HEAD, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(KEY_HEAD));
  Q := Pos(KEY_TAIL, AMessage, P);
  if Q > P then
    Result := Copy(AMessage, P, Q - P);
end;

class function TRdxExceptionNameFix.PrefixedName(
  const AName: string): string;
begin
  Result := '';
  if (Length(AName) >= 3) and (AName[1] = 'T')
     and CharInSet(AName[2], ['A'..'Z'])
     and CharInSet(AName[3], ['a'..'z']) then
    Result := 'E' + Copy(AName, 2, MaxInt)
  else if AName <> '' then
    Result := 'E' + UpCase(AName[1]) + Copy(AName, 2, MaxInt);
end;

// Die Deklaration 'ALow = [packed] class' auf ALine: '' mit dem Namens-Token
// in ADecl und dem Token 'class' in AClass, sonst der Grund.
function FindDecl(AMap: TRdxCodeMap; ALine: Integer; const AName,
  ALow: string; out ADecl, AClass: TRdxToken): string;
var
  T, N, C : TRdxToken;
  Count   : Integer;
begin
  ADecl := Default(TRdxToken);
  AClass := Default(TRdxToken);
  Count := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = ALow) and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      N := After(AMap, T);
      C := After(AMap, N);
      if C.Low = 'packed' then
        C := After(AMap, C);
      if (N.Low = '=') and (C.Low = 'class') then
      begin
        Inc(Count);
        ADecl := T;
        AClass := C;
      end;
    end;
    T := After(AMap, T);
  end;
  if Count = 0 then
    Result := MsgMovedSuffix(_(R_EXC_MOVED, [AName]))
  else if Count > 1 then
    Result := _(R_EXC_MANY, [AName])
  else
    Result := '';
end;

// Das letzte Token der Deklaration ab AClass: die ')' der Vorfahrenliste
// bzw. 'class' (oder sein letzter Modifizierer) ohne Liste; Low = '', wenn
// die Liste nicht schliesst.
function DeclTail(AMap: TRdxCodeMap; const AClass: TRdxToken): TRdxToken;
var
  N : TRdxToken;
begin
  Result := AClass;
  N := After(AMap, AClass);
  while InList(N.Low, CLASS_MODS) do
  begin
    Result := N;
    N := After(AMap, N);
  end;
  if N.Low = '(' then
    Result := MatchClose(AMap, N);
end;

// Das erste 'implementation' der Datei als Schluesselwort; Low = '' ohne.
function ImplementationTok(AMap: TRdxCodeMap): TRdxToken;
begin
  Result := NextTokenOnLineWith(AMap, Default(TRdxToken), KW_IMPL);
  while Result.Low <> '' do
  begin
    if (Result.Low = KW_IMPL)
       and IsKeywordAfter(Result, Before(AMap, Result)) then
      Exit;
    Result := NextTokenOnLineWith(AMap, Result, KW_IMPL);
  end;
end;

// Nennt eine Direktive in den Zeilen AFrom..ATo ALow als Wort?
function DirectiveNames(AMap: TRdxCodeMap; AFrom, ATo: Integer;
  const ALow: string): Boolean;
var
  Li, c : Integer;
  L     : string;
begin
  Result := False;
  for Li := AFrom to ATo do
  begin
    L := AMap.Raw(Li);
    if Pos('$', L) = 0 then Continue;
    for c := 1 to Length(L) do
      if OpensDirective(AMap, Li, c)
         and HasIdentWord(LowerCase(DirectiveArgs(AMap, Li, c)), ALow) then
        Exit(True);
  end;
end;

// Nennt ein String-Literal der Datei ALow als Wort? Je Zeile nur die
// Zeichen der Klasse 's' (Code-Sicht), alles andere als Leerzeichen.
function StringNames(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  Li, c : Integer;
  L, S  : string;
begin
  Result := False;
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    if Pos(ALow, LowerCase(L)) = 0 then Continue;
    S := L;
    for c := 1 to Length(L) do
      if AMap.ClassAt(Li, c) <> 's' then
        S[c] := ' ';
    if HasIdentWord(LowerCase(S), ALow) then
      Exit(True);
  end;
end;

// Steht im Code der Datei ein Token ALow?
function CodeNames(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if T.Low = ALow then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Ein 'with' als Schluesselwort zwischen AFrom (einschliesslich) und T -
// ausser in den Bereichen ASkipFrom[k]..ASkipTo[k] (Routinen, die T nicht
// umfassen). Die Bereiche kommen rueckwaerts gesammelt: der letzte beginnt
// zuerst; ein spaeter gesammelter kann einen frueheren umfassen (die
// aeussere Routine nach ihrer lokalen).
function WithIn(AMap: TRdxCodeMap; const AFrom, T: TRdxToken;
  const ASkipFrom, ASkipTo: TArray<TRdxToken>): Boolean;
var
  P, X : TRdxToken;
  k    : Integer;
begin
  Result := False;
  k := High(ASkipFrom);
  P := Before(AMap, AFrom);
  X := AFrom;
  while (X.Low <> '') and TokBefore(X, T) do
  begin
    while (k >= 0) and TokBefore(ASkipTo[k], X) do
      Dec(k);
    if (k >= 0) and not TokBefore(X, ASkipFrom[k]) then
    begin
      P := ASkipTo[k];
      X := After(AMap, P);
      Dec(k);
      Continue;
    end;
    if (X.Low = 'with') and IsKeywordAfter(X, P) then
      Exit(True);
    P := X;
    X := After(AMap, X);
  end;
end;

// Steht vor T in derselben Routine (ab ihrem Kopf) bzw. im selben
// initialization-/finalization-Teil oder Hauptblock ein 'with'?
// Vorsichtig: auch ein schon geschlossenes with davor sperrt. Die Routine
// ist die innerste, deren Kopf..';' T umfasst (TRdxBlocks.HeadBefore);
// Routinen auf dem Weg, die T nicht umfassen, zaehlen nicht mit (ihre
// with-Bloecke enden in ihnen). Ein Kopf mit unsicheren Grenzen auf dem
// Weg (auch jede Methodendeklaration im Klassenrumpf - sie hat keinen
// Rumpf) koennte T umfassen: steht zwischen ihm und T ein with, sperrt es,
// sonst geht die Suche weiter. '' oder der Grund.
function WithReason(AMap: TRdxCodeMap; const T: TRdxToken;
  const AName: string): string;
var
  H                : TRdxToken;
  S                : TRdxHeadStep;
  W                : Boolean;
  SkipFrom, SkipTo : TArray<TRdxToken>;
begin
  Result := '';
  W := False;
  SkipFrom := nil;
  SkipTo := nil;
  H := T;
  while TRdxBlocks.HeadBefore(AMap, H, WITH_STOPS, S) do
  begin
    if S.Stop then
    begin
      W := (S.Tok.Low <> KW_IMPL)
        and WithIn(AMap, S.Tok, T, SkipFrom, SkipTo);
      Break;
    end;
    if S.Reason <> '' then
    begin
      W := WithIn(AMap, S.Tok, T, SkipFrom, SkipTo);
      if W then
        Break;
    end
    else if TokBefore(T, S.Routine.Last) then
    begin
      W := WithIn(AMap, S.Routine.Head, T, SkipFrom, SkipTo);
      Break;
    end
    else
    begin
      AddToken(SkipFrom, S.Routine.Head);
      AddToken(SkipTo, S.Routine.Last);
    end;
  end;
  if W then
    Result := _(R_EXC_WITH, [T.Line, AName]);
end;

// Der Grund, den Verweis T (Low = der alte Name) NICHT umzubenennen; ''
// wenn er umbenannt werden kann.
function UseReason(AMap: TRdxCodeMap; const T, ADecl: TRdxToken;
  const AName: string): string;
begin
  Result := '';
  if TokBefore(T, ADecl) then
    Result := _(R_EXC_BEFORE, [AName, T.Line])
  else if Before(AMap, T).Low = '.' then
    Result := _(R_EXC_QUALIFIED, [AName, T.Line])
  else if After(AMap, T).Low = ':=' then
    Result := _(R_EXC_NAMED_ARG, [AName, T.Line])
  else
    Result := WithReason(AMap, T, AName);
end;

// Alle Verweise auf ALow in der Datei als Ersetzungen; '' oder der Grund.
function CollectEdits(AMap: TRdxCodeMap; const ADecl: TRdxToken;
  const AName, ALow, ANewName: string;
  var AEdits: TArray<TRdxEdit>): string;
var
  T : TRdxToken;
  E : TRdxEdit;
begin
  Result := '';
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if T.Low = ALow then
    begin
      Result := UseReason(AMap, T, ADecl, AName);
      if Result <> '' then
        Exit;
      E := Default(TRdxEdit);
      E.Span := TRefactorSpan.Make(SPAN_118, T.Line, T.Col, T.Line, T.EndCol);
      E.Expected := TokText(AMap, T);
      E.NewText := ANewName;
      AddEdit(AEdits, E);
    end;
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Was gegen den neuen Namen ANewName spricht: die Form, ein
// Schluesselwort; '' sonst.
function NameReason(const AName, ANewName: string): string;
begin
  Result := '';
  if not IsAsciiName(AName) then
    Result := _(R_EXC_NON_ASCII, [AName])
  else if TRdxExceptionNameFix.HasPrefixShape(AName)
          or SameText(AName, 'Exception') then
    Result := MsgStaleSuffix(_(R_EXC_STALE, [AName]))
  else if not TRdxExceptionNameFix.HasPrefixShape(ANewName) then
    Result := _(R_EXC_SHAPE, [ANewName])
  else if InList(LowerCase(ANewName), E_KEYWORDS) then
    Result := _(R_EXC_KEYWORD, [ANewName]);
end;

// Ist die Klasse an ADecl nur in dieser Datei sichtbar? '' mit der ersten
// Zeile des Teils, in dem andere Verweise stehen koennen (AFrom), sonst
// der Grund.
function LocalReason(AMap: TRdxCodeMap; const ADecl: TRdxToken;
  out AFrom: Integer): string;
var
  Impl : TRdxToken;
begin
  Result := '';
  AFrom := 1;
  Impl := ImplementationTok(AMap);
  if Impl.Low <> '' then
  begin
    if not TokBefore(Impl, ADecl) then
      Result := _(R_EXC_NOT_LOCAL);
    AFrom := Impl.Line;
  end
  else if not InList(NextToken(AMap, 1, 1).Low, LOCAL_FILES) then
    Result := _(R_EXC_NOT_LOCAL);
end;

// Die Fragen an die ganze Datei: Kommentar in der Deklaration, Include,
// neuer Name im Code, Direktive, String-Literal. '' oder der Grund.
function FileReason(AMap: TRdxCodeMap; const ADecl, AClass: TRdxToken;
  AFrom: Integer; const AName, ANewName: string): string;
var
  Tail    : TRdxToken;
  IncLine : Integer;
  Low     : string;
begin
  Result := '';
  Low := LowerCase(AName);
  Tail := DeclTail(AMap, AClass);
  IncLine := IncludeInLines(AMap, AFrom, AMap.LineCount);
  if (Tail.Low = '') or CommentInRange(AMap, TRefactorSpan.Make(SPAN_118,
       ADecl.Line, ADecl.Col, Tail.Line, Tail.EndCol)) then
    Result := _(R_EXC_COMMENT, [AName])
  else if IncLine > 0 then
    Result := _(R_EXC_INCLUDE, [IncLine])
  else if CodeNames(AMap, LowerCase(ANewName)) then
    Result := _(R_EXC_TAKEN, [ANewName])
  else if DirectiveNames(AMap, 1, AMap.LineCount, Low) then
    Result := _(R_EXC_DIRECTIVE, [AName])
  else if DirectiveNames(AMap, 1, AMap.LineCount, LowerCase(ANewName)) then
    Result := _(R_EXC_DIRECTIVE, [ANewName])
  else if StringNames(AMap, Low) then
    Result := _(R_EXC_STRING, [AName]);
end;

class function TRdxExceptionNameFix.RenameClass(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxExceptionNamePlan;
  out AReason: string): Boolean;
var
  Decl, Cls : TRdxToken;
  From      : Integer;
begin
  Result := False;
  Decl := Default(TRdxToken);
  Cls := Default(TRdxToken);
  From := 1;
  APlan := Default(TRdxExceptionNamePlan);
  APlan.OldName := ClassNameOf(AMessage);
  if APlan.OldName = '' then
  begin
    AReason := _(R_EXC_FORM);
    Exit;
  end;
  APlan.Name := PrefixedName(APlan.OldName);
  AReason := NameReason(APlan.OldName, APlan.Name);
  if AReason = '' then
    AReason := FindDecl(AMap, ALine, APlan.OldName, LowerCase(APlan.OldName),
      Decl, Cls);
  if AReason = '' then
    AReason := LocalReason(AMap, Decl, From);
  if AReason = '' then
    AReason := FileReason(AMap, Decl, Cls, From, APlan.OldName, APlan.Name);
  if AReason = '' then
    AReason := CollectEdits(AMap, Decl, APlan.OldName,
      LowerCase(APlan.OldName), APlan.Name, APlan.Edits);
  if AReason <> '' then
  begin
    APlan.Edits := nil;
    Exit;
  end;
  Result := True;
end;

end.
