unit uBaseline;

// Baseline-Filter fuer CI-Adoption. Schreibt / liest eine JSON-Datei
// mit den AKZEPTIERTEN Findings, damit ein laufender Lauf NEUE Findings
// vs. Baseline klar abhebt.
//
// Anwendung (typisch in CI):
//   Erst-Lauf:  analyser.exe --full --path repo --write-baseline sca.baseline.json
//   Folge-Lauf: analyser.exe --branch --path repo --baseline sca.baseline.json
//
// Mit --baseline werden alle Findings entfernt, deren Fingerprint im
// Baseline-Set vorkommt. Was uebrig bleibt sind die "neu seit Baseline"-
// Findings - das ist was die CI zaehlen soll.
//
// Fingerprint-Stabilitaet:
//   - Pfad: nur Dateiname (kein Verzeichnis - umgeht checkout-Variationen)
//   - Kind: Catalog-Token (z.B. 'MemoryLeak')
//   - MethodName: stabilisiert gegen Zeilen-Drift
//   - MissingVar (Detail): unterscheidet mehrere Findings im selben Method
//   Line wird BEWUSST NICHT in den Fingerprint genommen - Insert/Delete
//   einer Zeile verschiebt jedes Finding sonst. Trade-off: zwei Findings
//   gleichen Detektor-Typs in derselben Methode mit identischem Detail
//   matchen denselben Fingerprint -> Baseline matched einen davon (fine).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Hash,
  uSCAConsts, uMethodd12;

type
  TBaseline = class
  public
    // Schreibt die aktuelle Findings-Liste als JSON in DestFile.
    // ueberschreibt eine vorhandene Datei.
    class procedure Write(Findings: TObjectList<TLeakFinding>;
      const DestFile: string); static;

    // Liest BaselineFile und filtert aus Findings alle Eintraege heraus
    // deren Fingerprint in der Baseline ist (vorhandene "akzeptierte"
    // Befunde). Idempotent; fehlende/leere Datei = no-op.
    // Liefert die Anzahl der GEDROPPTEN Findings (fuer Reporting).
    class function Apply(Findings: TObjectList<TLeakFinding>;
      const BaselineFile: string): Integer; static;

    // Fingerprint einer einzelnen Finding-Instanz. Public weil Tests sie
    // mocken.
    class function Fingerprint(const F: TLeakFinding): string; static;
  end;

implementation

uses
  System.JSON, System.IOUtils,
  uFindingFingerprint;

class function TBaseline.Fingerprint(const F: TLeakFinding): string;
var
  Bare : string;
begin
  // Pfad-Normalisierung: nur Dateiname (Backslash-zu-Slash, lowercase).
  Bare := LowerCase(ExtractFileName(F.FileName));
  Result := THashSHA2.GetHashString(
    Bare + '|' + KindName(F.Kind) + '|' +
    F.MethodName + '|' + F.MissingVar);
end;

class procedure TBaseline.Write(Findings: TObjectList<TLeakFinding>;
  const DestFile: string);
var
  Arr   : TJSONArray;
  Obj   : TJSONObject;
  F     : TLeakFinding;
  Root  : TJSONObject;
  SL    : TStringList;
begin
  if DestFile = '' then Exit;
  Arr := TJSONArray.Create;
  if Assigned(Findings) then
    for F in Findings do
    begin
      if F.Kind = fkFileReadError then Continue; // I/O-Fehler nicht baseline'n
      Obj := TJSONObject.Create;
      Obj.AddPair('file',        ExtractFileName(F.FileName));
      Obj.AddPair('kind',        KindName(F.Kind));
      Obj.AddPair('method',      F.MethodName);
      Obj.AddPair('detail',      F.MissingVar);
      Obj.AddPair('line',        F.LineNumber);
      Obj.AddPair('fingerprint', Fingerprint(F));
      // C.2: zusaetzlich Code-Snippet-Hash. Leer wenn Datei nicht lesbar -
      // dann faellt Apply auf den legacy fingerprint zurueck.
      var Ctx := TFindingFingerprint.ContextHash(F);
      if Ctx <> '' then
        Obj.AddPair('contextHash', Ctx);
      Arr.AddElement(Obj);
    end;

  Root := TJSONObject.Create;
  Root.AddPair('version',     '1');
  Root.AddPair('createdAt',   FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
  Root.AddPair('count',       TJSONNumber.Create(Arr.Count));
  Root.AddPair('findings',    Arr);

  SL := TStringList.Create;
  try
    SL.Text := Root.Format(2);
    SL.SaveToFile(DestFile, TEncoding.UTF8);
  finally
    SL.Free;
    Root.Free; // -> Arr + Objs werden mit befreit
  end;
end;

class function TBaseline.Apply(Findings: TObjectList<TLeakFinding>;
  const BaselineFile: string): Integer;
// Match-Strategie (C.2):
//   1. Wenn Finding einen contextHash hat UND der in der Baseline ist
//      -> Drop (stabilster Pfad, ueberlebt Line-Drift + Re-Indent).
//   2. Sonst: legacy fingerprint pruefen (File+Kind+Method+Detail).
//   Backward-compat: alte Baselines ohne contextHash matchen weiter via 2.
var
  Raw       : string;
  Root      : TJSONValue;
  Arr       : TJSONArray;
  Obj       : TJSONValue;
  FpJson    : TJSONValue;
  CtxJson   : TJSONValue;
  FpSet     : TDictionary<string, Boolean>;
  CtxSet    : TDictionary<string, Boolean>;
  i         : Integer;
  F         : TLeakFinding;
  FCtx      : string;
begin
  Result := 0;
  if (Findings = nil) or (BaselineFile = '') then Exit;
  if not FileExists(BaselineFile) then Exit;

  Raw := TFile.ReadAllText(BaselineFile, TEncoding.UTF8);
  Root := TJSONObject.ParseJSONValue(Raw);
  if Root = nil then Exit;

  FpSet  := TDictionary<string, Boolean>.Create;
  CtxSet := TDictionary<string, Boolean>.Create;
  try
    if Root is TJSONObject then
      Arr := TJSONObject(Root).Values['findings'] as TJSONArray
    else if Root is TJSONArray then
      Arr := TJSONArray(Root)            // Alt-Format: rein das Array
    else
      Arr := nil;

    if Arr <> nil then
      for Obj in Arr do
        if Obj is TJSONObject then
        begin
          FpJson := TJSONObject(Obj).Values['fingerprint'];
          if (FpJson <> nil) and not FpJson.Null then
            FpSet.AddOrSetValue(FpJson.Value, True);
          CtxJson := TJSONObject(Obj).Values['contextHash'];
          if (CtxJson <> nil) and not CtxJson.Null
             and (CtxJson.Value <> '') then
            CtxSet.AddOrSetValue(CtxJson.Value, True);
        end;

    // Rueckwaerts iterieren wegen Delete
    for i := Findings.Count - 1 downto 0 do
    begin
      F := Findings[i];
      if F.Kind = fkFileReadError then Continue;
      FCtx := TFindingFingerprint.ContextHash(F);
      if ((FCtx <> '') and CtxSet.ContainsKey(FCtx))
         or FpSet.ContainsKey(Fingerprint(F)) then
      begin
        Findings.Delete(i);     // owns - F wird freigegeben
        Inc(Result);
      end;
    end;
  finally
    FpSet.Free;
    CtxSet.Free;
    Root.Free;
  end;
end;

end.
