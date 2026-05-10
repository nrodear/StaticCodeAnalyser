unit uDfmActionMismatch;

// Detektor: Komponente hat sowohl Action- als auch OnClick-Property
// gesetzt. Wenn Action gesetzt ist, gewinnt das ueber OnClick - der
// OnClick-Handler wird nie aufgerufen und ist toter Code.
//
// Beispiel:
//   object btnSave: TButton
//     Action  = ActSave
//     OnClick = btnSaveClick      // <- niemals gerufen
//   end
//
// Erkennung: Property 'Action' (pvkIdent, nicht leer) UND 'OnClick'
// (pvkIdent, nicht leer) auf derselben Komponente.
//
// Schweregrad: lsWarning, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmActionMismatchDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

class procedure TDfmActionMismatchDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All  : TList<TComponentNode>;
  N    : TComponentNode;
  Act, Clk : TPropValue;
  F    : TLeakFinding;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if not N.TryGetProperty('Action', Act) then Continue;
      if Act.Kind <> pvkIdent then Continue;
      if Trim(Act.RawValue) = '' then Continue;

      if not N.TryGetProperty('OnClick', Clk) then Continue;
      if Clk.Kind <> pvkIdent then Continue;
      if Trim(Clk.RawValue) = '' then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Clk.Line);
      F.MissingVar := Format(
        '%s has Action=%s AND OnClick=%s - Action wins, OnClick handler is dead',
        [N.Name, Act.RawValue, Clk.RawValue]);
      F.Severity   := lsWarning;
      F.Kind       := fkDfmActionMismatch;
      Results.Add(F);
    end;
  finally
    All.Free;
  end;
end;

end.
