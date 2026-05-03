unit uUIDockableForm;

// Dockbares Tool-Fenster fuer UI-Befunde.
// Layout entspricht dem Vorschlag aus docs/ux_split_layout_mockup.svg:
// Grid links, Detail rechts, dazwischen ein TSplitter.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.Classes, System.SysUtils, System.Generics.Collections,
  System.IniFiles, System.Actions,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Grids, Vcl.ComCtrls, Vcl.Menus, Vcl.ActnList, Vcl.ImgList,
  DesignIntf, ToolsAPI,
  uDfmIssues;

type
  TUIEditorFrame = class(TFrame)
    TopBar       : TPanel;
    LblForm      : TLabel;
    BtnRefresh   : TButton;
    Grid         : TStringGrid;
    Splitter1    : TSplitter;
    DetailPanel  : TPanel;
    LblSeverity  : TLabel;
    LblRule      : TLabel;
    LblComponent : TLabel;
    MemoMessage  : TMemo;
    BtnSelect    : TButton;
    StatusBar1   : TStatusBar;
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure GridDblClick(Sender: TObject);
    procedure BtnRefreshClick(Sender: TObject);
    procedure BtnSelectClick(Sender: TObject);
  private
    FIssues : TList<TUIIssue>;
    FRoot   : string;
    procedure FillGrid;
    procedure ShowDetail(Index: Integer);
    function  CurrentDesigner: IDesigner;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Vom Notifier aufgerufen, wenn sich die Befunde aendern.
    procedure UpdateIssues(const ARootName: string; AIssues: TUIIssueList);
  end;

  TUIEditorDockableForm = class(TInterfacedObject, INTACustomDockableForm)
  private
    FFrame : TUIEditorFrame;
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolBarActionList: TCustomActionList;
    function GetToolBarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile;
      const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
    property Frame: TUIEditorFrame read FFrame;
  end;

procedure ShowUIEditorDockable;
function  GetUIEditorFrame: TUIEditorFrame;
procedure RegisterUIEditorDockable;
procedure UnregisterUIEditorDockable;

implementation

{$R *.dfm}

var
  GDockable : TUIEditorDockableForm = nil;

{ TUIEditorFrame }

constructor TUIEditorFrame.Create(AOwner: TComponent);
begin
  inherited;
  FIssues := TList<TUIIssue>.Create;

  Grid.ColCount := 4;
  Grid.RowCount := 2;
  Grid.FixedRows := 1;
  Grid.Cells[0, 0] := 'Severity';
  Grid.Cells[1, 0] := 'Regel';
  Grid.Cells[2, 0] := 'Komponente';
  Grid.Cells[3, 0] := 'Meldung';
  Grid.ColWidths[0] := 70;
  Grid.ColWidths[1] := 170;
  Grid.ColWidths[2] := 140;
  Grid.ColWidths[3] := 400;

  FillGrid;
end;

destructor TUIEditorFrame.Destroy;
begin
  FIssues.Free;
  inherited;
end;

procedure TUIEditorFrame.UpdateIssues(const ARootName: string;
  AIssues: TUIIssueList);
var
  i: Integer;
begin
  FRoot := ARootName;
  FIssues.Clear;
  if Assigned(AIssues) then
    for i := 0 to AIssues.Count - 1 do
      FIssues.Add(AIssues[i]);

  if FRoot = '' then
    LblForm.Caption := 'Form: (keine geoeffnet)'
  else
    LblForm.Caption := 'Form: ' + FRoot;

  FillGrid;
  if FIssues.Count > 0 then
    ShowDetail(0)
  else
    ShowDetail(-1);

  StatusBar1.SimpleText := Format('%d Befund(e)', [FIssues.Count]);
end;

procedure TUIEditorFrame.FillGrid;
var
  i: Integer;
begin
  if FIssues.Count = 0 then
  begin
    Grid.RowCount := 2;
    Grid.Rows[1].Clear;
    Exit;
  end;

  Grid.RowCount := FIssues.Count + 1;
  for i := 0 to FIssues.Count - 1 do
  begin
    Grid.Cells[0, i + 1] := TDfmIssueDetector.SeverityToStr(FIssues[i].Severity);
    Grid.Cells[1, i + 1] := FIssues[i].RuleId;
    Grid.Cells[2, i + 1] := FIssues[i].ComponentName;
    Grid.Cells[3, i + 1] := FIssues[i].Message;
  end;
end;

procedure TUIEditorFrame.ShowDetail(Index: Integer);
var
  Issue: TUIIssue;
begin
  if (Index < 0) or (Index >= FIssues.Count) then
  begin
    LblSeverity.Caption  := '';
    LblRule.Caption      := '';
    LblComponent.Caption := '';
    MemoMessage.Lines.Clear;
    BtnSelect.Enabled    := False;
    Exit;
  end;

  Issue := FIssues[Index];
  LblSeverity.Caption  := TDfmIssueDetector.SeverityToStr(Issue.Severity);
  case Issue.Severity of
    uisError:   LblSeverity.Font.Color := clRed;
    uisWarning: LblSeverity.Font.Color := $00007BCC;
  else          LblSeverity.Font.Color := clGray;
  end;
  LblRule.Caption      := Issue.RuleId;
  LblComponent.Caption := Format('%s : %s', [Issue.ComponentName,
                                             Issue.ComponentClass]);
  MemoMessage.Text     := Issue.Message;
  BtnSelect.Enabled    := Issue.ComponentName <> '';
end;

procedure TUIEditorFrame.GridSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
begin
  CanSelect := True;
  if ARow >= 1 then
    ShowDetail(ARow - 1);
end;

procedure TUIEditorFrame.GridDblClick(Sender: TObject);
begin
  BtnSelectClick(Sender);
end;

function TUIEditorFrame.CurrentDesigner: IDesigner;
var
  ModSvc   : IOTAModuleServices;
  i, j     : Integer;
  Module   : IOTAModule;
  FormEd   : IOTAFormEditor;
  NTAForm  : INTAFormEditor;
  Designer : IDesigner;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;

  // INTAFormEditor.FormDesigner liefert den IDesigner; dessen Root ist
  // direkt der TComponent der aktiven Form. So muessen wir nicht ueber
  // IOTAComponent.GetComponent(Index) gehen (das ist Index-basiert).
  for i := 0 to ModSvc.ModuleCount - 1 do
  begin
    Module := ModSvc.Modules[i];
    for j := 0 to Module.GetModuleFileCount - 1 do
      if Supports(Module.GetModuleFileEditor(j), IOTAFormEditor, FormEd) then
        if Supports(FormEd, INTAFormEditor, NTAForm) then
        begin
          Designer := NTAForm.FormDesigner;
          if (Designer <> nil) and (Designer.Root <> nil) and
             SameText(Designer.Root.Name, FRoot) then
            Exit(Designer);
        end;
  end;
end;

procedure TUIEditorFrame.BtnRefreshClick(Sender: TObject);
var
  D: IDesigner;
begin
  D := CurrentDesigner;
  if D = nil then
  begin
    StatusBar1.SimpleText := 'Kein passender Designer offen.';
    Exit;
  end;
  // Detect-Lauf wird durch Notifier ausgeloest; hier nur ItemsModified
  // simulieren, indem wir direkt detect aufrufen.
  UpdateIssues(D.Root.Name, TDfmIssueDetector.Detect(D.Root));
end;

procedure TUIEditorFrame.BtnSelectClick(Sender: TObject);
var
  D    : IDesigner;
  Comp : TComponent;
  Row  : Integer;
begin
  Row := Grid.Row - 1;
  if (Row < 0) or (Row >= FIssues.Count) then Exit;

  D := CurrentDesigner;
  if D = nil then Exit;
  Comp := D.Root.FindComponent(FIssues[Row].ComponentName);
  if Comp <> nil then
    D.SelectComponent(Comp);
end;

{ TUIEditorDockableForm }

function TUIEditorDockableForm.GetCaption: string;
begin
  Result := 'UI Befunde';
end;

function TUIEditorDockableForm.GetIdentifier: string;
begin
  Result := 'StaticCodeAnalyser.UIEditor.DockForm';
end;

function TUIEditorDockableForm.GetFrameClass: TCustomFrameClass;
begin
  Result := TUIEditorFrame;
end;

procedure TUIEditorDockableForm.FrameCreated(AFrame: TCustomFrame);
begin
  FFrame := AFrame as TUIEditorFrame;
end;

function TUIEditorDockableForm.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TUIEditorDockableForm.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TUIEditorDockableForm.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TUIEditorDockableForm.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TUIEditorDockableForm.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TUIEditorDockableForm.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TUIEditorDockableForm.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
end;

procedure TUIEditorDockableForm.LoadWindowState(Desktop: TCustomIniFile;
  const Section: string);
begin
end;

function TUIEditorDockableForm.GetEditState: TEditState;
begin
  Result := [];
end;

function TUIEditorDockableForm.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure RegisterUIEditorDockable;
var
  NTASvc: INTAServices;
begin
  if GDockable <> nil then Exit;
  GDockable := TUIEditorDockableForm.Create;
  NTASvc := BorlandIDEServices as INTAServices;
  NTASvc.RegisterDockableForm(GDockable);
end;

procedure UnregisterUIEditorDockable;
begin
  if GDockable = nil then Exit;
  (BorlandIDEServices as INTAServices).UnregisterDockableForm(GDockable);
  GDockable := nil;
end;

procedure ShowUIEditorDockable;
begin
  if GDockable = nil then RegisterUIEditorDockable;
  (BorlandIDEServices as INTAServices).CreateDockableForm(GDockable);
end;

function GetUIEditorFrame: TUIEditorFrame;
begin
  if GDockable <> nil then
    Result := GDockable.Frame
  else
    Result := nil;
end;

end.
