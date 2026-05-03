unit uIDEUIEditorExpert;

// IOTAWizard / IOTAMenuWizard fuer den UI-Editor.
// IOTAMenuWizard erzeugt automatisch einen Eintrag unter "Hilfe / Tools";
// Execute oeffnet das dockbare Tool-Fenster. Zusaetzlich wird der
// DesignNotifier installiert, der bei Designer-Aenderungen die
// Befunde neu berechnet und ans Frame pusht.

interface

uses
  System.Classes, System.SysUtils,
  ToolsAPI, DesignIntf,
  uDesignerNotifier, uDfmIssues, uUIDockableForm, uOverlayPainter;

type
  TUIEditorExpert = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  private
    FNotifier : TUIDesignerNotifier;
    FNotifIfc : IDesignNotification;  // haelt Reference-Count auf FNotifier
    FOverlay  : TOverlayPainter;
    procedure OnIssuesChanged(const RootName: string; Issues: TUIIssueList);
  public
    constructor Create;
    destructor Destroy; override;
    { IOTAWizard }
    function  GetIDString: string;
    function  GetName: string;
    function  GetState: TWizardState;
    procedure Execute;
    { IOTAMenuWizard }
    function  GetMenuText: string;
  end;

procedure RegisterUIEditorExpert;
procedure UnregisterUIEditorExpert;

implementation

var
  GExpertIndex : Integer = -1;

{ TUIEditorExpert }

constructor TUIEditorExpert.Create;
begin
  inherited Create;
  FOverlay := TOverlayPainter.Create;
  FNotifier := TUIDesignerNotifier.Create(OnIssuesChanged);
  FNotifIfc := FNotifier;
  FNotifier.RegisterSelf;
end;

destructor TUIEditorExpert.Destroy;
begin
  if Assigned(FNotifier) then
    FNotifier.UnregisterSelf;
  FNotifIfc := nil; // gibt FNotifier frei
  FOverlay.Free;
  UnregisterUIEditorDockable;
  inherited;
end;

procedure TUIEditorExpert.OnIssuesChanged(const RootName: string;
  Issues: TUIIssueList);
var
  Frame: TUIEditorFrame;
begin
  Frame := GetUIEditorFrame;
  if Frame = nil then Exit;
  Frame.UpdateIssues(RootName, Issues);
  FOverlay.SetIssues(Issues);
end;

function TUIEditorExpert.GetIDString: string;
begin
  Result := 'StaticCodeAnalyser.UIEditor';
end;

function TUIEditorExpert.GetName: string;
begin
  Result := 'Static Code Analyser - UI Editor';
end;

function TUIEditorExpert.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TUIEditorExpert.Execute;
begin
  ShowUIEditorDockable;
end;

function TUIEditorExpert.GetMenuText: string;
begin
  Result := 'Static Code Analyser - UI Befunde';
end;

{ Registrierung }

procedure RegisterUIEditorExpert;
begin
  RegisterUIEditorDockable;
  GExpertIndex := (BorlandIDEServices as IOTAWizardServices).AddWizard(
    TUIEditorExpert.Create);
end;

procedure UnregisterUIEditorExpert;
begin
  // Cleanup laeuft via TUIEditorExpert.Destroy, das die IDE beim
  // Entladen des Pakets selbst aufruft (RemoveWizard wird vom
  // Wizard-Service besorgt). Hier nichts zu tun.
end;

end.
