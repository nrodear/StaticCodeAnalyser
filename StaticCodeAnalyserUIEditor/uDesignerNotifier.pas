unit uDesignerNotifier;

// Hoert auf Designer-Ereignisse (Form geoeffnet/geschlossen, Auswahl
// geaendert, Komponente eingefuegt/geloescht/modifiziert) und stoesst
// eine Neuberechnung der UI-Befunde an.
//
// Die Befunde werden ueber ein Callback (TUIIssuesChangedProc) an den
// Listener (z. B. das dockbare Tool-Fenster) gepusht. So bleibt der
// Notifier von der UI-Schicht entkoppelt.

interface

uses
  System.Classes, System.SysUtils,
  DesignIntf,
  uDfmIssues;

type
  TUIIssuesChangedProc = reference to procedure(const RootName: string;
    Issues: TUIIssueList);

  TUIDesignerNotifier = class(TInterfacedObject, IDesignNotification)
  private
    FOnChanged    : TUIIssuesChangedProc;
    FCurrentRoot  : TComponent;
    FRegistered   : Boolean;
    procedure Recompute(const ADesigner: IDesigner);
  public
    constructor Create(const AOnChanged: TUIIssuesChangedProc);
    destructor Destroy; override;

    procedure RegisterSelf;
    procedure UnregisterSelf;

    { IDesignNotification }
    procedure ItemDeleted(const ADesigner: IDesigner; Item: TPersistent);
    procedure ItemInserted(const ADesigner: IDesigner; Item: TPersistent);
    procedure ItemsModified(const ADesigner: IDesigner);
    procedure SelectionChanged(const ADesigner: IDesigner;
      const ASelection: IDesignerSelections);
    procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
    procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
  end;

implementation

{ TUIDesignerNotifier }

constructor TUIDesignerNotifier.Create(const AOnChanged: TUIIssuesChangedProc);
begin
  inherited Create;
  FOnChanged := AOnChanged;
end;

destructor TUIDesignerNotifier.Destroy;
begin
  UnregisterSelf;
  inherited;
end;

procedure TUIDesignerNotifier.RegisterSelf;
begin
  if FRegistered then Exit;
  RegisterDesignNotification(Self);
  FRegistered := True;
end;

procedure TUIDesignerNotifier.UnregisterSelf;
begin
  if not FRegistered then Exit;
  UnregisterDesignNotification(Self);
  FRegistered := False;
end;

procedure TUIDesignerNotifier.Recompute(const ADesigner: IDesigner);
var
  Root   : TComponent;
  Issues : TUIIssueList;
  Name_  : string;
begin
  if not Assigned(FOnChanged) then Exit;
  if ADesigner = nil then Exit;

  Root := ADesigner.Root;
  FCurrentRoot := Root;

  if Root = nil then
  begin
    FOnChanged('', nil);
    Exit;
  end;

  Issues := TDfmIssueDetector.Detect(Root);
  try
    Name_ := Root.Name;
    FOnChanged(Name_, Issues);
  finally
    Issues.Free;
  end;
end;

procedure TUIDesignerNotifier.ItemDeleted(const ADesigner: IDesigner;
  Item: TPersistent);
begin
  Recompute(ADesigner);
end;

procedure TUIDesignerNotifier.ItemInserted(const ADesigner: IDesigner;
  Item: TPersistent);
begin
  Recompute(ADesigner);
end;

procedure TUIDesignerNotifier.ItemsModified(const ADesigner: IDesigner);
begin
  Recompute(ADesigner);
end;

procedure TUIDesignerNotifier.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
  // Auswahlwechsel beeinflusst die Befunde nicht; das Tool-Fenster kann
  // hierauf gesondert hoeren falls "follow selection" gewuenscht ist.
end;

procedure TUIDesignerNotifier.DesignerOpened(const ADesigner: IDesigner;
  AResurrecting: Boolean);
begin
  Recompute(ADesigner);
end;

procedure TUIDesignerNotifier.DesignerClosed(const ADesigner: IDesigner;
  AGoingDormant: Boolean);
begin
  if Assigned(FOnChanged) then
    FOnChanged('', nil);
  FCurrentRoot := nil;
end;

end.
