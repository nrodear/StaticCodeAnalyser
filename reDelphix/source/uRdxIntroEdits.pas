unit uRdxIntroEdits;

// reDelphix - Code-Aktion "Lokale Konstante einfuehren" (Refactoring ohne
// Fund; bis E26 "Lokale Variable einfuehren"): was die Aktion am Puffer
// aendert, OHNE ToolsAPI (laeuft auch unter FPC, Pruefstand
// tools\fpc-pruefstand): der Text beim Start (Zeilen, Byte-Anfaenge,
// Zeilenenden), das Ziel an der Caret-Position samt den Pruefungen ueber
// die Zeile hinaus (mehrzeilige Strings und Kommentare, asm,
// initialization, FPC-Weiche, Direktiven, Kommentargrenzen eines
// begin..end), die Ersetzungen des Writers fuer C1h und das Ende des
// Sync-Blocks. Der IDE-Teil wendet genau diese Ersetzungen mit EINEM
// IOTAEditWriter an; ApplyIntroEdits stellt den Writer nach - so pruefen
// die Tests den Text, der am Ende im Puffer steht, nicht nur Offsets.
//
// 1:1 aus dem Labor VarNameProject (uVnpEdits, Stand 2026-10-14 nach dem
// Review F/B vom 2026-10-13, Entscheid E24: erst der im Labor gemessene
// Stand, die Zusammenlegung mit uRdxCodeMap/uRdxBufferMath folgt
// spaeter), nur Variante C1h -
// Loeschen und Zurueckschreiben der Anweisung und die Template-Datei fuer
// D1 (Live Template) bleiben im Labor. Der IDE-Teil (im Labor
// uVnpIntroduce) folgt, wenn das Labor Enter und Esc geklaert hat (E25:
// Esc zerstoert im Sync Edit der IDE Text, UI-Test 2026-10-11).
// ApplyIntroEdits heisst im Labor ApplyByteEdits; uRdxBufferMath hat eine
// gleichnamige Routine mit anderer Signatur. Die Zeilenenden je Zeile
// (Ends/RowEol, Eol als Rueckfall = erstes Zeilenende) entsprechen
// uRdxBufferMath.BufferEol; ein einzelnes CR ist hier kein Zeilenende
// (BufferMath: doch) - bis zur Zusammenlegung bewusst so belassen.
//
// Positionen: Zeilen 1-basiert; Spalten 1-basierte Zeichenspalten der
// Zeile (UTF-16, wie uRdxIntroPlan); Offsets UTF-8-Bytes ab Pufferanfang -
// so zaehlen IOTAEditReader und IOTAEditWriter.

interface

uses
  System.SysUtils, uRdxIntroPlan;

type
  // Der Puffer beim Start. Eine Zeile je Zeilenanfang: LF beendet eine
  // Zeile, ein CR direkt davor - oder als letztes Byte des Puffers -
  // gehoert zum Zeilenende. Endet der Puffer mit einem LF, ist die letzte
  // Zeile leer. Ein BOM am Anfang bleibt Teil der ersten Zeile (U+FEFF,
  // Starts[0] = 0), die Byte-Offsets zaehlen seine drei Bytes mit.
  // Zeilenenden: jede Zeile traegt ihr eigenes (Ends), eingefuegte Zeilen
  // bekommen das der Zeile, vor die sie kommen (RowEol) - 'CR LF, sobald
  // eines vorkommt' mischte LF-Dateien mit einer einzigen CR-LF-Zeile
  // (Pruefer 2026-10-13, Minor 5). Eol ist nur der Rueckfall fuer eine
  // Zeile ohne eigenes Ende (die letzte) und fuer D1: das Ende der ERSTEN
  // Zeile, die eines hat (wie uRdxBufferMath.BufferEol in reDelphix, der
  // Zusammenlegung wegen); ohne jedes Zeilenende CR LF, das Zeilenende
  // der IDE unter Windows. Ein einzelnes CR am Pufferende zaehlt als
  // Zeilenende der letzten Zeile, Ends traegt dafuer '' (kein LF).
  TRdxIntroText = record
    Text   : string;            // der ganze Puffer
    Lines  : TArray<string>;    // Zeilen ohne Zeilenende
    Starts : TArray<Integer>;   // Byte-Offset jedes Zeilenanfangs
    Ends   : TArray<string>;    // Zeilenende je Zeile: #13#10, #10 oder ''
    Eol    : string;            // Rueckfall: erstes Zeilenende, sonst CR LF
  end;

  // Wo die Hilfe arbeitet und wo der Name nach dem Schreiben steht.
  TRdxIntroTarget = record
    FileName  : string;    // setzt der IDE-Teil
    SourceRow : Integer;   // Zeile der Anweisung VOR dem Schreiben
    PrevRow   : Integer;   // Zeile mit Code darueber (0 = keine)
    DeclRow   : Integer;   // Zeile der Deklaration NACH dem Schreiben
    UseRow    : Integer;   // Zeile der Anweisung NACH dem Schreiben
    Name      : string;
    Plan      : TRdxIntroPlan;  // Plan.Ok = False: Plan.Reason sagt, warum nicht
  end;

  // Eine Ersetzung im Puffer: ab Offset Len Bytes verwerfen, Text einfuegen.
  TRdxIntroByteEdit = record
    Offset : Integer;
    Len    : Integer;
    Text   : string;
  end;
  TRdxIntroByteEdits = TArray<TRdxIntroByteEdit>;

// Der Text zu den Pufferbytes (wie IOTAEditReader sie liefert).
function TextOf(const ABytes: TBytes): TRdxIntroText;

// Das Zeilenende der Zeile ARow (1-basiert): ihr eigenes (Ends) oder, wenn
// sie keines hat, AText.Eol.
function RowEol(const AText: TRdxIntroText; ARow: Integer): string;

// Die naechste Zeile ueber ARow mit Code (0 am Dateianfang); leere und
// reine Kommentarzeilen zaehlen nicht.
function PrevCodeRow(const AText: TRdxIntroText; ARow: Integer): Integer;

// Das Ziel fuer den Caret in Zeile ARow, Zeichenspalte ACol: freier Name
// ANameBase + '01', '02' ..., Plan, Zeilen nach dem Schreiben.
// Result.Plan.Ok = False mit Result.Plan.Reason, wenn es nichts zu tun
// gibt. Ueber die Zeile hinaus prueft TargetAt den Zusammenhang: kein
// mehrzeiliger String oder Kommentar, kein asm-Block, kein
// initialization-Abschnitt, keine FPC-Weiche in der Datei, keine
// Direktive zwischen der Zeile darueber und der Anweisung und keine auf
// der Anweisungszeile, und bei begin..end keine offene Kommentargrenze
// und kein Bedingungsausdruck.
function TargetAt(const AText: TRdxIntroText; ARow, ACol: Integer;
  const ANameBase: string): TRdxIntroTarget;

// C1h: die Ersetzungen EINES Writers, aufsteigend - die Deklaration ueber
// die Anweisung, die Literale der Zeile durch den Namen; bei Plan.Wrap
// 'begin' an den Anfang der Zeile nach der Zweigzeile und 'end;' an den
// Anfang der Zeile nach der Anweisung, beide mit der Einrueckung der
// Zweigzeile. Jede neue Zeile bekommt das Zeilenende der Zeile, vor die
// sie kommt (RowEol). Vorbedingung: ATarget.Plan.Ok - sonst nil (ein
// abgelehntes Ziel hat keine Zeilen).
function IntroduceEdits(const AText: TRdxIntroText;
  const ATarget: TRdxIntroTarget): TRdxIntroByteEdits;

// C1h: wo der Sync-Block endet - Zeile und Zeichenspalte (exklusiv) im
// Puffer NACH dem Schreiben (Vorbedingung wie IntroduceEdits: Plan.Ok -
// sonst 0 und 0). Normal direkt hinter der letzten Verwendung:
// so koppelt die IDE moeglichst wenige andere Bezeichner. Steht davor in
// der Zeile Nicht-ASCII, endet er am Anfang der Folgezeile, wo Zeichen und
// Bytes gleich zaehlen: SyncEditBlock liest das Blockende als UTF-8-Bytes
// (UI-Test 2026-10-11, Fall 6: Block bis 25:52 gemeldet, danach Caret
// 25:48 und keine Sitzung - das zweite MagicNr01 lag nicht mehr ganz im
// Block). Ohne Folgezeile rueckt die Spalte um die Mehrbytes weiter.
procedure SyncBlockEnd(const AText: TRdxIntroText; const ATarget: TRdxIntroTarget;
  out ARow, ACol: Integer);

// Der IOTAEditWriter nachgestellt: Bytes bis Offset uebernehmen, Len Bytes
// verwerfen, Text als UTF-8 einfuegen - der Reihe nach. EArgumentException,
// wenn eine Ersetzung vor dem Ende der vorigen beginnt (der Writer kann
// nicht zurueck), Len < 0 ist oder sie aus dem Puffer ragt.
function ApplyIntroEdits(const ABytes: TBytes;
  const AEdits: TRdxIntroByteEdits): TBytes;

implementation

const
  BYTE_LF = 10;
  BYTE_CR = 13;
  // So viele Quotes oeffnen mindestens einen mehrzeiligen String (Delphi 12).
  MIN_MULTILINE_QUOTES = 3;

// Ende (exklusiv, in Bytes) der Zeile n ohne ihr Zeilenende und das
// Zeilenende selbst: vor ihrem LF bzw. am Pufferende, ohne das CR davor
// (ein CR als letztes Byte des Puffers gehoert zum Zeilenende, AEnd bleibt
// dann '' - kein LF).
procedure RowBounds(const ABytes: TBytes; const AStarts: TArray<Integer>;
  n: Integer; out AStop: Integer; out AEnd: string);
begin
  AEnd := '';
  AStop := Length(ABytes);
  if n < High(AStarts) then
  begin
    AStop := AStarts[n + 1] - 1;
    AEnd := #10;
  end;
  if (AStop > AStarts[n]) and (ABytes[AStop - 1] = BYTE_CR) then
  begin
    Dec(AStop);
    if AEnd <> '' then
      AEnd := #13#10;
  end;
end;

function TextOf(const ABytes: TBytes): TRdxIntroText;
var
  i, n, Stop : Integer;
begin
  Result := Default(TRdxIntroText);
  if Length(ABytes) > 0 then
    Result.Text := TEncoding.UTF8.GetString(ABytes);
  // Erst die LFs zaehlen, dann EIN SetLength: die Verkettung je LF kopierte
  // das Array jedes Mal (quadratisch; der SCA014-Quick-Fix baut den Text je
  // Fund neu - Wochen-Review 2026-10-21).
  n := 1;
  for i := 0 to High(ABytes) do
    if ABytes[i] = BYTE_LF then
      Inc(n);
  SetLength(Result.Starts, n);
  Result.Starts[0] := 0;
  n := 1;
  for i := 0 to High(ABytes) do
    if ABytes[i] = BYTE_LF then
    begin
      Result.Starts[n] := i + 1;
      Inc(n);
    end;
  SetLength(Result.Lines, Length(Result.Starts));
  SetLength(Result.Ends, Length(Result.Starts));
  Result.Eol := '';
  for n := 0 to High(Result.Starts) do
  begin
    RowBounds(ABytes, Result.Starts, n, Stop, Result.Ends[n]);
    if (Result.Eol = '') and (Result.Ends[n] <> '') then
      Result.Eol := Result.Ends[n];
    // Leere Zeile ohne GetString: dessen Index laege sonst am Pufferende.
    Result.Lines[n] := '';
    if Stop > Result.Starts[n] then
      Result.Lines[n] := TEncoding.UTF8.GetString(ABytes, Result.Starts[n],
        Stop - Result.Starts[n]);
  end;
  if Result.Eol = '' then
    Result.Eol := #13#10;
end;

function RowEol(const AText: TRdxIntroText; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow <= Length(AText.Ends)) then
    Result := AText.Ends[ARow - 1];
  if Result = '' then
    Result := AText.Eol;
end;

type
  // Eine Zeile ueber dem Caret, wie TargetAt sie sieht: der Zustand an
  // ihrem Anfang ('c' Code, 'b' in { }, 'p' in (* *), 's' in einem
  // mehrzeiligen String) und ihr Code-Anteil (Strings bleiben, Kommentare
  // fallen weg; eine Inhaltszeile eines mehrzeiligen Strings hat keinen,
  // eine Zeile, die ihn schliesst, den Rest hinter dem Schliesser).
  TRdxIntroRow = record
    State : Char;
    Code  : string;
  end;
  TRdxIntroRows = TArray<TRdxIntroRow>;

// Die Zahl der Quotes, mit denen die (getrimmte) Zeile einen mehrzeiligen
// String oeffnet (Delphi 12: mindestens drei am Zeilenende, der String
// bleibt offen), sonst 0. AState: der Kommentar-Zustand am Zeilenanfang -
// ein ''' in einem Kommentarblock oeffnet nichts.
function OpenerQuotes(const ALine: string; AState: Char): Integer;
var
  i : Integer;
begin
  i := Length(ALine);
  while (i > 0) and (ALine[i] = '''') do
    Dec(i);
  Result := Length(ALine) - i;
  if (Result < MIN_MULTILINE_QUOTES) or not StringOpenAtEnd(ALine, AState) then
    Result := 0;
end;

// Schliesst die (getrimmte) Zeile einen mehrzeiligen String mit AQuotes
// Quotes - genau so viele am Zeilenanfang wie der Oeffner hatte? Eine
// Inhaltszeile, die mit weniger (''' quoted bei einem '''''-String) oder
// mehr Quotes beginnt, schliesst nicht (Pruefer 2026-10-13, Harness 23:
// sonst galt die Folgezeile als Code, und die Deklaration landete IM
// String).
function ClosesWith(const ALine: string; AQuotes: Integer): Boolean;
begin
  Result := (Copy(ALine, 1, AQuotes) = StringOfChar('''', AQuotes))
    and ((Length(ALine) <= AQuotes) or (ALine[AQuotes + 1] <> ''''));
end;

// Der Zustand nach der Zeile ALine, die im Kommentar-Zustand AState
// beginnt: ein offener Kommentar - oder 's' mit AQuotes, wenn die Zeile
// im Code endet und dort einen mehrzeiligen String oeffnet.
function NextState(const ALine: string; AState: Char;
  var AQuotes: Integer): Char;
begin
  Result := CommentStateAfter(ALine, AState);
  if Result <> 'c' then
    Exit;
  AQuotes := OpenerQuotes(Trim(ALine), AState);
  if AQuotes > 0 then
    Result := 's';
end;

// Die Zeilen 1..ACount (hoechstens alle): Zustand am Anfang und Code-
// Anteil, Kommentar- und String-Zustand in EINEM Lauf - fuer Kommentare
// und Strings ueber mehrere Zeilen (Korpus-A/B 2026-10-11: auskommentierter
// Code und Prosa darin sahen aus wie Code; der Zeilen-Leser saehe in einem
// String Code und aenderte ihn still). Eine Inhaltszeile des Strings sieht
// der Kommentar-Leser nicht ('{' im Text vergiftete sonst die Zeilen
// danach), ein ''' in einem Kommentarblock oeffnet keinen String, und
// hinter dem Schliesser geht es im Code weiter - auch mit einem neuen
// Oeffner (''' + '''; Pruefer 2026-10-14, c).
function RowsUpTo(const AText: TRdxIntroText; ACount: Integer): TRdxIntroRows;
var
  i, Quotes : Integer;
  L, T      : string;
  State     : Char;
begin
  Result := nil;
  if ACount > Length(AText.Lines) then
    ACount := Length(AText.Lines);
  SetLength(Result, ACount);
  State := 'c';
  Quotes := 0;
  for i := 0 to ACount - 1 do
  begin
    L := AText.Lines[i];
    Result[i].State := State;
    Result[i].Code := '';
    if State <> 's' then
    begin
      Result[i].Code := CodePartFrom(L, State);
      State := NextState(L, State, Quotes);
      Continue;
    end;
    T := Trim(L);
    if ClosesWith(T, Quotes) then
    begin
      T := Copy(T, Quotes + 1, MaxInt);
      Result[i].Code := CodePart(T);
      State := NextState(T, 'c', Quotes);
    end;
  end;
end;

// Die naechste Zeile ueber ARow mit Code (0 am Dateianfang) in ARows.
function PrevCodeRowIn(const ARows: TRdxIntroRows; ARow: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  i := ARow - 2;
  if i > High(ARows) then
    i := High(ARows);
  while i >= 0 do
  begin
    if Trim(ARows[i].Code) <> '' then
      Exit(i + 1);
    Dec(i);
  end;
end;

function PrevCodeRow(const AText: TRdxIntroText; ARow: Integer): Integer;
begin
  Result := PrevCodeRowIn(RowsUpTo(AText, ARow), ARow);
end;

// Die Zeile ARow (1-basiert) oder '' fuer 0.
function LineOrEmpty(const AText: TRdxIntroText; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow <= Length(AText.Lines)) then
    Result := AText.Lines[ARow - 1];
end;

// Traegt der Text S eine Compiler-Direktive ('{$' oder '(*$')?
function LineHasDirective(const S: string): Boolean;
begin
  Result := (Pos('{$', S) > 0) or (Pos('(*$', S) > 0);
end;

// Steht auf der Zeile darueber AFromRow oder zwischen ihr und der
// Anweisung AToRow eine Compiler-Direktive ({$IFDEF ...})? Dann gilt die
// Zeile darueber nur in einem Zweig der bedingten Uebersetzung: begin und
// end landeten in verschiedenen Zweigen (Korpus-A/B 2026-10-11), und ohne
// Block stuende die Deklaration im anderen Zweig hinter einem 'then'
// ('{$IFDEF A} if B then {$ELSE} Foo; {$ENDIF}' - Pruefer 2026-10-13,
// Harness 7). Die Direktive AUF der Zeile darueber zaehlt mit: die
// Spanne lag strikt dazwischen, und genau dieser Fall stand still hinter
// dem then (Pruefer 2026-10-14, b). Geprueft wird die rohe Zeile - ein
// '{$' in einem String zaehlt auch (lieber ablehnen).
function DirectiveBetween(const AText: TRdxIntroText;
  AFromRow, AToRow: Integer): Boolean;
var
  i : Integer;
begin
  for i := AFromRow - 1 to AToRow - 2 do
    if (i >= 0) and LineHasDirective(AText.Lines[i]) then
      Exit(True);
  Result := False;
end;

// Steht auf der Anweisungszeile selbst eine Direktive? Die Deklaration
// kommt an den ANFANG der Zeile: eine Direktive davor - '{$ENDIF} X :=
// 42;' - stellte sie in den anderen Zweig der bedingten Uebersetzung
// (Wochen-Review 2026-10-21: die Spanne von DirectiveBetween endete vor
// der Anweisungszeile); mit Block (Plan.Wrap) kommt 'end;' hinter das
// Zeilenende, eine Direktive dahinter ('X := 42; {$ENDIF}') laege
// zwischen begin und end. Es zaehlt die GANZE rohe Zeile, auch ohne Block
// und hinter dem Literal ('X := 42; {$IFDEF D} Log; {$ENDIF}'): so streng
// wie das Labor (uVnpEdits.DirectiveBetween bis einschliesslich der
// Anweisungszeile, Review Woche G10-02) - lieber ablehnen, und die Regel
// haengt nicht davon ab, wo die Deklaration genau hinkommt (Folgewelle
// A7, Gleichschritt Labor/Produkt).
function DirectiveOnStatementRow(const AText: TRdxIntroText;
  const ATarget: TRdxIntroTarget): Boolean;
begin
  Result := LineHasDirective(AText.Lines[ATarget.SourceRow - 1]);
end;

// Der Abschnitt, in dem Zeile ARow liegt ('c' Code, 'a' asm-Block, 'i'
// initialization/finalization) - der Code der Zeilen darueber (ARows)
// durch uRdxIntroPlan.SectionStateAfter gefaltet.
function SectionAt(const ARows: TRdxIntroRows; ARow: Integer): Char;
var
  i : Integer;
begin
  Result := 'c';
  for i := 0 to ARow - 2 do
    Result := SectionStateAfter(ARows[i].Code, Result);
end;

// Traegt irgendeine Zeile der Datei eine FPC-Weiche (uRdxIntroPlan.
// LineLooksFpcAware)? Eine Inline-Konstante gibt es in FPC 3.2 nicht -
// sie braeche den FPC-Bau einer Datei, die beide Compiler kennt.
function SourceLooksFpcAware(const AText: TRdxIntroText): Boolean;
var
  L : string;
begin
  for L in AText.Lines do
    if LineLooksFpcAware(L) then
      Exit(True);
  Result := False;
end;

// Was an der Caret-Zeile ARow selbst keinen Code zulaesst - vor dem Plan:
// '' oder der Grund. ARows sind die Zeilen 1..ARow (RowsUpTo).
function ContextReason(const AText: TRdxIntroText; ARow: Integer;
  const ARows: TRdxIntroRows): string;
var
  Section : Char;
begin
  Result := '';
  if ARows[ARow - 1].State = 's' then
    Exit('die Zeile liegt in einem mehrzeiligen String - dort ist kein Code');
  if ARows[ARow - 1].State <> 'c' then
    Exit('die Zeile liegt in einem mehrzeiligen Kommentar - dort ist kein '
      + 'Code');
  Section := SectionAt(ARows, ARow);
  if Section = 'a' then
    Exit('die Zeile liegt in einem asm-Block - dort ist kein Pascal-Code');
  if Section = 'i' then
    Exit('die Zeile liegt im initialization-/finalization-Abschnitt - ob '
      + 'dort eine Inline-Deklaration gilt, ist nicht gemessen');
  if SourceLooksFpcAware(AText) then
    Exit('die Datei traegt eine FPC-Weiche ({$IFDEF FPC}, {$MODE ...}) - '
      + 'eine Inline-Konstante gibt es in FPC 3.2 nicht');
end;

// Die Zeile darueber APrevRow fuer den Plan: roh ab ihrem Kommentar-
// Zustand (beginnt sie in einem Kommentar, ist ihr Code der Teil hinter
// dessen Ende - Pruefer 2026-10-13, Minor 1); schliesst sie einen
// mehrzeiligen String, nur der Code hinter dem Schliesser, als Code-
// Zeile. '' und 'c' fuer 0 (keine Zeile).
procedure PrevForPlan(const AText: TRdxIntroText; const ARows: TRdxIntroRows;
  APrevRow: Integer; out ALine: string; out AState: Char);
begin
  ALine := LineOrEmpty(AText, APrevRow);
  AState := 'c';
  if (APrevRow >= 1) and (APrevRow <= Length(ARows)) then
    AState := ARows[APrevRow - 1].State;
  if AState = 's' then
  begin
    ALine := ARows[APrevRow - 1].Code;
    AState := 'c';
  end;
end;

// Die Einrueckung fuer begin..end um den Zweig der Zweigzeile APrevRow: die
// ihrer rohen Zeile - schliesst sie einen mehrzeiligen String, die der
// Zeile, auf der die Anweisung beginnt (aufwaerts ueber die String-Zeilen
// bis zum Oeffner). PrevForPlan gibt dem Plan dort nur den Code hinter dem
// Schliesser (' then'), und begin..end bekam EIN Leerzeichen Einrueckung
// (Wochen-Review 2026-10-21).
function BranchIndent(const AText: TRdxIntroText; const ARows: TRdxIntroRows;
  APrevRow: Integer): string;
var
  Row : Integer;
  L   : string;
begin
  Row := APrevRow;
  while (Row > 1) and (Row <= Length(ARows)) and (ARows[Row - 1].State = 's') do
    Dec(Row);
  L := LineOrEmpty(AText, Row);
  Result := Copy(L, 1, Length(L) - Length(TrimLeft(L)));
end;

// Der Code der Zeile AFromRow und der Code-Zeilen darueber, von unten nach
// oben (0: leer) - fuer uRdxIntroPlan.IfExpressionAbove.
// Erst zaehlen, dann EIN SetLength (die Verkettung je Zeile war
// quadratisch, Wochen-Review 2026-10-21).
function CodeFromRowUp(const ARows: TRdxIntroRows; AFromRow: Integer): TArray<string>;
var
  Row, n : Integer;
begin
  n := 0;
  Row := AFromRow;
  while Row > 0 do
  begin
    Inc(n);
    Row := PrevCodeRowIn(ARows, Row);
  end;
  SetLength(Result, n);
  n := 0;
  Row := AFromRow;
  while Row > 0 do
  begin
    Result[n] := ARows[Row - 1].Code;
    Inc(n);
    Row := PrevCodeRowIn(ARows, Row);
  end;
end;

// Gehoert das then/else am Ende der Zweigzeile APrevRow zu einem
// Bedingungsausdruck (Delphi 13: 'X := if C then A' / 'else' / 'Foo(42);',
// 'X :=' / 'if C then' / 'A' / 'else' / ..., 'X :=' / 'if C then' /
// 'Foo(42);')? Aufwaerts bis zum 'if' entscheidet uRdxIntroPlan.
// IfExpressionAbove; das 'X := if ... then' bzw. '... else' auf der
// Zweigzeile selbst prueft schon der Plan. Vorher zaehlte nur EINE Zeile
// ueber dem else (Pruefer 2026-10-14, a).
function BranchOfIfExpression(const ATarget: TRdxIntroTarget;
  const ARows: TRdxIntroRows): Boolean;
begin
  if SameText(LastWord(ARows[ATarget.PrevRow - 1].Code), 'else') then
    Result := IfExpressionAbove(CodeFromRowUp(ARows,
      PrevCodeRowIn(ARows, ATarget.PrevRow)))
  else
    Result := IfExpressionAbove(CodeFromRowUp(ARows, ATarget.PrevRow));
end;

// Der Zweig (Plan.Wrap) bekommt begin..end: 'begin' an den Anfang der
// Zeile nach der Zweigzeile, 'end;' an den Anfang der Zeile nach der
// Anweisung - beide Stellen muessen Code sein, nicht das Innere eines
// Kommentars oder Strings ('X := 42; { Kommentar' / 'geht weiter }' -
// Pruefer 2026-10-13, Harness 5/6/20/24), und das Zeilenende hinter der
// Anweisung muss es geben. ARows reicht bis zur Zeile NACH der Anweisung
// (ihr Zustand am Anfang = der am Ende der Anweisung). '' oder der Grund.
function BlockReason(const AText: TRdxIntroText; const ATarget: TRdxIntroTarget;
  const ARows: TRdxIntroRows): string;
begin
  if ATarget.SourceRow >= Length(AText.Starts) then
    Result := 'die Anweisung ist die letzte Zeile ohne Zeilenende - kein '
      + 'Platz fuer end;'
  else if ARows[ATarget.PrevRow].State <> 'c' then
    Result := 'die Zweigzeile endet in einem offenen Kommentar oder String '
      + '- "begin" landete darin'
  else if ARows[ATarget.SourceRow].State <> 'c' then
    Result := 'die Anweisung endet in einem offenen Kommentar oder String - '
      + '"end;" landete darin'
  else if BranchOfIfExpression(ATarget, ARows) then
    Result := 'das then/else darueber gehoert zu einem Bedingungsausdruck '
      + '(Delphi 13: "X := if C then A" / "else" / ...) - ein begin..end '
      + 'mitten im Ausdruck ist kein Code'
  else
    Result := '';
end;

// Was die Zeilen um einen (fuer sich gueltigen) Plan verbieten: eine
// Direktive auf oder unter der Zeile darueber bis zur Anweisung - fuer
// JEDEN Plan, nicht nur mit Block (Pruefer 2026-10-13, Major 4) -, eine
// Direktive irgendwo auf der Anweisungszeile (DirectiveOnStatementRow)
// und bei begin..end die Grenzen des Blocks (BlockReason). '' oder der
// Grund.
function PlacementReason(const AText: TRdxIntroText; const ATarget: TRdxIntroTarget;
  const ARows: TRdxIntroRows): string;
begin
  if DirectiveBetween(AText, ATarget.PrevRow, ATarget.SourceRow) then
    Result := 'auf der Zeile darueber oder zwischen ihr und der Anweisung '
      + 'steht eine Direktive - in einem anderen Zweig der bedingten '
      + 'Uebersetzung stuende die Deklaration woanders'
  else if DirectiveOnStatementRow(AText, ATarget) then
    Result := 'auf der Anweisungszeile steht eine Direktive - die '
      + 'Deklaration bzw. begin..end koennte in einem anderen Zweig der '
      + 'bedingten Uebersetzung landen'
  else if ATarget.Plan.Wrap then
    Result := BlockReason(AText, ATarget, ARows)
  else
    Result := '';
end;

function TargetAt(const AText: TRdxIntroText; ARow, ACol: Integer;
  const ANameBase: string): TRdxIntroTarget;
var
  Rows      : TRdxIntroRows;
  Why       : string;
  PrevLine  : string;
  PrevState : Char;
begin
  Result := Default(TRdxIntroTarget);
  Result.SourceRow := ARow;
  if (ARow < 1) or (ARow > Length(AText.Lines)) then
  begin
    Result.Plan.Reason := Format('die Caret-Zeile %d liegt nicht im Puffer',
      [ARow]);
    Exit;
  end;
  // Vor dem Plan: in einem mehrzeiligen String oder Kommentar, im
  // asm-Block, im initialization-Abschnitt und in einer FPC-Datei ist
  // nichts zu tun. Die Zeilen bis EINE hinter der Anweisung: ihr Zustand
  // am Anfang ist der am Ende der Anweisung (BlockReason).
  Rows := RowsUpTo(AText, ARow + 1);
  Why := ContextReason(AText, ARow, Rows);
  if Why <> '' then
  begin
    Result.Plan.Reason := Why;
    Exit;
  end;
  Result.Name := NextFreeName(AText.Text, ANameBase);
  Result.PrevRow := PrevCodeRowIn(Rows, ARow);
  PrevForPlan(AText, Rows, Result.PrevRow, PrevLine, PrevState);
  Result.Plan := PlanIntroduce(AText.Lines[ARow - 1], PrevLine, ACol,
    Result.Name, PrevState);
  if not Result.Plan.Ok then
    Exit;
  if Result.Plan.Wrap then
    Result.Plan.BlockIndent := BranchIndent(AText, Rows, Result.PrevRow);
  Why := PlacementReason(AText, Result, Rows);
  if Why <> '' then
  begin
    Result.Plan.Ok := False;
    Result.Plan.Wrap := False;
    Result.Plan.Reason := Why;
    Exit;
  end;
  // Mit Block steht 'begin' ueber der Deklaration: beide eine Zeile tiefer.
  Result.DeclRow := ARow + Ord(Result.Plan.Wrap);
  Result.UseRow := Result.DeclRow + 1;
end;

function ByteEdit(AOffset, ALen: Integer; const AText: string): TRdxIntroByteEdit;
begin
  Result.Offset := AOffset;
  Result.Len := ALen;
  Result.Text := AText;
end;

function IntroduceEdits(const AText: TRdxIntroText;
  const ATarget: TRdxIntroTarget): TRdxIntroByteEdits;
var
  P     : TRdxIntroPlan;
  Row   : Integer;   // 0-basierter Index der Anweisungszeile
  Col   : Integer;
  Start : Integer;
begin
  Result := nil;
  P := ATarget.Plan;
  if not P.Ok then
    Exit;
  Row := ATarget.SourceRow - 1;
  Start := AText.Starts[Row];
  // 'begin' kommt vor die Zeile nach der Zweigzeile und endet wie die
  // Zweigzeile; Deklaration und 'end;' enden wie die Anweisungszeile.
  if P.Wrap then
    Result := Result + [ByteEdit(AText.Starts[ATarget.PrevRow], 0,
      P.BlockIndent + 'begin' + RowEol(AText, ATarget.PrevRow))];
  Result := Result + [ByteEdit(Start, 0,
    P.DeclText + RowEol(AText, ATarget.SourceRow))];
  for Col in P.OldCols do
    Result := Result + [ByteEdit(Start
      + Utf8Len(Copy(AText.Lines[Row], 1, Col - 1)), Utf8Len(P.Literal),
      ATarget.Name)];
  if P.Wrap then
    Result := Result + [ByteEdit(AText.Starts[Row + 1], 0,
      P.BlockIndent + 'end;' + RowEol(AText, ATarget.SourceRow))];
end;

procedure SyncBlockEnd(const AText: TRdxIntroText; const ATarget: TRdxIntroTarget;
  out ARow, ACol: Integer);
var
  Stop  : Integer;   // Spalte hinter der letzten Verwendung
  Extra : Integer;   // Mehrbytes davor in der Zeile
begin
  // Wie IntroduceEdits: ein abgelehntes Ziel hat keine Spalten (NewCols
  // leer) - (0, 0) statt eines Bereichsfehlers (Wochen-Review 2026-10-21).
  if not ATarget.Plan.Ok or (Length(ATarget.Plan.NewCols) = 0) then
  begin
    ARow := 0;
    ACol := 0;
    Exit;
  end;
  Stop := ATarget.Plan.NewCols[High(ATarget.Plan.NewCols)]
    + Length(ATarget.Name);
  Extra := Utf8Len(Copy(ATarget.Plan.NewUseLine, 1, Stop - 1)) - (Stop - 1);
  ARow := ATarget.UseRow;
  ACol := Stop;
  if Extra = 0 then
    Exit;
  // Nach der Anweisung kommt noch eine Zeile (bei Wrap 'end;').
  if ATarget.Plan.Wrap or (ATarget.SourceRow < Length(AText.Lines)) then
  begin
    ARow := ATarget.UseRow + 1;
    ACol := 1;
  end
  else
    ACol := Stop + Extra;
end;

// ACount Bytes von ASrc ab AFrom an ADest anhaengen. Bewusst ohne '+':
// FPC 3.2.2 verkettet 'X := X + Copy(..) + F(..)' falsch (Pruefstand
// 2026-10-11: Laenge 4 statt 9), und der Pruefstand soll dasselbe rechnen
// wie Delphi.
procedure AppendBytes(var ADest: TBytes; const ASrc: TBytes;
  AFrom, ACount: Integer);
var
  n : Integer;
begin
  if ACount <= 0 then
    Exit;
  n := Length(ADest);
  SetLength(ADest, n + ACount);
  Move(ASrc[AFrom], ADest[n], ACount);
end;

function ApplyIntroEdits(const ABytes: TBytes;
  const AEdits: TRdxIntroByteEdits): TBytes;
var
  E   : TRdxIntroByteEdit;
  At  : Integer;
  Ins : TBytes;
begin
  Result := nil;
  At := 0;
  for E in AEdits do
  begin
    if (E.Offset < At) or (E.Len < 0)
       or (E.Offset + E.Len > Length(ABytes)) then
      raise EArgumentException.CreateFmt('Ersetzung bei Byte %d (Laenge %d) '
        + 'steigt nicht auf oder ragt aus dem Puffer (Stand %d, Puffer %d)',
        [E.Offset, E.Len, At, Length(ABytes)]);
    AppendBytes(Result, ABytes, At, E.Offset - At);
    Ins := TEncoding.UTF8.GetBytes(E.Text);
    AppendBytes(Result, Ins, 0, Length(Ins));
    At := E.Offset + E.Len;
  end;
  AppendBytes(Result, ABytes, At, Length(ABytes) - At);
end;

end.
