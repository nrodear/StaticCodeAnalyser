unit uDfmForbiddenClass;

// Detektor: Komponente nutzt eine via analyser.ini verbotene Klasse.
//
// Anwendungsfall: Projekt-Style-Guide schreibt vor, dass z.B. statt
// TLabel die Theme-fähige TcxLabel verwendet werden soll - oder eine
// Drittanbieter-Komponente ist deprecated und soll nicht mehr neu
// eingesetzt werden.
//
// Konfiguration ueber uSCAConsts.DfmForbiddenClasses (analog zu den
// anderen INI-getriebenen Listen). Default leer - der Detektor schweigt,
// bis das Projekt eine Liste eintraegt:
//   [Components] ForbiddenClasses=TLabel,TQuery
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmForbiddenClassDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

class procedure TDfmForbiddenClassDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All : TList<TComponentNode>;
  N   : TComponentNode;
  F   : TLeakFinding;
begin
  if Graph = nil then Exit;
  if (DfmForbiddenClasses = nil) or (DfmForbiddenClasses.Count = 0) then Exit;

  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      // DfmForbiddenClasses ist CaseSensitive=False -> .IndexOf matcht
      // 'tlabel' gegen 'TLabel'.
      if DfmForbiddenClasses.IndexOf(N.ClassRef) < 0 then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format('%s uses forbidden class %s',
                              [N.Name, N.ClassRef]);
      F.SetKind(fkDfmForbiddenClass);
      Results.Add(F);
    end;
  finally
    All.Free;
  end;
end;

end.
