unit uRdxEditor;

// reDelphix - der einzige ToolsAPI-Teil des Moduls: Bereich im Editor
// markieren, Bereich ersetzen, Editor-Puffer lesen, Projekt-Units nachsehen
// (Konzept_SourceRefactor_Quellstellen Abschnitt 15.4b: H2/H3 wohnen im
// Modul).
//
// SCHREIBEN UEBER IOTAEditWriter MIT BYTE-POSITIONEN AUS DEMSELBEN PUFFER
//
// Zwei Anlaeufe ueber die Cursor-API (IOTAEditPosition) sind am 2026-10-06
// gescheitert: Read bewegt den Cursor nicht verbuergt (AH16), und
// GotoLine/MoveBOL/BackspaceDelete am Zeilenanfang zogen keine Zeilen
// zusammen (AH17) - die Cursor-API ist zeilengebunden und rechnet in
// Anzeigespalten. Deshalb jetzt der klassische Weg der IDE-Erweiterungen:
//   * der Puffer wird als UTF-8-BYTES gelesen (IOTAEditReader),
//   * Zeilenanfaenge und die Byte-Offsets von (Zeile, Zeichen-Spalte)
//     werden aus GENAU diesen Bytes berechnet,
//   * der Bereich wird mit CreateUndoableWriter.CopyTo/DeleteTo/Insert
//     ersetzt - Reader- und Writer-Positionen sind derselbe Byte-Raum.
// Spalten der IDE kommen nirgends vor; Tabulatoren, Umlaute und
// Zeilenenden (CRLF/LF/CR) sind damit gleichgueltig.
//
// NICHTS WIRD BLIND GESCHRIEBEN
//
// Vor dem Schreiben wird JEDER Bereich einer Aktion zweimal gegen den
// Scan-Text geprueft: als Zeilen (SpanText, wie der Dienst ihn gebildet
// hat) und als Bytes (der Ausschnitt, der tatsaechlich geloescht wird) -
// uRdxBufferMath.PlanByteEdits, getestet. Weicht einer ab, wird KEINER
// geschrieben. Dann laufen alle Ersetzungen durch EINEN
// CreateUndoableWriter: eine Aktion = ein Strg+Z (Review reDelphiX
// 2026-10-07, Major 3 - vorher je Ersetzung ein Writer, Strg+Z nahm nur
// die letzte zurueck und ein Fehler mittendrin liess den Puffer halb
// umgeformt). Jeder Schritt steht im Protokoll (uRdxLog,
// %TEMP%\reDelphix.log).

interface

uses
  uRefactorInfo, uRdxBufferMath;

type
  TRdxEditor = class
  public
    // Oeffnet die Datei (falls noetig), holt den Tab nach vorn und
    // markiert den Bereich.
    class function SelectSpan(const AFile: string;
      const ASpan: TRefactorSpan; out AError: string): Boolean; static;

    // Fuehrt alle Ersetzungen EINER Aktion aus - nur wenn der Puffer an
    // jedem Bereich den erwarteten Text enthaelt (Zeilenumbrueche als #10
    // verglichen), sonst keine. Ein Undo-Schritt fuer alle. Praefix vor
    // und Suffix hinter einem Bereich bleiben stehen; ein mehrzeiliger
    // Bereich wird zu dem, was NewText vorgibt.
    class function ReplaceSpans(const AFile: string;
      const AEdits: TArray<TRdxEdit>; out AError: string): Boolean; static;

    // True, wenn eine Unit namens AShortName zum aktiven Projekt gehoert
    // oder als AShortName.pas neben ANearFile liegt - dann darf ein
    // uses-Eintrag dieses Namens NICHT auf eine RTL-Unit expandiert werden.
    class function ProjectHasUnit(const AShortName,
      ANearFile: string): Boolean; static;

    // Liefert den aktuellen EDITOR-PUFFER der Datei (IOTAEditReader,
    // UTF-8 -> string) - nur wenn die Datei in der IDE offen ist; sie
    // wird dafuer nicht geoeffnet. False sonst. Der Anbieter beschreibt
    // die Stellen auf diesem Text, nicht auf der Platte: ungespeicherte
    // Aenderungen sind sonst ein Widerspruch zwischen Scan und Editor.
    class function TryReadBuffer(const AFile: string;
      out AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  ToolsAPI,
  uRdxLog;

const
  SNoEditor = 'Datei ist nicht im Editor geoeffnet';
  SNoView   = 'Editor-Ansicht nicht verfuegbar';
  SNoBuffer = 'Editor-Puffer nicht lesbar';
  SNoWriter = 'Editor-Puffer nicht beschreibbar';

function WithLogHint(const AMsg: string): string;
begin
  Result := AMsg + ' [Protokoll: ' + RdxLogPath + ']';
end;

function TryGetSourceEditor(const AFile: string; AOpen: Boolean;
  out ASrc: IOTASourceEditor): Boolean;
// Modul finden (oder oeffnen) -> erster IOTASourceEditor des Moduls.
// Nicht ModuleFileEditors[0]: bei einem Form-Modul kann dort der
// DFM-Editor stehen.
var
  ModSvc : IOTAModuleServices;
  ActSvc : IOTAActionServices;
  Module : IOTAModule;
  i      : Integer;
begin
  Result := False;
  ASrc   := nil;
  if AFile = '' then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  Module := ModSvc.FindModule(AFile);
  if (Module = nil) and AOpen then
  begin
    if Supports(BorlandIDEServices, IOTAActionServices, ActSvc) then
      ActSvc.OpenFile(AFile);
    Module := ModSvc.FindModule(AFile);
  end;
  if Module = nil then Exit;
  for i := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[i], IOTASourceEditor, ASrc) then
      Break;
  Result := ASrc <> nil;
end;

function TryGetView(const ASrc: IOTASourceEditor; out AView: IOTAEditView;
  out APos: IOTAEditPosition): Boolean;
// Erste Ansicht des Editors samt Cursor-API ihres Puffers.
begin
  Result := False;
  AView  := nil;
  APos   := nil;
  if (ASrc = nil) or (ASrc.EditViewCount = 0) then Exit;
  AView := ASrc.EditViews[0];
  if (AView = nil) or (AView.Buffer = nil) then Exit;
  APos := AView.Buffer.EditPosition;
  Result := APos <> nil;
end;

function ReadBufferBytes(const ASrc: IOTASourceEditor;
  out ABytes: TBytes): Boolean;
// IOTAEditReader liefert UTF-8-Bytes in Bloecken; der Reader wird vor
// dem Verlassen freigegeben - solange er lebt, darf niemand in den
// Puffer schreiben.
const
  BLOCK = 16384;
var
  Reader : IOTAEditReader;
  Chunk  : TBytes;
  Got    : Integer;
  Total  : Integer;
begin
  Result := False;
  SetLength(ABytes, 0);
  if ASrc = nil then Exit;
  Reader := ASrc.CreateReader;
  if Reader = nil then Exit;
  try
    Total := 0;
    repeat
      SetLength(Chunk, BLOCK);
      Got := Reader.GetText(Total, PAnsiChar(@Chunk[0]), BLOCK);
      if Got > 0 then
      begin
        SetLength(ABytes, Total + Got);
        Move(Chunk[0], ABytes[Total], Got);
        Inc(Total, Got);
      end;
    until Got < BLOCK;
  finally
    Reader := nil;
  end;
  Result := Length(ABytes) > 0;
end;

// LineStartsOf, OffsetOf, NormalizeEol, BufferEol, Visible und
// DescribeMismatch liegen seit Stufe 0 in uRdxBufferMath (getestet).

function DisplayPosOf(const AView: IOTAEditView; ALines: TStrings;
  ALine, ACol: Integer): TOTAEditPos;
// Zeichen-Spalte -> Anzeige-Spalte ueber die IDE selbst. TOTACharPos
// zaehlt die UTF-8-Bytes der Zeile (so handhaben es GExperts & Co.);
// fuer reinen ASCII-Code ist das die Zeichenzahl.
var
  CharPos : TOTACharPos;
  Prefix  : string;
begin
  Result.Line := ALine;
  Result.Col  := ACol;
  if (ALine < 1) or (ALine > ALines.Count) then Exit;
  Prefix := Copy(ALines[ALine - 1], 1, ACol - 1);
  CharPos.Line      := ALine;
  CharPos.CharIndex := Length(UTF8Encode(Prefix));
  AView.ConvertPos(False, Result, CharPos);
  Result.Line := ALine;
end;

{ TRdxEditor }

class function TRdxEditor.TryReadBuffer(const AFile: string;
  out AText: string): Boolean;
var
  Src   : IOTASourceEditor;
  Bytes : TBytes;
begin
  Result := False;
  AText  := '';
  if not TryGetSourceEditor(AFile, False, Src) then Exit;
  try
    if not ReadBufferBytes(Src, Bytes) then Exit;
    AText  := TEncoding.UTF8.GetString(Bytes);
    Result := AText <> '';
  except
    on E: Exception do
    begin
      RdxLog('TryReadBuffer %s: %s', [ExtractFileName(AFile), E.Message]);
      AText  := '';
      Result := False;
    end;
  end;
end;

class function TRdxEditor.SelectSpan(const AFile: string;
  const ASpan: TRefactorSpan; out AError: string): Boolean;
var
  Src   : IOTASourceEditor;
  View  : IOTAEditView;
  EdPos : IOTAEditPosition;
  Block : IOTAEditBlock;
  Lines : TStringList;
  Text  : string;
  P     : TOTAEditPos;
begin
  Result := False;
  AError := '';
  RdxLog('SelectSpan %s %d:%d-%d:%d', [ExtractFileName(AFile),
    ASpan.StartLine, ASpan.StartCol, ASpan.EndLine, ASpan.EndCol]);
  if not ASpan.IsValid then
  begin
    AError := 'kein gueltiger Bereich';
    Exit;
  end;
  if not TryGetSourceEditor(AFile, True, Src) then
  begin
    AError := SNoEditor;
    Exit;
  end;
  Lines := TStringList.Create;
  try
    try
      Src.Show;
      if not TryGetView(Src, View, EdPos) then
      begin
        AError := SNoView;
        Exit;
      end;
      if not TryReadBuffer(AFile, Text) then
      begin
        AError := SNoBuffer;
        Exit;
      end;
      Lines.Text := Text;
      Block := View.Block;
      if Block = nil then
      begin
        AError := SNoView;
        Exit;
      end;
      Block.Reset;
      P := DisplayPosOf(View, Lines, ASpan.StartLine, ASpan.StartCol);
      RdxLog('  Anfang Zeichen %d -> Anzeige %d', [ASpan.StartCol, P.Col]);
      if not EdPos.Move(P.Line, P.Col) then Exit;
      Block.BeginBlock;
      P := DisplayPosOf(View, Lines, ASpan.EndLine, ASpan.EndCol);
      RdxLog('  Ende Zeichen %d -> Anzeige %d', [ASpan.EndCol, P.Col]);
      if not EdPos.Move(P.Line, P.Col) then Exit;
      Block.EndBlock;
      View.MoveViewToCursor;
      View.Paint;
      Result := True;
    except
      on E: Exception do
        AError := E.Message;
    end;
  finally
    Lines.Free;
    if AError <> '' then RdxLog('  SelectSpan FEHLER: ' + AError);
  end;
end;

class function TRdxEditor.ReplaceSpans(const AFile: string;
  const AEdits: TArray<TRdxEdit>; out AError: string): Boolean;
var
  Src      : IOTASourceEditor;
  View     : IOTAEditView;
  EdPos    : IOTAEditPosition;
  Bytes    : TBytes;
  Plan     : TArray<TRdxByteEdit>;
  Writer   : IOTAEditWriter;
  NewUtf8  : UTF8String;
  i        : Integer;
  Removed  : Integer;
  Inserted : Integer;
begin
  Result := False;
  AError := '';
  RdxLog('ReplaceSpans %s, %d Ersetzung(en)', [ExtractFileName(AFile),
    Length(AEdits)]);
  for i := 0 to High(AEdits) do
    RdxLog('  %d:%d-%d:%d, neu "%s"', [AEdits[i].Span.StartLine,
      AEdits[i].Span.StartCol, AEdits[i].Span.EndLine, AEdits[i].Span.EndCol,
      Visible(AEdits[i].NewText)]);
  if not TryGetSourceEditor(AFile, True, Src) then
  begin
    AError := SNoEditor;
    RdxLog('  FEHLER: ' + AError);
    Exit;
  end;
  try
    try
      // 1) Puffer als Bytes; ALLE Bereiche pruefen, bevor einer
      //    geschrieben wird.
      if not ReadBufferBytes(Src, Bytes) then
      begin
        AError := SNoBuffer;
        Exit;
      end;
      if not PlanByteEdits(Bytes, AEdits, Plan, AError) then
        Exit;

      // 2) EIN Writer = EIN Undo-Schritt. Der Writer kopiert nur vorwaerts,
      //    deshalb aufsteigend (PlanByteEdits sortiert): Praefix kopieren,
      //    Bereich verwerfen, neuen Text einfuegen; den Rest kopiert die
      //    Freigabe des Writers.
      Writer := Src.CreateUndoableWriter;
      if Writer = nil then
      begin
        AError := SNoWriter;
        Exit;
      end;
      Removed  := 0;
      Inserted := 0;
      try
        for i := 0 to High(Plan) do
        begin
          Writer.CopyTo(Plan[i].StartPos);
          Writer.DeleteTo(Plan[i].EndPos);
          NewUtf8 := UTF8Encode(Plan[i].NewText);
          if NewUtf8 <> '' then
            Writer.Insert(PAnsiChar(NewUtf8));
          Inc(Removed, Plan[i].EndPos - Plan[i].StartPos);
          Inc(Inserted, Length(NewUtf8));
        end;
      finally
        Writer := nil;
      end;
      RdxLog('  geschrieben: %d Ersetzung(en), %d Bytes entfernt, %d eingefuegt',
        [Length(Plan), Removed, Inserted]);
      if TryGetView(Src, View, EdPos) then
        View.Paint;
      Result := True;
    except
      on E: Exception do
        AError := E.ClassName + ': ' + E.Message;
    end;
  finally
    if AError <> '' then
    begin
      RdxLog('  FEHLER: ' + AError);
      AError := WithLogHint(AError);
    end;
  end;
end;

class function TRdxEditor.ProjectHasUnit(const AShortName,
  ANearFile: string): Boolean;
var
  ModSvc : IOTAModuleServices;
  Proj   : IOTAProject;
  Info   : IOTAModuleInfo;
  i      : Integer;
begin
  Result := False;
  if AShortName = '' then Exit;
  // 1) Datei gleichen Namens neben der bearbeiteten Datei
  if (ANearFile <> '')
     and FileExists(ExtractFilePath(ANearFile) + AShortName + '.pas') then
    Exit(True);
  // 2) Units des aktiven Projekts
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  Proj := ModSvc.GetActiveProject;
  if Proj = nil then Exit;
  for i := 0 to Proj.GetModuleCount - 1 do
  begin
    Info := Proj.GetModule(i);
    if Info = nil then Continue;
    if SameText(ChangeFileExt(ExtractFileName(Info.FileName), ''), AShortName) then
      Exit(True);
  end;
end;

end.
