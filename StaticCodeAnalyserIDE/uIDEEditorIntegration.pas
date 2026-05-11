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
    class procedure OpenFileAtLine(const AbsPath: string;
                                   LineNumber: Integer); static;
  end;

implementation

uses
  System.SysUtils, System.IOUtils;

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

class procedure TIDEEditor.OpenFileAtLine(const AbsPath: string;
  LineNumber: Integer);
var
  ModuleSvc : IOTAModuleServices;
  ActionSvc : IOTAActionServices;
  Module    : IOTAModule;
  SrcEditor : IOTASourceEditor;
  EditView  : IOTAEditView;
  EditPos   : TOTAEditPos;
  i         : Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleSvc) then Exit;

  // Modul suchen (bereits geoeffnet oder erst oeffnen)
  Module := ModuleSvc.FindModule(AbsPath);
  if not Assigned(Module) then
  begin
    if Supports(BorlandIDEServices, IOTAActionServices, ActionSvc) then
      ActionSvc.OpenFile(AbsPath);
    Module := ModuleSvc.FindModule(AbsPath);
  end;

  if not Assigned(Module) then Exit;
  if LineNumber <= 0 then Exit;

  // IOTASourceEditor aus dem Modul holen
  SrcEditor := nil;
  for i := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[i], IOTASourceEditor, SrcEditor) then
      Break;
  if not Assigned(SrcEditor) then Exit;

  // Editor-Tab in den Vordergrund bringen (wichtig wenn Datei bereits
  // geoeffnet war und nur ein anderer Tab aktiv ist).
  SrcEditor.Show;

  // View holen und Cursor setzen
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

end.
