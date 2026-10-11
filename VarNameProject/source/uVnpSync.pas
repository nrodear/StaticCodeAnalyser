unit uVnpSync;

// VarNameProject - die Sync-Edit-Punkte der IDE (ToolsAPI: IOTAEditBlock.
// SyncEditBlock). Ein Punkt hat einen Namen, einen Text und mehrere
// Fundstellen (Offsets); die IDE umrandet sie und aendert beim Tippen
// alle mit - derselbe Mechanismus wie Sync Edit (Strg+Umschalt+J) und die
// Live Templates. Woher die Punkte kommen, ist eine Messfrage:
//   psCodeTemplates  IOTACodeTemplateServices.CreateClass(GUID) - die
//                    Fabrik der IDE (CodeTemplateAPI), falls sie diese
//                    GUIDs kennt.
//   psOwn            eigene Klassen (TVnpSyncPoint/TVnpSyncPoints) - falls
//                    die IDE fremde Umsetzungen annimmt.
// TVnpSyncNotifier schreibt jedes Ereignis der Sitzung ins Protokoll,
// samt der Offsets - bei SyncEditBlock(nil) sind das die Punkte, die die
// IDE SELBST anlegt: daraus liest man das Koordinatensystem ab.

interface

uses
  System.SysUtils, System.Generics.Collections, ToolsAPI;

type
  TVnpPointSource = (psCodeTemplates, psOwn);

  // Ein Sync-Punkt, eigene Umsetzung (psOwn).
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

  // Die Liste der Punkte, eigene Umsetzung (psOwn).
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

  // Protokolliert die Sitzung; bei sepExit meldet er sich selbst ab.
  TVnpSyncNotifier = class(TInterfacedObject, IOTASyncEditNotifier)
  public
    procedure OnPoint(const APoint: IOTASyncEditPoint;
      const APoints: IOTASyncEditPoints;
      EventType: TOTASyncEditPointEventType);
    procedure OnSyncEdit(const APoints: IOTASyncEditPoints;
      EventType: TOTASyncEditPointEventType);
  end;

// Ein editierbarer Punkt AName mit den Fundstellen AOffsets in einer neuen
// Liste. False mit AError, wenn die Quelle ihn nicht liefern kann.
function MakePoints(ASource: TVnpPointSource; const AName: string;
  const AOffsets: TArray<TOTACharPos>; out APoints: IOTASyncEditPoints;
  out AError: string): Boolean;

// 'Name="X" Text="X" editierbar mehrzeilig=nein Offsets=[(5,6), ...]' je
// Punkt, fuers Protokoll. Offsets als (Line,CharIndex) wie TOTACharPos.
function DescribePoints(const APoints: IOTASyncEditPoints): string;

// Notifier an ABlock haengen (ein vorheriger wird vorher abgemeldet).
procedure WatchBlock(const ABlock: IOTAEditBlock);
// Den Notifier abmelden (beim Entladen des Pakets).
procedure UnwatchBlock;

implementation

// Die public-Methoden der Punkt-Klassen setzen nur die ToolsAPI-Interfaces
// um (dort beschrieben); die Texte sind deutsch, das Testprojekt hat keine
// Uebersetzung.
// noinspection-file PublicMemberWithoutDoc, HardcodedString

uses
  System.Classes, CodeTemplateAPI, uVnpLog;

const
  EVENT_NAMES : array[TOTASyncEditPointEventType] of string =
    ('Enter', 'Leave', 'Exit');
  SOURCE_NAMES : array[TVnpPointSource] of string =
    ('CreateClass', 'eigene Klassen');

var
  GBlock         : IOTAEditBlock = nil;
  GNotifierIndex : Integer = -1;

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
  VnpLog('  Ereignis Sitzung %s: %s', [EVENT_NAMES[EventType],
    DescribePoints(APoints)]);
  // Abmelden NICHT im Rueckruf selbst - die IDE iteriert gerade ihre
  // Notifier-Liste.
  if EventType = sepExit then
    TThread.ForceQueue(nil,
      procedure
      begin
        UnwatchBlock;
      end);
end;

procedure UnwatchBlock;
begin
  try
    if (GBlock <> nil) and (GNotifierIndex >= 0) then
      GBlock.RemoveNotifier(GNotifierIndex);
  except
    // Der Editor kann inzwischen zu sein - beim Entladen darf nichts
    // durchschlagen.
    // noinspection ExceptionTooGeneral
    on E: Exception do
      VnpLog('  RemoveNotifier: %s: %s', [E.ClassName, E.Message]);
  end;
  GBlock := nil;
  GNotifierIndex := -1;
end;

procedure WatchBlock(const ABlock: IOTAEditBlock);
begin
  UnwatchBlock;
  if ABlock = nil then Exit;
  GBlock := ABlock;
  GNotifierIndex := ABlock.AddNotifier(TVnpSyncNotifier.Create);
  VnpLog('  Notifier angemeldet (Index %d)', [GNotifierIndex]);
end;

{ Punkte erzeugen }

function NewPoints(ASource: TVnpPointSource; out APoints: IOTASyncEditPoints;
  out APoint: IOTASyncEditPoint; out AError: string): Boolean;
var
  Svc : IOTACodeTemplateServices;
begin
  Result := False;
  APoints := nil;
  APoint := nil;
  AError := '';
  if ASource = psOwn then
  begin
    APoints := TVnpSyncPoints.Create;
    APoint := TVnpSyncPoint.Create;
    Exit(True);
  end;
  if not Supports(BorlandIDEServices, IOTACodeTemplateServices, Svc) then
  begin
    AError := 'BorlandIDEServices kennt IOTACodeTemplateServices nicht';
    Exit;
  end;
  try
    if not Supports(Svc.CreateClass(IOTASyncEditPoints), IOTASyncEditPoints,
      APoints) then
      AError := 'CreateClass(IOTASyncEditPoints) lieferte nichts Passendes'
    else if not Supports(Svc.CreateClass(IOTASyncEditPoint),
      IOTASyncEditPoint, APoint) then
      AError := 'CreateClass(IOTASyncEditPoint) lieferte nichts Passendes';
  except
    // Messung: welche Ausnahme CreateClass wirft, gehoert ins Protokoll.
    // noinspection ExceptionTooGeneral
    on E: Exception do
      AError := 'CreateClass: ' + E.ClassName + ': ' + E.Message;
  end;
  Result := AError = '';
end;

function MakePoints(ASource: TVnpPointSource; const AName: string;
  const AOffsets: TArray<TOTACharPos>; out APoints: IOTASyncEditPoints;
  out AError: string): Boolean;
var
  P   : IOTASyncEditPoint;
  Off : TOTACharPos;
begin
  Result := NewPoints(ASource, APoints, P, AError);
  if not Result then
  begin
    VnpLog('  Punkte (%s): FEHLER %s', [SOURCE_NAMES[ASource], AError]);
    Exit;
  end;
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
      VnpLog('  Punkte (%s): FEHLER %s', [SOURCE_NAMES[ASource], AError]);
      Exit(False);
    end;
  end;
  VnpLog('  Punkte (%s): %s', [SOURCE_NAMES[ASource], DescribePoints(APoints)]);
end;

initialization

finalization
  UnwatchBlock;

end.
