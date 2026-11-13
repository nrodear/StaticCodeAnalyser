unit uIDEEditorIntegration;

// Zustandslose Huellen um die ToolsAPI fuer alles, was Dock-Fenster,
// Kontextmenue und Gluehbirne vom IDE-Editor brauchen:
//   * eine Datei im Editor oeffnen und zu einer Zeile springen
//     (OpenFileAtLine, ShowFileAtLine, CenterCurrentViewOnLine);
//   * die .pas der obersten Ansicht bestimmen (TryGetCurrentPasFile) und
//     Datei plus Caret-Zeile einer Ansicht lesen (ViewFileAndLine,
//     TopViewFileAndLine - EINE Fassung fuer Kontextmenue und Birne,
//     Review 2026-10-14, Punkt 10);
//   * Caret und Auswahl einer Ansicht in ZEICHEN-Spalten als
//     TEditorContext (ViewContext, TopViewContext - Charge B, V3: die
//     Code-Aktionen ohne Fund im Editor-Kontextmenue);
//   * das Verzeichnis des aktiven Projekts (GetCurrentProjectDir);
//   * eine Zeile VOR eine Pufferzeile schreiben (InsertLineAbove - der
//     Unterdrueck-Marker von Ctrl+Alt+S ohne Anbieter).
//
// Vorher: zwei Methoden + eine free function direkt in der God-Class
// TAnalyserFrame, alle drei mit `BorlandIDEServices as IOTAxxx`-Casts
// die `EIntfCastError` werfen wenn der Service in einem instabilen
// IDE-Zustand nicht verfuegbar ist (z.B. waehrend BPL-Reload).
//
// Hier saubere `Supports(...)`-Casts -> defensive failure-mode statt
// AV. Loest gleich zwei TODO-Items zu „OpenFileAtLine / Analyse
// CurrentFileClick AV-Pfade" und „RegisterDockableForm `as`-Cast".

interface

uses
  ToolsAPI,
  uFindingActions;   // TEditorContext (ViewContext)

type
  // Status-Code von TryGetCurrentPasFile - der Caller will pro Fehlerursache
  // eine andere Status-Bar-Meldung anzeigen (lokalisierter Text bleibt im
  // Caller, dieser hier ist UI-frei).
  TCurrentFileResult = (
    cfrOK,                 // .pas-Datei erfolgreich detektiert
    cfrNoEditorService,    // BorlandIDEServices ohne IOTAEditorServices
    cfrNoOpenView,         // kein offener Editor-View / Buffer
    cfrNotPascalFile       // Datei offen, aber kein .pas / .dfm
  );

  // Result-Code von OpenFileAtLine - damit der Aufrufer in der Status-Bar
  // den richtigen Hinweis zeigen kann.
  TOpenFileMode = (
    ofmRegular,         // .pas - oder der DFM-Sprung kam nicht zustande
    ofmDfmAsText        // .dfm-Befund: die DFM steht NACHWEISLICH als Text
                        // im Code-Editor (ShowDfmAsTextAtLine = True)
    // Ein dritter Wert ofmDfmFallbackPas ("Companion-.pas war modifiziert,
    // deshalb nur die .pas geoeffnet") stand hier bis 2026-08-18 und wurde
    // nie zugewiesen. Den Fall gibt es weiter nicht: ein geaendertes
    // Form-Modul schliesst die IDE erst nach ihrer eigenen Rueckfrage
    // (s. CloseModuleOf in der Implementierung).
  );

  TIDEEditor = class
  public
    // Versucht den Pfad der aktuell im Editor offenen .pas- oder .dfm-Datei
    // zu liefern. Bei OK enthaelt APath einen absoluten Pfad.
    // Bei einer .dfm wird automatisch auf die zugehoerige .pas umgeleitet
    // (gleicher Basename im gleichen Ordner), damit der DFM-Analyse-Runner
    // sie sauber als Pas-Input bekommt - er sucht intern selbst nach
    // der .dfm dazu.
    class function TryGetCurrentPasFile(out APath: string): TCurrentFileResult; static;

    // Datei und Caret-Zeile EINER Ansicht - ohne Umleitung auf die .pas:
    // auch .dpr/.dpk/.inc, und in der Textansicht eines Formulars die
    // .dfm selbst (deren Zeilen stehen nicht in der .pas; Review reDelphiX
    // nach Bereichen 2026-10-10, Minor 20). False ohne Ansicht, Puffer,
    // Dateinamen oder bei Zeile < 1. nil-sicher.
    class function ViewFileAndLine(const AView: IOTAEditView;
      out AFile: string; out ALine: Integer): Boolean; static;
    // Dasselbe fuer die oberste Ansicht (TopView) - der Weg des
    // Editor-Kontextmenues; die Gluehbirne nimmt die Ansicht IHRES
    // Editors (INTACodeEditorServices.GetViewForEditor) und ruft
    // ViewFileAndLine.
    class function TopViewFileAndLine(out AFile: string;
      out ALine: Integer): Boolean; static;

    // Datei, Caret (Zeile, ZEICHEN-Spalte 1-basiert) und Auswahl einer
    // Ansicht als TEditorContext (Charge B, V3). Datei und Zeile wie
    // ViewFileAndLine (auch .dfm in der Textansicht), False in denselben
    // Faellen. Die Spalten kommen aus IOTAEditView.ConvertPos: CharIndex
    // zaehlt ZEICHEN (0-basiert, Tab = 1; gemessen 2026-10-11) - keine
    // Byte-Rechnung, kein Puffertext. Auswahl nur aus einem gueltigen,
    // sichtbaren, nicht leeren Block; ein Spaltenblock ist keine Auswahl
    // (uEditorContextModel.ApplyEditorBlock). Findings bleibt leer (setzt
    // der Aufrufer). Protokolliert Rohwerte und Umrechnung per
    // OutputDebugString ('SCA: ctx ...', nur im DEBUG-Bau) - Messpunkt fuer
    // den UI-Test (btInclusive/btLine und das Blockende auf
    // Nicht-ASCII-Zeilen sind ungemessen). Reine Abfrage: kein Notifier,
    // kein Fenster. Nur mit GContextActionsOn gerufen - ohne den Schalter
    // nimmt das Kontextmenue TopViewFileAndLine wie bis Charge B.
    class function ViewContext(const AView: IOTAEditView;
      out ACtx: TEditorContext): Boolean; static;
    // Dasselbe fuer die oberste Ansicht - der Weg des Editor-Kontextmenues.
    class function TopViewContext(out ACtx: TEditorContext): Boolean; static;

    // Liefert das Verzeichnis des aktiven IDE-Projekts (ohne Trailing
    // PathDelimiter). Leer wenn kein Projekt geladen oder Service
    // nicht verfuegbar.
    class function GetCurrentProjectDir: string; static;

    // Oeffnet eine Datei im IDE-Editor (oder bringt sie nach vorne wenn
    // bereits offen) und positioniert den Cursor auf LineNumber.
    // No-op bei nicht-verfuegbaren Services. LineNumber <= 0: die Datei
    // wird geoeffnet, nur der Cursor nicht gesetzt.
    //
    // .dfm: wie ShowDfmAsTextAtLine; ofmDfmAsText nur, wenn die DFM danach
    // wirklich als Text gezeigt wird. .pas: wie ShowFileAtLine, nur dass
    // die Datei auch bei LineNumber <= 0 geoeffnet wird.
    class function OpenFileAtLine(const AbsPath: string;
                                  LineNumber: Integer): TOpenFileMode; static;

    // Sprung aus einer Fundliste: bringt die Datei nach vorn (oeffnet sie
    // noetigenfalls) und setzt den Caret. True, wenn der Caret gesetzt ist.
    // .dfm-Befunde gehen an ShowDfmAsTextAtLine - nie ein Sprung mit der
    // DFM-Zeilennummer in die .pas. Bei einem .pas-Befund wird vorher nur
    // EINES geschlossen: die DFM derselben Unit, wenn sie von einem
    // DFM-Sprung noch als freistehender Text offen ist.
    class function ShowFileAtLine(const AbsPath: string;
                                  LineNumber: Integer): Boolean; static;

    // ShowFileAtLine und danach - NUR bei Erfolg - CenterCurrentViewOnLine:
    // nach einem gescheiterten Sprung laege oben eine fremde Datei, und das
    // Zentrieren setzte deren Caret auf die Fundzeile.
    class function ShowFileCenteredAtLine(const AbsPath: string;
      LineNumber: Integer): Boolean; static;

    // Zeigt eine .dfm als TEXT im Code-Editor und setzt den Caret auf
    // LineNumber (<= 0: nur zeigen). Die IDE laedt eine DFM nur dann als
    // Text, wenn ihr Form-Modul NICHT offen ist (gemessen 2026-11-13) - ist
    // die Unit offen, wird ihr Modul deshalb zuerst geschlossen. Traegt es
    // nachweislich nichts vom Nutzer (nur was die IDE selbst eingetragen
    // hat), ohne Rueckfrage; sonst auf dem normalen Weg der IDE: bei
    // ungespeicherten Aenderungen fragt sie selbst, "Abbrechen" laesst
    // alles, wie es ist. True NUR, wenn danach die oberste Ansicht wirklich
    // die .dfm zeigt; sonst bleibt der Caret unangetastet.
    class function ShowDfmAsTextAtLine(const AbsPath: string;
                                       LineNumber: Integer): Boolean; static;

    // Bringt LineNumber im aktuellen Top-EditView in die Mitte des
    // Editor-Fensters und setzt den Cursor dorthin. No-op bei
    // LineNumber <= 0 oder fehlendem Editor-Service.
    //
    // Unterschied zu OpenFileAtLine.MoveViewToCursor: letzteres scrollt
    // nur das Minimum noetig, damit der Cursor sichtbar wird (haengt am
    // oberen oder unteren Rand). Hier rechnen wir die sichtbare Hoehe
    // aus BottomRow-TopRow aus und setzen SetTopLeft so dass die
    // Zielzeile vertikal mittig liegt - der User sieht den Befund
    // sofort ohne Augen-Tracking-Aufwand.
    class procedure CenterCurrentViewOnLine(LineNumber: Integer); static;

    // Fuegt eine neue Zeile DIREKT VOR der angegebenen LineNumber ein.
    // Wird vom Auto-Suppress benutzt: `// noinspection <RuleName>`
    // ueber der Befund-Zeile (Host und Zeile liefert
    // TSuppression.MarkerTargetFor - bei einem .dfm-Fund die .pas).
    // NewLine wird mit der Einrueckung der Befund-Zeile ausgerichtet
    // (lexikalisches Whitespace-Kopieren), damit der Marker visuell zur
    // Code-Zeile gehoert; das Zeilenende ist das des PUFFERS an dieser
    // Zeile (eine LF-Datei bekommt kein CRLF untergeschoben, Review
    // 2026-10-14), hinter der letzten Zeile ohne Zeilenende sLineBreak.
    //
    // Liefert True bei Erfolg, sonst False (Datei nicht in der IDE,
    // Zeile out-of-range, ...).
    class function InsertLineAbove(const AbsPath: string;
      LineNumber: Integer; const NewLine: string): Boolean; static;

    // Vom zentralen IDE-Notifier (uIDELineHighlighter) bei ofnFileClosing:
    // der Vergleichsstand, an dem die Navigation erkennt, ob seit ihrem
    // Sprung jemand getippt hat (s. "Vergleichsstand" in der
    // Implementierung), wird mit dem Modul nicht mehr gebraucht.
    class procedure NoteFileClosing(const AFileName: string); static;
  end;

const
  // Ablaufspur der Fund-Navigation: geschrieben wird nur, solange im
  // TEMP-Verzeichnis die Schalterdatei liegt (Inhalt egal). Kein Egress.
  NAVTRACE_SWITCH = 'sca-navtrace.on';
  NAVTRACE_FILE   = 'sca-navtrace.log';

// Eine Zeile Ablaufspur (Zeitstempel + Text) nach %TEMP%\sca-navtrace.log,
// wenn %TEMP%\sca-navtrace.on existiert. Wirft nie.
procedure NavTrace(const AText: string);

// Wie NavTrace, haengt aber an, was die IDE zu AFileName gerade fuehrt:
// 'Modul[src:Unit.pas* form:Unit.dfm]', '*' = gilt als geaendert, '-' ohne
// Modul. Fuer die Frage, WANN eine Unit ohne Zutun des Nutzers als geaendert
// gilt (s. "Vergleichsstand" in der Implementierung). Gelesen wird nur bei
// laufender Spur. Wirft nie.
procedure NavTraceState(const AWhat, AFileName: string);

implementation

// noinspection-file AvoidOut, BeginEndRequired, DuplicateBlock, GroupedDeclaration, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  Winapi.Windows,        // OutputDebugString; VOR System.SysUtils (FindClose-Falle)
  System.SysUtils, System.IOUtils, System.Classes,
  System.Generics.Collections,
  uCrashDiag,            // EStackExhausted - nie verschlucken
  uEditorContextModel,   // ApplyEditorBlock, DecideModuleClose - der getestete Kern
  uPathNormalize;        // Schluessel der Vergleichsstaende

function IsDfmFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm');
end;

function FirstSourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
// Der Pascal-Quelltext eines Moduls: der erste IOTASourceEditor unter den
// ModuleFileEditors, der KEINE .dfm ist - in der Textansicht eines
// Formulars fuehrt das Modul auch die DFM als Quelltext-Editor. nil ohne
// Modul oder ohne solchen Editor.
var
  i : Integer;
begin
  Result := nil;
  if not Assigned(AModule) then Exit;
  for i := 0 to AModule.ModuleFileCount - 1 do
    if Supports(AModule.ModuleFileEditors[i], IOTASourceEditor, Result)
       and not IsDfmFile(Result.FileName) then
      Exit;
  Result := nil;
end;

function DfmTextEditorOf(const AModule: IOTAModule): IOTASourceEditor;
// Die DFM eines Moduls als TEXT-Editor - den gibt es nur in der Ansicht
// "als Text" (oder bei einer freistehenden .dfm). nil in der
// Designer-Ansicht: dort ist der DFM-Editor ein IOTAFormEditor.
var
  i : Integer;
begin
  Result := nil;
  if not Assigned(AModule) then Exit;
  for i := 0 to AModule.ModuleFileCount - 1 do
    if Supports(AModule.ModuleFileEditors[i], IOTASourceEditor, Result)
       and IsDfmFile(Result.FileName) then
      Exit;
  Result := nil;
end;

function NavTraceOn: Boolean;
// Die Schalterdatei liegt - vor teuren Spurtexten (Modulzustand) fragen.
begin
  Result := FileExists(IncludeTrailingPathDelimiter(TPath.GetTempPath)
    + NAVTRACE_SWITCH);
end;

procedure NavTrace(const AText: string);
// Reine Win32-Aufrufe statt TFile: ein Schreibfehler ist dann ein
// Rueckgabewert, keine Exception - die Spur darf die Navigation nie stoeren.
var
  Dir     : string;
  Line    : UTF8String;
  Handle  : THandle;
  Written : DWORD;
begin
  if not NavTraceOn then Exit;
  Dir := IncludeTrailingPathDelimiter(TPath.GetTempPath);
  Line := UTF8Encode(FormatDateTime('hh:nn:ss.zzz', Now,
    TFormatSettings.Invariant) + ' ' + AText + sLineBreak);
  Handle := CreateFile(PChar(Dir + NAVTRACE_FILE), FILE_APPEND_DATA,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then Exit;
  WriteFile(Handle, PAnsiChar(Line)^, Length(Line), Written, nil);
  CloseHandle(Handle);
end;

procedure DfmNavLog(const AText: string);
// Diagnose der DFM-Navigation: DebugView (Praefix 'SCA: dfmnav') und Spur.
begin
  // noinspection DebugOutput
  OutputDebugString(PChar('SCA: dfmnav ' + AText));
  NavTrace(AText);
end;

function TopViewFileName: string;
// Datei der obersten Editor-Ansicht, '' ohne Ansicht - nur fuer die Spur.
var
  EditorSvc : IOTAEditorServices;
  View      : IOTAEditView;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  View := EditorSvc.TopView;
  if Assigned(View) and Assigned(View.Buffer) then
    Result := View.Buffer.FileName;
end;

// ---------------------------------------------------------------------------
// Vergleichsstand "so sah der Puffer direkt nach dem Sprung aus"
//
// Wozu: die IDE fuehrt eine Unit als geaendert, sobald sie selbst Units in
// die uses-Klausel eingetragen hat, die das Formular braucht
// (ShowcaseDemo\uOrderForm: FireDAC.Phys.PG, FireDAC.Phys.PGDef). Schliesst
// die Fund-Navigation so eine Unit, fragte die IDE jedesmal "Speichern?" -
// auch wenn niemand getippt hat (Nutzer-Fund 2026-11-13). CloseModuleOf
// schliesst deshalb OHNE Rueckfrage, wenn der Puffer nachweislich nichts
// vom Nutzer traegt: er gleicht der Datei, oder er gleicht dem
// Vergleichsstand und die Datei ist seither dieselbe
// (uEditorContextModel.DecideModuleClose).
//
// WANN die IDE die Unit aendert (gemessen 2026-11-13, uOrderForm): NICHT
// beim Oeffnen - nach OpenFile und bei ofnFileOpened gleicht der Puffer der
// Datei, auch Sekunden spaeter -, sondern synchron in IOTASourceEditor.Show,
// mit dem die Navigation den Tab nach vorn holt (5989 -> 6026 Bytes, der
// uses-Eintrag; das Setzen des Carets aendert nichts). Es ist also unser
// eigener Sprung, der die Unit "aendert".
//
// Ein Vergleichsstand entsteht deshalb genau dort und NUR, wenn der Puffer
// unmittelbar VOR dem Show nachweislich nichts Ungespeichertes trug - das
// Modul hat dieser Aufruf gerade erst geoeffnet, oder der Editor galt nicht
// als geaendert, oder sein Puffer glich der Datei (UnitAtLine). Dazwischen
// laeuft nur unser synchroner Aufruf; was danach im Puffer steht, ist Datei
// plus Aenderung der IDE. Traegt der Puffer vor dem Sprung schon etwas
// (getippt, oder von der IDE bei einem Ansichtswechsel des Nutzers
// eingetragen - das ist von aussen nicht zu unterscheiden), entsteht keiner;
// dort gilt nur der Vergleich mit der Datei, sonst fragt die IDE wie bisher.
// Gehalten werden Puffertext UND Dateiinhalt: nach einem Speichern
// dazwischen beweist die Gleichheit mit dem alten Puffertext nichts mehr.
// ---------------------------------------------------------------------------

const
  // Groesser wird kein Puffer verglichen oder gehalten - dann fragt die IDE.
  MAX_COMPARE_BYTES = 16 * 1024 * 1024;

type
  TNavBaseline = record
    Buffer : TBytes;   // Puffertext (UTF-8, wie IOTAEditReader ihn liefert)
    Disk   : TBytes;   // rohe Dateibytes zum selben Zeitpunkt
  end;

var
  // Schluessel: BaselineKey(Datei des Quelltext-Editors). Nur Hauptthread.
  GNavBaselines : TDictionary<string, TNavBaseline> = nil;

function BaselineKey(const AFileName: string): string;
begin
  Result := NormalizePathForKey(ExpandFileName(AFileName));
end;

function ReadEditorBytes(const AEditor: IOTASourceEditor;
  out ABytes: TBytes): Boolean;
// Der Puffertext als UTF-8-Bytes. False ohne Reader, ueber
// MAX_COMPARE_BYTES oder bei jedem Fehler des Readers - der Aufrufer
// behandelt das als "nicht belegbar". Der Reader ist beim Ruecksprung frei.
const
  BLOCK = 16384;
var
  Reader : IOTAEditReader;
  Chunk  : TBytes;
  Got    : Integer;
  Total  : Integer;
begin
  Result := False;
  ABytes := nil;
  if not Assigned(AEditor) then Exit;
  try
    Reader := AEditor.CreateReader;
    if not Assigned(Reader) then Exit;
    SetLength(Chunk, BLOCK);
    Total := 0;
    repeat
      Got := Reader.GetText(Total, PAnsiChar(@Chunk[0]), BLOCK);
      if Got > 0 then
      begin
        if Total + Got > MAX_COMPARE_BYTES then
        begin
          ABytes := nil;
          Exit;
        end;
        SetLength(ABytes, Total + Got);
        Move(Chunk[0], ABytes[Total], Got);
        Inc(Total, Got);
      end;
    until Got < BLOCK;
    Result := True;
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Die Puffer-API wirft ohne eigene Klasse (Modul im Abbau, Puffer
    // gesperrt): nicht gelesen - dann fragt die IDE.
    on Exception do
    begin
      ABytes := nil;
      Result := False;
    end;
  end;
end;

function LoadFileBytes(const AFileName: string; out ABytes: TBytes): Boolean;
// Liest die Datei, ohne sie fuer andere zu sperren. False ueber
// MAX_COMPARE_BYTES; Lesefehler wirft der Stream (s. ReadFileBytes).
var
  Stream : TFileStream;
begin
  ABytes := nil;
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Result := Stream.Size <= MAX_COMPARE_BYTES;
    if not Result then Exit;
    SetLength(ABytes, Stream.Size);
    if Length(ABytes) > 0 then
      Stream.ReadBuffer(ABytes[0], Length(ABytes));
  finally
    Stream.Free;
  end;
end;

function ReadFileBytes(const AFileName: string; out ABytes: TBytes): Boolean;
// Die rohen Bytes der Datei. False, wenn sie fehlt, nicht lesbar oder
// groesser als MAX_COMPARE_BYTES ist.
begin
  try
    Result := LoadFileBytes(AFileName, ABytes);
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Datei weg, gesperrt, Lesefehler (EFOpenError, EReadError,
    // EInOutError ...): nicht gelesen - dann fragt die IDE.
    on Exception do
    begin
      ABytes := nil;
      Result := False;
    end;
  end;
end;

procedure ForgetBaseline(const AFileName: string);
begin
  if Assigned(GNavBaselines) then
    GNavBaselines.Remove(BaselineKey(AFileName));
end;

function HoldsNothingUnsaved(const AEditor: IOTASourceEditor): Boolean;
// Traegt der Editor nachweislich nichts Ungespeichertes? Ja, wenn die IDE
// ihn nicht als geaendert fuehrt (dann schloesse sie ihn selbst ohne
// Rueckfrage) oder sein Puffer der Datei gleicht. Nicht lesbar: Nein.
var
  Buffer : TBytes;
  Disk   : TBytes;
begin
  Result := False;
  if not Assigned(AEditor) then Exit;
  try
    Result := not AEditor.Modified
      or (ReadEditorBytes(AEditor, Buffer)
        and ReadFileBytes(AEditor.FileName, Disk)
        and BufferMatchesDisk(Buffer, Disk));
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // ToolsAPI ohne eigene Fehlerklasse: nicht belegt - kein Vergleichsstand.
    on Exception do
      Result := False;
  end;
end;

procedure RememberBaseline(const AEditor: IOTASourceEditor);
// Haelt Puffertext und Dateiinhalt des Editors fest. NUR von der einen
// Stelle zu rufen, an der der Puffer nachweislich nichts vom Nutzer traegt
// (UnitAtLine, s. Kopf dieses Abschnitts). Ist eines von beiden nicht
// lesbar, gibt es keinen Vergleichsstand (ein alter verfaellt). Wirft nie.
var
  FileName : string;
  Baseline : TNavBaseline;
begin
  if not Assigned(AEditor) then Exit;
  try
    FileName := AEditor.FileName;
    ForgetBaseline(FileName);
    if not ReadEditorBytes(AEditor, Baseline.Buffer) then Exit;
    if not ReadFileBytes(FileName, Baseline.Disk) then Exit;
    if not Assigned(GNavBaselines) then
      GNavBaselines := TDictionary<string, TNavBaseline>.Create;
    GNavBaselines.AddOrSetValue(BaselineKey(FileName), Baseline);
    NavTrace(Format('stand: %s Puffer=%d Datei=%d gleichDatei=%s',
      [ExtractFileName(FileName), Length(Baseline.Buffer),
       Length(Baseline.Disk),
       BoolToStr(BufferMatchesDisk(Baseline.Buffer, Baseline.Disk), True)]));
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Ohne Vergleichsstand fragt die IDE - das ist der sichere Ausgang
    // fuer jeden Fehler hier (ToolsAPI ohne eigene Fehlerklasse).
    on Exception do
      if FileName <> '' then
        ForgetBaseline(FileName);
  end;
end;

function FindOrOpenModule(const AbsPath: string): IOTAModule;
// Das Modul zu einer Datei - schon offen, sonst ueber File->Open. nil ohne
// Dienst oder wenn die IDE die Datei nicht oeffnet. Nicht fuer .dfm: bei
// offenem Form-Modul liefert FindModule(.dfm) das Modul der UNIT.
var
  ModSvc : IOTAModuleServices;
  ActSvc : IOTAActionServices;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  Result := ModSvc.FindModule(AbsPath);
  if Assigned(Result) then Exit;
  if Supports(BorlandIDEServices, IOTAActionServices, ActSvc) then
    ActSvc.OpenFile(AbsPath);
  Result := ModSvc.FindModule(AbsPath);
end;

function PlaceCaretInView(const AView: IOTAEditView; ALine: Integer): Boolean;
// Caret der Ansicht auf ALine, Spalte 1, und in den sichtbaren Bereich.
var
  EditPos : TOTAEditPos;
begin
  Result := False;
  if not Assigned(AView) then Exit;
  EditPos.Col  := 1;
  EditPos.Line := ALine;
  AView.CursorPos := EditPos;
  AView.MoveViewToCursor;
  AView.Paint;
  Result := True;
end;

function PlaceCaret(const AEditor: IOTASourceEditor; ALine: Integer): Boolean;
// Caret der ersten Ansicht auf ALine. False ohne Ansicht.
begin
  Result := False;
  if not Assigned(AEditor) or (AEditor.EditViewCount < 1) then Exit;
  Result := PlaceCaretInView(AEditor.GetEditView(0), ALine);
end;

function ViewShowsFile(const AView: IOTAEditView; const AbsPath: string): Boolean;
begin
  Result := Assigned(AView) and Assigned(AView.Buffer)
    and SameFileName(ExpandFileName(AView.Buffer.FileName),
                     ExpandFileName(AbsPath));
end;

function EditorTag(const AEditor: IOTAEditor): string;
// Fuer die Spur: Art, Datei und '*' fuer Modified - 'src:Foo.pas*'.
var
  Src  : IOTASourceEditor;
  Form : IOTAFormEditor;
begin
  if not Assigned(AEditor) then Exit('nil');
  if Supports(AEditor, IOTASourceEditor, Src) then
    Result := 'src:'
  else if Supports(AEditor, IOTAFormEditor, Form) then
    Result := 'form:'
  else
    Result := '?:';
  Result := Result + ExtractFileName(AEditor.FileName);
  if AEditor.Modified then
    Result := Result + '*';
end;

function ModuleStateText(const AFileName: string): string;
// Fuer die Spur: was die IDE zu AFileName gerade fuehrt - '-' ohne Modul,
// sonst 'Modul[Editor Editor]'.
var
  ModSvc : IOTAModuleServices;
  Module : IOTAModule;
  Tags   : TArray<string>;
  i      : Integer;
begin
  Result := '-';
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  Module := ModSvc.FindModule(AFileName);
  if not Assigned(Module) then Exit;
  SetLength(Tags, Module.ModuleFileCount);
  for i := 0 to High(Tags) do
    Tags[i] := EditorTag(Module.ModuleFileEditors[i]);
  Result := Format('%s[%s]', [ExtractFileName(Module.FileName),
    string.Join(' ', Tags)]);
end;

procedure TraceState(const AWhat, AFileName: string);
// Spurzeile mit Modulzustand - der Zustand wird nur bei laufender Spur
// gelesen (er fasst jeden Datei-Editor des Moduls an).
begin
  if NavTraceOn then
    NavTrace(Format('%s %s top=%s', [AWhat, ModuleStateText(AFileName),
      ExtractFileName(TopViewFileName)]));
end;

procedure NavTraceState(const AWhat, AFileName: string);
begin
  try
    TraceState(AWhat, AFileName);
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Nur Spur: ein Modul im Auf- oder Abbau darf sie nicht stoeren
    // (ToolsAPI ohne eigene Fehlerklasse).
    on Exception do
      NavTrace(AWhat + ' (Zustand nicht lesbar)');
  end;
end;

function IsModuleOpen(const AFileName: string): Boolean;
var
  ModSvc : IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, ModSvc)
    and Assigned(ModSvc.FindModule(AFileName));
end;

function HasDfmTextEditor(const ADfmPath: string): Boolean;
// Die IDE fuehrt die DFM als TEXT - freistehend oder in der Textansicht
// ihres Form-Moduls.
var
  ModSvc : IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, ModSvc)
    and Assigned(DfmTextEditorOf(ModSvc.FindModule(ADfmPath)));
end;

function IsStandaloneDfmText(const ADfmPath: string): Boolean;
// Die DFM ist als FREISTEHENDER Text offen: ihr Modul fuehrt einen
// DFM-Texteditor, aber keine Unit.
var
  ModSvc : IOTAModuleServices;
  Module : IOTAModule;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  Module := ModSvc.FindModule(ADfmPath);
  Result := Assigned(Module) and Assigned(DfmTextEditorOf(Module))
    and not Assigned(FirstSourceEditorOf(Module));
end;

function EditorCloseState(const AEditor: IOTAEditor;
  out ATag: string): TModuleEditorState;
// Liest EINEN Datei-Editor fuer die Schliess-Entscheidung. Belegt wird nur,
// was gelesen wurde: ein nicht lesbarer Puffer, eine nicht lesbare Datei
// oder ein fehlender Vergleichsstand lassen die Felder False (dann fragt die
// IDE). ATag: der Zustand fuer die Spur. Haelt beim Ruecksprung nichts.
var
  Src      : IOTASourceEditor;
  Buffer   : TBytes;
  Disk     : TBytes;
  DiskRead : Boolean;
  Baseline : TNavBaseline;
begin
  Result := Default(TModuleEditorState);
  Result.Kind := mekOther;
  ATag := EditorTag(AEditor);
  if not Assigned(AEditor) then Exit;
  Result.Modified := AEditor.Modified;
  if Supports(AEditor, IOTAFormEditor) then
    Result.Kind := mekForm
  else if Supports(AEditor, IOTASourceEditor, Src) then
    Result.Kind := mekSource;
  if (Result.Kind <> mekSource) or not Result.Modified then Exit;

  Result.BufferRead := ReadEditorBytes(Src, Buffer);
  if not Result.BufferRead then
  begin
    ATag := ATag + '[Puffer nicht lesbar]';
    Exit;
  end;
  DiskRead := ReadFileBytes(Src.FileName, Disk);
  Result.EqualsDisk := DiskRead and BufferMatchesDisk(Buffer, Disk);
  Result.HasBaseline := Assigned(GNavBaselines)
    and GNavBaselines.TryGetValue(BaselineKey(Src.FileName), Baseline);
  if Result.HasBaseline then
  begin
    Result.EqualsBaseline   := SameBytes(Buffer, Baseline.Buffer);
    Result.DiskAsAtBaseline := DiskRead and SameBytes(Disk, Baseline.Disk);
  end;
  ATag := ATag + Format('[Puffer=%d Datei=%s gleichDatei=%s Stand=%s '
    + 'gleichStand=%s DateiWieStand=%s]',
    [Length(Buffer), BoolToStr(DiskRead, True),
     BoolToStr(Result.EqualsDisk, True), BoolToStr(Result.HasBaseline, True),
     BoolToStr(Result.EqualsBaseline, True),
     BoolToStr(Result.DiskAsAtBaseline, True)]);
end;

function ModuleCloseDecision(const AFileName: string): TModuleCloseDecision;
// Darf das Modul zu AFileName ohne die Rueckfrage der IDE zu? Liest jeden
// Datei-Editor des Moduls und entscheidet in
// uEditorContextModel.DecideModuleClose. Jeder Fehler heisst mcdAsk. Eigene
// Routine, damit beim Ruecksprung keine Editor-Referenz mehr lebt
// (s. CloseModuleOf). Schreibt die Entscheidung in die Spur.
const
  NAMES : array[TModuleCloseDecision] of string = (
    'normal (nichts geaendert)', 'OHNE Rueckfrage (nachweislich unbearbeitet)',
    'IDE fragt');
var
  ModSvc : IOTAModuleServices;
  Module : IOTAModule;
  States : TArray<TModuleEditorState>;
  Tags   : TArray<string>;
  i      : Integer;
begin
  Result := mcdAsk;
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
    Module := ModSvc.FindModule(AFileName);
    if not Assigned(Module) then Exit;
    SetLength(States, Module.ModuleFileCount);
    SetLength(Tags, Length(States));
    for i := 0 to High(States) do
      States[i] := EditorCloseState(Module.ModuleFileEditors[i], Tags[i]);
    Result := DecideModuleClose(States);
    NavTrace(Format('close: Entscheid %s - %s',
      [NAMES[Result], string.Join(' ', Tags)]));
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Jeder Fehler beim Lesen (ToolsAPI ohne eigene Fehlerklasse) laesst
    // die IDE fragen - nie umgekehrt.
    on E: Exception do
    begin
      Result := mcdAsk;
      NavTrace('close: Entscheid IDE fragt - Fehler beim Lesen: '
        + E.ClassName + ': ' + E.Message);
    end;
  end;
end;

function CloseModuleOf(const AFileName: string): Boolean;
// Schliesst das Modul, das die IDE zu AFileName fuehrt. True, wenn danach
// keines mehr offen ist (oder nie war).
//
// Ohne Rueckfrage (ForceClosed=True) NUR, wenn ModuleCloseDecision belegt
// hat, dass kein Editor etwas vom Nutzer traegt (Vergleichsstand, s.
// RememberBaseline) - dann verfallen allein die Aenderungen, die die IDE
// selbst gemacht hat, geschrieben wird nichts (gemessen 2026-11-13: kein
// Dialog, Dateien auf der Platte unveraendert). Sonst auf dem NORMALEN
// Schliessen-Weg der IDE:
//
// ToolsAPI.pas woertlich - IOTAModule50.CloseModule(ForceClosed): "allows
// an add-in to force a module closed regardless of whether or not it is
// modified. If ForceClosed is False, then calling this method has the same
// behavior as Close"; IOTAModule40.Close: "Attempt to close this module.
// True was successful and all references to this module must be released.
// False if this module was not closed." Von Speichern steht bei
// ForceClosed=True nichts - es schliesst auch ein geaendertes Modul ohne
// Rueckfrage (der fruehere SafeCloseModule rief genau das und nannte es
// "save-if-dirty"). Deshalb im Zweifel False: bei ungespeicherten
// Aenderungen fragt die IDE selbst, "Abbrechen" liefert False und der
// Sprung unterbleibt - nichts vom Nutzer wird ungefragt verworfen, nichts
// ungefragt geschrieben.
// Gemessen 2026-11-13: "geaendert" ist eine Unit auch OHNE Zutun des
// Nutzers, wenn die IDE fehlende Units des Formulars in die uses-Klausel
// eintraegt (ShowcaseDemo\uOrderForm: FireDAC.Phys.PG) - auf dem False-Weg
// fragt sie dann bei jedem Schliessen. Und: ofnFileClosing feuert auf
// beiden Wegen, die Abraeum-Haken von Highlighter und Watch-Mode laufen
// also wie beim Schliessen von Hand.
//
// Refcount: waehrend CloseModule darf niemand einen Editor, Puffer oder
// eine Ansicht des Moduls halten, sonst meldet die IDE "Der Referenzzaehler
// von Instanz von Klasse TEditSource zeigt die Anzahl 1". Diese Routine
// haelt nur das Modul; alles, was Editoren anfasst (TraceState,
// ModuleCloseDecision, IsModuleOpen), steht in eigenen Routinen, deren
// Interface-Temporaere beim Ruecksprung frei sind. Dasselbe gilt fuer jeden
// Aufrufer bis zum Klick.
var
  ModSvc : IOTAModuleServices;
  Module : IOTAModule;
  Force  : Boolean;
  Closed : Boolean;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then
    Exit(False);
  Module := ModSvc.FindModule(AFileName);
  if not Assigned(Module) then Exit(True);
  TraceState('close: vor', AFileName);
  Force  := ModuleCloseDecision(AFileName) = mcdForce;
  Closed := Module.CloseModule(Force);
  Module := nil;
  Result := Closed and not IsModuleOpen(AFileName);
  NavTrace(Format('close: %s CloseModule=%s geschlossen=%s',
    [ExtractFileName(AFileName), BoolToStr(Closed, True),
     BoolToStr(Result, True)]));
end;

function OpenDfmAsText(const ADfmPath: string): Boolean;
// Die IDE laedt eine .dfm nur dann als TEXT, wenn ihr Form-Modul nicht
// offen ist (gemessen 2026-11-13; bei offenem Modul liefert OpenFile den
// Designer). Also: Form-Modul schliessen, DFM oeffnen, Ergebnis am Zustand
// pruefen. FindModule(.dfm) liefert das Form-Modul; die Unit wird
// zusaetzlich unter ihrem eigenen Namen geschlossen, falls sie ohne
// geladenes Formular offen ist.
// "Ansicht als Text" (IOTAEditActions.SwapSourceFormView) ist KEIN Ersatz,
// ebenfalls gemessen: es greift nur aus der Designer-Ansicht und erst
// asynchron, und es zeigt die vom Designer NEU serialisierte DFM - mit
// anderen Zeilen als die Datei, auf die sich die Fundzeile bezieht
// (uOrderForm: ExplicitTop/ExplicitWidth kamen hinzu), und das Formular
// gilt danach als geaendert.
var
  ActSvc : IOTAActionServices;
  Opened : Boolean;
begin
  Result := False;
  if not CloseModuleOf(ADfmPath) then Exit;
  if not CloseModuleOf(ChangeFileExt(ADfmPath, '.pas')) then Exit;
  Opened := Supports(BorlandIDEServices, IOTAActionServices, ActSvc)
    and ActSvc.OpenFile(ADfmPath);
  TraceState('dfm: OpenFile=' + BoolToStr(Opened, True), ADfmPath);
  Result := HasDfmTextEditor(ADfmPath);
  if not Result then
    DfmNavLog('die IDE fuehrt die DFM nach OpenFile nicht als Text: ' + ADfmPath);
end;

function ShowDfmText(const ADfmPath: string; ALine: Integer): Boolean;
// Bringt den DFM-Texteditor nach vorn und setzt den Caret. True NUR, wenn
// danach die oberste Ansicht nachweislich die DFM zeigt - die Aufrufer
// zentrieren ueber die oberste Ansicht (CenterCurrentViewOnLine).
var
  ModSvc    : IOTAModuleServices;
  EditorSvc : IOTAEditorServices;
  Editor    : IOTASourceEditor;
  View      : IOTAEditView;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  Editor := DfmTextEditorOf(ModSvc.FindModule(ADfmPath));
  if not Assigned(Editor) then Exit;
  Editor.Show;
  View := EditorSvc.TopView;
  if not ViewShowsFile(View, ADfmPath) then
  begin
    DfmNavLog('oberste Ansicht zeigt nicht die DFM: ' + ADfmPath);
    Exit;
  end;
  Result := (ALine <= 0) or PlaceCaretInView(View, ALine);
end;

function DfmTextAtLine(const ADfmPath: string; ALine: Integer): Boolean;
// Zustandsbasiert: steht die DFM schon als Text bereit, wird sie nur
// gezeigt - nichts wird geschlossen. Sonst Form-Modul schliessen und die
// DFM als Text oeffnen (OpenDfmAsText).
begin
  Result := False;
  TraceState(Format('dfm: Start Zeile %d', [ALine]), ADfmPath);
  if HasDfmTextEditor(ADfmPath) or OpenDfmAsText(ADfmPath) then
    Result := ShowDfmText(ADfmPath, ALine);
  TraceState('dfm: Ende ok=' + BoolToStr(Result, True), ADfmPath);
end;

function UnitAtLine(const AbsPath: string; ALine: Integer): Boolean;
// Oeffnet eine Nicht-DFM-Datei und setzt den Caret; ALine <= 0: nur
// oeffnen (False). Steht die DFM einer .pas noch als freistehender Text
// offen (von einem DFM-Sprung), wird die zuerst geschlossen - sonst traefe
// das Form-Modul beim Oeffnen auf den offenen Text-Puffer seiner eigenen
// DFM. Lehnt der Nutzer das Schliessen ab, unterbleibt der Sprung.
//
// SrcEditor.Show ist der Aufruf, in dem die IDE eine Unit von sich aus
// aendert (uses-Eintraege zum Formular, gemessen 2026-11-13). Trug der
// Puffer unmittelbar davor nichts Ungespeichertes, wird der Stand danach
// als Vergleichsstand festgehalten - so erkennt CloseModuleOf spaeter, dass
// seither niemand getippt hat (s. "Vergleichsstand" oben).
var
  DfmPath   : string;
  WasOpen   : Boolean;
  WasClean  : Boolean;
  SrcEditor : IOTASourceEditor;
begin
  Result := False;
  if SameText(ExtractFileExt(AbsPath), '.pas') then
  begin
    DfmPath := ChangeFileExt(AbsPath, '.dfm');
    if IsStandaloneDfmText(DfmPath) and not CloseModuleOf(DfmPath) then Exit;
  end;
  WasOpen   := IsModuleOpen(AbsPath);
  SrcEditor := FirstSourceEditorOf(FindOrOpenModule(AbsPath));
  if not Assigned(SrcEditor) or (ALine <= 0) then Exit;
  WasClean := not WasOpen or HoldsNothingUnsaved(SrcEditor);
  SrcEditor.Show;   // Tab nach vorne bringen
  Result := PlaceCaret(SrcEditor, ALine);
  if WasClean then
    RememberBaseline(SrcEditor);
end;

var
  // Eine Navigation laeuft: die Rueckfrage der IDE beim Schliessen ist
  // modal, ein Timer-Tick einer Fundliste kaeme sonst mitten hinein.
  GNavBusy : Boolean = False;

function EnterNav(const AbsPath: string): Boolean;
begin
  Result := not GNavBusy;
  if Result then
    GNavBusy := True
  else
    NavTrace('nav: uebersprungen, eine Navigation laeuft noch: '
      + ExtractFileName(AbsPath));
end;

class function TIDEEditor.TryGetCurrentPasFile(out APath: string): TCurrentFileResult;
var
  EditorSvc : IOTAEditorServices;
  EditView  : IOTAEditView;
  Path      : string;
  AsPas     : string;
begin
  APath := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then
    Exit(cfrNoEditorService);
  EditView := EditorSvc.TopView;
  if not Assigned(EditView) or not Assigned(EditView.Buffer) then
    Exit(cfrNoOpenView);
  Path := EditView.Buffer.FileName;
  if Path = '' then Exit(cfrNotPascalFile);

  if Path.EndsWith('.pas', True) then
  begin
    APath  := Path;
    Result := cfrOK;
    Exit;
  end;

  // Bei einer .dfm-Datei auf die zugehoerige .pas umleiten, falls sie im
  // gleichen Ordner existiert. Der Analyse-Runner sucht die .dfm dann
  // selbst wieder ueber TPath.ChangeExtension.
  //
  // A6/C10-INVENTUR-ABSCHLUSS (2026-09-18, autonom entschieden):
  // BEWUSST delphi-only. Das Plugin laeuft in der Delphi-IDE und
  // scannt deren AKTIVES Projekt - dlFpc-Funde (.lfm/.pp) entstehen
  // auf diesem Pfad nie; eine .lfm-Weiche hier waere toter Code.
  // Gleiches gilt fuer uIDEAnalyserForm (SafeClose-Designer-Schutz -
  // .lfm oeffnet keinen Delphi-Designer) und uIDEWatchMode
  // (CompanionOf). Damit sind alle 16 Stellen der A4-Paarungs-
  // Inventur behandelt: 12 Engine (A4/A5), 2 Form-UI (C9), 2 IDE
  // (dieser Entscheid).
  if Path.EndsWith('.dfm', True) then
  begin
    AsPas := TPath.ChangeExtension(Path, '.pas');
    if TFile.Exists(AsPas) then
    begin
      APath  := AsPas;
      Result := cfrOK;
      Exit;
    end;
  end;

  Result := cfrNotPascalFile;
end;

class function TIDEEditor.ViewFileAndLine(const AView: IOTAEditView;
  out AFile: string; out ALine: Integer): Boolean;
begin
  AFile  := '';
  ALine  := 0;
  Result := False;
  if not Assigned(AView) or not Assigned(AView.Buffer) then Exit;
  AFile := AView.Buffer.FileName;
  ALine := AView.CursorPos.Line;
  Result := (AFile <> '') and (ALine >= 1);
end;

class function TIDEEditor.TopViewFileAndLine(out AFile: string;
  out ALine: Integer): Boolean;
var
  EditorSvc : IOTAEditorServices;
begin
  AFile  := '';
  ALine  := 0;
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  Result := ViewFileAndLine(EditorSvc.TopView, AFile, ALine);
end;

procedure CtxLog(const AFormat: string; const AArgs: array of const);
// Messkanal von ViewContext (DebugView, Praefix 'SCA: ctx') - Rohwerte und
// Umrechnung fuer den UI-Test; eine Meldung im Editor waere lauter als der
// Nutzen. Nur im DEBUG-Bau (Konfiguration Debug des Plugin-Projekts, wie
// der Detector-Review-Filter in uIDEAnalyserForm): eine MESSUNG, keine
// Fehlerdiagnose - die bleibt immer sichtbar (uUiElementRegistry). Im
// Release-Bau ein leerer Aufruf (Review Charge B, Befund 3).
begin
  {$IFDEF DEBUG}
  // noinspection DebugOutput
  OutputDebugString(PChar('SCA: ctx ' + Format(AFormat, AArgs)));
  {$ENDIF}
end;

function BlockStyleOf(AStyle: TOTABlockType): TEditorBlockStyle;
// ToolsAPI-Blockart -> Spiegel in uEditorContextModel (gleiche Reihenfolge,
// aber per case - keine Ord-Gleichheit vorausgesetzt).
begin
  case AStyle of
    btInclusive    : Result := ebsInclusive;
    btLine         : Result := ebsLine;
    btColumn       : Result := ebsColumn;
    btNonInclusive : Result := ebsNonInclusive;
  else
    Result := ebsUnknown;
  end;
end;

function CharColAt(const AView: IOTAEditView; ALine, ADisplayCol: Integer): Integer;
// Anzeige-Spalte (TOTAEditPos.Col, Tabs expandiert) -> Zeichen-Spalte
// (1-basiert) ueber die IDE selbst: ConvertPos(True, ...) liefert
// TOTACharPos.CharIndex in ZEICHEN der Zeile (Rueckrichtung von reDelphix
// uRdxEditor.DisplayPosOf). TOTAEditPos.Col ist SmallInt - ein Block-Wert
// ausserhalb wird vorher gekappt (sonst ERangeError unter $R+).
var
  EP : TOTAEditPos;
  CP : TOTACharPos;
begin
  if ADisplayCol < 1 then
    ADisplayCol := 1
  else if ADisplayCol > High(SmallInt) then
    ADisplayCol := High(SmallInt);
  EP.Line      := ALine;
  EP.Col       := ADisplayCol;
  CP.Line      := ALine;
  CP.CharIndex := 0;
  AView.ConvertPos(True, EP, CP);
  Result := CharColOfIndex(CP.CharIndex);
end;

class function TIDEEditor.ViewContext(const AView: IOTAEditView;
  out ACtx: TEditorContext): Boolean;
var
  FileName : string;
  Line     : Integer;
  Caret    : TOTAEditPos;
  Block    : IOTAEditBlock;
  Raw      : TEditorBlockChars;
  {$IFDEF DEBUG}
  Buf      : IOTAEditBuffer;
  {$ENDIF}
begin
  ACtx   := Default(TEditorContext);
  Result := False;
  if not ViewFileAndLine(AView, FileName, Line) then Exit;
  Caret := AView.CursorPos;
  ACtx  := TEditorContext.At(FileName, Line, CharColAt(AView, Line, Caret.Col));
  CtxLog('caret %d:%d (display) -> char col %d', [Caret.Line, Caret.Col, ACtx.Col]);
  Block := AView.Block;
  if Assigned(Block) and Block.IsValid and Block.Visible and (Block.Size > 0) then
  begin
    Raw.Style     := BlockStyleOf(Block.Style);
    Raw.StartLine := Block.StartingRow;
    Raw.StartCol  := CharColAt(AView, Block.StartingRow, Block.StartingColumn);
    Raw.EndLine   := Block.EndingRow;
    Raw.EndCol    := CharColAt(AView, Block.EndingRow, Block.EndingColumn);
    ApplyEditorBlock(ACtx, Raw);
    // Messung (UI-Test) nur im DEBUG-Bau - auch die Lesezugriffe dafuer.
    {$IFDEF DEBUG}
    CtxLog('block style=%d size=%d '
      + 'display %d:%d..%d:%d -> chars %d:%d..%d:%d -> sel=%s %d:%d..%d:%d',
      [Ord(Block.Style), Block.Size,
       Block.StartingRow, Block.StartingColumn,
       Block.EndingRow, Block.EndingColumn,
       Raw.StartLine, Raw.StartCol, Raw.EndLine, Raw.EndCol,
       BoolToStr(ACtx.HasSelection, True),
       ACtx.SelStartLine, ACtx.SelStartCol, ACtx.SelEndLine, ACtx.SelEndCol]);
    // Nur Messung (nicht benutzt): die Blockgrenzen des Puffers als
    // TOTACharPos - ob deren CharIndex Zeichen oder Bytes zaehlt, ist
    // ungemessen (memory: SyncEditBlock liest das Blockende als Bytes).
    Buf := AView.Buffer;
    if Assigned(Buf) then
      CtxLog('buffer block start %d:%d after %d:%d (raw CharIndex)',
        [Buf.BlockStart.Line, Buf.BlockStart.CharIndex,
         Buf.BlockAfter.Line, Buf.BlockAfter.CharIndex]);
    {$ENDIF}
  end;
  Result := True;
end;

class function TIDEEditor.TopViewContext(out ACtx: TEditorContext): Boolean;
var
  EditorSvc : IOTAEditorServices;
begin
  ACtx   := Default(TEditorContext);
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  Result := ViewContext(EditorSvc.TopView, ACtx);
end;

class function TIDEEditor.GetCurrentProjectDir: string;
var
  ModSvc    : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  ProjGroup := ModSvc.MainProjectGroup;
  if Assigned(ProjGroup) then
    Result := ExcludeTrailingPathDelimiter(
      ExtractFilePath(ProjGroup.FileName));
end;

class function TIDEEditor.OpenFileAtLine(const AbsPath: string;
  LineNumber: Integer): TOpenFileMode;
begin
  Result := ofmRegular;
  if not EnterNav(AbsPath) then Exit;
  try
    if not IsDfmFile(AbsPath) then
      UnitAtLine(AbsPath, LineNumber)
    else if DfmTextAtLine(AbsPath, LineNumber) then
      Result := ofmDfmAsText;
  finally
    GNavBusy := False;
  end;
end;

class function TIDEEditor.ShowDfmAsTextAtLine(const AbsPath: string;
  LineNumber: Integer): Boolean;
begin
  Result := False;
  if not IsDfmFile(AbsPath) or not EnterNav(AbsPath) then Exit;
  try
    Result := DfmTextAtLine(AbsPath, LineNumber);
  finally
    GNavBusy := False;
  end;
end;

class function TIDEEditor.ShowFileAtLine(const AbsPath: string;
  LineNumber: Integer): Boolean;
begin
  Result := False;
  if (AbsPath = '') or (LineNumber <= 0) or not EnterNav(AbsPath) then Exit;
  try
    if IsDfmFile(AbsPath) then
      Result := DfmTextAtLine(AbsPath, LineNumber)
    else
      Result := UnitAtLine(AbsPath, LineNumber);
  finally
    GNavBusy := False;
  end;
end;

class function TIDEEditor.ShowFileCenteredAtLine(const AbsPath: string;
  LineNumber: Integer): Boolean;
begin
  Result := ShowFileAtLine(AbsPath, LineNumber);
  if Result then
    CenterCurrentViewOnLine(LineNumber);
end;

class procedure TIDEEditor.CenterCurrentViewOnLine(LineNumber: Integer);
const
  // Fallback wenn BottomRow/TopRow keine plausible Editor-Hoehe liefern
  // (z.B. View noch nicht gepaintet, IDE-Layout-Edge-Case). 24 entspricht
  // einer typischen Code-Editor-Hoehe; Half = 12 platziert die Zielzeile
  // ungefaehr in der vertikalen Mitte.
  FALLBACK_HALF_ROWS = 12;
var
  EditorSvc : IOTAEditorServices;
  EditView  : IOTAEditView;
  EditPos   : TOTAEditPos;
  Visible   : Integer;
  TopTarget : Integer;
begin
  if LineNumber <= 0 then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  EditView := EditorSvc.TopView;
  if not Assigned(EditView) then Exit;

  // Cursor auf Zielzeile setzen (sichtbarer Caret + Edit-Hooks reagieren).
  EditPos.Col  := 1;
  EditPos.Line := LineNumber;
  EditView.CursorPos := EditPos;

  // Sichtbare Zeilen ausrechnen. BottomRow-TopRow+1 ist die Editor-Hoehe in
  // Zeilen. Bei nicht-plausiblen Werten (Edge-Case beim ersten Paint) auf
  // FALLBACK_HALF_ROWS*2 zurueckfallen.
  Visible := EditView.BottomRow - EditView.TopRow + 1;
  if Visible < 4 then
    Visible := FALLBACK_HALF_ROWS * 2;

  TopTarget := LineNumber - (Visible div 2);
  if TopTarget < 1 then TopTarget := 1;
  EditView.SetTopLeft(TopTarget, 1);
  EditView.Paint;
end;

function TryGetEditPosition(const AbsPath: string;
  out AEditPos: IOTAEditPosition): Boolean;
// Loest einen Dateipfad zur Cursor-API des IDE-Editors auf:
//   Modul finden (oder oeffnen) -> Source-Editor -> EditView -> Buffer
//   -> EditPosition
//
// Einziger Aufrufer ist seit 2026-10-10 InsertLineAbove (der zweite,
// ApplyLineReplacement fuer den alten uQuickFix-Weg, entfiel - Ctrl+Alt+F
// laeuft ueber die Anbieter-Registry). Die Routine bleibt eigenstaendig,
// weil sie der EINE Ort ist, an dem das Plugin einen Pfad in eine
// Schreibposition des Puffers uebersetzt: Modulwahl, Editorwahl und
// View-Wahl stehen hier, nicht im Schreiber.
//
// Der Source-Editor wird ueber die ModuleFileEditors gesucht und nicht
// ueber Index 0: ein Form-Modul liefert dort auch den DFM-Editor, und
// nur der erste IOTASourceEditor ist der Pascal-Quelltext.
//
// Bekannte Enge, bewusst uebernommen statt hier still geaendert:
// EditViews[0] ist nicht zwingend der AKTIVE View. Bei geteiltem Fenster
// editiert der Nutzer moeglicherweise in einem anderen. Es zu aendern ist
// eine Verhaltensfrage und gehoert in einen eigenen Schritt.
var
  ModSvc     : IOTAModuleServices;
  Module     : IOTAModule;
  SourceEdit : IOTASourceEditor;
  EditView   : IOTAEditView;
  EditBuffer : IOTAEditBuffer;
begin
  Result   := False;
  AEditPos := nil;
  if AbsPath = '' then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;

  Module := ModSvc.FindModule(AbsPath);
  if Module = nil then
  begin
    try
      Module := ModSvc.OpenModule(AbsPath);
    except
      on EStackExhausted do raise;
      on EAbort do raise;
      // noinspection ExceptionTooGeneral
      // Die IDE konnte das Modul nicht oeffnen (Datei weg, gesperrt,
      // fremder Dateityp - die OTA wirft dafuer keine eigene Klasse): fuer
      // den Aufrufer ist das "nicht schreibbar", er meldet es in der
      // Statuszeile; eine IDE-Meldung waere lauter als der Schaden.
      on Exception do Exit;
    end;
  end;
  if Module = nil then Exit;

  SourceEdit := FirstSourceEditorOf(Module);
  if SourceEdit = nil then Exit;
  if SourceEdit.EditViewCount = 0 then Exit;

  EditView := SourceEdit.EditViews[0];
  if EditView = nil then Exit;
  EditBuffer := EditView.Buffer;
  if EditBuffer = nil then Exit;
  AEditPos := EditBuffer.EditPosition;
  Result := AEditPos <> nil;
end;

function BufferLineBreakAt(const AEditPos: IOTAEditPosition): string;
// Zeilenende des Puffers an der Zeile der Position: Read hinter dem
// Zeilenende liefert die Umbruchzeichen selbst (CRLF, LF, CR). Keine
// (letzte Zeile ohne Umbruch) oder etwas anderes: sLineBreak wie bisher.
// Verschiebt die Position ans Zeilenende - der Aufrufer setzt sie neu.
var
  Tail : string;
begin
  Result := sLineBreak;
  AEditPos.MoveEOL;
  Tail := AEditPos.Read(2);
  if Tail.StartsWith(#13#10) then
    Result := #13#10
  else if (Tail <> '') and (Tail[1] = #10) then
    Result := #10
  else if (Tail <> '') and (Tail[1] = #13) then
    Result := #13;
end;

class function TIDEEditor.InsertLineAbove(const AbsPath: string;
  LineNumber: Integer; const NewLine: string): Boolean;
// Strategie:
//   1. Modul / Source-Editor ueber TryGetEditPosition
//   2. EditPosition.GotoLine(LineNumber); MoveBOL;
//   3. Read(MaxIndent) -> Einrueckungs-String der Befund-Zeile lesen
//   4. MoveEOL; Read(2) -> das Zeilenende des Puffers an dieser Zeile
//   5. EditPosition.GotoLine(LineNumber); MoveBOL; (zurueck nach Read)
//   6. InsertText(Indent + NewLine + Zeilenende);
//
// `Indent + NewLine` wird VOR der bestehenden Zeile eingefuegt - die
// alte Zeile rutscht eins runter. Ctrl+Z reverts.
const
  MAX_INDENT_LEN = 32; // 32 Leerzeichen Einrueckung sind schon viel.
var
  EditPos     : IOTAEditPosition;
  j           : Integer;
  LineHead    : string;
  Indent      : string;
  LineBreak   : string;
begin
  Result := False;
  if (LineNumber <= 0) or (AbsPath = '') or (NewLine = '') then Exit;
  // Schritt 1 der Strategie oben (TryGetEditPosition).
  if not TryGetEditPosition(AbsPath, EditPos) then Exit;

  try
    // Einrueckung der Befund-Zeile auslesen.
    EditPos.GotoLine(LineNumber);
    EditPos.MoveBOL;
    LineHead := EditPos.Read(MAX_INDENT_LEN);
    Indent := '';
    for j := 1 to Length(LineHead) do
      if CharInSet(LineHead[j], [' ', #9]) then
        Indent := Indent + LineHead[j]
      else
        Break;

    // Zeilenende des Puffers an dieser Zeile (steht noch am Zeilenanfang).
    LineBreak := BufferLineBreakAt(EditPos);

    // Cursor zurueck an Zeilen-Anfang + neue Zeile davor einfuegen.
    EditPos.GotoLine(LineNumber);
    EditPos.MoveBOL;
    EditPos.InsertText(Indent + NewLine + LineBreak);
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Die Puffer-API wirft bei einer Zeile hinter dem Ende, einem
    // schreibgeschuetzten Puffer oder einem Modul im Abbau - ohne eigene
    // Klasse dafuer: nicht geschrieben, der Aufrufer meldet es in der
    // Statuszeile.
    on Exception do Exit;
  end;

  Result := True;
end;

class procedure TIDEEditor.NoteFileClosing(const AFileName: string);
begin
  ForgetBaseline(AFileName);
end;

initialization

finalization
  FreeAndNil(GNavBaselines);

end.
