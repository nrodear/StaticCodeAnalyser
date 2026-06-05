unit uIDEDiagnostic;

// Diagnostics-Pipeline fuer das IDE-Plugin: TDiagnostic-Record,
// TDiagnosticStore-Singleton, Severity-Helper.
//
// Sprint A von Konzept_DiagnosticsHints.md (lokal):
//   * Daten-Layer ohne UI
//   * Voraussetzung fuer Sprints B-E (InfoBar, AnnotationOverlay,
//     Squiggly Underline, Gutter-Icons)
//
// Singleton-Begruendung: 1 Plugin = 1 Store. Renderer haengen sich an
// OnChange. Bei Plugin-Unload finalization-Cleanup.
//
// Kein AI-Egress (Memory: no-ai-in-pipeline). Description/Example
// kommen statisch aus uRuleCatalog.

interface

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections,
  uSCAConsts;

type
  TDiagnosticSeverity = (dsHint, dsWarning, dsError);

  TDiagnosticRange = record
    StartLine : Integer;  // 1-basiert
    StartCol  : Integer;  // 1-basiert
    EndLine   : Integer;
    EndCol    : Integer;
    class function FromLine(ALine: Integer): TDiagnosticRange; static;
    class function FromTokenInLine(ALine, AStartCol,
                                   ALength: Integer): TDiagnosticRange; static;
    function IsValid: Boolean;
  end;

  TDiagnostic = class
  public
    FileName    : string;
    RuleId      : string;             // 'SCA131'
    Kind        : TFindingKind;       // fkXxx aus uSCAConsts
    Severity    : TDiagnosticSeverity;
    Title       : string;             // 'Moeglicher Fehler'
    Message     : string;             // 1-Zeilen-Kurzform
    Description : string;             // Detail aus RuleCatalog
    Example     : string;             // optional Code-Beispiel
    Range       : TDiagnosticRange;
    HasQuickFix : Boolean;
    QuickFixId  : string;             // verweist auf uQuickFix-Action
  end;

  // Pro File eine Liste von Diagnostics. Store besitzt die Diagnostics
  // ueber TObjectList<TDiagnostic>(OwnsObjects=True).
  //
  // Thread-Safety: alle Mutationen + Reads via FLock geschuetzt.
  // Renderer halten lokal-kopierte Pointer-Arrays waehrend Paint.
  TDiagnosticStore = class
  private
    FByFile  : TObjectDictionary<string, TObjectList<TDiagnostic>>;
    FLock    : TCriticalSection;
    FOnChange : TProc<string>;
    function KeyFor(const AFileName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    // Ueberschreibt vorhandene Diagnostics fuer AFileName.
    // ADiagnostics geht in Store-Ownership ueber (wird beim
    // naechsten UpdateFile/ClearFile/Destroy freigegeben).
    procedure UpdateFile(const AFileName: string;
                         ADiagnostics: TObjectList<TDiagnostic>);
    procedure ClearFile(const AFileName: string);
    procedure ClearAll;

    function CountForFile(const AFileName: string): Integer;

    // Liefert Snapshot (kopierte Liste der TDiagnostic-Referenzen).
    // Aufrufer darf die TDiagnostic NICHT freen.
    function GetForFile(const AFileName: string): TArray<TDiagnostic>;
    function GetByLine(const AFileName: string;
                       ALine: Integer): TArray<TDiagnostic>;
    function TryGetAtPosition(const AFileName: string;
                              ALine, ACol: Integer;
                              out ADiagnostic: TDiagnostic): Boolean;

    // Aggregiert hoechste Severity pro Zeile (fuer Gutter-Icon-Cache).
    // Liefert Dictionary LineNo -> Severity. Caller besitzt Result.
    function BuildLineSeverityMap(
      const AFileName: string): TDictionary<Integer, TDiagnosticSeverity>;

    property OnChange: TProc<string> read FOnChange write FOnChange;
  end;

// Severity-Vergleich: dsError > dsWarning > dsHint
function SeverityHigher(A, B: TDiagnosticSeverity): TDiagnosticSeverity;

// Mapping aus Engine-Severity (uSCAConsts.TLeakSeverity).
function MapSeverity(L: TLeakSeverity): TDiagnosticSeverity;

// Lazy-init Singleton. Wird in uIDEExpert.Register erstellt + in
// uIDEExpert.finalization freigegeben.
var
  gDiagnosticStore : TDiagnosticStore = nil;

implementation

uses
  System.Types;

{ TDiagnosticRange }

class function TDiagnosticRange.FromLine(ALine: Integer): TDiagnosticRange;
begin
  Result.StartLine := ALine;
  Result.StartCol  := 1;
  Result.EndLine   := ALine;
  Result.EndCol    := MaxInt;  // bis Zeilenende
end;

class function TDiagnosticRange.FromTokenInLine(ALine, AStartCol,
  ALength: Integer): TDiagnosticRange;
begin
  Result.StartLine := ALine;
  Result.StartCol  := AStartCol;
  Result.EndLine   := ALine;
  if ALength > 0 then
    Result.EndCol  := AStartCol + ALength - 1
  else
    Result.EndCol  := AStartCol;
end;

function TDiagnosticRange.IsValid: Boolean;
begin
  Result := (StartLine > 0) and (EndLine >= StartLine)
        and (StartCol > 0) and (EndCol >= StartCol);
end;

{ Severity-Helper }

function SeverityHigher(A, B: TDiagnosticSeverity): TDiagnosticSeverity;
begin
  if Ord(A) > Ord(B) then Result := A else Result := B;
end;

function MapSeverity(L: TLeakSeverity): TDiagnosticSeverity;
begin
  case L of
    lsError:   Result := dsError;
    lsWarning: Result := dsWarning;
    lsHint:    Result := dsHint;
  else
    Result := dsHint;
  end;
end;

{ TDiagnosticStore }

constructor TDiagnosticStore.Create;
begin
  inherited;
  FByFile := TObjectDictionary<string, TObjectList<TDiagnostic>>.Create([doOwnsValues]);
  FLock   := TCriticalSection.Create;
end;

destructor TDiagnosticStore.Destroy;
begin
  FLock.Free;
  FByFile.Free;
  inherited;
end;

function TDiagnosticStore.KeyFor(const AFileName: string): string;
begin
  // Case-insensitiv (Windows Filesystem). Backslash-normalisiert.
  Result := LowerCase(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
end;

procedure TDiagnosticStore.UpdateFile(const AFileName: string;
  ADiagnostics: TObjectList<TDiagnostic>);
var
  Key : string;
begin
  if ADiagnostics = nil then Exit;
  // Sicherstellen dass Liste owns ihre Diagnostics
  ADiagnostics.OwnsObjects := True;
  Key := KeyFor(AFileName);
  FLock.Acquire;
  try
    FByFile.AddOrSetValue(Key, ADiagnostics);  // alte Liste wird per
                                                 // doOwnsValues freigegeben
  finally
    FLock.Release;
  end;
  if Assigned(FOnChange) then FOnChange(AFileName);
end;

procedure TDiagnosticStore.ClearFile(const AFileName: string);
var
  Key : string;
begin
  Key := KeyFor(AFileName);
  FLock.Acquire;
  try
    FByFile.Remove(Key);
  finally
    FLock.Release;
  end;
  if Assigned(FOnChange) then FOnChange(AFileName);
end;

procedure TDiagnosticStore.ClearAll;
begin
  FLock.Acquire;
  try
    FByFile.Clear;
  finally
    FLock.Release;
  end;
  if Assigned(FOnChange) then FOnChange('');
end;

function TDiagnosticStore.CountForFile(const AFileName: string): Integer;
var
  L : TObjectList<TDiagnostic>;
begin
  Result := 0;
  FLock.Acquire;
  try
    if FByFile.TryGetValue(KeyFor(AFileName), L) then
      Result := L.Count;
  finally
    FLock.Release;
  end;
end;

function TDiagnosticStore.GetForFile(const AFileName: string): TArray<TDiagnostic>;
var
  L : TObjectList<TDiagnostic>;
  i : Integer;
begin
  Result := nil;
  FLock.Acquire;
  try
    if FByFile.TryGetValue(KeyFor(AFileName), L) then
    begin
      SetLength(Result, L.Count);
      for i := 0 to L.Count - 1 do
        Result[i] := L[i];
    end;
  finally
    FLock.Release;
  end;
end;

function TDiagnosticStore.GetByLine(const AFileName: string;
  ALine: Integer): TArray<TDiagnostic>;
var
  L : TObjectList<TDiagnostic>;
  D : TDiagnostic;
  Tmp : TList<TDiagnostic>;
begin
  Result := nil;
  Tmp := TList<TDiagnostic>.Create;
  try
    FLock.Acquire;
    try
      if FByFile.TryGetValue(KeyFor(AFileName), L) then
        for D in L do
          if (ALine >= D.Range.StartLine) and (ALine <= D.Range.EndLine) then
            Tmp.Add(D);
    finally
      FLock.Release;
    end;
    Result := Tmp.ToArray;
  finally
    Tmp.Free;
  end;
end;

function TDiagnosticStore.TryGetAtPosition(const AFileName: string;
  ALine, ACol: Integer; out ADiagnostic: TDiagnostic): Boolean;
var
  L : TObjectList<TDiagnostic>;
  D : TDiagnostic;
begin
  Result := False;
  ADiagnostic := nil;
  FLock.Acquire;
  try
    if not FByFile.TryGetValue(KeyFor(AFileName), L) then Exit;
    for D in L do
    begin
      if ALine < D.Range.StartLine then Continue;
      if ALine > D.Range.EndLine then Continue;
      // Single-line range: Col-Check exakt
      if D.Range.StartLine = D.Range.EndLine then
      begin
        if (ACol < D.Range.StartCol) or (ACol > D.Range.EndCol) then Continue;
      end;
      // Multi-line range: Start-Col gilt nur fuer StartLine, End-Col nur
      // fuer EndLine; mittlere Zeilen ganz.
      if (ALine = D.Range.StartLine) and (ACol < D.Range.StartCol) then Continue;
      if (ALine = D.Range.EndLine)   and (ACol > D.Range.EndCol) then Continue;
      ADiagnostic := D;
      Exit(True);
    end;
  finally
    FLock.Release;
  end;
end;

function TDiagnosticStore.BuildLineSeverityMap(
  const AFileName: string): TDictionary<Integer, TDiagnosticSeverity>;
var
  L : TObjectList<TDiagnostic>;
  D : TDiagnostic;
  Existing : TDiagnosticSeverity;
  i : Integer;
begin
  Result := TDictionary<Integer, TDiagnosticSeverity>.Create;
  FLock.Acquire;
  try
    if not FByFile.TryGetValue(KeyFor(AFileName), L) then Exit;
    for D in L do
    begin
      // Pro Zeile im Range hoechste Severity merken
      for i := D.Range.StartLine to D.Range.EndLine do
      begin
        if Result.TryGetValue(i, Existing) then
          Result.AddOrSetValue(i, SeverityHigher(Existing, D.Severity))
        else
          Result.Add(i, D.Severity);
      end;
    end;
  finally
    FLock.Release;
  end;
end;

end.
