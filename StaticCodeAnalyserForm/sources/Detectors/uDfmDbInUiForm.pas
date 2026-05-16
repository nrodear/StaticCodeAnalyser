unit uDfmDbInUiForm;

// Detektor: DB-Komponente liegt direkt auf einer TForm/TFrame statt im
// dafuer vorgesehenen TDataModule.
//
// Architektur-Smell: Verbindungen, Queries, StoredProcs gehoeren in ein
// DataModule, das von allen Forms gemeinsam genutzt wird. Direkt auf der
// Form liegende DB-Komponenten erschweren das Test-Setup, machen
// Connection-Pooling unmoeglich und fuehren dazu, dass das Schliessen der
// Form die Verbindung beendet.
//
// Heuristik:
//   * Root-Klasse Suffix 'DataModule' -> nicht zu pruefen (das ist genau
//     das gewuenschte Pattern).
//   * Sonst: alle DB-Komponenten (TADOConnection, TFDQuery, ...) im
//     Komponenten-Baum melden.
//
// Erkennung der DB-Klassen ueber die bestehende Whitelist aus
// uDfmDbFieldAnalysis (DataSetClass / DataSourceClass) plus ein paar
// zusaetzliche Connection-Klassen.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uComponentGraph, uDfmDbFieldAnalysis;

type
  TDfmDbInUiFormDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils;

const
  // Connection-Klassen, die auch nicht auf eine UI-Form gehoeren - durch
  // die Whitelist hier ergaenzt, weil uDfmDbFieldAnalysis nur DataSet/
  // DataSource kennt.
  CONNECTION_CLASSES: array[0..6] of string = (
    'TADOConnection', 'TFDConnection', 'TIBDatabase',
    'TSQLConnection', 'TZConnection', 'TUniConnection',
    'TOracleSession'
  );

function IsConnectionClass(const ClassRef: string): Boolean;
var X: string;
begin
  for X in CONNECTION_CLASSES do
    if SameText(ClassRef, X) then Exit(True);
  Result := False;
end;

function IsDbComponent(const ClassRef: string): Boolean;
begin
  Result := IsDataSetClass(ClassRef)
         or IsDataSourceClass(ClassRef)
         or IsConnectionClass(ClassRef);
end;

function IsDataModuleRoot(const ClassRef: string): Boolean;
// Schluesselheuristik: Klassen-Name endet auf 'DataModule' (Delphi-
// Konvention fuer TDataModule-Nachfahren). Deckt 'TDataModule',
// 'TMainDataModule', 'TPersonsDataModule' etc. ab.
begin
  Result := EndsText('DataModule', ClassRef);
end;

class procedure TDfmDbInUiFormDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All  : TList<TComponentNode>;
  Root : TComponentNode;
  N    : TComponentNode;
  F    : TLeakFinding;
begin
  if Graph = nil then Exit;
  if Graph.Roots.Count = 0 then Exit;

  Root := Graph.Roots[0];
  if IsDataModuleRoot(Root.ClassRef) then Exit;

  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if N = Root then Continue;        // Root selbst nie melden
      if not IsDbComponent(N.ClassRef) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format('%s (%s) lives on %s (%s) - move to a TDataModule',
                              [N.Name, N.ClassRef, Root.Name, Root.ClassRef]);
      F.SetKind(fkDfmDbInUiForm);
      Results.Add(F);
    end;
  finally
    All.Free;
  end;
end;

end.
