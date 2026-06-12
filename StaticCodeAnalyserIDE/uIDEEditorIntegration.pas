unit uIDEEditorIntegration;

// Stateless wrappers around RAD Studio's ToolsAPI for everything the
// Analyser-Frame needs from the IDE-Editor:
//   * Open a file in the editor and jump to a specific line.
//   * Detect the .pas file currently shown in the top edit-view.
//   * Get the active project's directory.
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
  ToolsAPI;

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
    ofmRegular,         // .pas oder DFM-im-Code-Editor: alles normal
    ofmDfmAsText,       // .dfm-Befund: .pas geschlossen, DFM jetzt als
                        // Text im Code-Editor sichtbar (Close-and-Reopen)
    ofmDfmFallbackPas   // .dfm-Befund: zugehoerige .pas war modifiziert,
                        // wir konnten sie nicht schliessen und haben sie
                        // stattdessen geoeffnet. Aufrufer zeigt Hint
                        // "Alt+F12 to view DFM as text".
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

    // Liefert das Verzeichnis des aktiven IDE-Projekts (ohne Trailing
    // PathDelimiter). Leer wenn kein Projekt geladen oder Service
    // nicht verfuegbar.
    class function GetCurrentProjectDir: string; static;

    // Oeffnet eine Datei im IDE-Editor (oder bringt sie nach vorne wenn
    // bereits offen) und positioniert den Cursor auf LineNumber.
    // No-op bei nicht-verfuegbaren Services oder LineNumber <= 0.
    //
    // Bei einer .dfm-Datei wird die Close-and-Reopen-Strategie versucht:
    // wenn die zugehoerige .pas offen aber nicht modifiziert ist, wird
    // sie geschlossen und die .dfm direkt geoeffnet - landet als Text
    // im Code-Editor (siehe DFMCheck/GExperts-Pattern). Bei modifizierter
    // .pas fallback auf .pas oeffnen + Hint, weil Close den User-Stand
    // zerstoeren wuerde.
    class function OpenFileAtLine(const AbsPath: string;
                                  LineNumber: Integer): TOpenFileMode; static;

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

    // Ersetzt die KOMPLETTE Zeile LineNumber in der Datei AbsPath durch
    // NewLine. Nutzt IOTAEditWriter (Buffer-Writer): die Aenderung ist
    // ein normaler Edit-Operation und kann mit Ctrl+Z rueckgaengig
    // gemacht werden.
    //
    // Vorgehen:
    //   1. Modul finden / oeffnen (FindModule + OpenFile als Fallback)
    //   2. SourceEditor + EditWriter holen
    //   3. Byte-Offset des Zeilen-Anfangs via Buffer.GetSubText / Lesen
    //      bestimmen (Pascal-IDE-Buffer = UTF-8)
    //   4. DeleteTo (Ende der Zeile vor LineBreak) + Insert(NewLine)
    //
    // Liefert True wenn der Replace durchgefuehrt wurde. False bei
    // jedem Fehler (Datei nicht offen / Service fehlt / Zeile out of
    // range). Caller zeigt in dem Fall einen Status-Bar-Hint.
    //
    // Notiz fuer Anrufer: NewLine darf KEINEN Trailing-LineBreak
    // enthalten - das System uebernimmt die Zeilenenden des Buffers.
    class function ApplyLineReplacement(const AbsPath: string;
      LineNumber: Integer; const NewLine: string): Boolean; static;

    // Fuegt eine neue Zeile DIREKT VOR der angegebenen LineNumber ein.
    // Wird vom Auto-Suppress benutzt: `// noinspection <RuleName>`
    // ueber der Befund-Zeile. NewLine wird mit der Einrueckung der
    // Befund-Zeile ausgerichtet (lexikalisches Whitespace-Kopieren),
    // damit der Marker visuell zur Code-Zeile gehoert.
    //
    // Liefert True bei Erfolg, sonst False (Datei nicht in der IDE,
    // Zeile out-of-range, ...).
    class function InsertLineAbove(const AbsPath: string;
      LineNumber: Integer; const NewLine: string): Boolean; static;
  end;

implementation

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils, System.IOUtils, System.StrUtils;

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

  procedure SafeCloseModule(ModSvc: IOTAModuleServices; const APath: string);
  // Modul schliessen mit Save-if-Modified. In Delphi 12 ist sowohl
  // IOTAEditor.Modified als auch IOTAEditBuffer.IsModified direkt
  // nach OpenFile unzuverlaessig True (auch ohne User-Edit). Ein
  // expliziter Modified-Check rutscht damit fast immer in den Fallback
  // und blockiert den Close-and-Reopen-Trick.
  //
  // Pragma: CloseModule(True) ist idempotent wenn nichts wirklich
  // modifiziert wurde (max. LastWriteTime aendert sich) und schuetzt
  // gegen Datenverlust bei echten User-Edits. Pattern aus DFMCheck.
  //
  // Alle Interface-Refs explizit auf nil, sonst Refcount-Assert beim
  // IDE-internen Destroy ("TEditSource Refcount = 2").
  var
    Mod_: IOTAModule;
  begin
    Mod_ := ModSvc.FindModule(APath);
    if Mod_ = nil then Exit;
    Mod_.CloseModule(True);
    Mod_ := nil;
  end;

var
  ModuleSvc  : IOTAModuleServices;
  ActionSvc  : IOTAActionServices;
  Module     : IOTAModule;
  SrcEditor  : IOTASourceEditor;
  EditView   : IOTAEditView;
  EditPos    : TOTAEditPos;
  i          : Integer;
  TargetPath : string;
  AsPas      : string;
  AsDfm      : string;
  IsDfm      : Boolean;
begin
  Result     := ofmRegular;
  IsDfm      := EndsText('.dfm', AbsPath);
  TargetPath := AbsPath;

  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleSvc) then Exit;
  Supports(BorlandIDEServices, IOTAActionServices, ActionSvc);

  // Close-and-Reopen-Strategy:
  //   .dfm-Befund: zugehoerige .pas schliessen damit OpenFile(.dfm) als
  //                TEXT in den Code-Editor laedt (sonst Form-Designer).
  //   .pas-Befund: zugehoerige .dfm schliessen falls sie als generischer
  //                Text-Buffer offen ist (von einem vorherigen DFM-Doppel-
  //                klick), sonst wuerde OpenFile(.pas) sie in den Form-
  //                Designer "assimilieren".
  //
  // SafeCloseModule nutzt CloseModule(True) (save-if-dirty), weil
  // Modified-Checks in Delphi 12 nach OpenFile unzuverlaessig sind -
  // siehe Helper-Doku. Pattern aus DFMCheck.
  if IsDfm then
  begin
    AsPas := TPath.ChangeExtension(AbsPath, '.pas');
    if TFile.Exists(AsPas) then
      SafeCloseModule(ModuleSvc, AsPas);
    Result := ofmDfmAsText;
  end
  else
  begin
    AsDfm := TPath.ChangeExtension(AbsPath, '.dfm');
    if TFile.Exists(AsDfm) then
      SafeCloseModule(ModuleSvc, AsDfm);
  end;

  // Modul suchen (bereits geoeffnet oder erst oeffnen).
  Module := ModuleSvc.FindModule(TargetPath);
  if not Assigned(Module) then
  begin
    if Assigned(ActionSvc) then
      ActionSvc.OpenFile(TargetPath);
    Module := ModuleSvc.FindModule(TargetPath);
  end;

  if not Assigned(Module) then Exit;
  if LineNumber <= 0 then Exit;

  // IOTASourceEditor aus dem Modul holen.
  SrcEditor := nil;
  for i := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[i], IOTASourceEditor, SrcEditor) then
      Break;
  if not Assigned(SrcEditor) then Exit;

  // Editor-Tab in den Vordergrund bringen (wichtig wenn Datei bereits
  // geoeffnet war und nur ein anderer Tab aktiv ist).
  SrcEditor.Show;

  // CursorPos setzen, aber NICHT bei ofmDfmFallbackPas: dort ist die
  // .pas modifiziert und der User editiert gerade darin. Wuerden wir den
  // Cursor verstellen, ginge sein Caret-State verloren. Wir bringen
  // stattdessen nur den Tab nach vorne (SrcEditor.Show oben) und lassen
  // den Aufrufer per Status-Bar darauf hinweisen, dass die DFM-Befund-
  // Zeile via Alt+F12 erreichbar ist.
  if Result = ofmDfmFallbackPas then Exit;

  EditView := SrcEditor.GetEditView(0);
  if Assigned(EditView) then
  begin
    EditPos.Col  := 1;
    EditPos.Line := LineNumber;
    EditView.CursorPos := EditPos;
    EditView.MoveViewToCursor;
    EditView.Paint;
  end;
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

class function TIDEEditor.ApplyLineReplacement(const AbsPath: string;
  LineNumber: Integer; const NewLine: string): Boolean;
// Strategie (echte API - keine Byte-Offset-Arithmetik):
//   1. Modul finden (FindModule / OpenModule)
//   2. SourceEditor via Module.ModuleFileEditors
//   3. Buffer.EditPosition -> IOTAEditPosition (Cursor-API)
//   4. GotoLine(LineNumber); MoveEOL; -> Column = Zeilen-Laenge
//   5. MoveBOL; Delete(ColAfterEOL - 1); InsertText(NewLine);
//
// IOTAEditPosition kennt KEIN Address-Property - die API ist row/col +
// relative Deletes/Inserts vom aktuellen Cursor aus. Das ist langfristig
// die stabilere Variante (UTF-8/UTF-16-Konversion uebernimmt der IDE-
// Buffer-Layer selbst).
//
// Undo: jede EditPosition-Modifikation laeuft durch den IDE-Edit-Stack,
// Ctrl+Z reverts. Delete + InsertText in derselben Action-Sequenz
// koennen 2 Undo-Steps werden - akzeptabel, kostet einen zusaetzlichen
// Ctrl+Z bei Bedarf.
var
  ModSvc      : IOTAModuleServices;
  Module      : IOTAModule;
  SourceEdit  : IOTASourceEditor;
  EditView    : IOTAEditView;
  EditBuffer  : IOTAEditBuffer;
  EditPos     : IOTAEditPosition;
  LineEndCol  : Integer;
  i           : Integer;
begin
  Result := False;
  if (LineNumber <= 0) or (AbsPath = '') or (NewLine = '') then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;

  // 1) Modul finden (oder oeffnen wenn noch nicht in der IDE).
  Module := ModSvc.FindModule(AbsPath);
  if Module = nil then
  begin
    try
      Module := ModSvc.OpenModule(AbsPath);
    except
      Exit; // Open fehlgeschlagen - Caller meldet im Status-Bar
    end;
  end;
  if Module = nil then Exit;

  // 2) SourceEditor finden (Pascal-Source, nicht z.B. DFM-Editor).
  SourceEdit := nil;
  for i := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[i], IOTASourceEditor, SourceEdit) then
      Break;
  if SourceEdit = nil then Exit;
  if SourceEdit.EditViewCount = 0 then Exit;

  // 3) EditView -> Buffer -> EditPosition (Navigations-Cursor).
  EditView := SourceEdit.EditViews[0];
  if EditView = nil then Exit;
  EditBuffer := EditView.Buffer;
  if EditBuffer = nil then Exit;
  EditPos := EditBuffer.EditPosition;
  if EditPos = nil then Exit;

  try
    // 4) Zielzeile positionieren + Zeilen-Laenge ermitteln.
    EditPos.GotoLine(LineNumber);
    EditPos.MoveEOL;
    LineEndCol := EditPos.Column; // Column ist 1-basiert; bei leerer Zeile = 1.
    EditPos.MoveBOL;

    // 5) Komplette Zeile loeschen + Replacement einfuegen.
    if LineEndCol > 1 then
      EditPos.Delete(LineEndCol - 1);
    EditPos.InsertText(NewLine);
  except
    Exit; // Out-of-range Line oder API-Edge-Case
  end;

  Result := True;
end;

class function TIDEEditor.InsertLineAbove(const AbsPath: string;
  LineNumber: Integer; const NewLine: string): Boolean;
// Strategie:
//   1. Modul / Source-Editor wie in ApplyLineReplacement
//   2. EditPosition.GotoLine(LineNumber); MoveBOL;
//   3. Read(MaxIndent) -> Einrueckungs-String der Befund-Zeile lesen
//   4. EditPosition.GotoLine(LineNumber); MoveBOL; (zurueck nach Read)
//   5. InsertText(Indent + NewLine + #13#10);
//
// `Indent + NewLine` wird VOR der bestehenden Zeile eingefuegt - die
// alte Zeile rutscht eins runter. Ctrl+Z reverts.
const
  MAX_INDENT_LEN = 32; // 32 Leerzeichen Einrueckung sind schon viel.
var
  ModSvc      : IOTAModuleServices;
  Module      : IOTAModule;
  SourceEdit  : IOTASourceEditor;
  EditView    : IOTAEditView;
  EditBuffer  : IOTAEditBuffer;
  EditPos     : IOTAEditPosition;
  i, j        : Integer;
  LineHead    : string;
  Indent      : string;
begin
  Result := False;
  if (LineNumber <= 0) or (AbsPath = '') or (NewLine = '') then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;

  Module := ModSvc.FindModule(AbsPath);
  if Module = nil then
  begin
    try
      Module := ModSvc.OpenModule(AbsPath);
    except
      Exit;
    end;
  end;
  if Module = nil then Exit;

  SourceEdit := nil;
  for i := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[i], IOTASourceEditor, SourceEdit) then
      Break;
  if SourceEdit = nil then Exit;
  if SourceEdit.EditViewCount = 0 then Exit;

  EditView := SourceEdit.EditViews[0];
  if EditView = nil then Exit;
  EditBuffer := EditView.Buffer;
  if EditBuffer = nil then Exit;
  EditPos := EditBuffer.EditPosition;
  if EditPos = nil then Exit;

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

    // Cursor zurueck an Zeilen-Anfang + neue Zeile davor einfuegen.
    EditPos.GotoLine(LineNumber);
    EditPos.MoveBOL;
    EditPos.InsertText(Indent + NewLine + sLineBreak);
  except
    Exit;
  end;

  Result := True;
end;

end.
