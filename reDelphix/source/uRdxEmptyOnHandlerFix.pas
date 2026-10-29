unit uRdxEmptyOnHandlerFix;

// reDelphix - Editorhilfe SCA159 EmptyOnHandler, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11):
//   'on E: T do ;'          -> 'on E: T do raise;'
//   'on E: T do begin end;' -> 'on E: T do begin raise; end;'
//   (begin und end auf eigenen Zeilen: 'raise;' kommt als eigene Zeile eine
//   Stufe tiefer dazwischen).
// Der leere Handler schluckt die Ausnahme still; mit 'raise;' laeuft sie
// weiter nach aussen. Das AENDERT das Verhalten (Changes: True, der Hinweis
// nennt die Folge). Der Detektor bleibt unveraendert (Entscheid E9).
//
// WAS DER DETEKTOR MELDET (uEmptyOnHandler): auf der Text-Sicht OHNE
// Kommentare und Strings 'on [E:] T do' mit ';' oder 'begin end [;]'
// dahinter, Zeilen und Leerraum beliebig; die Meldung 'Typed exception
// handler on T has empty body - silent failure' traegt Zeile des 'on', aber
// keine Spalte. EAbort meldet er nie. Weil er Kommentare ausblendet, meldet
// er auch 'on E: T do ; // darf ignoriert werden' - die Hilfe nicht.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * auf der gemeldeten Zeile steht kein Handler 'on [E:] T do' mit leerem
//     Rumpf (Zeile verschoben, Rumpf inzwischen gefuellt) - oder der Typ
//     heisst anders als in der Meldung;
//   * mehr als ein 'on'-Handler auf der Zeile (der Fund koennte jeden
//     meinen);
//   * das 'on' steht nicht am Anfang eines Handlers (davor weder except
//     noch ';');
//   * Kommentar oder Direktive im Handler - von 'on' bis hinter das ';'
//     bzw. end, davor auf der Zeile oder dahinter auf der Zeile: ein
//     Kommentar ist Absicht ('// Abbruch ist hier gewollt');
//   * der Kopf 'on E: T do' steht nicht auf einer Zeile, das ';' weder auf
//     der Zeile des 'do' noch allein am Anfang der Zeile darunter (rwE30,
//     jvcl JvParameterList.pas:977 'on E: EConvertError do' / '  ;' -
//     'raise' kommt dort vor das ';');
//   * der Typ ist EAbort (stilles Abbruchsignal der VCL);
//   * der Handler steht in einem Destruktor bzw. BeforeDestruction
//     (DestructorReason, rwE30 HeidiSQL dbconnection.pas:10202): 'raise;'
//     ueberspraenge den Rest (inherited) und liesse eine Exception aus dem
//     Destruktor;
//   * die Routine ist eine Funktion, die den Fehler ueber ihr Ergebnis
//     meldet - 'Result := False' vor dem try, 'Result := True' auf oberster
//     Ebene des try-Teils (TryParseReason, rwE31 Stufe 3: issrc
//     Compiler.SetupCompiler.pas:2100 StrToInteger64, 'Returns True if
//     successful, or False if ... an overflow occurred'): 'raise;' braeche
//     den Vertrag fuer jeden Aufrufer, der nur das Ergebnis prueft;
//   * der try-Teil ist eine einzige Freigabe (Free, PQfinish,
//     sqlite3_finalize, Close ... - ReleaseGuardReason, rwE30 HeidiSQL
//     dbconnection.pas:2928/2968): der Fehler beim Freigeben wird mit
//     Absicht geschluckt, damit das Aufraeumen danach laeuft;
//   * hinter dem try..except folgt im selben Block die Freigabe zu einer
//     Sperre vor dem try (BeginUpdate/EndUpdate, Lock/Unlock ... -
//     CleanupReason): 'raise;' ueberspraenge sie, es gibt kein finally
//     (rwE29, HeidiSQL table_editor.pas:3209 - die ListView bliebe in
//     BeginUpdate).
// Der Rumpf 'begin end' darf ueber Zeilen gehen, wenn dazwischen nur
// Leerraum steht.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Die Gruende als englische msgids (die Tests pruefen sie mit _()).
  R_EOH_MOVED     = 'no empty "on ... do" handler at the reported place';
  R_EOH_MANY      = 'several "on ... do" handlers on this line - the '
    + 'finding could mean any of them';
  R_EOH_CONTEXT   = 'the "on" does not start a handler of an except block';
  R_EOH_COMMENT   = 'comment or directive in or beside the handler - '
    + 'intent, no help';
  R_EOH_LAYOUT    = 'the handler head is not on one line, or the ";" is not '
    + 'on the line of "do"';
  R_EOH_ABORT     = 'EAbort is swallowed on purpose - "raise;" would show '
    + 'the abort';
  R_EOH_CLEANUP   = 'after the try..except, %s (line %d) undoes %s from '
    + 'before the try - "raise;" would skip it (no finally)';
  R_EOH_DESTRUCTOR = 'the handler is in %s - "raise;" would skip the rest '
    + 'of it (inherited, freeing) and let an exception leave the destructor';
  R_EOH_RELEASE   = 'the try only releases (%s) - an error while freeing or '
    + 'closing is swallowed on purpose so that the cleanup after it still '
    + 'runs; "raise;" would skip it';
  R_EOH_TRYPARSE  = 'the function reports the failure through its result '
    + '(Result := False in line %d before the try, Result := True in line %d '
    + 'in the try part) - "raise;" would break callers that only check the '
    + 'result';

type
  // Der Planer von SCA159 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxEmptyOnHandlerFix = class
  public
    // ALine ist die Zeile des 'on' (die Meldung traegt keine Spalte); aus
    // AMessage wird nur der Typname gelesen, falls vorhanden. Liefert die
    // eine Ersetzung oder den Grund.
    class function Reraise(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxBlocks,        // BeginBodyAround (DestructorReason)
  uRdxText;          // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_159 = 'sca159';
  // Davor beginnt ein Handler.
  HANDLER_PREV: array[0..1] of string = ('except', ';');
  KW_ON    = 'on';
  KEY_HAND = 'handler on ';
  KEY_HAS  = ' has empty body';
  RAISE_INLINE = ' raise;';
  RAISE_BLOCK  = ' raise; ';
  RAISE_STMT   = 'raise;';
  // Sperre vor dem try und ihre Freigabe hinter dem except (CleanupReason),
  // je Index ein Paar.
  PAIR_OPEN: array[0..6] of string = ('beginupdate', 'lock', 'enter',
    'acquire', 'beginwrite', 'beginread', 'disablecontrols');
  PAIR_CLOSE: array[0..6] of string = ('endupdate', 'unlock', 'leave',
    'release', 'endwrite', 'endread', 'enablecontrols');
  // Ein Aufruf, dessen Name so endet, gibt etwas frei (ReleaseGuardReason):
  // 'Free', 'FreeAndNil', 'PQfinish', 'sqlite3_finalize', 'CloseHandle' ...
  RELEASE_ENDS: array[0..13] of string = ('free', 'freeandnil', 'finish',
    'finalize', 'close', 'closehandle', 'release', 'disconnect', 'destroy',
    'dispose', 'freemem', 'freelibrary', 'unload', 'shutdown');
  // Routinen, in denen ein Objekt abgebaut wird (DestructorReason).
  TEARDOWN_NAMES: array[0..0] of string = ('beforedestruction');

type
  // Ein Handler-Kopf 'on [E:] T do' auf einer Zeile.
  TOnHead = record
    OnTok   : TRdxToken;
    TypeTok : TRdxToken;
    DoTok   : TRdxToken;
  end;

  // Der leere Rumpf hinter 'do': Form A (';') oder Form B ('begin end').
  TEmptyBody = record
    IsBlock : Boolean;
    First   : TRdxToken;   // ';' bzw. begin
    Last    : TRdxToken;   // ';' bzw. end
  end;

// Der Typname aus der Meldung ('Typed exception handler on EFoo has empty
// body - ...'); '' ohne.
function TypeFromMessage(const AMessage: string): string;
var
  p, q : Integer;
begin
  Result := '';
  p := Pos(KEY_HAND, AMessage);
  if p = 0 then Exit;
  Inc(p, Length(KEY_HAND));
  q := Pos(KEY_HAS, AMessage);
  if q > p then
    Result := Copy(AMessage, p, q - p);
end;

// Beginnt an T ein Handler-Kopf 'on [E:] T do' - alles auf der Zeile von T?
// Die Form, die der Detektor liest (nur ein einfacher Typname).
function ReadHead(AMap: TRdxCodeMap; const T: TRdxToken;
  out AHead: TOnHead): Boolean;
var
  N1, N2, N3 : TRdxToken;
begin
  Result := False;
  AHead := Default(TOnHead);
  if (T.Low <> KW_ON) or not IsKeywordAfter(T, Before(AMap, T)) then Exit;
  N1 := After(AMap, T);
  if not N1.IsWord or (N1.Line <> T.Line) then Exit;
  N2 := After(AMap, N1);
  if N2.Line <> T.Line then Exit;
  if N2.Low = ':' then
  begin
    N3 := After(AMap, N2);
    if not N3.IsWord or (N3.Line <> T.Line) then Exit;
    AHead.TypeTok := N3;
    AHead.DoTok := After(AMap, N3);
  end
  else
  begin
    AHead.TypeTok := N1;
    AHead.DoTok := N2;
  end;
  AHead.OnTok := T;
  Result := (AHead.DoTok.Low = 'do') and (AHead.DoTok.Line = T.Line);
end;

// Beginnt an T ein Handler-Kopf (ReadHead; das Praedikat fuer
// CountTokensOnLine)?
function IsHandlerHead(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
var
  H : TOnHead;
begin
  Result := ReadHead(AMap, T, H);
end;

// Genau ein Handler-Kopf auf ALine. '' oder der Grund. Der Lauf ist
// CountTokensOnLine (uRdxCodeMap; bis zur Folgewelle des Wochen-Reviews,
// G09-16, hier ausgeschrieben); den Kopf des letzten Treffers liest
// ReadHead noch einmal - wie bisher steht in AHead der letzte.
function FindHead(AMap: TRdxCodeMap; ALine: Integer;
  out AHead: TOnHead): string;
var
  Hit : TRdxToken;
  n   : Integer;
begin
  AHead := Default(TOnHead);
  n := CountTokensOnLine(AMap, ALine, IsHandlerHead, '', Hit);
  if n > 0 then
    ReadHead(AMap, Hit, AHead);
  Result := '';
  if n = 0 then
    Result := MsgMovedSuffix(_(R_EOH_MOVED))
  else if n > 1 then
    Result := _(R_EOH_MANY);
end;

// Der leere Rumpf hinter dem 'do'. '' oder der Grund.
function ReadBody(AMap: TRdxCodeMap; const AHead: TOnHead;
  out ABody: TEmptyBody): string;
var
  Nx, En : TRdxToken;
begin
  Result := '';
  ABody := Default(TEmptyBody);
  Nx := After(AMap, AHead.DoTok);
  if Nx.Low = ';' then
  begin
    // Das ';' allein am Anfang der Zeile unter dem 'do' (rwE30, jvcl
    // JvParameterList.pas:977) - BuildEdit setzt 'raise' davor.
    if (Nx.Line <> AHead.DoTok.Line)
       and not ((Nx.Line = AHead.DoTok.Line + 1) and FirstOnLine(AMap, Nx)) then
      Exit(_(R_EOH_LAYOUT));
    ABody.First := Nx;
    ABody.Last := Nx;
    Exit;
  end;
  En := After(AMap, Nx);
  if (Nx.Low = 'begin') and (En.Low = 'end')
     and IsKeywordAfter(Nx, AHead.DoTok) and IsKeywordAfter(En, Nx) then
  begin
    ABody.IsBlock := True;
    ABody.First := Nx;
    ABody.Last := En;
  end
  else
    Result := MsgMovedSuffix(_(R_EOH_MOVED));
end;

// Steht 'on' am Anfang eines Handlers, und ist der Typ der gemeldete?
function ContextReason(AMap: TRdxCodeMap; const AHead: TOnHead;
  const AMessage: string): string;
var
  Named : string;
begin
  Result := '';
  Named := TypeFromMessage(AMessage);
  if (Named <> '') and not SameText(Named, TokText(AMap, AHead.TypeTok)) then
    Exit(MsgMovedSuffix(_(R_EOH_MOVED)));
  if SameText(AHead.TypeTok.Low, 'eabort') then
    Exit(_(R_EOH_ABORT));
  if not InList(Before(AMap, AHead.OnTok).Low, HANDLER_PREV) then
    Result := _(R_EOH_CONTEXT);
end;

// Kommentar oder Direktive von 'on' bis zum Ende des Handlers, vor dem 'on'
// auf seiner Zeile, in der Zeile DAVOR (ein Kommentar dort nennt meist die
// Absicht) oder hinter dem Ende auf der Zeile?
function CommentReason(AMap: TRdxCodeMap; const AHead: TOnHead;
  const ABody: TEmptyBody): string;
var
  Span : TRefactorSpan;
  Last : TRdxToken;
begin
  Result := '';
  Last := ABody.Last;
  Span := TRefactorSpan.Make(SPAN_159, AHead.OnTok.Line, AHead.OnTok.Col,
    Last.Line, Last.EndCol);
  if CommentInRange(AMap, Span)
     or DirectiveInLines(AMap, AHead.OnTok.Line, Last.Line)
     or AMap.HasComment(AHead.OnTok.Line, 1, AHead.OnTok.Col - 1)
     or ((AHead.OnTok.Line > 1)
       and AMap.HasComment(AHead.OnTok.Line - 1, 1,
         Length(AMap.Raw(AHead.OnTok.Line - 1))))
     or AMap.HasComment(Last.Line, Last.EndCol, Length(AMap.Raw(Last.Line))) then
    Result := _(R_EOH_COMMENT);
end;

// Ist T ein Aufruf des Namens ALow - ein Wort hinter '.' oder mit ';' bzw.
// '(' dahinter (nicht 'X := Lock')?
function IsCallOf(AMap: TRdxCodeMap; const T: TRdxToken;
  const AList: array of string; out AIndex: Integer): Boolean;
var
  i : Integer;
  N : string;
begin
  Result := False;
  AIndex := -1;
  if not T.IsWord then Exit;
  for i := 0 to High(AList) do
    if T.Low = AList[i] then
      AIndex := i;
  if AIndex < 0 then Exit;
  N := After(AMap, T).Low;
  Result := (Before(AMap, T).Low = '.') or (N = ';') or (N = '(');
end;

// Hinter dem try..except des Handlers folgt im selben Block die Freigabe
// (PAIR_CLOSE) zu einer Sperre (PAIR_OPEN) vor dem try - 'raise;'
// ueberspraenge sie. Rueckwaerts vom 'on' zum except und zu seinem try
// (ganze Bloecke uebersprungen), weiter rueckwaerts bis zum Anfang des
// umgebenden Blocks nach Sperren; vorwaerts vom 'on' zum end des except
// und weiter bis zum Ende des umgebenden Blocks nach der Freigabe.
// '' oder der Grund.
// Rueckwaerts vom 'on' das except und das try dieses Handlers (ganze
// Bloecke uebersprungen). False, wenn vorher ein Block oeffnet oder die
// Datei beginnt - die Lage ist dann unklar.
function TryOfHandler(AMap: TRdxCodeMap; const AHead: TOnHead;
  out ATry, AExcept: TRdxToken): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  ATry := Default(TRdxToken);
  AExcept := Default(TRdxToken);
  T := Before(AMap, AHead.OnTok);
  Depth := 0;
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsKeywordAfter(T, P) then
    begin
      if T.Low = 'end' then
        Inc(Depth)
      else if IsEndOpener(T.Low) then
      begin
        if (Depth = 0) and (T.Low = 'try') then
          Break;
        if Depth = 0 then
          Exit;   // ein Block oeffnet vor dem try - Lage unklar
        Dec(Depth);
      end
      else if (Depth = 0) and (T.Low = 'except') then
        AExcept := T;
    end;
    T := P;
  end;
  ATry := T;
  Result := (T.Low = 'try') and (AExcept.Low <> '');
end;

// Steht der Handler in einem Destruktor bzw. BeforeDestruction (der
// innerste Rumpf um das 'on')? 'raise;' ueberspraenge den Rest - meist
// 'inherited;' - und liesse eine Exception aus Free/Destroy (rwE30,
// HeidiSQL dbconnection.pas:10202 TSQLiteGridRows.Destroy). '' oder der
// Grund.
function DestructorReason(AMap: TRdxCodeMap; const AHead: TOnHead): string;
var
  R : TRdxRoutine;
begin
  Result := '';
  if BeginBodyAround(AMap, AHead.OnTok, R) <> rbfFound then Exit;
  if R.Keyword.Low = 'destructor' then
    Result := _(R_EOH_DESTRUCTOR, [R.Name])
  else if (Length(R.Parts) > 0) and InList(R.Parts[High(R.Parts)], TEARDOWN_NAMES) then
    Result := _(R_EOH_DESTRUCTOR, [R.Name]);
end;

// Ein Schritt der Tiefe vorwaerts im try-Teil (ReleaseGuardReason,
// TryParseReason): Bloecke (END_OPENERS und repeat..until) und Klammern
// zaehlen. True, wenn T die Tiefe aenderte.
function StepDepth(const T, P: TRdxToken; var ADepth: Integer): Boolean;
begin
  Result := True;
  if IsKeywordAfter(T, P) and (IsEndOpener(T.Low) or (T.Low = 'repeat')) then
    Inc(ADepth)
  else if IsKeywordAfter(T, P) and ((T.Low = 'end') or (T.Low = 'until')) then
    Dec(ADepth)
  else if (T.Low = '(') or (T.Low = '[') then
    Inc(ADepth)
  else if (T.Low = ')') or (T.Low = ']') then
    Dec(ADepth)
  else
    Result := False;
end;

// Steht an T die ganze Zuweisung 'Name := AValue' - Name einer aus ANames
// ('result' oder der Name der Funktion), nicht hinter '.', '&' oder '@',
// dahinter das Ende der Anweisung?
function ResultAssignAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const ANames: array of string; const AValue: string): Boolean;
var
  A, V : TRdxToken;
begin
  Result := False;
  if not T.IsWord or not InList(T.Low, ANames)
     or InList(Before(AMap, T).Low, IDENT_PREFIXES) then
    Exit;
  A := After(AMap, T);
  if A.Low <> ':=' then Exit;
  V := After(AMap, A);
  Result := (V.Low = AValue)
    and InList(After(AMap, V).Low, [';', 'end', 'except', 'finally', 'else']);
end;

// Gibt der Aufruf an T etwas frei (RELEASE_ENDS) - ein Name mit '(' oder
// ';' dahinter bzw. hinter einem '.'?
function IsReleaseCall(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  i : Integer;
  N : string;
begin
  Result := False;
  if not T.IsWord then Exit;
  N := After(AMap, T).Low;
  if not ((Before(AMap, T).Low = '.') or (N = ';') or (N = '(')
     or (N = 'except')) then
    Exit;
  for i := 0 to High(RELEASE_ENDS) do
    if (Length(T.Low) >= Length(RELEASE_ENDS[i]))
       and (Copy(T.Low, Length(T.Low) - Length(RELEASE_ENDS[i]) + 1, MaxInt)
         = RELEASE_ENDS[i]) then
      Exit(True);
end;

// Ist der try-Teil des Handlers EINE Anweisung, die etwas freigibt
// ('try FLib.PQfinish(FHandle); except on E: EAccessViolation do; end;',
// auch 'if FActive then FLib.PQfinish(FHandle);' - rwE30 HeidiSQL
// dbconnection.pas:2928/2968)? Der Fehler beim Freigeben wird mit Absicht
// geschluckt: danach folgt das weitere Aufraeumen (FHandle := nil,
// EndSSHTunnel), das 'raise;' uebersprange. '' oder der Grund.
function ReleaseGuardReason(AMap: TRdxCodeMap; const AHead: TOnHead): string;
var
  TryTok, ExceptTok, T, P, Hit : TRdxToken;
  Depth                        : Integer;
begin
  Result := '';
  if not TryOfHandler(AMap, AHead, TryTok, ExceptTok) then Exit;
  Hit := Default(TRdxToken);
  Depth := 0;
  T := After(AMap, TryTok);
  while (T.Low <> '') and TokBefore(T, ExceptTok) do
  begin
    P := Before(AMap, T);
    if not StepDepth(T, P, Depth) then
    begin
      // Ein ';' auf oberster Ebene vor dem letzten: mehr als eine
      // Anweisung.
      if (T.Low = ';') and (Depth = 0)
         and not SameTok(After(AMap, T), ExceptTok) then
        Exit;
      if (Hit.Low = '') and IsReleaseCall(AMap, T) then
        Hit := T;
    end;
    T := After(AMap, T);
  end;
  if Hit.Low <> '' then
    Result := _(R_EOH_RELEASE, [TokText(AMap, Hit)]);
end;

// Meldet die Funktion um den Handler den Fehler ueber ihr Ergebnis? Vor
// dem try (ab dem begin der Routine) 'Result := False', im try-Teil auf
// oberster Ebene 'Result := True' (auch mit dem Namen der Funktion statt
// Result) - das Try-Parse-Muster: der leere Handler laesst False stehen,
// und das ist der Vertrag (rwE31 Stufe 3, issrc Compiler.SetupCompiler.pas:
// 2100 StrToInteger64 - 'raise;' machte aus False eine Ausnahme fuer jeden
// Aufrufer, der nur das Ergebnis prueft). '' oder der Grund.
function TryParseReason(AMap: TRdxCodeMap; const AHead: TOnHead): string;
var
  R                         : TRdxRoutine;
  TryTok, ExceptTok, T      : TRdxToken;
  FalseTok, TrueTok         : TRdxToken;
  Depth                     : Integer;
  FnLow                     : string;
begin
  Result := '';
  if BeginBodyAround(AMap, AHead.OnTok, R) <> rbfFound then Exit;
  if (R.Keyword.Low <> 'function') or (Length(R.Parts) = 0) then Exit;
  if not TryOfHandler(AMap, AHead, TryTok, ExceptTok) then Exit;
  FnLow := R.Parts[High(R.Parts)];
  FalseTok := Default(TRdxToken);
  T := After(AMap, R.Body);
  while (T.Low <> '') and TokBefore(T, TryTok) do
  begin
    if ResultAssignAt(AMap, T, ['result', FnLow], 'false') then
      FalseTok := T;
    T := After(AMap, T);
  end;
  if FalseTok.Low = '' then Exit;
  TrueTok := Default(TRdxToken);
  Depth := 0;
  T := After(AMap, TryTok);
  while (T.Low <> '') and TokBefore(T, ExceptTok) do
  begin
    if not StepDepth(T, Before(AMap, T), Depth) and (Depth = 0)
       and ResultAssignAt(AMap, T, ['result', FnLow], 'true') then
      TrueTok := T;
    T := After(AMap, T);
  end;
  if TrueTok.Low <> '' then
    Result := _(R_EOH_TRYPARSE, [FalseTok.Line, TrueTok.Line]);
end;

function CleanupReason(AMap: TRdxCodeMap; const AHead: TOnHead): string;
var
  T, P      : TRdxToken;
  Depth, i  : Integer;
  Opened    : array[0..6] of Boolean;     // je Index von PAIR_OPEN
  OpenTok   : array[0..6] of TRdxToken;
  ExceptTok : TRdxToken;
begin
  Result := '';
  // Rueckwaerts: das except und das try dieses Handlers.
  if not TryOfHandler(AMap, AHead, T, ExceptTok) then Exit;
  // Weiter rueckwaerts bis zum Anfang des umgebenden Blocks: Sperren.
  for i := 0 to High(Opened) do
    Opened[i] := False;
  T := Before(AMap, T);
  Depth := 0;
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsKeywordAfter(T, P) and (T.Low = 'end') then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and IsEndOpener(T.Low) then
    begin
      if Depth = 0 then
        Break;
      Dec(Depth);
    end
    else if (Depth = 0) and IsCallOf(AMap, T, PAIR_OPEN, i) then
    begin
      Opened[i] := True;
      OpenTok[i] := T;
    end;
    T := P;
  end;
  // Vorwaerts: das end des except, dann bis zum Ende des Blocks.
  T := After(AMap, AHead.OnTok);
  Depth := 0;
  while T.Low <> '' do
  begin
    if IsKeywordAfter(T, Before(AMap, T)) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, Before(AMap, T)) and (T.Low = 'end') then
    begin
      if Depth = 0 then
        Break;
      Dec(Depth);
    end;
    T := After(AMap, T);
  end;
  if T.Low <> 'end' then Exit;
  T := After(AMap, T);
  Depth := 0;
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsKeywordAfter(T, P) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and ((T.Low = 'end') or (T.Low = 'until')) then
    begin
      if Depth = 0 then
        Exit;
      Dec(Depth);
    end
    else if (Depth = 0) and IsCallOf(AMap, T, PAIR_CLOSE, i) and Opened[i] then
      Exit(_(R_EOH_CLEANUP, [TokText(AMap, T), T.Line,
        TokText(AMap, OpenTok[i])]));
    T := After(AMap, T);
  end;
end;

// Die Ersetzung: Form A hinter dem 'do', Form B in 'begin end'.
function BuildEdit(AMap: TRdxCodeMap; const AHead: TOnHead;
  const ABody: TEmptyBody; out AEdit: TRdxEdit): string;
var
  Bg, En           : TRdxToken;
  EndIndent, Inner : string;
  Last1            : string;
begin
  Result := '';
  AEdit := Default(TRdxEdit);
  if not ABody.IsBlock and (ABody.Last.Line <> AHead.DoTok.Line) then
  begin
    // Das ';' auf der Zeile unter dem 'do' (ReadBody): 'raise' davor, die
    // Zeilen bleiben.
    AEdit.Span := TRefactorSpan.Make(SPAN_159, ABody.Last.Line,
      ABody.Last.Col, ABody.Last.Line, ABody.Last.EndCol);
    AEdit.NewText := RAISE_STMT;
  end
  else if not ABody.IsBlock then
  begin
    AEdit.Span := TRefactorSpan.Make(SPAN_159, AHead.DoTok.Line,
      AHead.DoTok.EndCol, ABody.Last.Line, ABody.Last.EndCol);
    AEdit.NewText := RAISE_INLINE;
  end
  else
  begin
    Bg := ABody.First;
    En := ABody.Last;
    if Bg.Line = En.Line then
    begin
      AEdit.Span := TRefactorSpan.Make(SPAN_159, Bg.Line, Bg.EndCol, En.Line,
        En.Col);
      AEdit.NewText := RAISE_BLOCK;
    end
    else
    begin
      // Der Start liegt auf dem letzten Zeichen von begin: eine Spanne darf
      // nicht hinter dem Zeilenende beginnen.
      EndIndent := Copy(AMap.Raw(En.Line), 1, En.Col - 1);
      if not FirstOnLine(AMap, En) then
        Exit(_(R_EOH_LAYOUT));
      Inner := EndIndent + IndentStep(EndIndent, '');
      Last1 := Copy(AMap.Raw(Bg.Line), Bg.EndCol - 1, 1);
      AEdit.Span := TRefactorSpan.Make(SPAN_159, Bg.Line, Bg.EndCol - 1,
        En.Line, En.Col);
      AEdit.NewText := Last1 + #10 + Inner + RAISE_STMT + #10 + EndIndent;
    end;
  end;
  AEdit.Expected := RangeText(AMap, AEdit.Span);
end;

{ TRdxEmptyOnHandlerFix }

class function TRdxEmptyOnHandlerFix.Reraise(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Head : TOnHead;
  Body : TEmptyBody;
begin
  AEdit := Default(TRdxEdit);
  AReason := FindHead(AMap, ALine, Head);
  if AReason = '' then
    AReason := ReadBody(AMap, Head, Body);
  if AReason = '' then
    AReason := ContextReason(AMap, Head, AMessage);
  if AReason = '' then
    AReason := CommentReason(AMap, Head, Body);
  if AReason = '' then
    AReason := DestructorReason(AMap, Head);
  if AReason = '' then
    AReason := TryParseReason(AMap, Head);
  if AReason = '' then
    AReason := ReleaseGuardReason(AMap, Head);
  if AReason = '' then
    AReason := CleanupReason(AMap, Head);
  if AReason = '' then
    AReason := BuildEdit(AMap, Head, Body, AEdit);
  Result := AReason = '';
  if not Result then
    AEdit := Default(TRdxEdit);
end;

end.
