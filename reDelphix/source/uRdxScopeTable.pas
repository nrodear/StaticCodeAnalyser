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

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
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

    procedure Clear;
    // Zeilen 'kurzname=Qualifiziert1;Qualifiziert2', '#' = Kommentar.
    // Doppelte Namen (nur Gross/Klein verschieden) fallen zusammen.
    procedure LoadFromStrings(AStrings: TStrings);
    function LoadFromFile(const AFileName: string): Boolean;
    // RCDATA-Ressource AResName aus dem eigenen Modul (HInstance).
    function LoadFromResource(const AResName: string): Boolean;
    // Standardquelle: Datei neben der BPL (auch .\data und ..\data),
    // sonst die eingelinkte Ressource. False, wenn nichts davon da ist.
    function LoadDefault: Boolean;

    function Count: Integer;
    function Candidates(const AShortName: string): TArray<string>;
    // Aufloesung nach der Scope-Reihenfolge des Rahmenwerks (s. Kopf).
    // False mit Grund: schon qualifiziert, unbekannt, mehrdeutig ohne
    // erkennbares Rahmenwerk.
    function Resolve(const AShortName: string; AFramework: TRdxFramework;
      out AQualified, AReason: string): Boolean;

    // Woher die Tabelle geladen wurde (Diagnose), leer = nichts geladen.
    property Source: string read FSource;
  end;

implementation

const
  // Unit-Scope-Vorgabe eines Win32-Projekts, in Compiler-Reihenfolge.
  COMMON_ORDER: array[0..13] of string = (
    'winapi', 'system.win', 'data.win', 'datasnap.win', 'web.win',
    'soap.win', 'xml.win', 'bde', 'system', 'xml', 'data', 'datasnap',
    'web', 'soap');
  VCL_ORDER: array[0..4] of string = (
    'vcl', 'vcl.imaging', 'vcl.touch', 'vcl.samples', 'vcl.shell');
  FMX_ORDER: array[0..0] of string = ('fmx');

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

function JoinNames(const ANames: TArray<string>): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(ANames) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + ANames[i];
  end;
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
  i, k  : Integer;
  Line  : string;
  P     : Integer;
  Short : string;
  Rest  : string;
  Parts : TStringList;
  Names : TArray<string>;
  Known : Boolean;
  j     : Integer;
begin
  Clear;
  if not Assigned(AStrings) then Exit;
  Parts := TStringList.Create;
  try
    Parts.Delimiter       := ';';
    Parts.StrictDelimiter := True;
    for i := 0 to AStrings.Count - 1 do
    begin
      Line := Trim(AStrings[i]);
      if (Line = '') or (Line[1] = '#') then Continue;
      P := Pos('=', Line);
      if P <= 1 then Continue;
      Short := LowerCase(Trim(Copy(Line, 1, P - 1)));
      Rest  := Trim(Copy(Line, P + 1, MaxInt));
      if (Short = '') or (Rest = '') then Continue;
      Parts.DelimitedText := Rest;
      SetLength(Names, 0);
      for k := 0 to Parts.Count - 1 do
      begin
        if Trim(Parts[k]) = '' then Continue;
        Known := False;
        for j := 0 to High(Names) do
          if SameText(Names[j], Trim(Parts[k])) then
          begin
            Known := True;
            Break;
          end;
        if Known then Continue;
        SetLength(Names, Length(Names) + 1);
        Names[High(Names)] := Trim(Parts[k]);
      end;
      if Length(Names) > 0 then
        FMap.AddOrSetValue(Short, Names);
    end;
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
      Exit;
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
    Exit;   // Ressource nicht vorhanden
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
    AReason := 'bereits qualifiziert';
    Exit;
  end;
  Cands := Candidates(AShortName);
  if Length(Cands) = 0 then
  begin
    AReason := 'nicht in der Scope-Tabelle (Projekt- oder Fremd-Unit)';
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
        AReason := 'Datei nutzt VCL und FMX: ' + JoinNames(Cands);
        Exit;
      end;
  else
    begin
      AReason := 'Rahmenwerk (VCL/FMX) der Datei nicht erkennbar: '
        + JoinNames(Cands);
      Exit;
    end;
  end;
  AReason := 'kein Scope-Praefix des Rahmenwerks passt: ' + JoinNames(Cands);
end;

end.
