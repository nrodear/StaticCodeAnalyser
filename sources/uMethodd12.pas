unit uMethodd12;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TMethodInfo = class
  public
    Name: string;
    Signatur: string;
    LineNumber: string;
    Variables: TStringList;
    SourceBody: TStringList;

    constructor Create;
    destructor Destroy; override;
    procedure GetVarNamesByFilter(const myClazz: string; out vars: TStringList);
  end;

implementation

{ TMethodInfo }

constructor TMethodInfo.Create;
begin
  inherited;
  Name := '';
  SourceBody := TStringList.Create;
  Variables := TStringList.Create;
  Variables.clear;
  SourceBody.clear;
end;

destructor TMethodInfo.Destroy;
begin
  freeAndNil(SourceBody);
  freeAndNil(Variables);
  inherited;
end;

procedure TMethodInfo.GetVarNamesByFilter(const myClazz: string;
  out vars: TStringList);
var
  temps: TStringList;
  line, inputString: string;

begin
  temps := TStringList.Create;

  for line in Variables do
  begin
    if line.Contains(myClazz) then
    begin
      inputString := Copy(line, 1, Pos(':', line) - 1);
      temps.clear;
      temps.DelimitedText := inputString;
      vars.AddStrings(temps);
    end;
  end;

  freeAndNil(temps);
end;

end.
