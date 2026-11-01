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
// Text beim Menueaufbau geprueft (den der Anbieter beschrieben hat - nicht
// den Scan): als Zeilen (SpanText, wie der Dienst ihn gebildet hat) und
// als Bytes (der Ausschnitt, der tatsaechlich geloescht wird) -
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
  uRefactorInfo, uRdxBufferMath,
  uRdxScopeTable;   // TRdxProjectUnits (Index der Projekt-Units)

// Der Text zu EDITOR_MAX_COLUMN steht EINMAL fuer Editor und Kern in
// uRdxText (MsgTooLongForEditor; Review nach Bereichen 2026-10-10, Nit 34) -
// bis zur Probe-Charge E3 hier als S_TOO_LONG.

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

    // Die Units, die das Projekt selbst fuehren kann, als Index fuer die
    // uses-Eintraege EINES Aufrufs (der Anbieter baut ihn je Fund auf einer
    // uses-Zeile einmal, beim ersten Eintrag, der fragt - Review R1-02; bis
    // dahin lief ProjectHasUnit je Eintrag ueber die ganze Projektgruppe):
    // das Verzeichnis von ANearFile, die Module ALLER Projekte der Gruppe
    // (nicht nur des aktiven) und die Verzeichnisse ihres Unit-Suchpfads
    // in der aktiven Konfiguration und Plattform, jede Ebene einzeln
    // (missed 3: 360 von 3.305 .dproj des Korpus setzen ihn auf Plattform-
    // Ebene; s. AddSearchPaths). Hat das Projekt eine Unit des
    // Kurznamens (TRdxProjectUnits.Knows), darf ein uses-Eintrag NICHT auf
    // eine RTL-Unit expandiert werden (Review nach Bereichen 2026-10-10,
    // Minor 18). Netzpfade (UNC, Netzlaufwerk) liest der Index nicht -
    // dann bleibt jede Antwort offen, der Eintrag gesperrt mit Grund.
    // GRENZE (Review R1-07, offen): Eintraege mit Makros ($(BDS),
    // $(DUnitX) ...) und der Bibliotheks-/Browsing-Pfad der IDE bleiben
    // aussen vor. Bringt eine Drittbibliothek dort eine Unit mit dem
    // Kurznamen einer RTL-Unit mit (JEDI-DirectX 'Direct3D9', 'pngimage',
    // die alte Borland-'ZLib'), wird der Eintrag trotzdem angeboten - der
    // Compiler faende vorher die Bibliothek. Gemessen ist das nicht (IDE-
    // Test mit einer Bibliothek nur im Library Path fehlt), s. README
    // "Grenzen". Der Aufrufer gibt den Index frei.
    class function ProjectUnits(const ANearFile: string): TRdxProjectUnits; static;

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
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization (E29)
  uRdxLog;

const
  // Die Meldungen an den Benutzer, alle ueber _() (Editorhilfen E6,
  // Entscheid E29): englische msgids, de/fr in i18n/*.po. Das Protokoll
  // (RdxLog) bleibt deutsch.
  SNoEditor   = 'Cannot open or find the file in the editor';
  SNoView     = 'Editor view not available';
  SNoBuffer   = 'Editor buffer not readable';
  SNoWriter   = 'Editor buffer not writable';
  SReadOnly   = 'Editor buffer is read-only - nothing written';
  S_PAST_END = 'Range %d:%d to %d:%d lies behind the end of the editor '
    + 'buffer (%d lines) - rescan the file';
  S_NO_MOVE  = 'Cannot move the editor cursor to line %d, column %d';
  // Die Meldung samt Pfad des Protokolls (%TEMP%\reDelphix.log).
  S_LOG_HINT = '%s [log: %s]';

function WithLogHint(const AMsg: string): string;
begin
  Result := _(S_LOG_HINT, [AMsg, RdxLogPath]);
end;

// Der IOTASourceEditor DIESER Datei im Modul AModule. Nicht einfach der
// erste: bei einem Form-Modul kann dort der DFM-Editor stehen (als Text
// angezeigt ist er auch ein IOTASourceEditor) - ein Marker landete sonst
// im Formular. Erst der volle Pfad, dann derselbe Dateiname in anderer
// Schreibweise; sonst nil (Review nach Bereichen 2026-10-10, Nit 35). Bis
// Review R1-05 Teil von TryGetSourceEditor (SCA176 18).
function SourceEditorIn(const AModule: IOTAModule;
  const AFile: string): IOTASourceEditor;
var
  Cand : IOTASourceEditor;
  i    : Integer;
begin
  Result := nil;
  for i := 0 to AModule.ModuleFileCount - 1 do
    if Supports(AModule.ModuleFileEditors[i], IOTASourceEditor, Cand)
       and SameFileName(Cand.FileName, AFile) then
      Exit(Cand);
  for i := 0 to AModule.ModuleFileCount - 1 do
    if Supports(AModule.ModuleFileEditors[i], IOTASourceEditor, Cand)
       and SameText(ExtractFileName(Cand.FileName), ExtractFileName(AFile)) then
    begin
      RdxLog('Editor fuer %s ueber den Dateinamen gefunden (%s)',
        [ExtractFileName(AFile), Cand.FileName]);
      Exit(Cand);
    end;
end;

// Das Modul der Datei, wenn sie in der IDE offen ist; sonst nil.
function FindModuleOf(const AFile: string): IOTAModule;
var
  ModSvc : IOTAModuleServices;
begin
  Result := nil;
  if (AFile <> '') and Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then
    Result := ModSvc.FindModule(AFile);
end;

// Der Quelltext-Editor der Datei, nur wenn sie schon offen ist (ReadBuffer:
// eine geschlossene Datei gilt von der Platte).
function TryFindSourceEditor(const AFile: string;
  out ASrc: IOTASourceEditor): Boolean;
var
  Module : IOTAModule;
begin
  ASrc := nil;
  Module := FindModuleOf(AFile);
  if Module <> nil then
    ASrc := SourceEditorIn(Module, AFile);
  Result := ASrc <> nil;
end;

// Wie TryFindSourceEditor; ist die Datei nicht offen, wird sie vorher
// geoeffnet (Markieren und Ersetzen). Bis Review R1-05 ein Boolean-Schalter
// von TryGetSourceEditor (SCA146).
function TryOpenSourceEditor(const AFile: string;
  out ASrc: IOTASourceEditor): Boolean;
var
  ActSvc : IOTAActionServices;
begin
  if (AFile <> '') and (FindModuleOf(AFile) = nil)
     and Supports(BorlandIDEServices, IOTAActionServices, ActSvc) then
    ActSvc.OpenFile(AFile);
  Result := TryFindSourceEditor(AFile, ASrc);
end;

function TryGetView(const ASrc: IOTASourceEditor; out AView: IOTAEditView;
  out APos: IOTAEditPosition): Boolean;
// EINE Ansicht des Editors samt IHRER Cursor-API: die oberste des Puffers
// (nach Src.Show die gezeigte), sonst die erste. Block, ConvertPos und
// Cursor kommen so aus derselben Ansicht - bis Review R1-06 kam der Cursor
// aus Buffer.EditPosition (der obersten Ansicht), Block und ConvertPos aus
// EditViews[0]; mit zwei Editorfenstern auf derselben Unit konnten das
// verschiedene sein (das Labor nimmt View.Position aus demselben Grund,
// uVnpIntroduce). Mit EINEM Fenster ist es dieselbe Ansicht wie vorher.
var
  Buffer : IOTAEditBuffer;
begin
  Result := False;
  AView  := nil;
  APos   := nil;
  if (ASrc = nil) or (ASrc.EditViewCount = 0) then Exit;
  if Supports(ASrc, IOTAEditBuffer, Buffer) then
    AView := Buffer.TopView;
  if AView = nil then
    AView := ASrc.EditViews[0];
  if AView = nil then Exit;
  APos := AView.Position;
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

// LineStartsOf, OffsetOf, NormalizeEol, BufferEol und Visible liegen seit
// Stufe 0 in uRdxBufferMath (getestet); das Detail einer Abweichung
// (bis Charge G7 DescribeMismatch) bildet dort PlanByteEdits selbst.

function DisplayPosOf(const AView: IOTAEditView; ALines: TStrings;
  ALine, ACol: Integer): TOTAEditPos;
// Zeichen-Spalte -> Anzeige-Spalte ueber die IDE selbst. ConvertPos liest
// TOTACharPos.CharIndex in ZEICHEN der Zeile (0-basiert, Tab = 1) - gemessen
// 2026-10-11 mit VarNameProject (Sonde M10: hinter 'Gruesse EUR' mit
// Umlauten und Euro-Zeichen CharIndex 20 = 20 Zeichen, nicht 24 Bytes;
// die Rueckrechnung ergab dieselbe Anzeigespalte). Bis dahin stand hier
// der UTF-8-Byte-Praefix (wie GExperts) - auf Zeilen mit Nicht-ASCII vor
// ACol markierte SelectSpan dadurch zu weit rechts. Das Ersetzen selbst
// (Pufferbytes ueber Reader/Writer) war davon nicht betroffen.
// Vorbedingung, von SelectSpan mit SpanFitsEditor geprueft: ACol passt in
// die SmallInt-Felder von TOTAEditPos/TOTACharPos (Nit 8; die Pruefung
// ueber den Byte-Praefix ist strenger als noetig, also sicher).
var
  CharPos : TOTACharPos;
begin
  Result.Line := ALine;
  Result.Col  := ACol;
  if (ALine < 1) or (ALine > ALines.Count) then Exit;
  CharPos.Line      := ALine;
  CharPos.CharIndex := ACol - 1;
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
  if not TryFindSourceEditor(AFile, Src) then
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
    // noinspection ExceptionTooGeneral
    // Grenze des Menueaufbaus (Review R1, missed 5): jeder andere Fehler
    // des Readers - auch einer der UTF-8-Dekodierung - kostet nur die
    // Hilfen dieser Datei. Er steht im Protokoll, und die Datei gilt als
    // offen, aber nicht lesbar: gesperrt, nicht die Platte (Nit 24).
    on E: Exception do
    begin
      RdxLog('ReadBuffer %s: %s: %s', [ExtractFileName(AFile), E.ClassName,
        E.Message]);
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
  Lines := TStringList.Create;
  try
    try
      // Auch diese Ausstiege laufen durch das finally (Log + Hinweis).
      if not ASpan.IsValid then
      begin
        AError := MsgNoValidRange;
        Exit;
      end;
      if not TryOpenSourceEditor(AFile, Src) then
      begin
        AError := _(SNoEditor);
        Exit;
      end;
      Src.Show;
      if not TryGetView(Src, View, EdPos) then
      begin
        AError := _(SNoView);
        Exit;
      end;
      if not TryReadBuffer(AFile, Text) then
      begin
        AError := _(SNoBuffer);
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
        AError := MsgTooLongForEditor(EDITOR_MAX_COLUMN);
        Exit;
      end;
      Block := View.Block;
      if Block = nil then
      begin
        AError := _(SNoView);
        Exit;
      end;
      Block.Reset;
      // Eine vom Benutzer hinterlassene Spaltenblock-Art (Alt+Umschalt)
      // machte aus einer mehrzeiligen Anweisung ein Rechteck (Nit 38).
      Block.Style := btNonInclusive;
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
      // noinspection ExceptionTooGeneral
      // Aktionsgrenze: jeder andere Fehler der IDE geht als AError an den
      // Aufrufer, der ihn als Meldung zeigt - dasselbe Format wie
      // ReplaceSpans (Nit 39).
      on E: Exception do
        AError := E.ClassName + ': ' + E.Message;
    end;
  finally
    Lines.Free;
    if AError <> '' then
    begin
      RdxLog('  SelectSpan FEHLER: ' + AError);
      AError := WithLogHint(AError);
    end;
  end;
end;

class function TRdxEditor.ReplaceSpans(const AFile: string;
  const AEdits: TArray<TRdxEdit>; out AError: string): Boolean;
var
  Src      : IOTASourceEditor;
  Buffer   : IOTAEditBuffer;
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
  try
    try
      // Auch dieser Ausstieg laeuft durch das finally (Log + Hinweis, Nit 39).
      if not TryOpenSourceEditor(AFile, Src) then
      begin
        AError := _(SNoEditor);
        Exit;
      end;
      // Schreibgeschuetzt (Bibliotheksquelle, gesperrte Datei): nichts
      // schreiben, statt es dem Verhalten der IDE zu ueberlassen (Nit 40).
      if Supports(Src, IOTAEditBuffer, Buffer) and Buffer.IsReadOnly then
      begin
        AError := _(SReadOnly);
        Exit;
      end;
      // 1) Puffer als Bytes; ALLE Bereiche pruefen, bevor einer
      //    geschrieben wird.
      if not ReadBufferBytes(Src, Bytes) then
      begin
        AError := _(SNoBuffer);
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
        AError := _(SNoWriter);
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
      // noinspection ExceptionTooGeneral
      // Aktionsgrenze: jeder andere Fehler der IDE geht als AError an den
      // Aufrufer, der ihn als Meldung zeigt (Nit 39).
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

const
  UNIT_SEARCH_PATH = 'DCC_UnitSearchPath';
  // Obergrenze fuer die Kette der Eltern-Konfigurationen (Debug -> Base
  // sind zwei): eine Kette, die nie bei nil endet, haengte sonst den
  // Hauptthread.
  MAX_CFG_DEPTH = 16;

// Die Konfiguration der Plattform APlatform unter ACfg (Cfg_1 -> Cfg_1_Win32,
// Base -> Base_Win32); nil ohne. Gefragt wird nur mit einem Namen aus
// ACfg.Platforms (wie CnWizards) - ob PlatformConfiguration fuer einen
// fremden Namen nil liefert oder wirft, sagt die ToolsAPI nicht.
function PlatformCfgOf(const ACfg: IOTABuildConfiguration;
  const APlatform: string): IOTABuildConfiguration;
var
  Name : string;
begin
  Result := nil;
  if APlatform = '' then Exit;
  for Name in ACfg.Platforms do
    if SameText(Name, APlatform) then
      Exit(ACfg.PlatformConfiguration[Name]);
end;

// Der Unit-Suchpfad des Projekts AProj fuer die Gegenprobe (Review R1,
// missed 3; 360 von 3.305 .dproj des Korpus setzen ihn auf Plattform-Ebene,
// ActiveConfiguration allein sah ihn nicht): die VEREINIGUNG aus
//   * dem Wert der aktiven Plattform-Konfiguration samt Geerbtem
//     (GetValue(.., True); gibt es sie nicht, der aktiven Konfiguration)
//     und
//   * jeder Ebene einzeln ohne Geerbtes: die aktive Konfiguration und ihre
//     Eltern bis Base, je fuer alle Plattformen und fuer die aktive
//     (Cfg_1, Cfg_1_Win32, Base, Base_Win32).
// Ob GetValue(.., True) auf Cfg_1_Win32 auch Base_Win32 einschliesst, ist in
// der IDE NICHT geprueft (Nachbesserung, Pruefer missed 3) - die Vereinigung
// haengt nicht daran. Eine Ebene, die den Suchpfad ersetzt statt erweitert,
// bringt hoechstens ein Verzeichnis zu viel: dann sperrt die Gegenprobe
// einen Eintrag mehr, qualifiziert aber keinen zu viel. Doppelte
// Verzeichnisse fallen im Index zusammen.
procedure AddSearchPaths(AUnits: TRdxProjectUnits; const AProj: IOTAProject);
var
  Cfgs    : IOTAProjectOptionsConfigurations;
  Cfg     : IOTABuildConfiguration;
  PlatCfg : IOTABuildConfiguration;
  BaseDir : string;
  Plat    : string;
  Level   : Integer;
begin
  if not Supports(AProj.ProjectOptions, IOTAProjectOptionsConfigurations,
       Cfgs) then
    Exit;
  Cfg := Cfgs.ActiveConfiguration;
  if Cfg = nil then Exit;
  BaseDir := ExtractFilePath(AProj.FileName);
  Plat    := AProj.CurrentPlatform;
  PlatCfg := PlatformCfgOf(Cfg, Plat);
  if PlatCfg = nil then
    PlatCfg := Cfg;
  AUnits.AddSearchPath(PlatCfg.GetValue(UNIT_SEARCH_PATH, True), BaseDir);
  for Level := 1 to MAX_CFG_DEPTH do
  begin
    AUnits.AddSearchPath(Cfg.GetValue(UNIT_SEARCH_PATH, False), BaseDir);
    PlatCfg := PlatformCfgOf(Cfg, Plat);
    if PlatCfg <> nil then
      AUnits.AddSearchPath(PlatCfg.GetValue(UNIT_SEARCH_PATH, False), BaseDir);
    Cfg := Cfg.Parent;
    if Cfg = nil then Break;
  end;
end;

// Module und Unit-Suchpfad des Projekts AProj in den Index; nil: nichts.
procedure AddProjectUnits(AUnits: TRdxProjectUnits; const AProj: IOTAProject);
var
  Info : IOTAModuleInfo;
  i    : Integer;
begin
  if AProj = nil then Exit;
  for i := 0 to AProj.GetModuleCount - 1 do
  begin
    Info := AProj.GetModule(i);
    if Info <> nil then
      AUnits.AddModule(Info.FileName);
  end;
  AddSearchPaths(AUnits, AProj);
end;

class function TRdxEditor.ProjectUnits(
  const ANearFile: string): TRdxProjectUnits;
var
  ModSvc : IOTAModuleServices;
  Group  : IOTAProjectGroup;
  j      : Integer;
begin
  Result := TRdxProjectUnits.Create;
  try
    // Netzpfade (UNC und Netzlaufwerke) liest der Index nicht - er fragt
    // die Regel uRdxPaths.IsNetworkPath selbst (bis Charge B2S-a setzte
    // diese Unit dafuer einen eigenen GetDriveType-Test).
    // 1) Dateien neben der bearbeiteten Datei
    if ANearFile <> '' then
      Result.AddDir(ExtractFilePath(ANearFile));
    // 2) Module und Suchpfade aller Projekte der Gruppe - die bearbeitete
    //    Datei kann zu einem anderen als dem aktiven gehoeren.
    if Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then
    begin
      Group := ModSvc.MainProjectGroup;
      if Group = nil then
        AddProjectUnits(Result, ModSvc.GetActiveProject)
      else
        for j := 0 to Group.ProjectCount - 1 do
          AddProjectUnits(Result, Group.Projects[j]);
    end;
    if Result.Unreadable <> '' then
      RdxLog('Projekt-Units: Netzpfad %s nicht gelesen', [Result.Unreadable]);
  except
    Result.Free;
    raise;
  end;
end;

end.
