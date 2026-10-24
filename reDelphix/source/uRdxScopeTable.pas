unit uRdxScopeTable;

// reDelphix - Scope-Tabelle: Kurzname einer Unit -> qualifizierter Name
// (SysUtils -> System.SysUtils). Datenseite des Rezepts 5.3 "uses
// expandieren" (Konzept_SourceRefactor_Quellstellen, Entscheidung Nico
// 2026-10-03: Datendatei im Modul).
//
// WOHER DIE DATEN KOMMEN
//
// data\unitscopes.txt, erzeugt von tools\gen_unitscopes.py aus der
// lokalen Delphi-Installation: alle Units unter den Unit-Scope-Praefixen
// eines Win32-VCL-/FMX-Projekts. Die Datei wird als Ressource UNITSCOPES
// in die BPL gelinkt (data\unitscopes.rc); liegt eine Datei gleichen
// Namens neben der BPL, gewinnt die Datei - so laesst sich die Tabelle
// ohne Bau austauschen.
//
// WARUM DIE AUFLOESUNG NICHT TRIVIAL IST
//
// 'Forms' heisst Vcl.Forms ODER FMX.Forms, 'Types' System.Types ODER
// FMX.Types. Der Compiler entscheidet ueber die Unit-Scope-Liste des
// Projekts (DCC_Namespace), in ihrer REIHENFOLGE. Das Modul kennt die
// Projektoptionen nicht und bildet deshalb die Vorgabe-Listen nach:
// erst die gemeinsamen Praefixe (Winapi, System.Win, ..., System, Xml,
// Data, ...), dann Vcl.* bzw. FMX - je nach Rahmenwerk der DATEI
// (TRdxRecipes.DetectFramework). Ist das Rahmenwerk nicht erkennbar und
// der Kurzname mehrdeutig, wird NICHT geraten: Resolve liefert False
// mit Grund, der Menuepunkt bleibt ausgegraut.
//
// Die Vorgabe-Reihenfolge ist nicht die einzige: die SDI-/MDI-Vorlagen
// von Delphi 12 (ObjRepos\...\SDIApp, MDIApp) setzen Vcl VOR System.
// Steht ein Vcl.*-Kandidat neben einem unter System/Xml/Data/Datasnap/
// Web/Soap (ohne '.Win' - die stehen in beiden Listen vorn; heute nur
// 'skia' = FMX.Skia;System.Skia;Vcl.Skia), entscheidet allein die
// DCC_Namespace des Projekts. Ausser in einer FMX-Datei (kein Vcl in der
// Liste) wird dann nicht geraten (Review 2026-10-07, Minor 14).
//
// DIE GEGENPROBE
//
// Kennt das Projekt selbst eine Unit des Kurznamens, wird nicht
// qualifiziert: TRdxProjectUnits (unten) ist der Index dafuer, gefuellt
// von uRdxEditor.ProjectUnits (Review R1-02).

interface

uses
  System.Classes, System.Generics.Collections,
  uRdxRecipes;

const
  SCOPE_RESOURCE_NAME = 'UNITSCOPES';
  SCOPE_FILE_NAME     = 'unitscopes.txt';

type
  TRdxScopeTable = class
  private
    FMap    : TDictionary<string, TArray<string>>;   // Kurzname (klein) -> qualifizierte Namen
    FSource : string;
    function TryOrder(const ACandidates: TArray<string>;
      const AOrder: array of string; out AQualified: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // Leert die Tabelle und vergisst die Quelle (Source = '').
    procedure Clear;
    // Zeilen 'kurzname=Qualifiziert1;Qualifiziert2', '#' = Kommentar.
    // Doppelte Namen (nur Gross/Klein verschieden) fallen zusammen.
    procedure LoadFromStrings(AStrings: TStrings);
    // Liest die Datei AFileName (LoadFromStrings) und merkt sie als Source.
    // False, wenn es sie nicht gibt, sie nicht lesbar oder falsch kodiert
    // ist oder keinen Eintrag traegt - LoadDefault nimmt dann die naechste
    // Quelle.
    function LoadFromFile(const AFileName: string): Boolean;
    // RCDATA-Ressource AResName aus dem eigenen Modul (HInstance).
    function LoadFromResource(const AResName: string): Boolean;
    // Standardquelle: Datei neben der BPL (auch .\data und ..\data),
    // sonst die eingelinkte Ressource. False, wenn nichts davon da ist.
    function LoadDefault: Boolean;

    // Zahl der Kurznamen in der Tabelle; 0 = nichts geladen.
    function Count: Integer;
    // Die qualifizierten Namen zum Kurznamen (gross/klein und Leerraum
    // egal) in der Reihenfolge der Datei; nil, wenn die Tabelle ihn nicht
    // kennt.
    function Candidates(const AShortName: string): TArray<string>;
    // Aufloesung nach der Scope-Reihenfolge des Rahmenwerks (s. Kopf).
    // False mit Grund: schon qualifiziert, unbekannt, mehrdeutig ohne
    // erkennbares Rahmenwerk, System.* gegen Vcl.* (DCC_Namespace).
    function Resolve(const AShortName: string; AFramework: TRdxFramework;
      out AQualified, AReason: string): Boolean;

    // Woher die Tabelle geladen wurde (Diagnose), leer = nichts geladen.
    property Source: string read FSource;
  end;

  // Die Kurznamen, die das PROJEKT selbst fuehren kann - die Gegenprobe zur
  // Scope-Tabelle fuer 'uses: X -> Scope.X': eine Projekt-Unit 'Types' darf
  // nicht zu System.Types werden (Review nach Bereichen 2026-10-10, Minor
  // 18). uRdxEditor.ProjectUnits fuellt den Index einmal je Aufruf der
  // uses-Hilfe - je Fund auf einer uses-Zeile; ein Menue mit mehreren
  // solchen Funden baut ihn je Fund neu (Verzeichnis der Datei, Module
  // aller Projekte der Gruppe, deren Unit-Suchpfad). Die Frage je uses-
  // Eintrag ist danach ein Nachschlagen plus je Verzeichnis zwei
  // FileExists. Bis Review R1-02 lief dafuer je Eintrag die ganze
  // Projektgruppe ueber die ToolsAPI, auch fuer die Gluehbirne.
  // NETZPFADE (UNC und Netzlaufwerke, uRdxPaths.IsNetworkPath - dieselbe
  // Regel wie SCA014/SCA164/SCA147; bis Charge B2S-a prueften hier nur UNC
  // und ein Netzlaufwerk ueber die Naht IsRemote, die uRdxEditor setzte)
  // liest der Index nicht: der Menueaufbau laeuft im Hauptthread, ein nicht
  // erreichbarer Server kostete je FileExists Sekunden. Liegt ein
  // Verzeichnis dort, ist jede Antwort offen - Knows sagt dann immer True
  // (kein Angebot), UnreadableReason den Grund.
  TRdxProjectUnits = class
  private
    FModules    : TStringList;    // Kurznamen der Projektmodule, ohne Doppel
    FDirs       : TStringList;    // gelesene Verzeichnisse, mit Trenner am Ende
    FUnreadable : string;         // erstes nicht gelesenes Verzeichnis
  public
    constructor Create;
    destructor Destroy; override;
    // Ein Modul eines Projekts (Dateiname, mit oder ohne Pfad und Endung).
    procedure AddModule(const AFileName: string);
    // Ein Verzeichnis, in dem eine Unit des Projekts liegen kann (absolut).
    // Ein Netzpfad wird nicht gelesen, sondern als Unreadable gemerkt.
    procedure AddDir(const ADir: string);
    // Ein Unit-Suchpfad ('a;..\b;$(BDS)\lib') relativ zu ABaseDir: jedes
    // Verzeichnis ueber AddDir. Eintraege mit Makros ($(..)) bleiben aussen
    // vor (Grenze: s. uRdxEditor.ProjectUnits).
    procedure AddSearchPath(const ASearchPath, ABaseDir: string);
    // True: das Projekt kann eine Unit AShortName haben - ein Modul dieses
    // Namens, AShortName.pas oder .pp in einem gelesenen Verzeichnis, oder
    // ein Verzeichnis blieb ungelesen (dann offen, s. oben). '' = False.
    function Knows(const AShortName: string): Boolean;
    // Der Grund zu Unreadable, in der reDelphix-Sprache wie die Gruende
    // der Scope-Tabelle (uRdxText, E29); '' ohne ungelesenes Verzeichnis.
    function UnreadableReason: string;
    // Das erste ungelesene Verzeichnis (Netzpfad); '' = alles gelesen.
    property Unreadable: string read FUnreadable;
  end;

implementation

uses
  // System.SysUtils nur hier: die Schnittstelle braucht keinen seiner
  // Namen (bis Charge B2S im interface-uses, Gegenpruefung V2-B2S-3). Vor
  // uRdxPaths: ein gleicher Name kommt weiter von dort. Delphi: kein hier
  // benutzter Name steht zugleich in SysUtils und in System.Classes,
  // System.Generics.Collections oder uRdxRecipes - die Aufloesung bleibt.
  // FPC (Pruefstand) deklariert TArray<T> auch in SysUtils: die
  // Schnittstelle nimmt es dort jetzt aus ObjPas - derselbe Code.
  System.SysUtils,
  uRdxPaths,   // IsNetworkPath, HasUncLead
  uRdxText;    // _(), MsgByHand: Gruende in der reDelphix-Sprache (E29)

const
  // Unit-Scope-Vorgabe eines Win32-Projekts, in Compiler-Reihenfolge.
  COMMON_ORDER: array[0..13] of string = (
    'winapi', 'system.win', 'data.win', 'datasnap.win', 'web.win',
    'soap.win', 'xml.win', 'bde', 'system', 'xml', 'data', 'datasnap',
    'web', 'soap');
  VCL_ORDER: array[0..4] of string = (
    'vcl', 'vcl.imaging', 'vcl.touch', 'vcl.samples', 'vcl.shell');
  FMX_ORDER: array[0..0] of string = ('fmx');
  // Gemeinsame Praefixe OHNE '.Win': in der Vorgabe vor Vcl, in den
  // SDI-/MDI-Vorlagen dahinter (s. Kopf).
  SYSTEM_GROUP: array[0..5] of string = (
    'system', 'xml', 'data', 'datasnap', 'web', 'soap');

function PrefixOf(const AQualified: string): string;
var
  P : Integer;
begin
  P := LastDelimiter('.', AQualified);
  if P = 0 then
    Result := ''
  else
    Result := LowerCase(Copy(AQualified, 1, P - 1));
end;

// True, wenn ein Kandidat unter einem der Praefixe steht.
function HasPrefixIn(const ACandidates: TArray<string>;
  const APrefixes: array of string): Boolean;
var
  i, k : Integer;
begin
  Result := False;
  for k := 0 to High(ACandidates) do
    for i := Low(APrefixes) to High(APrefixes) do
      if PrefixOf(ACandidates[k]) = APrefixes[i] then
        Exit(True);
end;

function JoinNames(const ANames: TArray<string>): string;
var
  Sep : string;
  i   : Integer;
begin
  Result := '';
  Sep := '';
  for i := 0 to High(ANames) do
  begin
    // Ein Grundtext aus den Kandidaten EINES Kurznamens - in
    // unitscopes.txt hoechstens drei; ein TStringBuilder lohnte nicht.
    // noinspection StringConcatInLoop
    Result := Result + Sep + ANames[i];
    Sep := ', ';
  end;
end;

// AName an ANames[0..ACount-1] anhaengen, wenn nicht leer und noch nicht
// da (gross/klein egal); ANames ist gross genug angelegt.
procedure AddUnique(var ANames: TArray<string>; var ACount: Integer;
  const AName: string);
var
  j : Integer;
begin
  if AName = '' then Exit;
  for j := 0 to ACount - 1 do
    if SameText(ANames[j], AName) then Exit;
  ANames[ACount] := AName;
  Inc(ACount);
end;

// Eine Zeile 'kurzname=Qualifiziert1;Qualifiziert2' der Tabelle: True mit
// dem Kurznamen (klein) und den Namen ohne Doppel; False fuer Leerzeile,
// Kommentar ('#'), Zeile ohne '=' oder ohne Namen. AParts ist die
// Trennliste des Aufrufers (';', StrictDelimiter). Bis Review R1-05 der
// Rumpf der Schleife in LoadFromStrings (SCA176 27).
function ParseScopeLine(const ALine: string; AParts: TStringList;
  out AShort: string; out ANames: TArray<string>): Boolean;
var
  Line, Rest : string;
  P, k, n    : Integer;
begin
  Result := False;
  AShort := '';
  ANames := nil;
  Line := Trim(ALine);
  if (Line = '') or (Line[1] = '#') then Exit;
  P := Pos('=', Line);
  if P <= 1 then Exit;
  AShort := LowerCase(Trim(Copy(Line, 1, P - 1)));
  Rest   := Trim(Copy(Line, P + 1, MaxInt));
  if (AShort = '') or (Rest = '') then Exit;
  AParts.DelimitedText := Rest;
  // Hoechstens so viele Namen wie Teile: einmal anlegen, am Ende kuerzen
  // (SCA157 - vorher wuchs das Feld je Name).
  SetLength(ANames, AParts.Count);
  n := 0;
  for k := 0 to AParts.Count - 1 do
    AddUnique(ANames, n, Trim(AParts[k]));
  SetLength(ANames, n);
  Result := n > 0;
end;

{ TRdxScopeTable }

constructor TRdxScopeTable.Create;
begin
  inherited Create;
  FMap := TDictionary<string, TArray<string>>.Create;
end;

destructor TRdxScopeTable.Destroy;
begin
  FMap.Free;
  inherited;
end;

procedure TRdxScopeTable.Clear;
begin
  FMap.Clear;
  FSource := '';
end;

procedure TRdxScopeTable.LoadFromStrings(AStrings: TStrings);
var
  i     : Integer;
  Short : string;
  Names : TArray<string>;
  Parts : TStringList;
begin
  Clear;
  if not Assigned(AStrings) then Exit;
  Parts := TStringList.Create;
  try
    Parts.Delimiter       := ';';
    Parts.StrictDelimiter := True;
    for i := 0 to AStrings.Count - 1 do
      if ParseScopeLine(AStrings[i], Parts, Short, Names) then
        FMap.AddOrSetValue(Short, Names);
  finally
    Parts.Free;
  end;
end;

function TRdxScopeTable.LoadFromFile(const AFileName: string): Boolean;
var
  SL : TStringList;
begin
  Result := False;
  if not FileExists(AFileName) then Exit;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(AFileName);
    except
      // Nicht lesbar oder falsch kodiert: der Aufrufer faellt auf die
      // eingelinkte Ressource zurueck. Alles andere laeuft weiter.
      on EFOpenError do Exit;
      on EInOutError do Exit;
      on EEncodingError do Exit;
    end;
    LoadFromStrings(SL);
    FSource := AFileName;
    Result := Count > 0;
  finally
    SL.Free;
  end;
end;

function TRdxScopeTable.LoadFromResource(const AResName: string): Boolean;
var
  RS : TResourceStream;
  SL : TStringList;
begin
  Result := False;
  try
    // RT_RCDATA = MAKEINTRESOURCE(10), ohne Windows-Unit ausgedrueckt.
    // FPC erwartet hier PAnsiChar, Delphi PChar (= PWideChar).
    {$IFDEF FPC}
    RS := TResourceStream.Create(HInstance, AResName, PAnsiChar(10));
    {$ELSE}
    RS := TResourceStream.Create(HInstance, AResName, PChar(10));
    {$ENDIF}
  except
    on EResNotFound do Exit;   // Ressource nicht vorhanden
  end;
  try
    SL := TStringList.Create;
    try
      SL.LoadFromStream(RS);
      LoadFromStrings(SL);
      FSource := 'resource:' + AResName;
      Result := Count > 0;
    finally
      SL.Free;
    end;
  finally
    RS.Free;
  end;
end;

function TRdxScopeTable.LoadDefault: Boolean;
var
  Dir : string;
begin
  Dir := ExtractFilePath(GetModuleName(HInstance));
  Result := LoadFromFile(Dir + SCOPE_FILE_NAME)
    or LoadFromFile(Dir + 'data' + PathDelim + SCOPE_FILE_NAME)
    or LoadFromFile(ExpandFileName(Dir + '..' + PathDelim + 'data'
         + PathDelim + SCOPE_FILE_NAME))
    or LoadFromResource(SCOPE_RESOURCE_NAME);
end;

function TRdxScopeTable.Count: Integer;
begin
  Result := FMap.Count;
end;

function TRdxScopeTable.Candidates(const AShortName: string): TArray<string>;
begin
  if not FMap.TryGetValue(LowerCase(Trim(AShortName)), Result) then
    Result := nil;
end;

function TRdxScopeTable.TryOrder(const ACandidates: TArray<string>;
  const AOrder: array of string; out AQualified: string): Boolean;
var
  i, k : Integer;
begin
  Result := False;
  AQualified := '';
  for i := Low(AOrder) to High(AOrder) do
    for k := 0 to High(ACandidates) do
      if PrefixOf(ACandidates[k]) = AOrder[i] then
      begin
        AQualified := ACandidates[k];
        Exit(True);
      end;
end;

function TRdxScopeTable.Resolve(const AShortName: string;
  AFramework: TRdxFramework; out AQualified, AReason: string): Boolean;
var
  Cands : TArray<string>;
begin
  Result     := False;
  AQualified := '';
  AReason    := '';
  if Pos('.', AShortName) > 0 then
  begin
    AReason := _('already qualified');
    Exit;
  end;
  Cands := Candidates(AShortName);
  if Length(Cands) = 0 then
  begin
    AReason := _('not in the scope table (project or third-party unit)');
    Exit;
  end;
  // System.Skia oder Vcl.Skia: haengt an der Reihenfolge in DCC_Namespace
  // (Vorgabe- gegen SDI-/MDI-Vorlage) - nicht raten (s. Kopf).
  if (AFramework <> fwFmx) and HasPrefixIn(Cands, VCL_ORDER)
     and HasPrefixIn(Cands, SYSTEM_GROUP) then
  begin
    AReason := _('order System/Vcl depends on the project (DCC_Namespace): %s',
      [JoinNames(Cands)]);
    Exit;
  end;
  if TryOrder(Cands, COMMON_ORDER, AQualified) then Exit(True);
  case AFramework of
    fwVcl:
      if TryOrder(Cands, VCL_ORDER, AQualified) then Exit(True);
    fwFmx:
      if TryOrder(Cands, FMX_ORDER, AQualified) then Exit(True);
    fwBoth:
      begin
        AReason := _('file uses VCL and FMX: %s', [JoinNames(Cands)]);
        Exit;
      end;
  else
    begin
      // Ein EINZIGER Kandidat ist nicht mehrdeutig: eine Datei, die mit
      // dem Kurznamen uebersetzt, hat nur diese Wahl (ComCtrls ->
      // Vcl.ComCtrls). Geraten wird nur bei mehreren (Review nach
      // Bereichen 2026-10-10, Nit 16; so stand es schon im Kopf).
      if Length(Cands) = 1 then
      begin
        AQualified := Cands[0];
        Exit(True);
      end;
      AReason := _('framework (VCL/FMX) of the file not recognizable: %s',
        [JoinNames(Cands)]);
      Exit;
    end;
  end;
  AReason := _('no scope prefix of the framework fits: %s',
    [JoinNames(Cands)]);
end;

{ TRdxProjectUnits }

const
  // Englische msgid (E29); das Ende ('by hand') kommt als %s aus uRdxText
  // (MsgByHand), der Trenner ' - ' davor bleibt im Satz.
  R_UNREADABLE = 'network path in the unit search path or next to the file '
    + '(%s) - reDelphix does not read there (the menu is built in the main '
    + 'thread); whether the project has a unit of this name is open - %s';

constructor TRdxProjectUnits.Create;
begin
  inherited Create;
  FModules := TStringList.Create;
  FModules.CaseSensitive := False;
  FModules.Sorted        := True;
  FModules.Duplicates    := dupIgnore;
  FDirs := TStringList.Create;
  FDirs.CaseSensitive := False;
  FDirs.Sorted        := True;
  FDirs.Duplicates    := dupIgnore;
end;

destructor TRdxProjectUnits.Destroy;
begin
  FDirs.Free;
  FModules.Free;
  inherited;
end;

procedure TRdxProjectUnits.AddModule(const AFileName: string);
var
  Short : string;
begin
  Short := ChangeFileExt(ExtractFileName(AFileName), '');
  if Short <> '' then
    FModules.Add(Short);
end;

procedure TRdxProjectUnits.AddDir(const ADir: string);
begin
  if ADir = '' then Exit;
  if IsNetworkPath(ADir) then
  begin
    if FUnreadable = '' then
      FUnreadable := ADir;
    Exit;
  end;
  FDirs.Add(IncludeTrailingPathDelimiter(ADir));
end;

procedure TRdxProjectUnits.AddSearchPath(const ASearchPath, ABaseDir: string);
var
  Rest, Dir : string;
  P         : Integer;
begin
  // Von Hand an ';' getrennt: ohne die Anfuehrungszeichen-Regel von
  // TStrings.DelimitedText (wie bis R1-02 string.Split).
  Rest := ASearchPath;
  while Rest <> '' do
  begin
    P := Pos(';', Rest);
    if P = 0 then
      P := Length(Rest) + 1;
    Dir  := Trim(Copy(Rest, 1, P - 1));
    Rest := Copy(Rest, P + 1, MaxInt);
    if (Dir = '') or (Pos('$(', Dir) > 0) then Continue;
    // Relativ zum Projektverzeichnis, ausser mit Laufwerk oder zwei
    // Trennern vorn (UNC, auch der Win32-Namensraum '\\?\C:\..': absolut,
    // ob im Netz oder nicht - das entscheidet AddDir).
    if (ABaseDir <> '')
       and not ((Length(Dir) >= 2) and ((Dir[2] = ':') or HasUncLead(Dir))) then
      Dir := IncludeTrailingPathDelimiter(ABaseDir) + Dir;
    AddDir(ExpandFileName(Dir));
  end;
end;

function TRdxProjectUnits.Knows(const AShortName: string): Boolean;
var
  i : Integer;
begin
  if AShortName = '' then Exit(False);
  if FUnreadable <> '' then Exit(True);
  if FModules.IndexOf(AShortName) >= 0 then Exit(True);
  for i := 0 to FDirs.Count - 1 do
    if FileExists(FDirs[i] + AShortName + '.pas')
       or FileExists(FDirs[i] + AShortName + '.pp') then
      Exit(True);
  Result := False;
end;

function TRdxProjectUnits.UnreadableReason: string;
begin
  Result := '';
  if FUnreadable <> '' then
    Result := _(R_UNREADABLE, [FUnreadable, MsgByHand]);
end;

end.
