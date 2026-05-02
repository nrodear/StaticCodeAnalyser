unit uIDEExpert;

// Delphi IDE Expert: registriert "Static Code Analyser" im Tools-Menü

interface

uses
  ToolsAPI;

type
  TStaticCodeAnalyserExpert = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  public
    destructor Destroy; override;
    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
    { IOTAMenuWizard }
    function GetMenuText: string;
  end;

procedure Register;

implementation

uses
  uIDEAnalyserForm;

procedure Register;
begin
  RegisterAnalyserDockableForm;
  RegisterPackageWizard(TStaticCodeAnalyserExpert.Create);
end;

{ TStaticCodeAnalyserExpert }

destructor TStaticCodeAnalyserExpert.Destroy;
begin
  UnregisterAnalyserDockableForm;
  inherited;
end;

function TStaticCodeAnalyserExpert.GetIDString: string;
begin
  Result := 'StaticCodeAnalyser' ;
end;

function TStaticCodeAnalyserExpert.GetName: string;
begin
  Result := 'Static Code Analyser';
end;

function TStaticCodeAnalyserExpert.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TStaticCodeAnalyserExpert.Execute;
begin
  ShowAnalyserDockableForm;
end;

function TStaticCodeAnalyserExpert.GetMenuText: string;
begin
  Result := 'Static Code Analyser';
end;

end.
