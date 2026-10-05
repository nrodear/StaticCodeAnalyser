unit uRdxEditor;

// reDelphix - der einzige ToolsAPI-Teil des Moduls: Bereich im Editor
// markieren, Bereich ersetzen, Projekt-Units nachsehen
// (Konzept_SourceRefactor_Quellstellen Abschnitt 15.4b: H2/H3 wohnen im
// Modul).
//
// ZEICHENGENAU STATT ANZEIGESPALTEN
//
// IOTAEditPosition.Column und Move(Row, Col) rechnen in ANZEIGE-Spalten
// (Tabulatoren expandiert); die Bereiche aus TSourcePlaces zaehlen
// ZEICHEN. Der Weg dazwischen ist Read(N): es liest N Zeichen ab dem
// Cursor und bewegt ihn dabei - so landet der Cursor ohne Umrechnung auf
// einer Zeichen-Spalte. Dasselbe Verfahren benutzt das SCA-Plugin fuer
// seinen Zeilen-Quick-Fix (uIDEEditorIntegration, Vollausbau 2026-08-26).
//
// NICHTS WIRD BLIND GESCHRIEBEN
//
// ReplaceSpan liest den Bereich zuerst aus dem EDITOR-PUFFER und
// vergleicht ihn (Zeilenenden normalisiert) mit dem Text, den der Scan
// beschrieben hat. Weicht der Puffer ab - ungespeicherte Aenderung,
// verschobene Zeilen, veralteter Fund -, wird nicht geschrieben. Das ist
// strenger als der Hash-Vergleich gegen die Datei auf der Platte, denn
// geschrieben wird in den Puffer, nicht in die Datei.
//
// Jede Aenderung laeuft ueber die Cursor-API der IDE und ist damit mit
// Strg+Z ruecknehmbar.

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
    // AExpected enthaelt (Zeilenumbrueche als #10 verglichen).
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
  System.SysUtils,
  ToolsAPI;

const
  SNoEditor = 'Datei ist nicht im Editor geoeffnet';
  SNoView   = 'Editor-Ansicht nicht verfuegbar';
  SDiffers  = 'Quelltext im Editor weicht vom Scan ab - nicht geschrieben';

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

function MoveToChar(const APos: IOTAEditPosition; ALine, ACol: Integer): Boolean;
// Cursor auf Zeile/ZEICHEN-Spalte: an den Zeilenanfang, dann ACol-1
// Zeichen lesen - Read bewegt den Cursor um Zeichen, nicht um Spalten.
begin
  Result := APos.GotoLine(ALine) and APos.MoveBOL;
  if Result and (ACol > 1) then
    APos.Read(ACol - 1);
end;

function NormalizeEol(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

function CountChar(const S: string; C: Char): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if S[i] = C then Inc(Result);
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
// Benutzer sieht, WAS im Editor anders ist als im Scan (ungespeicherte
// Aenderung, verschobene Zeile, veralteter Fund).
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

{ TRdxEditor }

class function TRdxEditor.SelectSpan(const AFile: string;
  const ASpan: TRefactorSpan; out AError: string): Boolean;
var
  Src   : IOTASourceEditor;
  View  : IOTAEditView;
  EdPos : IOTAEditPosition;
  Block : IOTAEditBlock;
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
  try
    Src.Show;
    if Src.EditViewCount = 0 then
    begin
      AError := SNoView;
      Exit;
    end;
    View := Src.EditViews[0];
    if View = nil then
    begin
      AError := SNoView;
      Exit;
    end;
    EdPos := View.Position;
    Block := View.Block;
    if (EdPos = nil) or (Block = nil) then
    begin
      AError := SNoView;
      Exit;
    end;
    Block.Reset;
    if not MoveToChar(EdPos, ASpan.StartLine, ASpan.StartCol) then Exit;
    Block.BeginBlock;
    if not MoveToChar(EdPos, ASpan.EndLine, ASpan.EndCol) then Exit;
    Block.EndBlock;
    View.MoveViewToCursor;
    View.Paint;
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

class function TRdxEditor.ReplaceSpan(const AFile: string;
  const ASpan: TRefactorSpan; const AExpected, ANewText: string;
  out AError: string): Boolean;
var
  Src    : IOTASourceEditor;
  View   : IOTAEditView;
  EdPos  : IOTAEditPosition;
  Breaks : Integer;
  Raw    : string;
  Norm   : string;
  EolLen : Integer;
  Len    : Integer;
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
  try
    if Src.EditViewCount = 0 then
    begin
      AError := SNoView;
      Exit;
    end;
    View := Src.EditViews[0];
    if (View = nil) or (View.Buffer = nil) then
    begin
      AError := SNoView;
      Exit;
    end;
    EdPos := View.Buffer.EditPosition;
    if EdPos = nil then
    begin
      AError := SNoView;
      Exit;
    end;

    // 1) Den Bereich aus dem Puffer lesen und mit dem Scan vergleichen.
    //    Gelesen wird das CRLF-Maximum; der Vergleich laeuft normalisiert.
    Breaks := CountChar(AExpected, #10);
    if not MoveToChar(EdPos, ASpan.StartLine, ASpan.StartCol) then
    begin
      AError := SDiffers;
      Exit;
    end;
    Raw  := EdPos.Read(Length(AExpected) + Breaks);
    Norm := NormalizeEol(Raw);
    if Copy(Norm, 1, Length(AExpected)) <> AExpected then
    begin
      AError := SDiffers + DescribeMismatch(AExpected, Norm);
      Exit;
    end;
    EolLen := 1;
    if Pos(#13#10, Raw) > 0 then EolLen := 2;
    Len := Length(AExpected) + Breaks * (EolLen - 1);

    // 2) Zurueck an den Anfang (Read hat den Cursor bewegt), loeschen,
    //    einfuegen - beides ueber den Undo-Stapel der IDE.
    if not MoveToChar(EdPos, ASpan.StartLine, ASpan.StartCol) then
    begin
      AError := SDiffers;
      Exit;
    end;
    if not EdPos.Delete(Len) then
    begin
      AError := 'Loeschen im Editor fehlgeschlagen';
      Exit;
    end;
    EdPos.InsertText(ANewText);
    View.MoveViewToCursor;
    View.Paint;
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
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
