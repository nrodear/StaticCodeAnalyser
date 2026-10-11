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
  // Laeufe 1-4 (2026-10-11): jeder Absturz ging ueber einen nil-Eintrag
  // in der Notifier-Liste des Editorblocks (RemoveNotifier setzt nil,
  // SendSyncEvent prueft nicht) - siehe uVnpSync. Ohne Notifier treten
  // beide Wege noch einmal an (IDE NEU STARTEN, die nil-Eintraege haengen
  // an den offenen Ansichten):
  //   C1  die IDE-eigene Sync-Edit-Suche (SyncEditBlock(nil) =
  //       Strg+Umschalt+J) ueber einem Block vom Namen bis zu seiner
  //       letzten Verwendung - keine eigenen Objekte.
  //   B1  eigene Punkt-Klassen, Offsets absolut, CharIndex in Bytes.
  TVnpVariant = (vvIdeOnly, vvOwnPoints);

const
  VARIANT_CAPTIONS : array[TVnpVariant] of string = (
    'C1 IDE-Sync-Edit ueber Name..letzte Verwendung',
    'B1 eigene Punkte (Bytes), ohne Notifier');

// Der ganze Ablauf an der Caret-Position der obersten Editoransicht.
procedure RunIntroduce(AVariant: TVnpVariant);

// Sonde ohne Notifier: SyncMode, Caret, Geaendert-Zustand und die beiden
// Zeilen des letzten Laufs, frisch aus dem Puffer - beliebig oft
// aufrufbar (nach dem Tippen, nach Enter, nach Strg+Z).
procedure ProbeSession;

implementation

uses
  System.SysUtils, System.Classes, ToolsAPI, uVnpPlan, uVnpLog, uVnpSync,
  uVnpProbe;

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
    SourceRow : Integer;   // Zeile der Anweisung VOR dem Schreiben
    PrevRow   : Integer;   // Zeile mit Code darueber (0 = keine)
    DeclRow   : Integer;   // Zeile der Deklaration NACH dem Schreiben
    UseRow    : Integer;   // Zeile der Anweisung NACH dem Schreiben
    Name      : string;
    Plan      : TVnpPlan;
  end;

var
  // Das Ziel des letzten erfolgreichen Schreibens - fuer ProbeSession.
  GLast : TVnpTarget;

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

// Die Zeile ARow (1-basiert) oder '' fuer 0.
function LineOrEmpty(const AEd: TVnpEditor; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow <= AEd.Lines.Count) then
    Result := AEd.Lines[ARow - 1];
end;

// Die Nummer der naechsten Zeile ueber ARow mit Code (0 am Dateianfang);
// leere und reine Kommentarzeilen zaehlen nicht.
function PrevCodeRow(const AEd: TVnpEditor; ARow: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := ARow - 2 downto 0 do
    if Trim(CodePart(AEd.Lines[i])) <> '' then
      Exit(i + 1);
end;

// Byte-Offset der Zeichenspalte ACol in Zeile ARow (1-basiert).
function ByteOf(const AEd: TVnpEditor; ARow, ACol: Integer): Integer;
begin
  Result := AEd.Starts[ARow - 1]
    + Utf8Len(Copy(AEd.Lines[ARow - 1], 1, ACol - 1));
end;

// Schritt 2: Deklaration ueber die Zeile, Literale ersetzen - ein Writer,
// ein Undo-Schritt, Positionen aufsteigend.
// Bei Plan.Wrap kommen 'begin' (Anfang der Zeile nach der Zweigzeile -
// Kommentare dazwischen landen im Block) und 'end;' (Anfang der Zeile nach
// der Anweisung) mit in denselben Writer: weiter EIN Strg+Z.
procedure WriteEdits(const AEd: TVnpEditor; const ATarget: TVnpTarget);
var
  Writer : IOTAEditWriter;
  Col, B : Integer;
  Lit    : Integer;
  Probe  : TOTACharPos;
  Block  : string;
begin
  Probe.CharIndex := 0;
  Probe.Line := ATarget.SourceRow;
  VnpLog('Zeilenanfang: eigene Rechnung %d, IDE CharPosToPos %d',
    [AEd.Starts[ATarget.SourceRow - 1], AEd.View.CharPosToPos(Probe)]);
  Lit := Utf8Len(ATarget.Plan.Literal);
  Writer := AEd.Buffer.CreateUndoableWriter;
  try
    if ATarget.Plan.Wrap then
    begin
      Writer.CopyTo(AEd.Starts[ATarget.PrevRow]);
      Writer.Insert(PAnsiChar(UTF8Encode(ATarget.Plan.BlockIndent + 'begin'
        + AEd.Eol)));
    end;
    Writer.CopyTo(AEd.Starts[ATarget.SourceRow - 1]);
    Writer.Insert(PAnsiChar(UTF8Encode(ATarget.Plan.DeclText + AEd.Eol)));
    for Col in ATarget.Plan.OldCols do
    begin
      B := ByteOf(AEd, ATarget.SourceRow, Col);
      Writer.CopyTo(B);
      Writer.DeleteTo(B + Lit);
      Writer.Insert(PAnsiChar(UTF8Encode(ATarget.Name)));
    end;
    if ATarget.Plan.Wrap then
    begin
      Writer.CopyTo(AEd.Starts[ATarget.SourceRow]);
      Writer.Insert(PAnsiChar(UTF8Encode(ATarget.Plan.BlockIndent + 'end;'
        + AEd.Eol)));
    end;
  finally
    Writer := nil;   // erst die Freigabe schreibt in den Puffer
  end;
  Block := '';
  if ATarget.Plan.Wrap then
    Block := ' - in begin..end (Zweig ohne begin)';
  VnpLog('Geschrieben: "%s" + %d Ersetzung(en) in "%s"%s',
    [ATarget.Plan.DeclText, Length(ATarget.Plan.OldCols),
    ATarget.Plan.NewUseLine, Block]);
end;

// Die Fundstellen des Namens: Deklaration + Verwendungen. Line absolut
// (Zeile der Datei, Lauf 1). CharIndex in UTF-8-BYTES der Zeile - anders als
// ConvertPos (Zeichen): Lauf 3 (Fall 6) zeigte, dass die IDE im
// Template-Modus den Punkttext an jede Fundstelle schreibt und CharIndex 42
// dabei als Byte 42 (= Zeichen 39, das 't' von 'Count') las - aus
// 'Count * MagicNr01' wurde 'CounMagicNr01Nr01'.
function OffsetsOf(const ATarget: TVnpTarget): TArray<TOTACharPos>;
var
  P   : TOTACharPos;
  Col : Integer;
begin
  P.Line := ATarget.DeclRow;
  P.CharIndex := Utf8Len(Copy(ATarget.Plan.DeclText, 1,
    ATarget.Plan.NameCol - 1));
  Result := [P];
  for Col in ATarget.Plan.NewCols do
  begin
    P.Line := ATarget.UseRow;
    P.CharIndex := Utf8Len(Copy(ATarget.Plan.NewUseLine, 1, Col - 1));
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

// Den Block von Zeichenspalte AFromCol in ADeclRow bis vor AToCol in
// AUseRow markieren (btNonInclusive, Spalten in Zeichen).
function SelectRange(const AEd: TVnpEditor; const ATarget: TVnpTarget;
  AFromCol, AToCol: Integer): IOTAEditBlock;
var
  EdPos : IOTAEditPosition;
begin
  Result := AEd.View.Block;
  EdPos := AEd.Buffer.EditPosition;
  Result.Reset;
  Result.Style := btNonInclusive;
  EdPos.Move(ATarget.DeclRow, DisplayCol(AEd.View, ATarget.DeclRow, AFromCol));
  Result.BeginBlock;
  EdPos.Move(ATarget.UseRow, DisplayCol(AEd.View, ATarget.UseRow, AToCol));
  Result.EndBlock;
  VnpLog('Block: %d:%d - %d:%d, SyncMode vorher %d', [Result.StartingRow,
    Result.StartingColumn, Result.EndingRow, Result.EndingColumn,
    Ord(Result.SyncMode)]);
end;

// Der Block je Variante: fuer die eigenen Punkte die ganzen Zeilen; fuer
// die IDE-eigene Suche (SyncEditBlock(nil)) nur vom Namen in der
// Deklaration bis hinter seine letzte Verwendung - so kommen moeglichst
// wenige andere Bezeichner in den Block (die IDE koppelt jeden, der darin
// mehrfach vorkommt).
function SelectFor(AVariant: TVnpVariant; const AEd: TVnpEditor;
  const ATarget: TVnpTarget): IOTAEditBlock;
var
  LastCol : Integer;
begin
  if AVariant = vvOwnPoints then
    Exit(SelectRange(AEd, ATarget, 1, Length(ATarget.Plan.NewUseLine) + 1));
  LastCol := ATarget.Plan.NewCols[High(ATarget.Plan.NewCols)];
  Result := SelectRange(AEd, ATarget, ATarget.Plan.NameCol,
    LastCol + Length(ATarget.Name));
end;

// Schritt 3 je Variante.
procedure StartSync(AVariant: TVnpVariant; const ABlock: IOTAEditBlock;
  const ATarget: TVnpTarget);
var
  Points : IOTASyncEditPoints;
  Err    : string;
begin
  if AVariant = vvIdeOnly then
  begin
    VnpLog('  ohne eigene Objekte');
    ABlock.SyncEditBlock(nil);
  end
  else if MakePoints(ATarget.Name, OffsetsOf(ATarget), Points, Err) then
  begin
    KeepAlive(Points);
    ABlock.SyncEditBlock(Points);
  end;
end;

// Nach dem Start nur protokollieren: wo die IDE den Caret hingesetzt hat
// und wo der Name steht (ReSharper: der Caret steht im umrandeten Namen).
// Was steht WIRKLICH im Puffer (Zeilen frisch gelesen) und ist der Puffer
// als geaendert markiert? Lauf 3: der Editor zeigte noch den alten Text,
// die Datei war nicht als geaendert markiert, der Puffer aber zerstoert.
procedure LogBufferState(const AEd: TVnpEditor; const ATarget: TVnpTarget;
  const AWhen: string);
var
  Use : string;
begin
  Use := ReadRow(AEd.View, ATarget.UseRow);
  VnpLog('%s: Puffer geaendert=%s', [AWhen,
    BoolToStr(AEd.Buffer.Modified, True)]);
  VnpLog('  Zeile %d: "%s"', [ATarget.DeclRow,
    ReadRow(AEd.View, ATarget.DeclRow)]);
  VnpLog('  Zeile %d: "%s"', [ATarget.UseRow, Use]);
  if Use <> ATarget.Plan.NewUseLine then
    VnpLog('  ABWEICHUNG - geplant war: "%s"', [ATarget.Plan.NewUseLine]);
end;

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
  LogBufferState(AEd, ATarget, 'Nach dem Sitzungsstart');
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
  ATarget.SourceRow := Row;
  ATarget.PrevRow := PrevCodeRow(AEd, Row);
  ATarget.Plan := PlanIntroduce(AEd.Lines[Row - 1],
    LineOrEmpty(AEd, ATarget.PrevRow), Col, ATarget.Name);
  if ATarget.Plan.Ok and ATarget.Plan.Wrap
     and (Row >= Length(AEd.Starts)) then
    ATarget.Plan.Reason := 'die Anweisung ist die letzte Zeile ohne '
      + 'Zeilenende - kein Platz fuer end;';
  if not ATarget.Plan.Ok or (ATarget.Plan.Reason <> '') then
  begin
    VnpLog('Abbruch: %s', [ATarget.Plan.Reason]);
    Exit;
  end;
  // Mit Block steht 'begin' ueber der Deklaration: beide eine Zeile tiefer.
  ATarget.DeclRow := Row + Ord(ATarget.Plan.Wrap);
  ATarget.UseRow := ATarget.DeclRow + 1;
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
        GLast := Target;
        LogBufferState(Ed, Target, 'Nach dem Schreiben');
        Block := SelectFor(AVariant, Ed, Target);
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

procedure ProbeSession;
var
  Ed    : TVnpEditor;
  Caret : TOTAEditPos;
begin
  VnpLog('=== Sonde Sitzung jetzt ===');
  if not OpenEditor(Ed) then
  begin
    VnpLog('Abbruch: keine Editoransicht');
    Exit;
  end;
  Caret := Ed.View.CursorPos;
  VnpLog('SyncMode %d (0 keine, 1 normal, 2 Templates), Caret %d:%d',
    [Ord(Ed.View.Block.SyncMode), Caret.Line, Caret.Col]);
  if GLast.DeclRow < 1 then
  begin
    // SCA162-Fehlalarm: "des" im deutschen Text als Krypto-Algorithmus DES.
    // noinspection InsecureCryptoAlgorithm
    VnpLog('(noch kein Lauf in dieser Sitzung des Pakets)');
    Exit;
  end;
  LogBufferState(Ed, GLast, 'Jetzt');
end;

end.
