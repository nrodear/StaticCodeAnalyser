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
// Direktive zwischen der Zeile darueber und der Anweisung, und bei
// begin..end keine offene Kommentargrenze und kein Bedingungsausdruck.
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
// Puffer NACH dem Schreiben (Vorbedingung wie IntroduceEdits: Plan.Ok).
// Normal direkt hinter der letzten Verwendung:
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
  Result.Starts := [0];
  for i := 0 to High(ABytes) do
    if ABytes[i] = BYTE_LF then
      Result.Starts := Result.Starts + [i + 1];
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

// Der Kommentar-Zustand am Anfang der Zeilen 1..ARow ('c' Code, 'b' in
// { }, 'p' in (* *)) - fuer Kommentare ueber mehrere Zeilen (Korpus-A/B
// 2026-10-11: auskommentierter Code und Prosa darin sahen aus wie Code).
function StartStates(const AText: TRdxIntroText; ARow: Integer): TArray<Char>;
var
  i : Integer;
begin
  Result := nil;
  SetLength(Result, ARow);
  if ARow > 0 then
    Result[0] := 'c';
  for i := 1 to ARow - 1 do
    Result[i] := CommentStateAfter(AText.Lines[i - 1], Result[i - 1]);
end;

function PrevCodeRow(const AText: TRdxIntroText; ARow: Integer): Integer;
var
  States : TArray<Char>;
  i      : Integer;
begin
  Result := 0;
  States := StartStates(AText, ARow);
  for i := ARow - 2 downto 0 do
    if Trim(CodePartFrom(AText.Lines[i], States[i])) <> '' then
      Exit(i + 1);
end;

// Die Zeile ARow (1-basiert) oder '' fuer 0.
function LineOrEmpty(const AText: TRdxIntroText; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow <= Length(AText.Lines)) then
    Result := AText.Lines[ARow - 1];
end;

// Steht zwischen der Zeile darueber AFromRow und der Anweisung AToRow eine
// Compiler-Direktive ({$IFDEF ...})? Dann gilt die Zeile darueber nur in
// einem Zweig der bedingten Uebersetzung: begin und end landeten in
// verschiedenen Zweigen (Korpus-A/B 2026-10-11), und ohne Block stuende
// die Deklaration im anderen Zweig hinter einem 'then' ('{$IFDEF A} if B
// then {$ELSE} Foo; {$ENDIF}' - Pruefer 2026-10-13, Harness 7). Eine
// Direktive AUF der Zeile darueber sieht die Pruefung nicht (Grenze).
function DirectiveBetween(const AText: TRdxIntroText;
  AFromRow, AToRow: Integer): Boolean;
var
  i : Integer;
begin
  for i := AFromRow to AToRow - 2 do
    if (Pos('{$', AText.Lines[i]) > 0) or (Pos('(*$', AText.Lines[i]) > 0) then
      Exit(True);
  Result := False;
end;

// Die Zahl der Quotes, mit denen die (getrimmte) Zeile einen mehrzeiligen
// String oeffnet (Delphi 12: mindestens drei am Zeilenende, der String
// bleibt offen), sonst 0.
function OpenerQuotes(const ALine: string): Integer;
var
  i : Integer;
begin
  i := Length(ALine);
  while (i > 0) and (ALine[i] = '''') do
    Dec(i);
  Result := Length(ALine) - i;
  if (Result < MIN_MULTILINE_QUOTES) or not StringOpenAtEnd(ALine) then
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

// Liegt Zeile ARow in einem mehrzeiligen String (Delphi 12)? Der
// Zeilen-Leser saehe dort Code und aenderte still den String (Korpus-A/B
// 2026-10-11).
function InMultiLineString(const AText: TRdxIntroText; ARow: Integer): Boolean;
var
  i, Quotes : Integer;
  L         : string;
begin
  Quotes := 0;   // 0 = kein String offen, sonst die Quote-Zahl des Oeffners
  for i := 0 to ARow - 2 do
  begin
    L := Trim(AText.Lines[i]);
    if Quotes = 0 then
      Quotes := OpenerQuotes(L)
    else if ClosesWith(L, Quotes) then
      Quotes := 0;
  end;
  Result := Quotes > 0;
end;

// Der Abschnitt, in dem Zeile ARow liegt ('c' Code, 'a' asm-Block, 'i'
// initialization/finalization) - die Zeilen darueber, jede ab ihrem
// Kommentar-Zustand, durch uRdxIntroPlan.SectionStateAfter gefaltet.
function SectionAt(const AText: TRdxIntroText; ARow: Integer;
  const AStates: TArray<Char>): Char;
var
  i : Integer;
begin
  Result := 'c';
  for i := 0 to ARow - 2 do
    Result := SectionStateAfter(CodePartFrom(AText.Lines[i], AStates[i]),
      Result);
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
// '' oder der Grund. AStates sind die Kommentar-Zustaende am Anfang der
// Zeilen 1..ARow (StartStates).
function ContextReason(const AText: TRdxIntroText; ARow: Integer;
  const AStates: TArray<Char>): string;
var
  Section : Char;
begin
  Result := '';
  if InMultiLineString(AText, ARow) then
    Exit('die Zeile liegt in einem mehrzeiligen String - dort ist kein Code');
  if AStates[ARow - 1] <> 'c' then
    Exit('die Zeile liegt in einem mehrzeiligen Kommentar - dort ist kein '
      + 'Code');
  Section := SectionAt(AText, ARow, AStates);
  if Section = 'a' then
    Exit('die Zeile liegt in einem asm-Block - dort ist kein Pascal-Code');
  if Section = 'i' then
    Exit('die Zeile liegt im initialization-/finalization-Abschnitt - ob '
      + 'dort eine Inline-Deklaration gilt, ist nicht gemessen');
  if SourceLooksFpcAware(AText) then
    Exit('die Datei traegt eine FPC-Weiche ({$IFDEF FPC}, {$MODE ...}) - '
      + 'eine Inline-Konstante gibt es in FPC 3.2 nicht');
end;

// Der Kommentar-Zustand am Anfang der Zeile ARow (1-basiert) aus AStates,
// 'c' fuer 0 (keine Zeile).
function StateOrCode(const AStates: TArray<Char>; ARow: Integer): Char;
begin
  Result := 'c';
  if (ARow >= 1) and (ARow <= Length(AStates)) then
    Result := AStates[ARow - 1];
end;

// Gehoert das 'else' am Ende der Zweigzeile APrevRow zu einem
// Bedingungsausdruck ('X := if C then A' / 'else' / 'Foo(42);')? Das
// entscheidet die Code-Zeile VOR der else-Zeile (uRdxIntroPlan.
// ContinuesIfExpression); das 'X := if ... else' auf EINER Zeile prueft
// schon der Plan.
function ElseOfIfExpression(const AText: TRdxIntroText; APrevRow: Integer;
  const AStates: TArray<Char>): Boolean;
var
  Before : Integer;
begin
  Result := False;
  if not SameText(LastWord(CodePartFrom(AText.Lines[APrevRow - 1],
       AStates[APrevRow - 1])), 'else') then
    Exit;
  Before := PrevCodeRow(AText, APrevRow);
  if Before > 0 then
    Result := ContinuesIfExpression(CodePartFrom(AText.Lines[Before - 1],
      AStates[Before - 1]));
end;

// Der Zweig (Plan.Wrap) bekommt begin..end: 'begin' an den Anfang der
// Zeile nach der Zweigzeile, 'end;' an den Anfang der Zeile nach der
// Anweisung - beide Stellen muessen Code sein, nicht das Innere eines
// Kommentars ('X := 42; { Kommentar' / 'geht weiter }' - Pruefer
// 2026-10-13, Harness 5/6/20/24), und das Zeilenende hinter der Anweisung
// muss es geben. '' oder der Grund.
function BlockReason(const AText: TRdxIntroText; const ATarget: TRdxIntroTarget;
  const AStates: TArray<Char>): string;
begin
  if ATarget.SourceRow >= Length(AText.Starts) then
    Result := 'die Anweisung ist die letzte Zeile ohne Zeilenende - kein '
      + 'Platz fuer end;'
  else if AStates[ATarget.PrevRow] <> 'c' then
    Result := 'die Zweigzeile endet in einem offenen Kommentar - "begin" '
      + 'landete darin'
  else if CommentStateAfter(AText.Lines[ATarget.SourceRow - 1], 'c') <> 'c'
  then
    Result := 'die Anweisung endet in einem offenen Kommentar - "end;" '
      + 'landete darin'
  else if ElseOfIfExpression(AText, ATarget.PrevRow, AStates) then
    Result := 'das else darueber gehoert zu einem Bedingungsausdruck (Delphi '
      + '13: "X := if C then A" / "else" / ...) - ein begin..end mitten im '
      + 'Ausdruck ist kein Code'
  else
    Result := '';
end;

// Was die Zeilen um einen (fuer sich gueltigen) Plan verbieten: eine
// Direktive zwischen der Zeile darueber und der Anweisung - fuer JEDEN
// Plan, nicht nur mit Block (Pruefer 2026-10-13, Major 4) - und bei
// begin..end die Grenzen des Blocks (BlockReason). '' oder der Grund.
function PlacementReason(const AText: TRdxIntroText; const ATarget: TRdxIntroTarget;
  const AStates: TArray<Char>): string;
begin
  if DirectiveBetween(AText, ATarget.PrevRow, ATarget.SourceRow) then
    Result := 'zwischen der Zeile darueber und der Anweisung steht eine '
      + 'Direktive - in einem anderen Zweig der bedingten Uebersetzung '
      + 'stuende die Deklaration woanders'
  else if ATarget.Plan.Wrap then
    Result := BlockReason(AText, ATarget, AStates)
  else
    Result := '';
end;

function TargetAt(const AText: TRdxIntroText; ARow, ACol: Integer;
  const ANameBase: string): TRdxIntroTarget;
var
  States : TArray<Char>;
  Why    : string;
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
  // nichts zu tun.
  States := StartStates(AText, ARow);
  Why := ContextReason(AText, ARow, States);
  if Why <> '' then
  begin
    Result.Plan.Reason := Why;
    Exit;
  end;
  Result.Name := NextFreeName(AText.Text, ANameBase);
  Result.PrevRow := PrevCodeRow(AText, ARow);
  // Die Zeile darueber zaehlt ab ihrem Kommentar-Zustand: beginnt sie in
  // einem Kommentar, ist ihr Code der Teil hinter dessen Ende (Pruefer
  // 2026-10-13, Minor 1).
  Result.Plan := PlanIntroduce(AText.Lines[ARow - 1],
    LineOrEmpty(AText, Result.PrevRow), ACol, Result.Name,
    StateOrCode(States, Result.PrevRow));
  if not Result.Plan.Ok then
    Exit;
  Why := PlacementReason(AText, Result, States);
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
