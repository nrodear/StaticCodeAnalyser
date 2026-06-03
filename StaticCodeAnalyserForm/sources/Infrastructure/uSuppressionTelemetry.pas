unit uSuppressionTelemetry;

// Optionale Telemetrie pro suppressed Finding (Konzept C.5).
//
// Aktivierung: CLI `--telemetry-csv <out.csv>` setzt gTelemetry. Default
// nil = nichts gesammelt, kein Overhead. Wenn aktiviert:
//   * uSuppression.RemoveSuppressedFindings appendet pro consumed Marker
//     einen TTelemetryRecord (Kind + FileName + FindingLine + MarkerLine)
//   * uConsoleRunner.RunFromCmdLine schreibt am Ende die CSV
//
// Output-Format (UTF-8, Header in Zeile 1):
//   timestamp_iso,kind,filename,finding_line,marker_line
//
// Aggregations-Workflow: User sammelt CSVs aus mehreren Repos / Runs,
// pipt sie in PowerShell o.a.:
//
//   Get-ChildItem *.telemetry.csv | Import-Csv | Group-Object kind |
//     Sort-Object Count -Descending |
//     Select-Object Count, Name
//
// Liefert ein "Noise-Ranking pro Detektor" - Datenbasis fuer kuenftige
// Confidence-Tagging-Iterationen (A.1) und Profile-Default-Anpassungen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TTelemetryRecord = record
    Timestamp   : TDateTime;
    Kind        : string;    // 'MemoryLeak', 'NilDeref', ...
    FileName    : string;    // voller Pfad
    FindingLine : Integer;
    MarkerLine  : Integer;
  end;

  TSuppressionTelemetry = class
  private
    FRecords : TList<TTelemetryRecord>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Append(const Kind, FileName: string;
      FindingLine, MarkerLine: Integer);
    // CSV nach DestFile schreiben (UTF-8, Header). Append=False ueber-
    // schreibt; Append=True haengt ohne Header an (fuer Multi-Run-Sammlung).
    procedure SaveCsv(const DestFile: string; Append: Boolean = False);
    function Count: Integer;
    // RFC-4180 Escape - public fuer Unit-Tests.
    class function CsvEscape(const S: string): string; static;
  end;

var
  // Global, opt-in. nil = Telemetry OFF (kein Sammeln, kein Overhead).
  // uConsoleRunner setzt das wenn --telemetry-csv aktiv ist.
  gSuppressionTelemetry : TSuppressionTelemetry = nil;

implementation

uses
  System.IOUtils;

const
  CSV_HEADER = 'timestamp_iso,kind,filename,finding_line,marker_line';

constructor TSuppressionTelemetry.Create;
begin
  inherited;
  FRecords := TList<TTelemetryRecord>.Create;
end;

destructor TSuppressionTelemetry.Destroy;
begin
  FRecords.Free;
  inherited;
end;

procedure TSuppressionTelemetry.Append(const Kind, FileName: string;
  FindingLine, MarkerLine: Integer);
var
  R : TTelemetryRecord;
begin
  R.Timestamp   := Now;
  R.Kind        := Kind;
  R.FileName    := FileName;
  R.FindingLine := FindingLine;
  R.MarkerLine  := MarkerLine;
  FRecords.Add(R);
end;

function TSuppressionTelemetry.Count: Integer;
begin
  Result := FRecords.Count;
end;

class function TSuppressionTelemetry.CsvEscape(const S: string): string;
// Minimal RFC-4180: wenn Komma/Quote/Newline in S, in Quotes packen +
// inner Quotes verdoppeln.
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0)
     or (Pos(#13, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

procedure TSuppressionTelemetry.SaveCsv(const DestFile: string;
  Append: Boolean);
var
  Lines : TStringList;
  R     : TTelemetryRecord;
  Ts    : string;
begin
  if DestFile = '' then Exit;
  Lines := TStringList.Create;
  try
    if not Append then
      Lines.Add(CSV_HEADER);
    for R in FRecords do
    begin
      Ts := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', R.Timestamp);
      Lines.Add(Format('%s,%s,%s,%d,%d',
        [Ts,
         CsvEscape(R.Kind),
         CsvEscape(R.FileName),
         R.FindingLine,
         R.MarkerLine]));   // class func ueber TSuppressionTelemetry
    end;
    if Append and TFile.Exists(DestFile) then
      TFile.AppendAllText(DestFile, Lines.Text, TEncoding.UTF8)
    else
      TFile.WriteAllText(DestFile, Lines.Text, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

initialization

finalization
  if Assigned(gSuppressionTelemetry) then
    FreeAndNil(gSuppressionTelemetry);

end.
