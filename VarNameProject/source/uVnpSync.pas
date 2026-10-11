unit uVnpSync;

// VarNameProject - die Sync-Edit-Punkte der IDE (ToolsAPI: IOTAEditBlock.
// SyncEditBlock). Ein Punkt hat einen Namen, einen Text und mehrere
// Fundstellen (Offsets); die IDE umrandet sie und aendert beim Tippen
// alle mit - derselbe Mechanismus wie Sync Edit (Strg+Umschalt+J) und die
// Live Templates. Die Punkte sind eigene Klassen (TVnpSyncPoint/
// TVnpSyncPoints): IOTACodeTemplateServices.CreateClass liefert fuer die
// Sync-Punkt-Interfaces nil (Sonde M21, 2026-10-11) - ob die IDE fremde
// Umsetzungen annimmt, ist die naechste Messung.
// TVnpSyncNotifier schreibt jedes Ereignis der Sitzung ins Protokoll,
// samt der Offsets - bei SyncEditBlock(nil) sind das die Punkte, die die
// IDE SELBST anlegt: daraus liest man das Koordinatensystem ab.

interface

uses
  System.SysUtils, System.Generics.Collections, ToolsAPI;

type
  // Ein Sync-Punkt, eigene Umsetzung.
  TVnpSyncPoint = class(TInterfacedObject, IOTASyncEditPoint100,
    IOTASyncEditPoint)
  private
    FOffsets   : TList<TOTACharPos>;
    FEditable  : Boolean;
    FMultiLine : Boolean;
    FHint      : string;
    FName      : string;
    FText      : string;
  public
    constructor Create;
    destructor Destroy; override;
    { IOTASyncEditPoint100 }
    procedure AddOffset(Offset: TOTACharPos);
    procedure RemoveOffset(Index: Integer);
    function GetCount: Integer;
    function GetEditable: Boolean;
    function GetHint: string;
    function GetName: string;
    function GetOffset(Index: Integer): TOTACharPos;
    function GetText: string;
    procedure SetEditable(Value: Boolean);
    procedure SetHint(const Value: string);
    procedure SetName(const Value: string);
    procedure SetOffset(Index: Integer; Value: TOTACharPos);
    procedure SetText(Value: string);
    { IOTASyncEditPoint }
    function GetMultiLine: Boolean;
    procedure SetMultiLine(Value: Boolean);
  end;

  // Die Liste der Punkte, eigene Umsetzung.
  TVnpSyncPoints = class(TInterfacedObject, IOTASyncEditPoints)
  private
    FPoints : TList<IOTASyncEditPoint>;
  public
    constructor Create;
    destructor Destroy; override;
    function AddPoint(const APoint: IOTASyncEditPoint): Integer;
    procedure RemovePoint(const APoint: IOTASyncEditPoint);
    function GetPoints(Index: Integer): IOTASyncEditPoint;
    function GetCount: Integer;
  end;

  // Protokolliert die Sitzung (meldet sich NICHT selbst ab).
  TVnpSyncNotifier = class(TInterfacedObject, IOTASyncEditNotifier)
  public
    procedure OnPoint(const APoint: IOTASyncEditPoint;
      const APoints: IOTASyncEditPoints;
      EventType: TOTASyncEditPointEventType);
    procedure OnSyncEdit(const APoints: IOTASyncEditPoints;
      EventType: TOTASyncEditPointEventType);
  end;

// Ein editierbarer Punkt AName mit den Fundstellen AOffsets in einer neuen
// Liste (eigene Klassen). False mit AError, wenn das Fuellen scheitert.
function MakePoints(const AName: string; const AOffsets: TArray<TOTACharPos>;
  out APoints: IOTASyncEditPoints; out AError: string): Boolean;

// 'Name="X" Text="X" editierbar mehrzeilig=nein Offsets=[(5,6), ...]' je
// Punkt, fuers Protokoll. Offsets als (Line,CharIndex) wie TOTACharPos.
function DescribePoints(const APoints: IOTASyncEditPoints): string;

// Einen Notifier an ABlock haengen. Er bleibt bis zum Entladen des Pakets
// angemeldet und am Leben: Strg+Z belebt eine beendete Sitzung wieder und
// ruft die Notifier erneut.
procedure WatchBlock(const ABlock: IOTAEditBlock);
// AObject bis zum Entladen des Pakets am Leben halten (die Punkte einer
// Sitzung - ob die IDE sie selbst referenziert, ist eine Messfrage).
procedure KeepAlive(const AObject: IInterface);
// Alle Notifier abmelden, alles Gehaltene freigeben (finalization).
procedure ReleaseAll;

implementation

// Die public-Methoden der Punkt-Klassen setzen nur die ToolsAPI-Interfaces
// um (dort beschrieben); die Texte sind deutsch, das Testprojekt hat keine
// Uebersetzung.
// noinspection-file PublicMemberWithoutDoc, HardcodedString

uses
  uVnpLog;

const
  EVENT_NAMES : array[TOTASyncEditPointEventType] of string =
    ('Enter', 'Leave', 'Exit');

type
  // Ein angemeldeter Notifier: Block, Index fuer RemoveNotifier und die
  // eigene Referenz, die ihn am Leben haelt.
  TVnpWatch = record
    Block    : IOTAEditBlock;
    Index    : Integer;
    Notifier : IOTASyncEditNotifier;
  end;

var
  GWatches : TList<TVnpWatch> = nil;
  GKept    : TList<IInterface> = nil;

{ TVnpSyncPoint }

constructor TVnpSyncPoint.Create;
begin
  inherited Create;
  FOffsets := TList<TOTACharPos>.Create;
end;

destructor TVnpSyncPoint.Destroy;
begin
  FOffsets.Free;
  inherited Destroy;
end;

procedure TVnpSyncPoint.AddOffset(Offset: TOTACharPos);
begin
  FOffsets.Add(Offset);
end;

procedure TVnpSyncPoint.RemoveOffset(Index: Integer);
begin
  FOffsets.Delete(Index);
end;

function TVnpSyncPoint.GetCount: Integer;
begin
  Result := FOffsets.Count;
end;

function TVnpSyncPoint.GetEditable: Boolean;
begin
  Result := FEditable;
end;

function TVnpSyncPoint.GetHint: string;
begin
  Result := FHint;
end;

function TVnpSyncPoint.GetName: string;
begin
  Result := FName;
end;

function TVnpSyncPoint.GetOffset(Index: Integer): TOTACharPos;
begin
  Result := FOffsets[Index];
end;

function TVnpSyncPoint.GetText: string;
begin
  Result := FText;
end;

procedure TVnpSyncPoint.SetEditable(Value: Boolean);
begin
  FEditable := Value;
end;

procedure TVnpSyncPoint.SetHint(const Value: string);
begin
  FHint := Value;
end;

procedure TVnpSyncPoint.SetName(const Value: string);
begin
  FName := Value;
end;

procedure TVnpSyncPoint.SetOffset(Index: Integer; Value: TOTACharPos);
begin
  FOffsets[Index] := Value;
end;

procedure TVnpSyncPoint.SetText(Value: string);
begin
  FText := Value;
end;

function TVnpSyncPoint.GetMultiLine: Boolean;
begin
  Result := FMultiLine;
end;

procedure TVnpSyncPoint.SetMultiLine(Value: Boolean);
begin
  FMultiLine := Value;
end;

{ TVnpSyncPoints }

constructor TVnpSyncPoints.Create;
begin
  inherited Create;
  FPoints := TList<IOTASyncEditPoint>.Create;
end;

destructor TVnpSyncPoints.Destroy;
begin
  FPoints.Free;
  inherited Destroy;
end;

function TVnpSyncPoints.AddPoint(const APoint: IOTASyncEditPoint): Integer;
begin
  Result := FPoints.Add(APoint);
end;

procedure TVnpSyncPoints.RemovePoint(const APoint: IOTASyncEditPoint);
begin
  FPoints.Remove(APoint);
end;

function TVnpSyncPoints.GetPoints(Index: Integer): IOTASyncEditPoint;
begin
  Result := FPoints[Index];
end;

function TVnpSyncPoints.GetCount: Integer;
begin
  Result := FPoints.Count;
end;

{ Protokoll }

function DescribePoints(const APoints: IOTASyncEditPoints): string;
var
  i, k : Integer;
  P    : IOTASyncEditPoint;
  SB   : TStringBuilder;
begin
  if APoints = nil then
    Exit('(keine Punkte)');
  SB := TStringBuilder.Create;
  try
    SB.Append(Format('%d Punkt(e)', [APoints.Count]));
    for i := 0 to APoints.Count - 1 do
    begin
      P := APoints[i];
      SB.Append(Format('; Name="%s" Text="%s" editierbar=%s mehrzeilig=%s '
        + 'Offsets=[', [P.Name, P.Text, BoolToStr(P.Editable, True),
        BoolToStr(P.MultiLine, True)]));
      for k := 0 to P.Count - 1 do
        SB.Append(Format(' (%d,%d)', [P.Offset[k].Line,
          P.Offset[k].CharIndex]));
      SB.Append(' ]');
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TVnpSyncNotifier }

procedure TVnpSyncNotifier.OnPoint(const APoint: IOTASyncEditPoint;
  const APoints: IOTASyncEditPoints; EventType: TOTASyncEditPointEventType);
var
  Name, Text : string;
begin
  Name := '?';
  Text := '?';
  if APoint <> nil then
  begin
    Name := APoint.Name;
    Text := APoint.Text;
  end;
  VnpLog('  Ereignis Punkt %s: Name="%s" Text="%s"',
    [EVENT_NAMES[EventType], Name, Text]);
end;

procedure TVnpSyncNotifier.OnSyncEdit(const APoints: IOTASyncEditPoints;
  EventType: TOTASyncEditPointEventType);
begin
  // KEIN Abmelden bei Exit mehr: Strg+Z belebt die Sitzung wieder und
  // ruft die Notifier erneut (Absturz in TSyncEditManager.SendSyncEvent,
  // Nicos Lauf 2026-10-11, nachdem der Notifier bei Exit abgemeldet und
  // freigegeben war).
  VnpLog('  Ereignis Sitzung %s: %s', [EVENT_NAMES[EventType],
    DescribePoints(APoints)]);
end;

procedure WatchBlock(const ABlock: IOTAEditBlock);
var
  W : TVnpWatch;
begin
  if ABlock = nil then Exit;
  if GWatches = nil then
    GWatches := TList<TVnpWatch>.Create;
  W.Block := ABlock;
  W.Notifier := TVnpSyncNotifier.Create;
  W.Index := ABlock.AddNotifier(W.Notifier);
  GWatches.Add(W);
  VnpLog('  Notifier angemeldet (Index %d, bleibt bis zum Entladen)',
    [W.Index]);
end;

procedure KeepAlive(const AObject: IInterface);
begin
  if GKept = nil then
    GKept := TList<IInterface>.Create;
  GKept.Add(AObject);
end;

procedure ReleaseAll;
var
  i : Integer;
begin
  // Rueckwaerts: entfernt die IDE beim Abmelden einen Listeneintrag,
  // bleiben die Indizes davor gueltig.
  if GWatches <> nil then
    for i := GWatches.Count - 1 downto 0 do
      try
        GWatches[i].Block.RemoveNotifier(GWatches[i].Index);
      except
        // Der Editor kann inzwischen zu sein - beim Entladen darf nichts
        // durchschlagen.
        // noinspection ExceptionTooGeneral
        on E: Exception do
          VnpLog('  RemoveNotifier: %s: %s', [E.ClassName, E.Message]);
      end;
  FreeAndNil(GWatches);
  FreeAndNil(GKept);
end;

{ Punkte erzeugen }

function MakePoints(const AName: string; const AOffsets: TArray<TOTACharPos>;
  out APoints: IOTASyncEditPoints; out AError: string): Boolean;
var
  P   : IOTASyncEditPoint;
  Off : TOTACharPos;
begin
  Result := True;
  AError := '';
  APoints := TVnpSyncPoints.Create;
  P := TVnpSyncPoint.Create;
  try
    P.Name := AName;
    P.Text := AName;
    P.Hint := 'Neuen Namen tippen - alle Stellen aendern sich mit';
    P.Editable := True;
    P.MultiLine := False;
    for Off in AOffsets do
      P.AddOffset(Off);
    APoints.AddPoint(P);
  except
    // Messung wie oben: eine IDE-Umsetzung kann Setter ablehnen.
    on E: Exception do
    begin
      AError := 'Punkt fuellen: ' + E.ClassName + ': ' + E.Message;
      VnpLog('  Punkte: FEHLER %s', [AError]);
      Exit(False);
    end;
  end;
  VnpLog('  Punkte: %s', [DescribePoints(APoints)]);
end;

initialization

finalization
  ReleaseAll;

end.
