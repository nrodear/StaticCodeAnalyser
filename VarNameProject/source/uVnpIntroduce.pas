unit uVnpIntroduce;

// VarNameProject - Code-Aktion "Lokale Konstante einfuehren" (bis E26
// "Lokale Variable einfuehren": eine Zahl wird zur Inline-Konstante, Nico
// 2026-10-13 - sie behaelt Faltung, Ueberladungswahl und die
// vorzeichenlose Rechnung des Literals, siehe uVnpPlan), Ablauf wie bei
// ReSharper "Introduce Variable" (Nico 2026-10-11, E17):
//   1. Caret auf einem Zahl-Literal, z. B. 'Result := Value * 42 + 42;'.
//   2. Darueber entsteht 'const MagicNr01 = 42;', die gleichen Literale
//      der Zeile werden zu MagicNr01.
//   3. Die Stellen von MagicNr01 werden gekoppelt: die IDE umrandet sie,
//      der Caret steht auf dem Namen, Tippen aendert alle Stellen mit.
// Zwei Wege (Gutachten 2026-10-11), beide nur mit IDE-eigenen Objekten:
//   C1h  wir schreiben (EIN Writer, EIN Strg+Z), markieren den Block vom
//        Namen bis hinter seine letzte Verwendung und starten das IDE-
//        eigene Sync Edit (SyncEditBlock(nil) = Strg+Umschalt+J). Koppelt
//        JEDEN Bezeichner, der im Block mehrfach vorkommt; Ende mit dem
//        Knopf im Rand - NICHT mit Esc: Esc zerstoert im Sync Edit der IDE
//        Text, auch ohne unseren Code (UI-Test 2026-10-11, E25); Enter
//        tut dort nichts.
//   D1   ein Live Template zur Laufzeit: wir loeschen die Anweisung, die
//        IDE fuegt Deklaration und Anweisung als Template ein und startet
//        die Template-Sitzung. Nur der Name ist ein Punkt; laut Hilfe
//        "Live Templates" beenden Enter oder Tab am letzten Punkt (Esc
//        dort ungeprueft - im Sync Edit zerstoert es Text).
// Vor jedem Lauf (Schritt 0): kein vergifteter Prozess (uVnpSync), keine
// laufende Sitzung, der Editor hat den Fokus.
//
// WAS geschrieben wird, rechnet uVnpEdits ohne ToolsAPI (getestet in
// tests\, auch unter FPC); diese Unit liest den Puffer, wendet die
// Ersetzungen mit EINEM IOTAEditWriter an und steuert die IDE.
//
// TOTACharPos: CharIndex 0-basiert in ZEICHEN der Zeile (Tab = 1), Line
// 1-basiert - gemessen 2026-10-11 (Sonde M10, 'Gruesse EUR': CharIndex 20
// bei 20 Zeichen = 24 Bytes). ACHTUNG: CharPosToPos addiert CharIndex als
// BYTES zum Zeilenanfang - auf Zeilen mit Nicht-ASCII davor stimmt es also
// nicht; Pufferpositionen rechnet dieses Projekt selbst (Reader-Bytes).

interface

type
  TVnpVariant = (vvIdeSync, vvTemplate);

const
  VARIANT_CAPTIONS : array[TVnpVariant] of string = (
    'Lokale Konstante einfuehren - C1h (IDE-Sync-Edit)',
    'Lokale Konstante einfuehren - D1 (Live Template)');

// Der ganze Ablauf an der Caret-Position der obersten Editoransicht.
procedure RunIntroduce(AVariant: TVnpVariant);

// Sonde, nur Datei-Protokoll (fasst die Sitzung nicht an): SyncMode,
// Caret, Datei, Geaendert-Zustand und die beiden Zeilen des letzten Laufs
// frisch aus dem Puffer - beliebig oft (nach dem Tippen, nach Enter, nach
// Strg+Z).
procedure ProbeSession;

// Abbau: das Template von D1 aus der Liste der IDE nehmen und seine
// Dateien loeschen; idempotent, nur Datei-Protokoll.
procedure ReleaseTemplate;

implementation

uses
  System.SysUtils, System.IOUtils, Vcl.Controls, ToolsAPI, ToolsAPI.Editor,
  CodeTemplateAPI, uVnpPlan, uVnpEdits, uVnpLog, uVnpSync, uVnpProbe;

const
  NAME_BASE = 'MagicNr';
  ABORT_FMT = 'Abbruch: %s';

type
  // Der Editor und sein Text beim Start.
  TVnpEditor = record
    View   : IOTAEditView;
    Buffer : IOTAEditBuffer;
    T      : TVnpText;
  end;

var
  // Das Ziel des letzten erfolgreichen Laufs - fuer ProbeSession.
  GLast         : TVnpTarget;
  // D1 hat in dieser Ladung ein Template geladen - der Abbau raeumt auf.
  GTemplateUsed : Boolean = False;

// Puffer als UTF-8-Bytes (Reader in Bloecken), daraus Zeilen, Byte-Anfaenge
// und Zeilenende (uVnpEdits.TextOf).
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
  AEd.T := TextOf(Bytes);
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

// Was steht WIRKLICH im Puffer (beide Zeilen frisch gelesen), und ist er
// als geaendert markiert? Lauf 3: der Editor zeigte noch den alten Text,
// die Datei war nicht als geaendert markiert, der Puffer aber zerstoert.
// Nach dem Umbenennen ist die Abweichung vom Plan gewollt. Nur die Zeilen -
// ins Protokoll schreibt der Aufrufer (die Sonde nur in die Datei).
function BufferStateLines(const AEd: TVnpEditor; const ATarget: TVnpTarget;
  const AWhen: string): TArray<string>;
var
  Decl, Use : string;
begin
  Decl := ReadRow(AEd.View, ATarget.DeclRow);
  Use := ReadRow(AEd.View, ATarget.UseRow);
  Result := [Format('%s: Puffer geaendert=%s', [AWhen,
    BoolToStr(AEd.Buffer.Modified, True)]),
    Format('  Zeile %d: "%s"', [ATarget.DeclRow, Decl]),
    Format('  Zeile %d: "%s"', [ATarget.UseRow, Use])];
  if Decl <> ATarget.Plan.DeclText then
    Result := Result + [Format('  ABWEICHUNG Zeile %d - geplant war: "%s"',
      [ATarget.DeclRow, ATarget.Plan.DeclText])];
  if Use <> ATarget.Plan.NewUseLine then
    Result := Result + [Format('  ABWEICHUNG Zeile %d - geplant war: "%s"',
      [ATarget.UseRow, ATarget.Plan.NewUseLine])];
end;

procedure LogBufferState(const AEd: TVnpEditor; const ATarget: TVnpTarget;
  const AWhen: string);
var
  S : string;
begin
  for S in BufferStateLines(AEd, ATarget, AWhen) do
    VnpLog(S);
end;

// Nach dem Start nur protokollieren: SyncMode, wo die IDE den Caret
// hingesetzt hat und wo der Name steht (ReSharper: der Caret steht im
// umrandeten Namen), dazu beide Zeilen. Kein Paint - das zoege den
// Zeichenpfad (DrawMark > SendSyncEvent) synchron in diesen Handler
// (Review 2026-10-11, Befund 7).
procedure AfterStart(const AEd: TVnpEditor; const ATarget: TVnpTarget;
  const AWhen: string);
var
  Caret : TOTAEditPos;
begin
  Caret := AEd.View.CursorPos;
  AEd.View.MoveViewToCursor;
  VnpLog('%s: SyncMode %d (0 keine, 1 normal, 2 Templates), Caret %d:%d, '
    + 'Name in der Deklaration bei %d:%d', [AWhen,
    Ord(AEd.View.Block.SyncMode), Caret.Line, Caret.Col, ATarget.DeclRow,
    DisplayCol(AEd.View, ATarget.DeclRow, ATarget.Plan.NameCol)]);
  LogBufferState(AEd, ATarget, AWhen);
end;

// Nach einer Zugriffsverletzung in einem Lauf: den Prozess-Merker setzen
// und nur in die Datei schreiben - KEIN ShowMessageView, die IDE ist in
// einem halb kaputten Zustand (Review 2026-10-11, Befund 1: der zweite
// Stack von Lauf 4 kam nach unserem Handler aus der Nachrichtenschleife).
procedure AfterExternal(const E: Exception; const AWhere: string);
begin
  VnpSetPoison(Format('%s in %s: %s', [E.ClassName, AWhere, E.Message]));
  VnpLogFileOnly('FEHLER %s in %s: %s', [E.ClassName, AWhere, E.Message]);
  VnpLogFileOnly('-> Dateien sichern, IDE beenden (Task-Manager pruefen), '
    + 'in diesem Prozess nicht weitertesten');
end;

// Die Meldungsansicht nur nach vorn holen, wenn keine Sitzung laeuft - sonst
// faellt ein Fokuswechsel in die Sitzung.
procedure ShowLogIfIdle(const AView: IOTAEditView);
begin
  if (AView <> nil) and (AView.Block.SyncMode = smNone) then
    VnpShowLog;
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

// Schritt 0, bevor irgendetwas geaendert wird: kein vergifteter Prozess und
// keine laufende Sitzung (bisher wurde SyncMode erst nach dem Schreiben
// gelesen - ein zweiter Start mitten in einer Sitzung haette unter ihr
// geschrieben).
function Refused(const AView: IOTAEditView): Boolean;
var
  Why  : string;
  Mode : TOTASyncMode;
begin
  Mode := smNone;
  Why := VnpPoisonReason;
  if Why <> '' then
    Why := 'dieser IDE-Prozess hatte eine Zugriffsverletzung (' + Why
      + ') - Dateien sichern, IDE beenden, Task-Manager pruefen'
  else
  begin
    Mode := AView.Block.SyncMode;
    // Nicht "mit Esc beenden": Esc zerstoert im Sync Edit der IDE Text
    // (UI-Test 2026-10-11); die Sitzung endet mit dem Knopf im Rand.
    if Mode <> smNone then
      Why := Format('Sync-Sitzung laeuft (SyncMode %d) - erst beenden '
        + '(Knopf im Rand; nicht Esc, das zerstoert Text)', [Ord(Mode)]);
  end;
  Result := Why <> '';
  if Result then
    VnpLog(ABORT_FMT, [Why])
  else
    VnpLog('Vor dem Start: SyncMode %d (0 keine, 1 normal, 2 Templates)',
      [Ord(Mode)]);
end;

// Der Editor bekommt den Fokus VOR dem Start, damit kein Fokuswechsel in
// die Sitzung faellt (Lauf 2 stuerzte in WMKillFocus ab). Kam der Start
// aus der Meldungsansicht, liegt der Fokus dort.
procedure EnsureFocus(const AView: IOTAEditView);
var
  Svc : INTACodeEditorServices;
  Ctl : TWinControl;
begin
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
  begin
    VnpLog('Fokus: INTACodeEditorServices fehlt - nicht geprueft');
    Exit;
  end;
  Ctl := Svc.GetEditorForView(AView);
  if Ctl = nil then
  begin
    VnpLog('Fokus: kein Editor-Steuerelement zur Ansicht - nicht geprueft');
    Exit;
  end;
  if Ctl.Focused then
  begin
    VnpLog('Fokus: der Editor hat ihn');
    Exit;
  end;
  Svc.FocusTopEditor;
  VnpLog('Fokus: der Editor hatte ihn NICHT - FocusTopEditor, jetzt %s',
    [BoolToStr(Ctl.Focused, True)]);
end;

// Schritt 1: das Ziel an der Caret-Position (uVnpEdits.TargetAt) -
// schreibt nichts. False mit Protokolleintrag, wenn es nichts zu tun gibt.
function PlanAtCaret(var AEd: TVnpEditor; out ATarget: TVnpTarget): Boolean;
var
  Row, Col : Integer;
begin
  ReadEditor(AEd);
  CaretOf(AEd, Row, Col);
  ATarget := TargetAt(AEd.T, Row, Col, NAME_BASE);
  ATarget.FileName := AEd.Buffer.FileName;
  Result := ATarget.Plan.Ok;
  if not Result then
    VnpLog(ABORT_FMT, [ATarget.Plan.Reason]);
end;

// Die Ersetzungen mit EINEM Writer - ein Undo-Schritt. Aufsteigend:
// CopyTo bis zum Offset, Len Bytes verwerfen, Text einfuegen (genau so
// stellt uVnpEdits.ApplyByteEdits den Writer fuer die Tests nach).
procedure ApplyWithWriter(const ABuffer: IOTAEditBuffer;
  const AEdits: array of TVnpByteEdit);
var
  Writer : IOTAEditWriter;
  i      : Integer;
begin
  Writer := ABuffer.CreateUndoableWriter;
  try
    for i := 0 to High(AEdits) do
    begin
      Writer.CopyTo(AEdits[i].Offset);
      if AEdits[i].Len > 0 then
        Writer.DeleteTo(AEdits[i].Offset + AEdits[i].Len);
      if AEdits[i].Text <> '' then
        Writer.Insert(PAnsiChar(UTF8Encode(AEdits[i].Text)));
    end;
  finally
    Writer := nil;   // erst die Freigabe schreibt in den Puffer
  end;
end;

{ C1h: IDE-eigenes Sync Edit }

// Deklaration ueber die Zeile, Literale ersetzen, bei Plan.Wrap begin/end -
// die Ersetzungen rechnet uVnpEdits.IntroduceEdits.
procedure WriteEdits(const AEd: TVnpEditor; const ATarget: TVnpTarget);
var
  Block : string;
begin
  ApplyWithWriter(AEd.Buffer, IntroduceEdits(AEd.T, ATarget));
  Block := '';
  if ATarget.Plan.Wrap then
    Block := ' - in begin..end (Zweig ohne begin)';
  VnpLog('Geschrieben: "%s" + %d Ersetzung(en) in "%s"%s',
    [ATarget.Plan.DeclText, Length(ATarget.Plan.OldCols),
    ATarget.Plan.NewUseLine, Block]);
end;

// Den Block vom Namen in der Deklaration bis hinter seine letzte
// Verwendung markieren (btNonInclusive): so kommen moeglichst wenige
// andere Bezeichner hinein (die IDE koppelt jeden, der im Block mehrfach
// vorkommt), und den Caret bekommt der Name. Ueber View.Position, nicht
// Buffer.EditPosition - das ist der Cursor der obersten Ansicht des
// Puffers, nicht zwingend dieser. nil mit Protokolleintrag, wenn ein Move
// scheitert. Das Protokoll nennt die an Move uebergebenen Anzeige-Spalten
// und, getrennt, was der Block selbst meldet: auf Tab-Zeilen sind das
// Zeichen-Spalten (Lauf 6, Fall 5; CnPack warnt ebenso). Das Ende kommt
// aus uVnpEdits.SyncBlockEnd: auf Zeilen mit Nicht-ASCII vor dem Ende ist
// es der Anfang der Folgezeile (UI-Test 2026-10-11, Fall 6).
function SelectFromName(const AEd: TVnpEditor;
  const ATarget: TVnpTarget): IOTAEditBlock;
var
  EdPos   : IOTAEditPosition;
  FromCol : Integer;
  ToRow   : Integer;
  ToCol   : Integer;
begin
  FromCol := DisplayCol(AEd.View, ATarget.DeclRow, ATarget.Plan.NameCol);
  SyncBlockEnd(AEd.T, ATarget, ToRow, ToCol);
  ToCol := DisplayCol(AEd.View, ToRow, ToCol);
  Result := AEd.View.Block;
  EdPos := AEd.View.Position;
  Result.Reset;
  Result.Style := btNonInclusive;
  if not EdPos.Move(ATarget.DeclRow, FromCol) then
  begin
    VnpLog('Abbruch: Move(%d, %d) zum Namen gescheitert',
      [ATarget.DeclRow, FromCol]);
    Exit(nil);
  end;
  Result.BeginBlock;
  if not EdPos.Move(ToRow, ToCol) then
  begin
    Result.Reset;
    VnpLog('Abbruch: Move(%d, %d) hinter die letzte Verwendung gescheitert',
      [ToRow, ToCol]);
    Exit(nil);
  end;
  Result.EndBlock;
  VnpLog('Block: Move %d:%d - %d:%d (Anzeige-Spalten), der Block meldet '
    + '%d:%d - %d:%d, SyncMode vorher %d', [ATarget.DeclRow, FromCol,
    ToRow, ToCol, Result.StartingRow, Result.StartingColumn,
    Result.EndingRow, Result.EndingColumn, Ord(Result.SyncMode)]);
  if ToRow <> ATarget.UseRow then
    VnpLog('  Blockende am Anfang der Folgezeile: Nicht-ASCII vor der letzten '
      + 'Verwendung (SyncEditBlock liest das Ende als Bytes)');
end;

// Den Block nach einer Zugriffsverletzung leeren - sonst laeuft das
// naechste Zeichnen ueber DrawMark > ShowSyncButton > SendSyncEvent in
// dieselbe AV (Lauf 4).
procedure ResetAfterAv(const ABlock: IOTAEditBlock);
begin
  try
    ABlock.Reset;
  except
    on E: EExternal do
      VnpLogFileOnly('Block.Reset nach der AV gescheitert: %s', [E.Message]);
  end;
end;

// Die IDE-eigene Suche (= Strg+Umschalt+J). Eine Zugriffsverletzung hier
// heisst: die Notifier-Liste des Sync-Edit-Managers ist vergiftet (H1).
function StartIdeSync(const ABlock: IOTAEditBlock): Boolean;
begin
  Result := True;
  try
    ABlock.SyncEditBlock(nil);
  except
    on E: EExternal do
    begin
      AfterExternal(E, 'SyncEditBlock');
      Result := False;
    end;
  end;
  if not Result then
    ResetAfterAv(ABlock);
end;

procedure RunIdeSync(const AEd: TVnpEditor; const ATarget: TVnpTarget);
var
  Block : IOTAEditBlock;
begin
  WriteEdits(AEd, ATarget);
  GLast := ATarget;
  LogBufferState(AEd, ATarget, 'Nach dem Schreiben');
  Block := SelectFromName(AEd, ATarget);
  if (Block <> nil) and StartIdeSync(Block) then
    AfterStart(AEd, ATarget, 'Nach SyncEditBlock');
end;

{ D1: Live Template }

// Erster Ort: ein eigener Ordner unter %TEMP% - die IDE liest ihn beim
// Start nicht, nach einem Absturz bleibt also nichts in ihrer Liste.
function TplTempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'VarNameProject\tpl');
end;

// Rueckfall B-b: der Ordner fuer Templates von Drittanbietern (DUnitX legt
// dort einen Unterordner an), den ReloadTemplates mitliest. Ohne
// Versionsnummer - Delphi 13 saehe die Datei mit.
function TplUserDir: string;
begin
  Result := TPath.Combine(TPath.GetDocumentsPath,
    'Embarcadero\Studio\code_templates\VarNameProject');
end;

// Ein Eintrag dieses Pakets (uVnpEdits.IsOwnTemplate). CodeObjects[i] kann
// nil sein (CnPack prueft es).
function IsOwn(const T: IOTACodeTemplate): Boolean;
begin
  Result := (T <> nil) and IsOwnTemplate(T.Shortcut, T.FileName);
end;

function FindOwn(const ACts: IOTACodeTemplateServices): Integer;
var
  i : Integer;
begin
  for i := 0 to ACts.CodeObjectCount - 1 do
    if IsOwn(ACts.CodeObjects[i]) then
      Exit(i);
  Result := -1;
end;

// Datei eines fremden Eintrags mit unserem Kuerzel (Nutzer-Template) oder
// '' - dann bricht D1 ab.
function ForeignTemplate(const ACts: IOTACodeTemplateServices): string;
var
  i : Integer;
  T : IOTACodeTemplate;
begin
  for i := 0 to ACts.CodeObjectCount - 1 do
  begin
    T := ACts.CodeObjects[i];
    if (T <> nil) and SameText(T.Shortcut, TPL_NAME) and not IsOwn(T) then
      Exit(T.FileName);
  end;
  Result := '';
end;

// Alle eigenen Eintraege aus der Liste der IDE nehmen; ihre Zahl.
function RemoveOwnTemplates(const ACts: IOTACodeTemplateServices): Integer;
var
  i : Integer;
  T : IOTACodeTemplate;
begin
  Result := 0;
  for i := ACts.CodeObjectCount - 1 downto 0 do
  begin
    T := ACts.CodeObjects[i];
    if IsOwn(T) then
    begin
      ACts.RemoveTemplate(T);
      Inc(Result);
    end;
  end;
end;

// Die Template-Dateien beider Orte loeschen (vielleicht tut RemoveTemplate
// es schon selbst - Messpunkt D-M8); den Ordner unter code_templates nur,
// wenn er leer ist.
procedure DeleteTemplateFiles;
var
  Dirs   : TArray<string>;
  Dir, F : string;
begin
  Dirs := [TplTempDir, TplUserDir];
  for Dir in Dirs do
  begin
    F := TPath.Combine(Dir, TPL_FILE);
    if FileExists(F) and not DeleteFile(F) then
      VnpLogFileOnly('  Template-Datei nicht geloescht: %s', [F]);
  end;
  if DirectoryExists(TplUserDir) then
    RemoveDir(TplUserDir);   // scheitert, solange etwas darin liegt - gewollt
end;

procedure SaveTemplateFile(const ADir, ACode, AName: string);
begin
  ForceDirectories(ADir);
  TFile.WriteAllText(TPath.Combine(ADir, TPL_FILE), TemplateXml(ACode, AName),
    TEncoding.UTF8);
end;

// Template schreiben und laden; sein Index in der Liste der IDE oder -1
// (mit Protokoll - dann ist im Editor noch nichts geaendert). Erst
// LoadTemplates auf den Temp-Ordner (Messpunkt D-M1: haengt es an oder
// ersetzt es die Liste?); steht der Eintrag danach nicht in der Liste
// oder ist sie nicht gewachsen, Rueckfall B-b.
function LoadOwnTemplate(const ACts: IOTACodeTemplateServices;
  const ACode, AName: string): Integer;
var
  Before  : Integer;
  Foreign : string;
begin
  Before := RemoveOwnTemplates(ACts);
  if Before > 0 then
    VnpLog('Alte eigene Templates aus der Liste genommen: %d', [Before]);
  Foreign := ForeignTemplate(ACts);
  if Foreign <> '' then
  begin
    VnpLog('Abbruch: ein fremdes Template heisst schon "%s" (%s)',
      [TPL_NAME, Foreign]);
    Exit(-1);
  end;
  SaveTemplateFile(TplTempDir, ACode, AName);
  Before := ACts.CodeObjectCount;
  ACts.LoadTemplates(IncludeTrailingPathDelimiter(TplTempDir));
  Result := FindOwn(ACts);
  VnpLog('LoadTemplates(%s): Templates %d -> %d, eigenes: Index %d',
    [TplTempDir, Before, ACts.CodeObjectCount, Result]);
  if (Result >= 0) and (ACts.CodeObjectCount > Before) then
    Exit;
  if ACts.CodeObjectCount < Before then
    VnpLog('  LoadTemplates hat die Liste ERSETZT, nicht ergaenzt');
  SaveTemplateFile(TplUserDir, ACode, AName);
  Before := ACts.CodeObjectCount;
  ACts.ReloadTemplates;
  Result := FindOwn(ACts);
  VnpLog('Rueckfall B-b, %s + ReloadTemplates: Templates %d -> %d, '
    + 'eigenes: Index %d', [TplUserDir, Before, ACts.CodeObjectCount, Result]);
  if Result < 0 then
    VnpLog('Abbruch: das Template steht nicht in der Liste der IDE - '
      + 'nichts geaendert');
end;

// Was die IDE aus der Datei gemacht hat (Messpunkte D-M2, D-M4): Kuerzel,
// Datei, Art, Editor-Optionen, Aufruf, Punkte und der zurueckgelesene Code
// mit sichtbaren Zeilenenden (XML macht aus CR LF im CDATA ein LF). Nur
// Messung: ein Fehler hier bricht den Lauf nicht ab.
procedure LogTemplate(const ACts: IOTACodeTemplateServices; AIndex: Integer);
var
  T : IOTACodeTemplate;
  P : IOTACodeTemplatePoint;
  i : Integer;
begin
  try
    T := ACts.CodeObjects[AIndex];
    VnpLog('Template %d: Kuerzel "%s", Datei %s, Sprache %s, Kind %d, '
      + 'EditorOpts "%s", Aufruf %d, FindByID %d', [AIndex, T.Shortcut,
      T.FileName, T.Language, Ord(T.Kind), T.EditorOpts, Ord(T.InvokeKind),
      ACts.FindByID(TPL_NAME,
      ACts.LanguageToOptionID(sTemplateLanguageDelphi))]);
    for i := 0 to T.PointsCount - 1 do
    begin
      P := T.Points[i];
      if P <> nil then
        VnpLog('  Punkt %d: ID "%s", Wert "%s", editierbar %s', [i, P.ID,
          P.Value, BoolToStr(P.Editable, True)]);
    end;
    VnpLog('  Code zurueck: "%s"', [StringReplace(StringReplace(T.Code,
      #13, '\r', [rfReplaceAll]), #10, '\n', [rfReplaceAll])]);
  except
    on EExternal do
      raise;
    // Messung: die Angaben sind Beiwerk, der Lauf geht weiter.
    // noinspection ExceptionTooGeneral
    on E: Exception do
      VnpLog('  (Template-Angaben unvollstaendig: %s: %s)',
        [E.ClassName, E.Message]);
  end;
end;

// Die geloeschte Anweisung wieder hinter die Einrueckung schreiben.
procedure RestoreStatement(const AEd: TVnpEditor; const ATarget: TVnpTarget);
begin
  ApplyWithWriter(AEd.Buffer, [StatementRestoreEdit(AEd.T, ATarget)]);
  VnpLog('Anweisung wiederhergestellt: "%s"',
    [AEd.T.Lines[ATarget.SourceRow - 1]]);
end;

// Die Anweisung zurueckschreiben, wenn ihre Zeile noch leer ist (nur die
// Einrueckung); sonst nur ein Protokolleintrag - das Original steht oben.
procedure RestoreIfBlank(const AEd: TVnpEditor; const ATarget: TVnpTarget);
begin
  if Trim(ReadRow(AEd.View, ATarget.SourceRow)) = '' then
    RestoreStatement(AEd, ATarget)
  else
    VnpLog('Die Zeile ist nicht leer - nichts wiederhergestellt (das '
      + 'Original steht oben)');
end;

// Den Caret hinter die Einrueckung der jetzt leeren Zeile setzen - dort
// fuegt InsertCode ein. Ein markierter Block gaelte als |selected|: weg.
function CaretAfterIndent(const AEd: TVnpEditor;
  const ATarget: TVnpTarget): Boolean;
var
  Row, Col : Integer;
begin
  Row := ATarget.SourceRow;
  AEd.View.Block.Reset;
  Col := DisplayCol(AEd.View, Row, Length(ATarget.Plan.Indent) + 1);
  Result := AEd.View.Position.Move(Row, Col);
  VnpLog('Caret fuer InsertCode: Move(%d, %d) = %s', [Row, Col,
    BoolToStr(Result, True)]);
end;

// InsertCode an der Caret-Position. Eine gewoehnliche Ausnahme darf die
// geloeschte Anweisung nicht verschlucken: zurueckschreiben, dann weiter
// an RunIntroduce (eine EExternal geht unveraendert weiter - dort setzt
// RunIntroduce den Prozess-Merker; das Original steht im Protokoll).
function InsertTemplate(const ACts: IOTACodeTemplateServices;
  AIndex: Integer; const AEd: TVnpEditor;
  const ATarget: TVnpTarget): Boolean;
begin
  try
    Result := ACts.InsertCode(AIndex, AEd.View, False);
  except
    on EExternal do
      raise;
    on Exception do
    begin
      RestoreIfBlank(AEd, ATarget);
      raise;
    end;
  end;
end;

// Mischt das Einfuegen Zeilenenden? Das XML liefert den Code mit LF.
procedure LogLoneLf(const AEd: TVnpEditor; ABefore: Integer);
var
  Fresh : TVnpEditor;
  Kind  : string;
begin
  Fresh := Default(TVnpEditor);
  Fresh.View := AEd.View;
  Fresh.Buffer := AEd.Buffer;
  ReadEditor(Fresh);
  Kind := 'LF';
  if AEd.T.Eol = #13#10 then
    Kind := 'CR LF';
  VnpLog('Einzelne LF in der Datei: vorher %d, nachher %d (Zeilenende der '
    + 'Datei: %s)', [ABefore, LoneLfCount(Fresh.T.Text), Kind]);
end;

// D1: Template laden, die Anweisung loeschen (die Einrueckung bleibt),
// Caret hinter die Einrueckung, InsertCode - die IDE fuegt Deklaration und
// Anweisung ein und startet die Template-Sitzung (erwartet: SyncMode 2).
// Liefert InsertCode False oder wirft eine gewoehnliche Ausnahme, kommt die
// Anweisung zurueck, wenn ihre Zeile noch leer ist.
procedure RunTemplate(const AEd: TVnpEditor; const ATarget: TVnpTarget);
var
  Cts    : IOTACodeTemplateServices;
  Code   : string;
  Why    : string;
  Idx    : Integer;
  LoneLf : Integer;
  Ok     : Boolean;
begin
  Code := TemplateCode(ATarget.Plan, ATarget.Name, TPL_POINT, AEd.T.Eol,
    Why);
  if Code = '' then
  begin
    VnpLog(ABORT_FMT, [Why]);
    VnpShowLog;
    Exit;
  end;
  if not Supports(BorlandIDEServices, IOTACodeTemplateServices, Cts) then
  begin
    VnpLog('Abbruch: die IDE kennt IOTACodeTemplateServices nicht');
    VnpShowLog;
    Exit;
  end;
  GTemplateUsed := True;
  Idx := LoadOwnTemplate(Cts, Code, ATarget.Name);
  if Idx < 0 then
  begin
    VnpShowLog;
    Exit;
  end;
  LogTemplate(Cts, Idx);
  VnpLog('Anweisung Zeile %d (wird ersetzt): "%s"', [ATarget.SourceRow,
    AEd.T.Lines[ATarget.SourceRow - 1]]);
  LoneLf := LoneLfCount(AEd.T.Text);
  ApplyWithWriter(AEd.Buffer, [StatementDeleteEdit(AEd.T, ATarget)]);
  if not CaretAfterIndent(AEd, ATarget) then
  begin
    RestoreStatement(AEd, ATarget);
    VnpShowLog;
    Exit;
  end;
  Ok := InsertTemplate(Cts, Idx, AEd, ATarget);
  AfterStart(AEd, ATarget, Format('Nach InsertCode (Ergebnis %s)',
    [BoolToStr(Ok, True)]));
  if not Ok then
  begin
    RestoreIfBlank(AEd, ATarget);
    ShowLogIfIdle(AEd.View);
    Exit;
  end;
  GLast := ATarget;
  LogLoneLf(AEd, LoneLf);
end;

procedure ReleaseTemplate;
var
  Cts : IOTACodeTemplateServices;
begin
  if GTemplateUsed
     and Supports(BorlandIDEServices, IOTACodeTemplateServices, Cts) then
    VnpLogFileOnly('  eigene Templates aus der Liste genommen: %d',
      [RemoveOwnTemplates(Cts)]);
  GTemplateUsed := False;
  DeleteTemplateFiles;
end;

procedure RunIntroduce(AVariant: TVnpVariant);
var
  Ed     : TVnpEditor;
  Target : TVnpTarget;
begin
  VnpLog('=== %s ===', [VARIANT_CAPTIONS[AVariant]]);
  if not OpenEditor(Ed) then
  begin
    VnpLog('Abbruch: keine Editoransicht');
    VnpShowLog;
    Exit;
  end;
  try
    if Refused(Ed.View) then
      Exit;
    EnsureFocus(Ed.View);
    if not PlanAtCaret(Ed, Target) then
    begin
      VnpShowLog;
      Exit;
    end;
    if AVariant = vvTemplate then
      RunTemplate(Ed, Target)
    else
      RunIdeSync(Ed, Target);
  except
    on EAbort do
      raise;
    on E: EExternal do
      AfterExternal(E, VARIANT_CAPTIONS[AVariant]);
    // Ein IDE-Plugin darf aus einem Menueklick keine Ausnahme in die IDE
    // werfen; jeder Fehler gehoert ins Protokoll (Messung).
    // noinspection ExceptionTooGeneral
    on E: Exception do
    begin
      VnpLog('FEHLER %s: %s', [E.ClassName, E.Message]);
      ShowLogIfIdle(Ed.View);
    end;
  end;
end;

procedure ProbeSession;
var
  Ed    : TVnpEditor;
  Caret : TOTAEditPos;
  S     : string;
begin
  VnpLogFileOnly('=== Sonde Sitzung jetzt ===');
  try
    if not OpenEditor(Ed) then
    begin
      VnpLogFileOnly('Abbruch: keine Editoransicht');
      Exit;
    end;
    Caret := Ed.View.CursorPos;
    VnpLogFileOnly('SyncMode %d (0 keine, 1 normal, 2 Templates), Caret '
      + '%d:%d, Datei %s', [Ord(Ed.View.Block.SyncMode), Caret.Line,
      Caret.Col, Ed.Buffer.FileName]);
    if GLast.DeclRow < 1 then
    begin
      VnpLogFileOnly('(noch kein Lauf seit dem Laden)');
      Exit;
    end;
    if not SameFileName(Ed.Buffer.FileName, GLast.FileName) then
    begin
      VnpLogFileOnly('Die oberste Ansicht zeigt nicht die Datei vom letzten '
        + 'Lauf (%s) - Zeilen nicht gelesen', [GLast.FileName]);
      Exit;
    end;
    for S in BufferStateLines(Ed, GLast, 'Jetzt') do
      VnpLogFileOnly(S);
  except
    on E: EExternal do
      AfterExternal(E, 'Sonde');
    // Die Sonde darf nie eine Ausnahme in die IDE werfen.
    // noinspection ExceptionTooGeneral
    on E: Exception do
      VnpLogFileOnly('FEHLER Sonde %s: %s', [E.ClassName, E.Message]);
  end;
end;

end.
