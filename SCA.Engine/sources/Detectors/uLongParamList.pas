unit uLongParamList;

// Detektor fuer Methoden mit zu vielen Parametern.
// Mehr als MAX_PARAMS Parameter deuten auf einen Refactoring-Bedarf hin
// (Parameter-Object, Builder, Konfigurations-Record).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLongParamListDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// Schwellwert kommt aus uSCAConsts.DetectorMaxParams (analyser.ini ->
// LongParamListMaxParams). Default 5.

class procedure TLongParamListDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods    : TList<TAstNode>;
  M          : TAstNode;
  ParamCount : Integer;
  Reported   : TDictionary<string, Boolean>;
  Key        : string;
  F          : TLeakFinding;
begin
  // Methoden koennen sowohl in Interface (Deklaration) als auch in
  // Implementation auftauchen → mit Methodennamen deduplizieren.
  Reported := TDictionary<string, Boolean>.Create;
  Methods  := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      ParamCount := M.ChildCount(nkParam);
      if ParamCount <= DetectorMaxParams then Continue;

      Key := M.Name + ':' + IntToStr(ParamCount);
      if Reported.ContainsKey(Key) then Continue;
      Reported.Add(Key, True);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format('%d parameters (limit: %d)',
        [ParamCount, DetectorMaxParams]);
      F.SetKind(fkLongParamList);
      Results.Add(F);
    end;
  finally
    Methods.Free;
    Reported.Free;
  end;
end;

end.
