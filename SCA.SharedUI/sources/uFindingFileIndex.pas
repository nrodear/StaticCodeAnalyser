unit uFindingFileIndex;

{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}

// Funde einer Editor-Zeile fuer Gluehbirne und Editor-Kontextmenue - reine
// Logik ohne VCL und ohne ToolsAPI (Charge P, P6, 2026-10-25). Vorher stand
// sie in uIDEAnalyserForm.FindingsAtEditorLine und lief bei jedem
// Zeilenwechsel und mindestens einmal je BULB_FINDINGS_RECHECK_MS linear
// ueber ALLE Funde des Docks - je Fund gleicher Pfadlaenge mit einem
// NormalizePathForKey (eine Zeichenkette je Aufruf). Getestet in
// TestProject (uTestFindingFileIndex).
//
// Zwei Teile:
//   * SameFindingFile / FindingsAtLine - die Regel je Fund, unveraendert
//     aus FindingsAtEditorLine uebernommen (Pfadvergleich, Bereich,
//     Doppelte). FindingsAtLine laeuft ueber die Liste, die es bekommt.
//   * TFindingFileIndex - die Funde einer Liste je Pfadschluessel
//     (NormalizePathForKey), in der Reihenfolge der Liste. Er liefert nur
//     KANDIDATEN; geprueft wird jeder weiter mit SameFindingFile.
//
// Warum der Index nichts verliert: SameFindingFile verlangt gleiche Laenge
// und (SameText oder gleichen Schluessel). SameText vergleicht ohne
// Gross/Klein nur im ASCII-Bereich, LowerCase faltet genau diesen Bereich -
// zwei SameText-gleiche Namen haben also denselben Schluessel. Jeder Treffer
// liegt damit im Eimer seines Schluessels, und die Eimer halten die
// Listenreihenfolge: gleiche Funde, gleiche Reihenfolge wie der lineare
// Lauf (Test Index_MatchesLinearScan).
//
// Stand: Sync baut den Index neu, wenn sich die Liste (Zeiger oder Anzahl)
// oder der Stempel des Aufrufers geaendert hat. Den Stempel rechnet
// FindingsStampOf aus den Generationen des Docks (Voll-Befuellung und
// Watch-Laeufe je Datei); jeder Schreiber der Liste dreht eine davon mit
// NextFindingsGeneration weiter, einem steigenden Zaehler - der Stempel
// steigt also mit jedem Schreiben. Die Zeiger im Index gelten nur bis zum
// naechsten Schreiben der Liste; vor jeder Abfrage Sync.

interface

uses
  System.Generics.Collections,
  uMethodd12;                   // TLeakFinding

// Derselbe Pfad? '/' gegen '\' und Gross/Klein wie NormalizePathForKey
// (Review nach Bereichen 2026-10-10, Nit 44) - die Laenge zuerst, das
// laesst die meisten Funde anderer Dateien ohne Kopie durch. AFileKey ist
// NormalizePathForKey(AFile).
function SameFindingFile(const AName, AFile, AFileKey: string): Boolean;

// Funde aus ACandidates in deren Reihenfolge, deren Datei AFile ist
// (SameFindingFile) und deren Bereich - Ankerzeile bis SpanEnd, gedeckelt
// auf Anker + AMaxSpan wie beim Highlighter - ALine einschliesst. Derselbe
// Fund kann aus zwei Scans (Projekt + Datei) in der Liste stehen - er
// erscheint einmal (Identitaet FindingIdentityKey, wie der Fingerabdruck
// der Gluehbirne). nil-Liste und nil-Eintraege ergeben nichts.
function FindingsAtLine(ACandidates: TList<TLeakFinding>;
  const AFile, AFileKey: string; ALine, AMaxSpan: Integer): TArray<TLeakFinding>;

// Stempel des Dock-Stands: die groesste der Generationen (Voll-Befuellung
// und Watch-Laeufe je Datei). AFileGens darf nil sein.
function FindingsStampOf(AFullGen: UInt64;
  AFileGens: TDictionary<string, UInt64>): UInt64;

type
  TFindingFileIndex = class
  private
    FBuckets : TObjectDictionary<string, TList<TLeakFinding>>;
    FSource  : TList<TLeakFinding>;   // nur zum Vergleich, nie gelesen
    FCount   : Integer;               // FSource.Count beim Bau
    FStamp   : UInt64;
    FBuilt   : Boolean;
    FBuilds  : Integer;
    // Der Eimer zu AKey; legt ihn an, wenn es ihn noch nicht gibt.
    function BucketOf(const AKey: string): TList<TLeakFinding>;
    procedure Rebuild(AList: TList<TLeakFinding>; AStamp: UInt64);
  public
    constructor Create;
    destructor Destroy; override;
    // Index auf AList im Stand AStamp bringen: baut neu, wenn er noch nie
    // gebaut wurde oder Liste, Anzahl oder Stempel abweichen. nil-Liste:
    // leerer Index. nil-Eintraege fehlen im Index.
    procedure Sync(AList: TList<TLeakFinding>; AStamp: UInt64);
    // Die Funde mit Schluessel AFileKey in Listenreihenfolge (gehoert dem
    // Index, gilt bis zum naechsten Neubau); nil, wenn es keine gibt.
    function Candidates(const AFileKey: string): TList<TLeakFinding>;
    // Haelt die Liste einen Fund der Datei AFile (SameFindingFile)?
    function HasFile(const AFile, AFileKey: string): Boolean;
    // Zahl der Neubauten seit Create - fuer die Tests.
    property Builds: Integer read FBuilds;
  end;

implementation

uses
  System.SysUtils,              // SameText
  uPathNormalize,               // NormalizePathForKey
  uFindingActionMenu;           // FindingIdentityKey

function SameFindingFile(const AName, AFile, AFileKey: string): Boolean;
begin
  Result := (Length(AName) = Length(AFile))
    and (SameText(AName, AFile) or (NormalizePathForKey(AName) = AFileKey));
end;

// Steht derselbe Fund (FindingIdentityKey) schon in AFound?
function AlreadyFound(AFound: TList<TLeakFinding>;
  AFinding: TLeakFinding): Boolean;
var
  k   : Integer;
  Key : string;
begin
  Result := False;
  Key := FindingIdentityKey(AFinding);
  for k := 0 to AFound.Count - 1 do
    if FindingIdentityKey(AFound[k]) = Key then
      Exit(True);
end;

function FindingsAtLine(ACandidates: TList<TLeakFinding>;
  const AFile, AFileKey: string; ALine, AMaxSpan: Integer): TArray<TLeakFinding>;
var
  Found   : TList<TLeakFinding>;
  F       : TLeakFinding;
  SpanEnd : Integer;
begin
  Result := nil;
  if not Assigned(ACandidates) then Exit;
  Found := TList<TLeakFinding>.Create;
  try
    for F in ACandidates do
    begin
      if not Assigned(F) or not SameFindingFile(F.FileName, AFile, AFileKey) then
        Continue;
      SpanEnd := F.SpanEnd;
      if SpanEnd > F.LineInt + AMaxSpan then
        SpanEnd := F.LineInt + AMaxSpan;
      if (ALine >= F.LineInt) and (ALine <= SpanEnd)
         and not AlreadyFound(Found, F) then
        Found.Add(F);
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function FindingsStampOf(AFullGen: UInt64;
  AFileGens: TDictionary<string, UInt64>): UInt64;
var
  Gen : UInt64;
begin
  Result := AFullGen;
  if Assigned(AFileGens) then
    for Gen in AFileGens.Values do
      if Gen > Result then
        Result := Gen;
end;

{ TFindingFileIndex }

constructor TFindingFileIndex.Create;
begin
  inherited Create;
  FBuckets := TObjectDictionary<string, TList<TLeakFinding>>.Create([doOwnsValues]);
end;

destructor TFindingFileIndex.Destroy;
begin
  FBuckets.Free;
  inherited;
end;

function TFindingFileIndex.BucketOf(const AKey: string): TList<TLeakFinding>;
begin
  if not FBuckets.TryGetValue(AKey, Result) then
  begin
    Result := TList<TLeakFinding>.Create;
    try
      FBuckets.Add(AKey, Result);   // ab hier gehoert er dem Dictionary
    except
      Result.Free;
      raise;
    end;
  end;
end;

procedure TFindingFileIndex.Rebuild(AList: TList<TLeakFinding>;
  AStamp: UInt64);
var
  F        : TLeakFinding;
  Bucket   : TList<TLeakFinding>;
  LastName : string;
begin
  FBuckets.Clear;
  FSource := AList;
  FCount  := 0;
  FStamp  := AStamp;
  FBuilt  := True;
  Inc(FBuilds);
  if not Assigned(AList) then Exit;
  FCount := AList.Count;
  // Die Funde einer Datei stehen meist hintereinander: den Schluessel des
  // vorigen Namens wiederverwenden spart die Normalisierung je Fund.
  // Bucket = nil heisst: noch kein Fund gesehen.
  Bucket   := nil;
  LastName := '';
  for F in AList do
  begin
    if not Assigned(F) then Continue;
    if (Bucket = nil) or (F.FileName <> LastName) then
    begin
      LastName := F.FileName;
      Bucket   := BucketOf(NormalizePathForKey(LastName));
    end;
    Bucket.Add(F);
  end;
end;

procedure TFindingFileIndex.Sync(AList: TList<TLeakFinding>; AStamp: UInt64);
var
  Count : Integer;
begin
  Count := 0;
  if Assigned(AList) then
    Count := AList.Count;
  if FBuilt and (AList = FSource) and (Count = FCount)
     and (AStamp = FStamp) then
    Exit;
  Rebuild(AList, AStamp);
end;

function TFindingFileIndex.Candidates(
  const AFileKey: string): TList<TLeakFinding>;
begin
  if not FBuckets.TryGetValue(AFileKey, Result) then
    Result := nil;
end;

function TFindingFileIndex.HasFile(const AFile, AFileKey: string): Boolean;
var
  Bucket : TList<TLeakFinding>;
  F      : TLeakFinding;
begin
  Result := False;
  Bucket := Candidates(AFileKey);
  if not Assigned(Bucket) then Exit;
  for F in Bucket do
    if SameFindingFile(F.FileName, AFile, AFileKey) then
      Exit(True);
end;

end.
