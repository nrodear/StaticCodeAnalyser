unit uRdxEditor;

// reDelphix - der einzige ToolsAPI-Teil des Moduls: Bereich im Editor
// markieren, Bereich ersetzen, Editor-Puffer lesen, Projekt-Units nachsehen
// (Konzept_SourceRefactor_Quellstellen Abschnitt 15.4b: H2/H3 wohnen im
// Modul).
//
// NUR VOM ZEILENANFANG AUS - KEINE SPALTENARITHMETIK IM EDITOR
//
// IOTAEditPosition rechnet in ANZEIGE-Spalten (Tabulatoren expandiert),
// die Bereiche aus TSourcePlaces zaehlen ZEICHEN, und ob Read(N) den
// Cursor bewegt, ist nicht verbuergt - die erste Fassung (AH16) nahm es
// an und verglich dann ab Spalte 1 ("Quelltext im Editor weicht vom Scan
// ab", 2026-10-06, bei identischem Text auf Platte und im Editor).
// Deshalb arbeitet ReplaceSpan jetzt ausschliesslich mit Operationen,
// die am ZEILENANFANG beginnen:
//   * Zeilen eines mehrzeiligen Bereichs werden von unten her mit
//     BackspaceDelete am Zeilenanfang zusammengezogen (loescht den
//     Umbruch, egal ob CRLF oder LF),
//   * die so entstandene EINE Zeile wird komplett geloescht (Delete
//     zaehlt Zeichen) und als Praefix + neuer Text + Suffix neu
//     eingefuegt - dasselbe Muster wie der Zeilen-Quick-Fix des Plugins.
// Fuer die Markierung (SelectSpan) rechnet die IDE selbst die Zeichen-
// in Anzeigespalten um (IOTAEditView.ConvertPos).
//
// NICHTS WIRD BLIND GESCHRIEBEN
//
// Vor jeder Aenderung wird der Bereich im EDITOR-PUFFER (IOTAEditReader)
// mit dem Text verglichen, den der Scan beschrieben hat; nach dem
// Zusammenziehen wird die Zeile ein zweites Mal gegengelesen. Weicht
// etwas ab, nennt die Meldung die erste Stelle aus beiden Fassungen.
// Jede Aenderung laeuft ueber die Cursor-API der IDE und ist mit Strg+Z
// ruecknehmbar.

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
    // AExpected enthaelt (Zeilenumbrueche als #10 verglichen). ANewText
    // ersetzt den Bereich auf EINER Zeile; ein mehrzeiliger Bereich wird
    // dabei zusammengezogen.
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
  System.SysUtils, System.Classes,
  ToolsAPI,
  uRefactorInfoBuilder;   // SpanText: derselbe Bereichstext wie beim Scan

const
  SNoEditor  = 'Datei ist nicht im Editor geoeffnet';
  SNoView    = 'Editor-Ansicht nicht verfuegbar';
  SNoBuffer  = 'Editor-Puffer nicht lesbar';
  SDiffers   = 'Quelltext im Editor weicht vom Scan ab - nicht geschrieben';
  SJoinFail  = 'Zeilen liessen sich nicht zusammenziehen - Strg+Z';
  SJoinDiff  = 'Zeile nach dem Zusammenziehen anders als erwartet - Strg+Z';

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

function Visible(const S: string): string;
// Zeilenumbrueche und Tabulatoren sichtbar machen - fuer die Meldung.
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

function BufferLines(const AFile: string; ALines: TStringList): Boolean;
// Der Puffer als Zeilen - TStringList.Text trennt CRLF, LF und CR.
var
  Text : string;
begin
  Result := TRdxEditor.TryReadBuffer(AFile, Text);
  if Result then
    ALines.Text := Text;
end;

function DisplayPosOf(const AView: IOTAEditView; ALines: TStringList;
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

class function TRdxEditor.SelectSpan(const AFile: string;
  const ASpan: TRefactorSpan; out AError: string): Boolean;
var
  Src    : IOTASourceEditor;
  View   : IOTAEditView;
  EdPos  : IOTAEditPosition;
  Block  : IOTAEditBlock;
  Lines  : TStringList;
  P      : TOTAEditPos;
begin
  Result := False;
  AError := '';
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
      if not BufferLines(AFile, Lines) then
      begin
        AError := SNoBuffer;
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
      if not EdPos.Move(P.Line, P.Col) then Exit;
      Block.BeginBlock;
      P := DisplayPosOf(View, Lines, ASpan.EndLine, ASpan.EndCol);
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
  end;
end;

class function TRdxEditor.ReplaceSpan(const AFile: string;
  const ASpan: TRefactorSpan; const AExpected, ANewText: string;
  out AError: string): Boolean;
var
  Src     : IOTASourceEditor;
  View    : IOTAEditView;
  EdPos   : IOTAEditPosition;
  Lines   : TStringList;
  Actual  : string;
  First   : string;
  Last    : string;
  Joined  : string;
  NewLine : string;
  Probe   : string;
  L       : Integer;
begin
  Result := False;
  AError := '';
  if not ASpan.IsValid or (AExpected = '') then
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
      // 1) Puffer lesen und den Bereich gegen den Scan-Text pruefen -
      //    derselbe Bereichstext wie beim Beschreiben (SpanText).
      if not BufferLines(AFile, Lines) then
      begin
        AError := SNoBuffer;
        Exit;
      end;
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
        Exit;
      end;

      // 2) Was aus den Zeilen des Bereichs wird: Praefix der ersten,
      //    neuer Text, Suffix der letzten - auf EINER Zeile.
      First   := Lines[ASpan.StartLine - 1];
      Last    := Lines[ASpan.EndLine - 1];
      NewLine := Copy(First, 1, ASpan.StartCol - 1) + ANewText
        + Copy(Last, ASpan.EndCol, MaxInt);
      Joined := First;
      for L := ASpan.StartLine + 1 to ASpan.EndLine do
        Joined := Joined + Lines[L - 1];

      if not TryGetView(Src, View, EdPos) then
      begin
        AError := SNoView;
        Exit;
      end;

      // 3) Fortsetzungszeilen von unten her anziehen: Backspace am
      //    Zeilenanfang loescht genau den Umbruch davor.
      for L := ASpan.EndLine downto ASpan.StartLine + 1 do
      begin
        if not (EdPos.GotoLine(L) and EdPos.MoveBOL
                and EdPos.BackspaceDelete(1)) then
        begin
          AError := SJoinFail;
          Exit;
        end;
      end;

      // 4) Gegenprobe: die zusammengezogene Zeile muss exakt die
      //    Verkettung der Bereichszeilen sein.
      if not (EdPos.GotoLine(ASpan.StartLine) and EdPos.MoveBOL) then
      begin
        AError := SJoinFail;
        Exit;
      end;
      Probe := EdPos.Read(Length(Joined));
      if Probe <> Joined then
      begin
        AError := SJoinDiff + DescribeMismatch(Joined, Probe);
        Exit;
      end;

      // 5) Die ganze Zeile ersetzen - Delete zaehlt Zeichen, der Umbruch
      //    am Ende bleibt stehen.
      if not (EdPos.GotoLine(ASpan.StartLine) and EdPos.MoveBOL) then
      begin
        AError := SJoinFail;
        Exit;
      end;
      if (Length(Joined) > 0) and not EdPos.Delete(Length(Joined)) then
      begin
        AError := 'Loeschen im Editor fehlgeschlagen - Strg+Z';
        Exit;
      end;
      EdPos.InsertText(NewLine);
      View.MoveViewToCursor;
      View.Paint;
      Result := True;
    except
      on E: Exception do
        AError := E.Message;
    end;
  finally
    Lines.Free;
  end;
end;

class function TRdxEditor.TryReadBuffer(const AFile: string;
  out AText: string): Boolean;
// IOTAEditReader liefert UTF-8-Bytes in Bloecken; der Reader wird vor
// dem Verlassen freigegeben - solange er lebt, darf niemand in den
// Puffer schreiben.
const
  BLOCK = 16384;
var
  Src    : IOTASourceEditor;
  Reader : IOTAEditReader;
  Buf    : TBytes;
  Chunk  : TBytes;
  Got    : Integer;
  Total  : Integer;
begin
  Result := False;
  AText  := '';
  if not TryGetSourceEditor(AFile, False, Src) then Exit;
  try
    Reader := Src.CreateReader;
    if Reader = nil then Exit;
    try
      SetLength(Buf, 0);
      Total := 0;
      repeat
        SetLength(Chunk, BLOCK);
        Got := Reader.GetText(Total, PAnsiChar(@Chunk[0]), BLOCK);
        if Got > 0 then
        begin
          SetLength(Buf, Total + Got);
          Move(Chunk[0], Buf[Total], Got);
          Inc(Total, Got);
        end;
      until Got < BLOCK;
    finally
      Reader := nil;
    end;
    AText  := TEncoding.UTF8.GetString(Buf);
    Result := AText <> '';
  except
    on E: Exception do
    begin
      AText  := '';
      Result := False;
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
