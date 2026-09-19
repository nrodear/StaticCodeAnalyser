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
  System.Classes,    // TStringList (GATE FFI)
  uDetectorUtils,    // OwnerTypeNameLower + BuildMethodOwnerMap (Major 74)
  uFileTextCache;    // AcquireLines/ReleaseLines (GATE FFI, H1)

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
  // GATE FFI (H1): beide LAZY - eine Datei ohne Kandidaten ueber der
  // Schwelle zahlt weder Dateizugriff noch Listenaufbau.
  FpcBindings    : TStringList;
  BindingsGeholt : Boolean;
  Lines          : TStringList;
  Cached         : Boolean;
begin
  // TD-1 (2026-07-06): Schwelle einmal aus dem Context lesen (scan-konstant).
  MaxParams := CfgMaxParams(AContext);
  // Methoden koennen sowohl in Interface (Deklaration) als auch in
  // Implementation auftauchen → mit Methodennamen deduplizieren.
  Reported := TDictionary<string, Boolean>.Create;
  OwnerMap := nil;
  FpcBindings    := nil;
  BindingsGeholt := False;
  Lines          := nil;
  Cached         := False;
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
      // GATE FFI (H1, 2026-09-20): Der Besitzertyp ist ein
      // FPC-Fremdsprachen-Binding (objcclass/objccategory/
      // objcprotocol/cppclass). Dessen Parameterzahl ist die Signatur
      // der FREMDEN API - der Autor kann sie nicht kuerzen, ohne die
      // Bindung zu brechen. Beleg (G-Abnahme 20.09.): cocoa_extra.pas
      // meldete 10 und 11 Parameter, beides ObjC-Selektoren.
      // LAZY in zwei Stufen: Datei erst ab dem ersten Kandidaten ueber
      // der Schwelle lesen, Liste danach einmal je Datei.
      if OwnerLow <> '' then
      begin
        if not BindingsGeholt then
        begin
          BindingsGeholt := True;
          Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
          if Lines <> nil then
            FpcBindings := TDetectorUtils.CollectFpcBindingTypeNames(
              Lines, AContext, FileName);
        end;
        if TDetectorUtils.IsFfiBindingTypeName(FpcBindings, OwnerLow) then
          Continue;
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
    FpcBindings.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
