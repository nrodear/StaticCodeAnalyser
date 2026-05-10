unit uMethodd12;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uLocalization;  // _() — SeverityText/TypeText lokalisierbar

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
// Liefert lokalisierten Severity-Text fuer UI-Anzeige (Grid, Hover-Overlay,
// Export). Source-Strings sind ENGLISCH (Konvention von uLocalization),
// uLocalization._() mappt bei aktiver DE-Sprache auf 'Fehler'/'Warnung'/etc.
// uAnalyserTypes.SeverityFromText akzeptiert beide Sprachen parallel,
// daher bleiben Sort + Grid-Filter intakt.
begin
  // FileReadError ist ein Sonderfall: kein Code-Befund sondern Parser-Fehler.
  if Kind = fkFileReadError then
    Exit(_('Read Error'));

  case Severity of
    lsError   : Result := _('Error');
    lsWarning : Result := _('Warning');
    lsHint    : Result := _('Hint');
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
// SonarQube-typische Type-Bezeichnungen — Source-Strings englisch (etabliert),
// fuer DE-UI via _() uebersetzbar (default Pass-Through bleibt englisch
// solange kein DE-Mapping fuer 'Bug'/'Code Smell' im Dictionary steht).
begin
  case FindingType of
    ftBug             : Result := _('Bug');
    ftCodeSmell       : Result := _('Code Smell');
    ftVulnerability   : Result := _('Vulnerability');
    ftSecurityHotspot : Result := _('Security Hotspot');
    ftCodeDuplication : Result := _('Code Duplication');
    ftFileError       : Result := _('Read Error');
  else
    Result := '';
  end;
end;

end.
