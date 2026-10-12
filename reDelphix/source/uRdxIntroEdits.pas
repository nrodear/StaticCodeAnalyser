unit uRdxIntroEdits;

// reDelphix - Code-Aktion "Lokale Variable einfuehren" (Refactoring ohne
// Fund): was die Aktion am Puffer aendert, OHNE ToolsAPI (laeuft auch unter
// FPC, Pruefstand tools\fpc-pruefstand): der Text beim Start (Zeilen,
// Byte-Anfaenge, Zeilenende), das Ziel an der Caret-Position, die
// Ersetzungen des Writers fuer C1h und das Ende des Sync-Blocks. Der
// IDE-Teil wendet genau diese Ersetzungen mit EINEM IOTAEditWriter an;
// ApplyIntroEdits stellt den Writer nach - so pruefen die Tests den Text,
// der am Ende im Puffer steht, nicht nur Offsets.
//
// 1:1 aus dem Labor VarNameProject (uVnpEdits, Stand 41bccb23, Entscheid
// E24), nur Variante C1h - Loeschen und Zurueckschreiben der Anweisung und
// die Template-Datei fuer D1 (Live Template) bleiben im Labor. Der IDE-Teil
// (im Labor uVnpIntroduce) folgt, wenn das Labor Enter und Esc geklaert hat
// (E25: Esc zerstoert im Sync Edit der IDE Text, UI-Test 2026-10-11).
// ApplyIntroEdits heisst im Labor ApplyByteEdits; uRdxBufferMath hat eine
// gleichnamige Routine mit anderer Signatur.
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
  // Zeile leer. Ein BOM am Anfang bleibt Teil der ersten Zeile (U+FEFF),
  // die Byte-Offsets zaehlen es mit.
  TRdxIntroText = record
    Text   : string;            // der ganze Puffer
    Lines  : TArray<string>;    // Zeilen ohne Zeilenende
    Starts : TArray<Integer>;   // Byte-Offset jedes Zeilenanfangs
    Eol    : string;            // #13#10, sobald eines vorkommt, sonst #10
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

// Die naechste Zeile ueber ARow mit Code (0 am Dateianfang); leere und
// reine Kommentarzeilen zaehlen nicht.
function PrevCodeRow(const AText: TRdxIntroText; ARow: Integer): Integer;

// Das Ziel fuer den Caret in Zeile ARow, Zeichenspalte ACol: freier Name
// ANameBase + '01', '02' ..., Plan, Zeilen nach dem Schreiben.
// Result.Plan.Ok = False mit Result.Plan.Reason, wenn es nichts zu tun
// gibt.
function TargetAt(const AText: TRdxIntroText; ARow, ACol: Integer;
  const ANameBase: string): TRdxIntroTarget;

// C1h: die Ersetzungen EINES Writers, aufsteigend - die Deklaration ueber
// die Anweisung, die Literale der Zeile durch den Namen; bei Plan.Wrap
// 'begin' an den Anfang der Zeile nach der Zweigzeile und 'end;' an den
// Anfang der Zeile nach der Anweisung, beide mit der Einrueckung der
// Zweigzeile.
function IntroduceEdits(const AText: TRdxIntroText;
  const ATarget: TRdxIntroTarget): TRdxIntroByteEdits;

// C1h: wo der Sync-Block endet - Zeile und Zeichenspalte (exklusiv) im
// Puffer NACH dem Schreiben. Normal direkt hinter der letzten Verwendung:
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
  for n := 0 to High(Result.Starts) do
  begin
    // Ende der Zeile: vor ihrem LF bzw. am Pufferende, ohne CR davor.
    if n < High(Result.Starts) then
      Stop := Result.Starts[n + 1] - 1
    else
      Stop := Length(ABytes);
    if (Stop > Result.Starts[n]) and (ABytes[Stop - 1] = BYTE_CR) then
      Dec(Stop);
    // Leere Zeile ohne GetString: dessen Index laege sonst am Pufferende.
    Result.Lines[n] := '';
    if Stop > Result.Starts[n] then
      Result.Lines[n] := TEncoding.UTF8.GetString(ABytes, Result.Starts[n],
        Stop - Result.Starts[n]);
  end;
  Result.Eol := #10;
  if Pos(#13#10, Result.Text) > 0 then
    Result.Eol := #13#10;
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

// Steht zwischen der Zweigzeile AFromRow und der Anweisung AToRow eine
// Compiler-Direktive ({$IFDEF ...})? Dann landeten begin und end in
// verschiedenen Zweigen der bedingten Uebersetzung (Korpus-A/B
// 2026-10-11). Dazwischen stehen nur Leer- und Kommentarzeilen.
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

// Liegt Zeile ARow in einem mehrzeiligen String (Delphi 12: eine Zeile
// endet mit ''' bei offenem String, eine spaetere beginnt mit ''')? Der
// Zeilen-Leser saehe dort Code und aenderte still den String (Korpus-A/B
// 2026-10-11).
function InMultiLineString(const AText: TRdxIntroText; ARow: Integer): Boolean;
const
  TRIPLE = '''''''';
var
  i : Integer;
  L : string;
begin
  Result := False;
  for i := 0 to ARow - 2 do
  begin
    L := Trim(AText.Lines[i]);
    if Result then
      Result := Copy(L, 1, 3) <> TRIPLE
    else
      Result := (Copy(L, Length(L) - 2, 3) = TRIPLE) and StringOpenAtEnd(L);
  end;
end;

function TargetAt(const AText: TRdxIntroText; ARow, ACol: Integer;
  const ANameBase: string): TRdxIntroTarget;
begin
  Result := Default(TRdxIntroTarget);
  Result.SourceRow := ARow;
  if (ARow < 1) or (ARow > Length(AText.Lines)) then
  begin
    Result.Plan.Reason := Format('die Caret-Zeile %d liegt nicht im Puffer',
      [ARow]);
    Exit;
  end;
  // Vor dem Plan: in einem mehrzeiligen String oder Kommentar ist gar kein
  // Code (beginnt die Zeile im Kommentar, lehnt die Hilfe sie ganz ab).
  if InMultiLineString(AText, ARow) then
  begin
    Result.Plan.Reason := 'die Zeile liegt in einem mehrzeiligen String - '
      + 'dort ist kein Code';
    Exit;
  end;
  if StartStates(AText, ARow)[ARow - 1] <> 'c' then
  begin
    Result.Plan.Reason := 'die Zeile liegt in einem mehrzeiligen Kommentar '
      + '- dort ist kein Code';
    Exit;
  end;
  Result.Name := NextFreeName(AText.Text, ANameBase);
  Result.PrevRow := PrevCodeRow(AText, ARow);
  Result.Plan := PlanIntroduce(AText.Lines[ARow - 1],
    LineOrEmpty(AText, Result.PrevRow), ACol, Result.Name);
  // 'end;' kommt an den Anfang der Zeile NACH der Anweisung - die muss es
  // geben.
  if Result.Plan.Ok and Result.Plan.Wrap
     and (ARow >= Length(AText.Starts)) then
  begin
    Result.Plan.Ok := False;
    Result.Plan.Reason := 'die Anweisung ist die letzte Zeile ohne '
      + 'Zeilenende - kein Platz fuer end;';
  end;
  if Result.Plan.Ok and Result.Plan.Wrap
     and DirectiveBetween(AText, Result.PrevRow, ARow) then
  begin
    Result.Plan.Ok := False;
    Result.Plan.Reason := 'zwischen der Zweigzeile und der Anweisung steht '
      + 'eine Direktive - begin und end landeten in verschiedenen Zweigen';
  end;
  if not Result.Plan.Ok then
    Exit;
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
  P := ATarget.Plan;
  Row := ATarget.SourceRow - 1;
  Start := AText.Starts[Row];
  Result := nil;
  if P.Wrap then
    Result := Result + [ByteEdit(AText.Starts[ATarget.PrevRow], 0,
      P.BlockIndent + 'begin' + AText.Eol)];
  Result := Result + [ByteEdit(Start, 0, P.DeclText + AText.Eol)];
  for Col in P.OldCols do
    Result := Result + [ByteEdit(Start
      + Utf8Len(Copy(AText.Lines[Row], 1, Col - 1)), Utf8Len(P.Literal),
      ATarget.Name)];
  if P.Wrap then
    Result := Result + [ByteEdit(AText.Starts[Row + 1], 0,
      P.BlockIndent + 'end;' + AText.Eol)];
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
