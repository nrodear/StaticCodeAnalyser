unit uLongParamList;

// Detektor fuer Methoden mit zu vielen Parametern.
// Mehr als MAX_PARAMS Parameter deuten auf einen Refactoring-Bedarf hin
// (Parameter-Object, Builder, Konfigurations-Record).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TLongParamListDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file ConcatToFormat, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils;   // OwnerTypeNameLower + BuildMethodOwnerMap (Major 74)

// Schwellwert kommt aus uSCAConsts.DetectorMaxParams (analyser.ini ->
// LongParamListMaxParams). Default 5.

class procedure TLongParamListDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods    : TList<TAstNode>;
  M          : TAstNode;
  ParamCount : Integer;
  Reported   : TDictionary<string, Boolean>;
  Key        : string;
  F          : TLeakFinding;
  MaxParams  : Integer;   // TD-1: Schwelle per-Scan aus AContext.Config
  OwnerMap   : TDictionary<TAstNode, string>;
  OwnerLow   : string;
begin
  // TD-1 (2026-07-06): Schwelle einmal aus dem Context lesen (scan-konstant).
  MaxParams := CfgMaxParams(AContext);
  // Methoden koennen sowohl in Interface (Deklaration) als auch in
  // Implementation auftauchen → mit Methodennamen deduplizieren.
  Reported := TDictionary<string, Boolean>.Create;
  OwnerMap := nil;
  Methods  := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      ParamCount := M.ChildCount(nkParam);
      if ParamCount <= MaxParams then Continue;

      // Schluessel ist (Besitzertyp, lokaler Name, Anzahl) - wie in
      // uMethodName (Voll-Review 2026-09-12, Major 74): der alte
      // Schluessel M.Name kollidierte NIE zwischen Deklaration ('Bar')
      // und Implementierung ('TFoo.Bar') - jede implementierte
      // Klassenmethode ueber der Schwelle wurde DOPPELT gemeldet -,
      // und er kollidierte FAELSCHLICH zwischen gleichnamigen Methoden
      // verschiedener Typen ('IAlpha.Setup'/'IBeta.Setup' - der zweite
      // Befund fiel weg). Deklarations-Knoten (unqualifizierter Name)
      // beziehen den Besitzer lazy aus der OwnerMap; gemeldet wird der
      // erste Knoten in Dokumentreihenfolge, also die Deklaration.
      OwnerLow := TDetectorUtils.OwnerTypeNameLower(M.Name);
      if OwnerLow = '' then
      begin
        if OwnerMap = nil then
          OwnerMap := TDetectorUtils.BuildMethodOwnerMap(UnitNode);
        if OwnerMap.TryGetValue(M, OwnerLow) then
          OwnerLow := LowerCase(OwnerLow);
      end;
      Key := OwnerLow + '.' + TDetectorUtils.UnqualifiedNameLastLower(M.Name)
             + ':' + IntToStr(ParamCount);
      if Reported.ContainsKey(Key) then Continue;
      Reported.Add(Key, True);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format('%d parameters (limit: %d)',
        [ParamCount, MaxParams]);
      F.SetKind(fkLongParamList);
      Results.Add(F);
    end;
  finally
    Methods.Free;
    Reported.Free;
    OwnerMap.Free;
  end;
end;

end.
