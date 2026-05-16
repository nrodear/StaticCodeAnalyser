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
  end;

implementation

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

end.
