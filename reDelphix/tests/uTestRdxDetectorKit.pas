unit uTestRdxDetectorKit;

// Testhilfen der Detektor-Rundlaeufe (nur Delphi, reDelphix.Test): Datei
// schreiben, den echten Detektor auf dem echten AST laufen lassen, die
// Hilfe ueber den Einstieg des Anbieters (TRdxFixTable.FixFor) planen und
// wie der Editor anwenden, Fund fuer Fund bis der Detektor schweigt. Bis
// Charge H3c stand das dreimal - in uTestRdxSimpleFixesDetector,
// uTestRdxCleanupDetector und uTestRdxRoutineFixesDetector (Gegen-Review
// H3, Minor 9); reine Verschiebung. Welcher Detektor zu welcher Art laeuft,
// bleibt in der Testunit (TDetectorRun) - die drei registrieren
// verschiedene Detektormengen.

interface

uses
  System.Generics.Collections,
  uAstNode,           // TAstNode
  uMethodd12,         // TLeakFinding
  uSCAConsts,         // TFindingKind
  uRdxBufferMath,     // TRdxEdit
  uRdxRecipeRunner;   // TRdxFixOutcome

type
  // Was die Hilfe aus einem Fund liest - wie der Anbieter aus TLeakFinding.
  // Variant: TLeakFinding.LeakVariant (SCA001 - die Hilfe der Charge H4
  // gibt es nur fuer freed-outside-finally); '' bei allen anderen Regeln.
  TSeen = record
    Line    : Integer;
    Msg     : string;
    Variant : string;
  end;

  // Der Verteiler einer Testunit: ruft fuer AKind den echten Detektor auf
  // Root (Funde nach Results).
  TDetectorRun = procedure(AKind: TFindingKind; Root: TAstNode;
    const Path: string; Results: TObjectList<TLeakFinding>);

  // Detect einer Testunit: die Funde der Art AKind im Quelltext.
  TDetectFunc = function(const ASource: string;
    AKind: TFindingKind): TArray<TSeen>;

// Zeilen mit CRLF verbunden.
function Join(const ALines: array of string): string;
// Ein Katalog-Beispiel als Quelltext: Zeilenenden CRLF (JSON liefert #10,
// der eingebaute Katalog #13#10). uTestRdxSimpleFixesDetector laesst dazu
// '...' weg (eigene Snip).
function CatalogText(const AExample: string): string;
// Ein Dateiname im TEMP-Verzeichnis: APrefix + GUID + AExt.
function TempName(const APrefix, AExt: string): string;
procedure WriteText(const APath, AText: string);
// ASource in eine neue .pas-Datei im TEMP-Verzeichnis; ihr Name.
function WriteTemp(const APrefix, ASource: string): string;
// Funde der Art AKind in der Datei APath - ARun auf dem echten AST.
function DetectFile(const APath: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
// Dasselbe fuer einen Quelltext (Datei APrefix* im TEMP, danach geloescht).
function DetectSource(const APrefix, ASource: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
// Die Hilfe fuer EINEN Fund ueber den Einstieg des Anbieters: der Fund als
// TLeakFinding der Datei AFile, der Quellstellen-Dienst auf demselben Text.
function PlanFixIn(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
// Dasselbe fuer 't.pas': True mit den Ersetzungen bzw. False mit dem Grund.
function PlanFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
// Schreibt wie der Editor: alle Ersetzungen gegen denselben Puffer geprueft.
function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
// Fund fuer Fund, nach jeder Ersetzung neu gemeldet (wie der Benutzer es
// taete), bis der Detektor (ADetect) schweigt.
function FixAllWith(const ASource: string; AKind: TFindingKind;
  ADetect: TDetectFunc): string;
// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelpWith(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string; ADetect: TDetectFunc);

implementation

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  uParser2,           // TParser2
  uEngineApi,         // TSourcePlaces
  uRdxFixTable;       // TRdxFixTable.FixFor

function Join(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

function CatalogText(const AExample: string): string;
begin
  Result := StringReplace(AExample, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

function TempName(const APrefix, AExt: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + APrefix + GUIDToString(TGUID.NewGuid) + AExt;
end;

procedure WriteText(const APath, AText: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := AText;
    SL.SaveToFile(APath);
  finally
    SL.Free;
  end;
end;

function WriteTemp(const APrefix, ASource: string): string;
begin
  Result := TempName(APrefix, '.pas');
  WriteText(Result, ASource);
end;

function DetectFile(const APath: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
var
  Parser  : TParser2;
  Root    : TAstNode;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
  n       : Integer;
begin
  Result := nil;
  Results := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(APath);
      try
        ARun(AKind, Root, APath, Results);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    SetLength(Result, Results.Count);
    n := 0;
    for F in Results do
      if F.Kind = AKind then
      begin
        Result[n].Line    := F.LineInt;
        Result[n].Msg     := F.Message;
        Result[n].Variant := F.LeakVariant;
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    Results.Free;
  end;
end;

function DetectSource(const APrefix, ASource: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
var
  Path : string;
begin
  Path := WriteTemp(APrefix, ASource);
  try
    Result := DetectFile(Path, AKind, ARun);
  finally
    DeleteFile(Path);
  end;
end;

function PlanFixIn(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
var
  SL      : TStringList;
  Places  : TSourcePlaces;
  Finding : TLeakFinding;
begin
  Assert.IsTrue(TRdxFixTable.Handles(AKind), 'FixFor kennt die Art');
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  Finding := TLeakFinding.New(AFile, '', ASeen.Line, ASeen.Msg, AKind);
  try
    Finding.LeakVariant := ASeen.Variant;
    SL.Text := ASource;
    Assert.IsTrue(Places.OpenSource(AFile, ASource), 'OpenSource');
    Result := TRdxFixTable.FixFor(Places, SL, Finding,
      TRdxRecipeRunner.UsesNamesOf(Places));
  finally
    Finding.Free;
    Places.Free;
    SL.Free;
  end;
end;

function PlanFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  O : TRdxFixOutcome;
begin
  O := PlanFixIn(ASource, 't.pas', AKind, ASeen);
  AEdits  := O.Edits;
  AReason := O.Reason;
  Result  := O.Enabled;
end;

function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, AEdits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

function FixAllWith(const ASource: string; AKind: TFindingKind;
  ADetect: TDetectFunc): string;
const
  MAX_PASSES = 10;
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
  Pass   : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := ADetect(Result, AKind);
    if Length(Seen) = 0 then Exit;
    Assert.IsTrue(PlanFix(Result, AKind, Seen[0], Edits, Reason),
      Format('Zeile %d: %s', [Seen[0].Line, Reason]));
    Result := Apply(Result, Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

procedure AssertNoHelpWith(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string; ADetect: TDetectFunc);
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Seen := ADetect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Assert.IsFalse(PlanFix(ASource, AKind, Seen[0], Edits, Reason), 'keine Hilfe');
  Assert.IsTrue(Pos(AReasonPart, Reason) > 0, Reason);
end;

end.
