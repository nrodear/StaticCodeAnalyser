unit uVnpSync;

// VarNameProject - die Sync-Edit-Punkte der IDE (ToolsAPI: IOTAEditBlock.
// SyncEditBlock). Ein Punkt hat einen Namen, einen Text und mehrere
// Fundstellen (Offsets); die IDE umrandet sie und aendert beim Tippen
// alle mit - derselbe Mechanismus wie Sync Edit (Strg+Umschalt+J) und die
// Live Templates. Die Punkte sind eigene Klassen (TVnpSyncPoint/
// TVnpSyncPoints): IOTACodeTemplateServices.CreateClass liefert fuer die
// Sync-Punkt-Interfaces nil (Sonde M21, 2026-10-11).
//
// KEIN IOTASyncEditNotifier (Lauf 4, 2026-10-11): IOTAEditBlock.
// RemoveNotifier laesst einen nil-Eintrag in der Notifier-Liste des Blocks
// stehen, und TSyncEditManager.SendSyncEvent prueft nicht auf nil -
// Zugriffsverletzung beim Lesen von Adresse 0, beim naechsten Sync-Ereignis
// in DIESER Ansicht (Strg+Z, Sitzungsstart, Neuzeichnen), auch nach dem
// Neuinstallieren des Pakets. Ohne Abmelden blieben Verweise auf Code, den
// das Entladen des Pakets entfernt. Die Sitzung wird stattdessen per
// Sonde abgefragt (Block.SyncMode, uVnpProbe).

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

// Ein editierbarer Punkt AName mit den Fundstellen AOffsets in einer neuen
// Liste (eigene Klassen). False mit AError, wenn das Fuellen scheitert.
function MakePoints(const AName: string; const AOffsets: TArray<TOTACharPos>;
  out APoints: IOTASyncEditPoints; out AError: string): Boolean;

// 'Name="X" Text="X" editierbar mehrzeilig=nein Offsets=[(5,6), ...]' je
// Punkt, fuers Protokoll. Offsets als (Line,CharIndex) wie TOTACharPos.
function DescribePoints(const APoints: IOTASyncEditPoints): string;

// AObject bis zum Entladen des Pakets am Leben halten (die Punkte einer
// Sitzung - ob die IDE sie selbst referenziert, ist offen). Vor dem
// Entladen des Pakets keine Sitzung offen lassen.
procedure KeepAlive(const AObject: IInterface);
// Alles Gehaltene freigeben (finalization).
procedure ReleaseAll;

implementation

// Die public-Methoden der Punkt-Klassen setzen nur die ToolsAPI-Interfaces
// um (dort beschrieben); die Texte sind deutsch, das Testprojekt hat keine
// Uebersetzung.
// noinspection-file PublicMemberWithoutDoc, HardcodedString

uses
  uVnpLog;

var
  GKept : TList<IInterface> = nil;

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

procedure KeepAlive(const AObject: IInterface);
begin
  if GKept = nil then
    GKept := TList<IInterface>.Create;
  GKept.Add(AObject);
end;

procedure ReleaseAll;
begin
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
