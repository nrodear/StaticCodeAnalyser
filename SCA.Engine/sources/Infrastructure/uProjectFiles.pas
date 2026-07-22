unit uProjectFiles;

// Scan-Scope-Variation (Konzept_ScanScope_2026-07-20): loest .dproj- und
// .groupproj-Dateien in die Liste der zu scannenden .pas-Dateien auf.
//
// Design-Entscheidungen (siehe Konzept §3.1):
//   * MSBuild-XML via IXMLDocument (Xml.XMLDoc) - kein Regex-Scraping,
//     Includes koennen XML-Escapes enthalten. Traversal ueber ChildNodes +
//     LocalName-Vergleich, damit der MSBuild-Namespace
//     (xmlns="http://schemas.microsoft.com/developer/msbuild/2003") egal ist.
//   * Nur explizite <DCCReference Include="*.pas">-Eintraege zaehlen - exakt
//     das, was das Projekt kompiliert. Search-Path-/uses-Schliessung ist
//     bewusst NICHT Scope (Konzept-Limitation v1). .dpk-Packages listen ihre
//     Units ebenfalls als DCCReference in der .dproj - der .dpk-Fall laeuft
//     also ueber dieselbe .dproj-Schiene.
//   * Tolerant wie der Verzeichnis-Walk: fehlende Dateien und unaufloesbare
//     $(Makro)-Includes werden als Warnung gemeldet und geskippt, der Scan
//     laeuft weiter. AErrorMsg nur, wenn die Datei selbst unlesbar/kaputt ist
//     (bzw. bei Gruppen: wenn KEIN Projekt aufloesbar war).
//   * COM-Guard: MSXML braucht CoInitialize im rufenden Thread. Der Guard
//     ist lokal und tolerant gegen bereits initialisierte Threads
//     (S_FALSE -> Host besitzt COM, NICHT uninitialisieren; RPC_E_CHANGED_MODE ->
//     Thread ist schon anders initialisiert, NICHT uninitialisieren).
//     Damit ist die Unit sowohl im CLI-Main-Thread als auch in kuenftigen
//     Worker-Threads (Plugin Phase 4) nutzbar.

interface

uses
  System.SysUtils, System.Classes;

type
  TProjectFiles = class
  public
    // .dproj -> absolute, deduplizierte .pas-Liste. Caller besitzt Result
    // (auch im Fehlerfall wird eine - dann leere - Liste geliefert).
    // AWarnings (optional): fehlende Dateien / geskippte Makro-Includes.
    class function FromDproj(const ADprojFile: string;
      out AErrorMsg: string; AWarnings: TStrings = nil): TStringList; static;

    // .groupproj -> Union der Projekt-Listen, case-insensitiv dedupliziert
    // (shared Units nur 1x). Einzelne kaputte Projekte -> Warnung; Fehler
    // nur wenn gar nichts aufloesbar war.
    class function FromGroupproj(const AGroupFile: string;
      out AErrorMsg: string; AWarnings: TStrings = nil): TStringList; static;
  end;

implementation

// noinspection-file NestedTry, TooLongLine

uses
  System.IOUtils, System.Variants,
  Winapi.ActiveX,
  Xml.XMLDoc, Xml.XMLIntf;

type
  // COM-Init-Guard (siehe Unit-Header). Init stellt sicher, dass COM auf dem
  // Thread oben ist; Done ist bewusst ein NO-OP.
  //
  // WARUM NIE CoUninitialize (AV-Fix 2026-07-22): dieser Helper laeuft in
  // Hosts, die COM selbst nutzen (VCL-GUI, TestInsight/DUnitX-Runner via
  // IPC, IDE-Plugin/ToolsAPI). CoUninitialize per From*-Aufruf reisst - bei
  // wiederholten Aufrufen (Testsuite: 12x FromDproj) oder wenn der Host COM
  // zwischen Aufrufen nutzt - die COM-Apartment ab -> AccessViolation in
  // fremdem Code (TestProject.exe c0000005). COM einmal hochziehen und bis
  // Prozessende oben lassen ist fuer Library-Helper das robuste Muster; die
  // eine Init-Ref gibt das OS beim Prozessende ohnehin frei. RPC_E_CHANGED_MODE
  // (Host im anderen Apartment-Modus) ist egal - MSXML/IXMLDocument arbeiten
  // in beiden Modi.
  TComGuard = record
    procedure Init;
    procedure Done;
  end;

procedure TComGuard.Init;
begin
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);   // Ergebnis bewusst ignoriert
end;

procedure TComGuard.Done;
begin
  // Bewusst NO-OP: COM bleibt fuer die Prozess-Lebensdauer oben (siehe
  // TComGuard-Kommentar) - nie per-Aufruf abbauen.
end;

function ResolveInclude(const ABaseDir, AInclude: string;
  AWarnings: TStrings; out AResolved: string): Boolean;
// Include-Attribut -> absoluter Pfad. False = skippen (mit Warnung).
var
  Raw : string;
begin
  Result    := False;
  AResolved := '';
  Raw := Trim(AInclude);
  if Raw = '' then Exit;
  // MSBuild-Makros koennen wir ohne Property-Evaluation nicht aufloesen -
  // Warnung + Skip (Konzept-Limitation v1; bei DCCReference unueblich).
  if Pos('$(', Raw) > 0 then
  begin
    if Assigned(AWarnings) then
      AWarnings.Add(Format('Include mit MSBuild-Makro uebersprungen: %s', [Raw]));
    Exit;
  end;
  // MSBuild nutzt '\' wie Windows; '/' defensiv mitnehmen.
  Raw := Raw.Replace('/', '\');
  if TPath.IsRelativePath(Raw) then
    Raw := TPath.Combine(ABaseDir, Raw);
  // GetFullPath loest '..'-Segmente auf und normalisiert Separatoren.
  try
    AResolved := TPath.GetFullPath(Raw);
  except
    on E: Exception do
    begin
      if Assigned(AWarnings) then
        AWarnings.Add(Format('Include nicht aufloesbar (%s): %s',
          [E.Message, AInclude]));
      Exit;
    end;
  end;
  Result := True;
end;

procedure CollectIncludes(const ANode: IXMLNode; const AElementLocalName: string;
  AInto: TStrings);
// Sammelt rekursiv alle Include-Attribute von Elementen mit dem gegebenen
// LocalName (DCCReference bzw. Projects). Rekursiv statt ItemGroup-fixiert:
// MSBuild erlaubt die Items in beliebigen/verschachtelten Gruppen.
var
  i     : Integer;
  Child : IXMLNode;
begin
  if ANode = nil then Exit;
  for i := 0 to ANode.ChildNodes.Count - 1 do
  begin
    Child := ANode.ChildNodes[i];
    if Child.NodeType <> ntElement then Continue;
    if SameText(Child.LocalName, AElementLocalName) and
       Child.HasAttribute('Include') then
      AInto.Add(VarToStr(Child.Attributes['Include']))
    else
      CollectIncludes(Child, AElementLocalName, AInto);
  end;
end;

function LoadIncludes(const AXmlFile, AElementLocalName: string;
  out AErrorMsg: string): TStringList;
// Gemeinsamer XML-Teil von FromDproj/FromGroupproj: Datei laden, alle
// Include-Attribute der Ziel-Elemente einsammeln. nil bei Lade-/Parse-Fehler.
var
  Com : TComGuard;
  Doc : IXMLDocument;
begin
  Result    := nil;
  AErrorMsg := '';
  if not FileExists(AXmlFile) then
  begin
    AErrorMsg := Format('Datei nicht gefunden: %s', [AXmlFile]);
    Exit;
  end;
  Com.Init;
  try
    try
      Doc := LoadXMLDocument(AXmlFile);
      Result := TStringList.Create;
      CollectIncludes(Doc.DocumentElement, AElementLocalName, Result);
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        AErrorMsg := Format('%s nicht lesbar: %s', [AXmlFile, E.Message]);
      end;
    end;
  finally
    // Doc-Interface hier freigeben (COM-Objekt haengt am Apartment); Com.Done
    // ist ein No-op (COM bleibt prozessweit oben, s. TComGuard-Kommentar).
    Doc := nil;
    Com.Done;
  end;
end;

class function TProjectFiles.FromDproj(const ADprojFile: string;
  out AErrorMsg: string; AWarnings: TStrings): TStringList;
var
  Includes : TStringList;
  Seen     : TStringList;
  BaseDir  : string;
  Inc0     : string;
  Full     : string;
begin
  Result := TStringList.Create;
  Includes := LoadIncludes(ADprojFile, 'DCCReference', AErrorMsg);
  if Includes = nil then Exit;   // AErrorMsg gesetzt, leere Liste zurueck

  Seen := TStringList.Create;
  Seen.CaseSensitive := False;
  Seen.Sorted := True;
  Seen.Duplicates := dupIgnore;
  try
    BaseDir := ExtractFilePath(TPath.GetFullPath(ADprojFile));
    for Inc0 in Includes do
    begin
      // Nur Pascal-Quellen; DCCReference listet auch .dcu-/Lib-Referenzen.
      if not SameText(ExtractFileExt(Inc0), '.pas') then Continue;
      if not ResolveInclude(BaseDir, Inc0, AWarnings, Full) then Continue;
      if Seen.IndexOf(Full) >= 0 then Continue;   // Dedup (case-insensitiv)
      Seen.Add(Full);
      if not FileExists(Full) then
      begin
        if Assigned(AWarnings) then
          AWarnings.Add(Format('Referenzierte Datei fehlt: %s', [Full]));
        Continue;
      end;
      Result.Add(Full);
    end;
  finally
    Seen.Free;
    Includes.Free;
  end;
end;

class function TProjectFiles.FromGroupproj(const AGroupFile: string;
  out AErrorMsg: string; AWarnings: TStrings): TStringList;
var
  Projects  : TStringList;
  Seen      : TStringList;
  BaseDir   : string;
  ProjRef   : string;
  ProjFull  : string;
  ProjErr   : string;
  ProjFiles : TStringList;
  F         : string;
  OkCount   : Integer;
begin
  Result := TStringList.Create;
  Projects := LoadIncludes(AGroupFile, 'Projects', AErrorMsg);
  if Projects = nil then Exit;

  Seen := TStringList.Create;
  Seen.CaseSensitive := False;
  Seen.Sorted := True;
  Seen.Duplicates := dupIgnore;
  try
    BaseDir := ExtractFilePath(TPath.GetFullPath(AGroupFile));
    OkCount := 0;
    for ProjRef in Projects do
    begin
      if not SameText(ExtractFileExt(ProjRef), '.dproj') then Continue;
      if not ResolveInclude(BaseDir, ProjRef, AWarnings, ProjFull) then Continue;
      ProjFiles := FromDproj(ProjFull, ProjErr, AWarnings);
      try
        if ProjErr <> '' then
        begin
          if Assigned(AWarnings) then
            AWarnings.Add(Format('Projekt uebersprungen: %s', [ProjErr]));
          Continue;
        end;
        Inc(OkCount);
        for F in ProjFiles do
          if Seen.IndexOf(F) < 0 then
          begin
            Seen.Add(F);        // Union-Dedup: shared Units nur 1x
            Result.Add(F);
          end;
      finally
        ProjFiles.Free;
      end;
    end;
    if (OkCount = 0) and (Projects.Count > 0) then
      AErrorMsg := Format(
        'Kein Projekt der Gruppe aufloesbar: %s', [AGroupFile]);
  finally
    Seen.Free;
    Projects.Free;
  end;
end;

end.
