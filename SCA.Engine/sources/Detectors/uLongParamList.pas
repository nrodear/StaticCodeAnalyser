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

// GATE FFI (H1, 2026-09-20): True, wenn AOwnerLow ein
// FPC-Fremdsprachen-Binding ist (objcclass/objccategory/
// objcprotocol/cppclass). Dessen Parameterzahl ist die Signatur der
// FREMDEN API - der Autor kann sie nicht kuerzen, ohne die Bindung zu
// brechen. Beleg (G-Abnahme 20.09.): cocoa_extra.pas meldete 10 und
// 11 Parameter, beides ObjC-Selektoren.
//
// FREISTEHEND statt inline: der Selbstscan der H-Charge hat
// AnalyzeUnit mit dem Gate auf CC 25 gehoben (SCA176, Limit 15).
// ABindings/AGeholt sind var-Parameter, damit die LAZY-Beschaffung
// ueber die Schleifendurchlaeufe haelt: die Datei wird erst ab dem
// ersten Kandidaten ueber der Schwelle gelesen, die Liste danach
// genau einmal je Datei gebaut.
type
  // Lazy-Zustand des Gates, gebuendelt: als fuenf einzelne
  // var-Parameter hob der Helfer den eigenen Detektor ueber die
  // Parameterschwelle (SCA013 am eigenen Code, Selbstscan der
  // H-Charge) und trug zwei Boolean-Schalter (SCA146).
  TBindingCache = record
    Namen   : TStringList;   // Binding-Typnamen der Datei
    Geholt  : Boolean;       // Datei schon einmal angefasst?
    Lines   : TStringList;   // gehaltene Zeilen (Freigabe im finally)
    Cached  : Boolean;       // gehoeren die Zeilen dem Textcache?
  end;

function IstBindingBesitzer(const AOwnerLow, AFileName: string;
  AContext: TAnalyzeContext; var ACache: TBindingCache): Boolean;
begin
  if AOwnerLow = '' then Exit(False);
  if not ACache.Geholt then
  begin
    ACache.Geholt := True;
    ACache.Lines := AcquireLines(AFileName, ACache.Cached,
      CtxFileTextCache(AContext));
    if ACache.Lines <> nil then
      ACache.Namen := TDetectorUtils.CollectFpcBindingTypeNames(
        ACache.Lines, AContext, AFileName);
  end;
  Result := TDetectorUtils.IsFfiBindingTypeName(ACache.Namen, AOwnerLow);
end;

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
  // GATE FFI (H1): LAZY - eine Datei ohne Kandidaten ueber der
  // Schwelle zahlt weder Dateizugriff noch Listenaufbau.
  Bindings : TBindingCache;
begin
  // TD-1 (2026-07-06): Schwelle einmal aus dem Context lesen (scan-konstant).
  MaxParams := CfgMaxParams(AContext);
  // Methoden koennen sowohl in Interface (Deklaration) als auch in
  // Implementation auftauchen → mit Methodennamen deduplizieren.
  Reported := TDictionary<string, Boolean>.Create;
  OwnerMap := nil;
  Bindings := Default(TBindingCache);
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
      // GATE FFI (H1): Besitzertyp spiegelt eine fremde API
      // (Herleitung und LAZY-Vertrag an IstBindingBesitzer).
      if IstBindingBesitzer(OwnerLow, FileName, AContext, Bindings) then
        Continue;

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
    Bindings.Namen.Free;
    ReleaseLines(Bindings.Lines, Bindings.Cached);
  end;
end;

end.
