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
// Vor dem Schreiben wird der Bereich zweimal gegen den Scan-Text geprueft:
// als Zeilen (SpanText, wie der Dienst ihn gebildet hat) und als Bytes
// (der Ausschnitt, der tatsaechlich geloescht wird). Weicht etwas ab,
// nennt die Meldung die erste Stelle aus beiden Fassungen. Jeder Schritt
// steht im Protokoll (uRdxLog, %TEMP%\reDelphix.log). Die Aenderung ist
// mit Strg+Z ruecknehmbar (CreateUndoableWriter).

interface

uses
  uRefactorInfo;

type
  TRdxEditor = class
  public
    // Oeffnet die Datei (falls noetig), holt den Tab nach vorn und
    // markiert den Bereich.
    class function SelectSpan(const AFile: string;
      const ASpan: TRefactorSpan; out AError: string): Boolean; static;

    // Ersetzt den Bereich durch ANewText - nur wenn der Puffer dort
    // AExpected enthaelt (Zeilenumbrueche als #10 verglichen). Praefix
    // vor dem Bereich und Suffix dahinter bleiben stehen; ein
    // mehrzeiliger Bereich wird dabei zu dem, was ANewText vorgibt.
    class function ReplaceSpan(const AFile: string;
      const ASpan: TRefactorSpan; const AExpected, ANewText: string;
      out AError: string): Boolean; static;

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
  System.SysUtils, System.Classes, System.Generics.Collections,
  ToolsAPI,
  uRefactorInfoBuilder,   // SpanText: derselbe Bereichstext wie beim Scan
  uRdxLog;

const
  SNoEditor = 'Datei ist nicht im Editor geoeffnet';
  SNoView   = 'Editor-Ansicht nicht verfuegbar';
  SNoBuffer = 'Editor-Puffer nicht lesbar';
  SNoWriter = 'Editor-Puffer nicht beschreibbar';
  SDiffers  = 'Quelltext im Editor weicht vom Scan ab - nicht geschrieben';

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

procedure LineStartsOf(const ABytes: TBytes; AStarts: TList<Integer>);
// Byte-Offset (0-basiert) jedes Zeilenanfangs; Terminatoren CRLF, LF und
// CR - dieselbe Trennung wie TStringList.Text.
var
  i, n : Integer;
begin
  AStarts.Clear;
  AStarts.Add(0);
  i := 0;
  n := Length(ABytes);
  while i < n do
  begin
    if ABytes[i] = 13 then
    begin
      if (i + 1 < n) and (ABytes[i + 1] = 10) then
        Inc(i, 2)
      else
        Inc(i);
      AStarts.Add(i);
    end
    else if ABytes[i] = 10 then
    begin
      Inc(i);
      AStarts.Add(i);
    end
    else
      Inc(i);
  end;
end;

function OffsetOf(AStarts: TList<Integer>; ALines: TStrings;
  ALine, ACol: Integer; out AOffset: Integer): Boolean;
// Byte-Offset der Zeichen-Spalte ACol (1-basiert) in Zeile ALine: Anfang
// der Zeile plus UTF-8-Laenge der Zeichen davor. ACol hinter dem
// Zeilenende landet am Zeilenende.
begin
  AOffset := 0;
  Result := (ALine >= 1) and (ALine <= ALines.Count) and (ALine <= AStarts.Count);
  if not Result then Exit;
  AOffset := AStarts[ALine - 1]
    + Length(UTF8Encode(Copy(ALines[ALine - 1], 1, ACol - 1)));
end;

function NormalizeEol(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

function BufferEol(const ABytes: TBytes): string;
// Das Zeilenende, das der Puffer benutzt: CRLF, wenn es darin vorkommt,
// sonst LF (ein Puffer ohne Umbruch bekommt CRLF).
var
  i : Integer;
begin
  Result := #13#10;
  for i := 0 to High(ABytes) - 1 do
    if ABytes[i] = 13 then
      Exit(#13#10)
    else if ABytes[i] = 10 then
      Exit(#10);
end;

function Visible(const S: string): string;
// Zeilenumbrueche und Tabulatoren sichtbar machen - fuer Meldung und
// Protokoll.
begin
  Result := StringReplace(S, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
end;

function DescribeMismatch(const AExpected, AActual: string): string;
// Erste abweichende Stelle samt Umfeld aus beiden Texten - damit der
// Benutzer sieht, WAS im Editor anders ist als im Scan (Puffer seit dem
// Oeffnen des Menues geaendert, verschobene Zeile, veralteter Fund).
const
  CTX = 24;
var
  i, n : Integer;
  From : Integer;
begin
  n := Length(AExpected);
  if Length(AActual) < n then n := Length(AActual);
  i := 1;
  while (i <= n) and (AExpected[i] = AActual[i]) do Inc(i);
  From := i - 8;
  if From < 1 then From := 1;
  Result := Format(' (ab Zeichen %d: Scan "%s", Editor "%s")', [i,
    Visible(Copy(AExpected, From, CTX)), Visible(Copy(AActual, From, CTX))]);
end;

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

class function TRdxEditor.ReplaceSpan(const AFile: string;
  const ASpan: TRefactorSpan; const AExpected, ANewText: string;
  out AError: string): Boolean;
var
  Src      : IOTASourceEditor;
  View     : IOTAEditView;
  EdPos    : IOTAEditPosition;
  Bytes    : TBytes;
  Lines    : TStringList;
  Starts   : TList<Integer>;
  Actual   : string;
  StartPos : Integer;
  EndPos   : Integer;
  Slice    : string;
  Writer   : IOTAEditWriter;
  NewUtf8  : UTF8String;
  After    : string;
begin
  Result := False;
  AError := '';
  RdxLog('ReplaceSpan %s %d:%d-%d:%d, neu "%s"', [ExtractFileName(AFile),
    ASpan.StartLine, ASpan.StartCol, ASpan.EndLine, ASpan.EndCol,
    Visible(ANewText)]);
  if not ASpan.IsValid or (AExpected = '') then
  begin
    AError := 'kein gueltiger Bereich';
    RdxLog('  FEHLER: ' + AError);
    Exit;
  end;
  if not TryGetSourceEditor(AFile, True, Src) then
  begin
    AError := SNoEditor;
    RdxLog('  FEHLER: ' + AError);
    Exit;
  end;
  Lines  := TStringList.Create;
  Starts := TList<Integer>.Create;
  try
    try
      // 1) Puffer als Bytes und als Zeilen
      if not ReadBufferBytes(Src, Bytes) then
      begin
        AError := SNoBuffer;
        Exit;
      end;
      Lines.Text := TEncoding.UTF8.GetString(Bytes);
      LineStartsOf(Bytes, Starts);
      RdxLog('  Puffer: %d Bytes, %d Zeilen, %d Zeilenanfaenge',
        [Length(Bytes), Lines.Count, Starts.Count]);

      // 2) Bereich als Zeilen gegen den Scan-Text
      if ASpan.EndLine > Lines.Count then
      begin
        AError := SDiffers + Format(' (Zeile %d, der Puffer hat %d Zeilen)',
          [ASpan.EndLine, Lines.Count]);
        Exit;
      end;
      Actual := TRefactorInfoBuilder.SpanText(Lines, ASpan);
      if Actual <> AExpected then
      begin
        AError := SDiffers + DescribeMismatch(AExpected, Actual);
        RdxLog('  Scan  : "%s"', [Visible(AExpected)]);
        RdxLog('  Editor: "%s"', [Visible(Actual)]);
        Exit;
      end;

      // 3) Byte-Offsets aus demselben Puffer; der Ausschnitt muss den
      //    Scan-Text ergeben - sonst stimmt die Offset-Rechnung nicht.
      if not OffsetOf(Starts, Lines, ASpan.StartLine, ASpan.StartCol, StartPos)
         or not OffsetOf(Starts, Lines, ASpan.EndLine, ASpan.EndCol, EndPos)
         or (EndPos <= StartPos) or (EndPos > Length(Bytes)) then
      begin
        AError := Format('Position im Puffer nicht berechenbar (%d..%d von %d)',
          [StartPos, EndPos, Length(Bytes)]);
        Exit;
      end;
      Slice := NormalizeEol(TEncoding.UTF8.GetString(Bytes, StartPos,
        EndPos - StartPos));
      RdxLog('  Bytes %d..%d (%d): "%s"', [StartPos, EndPos, EndPos - StartPos,
        Visible(Slice)]);
      if Slice <> AExpected then
      begin
        AError := 'Byte-Bereich weicht vom Scan ab - nicht geschrieben'
          + DescribeMismatch(AExpected, Slice);
        Exit;
      end;

      // 4) Schreiben: Praefix kopieren, Bereich verwerfen, neuen Text
      //    einfuegen; der Rest wird beim Freigeben des Writers kopiert.
      //    Zeilenumbrueche im neuen Text sind #10 (Vertrag von TRdxEdit)
      //    und bekommen das Zeilenende des Puffers.
      Writer := Src.CreateUndoableWriter;
      if Writer = nil then
      begin
        AError := SNoWriter;
        Exit;
      end;
      try
        Writer.CopyTo(StartPos);
        Writer.DeleteTo(EndPos);
        NewUtf8 := UTF8Encode(StringReplace(ANewText, #10, BufferEol(Bytes),
          [rfReplaceAll]));
        Writer.Insert(PAnsiChar(NewUtf8));
      finally
        Writer := nil;
      end;
      RdxLog('  geschrieben: %d Bytes entfernt, %d Bytes eingefuegt',
        [EndPos - StartPos, Length(NewUtf8)]);

      // 5) Nachkontrolle fuers Protokoll: die Zeile danach.
      if TryReadBuffer(AFile, After) then
      begin
        Lines.Text := After;
        if ASpan.StartLine <= Lines.Count then
          RdxLog('  Zeile %d jetzt: "%s"', [ASpan.StartLine,
            Visible(Lines[ASpan.StartLine - 1])]);
      end;
      if TryGetView(Src, View, EdPos) then
        View.Paint;
      Result := True;
    except
      on E: Exception do
        AError := E.ClassName + ': ' + E.Message;
    end;
  finally
    Starts.Free;
    Lines.Free;
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
