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
  // Zuschnitt des Baseline-Fingerprints: Modus UND Wurzel als EIN Wert.
  //
  // WARUM ES DEN TYP GIBT (Review 2026-08-18, Befund A): beides lag bisher
  // in zwei unabhaengig setzbaren Prozess-Globals
  // (uSCAConsts.BaselinePathFingerprint / BaselineFingerprintRoot). Genau
  // diese Trennung war der Fehler - ApplyDetectorThresholds setzte den
  // MODUS, die WURZEL setzte nur RefreshBaselineSet, und die steigt aus,
  // solange "nur neue Funde" aus ist. Beim Schreiben einer Baseline stand
  // die Wurzel damit auf Leerstring, der Token fiel still auf den
  // Dateinamen zurueck - gelesen wurde danach mit Relativpfad-Tokens. Das
  // Feature meldete Erfolg und filterte nichts.
  //
  // Ein Wert kann nicht halb gesetzt sein. Wer ihn uebergibt, uebergibt
  // beides.
  TBaselineScope = record
  strict private
    FPathMode : Boolean;
    FRoot     : string;
  public
    // Bestandsverhalten: nur der Dateiname, checkout-tolerant.
    class function ByFileName: TBaselineScope; static;
    // Relativpfad ab ARoot. Leeres ARoot ist zulaessig und verhaelt sich
    // wie ByFileName - Effective meldet dann False.
    class function ByPath(const ARoot: string): TBaselineScope; static;
    // Pfad-Modus mit der WURZEL-REGEL: Verzeichnis der Projekt-/
    // Gruppendatei, sonst die Scan-Wurzel. Genau diese Regel stand bis
    // 2026-08-18 viermal kopiert in CLI, EXE und Plugin.
    //
    // Kein Boolean-Parameter fuer "Pfad-Modus ja/nein": das waere eine
    // verdeckte Strategie-Wahl am Aufrufer (SCA146). Wer den Schalter aus
    // der INI liest, schreibt die zwei Zeilen selbst - die Regel, um die
    // es ging, ist trotzdem nur hier.
    class function ForProject(const AProjectOrGroupFile,
      AScanRoot: string): TBaselineScope; static;
    // UEBERGANG: liest die beiden Globals. Nur solange es Aufrufer ohne
    // Zuschnitt-Parameter gibt - faellt mit dem letzten von ihnen weg.
    class function FromGlobals: TBaselineScope; static;

    // Datei-Token fuer den Fingerprint.
    function FileToken(const AFileName: string): string;
    // Wirkt der Pfad-Modus TATSAECHLICH? Nur wenn Modus UND Wurzel gesetzt
    // sind. Der Unterschied zu IsPathMode ist der Kern von Befund A: der
    // blosse Wunsch nach Pfad-Modus aendert ohne Wurzel gar nichts.
    function Effective: Boolean;

    property IsPathMode : Boolean read FPathMode;
    property Root       : string  read FRoot;
  end;

  TBaseline = class
  public
    // Schreibt die aktuelle Findings-Liste als JSON in DestFile.
    // ueberschreibt eine vorhandene Datei.
    // Liefert die Anzahl der TATSAECHLICH geschriebenen Eintraege. Die ist
    // kleiner als Findings.Count, weil Lesefehler bewusst nicht
    // baseline-faehig sind (s. Rumpf). Bis 2026-08-08 meldeten alle fuenf
    // Aufrufer stattdessen Findings.Count - "Baseline written: ... (5
    // findings)" bei 4 Eintraegen in der Datei.
    class function Write(Findings: TObjectList<TLeakFinding>;
      const DestFile: string): Integer; static;

    // Liest BaselineFile und filtert aus Findings alle Eintraege heraus
    // deren Fingerprint in der Baseline ist (vorhandene "akzeptierte"
    // Befunde). Idempotent; fehlende/leere Datei = no-op.
    // Liefert die Anzahl der GEDROPPTEN Findings (fuer Reporting).
    // AWarnings (optional) sammelt Diagnose-Meldungen (z.B. Fingerprint-
    // Modus der Datei passt nicht zum aktiven [Baseline] PathInFingerprint
    // - dann matcht die Legacy-Stufe nichts und NUR contextHash greift).
    class function Apply(Findings: TObjectList<TLeakFinding>;
      const BaselineFile: string; AWarnings: TStrings = nil): Integer; static;

    // Ist die Datei ueberhaupt eine Baseline? Apply ist bewusst
    // fehlertolerant und liefert bei allem, was es nicht versteht,
    // stillschweigend 0 - richtig fuer eine leere oder halb geschriebene
    // Datei, FALSCH fuer eine verwechselte. Ein versehentlich
    // uebergebener SARIF-Report filterte so nichts, und das Gate meldete
    // den kompletten Bestand als neu (Audit 2026-08-08). Der Aufrufer
    // kann damit hart abbrechen, statt ein falsch-gruenes Ergebnis zu
    // liefern. AReason traegt eine Klartext-Begruendung.
    class function IsBaselineFile(const FileName: string;
      out AReason: string): Boolean; static;

    // Fingerprint einer einzelnen Finding-Instanz. Public weil Tests sie
    // mocken.
    class function Fingerprint(const F: TLeakFinding): string; overload; static;
    // Gleiche Berechnung, aber mit explizitem Zuschnitt statt aus den
    // Globals. Die parameterlose Fassung delegiert hierher.
    class function Fingerprint(const F: TLeakFinding;
      const AScope: TBaselineScope): string; overload; static;

    // Aufloesung des .sca-Standardorts (Konzept_BaselineSca 2026-08-08):
    //   Gruppe (.groupproj): <GroupDir>\.sca\<Name>.baseline.json
    //   Projekt (.dproj):    <ProjDir>\.sca\<Name>.baseline.json,
    //                        Fallback <ProjDir>\..\.sca\<Name>.baseline.json
    //                        (Projekt liegt typisch eine Ebene unter der
    //                        Gruppe, Baseline zentral gepflegt)
    //   Pfad-Scan:           <AScanRoot>\.sca\sca.baseline.json
    // AProjectOrGroupFile leer -> Pfad-Modus ueber AScanRoot. Liefert ''
    // wenn keiner der Kandidaten existiert; AProbed (optional) sammelt
    // ALLE geprueften Pfade fuer die Fehlermeldung des Aufrufers
    // (CLI-harter-Fehler bei --baseline-scan y ohne Datei).
    // Praezedenz insgesamt regelt der AUFRUFER: expliziter --baseline-
    // Pfad > [Baseline] File= > diese Aufloesung.
    class function ResolveBaselinePath(const AProjectOrGroupFile,
      AScanRoot: string; AProbed: TStrings = nil): string; static;

    // Standard-ZIEL fuer '--write-baseline auto' bzw. UI 'Write
    // baseline': der jeweils ERSTE .sca-Kandidat der Aufloesung, OHNE
    // Existenz-Pruefung ('' wenn weder Projekt/Gruppe noch Root
    // bekannt). Den .sca-Ordner legt der Schreiber bei Bedarf an.
    class function DefaultBaselineTarget(const AProjectOrGroupFile,
      AScanRoot: string): string; static;
  end;

  // Non-destruktiver Baseline-Filter fuer Live-Consumer (IDE-Editor): laedt
  // die Fingerprints einmalig und beantwortet pro Finding, ob es bereits in
  // der Baseline steht - OHNE die Findings-Liste zu veraendern. TBaseline.Apply
  // LOESCHT matchende Findings; das eignet sich nicht fuer einen umschaltbaren
  // "nur neue Funde"-Editor-Filter, bei dem die Vollmenge fuer Export/Toggle
  // erhalten bleiben muss. Match ueber den zeilenunabhaengigen Fingerprint
  // (KEIN contextHash - der Editor-Pfad soll nicht pro Finding eine Datei
  // erneut lesen).
  TBaselineSet = class
  private
    FFingerprints: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    // Ersetzt den Inhalt durch die Fingerprints aus BaselineFile. Tolerant
    // gegen beide Formate ({..,"findings":[{"fingerprint"..}]} ODER ein bare
    // Array) - exakt das was TBaseline.Write / CLI --write-baseline schreibt
    // und der HTML-Export liest. Fehlende/leere/kaputte Datei -> leeres Set
    // (Result 0), kein Fehler. Liefert die Anzahl geladener Fingerprints.
    function LoadFromFile(const BaselineFile: string): Integer;
    procedure Clear;
    function IsEmpty: Boolean;
    // True wenn F bereits in der Baseline steht (= KEIN neuer Fund).
    function Contains(const F: TLeakFinding): Boolean;
  end;

implementation

// noinspection-file ConcatToFormat, ConsecutiveSection, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.JSON, System.IOUtils,
  uFindingFingerprint;

// Zielverzeichnis einer zu schreibenden Datei bei Bedarf anlegen - so,
// wie es der Kontrakt am Unit-Kopf fuer den .sca-Ordner zusagt. Bis
// 2026-08-08 stand das nur im Kommentar: drei Aufrufer kompensierten es
// mit eigenem ForceDirectories, der vierte (Plugin) waere in eine
// EInOutError gelaufen.
procedure EnsureTargetDir(const AFileName: string);
var
  Dir : string;
begin
  Dir := ExtractFilePath(AFileName);
  if (Dir <> '') and not DirectoryExists(Dir) then
    ForceDirectories(Dir);
end;

// UTF-8 OHNE BOM schreiben (2026-08-08, RFC 8259 par.8.1 verbietet die
// Praeambel fuer JSON-Austausch). TStringList.SaveToFile mit
// TEncoding.UTF8 haette sie geschrieben. Bestehende Baselines MIT BOM
// bleiben lesbar - TFile.ReadAllText erkennt die Praeambel und
// ueberspringt sie.
procedure SaveTextNoBom(SL: TStringList; const DestFile: string);
var
  Enc : TEncoding;
begin
  Enc := TUTF8Encoding.Create(False);
  try
    SL.SaveToFile(DestFile, Enc);
  finally
    Enc.Free;
  end;
end;

{ ---- TBaselineScope ---- }

class function TBaselineScope.ByFileName: TBaselineScope;
begin
  Result.FPathMode := False;
  Result.FRoot     := '';
end;

class function TBaselineScope.ByPath(const ARoot: string): TBaselineScope;
begin
  Result.FPathMode := True;
  Result.FRoot     := ARoot;
end;

class function TBaselineScope.ForProject(const AProjectOrGroupFile,
  AScanRoot: string): TBaselineScope;
// Wurzel-Regel, woertlich wie in den bisherigen vier Kopien:
// Verzeichnis der Projekt-/Gruppendatei, sonst die Scan-Wurzel.
begin
  if AProjectOrGroupFile <> '' then
  begin
    Result := ByPath(ExtractFilePath(AProjectOrGroupFile));
  end
  else
  begin
    Result := ByPath(AScanRoot);
  end;
end;

class function TBaselineScope.FromGlobals: TBaselineScope;
begin
  Result.FPathMode := BaselinePathFingerprint;
  Result.FRoot     := BaselineFingerprintRoot;
end;

function TBaselineScope.Effective: Boolean;
begin
  Result := FPathMode and (FRoot <> '');
end;

function TBaselineScope.FileToken(const AFileName: string): string;
// Default: nur der Dateiname (checkout-tolerant). Im Pfad-Modus mit
// gesetzter Wurzel: normalisierter Relativpfad ab der Wurzel
// (lowercase, '/'), damit gleichnamige Dateien in verschiedenen
// Ordnern getrennte Fingerprints bekommen. Wurzel leer oder Datei
// nicht unterhalb -> Fallback Dateiname.
var
  RootLow, FullLow : string;
begin
  Result := LowerCase(ExtractFileName(AFileName));
  if not Effective then
  begin
    Exit;
  end;
  RootLow := LowerCase(StringReplace(
    IncludeTrailingPathDelimiter(ExpandFileName(FRoot)),
    '\', '/', [rfReplaceAll]));
  FullLow := LowerCase(StringReplace(
    ExpandFileName(AFileName), '\', '/', [rfReplaceAll]));
  if Copy(FullLow, 1, Length(RootLow)) = RootLow then
    Result := Copy(FullLow, Length(RootLow) + 1, MaxInt);
end;

// Uebergangs-Wrapper fuer unit-interne Aufrufer, die noch keinen
// Zuschnitt durchreichen. Faellt mit ihnen weg.
function FingerprintFileToken(const AFileName: string): string;
begin
  Result := TBaselineScope.FromGlobals.FileToken(AFileName);
end;

class function TBaseline.Fingerprint(const F: TLeakFinding): string;
begin
  Result := Fingerprint(F, TBaselineScope.FromGlobals);
end;

class function TBaseline.Fingerprint(const F: TLeakFinding;
  const AScope: TBaselineScope): string;
begin
  Result := THashSHA2.GetHashString(
    AScope.FileToken(F.FileName) + '|' + KindName(F.Kind) + '|' +
    F.MethodName + '|' + F.MissingVar);
end;

function BuildBaselineArray(Findings: TObjectList<TLeakFinding>): TJSONArray;
// Baut das findings[]-Array. Lesefehler bleiben BEWUSST draussen: ein
// I/O-Fehler ist kein akzeptierbarer Befund, sondern eine Aussage ueber
// die Vollstaendigkeit des Laufs - Apply filtert ihn symmetrisch ebenfalls.
var
  Obj     : TJSONObject;
  F       : TLeakFinding;
  CtxMemo : TDictionary<string, string>;
begin
  Result := TJSONArray.Create;
  // Perf (2026-07-05): P3 ContextHash-Memo - caller-scoped Memo fuer diesen
  // Write-Lauf (kein Global): identische (Datei,Zeile) wird nur einmal
  // gelesen + gehasht. Hash-Werte bleiben identisch (deterministisch).
  CtxMemo := TDictionary<string, string>.Create;
  try
    if Assigned(Findings) then
      for F in Findings do
      begin
        if F.Kind = fkFileReadError then Continue; // I/O-Fehler nicht baseline'n
        Obj := TJSONObject.Create;
        Obj.AddPair('file',        FingerprintFileToken(F.FileName));
        Obj.AddPair('kind',        KindName(F.Kind));
        Obj.AddPair('method',      F.MethodName);
        Obj.AddPair('detail',      F.MissingVar);
        Obj.AddPair('line',        F.LineNumber);
        Obj.AddPair('fingerprint', TBaseline.Fingerprint(F));
        // C.2: zusaetzlich Code-Snippet-Hash. Leer wenn Datei nicht lesbar -
        // dann faellt Apply auf den legacy fingerprint zurueck.
        var Ctx := TFindingFingerprint.ContextHashMemo(F, CtxMemo);
        if Ctx <> '' then
          Obj.AddPair('contextHash', Ctx);
        Result.AddElement(Obj);
      end;
  finally
    CtxMemo.Free;
  end;
end;

class function TBaseline.Write(Findings: TObjectList<TLeakFinding>;
  const DestFile: string): Integer;
var
  Arr  : TJSONArray;
  Root : TJSONObject;
  SL   : TStringList;
begin
  Result := 0;
  if DestFile = '' then Exit;
  Arr := BuildBaselineArray(Findings);
  // Was wirklich in der Datei landet - NICHT Findings.Count (die
  // Lesefehler sind beim Aufbau uebersprungen worden).
  Result := Arr.Count;

  Root := TJSONObject.Create;
  Root.AddPair('version',     '1');
  // Format-Marker gegen STILLE Vollinvalidierung: liest ein Consumer im
  // anderen Fingerprint-Modus, matcht sonst einfach nichts. Apply
  // erkennt den Mismatch und meldet ihn (AWarnings).
  Root.AddPair('pathFingerprint', TJSONBool.Create(BaselinePathFingerprint));
  Root.AddPair('createdAt',   FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
  Root.AddPair('count',       TJSONNumber.Create(Arr.Count));
  Root.AddPair('findings',    Arr);

  SL := TStringList.Create;
  try
    SL.Text := Root.Format(2);
    EnsureTargetDir(DestFile);
    SaveTextNoBom(SL, DestFile);
  finally
    SL.Free;
    Root.Free; // -> Arr + Objs werden mit befreit
  end;
end;

const
  // Hardening gegen manipulierte Baseline-Dateien:
  //   * MAX_BASELINE_ENTRIES bremst OOM-Angriffe via riesige JSON-Files
  //   * MAX_FINGERPRINT_LEN kappt absurd lange Hash-Strings
  // Werte grosszuegig genug, um realistische Repos zu erfassen (191k
  // Findings sind machbar). Bei Ueberschreitung werden weitere Eintraege
  // ignoriert + Warnung in ErrOutput.
  MAX_BASELINE_ENTRIES = 1_000_000;
  MAX_FINGERPRINT_LEN  = 256;

function TryReadBaselineText(const FileName: string; var AText,
  AReason: string): Boolean;
// Datei einlesen oder den Grund benennen, warum es nicht geht.
begin
  Result  := False;
  AText   := '';
  AReason := '';
  if FileName = '' then
  begin
    AReason := 'no file given';
  end
  else if not FileExists(FileName) then
  begin
    AReason := 'file not found';
  end
  else
  begin
    try
      AText  := TFile.ReadAllText(FileName, TEncoding.UTF8);
      Result := True;
    except
      // noinspection ExceptionTooGeneral
      // Jede Lesefehlerart fuehrt zur selben Antwort ("keine Baseline");
      // die konkrete Ursache steht im Klartext in AReason.
      on E: Exception do
      begin
        AReason := 'unreadable: ' + E.Message;
      end;
    end;
  end;
end;

class function TBaseline.IsBaselineFile(const FileName: string;
  out AReason: string): Boolean;
// Akzeptiert beide Formate, die Apply versteht: Objekt mit 'findings'-
// Array oder das blosse Array (Alt-Format). Alles andere ist keine
// Baseline - mit moeglichst konkreter Begruendung, damit der Nutzer die
// Verwechslung sofort sieht.
var
  Raw  : string;
  Root : TJSONValue;
  Obj  : TJSONObject;
begin
  Result := False;
  if not TryReadBaselineText(FileName, Raw, AReason) then
  begin
    Exit;
  end;
  Root := TJSONObject.ParseJSONValue(Raw);
  if not Assigned(Root) then
  begin
    AReason := 'not valid JSON';
    Exit;
  end;
  try
    if Root is TJSONArray then
    begin
      Result := True;                    // Alt-Format: blosses Array
    end
    else if not (Root is TJSONObject) then
    begin
      AReason := 'JSON root is neither object nor array';
    end
    else
    begin
      Obj := TJSONObject(Root);
      if Obj.Values['findings'] is TJSONArray then
      begin
        Result := True;
      end
      else if Assigned(Obj.Values['runs']) then
      begin
        // Haeufigste Verwechslung beim Namen nennen - ein SARIF-Report
        // sieht einer Baseline auf den ersten Blick aehnlich genug.
        AReason := 'this looks like a SARIF report, not a baseline ' +
                   '(no "findings" array). Baselines are written by ' +
                   '--write-baseline.';
      end
      else
      begin
        AReason := 'no "findings" array - not a baseline written by ' +
                   '--write-baseline';
      end;
    end;
  finally
    Root.Free;
  end;
end;

class function TBaseline.Apply(Findings: TObjectList<TLeakFinding>;
  const BaselineFile: string; AWarnings: TStrings): Integer;
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
  CtxMemo   : TDictionary<string, string>;
  i         : Integer;
  F         : TLeakFinding;
  FCtx      : string;
begin
  Result := 0;
  CtxMemo := nil;
  if (Findings = nil) or (BaselineFile = '') then Exit;
  if not FileExists(BaselineFile) then Exit;

  Raw := TFile.ReadAllText(BaselineFile, TEncoding.UTF8);
  Root := TJSONObject.ParseJSONValue(Raw);
  if Root = nil then Exit;

  FpSet  := TDictionary<string, Boolean>.Create;
  CtxSet := TDictionary<string, Boolean>.Create;
  try
    if Root is TJSONObject then
    begin
      // Fingerprint-Modus-Marker pruefen: Datei im anderen Modus
      // geschrieben -> die Legacy-Fingerprints koennen nicht matchen.
      var MarkerVal := TJSONObject(Root).Values['pathFingerprint'];
      if (MarkerVal is TJSONBool) and Assigned(AWarnings) and
         (TJSONBool(MarkerVal).AsBoolean <> BaselinePathFingerprint) then
        AWarnings.Add(Format(
          'baseline fingerprint mode mismatch: file written with ' +
          'PathInFingerprint=%s, current setting is %s - legacy ' +
          'fingerprints will not match (only contextHash still applies)',
          [BoolToStr(TJSONBool(MarkerVal).AsBoolean, True),
           BoolToStr(BaselinePathFingerprint, True)]));
      // Weicher Cast: 'findings' kann fehlen (Values liefert nil) ODER falsch
      // typisiert sein (manuell editiert / Merge-Konflikt: "findings": {}).
      // Hartes 'as TJSONArray' wuerfe dann EInvalidCast und deaktivierte die
      // Baseline still komplett - stattdessen als "kein Array" behandeln.
      var FindingsVal := TJSONObject(Root).Values['findings'];
      if FindingsVal is TJSONArray then
        Arr := TJSONArray(FindingsVal)
      else
        Arr := nil;
    end
    else if Root is TJSONArray then
      Arr := TJSONArray(Root)            // Alt-Format: rein das Array
    else
      Arr := nil;

    if Arr <> nil then
    begin
      var Loaded := 0;
      var Truncated := False;
      for Obj in Arr do
      begin
        if Loaded >= MAX_BASELINE_ENTRIES then
        begin
          Truncated := True;
          Break;
        end;
        if not (Obj is TJSONObject) then Continue;
        Inc(Loaded);
        FpJson := TJSONObject(Obj).Values['fingerprint'];
        if (FpJson <> nil) and not FpJson.Null
           and (Length(FpJson.Value) <= MAX_FINGERPRINT_LEN) then
          FpSet.AddOrSetValue(FpJson.Value, True);
        CtxJson := TJSONObject(Obj).Values['contextHash'];
        if (CtxJson <> nil) and not CtxJson.Null
           and (CtxJson.Value <> '')
           and (Length(CtxJson.Value) <= MAX_FINGERPRINT_LEN) then
          CtxSet.AddOrSetValue(CtxJson.Value, True);
      end;
      if Truncated then
        try
          WriteLn(ErrOutput, Format(
            'Baseline warning: file %s has more than %d entries - '
            + 'subsequent entries ignored (truncated). Hardening cap, '
            + 'see MAX_BASELINE_ENTRIES in uBaseline.pas.',
            [BaselineFile, MAX_BASELINE_ENTRIES]));
        except
          // stdout/stderr nicht erreichbar (GUI ohne AttachConsole) -
          // silent OK, Hardening greift trotzdem.
        end;
    end;

    // Rueckwaerts iterieren wegen Delete.
    // Perf: ContextHash nur berechnen wenn die Baseline ueberhaupt
    // contextHash-Eintraege hat. Bei Legacy-Baselines (nur fingerprint)
    // spart das ein SHA256 + File-Read pro Finding (= ~191k vermiedene
    // Operationen bei einem Real-World-Scan).
    // Perf (2026-07-05): P3 ContextHash-Memo - zusaetzlich wird innerhalb
    // dieses Apply-Laufs jede (Datei,Zeile) nur einmal gehasht (CtxMemo,
    // caller-scoped, im finally freigegeben).
    var HasCtx: Boolean := CtxSet.Count > 0;
    if HasCtx then
      CtxMemo := TDictionary<string, string>.Create;
    for i := Findings.Count - 1 downto 0 do
    begin
      F := Findings[i];
      if F.Kind = fkFileReadError then Continue;
      if HasCtx then
        FCtx := TFindingFingerprint.ContextHashMemo(F, CtxMemo)
      else
        FCtx := '';
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
    CtxMemo.Free;
    Root.Free;
  end;
end;

{ TBaselineSet }

constructor TBaselineSet.Create;
begin
  inherited Create;
  FFingerprints := TDictionary<string, Boolean>.Create;
end;

destructor TBaselineSet.Destroy;
begin
  FFingerprints.Free;
  inherited;
end;

procedure TBaselineSet.Clear;
begin
  FFingerprints.Clear;
end;

function TBaselineSet.IsEmpty: Boolean;
begin
  Result := FFingerprints.Count = 0;
end;

function TBaselineSet.Contains(const F: TLeakFinding): Boolean;
begin
  // Lesefehler sind nie baseline-faehig - dieselbe Regel, die Write (:209)
  // und Apply (:459) schon befolgen. Dem ANZEIGE-Filter in EXE und Plugin
  // fehlte sie bis 2026-08-08: eine handgepflegte oder aeltere Baseline mit
  // einem FileReadError-Fingerprint konnte dort einen unlesbaren Dateipfad
  // ausblenden, waehrend die CLI ihn weiter meldete. Ein Lauf, der Dateien
  // nicht lesen konnte, darf nirgends vollstaendig aussehen.
  if F.Kind = fkFileReadError then Exit(False);
  // Count-Guard spart bei leerem Set (Filter aus / Datei fehlt) das SHA2-
  // Hashing pro Finding im heissen ApplyFilter-Loop.
  Result := (FFingerprints.Count > 0)
            and FFingerprints.ContainsKey(TBaseline.Fingerprint(F));
end;

function TBaselineSet.LoadFromFile(const BaselineFile: string): Integer;
// Parst dieselbe Struktur wie TBaseline.Apply (Objekt-mit-'findings' ODER bare
// Array) + dieselben Hardening-Caps, aber non-destruktiv: sammelt nur die
// Fingerprints. Bewusst als eigener Parse gehalten statt Apply umzubauen -
// Apply ist der verifizierte CI-Gating-Pfad und bleibt byte-neutral.
var
  Raw    : string;
  Root   : TJSONValue;
  Arr    : TJSONArray;
  Obj    : TJSONValue;
  FpJson : TJSONValue;
  Loaded : Integer;
begin
  FFingerprints.Clear;
  Result := 0;
  if BaselineFile = '' then Exit;
  if not FileExists(BaselineFile) then Exit;

  try
    Raw := TFile.ReadAllText(BaselineFile, TEncoding.UTF8);
  except
    Exit;   // nicht lesbar -> leeres Set (kein Fehler)
  end;
  Root := TJSONObject.ParseJSONValue(Raw);
  if Root = nil then Exit;
  try
    if Root is TJSONObject then
    begin
      var FindingsVal := TJSONObject(Root).Values['findings'];
      if FindingsVal is TJSONArray then
        Arr := TJSONArray(FindingsVal)
      else
        Arr := nil;
    end
    else if Root is TJSONArray then
      Arr := TJSONArray(Root)
    else
      Arr := nil;

    if Arr <> nil then
    begin
      Loaded := 0;
      for Obj in Arr do
      begin
        if Loaded >= MAX_BASELINE_ENTRIES then Break;
        if not (Obj is TJSONObject) then Continue;
        Inc(Loaded);
        FpJson := TJSONObject(Obj).Values['fingerprint'];
        if (FpJson <> nil) and not FpJson.Null
           and (Length(FpJson.Value) <= MAX_FINGERPRINT_LEN) then
          FFingerprints.AddOrSetValue(FpJson.Value, True);
      end;
    end;
  finally
    Root.Free;
  end;
  Result := FFingerprints.Count;
end;

const
  SCA_DIR      = '.sca';
  BASELINE_EXT = '.baseline.json';

// Kandidat pruefen + fuer die Fehlermeldung protokollieren.
function ProbeBaselineCandidate(const Candidate: string;
  AProbed: TStrings): Boolean;
begin
  if Assigned(AProbed) then
    AProbed.Add(Candidate);
  Result := FileExists(Candidate);
end;

class function TBaseline.ResolveBaselinePath(const AProjectOrGroupFile,
  AScanRoot: string; AProbed: TStrings): string;
var
  Dir, BaseName, Cand : string;
begin
  Result := '';
  if AProjectOrGroupFile <> '' then
  begin
    Dir      := ExtractFilePath(ExpandFileName(AProjectOrGroupFile));
    BaseName := ChangeFileExt(ExtractFileName(AProjectOrGroupFile), '');
    Cand := Dir + SCA_DIR + PathDelim + BaseName + BASELINE_EXT;
    if ProbeBaselineCandidate(Cand, AProbed) then Exit(Cand);
    // Projekt-Fallback: zentrale Gruppen-.sca eine Ebene hoeher.
    if SameText(ExtractFileExt(AProjectOrGroupFile), '.dproj') then
    begin
      Cand := ExpandFileName(Dir + '..' + PathDelim + '.sca' + PathDelim +
        BaseName + '.baseline.json');
      if ProbeBaselineCandidate(Cand, AProbed) then Exit(Cand);
    end;
    Exit;
  end;
  if AScanRoot <> '' then
  begin
    Cand := IncludeTrailingPathDelimiter(ExpandFileName(AScanRoot)) +
      SCA_DIR + PathDelim + 'sca' + BASELINE_EXT;
    if ProbeBaselineCandidate(Cand, AProbed) then Exit(Cand);
  end;
end;

class function TBaseline.DefaultBaselineTarget(const AProjectOrGroupFile,
  AScanRoot: string): string;
begin
  Result := '';
  if AProjectOrGroupFile <> '' then
    Result := ExtractFilePath(ExpandFileName(AProjectOrGroupFile)) +
      SCA_DIR + PathDelim +
      ChangeFileExt(ExtractFileName(AProjectOrGroupFile), '') +
      BASELINE_EXT
  else if AScanRoot <> '' then
    Result := IncludeTrailingPathDelimiter(ExpandFileName(AScanRoot)) +
      SCA_DIR + PathDelim + 'sca' + BASELINE_EXT;
end;

end.
