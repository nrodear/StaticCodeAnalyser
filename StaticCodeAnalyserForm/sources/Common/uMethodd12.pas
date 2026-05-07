unit uMethodd12;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uSCAConsts;

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
    procedure GetVarNamesByClasses(const classes: TStringList; out vars: TStringList);
  end;

  TLeakFinding = class
  public
    FileName:   string;
    MethodName: string;
    LineNumber: string;
    MissingVar: string;
    Severity:   TLeakSeverity;
    Kind:       TFindingKind;
    function SeverityText: string;
    function FindingType: TFindingType;
    function TypeText: string;
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
  try
    for line in Variables do
    begin
      if line.Contains(myClazz) then
      begin
        inputString := Trim(Copy(line, 1, Pos(':', line) - 1));
        temps.clear;
        temps.Delimiter     := ',';
        temps.DelimitedText := inputString;
        for var t := 0 to temps.Count - 1 do
          temps[t] := Trim(temps[t]);
        vars.AddStrings(temps);
      end;
    end;
  finally
    FreeAndNil(temps);
  end;
end;

procedure TMethodInfo.GetVarNamesByClasses(const classes: TStringList;
  out vars: TStringList);
var
  clazz: string;
begin
  for clazz in classes do
    GetVarNamesByFilter(clazz, vars);
end;

function TLeakFinding.SeverityText: string;
begin
  // Lesefehler ist ein Sonderfall: kein Code-Befund sondern Parser-Fehler.
  if Kind = fkFileReadError then
    Exit('Lesefehler');

  case Severity of
    lsError   : Result := 'Fehler';
    lsWarning : Result := 'Warnung';
    lsHint    : Result := 'Hinweis';
  else
    Result := '';
  end;
end;

function TLeakFinding.FindingType: TFindingType;
// Delegiert an KIND_META in uSCAConsts (single source of truth fuer
// Kind -> Sonar-Type-Mapping). Vorher: case-Statement das gegen die
// Mappings in uExport/uClaudePrompt/uSuppression driften konnte.
begin
  Result := KindFindingType(Kind);
end;

function TLeakFinding.TypeText: string;
begin
  case FindingType of
    ftBug             : Result := 'Bug';
    ftCodeSmell       : Result := 'Code Smell';
    ftVulnerability   : Result := 'Vulnerability';
    ftSecurityHotspot : Result := 'Security Hotspot';
    ftCodeDuplication : Result := 'Code Duplication';
    ftFileError       : Result := 'Lesefehler';
  else
    Result := '';
  end;
end;

end.
