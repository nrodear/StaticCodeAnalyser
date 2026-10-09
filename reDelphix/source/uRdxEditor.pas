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
//
// MARKIEREN UEBER DIE CURSOR-API
//
// SelectSpan rechnet doch in Anzeigespalten (IOTAEditPosition.Move,
// ConvertPos); deren Felder sind SmallInt. Ein Bereich hinter Spalte
// 32767 bzw. hinter 32766 Bytes einer Zeile wird deshalb abgelehnt
// (uRdxBufferMath.SpanFitsEditor, Review Nit 8), ebenso einer hinter dem
// Pufferende; ein gescheitertes Move nennt seine Position (Minor 23).

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

    // Liest den aktuellen EDITOR-PUFFER der Datei (IOTAEditReader,
    // UTF-8 -> string); die Datei wird dafuer nicht geoeffnet. Ergebnis
    // nach uRdxBufferMath.ChooseTextSource: txBuffer mit AText, txDisk,
    // wenn die Datei nicht im Editor offen ist, txBlocked, wenn sie offen,
    // ihr Puffer aber leer oder nicht lesbar ist - dann gilt NICHT die
    // Platte (Review Nit 24). Der Anbieter beschreibt die Stellen auf
    // diesem Text: ungespeicherte Aenderungen sind sonst ein Widerspruch
    // zwischen Scan und Editor.
    class function ReadBuffer(const AFile: string;
      out AText: string): TRdxTextSource; static;

    // True nur bei txBuffer (ReadBuffer) - fuer SelectSpan.
    class function TryReadBuffer(const AFile: string;
      out AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  ToolsAPI,
  uCrashDiag,       // EStackExhausted
  uLocalization,
  uRdxLog;

const
  SNoEditor = 'Datei ist nicht im Editor geoeffnet';
  SNoView   = 'Editor-Ansicht nicht verfuegbar';
  SNoBuffer = 'Editor-Puffer nicht lesbar';
  SNoWriter = 'Editor-Puffer nicht beschreibbar';
  // Ueber _() (Editorhilfen E6); die vier oben folgen mit dem E6-Rest.
  S_PAST_END = 'Range %d:%d to %d:%d lies behind the end of the editor '
    + 'buffer (%d lines) - rescan the file';
  S_TOO_LONG = 'Line too long for the editor selection (the editor '
    + 'reaches at most column %d)';
  S_NO_MOVE  = 'Cannot move the editor cursor to line %d, column %d';

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
// Puffer schreiben. True, sobald ein Reader da war: ein LEERER Puffer ist
// gelesen, nicht unlesbar (Review Nit 24 - die Entscheidung trifft
// ChooseTextSource, ReplaceSpans meldet die Abweichung gegen den Scan).
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
  Result := True;
end;

// LineStartsOf, OffsetOf, NormalizeEol, BufferEol, Visible und
// DescribeMismatch liegen seit Stufe 0 in uRdxBufferMath (getestet).

function DisplayPosOf(const AView: IOTAEditView; ALines: TStrings;
  ALine, ACol: Integer): TOTAEditPos;
// Zeichen-Spalte -> Anzeige-Spalte ueber die IDE selbst. TOTACharPos
// zaehlt die UTF-8-Bytes der Zeile (so handhaben es GExperts & Co.);
// fuer reinen ASCII-Code ist das die Zeichenzahl. Vorbedingung, von
// SelectSpan mit SpanFitsEditor geprueft: ACol und der Byte-Praefix
// passen in die SmallInt-Felder von TOTAEditPos/TOTACharPos (Nit 8).
var
  CharPos : TOTACharPos;
begin
  Result.Line := ALine;
  Result.Col  := ACol;
  if (ALine < 1) or (ALine > ALines.Count) then Exit;
  CharPos.Line      := ALine;
  CharPos.CharIndex := Utf8PrefixLength(ALines[ALine - 1], ACol);
  AView.ConvertPos(False, Result, CharPos);
  Result.Line := ALine;
end;

{ TRdxEditor }

class function TRdxEditor.ReadBuffer(const AFile: string;
  out AText: string): TRdxTextSource;
var
  Src    : IOTASourceEditor;
  Bytes  : TBytes;
  ReadOk : Boolean;
begin
  AText := '';
  if not TryGetSourceEditor(AFile, False, Src) then
    Exit(ChooseTextSource(False, False, ''));
  ReadOk := False;
  try
    if ReadBufferBytes(Src, Bytes) then
    begin
      // Leerer Puffer: kein GetString auf einem leeren Array (@Bytes[0]).
      if Length(Bytes) > 0 then
        AText := TEncoding.UTF8.GetString(Bytes);
      ReadOk := True;
    end;
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    on E: Exception do
    begin
      // Offen, aber nicht lesbar: gesperrt, nicht die Platte (Nit 24).
      RdxLog('ReadBuffer %s: %s', [ExtractFileName(AFile), E.Message]);
      AText := '';
      Exit(ChooseTextSource(True, False, ''));
    end;
  end;
  Result := ChooseTextSource(True, ReadOk, AText);
  if Result = txBlocked then
    RdxLog('ReadBuffer %s: im Editor offen, Puffer leer oder nicht lesbar',
      [ExtractFileName(AFile)]);
end;

class function TRdxEditor.TryReadBuffer(const AFile: string;
  out AText: string): Boolean;
begin
  Result := ReadBuffer(AFile, AText) = txBuffer;
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
      // Der Puffer kann seit dem Menueaufbau kuerzer geworden sein
      // (Minor 23), und die Cursor-API rechnet in SmallInt-Spalten (Nit 8).
      if ASpan.EndLine > Lines.Count then
      begin
        AError := Format(_(S_PAST_END), [ASpan.StartLine, ASpan.StartCol,
          ASpan.EndLine, ASpan.EndCol, Lines.Count]);
        Exit;
      end;
      if not SpanFitsEditor(Lines, ASpan) then
      begin
        AError := Format(_(S_TOO_LONG), [EDITOR_MAX_COLUMN]);
        Exit;
      end;
      Block := View.Block;
      if Block = nil then
      begin
        AError := SNoView;
        Exit;
      end;
      Block.Reset;
      P := DisplayPosOf(View, Lines, ASpan.StartLine, ASpan.StartCol);
      RdxLog('  Anfang Zeichen %d -> Anzeige %d', [ASpan.StartCol, P.Col]);
      if not EdPos.Move(P.Line, P.Col) then
      begin
        AError := Format(_(S_NO_MOVE), [P.Line, P.Col]);
        Exit;
      end;
      Block.BeginBlock;
      P := DisplayPosOf(View, Lines, ASpan.EndLine, ASpan.EndCol);
      RdxLog('  Ende Zeichen %d -> Anzeige %d', [ASpan.EndCol, P.Col]);
      if not EdPos.Move(P.Line, P.Col) then
      begin
        Block.Reset;   // keinen halb begonnenen Block stehen lassen
        AError := Format(_(S_NO_MOVE), [P.Line, P.Col]);
        Exit;
      end;
      Block.EndBlock;
      View.MoveViewToCursor;
      View.Paint;
      Result := True;
    except
      on EStackExhausted do raise;
      on EAbort do raise;
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
      on EStackExhausted do raise;
      on EAbort do raise;
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
