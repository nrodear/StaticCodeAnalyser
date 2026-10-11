unit uVnpIntroduce;

// VarNameProject - "Zahl-Literal als Variable einfuehren", Ablauf wie bei
// ReSharper "Introduce Variable" (Nico 2026-10-11, E17):
//   1. Caret auf einem Zahl-Literal, z. B. 'Result := Value * 42 + 42;'.
//   2. Darueber entsteht 'var MagicNr01 := 42;', die gleichen Literale der
//      Zeile werden zu MagicNr01 - ein Schreibvorgang, EIN Strg+Z.
//   3. Die Stellen von MagicNr01 werden als Sync-Edit-Punkt angemeldet: die
//      IDE umrandet sie und setzt den Caret selbst auf die erste Stelle (die
//      Deklaration steht in den Offsets vorn); Tippen aendert alle Stellen
//      mit. Der Caret wird danach NICHT mehr bewegt - das koennte die
//      Vorauswahl der IDE aufheben (Messpunkt M11).
// Die Varianten unterscheiden NUR Schritt 3 - sie sind die Messung (siehe
// TVnpVariant): eigene Punkt-Klassen mit absoluten Offsets (Lauf 1:
// funktioniert; "Punkte per IOTACodeTemplateServices.CreateClass" ist
// entfallen - Sonde M21 ergab nil, relative Offsets sind nicht noetig),
// je mit/ohne gehaltene Punkte und Notifier; dazu SyncEditBlock(nil) als
// Referenz (die IDE sucht selbst, wie Strg+Umschalt+J).
// TOTACharPos: CharIndex 0-basiert in ZEICHEN der Zeile (Tab = 1), Line
// 1-basiert - gemessen 2026-10-11 (Sonde M10, 'Gruesse EUR': CharIndex 20
// bei 20 Zeichen = 24 Bytes). ACHTUNG: CharPosToPos addiert CharIndex als
// BYTES zum Zeilenanfang - auf Zeilen mit Nicht-ASCII davor stimmt es also
// nicht; Pufferpositionen rechnet dieses Projekt selbst (Reader-Bytes).

interface

type
  // Lauf 1 (2026-10-11): B1 mit absoluten Offsets startet die Sitzung,
  // Strg+Z danach stuerzt in TSyncEditManager.SendSyncEvent ab. Die
  // Varianten trennen die zwei Verdaechtigen: Punkte freigegeben (nur
  // lokal gehalten) und Notifier bei Exit abgemeldet (jetzt nie mehr).
  TVnpVariant = (vvKeepBoth, vvKeepPointsOnly, vvNotifierOnly,
    vvIdeSyncEdit);

const
  VARIANT_CAPTIONS : array[TVnpVariant] of string = (
    'B1a eigene Punkte gehalten + Notifier (Kandidat)',
    'B1b eigene Punkte gehalten, ohne Notifier',
    'B1d Notifier, Punkte NICHT gehalten',
    'C  SyncEditBlock(nil) - IDE-Sync-Edit + Notifier');

// Der ganze Ablauf an der Caret-Position der obersten Editoransicht.
procedure RunIntroduce(AVariant: TVnpVariant);

implementation

uses
  System.SysUtils, System.Classes, ToolsAPI, uVnpPlan, uVnpLog, uVnpSync;

const
  NAME_BASE = 'MagicNr';

type
  // Der Editor und sein Text beim Start.
  TVnpEditor = record
    View   : IOTAEditView;
    Buffer : IOTAEditBuffer;
    Lines  : TStringList;        // Zeilen ohne Zeilenende
    Starts : TArray<Integer>;    // Byte-Offset jedes Zeilenanfangs
    Eol    : string;
    Text   : string;
  end;

  // Wo der Name nach dem Schreiben steht.
  TVnpTarget = record
    DeclRow : Integer;
    UseRow  : Integer;
    Name    : string;
    Plan    : TVnpPlan;
  end;

// Puffer als UTF-8-Bytes (Reader in Bloecken) und die Zeilenanfaenge.
procedure ReadEditor(var AEd: TVnpEditor);
const
  BLOCK = 16384;
var
  Reader : IOTAEditReader;
  Bytes  : TBytes;
  Chunk  : TBytes;
  Got, i : Integer;
begin
  Reader := AEd.Buffer.CreateReader;
  SetLength(Bytes, 0);
  repeat
    SetLength(Chunk, BLOCK);
    Got := Reader.GetText(Length(Bytes), PAnsiChar(@Chunk[0]), BLOCK);
    if Got > 0 then
    begin
      i := Length(Bytes);
      SetLength(Bytes, i + Got);
      Move(Chunk[0], Bytes[i], Got);
    end;
  until Got < BLOCK;
  Reader := nil;   // vor jedem Schreiben freigeben
  AEd.Text := '';
  if Length(Bytes) > 0 then
    AEd.Text := TEncoding.UTF8.GetString(Bytes);
  AEd.Starts := [0];
  for i := 0 to High(Bytes) do
    if Bytes[i] = 10 then
      AEd.Starts := AEd.Starts + [i + 1];
  AEd.Eol := #10;
  if Pos(#13#10, AEd.Text) > 0 then
    AEd.Eol := #13#10;
  AEd.Lines.Text := AEd.Text;
end;

// Caret als Zeile und 1-basierte Zeichenspalte: CharIndex zaehlt Zeichen
// (Sonde M10), die Spalte ist CharIndex + 1. NICHT ueber CharPosToPos -
// das liest CharIndex als Bytes und lag hinter 'Gruesse EUR' 4 Spalten
// daneben (Protokoll 2026-10-11).
procedure CaretOf(const AEd: TVnpEditor; out ARow, ACol: Integer);
var
  EdPos   : TOTAEditPos;
  CharPos : TOTACharPos;
begin
  EdPos := AEd.View.CursorPos;
  CharPos.CharIndex := 0;
  CharPos.Line := EdPos.Line;
  AEd.View.ConvertPos(True, EdPos, CharPos);
  ARow := CharPos.Line;
  ACol := CharPos.CharIndex + 1;
  VnpLog('Caret: Anzeige %d:%d -> CharPos (Zeile %d, CharIndex %d) -> '
    + 'Zeichenspalte %d', [EdPos.Line, EdPos.Col, CharPos.Line,
    CharPos.CharIndex, ACol]);
end;

// Die naechste Zeile ueber ARow mit Code ('' am Dateianfang); leere und
// reine Kommentarzeilen zaehlen nicht.
function PrevCode(const AEd: TVnpEditor; ARow: Integer): string;
var
  i : Integer;
begin
  Result := '';
  for i := ARow - 2 downto 0 do
    if Trim(CodePart(AEd.Lines[i])) <> '' then
      Exit(AEd.Lines[i]);
end;

// Byte-Offset der Zeichenspalte ACol in Zeile ARow (1-basiert).
function ByteOf(const AEd: TVnpEditor; ARow, ACol: Integer): Integer;
begin
  Result := AEd.Starts[ARow - 1]
    + Utf8Len(Copy(AEd.Lines[ARow - 1], 1, ACol - 1));
end;

// Schritt 2: Deklaration ueber die Zeile, Literale ersetzen - ein Writer,
// ein Undo-Schritt, Positionen aufsteigend.
procedure WriteEdits(const AEd: TVnpEditor; const ATarget: TVnpTarget);
var
  Writer : IOTAEditWriter;
  Col, B : Integer;
  Lit    : Integer;
  Probe  : TOTACharPos;
begin
  Probe.CharIndex := 0;
  Probe.Line := ATarget.DeclRow;
  VnpLog('Zeilenanfang: eigene Rechnung %d, IDE CharPosToPos %d',
    [AEd.Starts[ATarget.DeclRow - 1], AEd.View.CharPosToPos(Probe)]);
  Lit := Utf8Len(ATarget.Plan.Literal);
  Writer := AEd.Buffer.CreateUndoableWriter;
  try
    Writer.CopyTo(AEd.Starts[ATarget.DeclRow - 1]);
    Writer.Insert(PAnsiChar(UTF8Encode(ATarget.Plan.DeclText + AEd.Eol)));
    for Col in ATarget.Plan.OldCols do
    begin
      B := ByteOf(AEd, ATarget.DeclRow, Col);
      Writer.CopyTo(B);
      Writer.DeleteTo(B + Lit);
      Writer.Insert(PAnsiChar(UTF8Encode(ATarget.Name)));
    end;
  finally
    Writer := nil;   // erst die Freigabe schreibt in den Puffer
  end;
  VnpLog('Geschrieben: "%s" + %d Ersetzung(en) in "%s"',
    [ATarget.Plan.DeclText, Length(ATarget.Plan.OldCols),
    ATarget.Plan.NewUseLine]);
end;

// Die Fundstellen des Namens: Deklaration + Verwendungen. Line absolut
// (Zeile der Datei), CharIndex in Zeichen wie ConvertPos - beides in Lauf 1
// bestaetigt (B1: Offsets (23,6) (24,42), Sitzung im Template-Modus).
function OffsetsOf(const ATarget: TVnpTarget): TArray<TOTACharPos>;
var
  P   : TOTACharPos;
  Col : Integer;
begin
  P.Line := ATarget.DeclRow;
  P.CharIndex := ATarget.Plan.NameCol - 1;
  Result := [P];
  for Col in ATarget.Plan.NewCols do
  begin
    P.Line := ATarget.UseRow;
    P.CharIndex := Col - 1;
    Result := Result + [P];
  end;
end;

// Anzeige-Spalte zur Zeichenspalte ACol in Zeile ARow (Tabs rechnet die
// IDE um; CharIndex in Zeichen).
function DisplayCol(const AView: IOTAEditView; ARow, ACol: Integer): Integer;
var
  EdPos   : TOTAEditPos;
  CharPos : TOTACharPos;
begin
  CharPos.Line := ARow;
  CharPos.CharIndex := ACol - 1;
  EdPos.Line := ARow;
  EdPos.Col := ACol;
  AView.ConvertPos(False, EdPos, CharPos);
  Result := EdPos.Col;
end;

// Block ueber Deklarations- und Verwendungszeile (ganze Zeilen).
function SelectLines(const AEd: TVnpEditor;
  const ATarget: TVnpTarget): IOTAEditBlock;
var
  EdPos : IOTAEditPosition;
begin
  Result := AEd.View.Block;
  EdPos := AEd.Buffer.EditPosition;
  Result.Reset;
  Result.Style := btNonInclusive;
  EdPos.Move(ATarget.DeclRow, 1);
  Result.BeginBlock;
  EdPos.Move(ATarget.UseRow, DisplayCol(AEd.View, ATarget.UseRow,
    Length(ATarget.Plan.NewUseLine) + 1));
  Result.EndBlock;
  VnpLog('Block: %d:%d - %d:%d, SyncMode vorher %d', [Result.StartingRow,
    Result.StartingColumn, Result.EndingRow, Result.EndingColumn,
    Ord(Result.SyncMode)]);
end;

// Schritt 3 je Variante.
procedure StartSync(AVariant: TVnpVariant; const ABlock: IOTAEditBlock;
  const ATarget: TVnpTarget);
const
  WITH_NOTIFIER = [vvKeepBoth, vvNotifierOnly, vvIdeSyncEdit];
  KEEP_POINTS   = [vvKeepBoth, vvKeepPointsOnly];
var
  Points : IOTASyncEditPoints;
  Err    : string;
begin
  if AVariant in WITH_NOTIFIER then
    WatchBlock(ABlock)
  else
    VnpLog('  ohne Notifier');
  if AVariant = vvIdeSyncEdit then
  begin
    ABlock.SyncEditBlock(nil);
    Exit;
  end;
  if not MakePoints(ATarget.Name, OffsetsOf(ATarget), Points, Err) then
    Exit;
  if AVariant in KEEP_POINTS then
  begin
    KeepAlive(Points);
    VnpLog('  Punkte gehalten bis zum Entladen');
  end
  else
    VnpLog('  Punkte NICHT gehalten (nur lokale Referenz)');
  ABlock.SyncEditBlock(Points);
end;

// Nach dem Start nur protokollieren: wo die IDE den Caret hingesetzt hat
// und wo der Name steht (ReSharper: der Caret steht im umrandeten Namen).
procedure AfterSync(const AEd: TVnpEditor; const ABlock: IOTAEditBlock;
  const ATarget: TVnpTarget);
var
  Caret : TOTAEditPos;
begin
  Caret := AEd.View.CursorPos;
  AEd.View.MoveViewToCursor;
  AEd.View.Paint;
  VnpLog('Nach SyncEditBlock: SyncMode %d (0 keine, 1 normal, 2 Templates), '
    + 'Caret %d:%d, Name in der Deklaration bei %d:%d', [Ord(ABlock.SyncMode),
    Caret.Line, Caret.Col, ATarget.DeclRow, DisplayCol(AEd.View,
    ATarget.DeclRow, ATarget.Plan.NameCol)]);
  VnpLog('  (Ereignis-Zeilen kommen spaeter: beim Verlassen der Sitzung und '
    + 'ggf. bei Strg+Z)');
end;

function OpenEditor(out AEd: TVnpEditor): Boolean;
var
  Svc : IOTAEditorServices;
begin
  Result := False;
  AEd := Default(TVnpEditor);
  if not Supports(BorlandIDEServices, IOTAEditorServices, Svc) then Exit;
  AEd.View := Svc.TopView;
  if (AEd.View = nil) or (AEd.View.Buffer = nil) then Exit;
  AEd.Buffer := AEd.View.Buffer;
  Result := True;
end;

// Schritte 1 und 2; False mit Protokolleintrag, wenn es nichts zu tun gibt.
function Prepare(var AEd: TVnpEditor; out ATarget: TVnpTarget): Boolean;
var
  Row, Col : Integer;
begin
  Result := False;
  ATarget := Default(TVnpTarget);
  ReadEditor(AEd);
  CaretOf(AEd, Row, Col);
  if (Row < 1) or (Row > AEd.Lines.Count) then
  begin
    // SCA162-Fehlalarm: der Detektor liest "des" im deutschen Meldetext
    // (String-Literal) als Krypto-Algorithmus DES.
    // noinspection InsecureCryptoAlgorithm
    VnpLog('Abbruch: Caret-Zeile %d ausserhalb des Puffers', [Row]);
    Exit;
  end;
  ATarget.Name := NextFreeName(AEd.Text, NAME_BASE);
  ATarget.Plan := PlanIntroduce(AEd.Lines[Row - 1], PrevCode(AEd, Row), Col,
    ATarget.Name);
  if not ATarget.Plan.Ok then
  begin
    VnpLog('Abbruch: %s', [ATarget.Plan.Reason]);
    Exit;
  end;
  ATarget.DeclRow := Row;
  ATarget.UseRow := Row + 1;
  WriteEdits(AEd, ATarget);
  Result := True;
end;

procedure RunIntroduce(AVariant: TVnpVariant);
var
  Ed     : TVnpEditor;
  Target : TVnpTarget;
  Block  : IOTAEditBlock;
begin
  VnpLog('=== %s ===', [VARIANT_CAPTIONS[AVariant]]);
  if not OpenEditor(Ed) then
  begin
    VnpLog('Abbruch: keine Editoransicht');
    VnpShowLog;
    Exit;
  end;
  Ed.Lines := TStringList.Create;
  try
    try
      if Prepare(Ed, Target) then
      begin
        Block := SelectLines(Ed, Target);
        StartSync(AVariant, Block, Target);
        AfterSync(Ed, Block, Target);
      end
      else
        VnpShowLog;
    except
      on EAbort do
        raise;
      // Ein IDE-Plugin darf aus einem Menueklick keine Ausnahme in die IDE
      // werfen; jeder Fehler gehoert ins Protokoll (Messung).
      // noinspection ExceptionTooGeneral
      on E: Exception do
      begin
        VnpLog('FEHLER %s: %s', [E.ClassName, E.Message]);
        VnpShowLog;
      end;
    end;
  finally
    Ed.Lines.Free;
  end;
end;

end.
