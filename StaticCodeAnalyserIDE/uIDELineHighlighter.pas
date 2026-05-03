unit uIDELineHighlighter;

// Custom Line-Highlights im Delphi-Editor sind aktuell DEAKTIVIERT.
//
// Warum:
//   Die Tools-API verlangt fuer jeden View-gebundenen Notifier ein sauberes
//   Lifecycle-Management mit RemoveNotifier(Idx) VOR der View-Destruction.
//   Beim Schliessen / Wiederoeffnen von Projekten ruft die IDE
//   NotifyDestroyed auf alle haengenden Notifier - ein nicht abgemeldeter
//   Notifier loest dort eine AV in coreide290.bpl aus
//   (Stack: TOTAEditView.NotifyDestroyed -> TEditView.BeforeDestruction).
//
// Diese Unit bleibt als Stub erhalten:
//   * GHighlighter ist ein Singleton mit der Befund-Map
//   * SetFindings befuellt die Map (kein Side-Effect)
//   * Register/Unregister sind No-Ops
//
// Wenn das Feature spaeter wieder aktiviert wird, ist der korrekte Weg:
//   * Pro EditView den NotifierIdx merken
//   * In INTAEditServicesNotifier.WindowNotification(opRemove) abmelden
//   * In INTAEditServicesNotifier.ViewNotification(opRemove) abmelden
//   * Alternative: Compiler-Message-Pane (IOTAMessageServices.AddToolMessage)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts;

type
  TFindingLineHighlighter = class
  private
    // FilePath (lower-case) -> (LineNumber -> Severity)
    FFiles : TObjectDictionary<string, TDictionary<Integer, TLeakSeverity>>;
    function NormalizePath(const APath: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    // Befunde -> interne Map. Aktuell ohne Editor-Painting (Stub).
    procedure SetFindings(Findings: TObjectList<TLeakFinding>);

    // Alle Highlights loeschen.
    procedure Clear;

    // Liefert Severity fuer (Datei, Zeile) oder False wenn kein Treffer.
    // Wird derzeit nicht aufgerufen, bleibt fuer kuenftige Aktivierung.
    function TryGetSeverity(const FilePath: string; Line: Integer;
      out Severity: TLeakSeverity): Boolean;
  end;

var
  GHighlighter : TFindingLineHighlighter = nil;

procedure RegisterLineHighlighter;
procedure UnregisterLineHighlighter;

implementation

{ ---- TFindingLineHighlighter ---- }

constructor TFindingLineHighlighter.Create;
begin
  inherited;
  FFiles := TObjectDictionary<string, TDictionary<Integer, TLeakSeverity>>.Create([doOwnsValues]);
end;

destructor TFindingLineHighlighter.Destroy;
begin
  FFiles.Free;
  inherited;
end;

function TFindingLineHighlighter.NormalizePath(const APath: string): string;
begin
  Result := APath.ToLower.Replace('/', '\');
end;

procedure TFindingLineHighlighter.Clear;
begin
  FFiles.Clear;
end;

procedure TFindingLineHighlighter.SetFindings(Findings: TObjectList<TLeakFinding>);
var
  F     : TLeakFinding;
  Key   : string;
  Lines : TDictionary<Integer, TLeakSeverity>;
  L     : Integer;
begin
  FFiles.Clear;
  if Findings = nil then Exit;
  for F in Findings do
  begin
    if F.FileName = '' then Continue;
    L := StrToIntDef(F.LineNumber, 0);
    if L <= 0 then Continue;
    Key := NormalizePath(F.FileName);
    if not FFiles.TryGetValue(Key, Lines) then
    begin
      Lines := TDictionary<Integer, TLeakSeverity>.Create;
      FFiles.Add(Key, Lines);
    end;
    if Lines.ContainsKey(L) then
    begin
      if Ord(F.Severity) < Ord(Lines[L]) then
        Lines[L] := F.Severity;
    end
    else
      Lines.Add(L, F.Severity);
  end;
end;

function TFindingLineHighlighter.TryGetSeverity(const FilePath: string;
  Line: Integer; out Severity: TLeakSeverity): Boolean;
var
  Lines: TDictionary<Integer, TLeakSeverity>;
begin
  Result := False;
  if FFiles.Count = 0 then Exit;
  if not FFiles.TryGetValue(NormalizePath(FilePath), Lines) then Exit;
  Result := Lines.TryGetValue(Line, Severity);
end;

{ ---- Public Register/Unregister ---- }

procedure RegisterLineHighlighter;
begin
  if Assigned(GHighlighter) then Exit;
  GHighlighter := TFindingLineHighlighter.Create;
end;

procedure UnregisterLineHighlighter;
begin
  if not Assigned(GHighlighter) then Exit;
  FreeAndNil(GHighlighter);
end;

end.
