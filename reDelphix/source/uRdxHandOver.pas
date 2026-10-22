unit uRdxHandOver;

// reDelphix - die Weitergabe-Sperre der Quick-Fixes try/finally (SCA009,
// SCA001, SCA156; Charge H4, Gegen-Review H4 Blocker 1) und die lokalen
// Variablen der Routine um eine Stelle, OHNE ToolsAPI und ohne Parser.
// Bis Review Woche G08-08 standen sie mitten in uRdxTryFixes. Wird X
// (Objekt bzw. Puffer) zwischen Erzeugung und Freigabe festgehalten,
// gaebe finally X im Fehlerfall frei, waehrend der Halter es noch kennt -
// aus einem Leck wuerde ein Use-after-free. Der Lauf (uRdxTrySpan) fragt
// je Nennung von X HandOverReason; der Baustein (uRdxTryFixes) fragt, ob
// ein Puffer eine lokale Variable ist (IsLocalVar) und wo eine
// Inline-Deklaration beginnt (InlineVarOf).
//
// WAS SPERRT (der Vertrag steht im Kopf von uRdxTryFixes, SPERREN
// "Weitergabe auch OHNE Ausstieg", ebenso was bewusst bleibt): '@X' bzw.
// '@X.M'; X als direktes Argument eines Aufrufs, der es festhaelt
// (STORE_PREFIXES ausser STORE_HARMLESS) oder wirft (RAISE_CALLS); X als
// ganze rechte Seite einer Zuweisung an keinen lokalen Namen der Routine
// (NonLocalTarget); ein Methodenzeiger 'X.M' an ein Ereignis ('On..',
// 'FOn..'). X auch in Huellen (WrappedAt: Typumwandlung, auch generisch,
// Klammern, 'as', Array-Konstruktor - beliebig tief). Tests:
// uTestRdxTryGates (HandOver_*).
//
// LOKALE VARIABLEN: die innerste Routine um die Stelle (RoutineAround,
// Politik von SCA009: ein unsicherer Kopf wird uebergangen, ein
// Abschnittswort der Unit beendet die Suche), ihr var-Abschnitt und ein
// Inline-var davor. Parameter zaehlen nicht.
//
// GETEILT (interface) mit uRdxTrySpan und uRdxTryFixes: die Woerter der
// Anweisungslisten (LIST_PREV, BRANCH_WORDS, LIST_ENDS, ARG_ENDS,
// UNIT_BOUNDS), SourceText, QualifiedEnd und das Satzende R_HELD - EINE
// Fassung fuer die drei Units, die bis G08-08 eine waren.

interface

uses
  uRdxCodeMap;

const
  // Davor beginnt eine Anweisung IN einer Anweisungsliste.
  LIST_PREV: array[0..7] of string = (';', 'begin', 'try', 'finally',
    'except', 'repeat', 'initialization', 'finalization');
  // Zweige ohne begin: dahinter steht genau eine Anweisung.
  BRANCH_WORDS: array[0..2] of string = ('then', 'else', 'do');
  // Hier endet eine Anweisungsliste.
  LIST_ENDS: array[0..3] of string = ('end', 'until', 'except', 'finally');
  // Hier endet die Rueckwaerts-Suche nach umschliessenden try-Bloecken
  // (uRdxTrySpan) bzw. nach der Routine um eine Stelle (RoutineAround).
  UNIT_BOUNDS: array[0..6] of string = ('implementation', 'interface',
    'initialization', 'finalization', 'unit', 'program', 'library');
  // Dahinter: ein direktes Argument ('F(X)', 'F(A, X, B)'; davor
  // ARG_STARTS).
  ARG_ENDS: array[0..1] of string = (',', ')');
  // Satzende der Weitergabe-Gruende (auch uRdxTryFixes.HolderReason).
  R_HELD = 'bei einer Ausnahme gaebe finally es frei, waehrend der Halter '
    + 'es noch kennt; von Hand pruefen';

// Derselbe Text wie im Quelltext (Menuetext), Zeilen mit Leerzeichen.
function SourceText(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;

// Das letzte Glied eines qualifizierten Namens ab T ('SysUtils.FreeAndNil'
// -> 'FreeAndNil'); T selbst, wenn kein '.' folgt.
function QualifiedEnd(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;

// Ist AName eine lokale Variable der Routine um AAt (var-Abschnitt oder
// Inline-var davor)? Parameter zaehlen nicht.
function IsLocalVar(AMap: TRdxCodeMap; const AAt: TRdxToken;
  const AName: string): Boolean;

// Das Inline-'var', mit dem die Anweisung mit dem ':=' AAssign beginnt;
// Low = '' ohne.
function InlineVarOf(AMap: TRdxCodeMap; const AAssign: TRdxToken): TRdxToken;

// Weitergabe ohne Ausstieg (s. Kopf): wird X an T (APrev davor)
// festgehalten? '' oder der Grund.
function HandOverReason(AMap: TRdxCodeMap; const T, APrev: TRdxToken): string;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make (SourceText)
  uRdxBlocks;        // ReadRoutine, HeadBefore (die Routine um eine Stelle)

const
  SPAN_TRY = 'try';
  // Davor: ein direktes Argument ('F(X)', 'F(A, X, B)'; dahinter ARG_ENDS).
  ARG_STARTS: array[0..1] of string = ('(', ',');
  // Dahinter: ein Element eines Array-Konstruktors ('[X]', '[A, X]').
  ELEM_ENDS: array[0..1] of string = (',', ']');
  // Davor steht bei einem Index ('Items[X]', 'F(1)[X]', 'P^[X]') - sonst
  // ist '[' ein Array-Konstruktor bzw. eine Menge (WrapOnce).
  INDEX_PREV: array[0..2] of string = (')', ']', '^');
  // Weitergabe ohne Ausstieg (Blocker 1, s. Kopf): ein Aufruf, dessen Name
  // so beginnt, haelt ein direktes Argument fest ...
  STORE_PREFIXES: array[0..7] of string = ('add', 'insert', 'push',
    'enqueue', 'register', 'attach', 'subscribe', 'put');
  // ... ausser diesen: InsertComponent - TComponent.Destroy meldet sich
  // beim Owner ab (RemoveComponent), Free im finally laesst dort keinen
  // Verweis zurueck; AddStrings kopiert nur Strings und Objects von X.
  STORE_HARMLESS: array[0..1] of string = ('insertcomponent', 'addstrings');
  // Sie werfen ihr Argument als Ausnahme (wie 'raise X').
  RAISE_CALLS: array[0..1] of string = ('raiseouterexception',
    'throwouterexception');
  // Typumwandlungen ohne T/P/I-Namen (IsCastName).
  CAST_WORDS: array[0..6] of string = ('pointer', 'nativeint', 'nativeuint',
    'integer', 'cardinal', 'int64', 'uint64');
  // So viele Token liest der Planer rueckwaerts bis zum Anfang des Ziels
  // einer Zuweisung - laenger heisst: kein Ziel, das er sicher liest.
  MAX_TARGET_TOKENS = 64;
  // Abschnitte im Deklarationsteil einer Routine: nur var deklariert
  // Variablen; davor bzw. dahinter steht ein deklarierter Name ('var A,
  // B: T;').
  VAR_SECTIONS: array[0..1] of string = ('var', 'threadvar');
  SECTION_WORDS: array[0..5] of string = ('var', 'threadvar', 'const', 'type',
    'label', 'resourcestring');
  DECL_PREV: array[0..3] of string = ('var', 'threadvar', ';', ',');
  DECL_NEXT: array[0..1] of string = (':', ',');
  // Ein Ereignis heisst 'On..' bzw. als Feld 'FOn..' (Ziel eines
  // Methodenzeigers 'X.M').
  EVENT_PREFIX = 'on';
  EVENT_FIELD  = 'FOn';

{ ---- kleine Helfer ---- }

// Derselbe Text wie im Quelltext (Menuetext), Zeilen mit Leerzeichen.
function SourceText(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;
begin
  Result := Trim(StringReplace(RangeText(AMap, TRefactorSpan.Make(SPAN_TRY,
    AFrom.Line, AFrom.Col, ATo.Line, ATo.EndCol)), #10, ' ', [rfReplaceAll]));
end;

// Endet an N (APrev davor) die Anweisung - ';', das Listenende oder else?
function EndsStatement(AMap: TRdxCodeMap; const N, APrev: TRdxToken): Boolean;
begin
  Result := (N.Low = ';') or (IsKeywordAt(AMap, N, APrev)
    and (InList(N.Low, LIST_ENDS) or (N.Low = 'else')));
end;

// Das letzte Glied eines qualifizierten Namens ab T ('SysUtils.FreeAndNil'
// -> 'FreeAndNil', 'Windows.EnterCriticalSection'); T selbst, wenn kein
// '.' folgt.
function QualifiedEnd(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  D, N : TRdxToken;
begin
  Result := T;
  if not T.IsWord then Exit;
  D := After(AMap, Result);
  N := After(AMap, D);
  while (D.Low = '.') and N.IsWord do
  begin
    Result := N;
    D := After(AMap, Result);
    N := After(AMap, D);
  end;
end;

// Rueckwaerts ab AFrom (einschliesslich) die erste '(' bzw. '[', die bis
// AFrom nicht geschlossen ist; Low = '' ohne (';' oder Dateianfang davor).
function UnmatchedOpener(AMap: TRdxCodeMap; const AFrom: TRdxToken): TRdxToken;
var
  T     : TRdxToken;
  Depth : Integer;
  Delta : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := AFrom;
  while (T.Low <> '') and (T.Low <> ';') do
  begin
    // Rueckwaerts: eine schliessende Klammer oeffnet eine Gruppe, eine
    // oeffnende auf Tiefe 0 ist die gesuchte (ParenDelta, uRdxCodeMap).
    Delta := ParenDelta(T);
    if (Delta > 0) and (Depth = 0) then
      Exit(T);
    Dec(Depth, Delta);
    T := Before(AMap, T);
  end;
end;

{ ---- Die Routine um A: lokale Variablen (Weitergabe-Sperre) ---- }

// Die innerste Routine, deren Rumpf AAt enthaelt (begin < AAt < end) -
// rueckwaerts bis zu ihrem Kopf, Grenzen per ReadRoutine (lokale Routinen
// davor enthalten AAt nicht und werden uebergangen). False ohne. Die Suche
// ist der Baustein TRdxBlocks.HeadBefore (Gegen-Review R5-03, bis Charge
// B2S-b hier ausgeschrieben); die Politik dieser Frage bleibt, wie sie war:
// ein Kopf, dessen Grenzen nicht sicher sind, wird uebergangen - die Suche
// geht davor weiter -, und ein Abschnittswort der Unit (UNIT_BOUNDS)
// beendet sie. Den Unterschied zeigt ein unsicherer Kopf im Rumpf der
// gesuchten Routine selbst - etwa die Zuweisung an eine Variable Operator
// ('operator' steht in ROUTINE_WORDS, ist aber kein reserviertes Wort):
// hier geht die Suche an ihm vorbei zur Routine davor (gepinnt in
// uTestRdxBlocks.TryPolicy_UnsafeHeadSkipped, Gegenpruefung V-B2S-1).
// (SCA196 in uRdxResultFixes fragt anders: Zeilen statt Token, und der
// erste unsichere Kopf beendet dort die Suche mit seinem Grund.)
function RoutineAround(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): Boolean;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  ARoutine := Default(TRdxRoutine);
  T := AAt;
  while TRdxBlocks.HeadBefore(AMap, T, UNIT_BOUNDS, S) and not S.Stop do
    if (S.Reason = '') and (S.Routine.Body.Low <> '')
       and TokBefore(S.Routine.Body, AAt)
       and TokBefore(AAt, S.Routine.EndTok) then
    begin
      ARoutine := S.Routine;
      Exit(True);
    end;
  Result := False;
end;

// Wird an T (P davor) der Name AName deklariert ('var A, B: T;' - davor
// var, ';' bzw. ',', dahinter ':' bzw. ',')?
function DeclaresName(AMap: TRdxCodeMap; const T, P: TRdxToken;
  const AName: string): Boolean;
begin
  Result := SameIdent(T.Low, AName) and InList(P.Low, DECL_PREV)
    and InList(After(AMap, T).Low, DECL_NEXT);
end;

// Eine lokale Routine ab ihrem Kopf T ueberspringen: T wird ihr letztes
// ';'. False, wenn ihre Grenzen nicht sicher sind.
function SkipLocalRoutine(AMap: TRdxCodeMap; var T: TRdxToken): Boolean;
var
  Local : TRdxRoutine;
begin
  Result := TRdxBlocks.ReadRoutine(AMap, T, Local) = '';
  if Result then
    T := Local.Last;
end;

// AName im var-Abschnitt des Deklarationsteils von ARoutine (zwischen Kopf
// und Rumpf; lokale Routinen - ihre Variablen gehoeren nicht hierher -
// uebersprungen)?
function VarInSections(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const AName: string): Boolean;
var
  T, P  : TRdxToken;
  InVar : Boolean;
begin
  Result := False;
  InVar := False;
  P := ARoutine.HeaderEnd;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, ARoutine.Body) do
  begin
    if IsRoutineHeadAfter(T, P) then
    begin
      if not SkipLocalRoutine(AMap, T) then
        Exit;
      InVar := False;
    end
    else if IsKeywordAt(AMap, T, P) and InList(T.Low, SECTION_WORDS) then
      InVar := InList(T.Low, VAR_SECTIONS)
    else if InVar and DeclaresName(AMap, T, P, AName) then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

// AName als Inline-var ('var A, B: T' bzw. 'var A := ..') im Rumpf ab
// ABody vor AAt?
function InlineVarBefore(AMap: TRdxCodeMap; const ABody, AAt: TRdxToken;
  const AName: string): Boolean;
var
  T, P, N : TRdxToken;
begin
  Result := False;
  P := ABody;
  T := After(AMap, ABody);
  while (T.Low <> '') and TokBefore(T, AAt) do
  begin
    if (T.Low = 'var') and IsKeywordAt(AMap, T, P) then
    begin
      N := After(AMap, T);
      while N.IsWord do
      begin
        if SameIdent(N.Low, AName) then
          Exit(True);
        if After(AMap, N).Low <> ',' then
          Break;
        N := After(AMap, After(AMap, N));
      end;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Ist AName eine lokale Variable der Routine um AAt (var-Abschnitt oder
// Inline-var davor)? Parameter zaehlen nicht (NonLocalTarget).
function IsLocalVar(AMap: TRdxCodeMap; const AAt: TRdxToken;
  const AName: string): Boolean;
var
  R : TRdxRoutine;
begin
  Result := RoutineAround(AMap, AAt, R) and (VarInSections(AMap, R, AName)
    or InlineVarBefore(AMap, R.Body, AAt, AName));
end;

// Das Inline-'var', mit dem die Anweisung mit dem ':=' AAssign beginnt
// ('var Y := X', 'var Y: TFoo := X'); Low = '' ohne. Die Deklaration ist
// lokal.
function InlineVarOf(AMap: TRdxCodeMap; const AAssign: TRdxToken): TRdxToken;
var
  T, P : TRdxToken;
  n    : Integer;
begin
  Result := Default(TRdxToken);
  T := Before(AMap, AAssign);
  for n := 1 to MAX_TARGET_TOKENS do
  begin
    if (T.Low = '') or InList(T.Low, LIST_PREV) or InList(T.Low, BRANCH_WORDS) then
      Exit;
    P := Before(AMap, T);
    if (T.Low = 'var') and IsKeywordAt(AMap, T, P) then
      Exit(T);
    T := P;
  end;
end;

// Das erste Token des Ziels vor AAssign (':='): rueckwaerts ueber Namen,
// '.', '^' und Klammern ('Items.Objects[I]', 'P^.Next', 'F(x).Y'); APlain
// = ein Name allein. Low = '' ohne lesbares Ziel.
function TargetStart(AMap: TRdxCodeMap; const AAssign: TRdxToken;
  out APlain: Boolean): TRdxToken;
var
  T, P : TRdxToken;
  n    : Integer;
begin
  Result := Default(TRdxToken);
  APlain := True;
  T := Before(AMap, AAssign);
  for n := 1 to MAX_TARGET_TOKENS do
  begin
    if (T.Low = ')') or (T.Low = ']') then
      T := Before(AMap, UnmatchedOpener(AMap, Before(AMap, T)))
    else if T.Low = '^' then
      T := Before(AMap, T)
    else if T.IsWord then
    begin
      P := Before(AMap, T);
      if P.Low <> '.' then
        Exit(T);
      T := Before(AMap, P);
    end
    else
      Exit;
    APlain := False;
  end;
end;

// Das Ziel der Zuweisung mit dem ':=' AAssign, wenn es keine lokale
// Variable der Routine um AAt ist - Feld, Property, Element, Result,
// globale Variable, Parameter (lieber eine Sperre zu viel: ein var-/out-
// Parameter gaebe X an den Aufrufer); '' fuer eine lokale.
function NonLocalTarget(AMap: TRdxCodeMap; const AAssign, AAt: TRdxToken): string;
var
  First : TRdxToken;
  Plain : Boolean;
begin
  Result := '';
  if InlineVarOf(AMap, AAssign).Low <> '' then Exit;
  First := TargetStart(AMap, AAssign, Plain);
  if Plain and (First.Low <> 'result') and IsLocalVar(AMap, AAt, First.Low) then
    Exit;
  if First.Low = '' then
    First := Before(AMap, AAssign);
  Result := SourceText(AMap, First, Before(AMap, AAssign));
end;

{ ---- Weitergabe ohne Ausstieg (Gegen-Review H4, Blocker 1) ---- }

// Haelt ein Aufruf namens ALow ein direktes Argument fest (STORE_PREFIXES
// ausser STORE_HARMLESS)?
function IsStoreCall(const ALow: string): Boolean;
var
  S : string;
begin
  Result := False;
  if InList(ALow, STORE_HARMLESS) then Exit;
  for S in STORE_PREFIXES do
    if Copy(ALow, 1, Length(S)) = S then
      Exit(True);
end;

// Rueckwaerts ab dem '>' AClose die passende '<' einer Typparameterliste
// ('TList<TFoo>', 'TDictionary<string, TList<TFoo>>'): dazwischen nur
// Woerter, '.', ',' und weitere spitze Klammern, hoechstens
// MAX_TARGET_TOKENS Token; Low = '' sonst - ein Vergleich 'A > (X)' hat
// keine solche '<' davor. MatchClose zaehlt nur vorwaerts. Bewusst nicht
// uRdxCodeMap.OpenAngleBefore (Folgewelle des Wochen-Reviews geprueft):
// die Fassung fuer Deklarationen liest auch ';', ':' und '&'
// ('TGen<T: class; U>') und hat keine Obergrenze - in einem Ausdruck liefe
// sie ueber das ';' in die Anweisung davor.
function GenericOpener(AMap: TRdxCodeMap; const AClose: TRdxToken): TRdxToken;
var
  T     : TRdxToken;
  Depth : Integer;
  n     : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := AClose;
  for n := 1 to MAX_TARGET_TOKENS do
  begin
    if T.Low = '>' then
      Inc(Depth)
    else if T.Low = '<' then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(T);
    end
    else if not T.IsWord and (T.Low <> '.') and (T.Low <> ',') then
      Exit;
    T := Before(AMap, T);
  end;
end;

// Das Token vor der Klammer AOpen, ueber eine Typparameterliste hinweg:
// 'TList<TFoo>(' -> 'TList', 'Reg.Add<TFoo>(' -> 'Add'; sonst das Token
// davor. Bis Review Woche G08-02 sahen WrapStart und CallOfArg dort nur
// '>' - 'FItems := TList<TFoo>(X)' galt als blosse Klammer, die Zuweisung
// an das Feld blieb unsichtbar.
function NameBeforeOpen(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
var
  L : TRdxToken;
begin
  Result := Before(AMap, AOpen);
  if Result.Low <> '>' then Exit;
  L := GenericOpener(AMap, Result);
  if L.Low <> '' then
    Result := Before(AMap, L);
end;

// Der Name des Aufrufs, dessen direktes Argument AFirst..ALast ist (davor
// '(' bzw. ',', dahinter ',' bzw. ')'); Low = '' ohne. Ein Element eines
// Array-Konstruktors ('[X]', '[A, X]') zaehlt wie der ganze Konstruktor -
// ist der ein direktes Argument, ist es der Aufruf ('FList.AddRange([X])';
// bis Review Woche G08-02 ohne Aufruf, im Fehlerfall gab finally X frei,
// waehrend die Liste es noch kannte). Ein Index ('Arr[X]') hat davor kein
// '(' bzw. ',' und bleibt ohne.
function CallOfArg(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken): TRdxToken;
var
  P, O, C : TRdxToken;
begin
  Result := Default(TRdxToken);
  P := Before(AMap, AFirst);
  if not InList(P.Low, ARG_STARTS) and (P.Low <> '[') then Exit;
  O := UnmatchedOpener(AMap, P);
  if O.Low = '[' then
  begin
    if not InList(After(AMap, ALast).Low, ELEM_ENDS) then Exit;
    C := MatchClose(AMap, O);
    if C.Low <> '' then
      Result := CallOfArg(AMap, O, C);
    Exit;
  end;
  if (O.Low <> '(') or not InList(After(AMap, ALast).Low, ARG_ENDS) then
    Exit;
  P := NameBeforeOpen(AMap, O);
  if P.IsWord then
    Result := P;
end;

// Sieht AName wie ein Typ aus - eine Typumwandlung 'TObject(X)',
// 'PByte(P)', 'IFoo(X)', 'Pointer(X)'? Delphi-Konvention: T, P bzw. I und
// ein Grossbuchstabe. Ein Funktionsaufruf 'AttToHtml(X)' gibt dagegen nur
// sein Ergebnis weiter, nicht X (Korpus-Harness H4c: 'Strings.Add(
// AttToHtml(Datt))' sperrte sonst sechsmal).
function IsCastName(const AName: string): Boolean;
begin
  Result := InList(LowerCase(AName), CAST_WORDS)
    or ((Length(AName) > 1) and CharInSet(AName[1], ['T', 'P', 'I'])
      and CharInSet(AName[2], ['A'..'Z']));
end;

// Ist W (ein Wort vor '(') eine Typumwandlung (IsCastName) - und kein
// Aufruf, der sein Argument festhaelt oder wirft ('PUTDATA(X)' sieht wie
// ein Cast aus)?
function IsCastWord(AMap: TRdxCodeMap; const W: TRdxToken): Boolean;
begin
  Result := W.IsWord and IsCastName(TokText(AMap, W))
    and not IsStoreCall(W.Low) and not InList(W.Low, RAISE_CALLS);
end;

// Das Ende des Typs hinter 'as' AAs: 'TFoo', 'System.TObject' bzw. das '>'
// von 'TList<T>'; Low = '' ohne lesbaren Typ.
function AsTypeEnd(AMap: TRdxCodeMap; const AAs: TRdxToken): TRdxToken;
var
  N : TRdxToken;
begin
  Result := Default(TRdxToken);
  N := After(AMap, AAs);
  if not N.IsWord then Exit;
  Result := QualifiedEnd(AMap, N);
  N := After(AMap, Result);
  if N.Low = '<' then
    Result := MatchClose(AMap, N);
end;

// Das erste Token der Klammer AOpen samt Typumwandlung davor: 'TFoo(' bzw.
// 'System.TObject(' ab dem ersten Glied, auch generisch 'TList<TFoo>('
// (NameBeforeOpen), '(' allein bei blossen Klammern; Low = '' hinter einem
// Namen, der kein Cast ist (ein Aufruf 'F(X)' bzw. 'F<T>(X)' - X ist dort
// sein Argument, CallOfArg).
function WrapStart(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
var
  W, D : TRdxToken;
begin
  Result := AOpen;
  W := NameBeforeOpen(AMap, AOpen);
  if not W.IsWord then Exit;
  if not IsCastWord(AMap, W) then
    Exit(Default(TRdxToken));
  repeat
    Result := W;
    D := Before(AMap, W);
    W := Before(AMap, D);
  until (D.Low <> '.') or not W.IsWord;
end;

// Eine Huelle mehr um AFirst..ALast (s. WrappedAt): ' as TFoo' dahinter, ein
// Array-Konstruktor '[..]' mit nur diesem Element ('FArr := [X]') bzw. eine
// Klammer drumherum - davor nichts oder eine Typumwandlung. True, wenn der
// Bereich gewachsen ist.
function WrapOnce(AMap: TRdxCodeMap; var AFirst, ALast: TRdxToken): Boolean;
var
  P, N, S : TRdxToken;
begin
  Result := False;
  N := After(AMap, ALast);
  if N.Low = 'as' then
  begin
    S := AsTypeEnd(AMap, N);
    if S.Low = '' then Exit;
    ALast := S;
    Exit(True);
  end;
  P := Before(AMap, AFirst);
  if (P.Low = '[') and (N.Low = ']') then
  begin
    // Vor einem Index steht ein Name, ')', ']' bzw. '^' - der ist keine
    // Huelle ('Items[X]').
    S := Before(AMap, P);
    if S.IsWord or InList(S.Low, INDEX_PREV) then Exit;
    AFirst := P;
    ALast := N;
    Exit(True);
  end;
  if (P.Low <> '(') or (N.Low <> ')') then Exit;
  S := WrapStart(AMap, P);
  if S.Low = '' then Exit;
  AFirst := S;
  ALast := N;
  Result := True;
end;

// X an T samt seinen Huellen - eine Typumwandlung 'TFoo(X)' (IsCastWord, X
// allein in der Klammer, auch qualifiziert 'System.TObject(X)'), Klammern
// '(X)' und 'X as TFoo' -, beliebig tief geschachtelt: AFirst..ALast ist der
// ganze Ausdruck, der X weiterreicht; ohne Huelle T selbst. Jede Huelle
// macht den Bereich groesser (WrapOnce), der Lauf endet also spaetestens an
// den Grenzen der Datei. Bis Charge B1-FE sah die Weitergabe-Sperre X nur
// direkt hinter ':=' bzw. als Argument und packte nur den Cast im Aufruf
// aus: 'FCurrent := TFoo(X);', 'FCurrent := X as TFoo;' und 'List.Add(X as
// TObject);' gingen durch (Gegen-Review R5, R5-04); bis zur Nachpruefung
// las sie hoechstens vier Huellen, mit der fuenften ging es wieder durch.
procedure WrappedAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out AFirst, ALast: TRdxToken);
var
  Grown : Boolean;
begin
  AFirst := T;
  ALast := T;
  Grown := True;
  while Grown do
    Grown := WrapOnce(AMap, AFirst, ALast);
end;

// X an T als direktes Argument eines Aufrufs, der es festhaelt bzw. wirft
// - auch in einer Huelle (AFirst..ALast, WrappedAt: 'List.Add(TObject(X))',
// 'List.Add(X as TObject)'). '' oder der Grund.
function CallArgReason(AMap: TRdxCodeMap;
  const T, AFirst, ALast: TRdxToken): string;
var
  Call : TRdxToken;
begin
  Result := '';
  Call := CallOfArg(AMap, AFirst, ALast);
  if Call.Low = '' then Exit;
  if InList(Call.Low, RAISE_CALLS) then
    Exit(Format('%s wird in Zeile %d an %s uebergeben - das Objekt ist die '
      + 'Ausnahme; finally gaebe es vor dem Handler frei',
      [TokText(AMap, T), T.Line, TokText(AMap, Call)]));
  if IsStoreCall(Call.Low) then
    Result := Format('%s wird in Zeile %d an %s weitergegeben - %s',
      [TokText(AMap, T), T.Line, TokText(AMap, Call), R_HELD]);
end;

// Heisst AName wie ein Ereignis - 'On..' (Gross/klein egal, ein 'Online'
// sperrt nur) bzw. das Feld 'FOn..'?
function IsEventName(const AName: string): Boolean;
begin
  Result := SameText(Copy(AName, 1, Length(EVENT_PREFIX)), EVENT_PREFIX)
    or (Copy(AName, 1, Length(EVENT_FIELD)) = EVENT_FIELD);
end;

// X an T als ganze rechte Seite einer Zuweisung - auch in einer Huelle
// (AFirst..ALast, WrappedAt: 'FCurrent := TFoo(X);') - an keinen lokalen
// Namen ('FCurrent := X;') oder als Methodenzeiger 'X.M' an ein Ereignis
// ('Btn.OnClick := X.Handler;'). '' oder der Grund.
function AssignReason(AMap: TRdxCodeMap;
  const T, AFirst, ALast: TRdxToken): string;
var
  A, N, M, Target : TRdxToken;
begin
  Result := '';
  A := Before(AMap, AFirst);
  if A.Low <> ':=' then Exit;
  N := After(AMap, ALast);
  M := After(AMap, N);
  if (N.Low = '.') and M.IsWord
     and EndsStatement(AMap, After(AMap, M), M) then
  begin
    Target := Before(AMap, A);
    if Target.IsWord and IsEventName(TokText(AMap, Target)) then
      Result := Format('Methodenzeiger %s.%s an %s in Zeile %d - %s',
        [TokText(AMap, T), TokText(AMap, M), TokText(AMap, Target), T.Line,
        R_HELD]);
    Exit;
  end;
  if not EndsStatement(AMap, N, ALast) then Exit;
  Result := NonLocalTarget(AMap, A, T);
  if Result <> '' then
    Result := Format('%s wird in Zeile %d an %s weitergegeben (kein lokaler '
      + 'Name der Routine) - %s', [TokText(AMap, T), T.Line, Result, R_HELD]);
end;

// Weitergabe ohne Ausstieg (s. Kopf): X an T wird festgehalten - '@X',
// Argument eines Speicher-Aufrufs, Zuweisung an keinen lokalen Namen,
// Methodenzeiger an ein Ereignis, auch in einer Huelle (WrappedAt). Im
// Fehlerfall gaebe finally X frei, waehrend der Halter es noch kennt. ''
// oder der Grund.
function HandOverReason(AMap: TRdxCodeMap; const T, APrev: TRdxToken): string;
var
  First, Last : TRdxToken;
begin
  if APrev.Low = '@' then
    Exit(Format('@%s in Zeile %d - ein Zeiger bzw. Methodenzeiger auf das '
      + 'Objekt verlaesst den Bereich; %s', [TokText(AMap, T), T.Line,
      R_HELD]));
  WrappedAt(AMap, T, First, Last);
  Result := CallArgReason(AMap, T, First, Last);
  if Result = '' then
    Result := AssignReason(AMap, T, First, Last);
end;

end.
