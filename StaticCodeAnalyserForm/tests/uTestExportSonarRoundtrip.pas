unit uTestExportSonarRoundtrip;

// Tests fuer die Befunde der Sonar-Roundtrip-Pruefung vom 2026-10-29:
// Faelle, in denen ein formal gueltiger Report beim Import trotzdem Funde
// verliert oder den Scanner abbrechen laesst, weil er nicht zu den Dateien
// passt, die Sonar indexiert.
//
// Eigene Unit, weil uTestExportSonarGeneric an der GodClass-Schwelle steht
// (s. Kopf von uTestExportSonarTextRange). Die Faelle brauchen ECHTE
// Dateien - Sonar vergleicht gegen die Platte, also tut es der Export auch.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  uMethodd12, uSCAConsts;

type
  [TestFixture]
  TTestExportSonarRoundtrip = class
  private
    FDir     : string;
    FOldTier : Boolean;
    procedure WriteBytes(const ARel: string; const ABytes: TBytes);
    function  Report(const AFindings: TObjectList<TLeakFinding>): TJSONObject;
    // Liefert die Severity des ersten Impacts der Regel im Export.
    function  CappedImpact(AFindings: TObjectList<TLeakFinding>;
      const ARuleID: string; AKeepDowngraded: Boolean = False): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    // Gross-/Kleinschreibung: Sonar vergleicht den Pfad exakt
    [Test] procedure FilePath_TakesCasingFromDisk;
    [Test] procedure FilePath_MissingFileKeepsSpelling;
    // Zeilen, die Sonar nicht kennt: Scanner-Abbruch statt Fund
    [Test] procedure BinaryFile_IssueOnFileLevel;
    [Test] procedure LineBeyondEof_IssueOnFileLevel;
    [Test] procedure EndLineBeyondEof_IsClamped;
    [Test] procedure LoneCr_CountsAsLineLikeSonar;
    [Test] procedure UnreadableFile_KeepsTextRange;
    // Lesefehler nach dem Oeffnen: wie die gesperrte Datei, nicht "eine Zeile"
    [Test] procedure ReadErrorOnFirstRead_KeepsTextRange;
    [Test] procedure ReadErrorInSecondBuffer_KeepsTextRange;
    [Test] procedure EmptyFile_StaysReadable;
    // Custom-Regeln: YAML-Severity ist keine Herabstufung
    [Test] procedure CustomRuleHint_IsExportedWithLowImpact;
    [Test] procedure CustomRuleError_GetsHighImpactAndOwnName;
    // ... eine Pfad-Ueberschreibung aber sehr wohl
    [Test] procedure CustomRulePathDowngrade_StaysOutAndKeepsYamlImpact;
    // UTF-16 mit BOM ist Text
    [Test] procedure Utf16Bom_IsTextNotBinary;
    // Konfidenz-Deckel ist keine Herabstufung (Nico-Entscheid 2026-10-29)
    [Test] procedure CappedErrorRule_IsExportedWithCappedImpact;
    [Test] procedure CappedFinding_PathDowngrade_StaysOut;
    [Test] procedure TieringOff_KeepsCatalogImpact;
    // Deckel je Lauf und Regel statt je Kind (Review 2026-10-31)
    [Test] procedure RunCap_OnlyUnprovenFindings_RuleCapped;
    [Test] procedure RunCap_DefaultHighKindCappedByPolicy_RuleCapped;
    [Test] procedure RunCap_OneFullFinding_RuleStaysFull;
    [Test] procedure RunCap_FullFindingOfMediumKind_RuleIsFull;
    [Test] procedure RunCap_OnlyHintFindings_RuleCappedToLow;
    [Test] procedure RunCap_TieringOff_CatalogUnchanged;
    [Test] procedure RunCap_WarningRuleWithCatalogHigh_Unchanged;
    [Test] procedure RunCap_PathUpgrade_CountsAsFull;
    [Test] procedure RunCap_DowngradedFullFinding_FollowsExportSet;
    [Test] procedure RunCap_CustomRule_FollowsItsFindings;
    [Test] procedure RunCap_RuleOrderStaysFirstOccurrence;
  end;

implementation

uses
  Winapi.Windows,          // LockFile - echter Lesefehler nach dem Oeffnen
  System.IOUtils,
  uEvidenceTiering,
  uExportSonarGeneric;

const
  KEY_ISSUES   = 'issues';
  KEY_PRIMARY  = 'primaryLocation';
  MSG_NOT_JSON = 'Report ist kein gueltiges JSON-Object';
  // Katalog-Regeln der Deckel-Tests
  RULE_PRECEDENCE = 'SCA202';   // Error, RELIABILITY/HIGH, Default fcHigh
  RULE_SECRET     = 'SCA004';   // Error, SECURITY/BLOCKER, Default fcMedium

function MakeFinding(AKind: TFindingKind; const AFile: string;
  ALine: Integer): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(AKind);
  Result.FileName   := AFile;
  Result.LineNumber := IntToStr(ALine);
  Result.MissingVar := 'probe';
end;

function FirstIssue(ARoot: TJSONObject): TJSONObject;
begin
  Result := ARoot.GetValue<TJSONArray>(KEY_ISSUES).Items[0] as TJSONObject;
end;

function TextRangeOf(ARoot: TJSONObject): TJSONObject;
// nil, wenn das Issue auf Dateiebene steht.
var
  V : TJSONValue;
begin
  V := FirstIssue(ARoot).GetValue<TJSONObject>(KEY_PRIMARY).GetValue('textRange');
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    Result := nil;
end;

function FilePathOf(ARoot: TJSONObject): string;
begin
  Result := FirstIssue(ARoot).GetValue<TJSONObject>(KEY_PRIMARY)
              .GetValue<string>('filePath');
end;

procedure TTestExportSonarRoundtrip.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_sonar_rt_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(FDir);
  FOldTier := uSCAConsts.LastScanEvidenceTiering;
end;

procedure TTestExportSonarRoundtrip.TearDown;
begin
  uSCAConsts.LastScanEvidenceTiering := FOldTier;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestExportSonarRoundtrip.WriteBytes(const ARel: string;
  const ABytes: TBytes);
var
  Full : string;
begin
  Full := TPath.Combine(FDir, ARel);
  TDirectory.CreateDirectory(ExtractFilePath(Full));
  TFile.WriteAllBytes(Full, ABytes);
end;

function TTestExportSonarRoundtrip.Report(
  const AFindings: TObjectList<TLeakFinding>): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(
    TSonarGenericWriter.ToJsonString(AFindings, FDir)) as TJSONObject;
  Assert.IsNotNull(Result, MSG_NOT_JSON);
end;

{ ---- Gross-/Kleinschreibung ---- }

procedure TTestExportSonarRoundtrip.FilePath_TakesCasingFromDisk;
// Die Engine bildet den DFM-Namen aus dem Unit-Namen; auf der Platte heisst
// die Datei 'ABOUT.DFM'. Windows findet sie trotzdem, Sonar nicht - dort
// muss der filePath exakt der Verzeichnis-Schreibweise folgen, auch im
// Ordnerteil.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes(TPath.Combine('Forms', 'ABOUT.DFM'), TEncoding.ASCII.GetBytes(
    'object AboutBox: TAboutBox' + sLineBreak + 'end' + sLineBreak));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkDfmDefaultName,
      TPath.Combine(TPath.Combine(FDir, 'FORMS'), 'ABOUT.dfm'), 1));
    Root := Report(Findings);
    Assert.AreEqual('Forms/ABOUT.DFM', FilePathOf(Root));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.FilePath_MissingFileKeepsSpelling;
// Gibt es die Datei nicht (mehr), bleibt der Pfad wie er war - lieber den
// Fund unveraendert durchreichen als eine Schreibweise erfinden.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak,
      TPath.Combine(TPath.Combine(FDir, 'gibtsnicht'), 'Weg.PAS'), 3));
    Root := Report(Findings);
    Assert.AreEqual('gibtsnicht/Weg.PAS', FilePathOf(Root));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

{ ---- Zeilen, die Sonar nicht kennt ---- }

procedure TTestExportSonarRoundtrip.BinaryFile_IssueOnFileLevel;
// Binaere DFM: die Engine zaehlt Zeilen der TEXT-Umwandlung, Sonar die der
// Binaerdatei. Eine Zeile dahinter laesst den Scanner abbrechen ("N is not a
// valid line for pointer"); und selbst eine Zeile innerhalb der Grenzen
// zeigt auf Binaermuell. Also Dateiebene: keine textRange.
//
// Zeile 1 mit Absicht: die Datei hat nach Sonar ZWEI Zeilen (ein $0A), der
// Fund liegt also in den Grenzen. Mit einer Zeile dahinter waere der Test
// auch ohne die NUL-Erkennung gruen (LineBeyondEof deckt jenen Zweig).
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Bin.dfm', TBytes.Create($FF, $0A, $00, Ord('T'), Ord('P'),
    Ord('F'), Ord('0'), $00, $01, $02));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkDfmDefaultName, TPath.Combine(FDir, 'Bin.dfm'), 1));
    Root := Report(Findings);
    Assert.IsNull(TextRangeOf(Root), 'binaere Datei: Issue ohne textRange');
    Assert.AreEqual('Bin.dfm', FilePathOf(Root), 'der Fund selbst bleibt');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.LineBeyondEof_IssueOnFileLevel;
// Zwei Zeilen nach Sonar ('a', 'b'), Fund auf Zeile 7.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Kurz.pas', TEncoding.ASCII.GetBytes('a'#13#10'b'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Kurz.pas'), 7));
    Root := Report(Findings);
    Assert.IsNull(TextRangeOf(Root), 'Zeile hinter dem Dateiende: Dateiebene');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.EndLineBeyondEof_IsClamped;
// Fuenf Zeilen nach Sonar (vier CRLF + 'e'), Fund 2..9: endLine wird 5.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Fuenf.pas', TEncoding.ASCII.GetBytes(
    'a'#13#10'b'#13#10'c'#13#10'd'#13#10'e'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := MakeFinding(fkLongMethod, TPath.Combine(FDir, 'Fuenf.pas'), 2);
    F.EndLine := 9;
    Findings.Add(F);
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root));
    Assert.AreEqual<Integer>(2, TextRangeOf(Root).GetValue<Integer>('startLine'));
    Assert.AreEqual<Integer>(5, TextRangeOf(Root).GetValue<Integer>('endLine'));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.LoneCr_CountsAsLineLikeSonar;
// Sonar zaehlt ein einzelnes CR als Zeilenende: 'a'#13'b'#13'c' hat drei
// Zeilen, Zeile 3 ist gueltig und behaelt ihre textRange.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Cr.pas', TEncoding.ASCII.GetBytes('a'#13'b'#13'c'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Cr.pas'), 3));
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root), 'Zeile 3 existiert nach Sonar-Zaehlung');
    Assert.AreEqual<Integer>(3, TextRangeOf(Root).GetValue<Integer>('startLine'));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.UnreadableFile_KeepsTextRange;
// Ohne lesbare Datei weiss der Export nichts ueber ihre Zeilen - dann bleibt
// der Fund wie er ist (das ist auch der Fall aller Tests mit erfundenen
// Pfaden in uTestExportSonarGeneric).
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Fehlt.pas'), 42));
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root));
    Assert.AreEqual<Integer>(42, TextRangeOf(Root).GetValue<Integer>('startLine'));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

{ ---- Lesefehler nach dem Oeffnen ---- }

function LockRange(const APath: string; AOffset,
  ACount: Cardinal): TFileStream;
// Haelt eine exklusive Bereichssperre auf APath, solange der Stream lebt.
// TFileStream oeffnet die Datei trotzdem (fmShareDenyNone), ReadFile im
// gesperrten Bereich scheitert aber mit ERROR_LOCK_VIOLATION - das ist ein
// ECHTER Lesefehler, ohne Mock und ohne defekte Platte. Mit dem Schliessen
// faellt die Sperre.
begin
  Result := TFileStream.Create(APath, fmOpenReadWrite or fmShareDenyNone);
  if not LockFile(Result.Handle, AOffset, 0, ACount, 0) then
  begin
    Result.Free;
    RaiseLastOSError;
  end;
end;

procedure TTestExportSonarRoundtrip.ReadErrorOnFirstRead_KeepsTextRange;
// FS.Read scheitert gleich beim ersten Puffer. THandleStream.Read macht aus
// dem -1 eine 0, die Datei sah damit leer aus: "lesbar, eine Zeile", und der
// Fund auf Zeile 3 rutschte auf Dateiebene. Richtig ist die Behandlung der
// gesperrten Datei: Default-Sicht, der Fund bleibt, wie er ist.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Lock     : TFileStream;
begin
  Root := nil;
  WriteBytes('Gesperrt.pas', TEncoding.ASCII.GetBytes('a'#13#10'b'#13#10'c'));
  Lock := LockRange(TPath.Combine(FDir, 'Gesperrt.pas'), 0, 1024);
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Gesperrt.pas'), 3));
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root), 'Lesefehler: der Fund behaelt seine Zeile');
    Assert.AreEqual<Integer>(3, TextRangeOf(Root).GetValue<Integer>('startLine'));
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'der Report bricht nicht ab');
  finally
    Root.Free;
    Findings.Free;
    Lock.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.ReadErrorInSecondBuffer_KeepsTextRange;
// Der erste Puffer (64 KiB) kommt durch, der zweite Read scheitert. Die
// Schleife endete dort still mit der halben Zeilenzahl; eine Zeile dahinter
// galt als hinter dem Dateiende. Eine Pruefung nur des ersten Read saehe
// das nicht. Auch endLine bleibt ungeklemmt: die Zeilenzahl ist unbekannt.
const
  LINE_BYTES = 2;       // 'a' + LF
  LINE_COUNT = 50000;   // 100.000 Bytes, also mehr als ein Puffer
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Root     : TJSONObject;
  Lock     : TFileStream;
  Body     : TBytes;
  I        : Integer;
begin
  Root := nil;
  SetLength(Body, LINE_COUNT * LINE_BYTES);
  for I := 0 to LINE_COUNT - 1 do
  begin
    Body[I * LINE_BYTES]     := Ord('a');
    Body[I * LINE_BYTES + 1] := 10;
  end;
  WriteBytes('Lang.pas', Body);
  Lock := LockRange(TPath.Combine(FDir, 'Lang.pas'), 70000, 1024);
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := MakeFinding(fkLongMethod, TPath.Combine(FDir, 'Lang.pas'), 40000);
    F.EndLine := 40010;
    Findings.Add(F);
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root),
      'Lesefehler im zweiten Puffer: der Fund behaelt seine Zeile');
    Assert.AreEqual<Integer>(40000, TextRangeOf(Root).GetValue<Integer>('startLine'));
    Assert.AreEqual<Integer>(40010, TextRangeOf(Root).GetValue<Integer>('endLine'));
  finally
    Root.Free;
    Findings.Free;
    Lock.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.EmptyFile_StaysReadable;
// Die Gegenprobe zu den beiden Lesefehlern: Read liefert hier ebenfalls 0,
// aber die Datei IST leer. Sonar kennt genau eine Zeile; ein Fund auf Zeile
// 5 muss weiter auf Dateiebene landen, sonst steigt der Scanner aus. Eine
// Fehlerpruefung auf N = 0 faende hier einen Lesefehler, den es nicht gibt.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  TFileStream.Create(TPath.Combine(FDir, 'Leer.pas'), fmCreate).Free;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Leer.pas'), 5));
    Root := Report(Findings);
    Assert.IsNull(TextRangeOf(Root), 'leere Datei: Zeile 5 gibt es nicht');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

{ ---- Custom-Regeln ---- }

function CustomFinding(const AFile, ARuleID: string;
  ASeverity: TLeakSeverity): TLeakFinding;
// Wie uCustomRuleDetector: Kind per Feldzuweisung, Severity aus der YAML.
begin
  Result := MakeFinding(fkCustomRule, AFile, 4);
  Result.RuleID   := ARuleID;
  Result.Severity := ASeverity;
end;

function FirstRule(ARoot: TJSONObject): TJSONObject;
begin
  Result := ARoot.GetValue<TJSONArray>('rules').Items[0] as TJSONObject;
end;

function ImpactSeverityOf(ARule: TJSONObject): string;
begin
  Result := (ARule.GetValue<TJSONArray>('impacts').Items[0] as TJSONObject)
              .GetValue<string>('severity');
end;

procedure TTestExportSonarRoundtrip.CustomRuleHint_IsExportedWithLowImpact;
// Bis 2026-10-29 verglich IsDowngraded die YAML-Severity 'hint' mit dem
// Katalog-Platzhalter SCA023 (Warning) und warf den Fund still raus.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(CustomFinding(TPath.Combine(FDir, 'X.pas'), 'MINI001', lsHint));
    Root := Report(Findings);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'Custom-Regel mit severity hint gehoert in den Report');
    Assert.AreEqual('MINI001', FirstRule(Root).GetValue<string>('id'));
    Assert.AreEqual('LOW', ImpactSeverityOf(FirstRule(Root)));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.CustomRuleError_GetsHighImpactAndOwnName;
// 'error' kam bisher als MEDIUM des Platzhalters an, und alle Custom-Regeln
// hiessen in Sonar gleich.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Name     : string;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(CustomFinding(TPath.Combine(FDir, 'X.pas'), 'MINI002', lsError));
    Root := Report(Findings);
    Assert.AreEqual('HIGH', ImpactSeverityOf(FirstRule(Root)));
    Name := FirstRule(Root).GetValue<string>('name');
    Assert.IsTrue(Pos('MINI002', Name) > 0, 'Regelname nennt die ID: ' + Name);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.CustomRulePathDowngrade_StaysOutAndKeepsYamlImpact;
// YAML 'error', in generiertem Code per Pfad-Ueberschreibung auf Hint
// gesetzt (OverrideSeverity, wie uPathOverrides): das IST eine Herabstufung
// und bleibt ohne --sonar-keep-downgraded draussen. Mit dem Schalter steht
// der Fund als ERSTER in der Liste - die Regel muss trotzdem HIGH bleiben,
// sonst bestimmte ein einzelner Fund in generiertem Code die Schwere aller.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := CustomFinding(TPath.Combine(FDir, 'Gen.pas'), 'MINI003', lsError);
    F.OverrideSeverity(lsHint);
    Findings.Add(F);
    Findings.Add(CustomFinding(TPath.Combine(FDir, 'Hand.pas'), 'MINI003', lsError));

    Root := Report(Findings);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'herabgestufter Custom-Fund bleibt draussen, der andere nicht');
    Assert.AreEqual('HIGH', ImpactSeverityOf(FirstRule(Root)));
    FreeAndNil(Root);

    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, FDir, True)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(2, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'mit --sonar-keep-downgraded beide');
    Assert.AreEqual('HIGH', ImpactSeverityOf(FirstRule(Root)),
      'Impact aus der YAML-Severity, nicht aus dem herabgestuften ersten Fund');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

{ ---- UTF-16 mit BOM ---- }

procedure TTestExportSonarRoundtrip.Utf16Bom_IsTextNotBinary;
// UTF-16LE mit BOM, 'a' CRLF 'b' CRLF 'c': drei Zeilen. Bytebasiert sah die
// Datei binaer aus (NUL nach jedem ASCII-Zeichen) und jedes CRLF zaehlte
// doppelt. Zeile 3 behaelt ihre textRange, Zeile 4 gibt es nicht.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Body     : TBytes;
begin
  Root := nil;
  Body := TEncoding.Unicode.GetBytes('a'#13#10'b'#13#10'c');
  WriteBytes('Wide.pas', TBytes.Create($FF, $FE) + Body);
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Wide.pas'), 3));
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root), 'UTF-16 mit BOM ist Text');
    Assert.AreEqual<Integer>(3, TextRangeOf(Root).GetValue<Integer>('startLine'));
    FreeAndNil(Root);
    Findings.Clear;
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Wide.pas'), 4));
    Root := Report(Findings);
    Assert.IsNull(TextRangeOf(Root), 'Zeile 4 gibt es nicht - CRLF zaehlt einmal');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

{ ---- Konfidenz-Deckel ---- }

function CappedSecret(const AFile: string;
  AFindings: TObjectList<TLeakFinding>): TLeakFinding;
// SCA004: Katalog Error + SECURITY/BLOCKER, Standard-Konfidenz medium. Der
// Deckel laeuft wie im Scan ueber TEvidenceTiering - nicht nachgebaut.
begin
  Result := MakeFinding(fkHardcodedSecret, AFile, 2);
  AFindings.Add(Result);
  TEvidenceTiering.ApplyToFindings(AFindings);
end;

procedure TTestExportSonarRoundtrip.CappedErrorRule_IsExportedWithCappedImpact;
// Bis 2026-10-29 galt der gedeckelte Fund als herabgestuft und fehlte in
// Sonar ganz (JVCL SCA003 10 von 10). Jetzt geht er mit - und die Regel
// traegt die gedeckelte Schwere: Warning -> hoechstens MEDIUM, nicht der
// BLOCKER des Katalogs.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Imp      : TJSONObject;
  OldTier  : Boolean;
begin
  Root    := nil;
  OldTier := uSCAConsts.LastScanEvidenceTiering;
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    CappedSecret(TPath.Combine(FDir, 'Secret.pas'), Findings);
    Assert.AreEqual(Ord(lsWarning), Ord(Findings[0].Severity),
      'Vorbedingung: der Deckel hat auf Warning gesetzt');
    Root := Report(Findings);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'gedeckelter Fund gehoert in den Report');
    Imp := FirstRule(Root).GetValue<TJSONArray>('impacts').Items[0] as TJSONObject;
    Assert.AreEqual('SECURITY', Imp.GetValue<string>('softwareQuality'));
    Assert.AreEqual('MEDIUM', Imp.GetValue<string>('severity'),
      'Impact = gedeckelte Schwere, nicht Katalog-BLOCKER');
  finally
    Root.Free;
    Findings.Free;
    uSCAConsts.LastScanEvidenceTiering := OldTier;
  end;
end;

procedure TTestExportSonarRoundtrip.CappedFinding_PathDowngrade_StaysOut;
// Gegenprobe: auf den gedeckelten Fund setzt eine Pfad-Ueberschreibung noch
// Hint - DAS ist eine Nutzer-Herabstufung und bleibt draussen; mit
// --sonar-keep-downgraded kommt sie wieder.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  OldTier  : Boolean;
begin
  Root    := nil;
  OldTier := uSCAConsts.LastScanEvidenceTiering;
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    CappedSecret(TPath.Combine(FDir, 'Gen.pas'), Findings).OverrideSeverity(lsHint);
    Root := Report(Findings);
    Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'Pfad-Herabstufung bleibt draussen');
    FreeAndNil(Root);
    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, FDir, True)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'mit --sonar-keep-downgraded drin');
  finally
    Root.Free;
    Findings.Free;
    uSCAConsts.LastScanEvidenceTiering := OldTier;
  end;
end;

procedure TTestExportSonarRoundtrip.TieringOff_KeepsCatalogImpact;
// [Rules] EvidenceTiering=0: kein Deckel, also auch kein gedeckelter Impact -
// der Katalog-BLOCKER bleibt.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  OldTier  : Boolean;
begin
  Root    := nil;
  OldTier := uSCAConsts.LastScanEvidenceTiering;
  uSCAConsts.LastScanEvidenceTiering := False;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkHardcodedSecret, TPath.Combine(FDir, 'S.pas'), 2));
    Root := Report(Findings);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count);
    Assert.AreEqual('BLOCKER', ImpactSeverityOf(FirstRule(Root)));
  finally
    Root.Free;
    Findings.Free;
    uSCAConsts.LastScanEvidenceTiering := OldTier;
  end;
end;

{ ---- Deckel je Lauf und Regel ---- }

function TTestExportSonarRoundtrip.CappedImpact(
  AFindings: TObjectList<TLeakFinding>; const ARuleID: string;
  AKeepDowngraded: Boolean): string;
var
  Root  : TJSONObject;
  Rules : TJSONArray;
  I     : Integer;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(TSonarGenericWriter.ToJsonString(
    AFindings, FDir, AKeepDowngraded)) as TJSONObject;
  Assert.IsNotNull(Root, MSG_NOT_JSON);
  try
    Rules := Root.GetValue<TJSONArray>('rules');
    for I := 0 to Rules.Count - 1 do
      if (Rules.Items[I] as TJSONObject).GetValue<string>('id') = ARuleID then
        Exit(ImpactSeverityOf(Rules.Items[I] as TJSONObject));
  finally
    Root.Free;
  end;
end;

function UnprovenFinding(AKind: TFindingKind; const AFile: string;
  ALine: Integer): TLeakFinding;
// Wie uComparisonPrecedence, uLoopPastHighBound und uFunctionNameResult ohne
// Beleg: der Detektor senkt selbst auf Warning/fcMedium, per Feldzuweisung
// und nicht per OverrideSeverity.
begin
  Result := MakeFinding(AKind, AFile, ALine);
  Result.Confidence := fcMedium;
  Result.Severity   := lsWarning;
end;

procedure TTestExportSonarRoundtrip.RunCap_OnlyUnprovenFindings_RuleCapped;
// Der Fund aus dem Review: SCA202 ist Kind-Default fcHigh, also griff der
// alte Kind-Deckel nicht, und ein unbewiesener Fund zeigte in Sonar HIGH.
var
  Findings : TObjectList<TLeakFinding>;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(UnprovenFinding(fkComparisonPrecedence, 'A.pas', 1));
    Findings.Add(UnprovenFinding(fkComparisonPrecedence, 'B.pas', 2));
    Assert.AreEqual('MEDIUM', CappedImpact(Findings, RULE_PRECEDENCE),
      'nur unbewiesene Funde: Warning -> hoechstens MEDIUM');
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_DefaultHighKindCappedByPolicy_RuleCapped;
// Die zweite Form desselben Falls: der Detektor senkt nur die Konfidenz
// (SCA166 bei Verdacht), die Schwere deckelt erst die Politik im Scan.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := TLeakFinding.New('A.pas', 'M', 3, 'read before write', fkUninitVar,
      fcMedium);
    Findings.Add(F);
    TEvidenceTiering.ApplyToFindings(Findings);
    Assert.AreEqual(Ord(lsWarning), Ord(F.Severity),
      'Vorbedingung: der Deckel hat den Fund gesenkt');
    Assert.AreEqual('MEDIUM', CappedImpact(Findings, 'SCA166'));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_OneFullFinding_RuleStaysFull;
// Reihenfolge mit Absicht: der volle Fund steht HINTER dem unbewiesenen.
// Wer nur den ersten Fund der Regel ansieht, bekaeme hier MEDIUM.
var
  Findings : TObjectList<TLeakFinding>;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(UnprovenFinding(fkComparisonPrecedence, 'A.pas', 1));
    Findings.Add(MakeFinding(fkComparisonPrecedence, 'B.pas', 2));
    Assert.AreEqual('HIGH', CappedImpact(Findings, RULE_PRECEDENCE),
      'ein voller Fund: die Regel bleibt voll');
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_FullFindingOfMediumKind_RuleIsFull;
// Die Gegenrichtung zum alten Kind-Deckel: SCA004 ist Kind-Default fcMedium,
// der Detektor belegt manche Treffer aber mit fcHigh. Der Fund traegt im
// Lauf Error, die Regel darf nicht darunter bleiben. Ohne ihn: MEDIUM.
var
  Findings : TObjectList<TLeakFinding>;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkHardcodedSecret, 'A.pas', 1));
    TEvidenceTiering.ApplyToFindings(Findings);
    Assert.AreEqual('MEDIUM', CappedImpact(Findings, RULE_SECRET));
    Findings.Add(TLeakFinding.New('B.pas', '', 2, 'AWS key', fkHardcodedSecret,
      fcHigh));
    TEvidenceTiering.ApplyToFindings(Findings);
    Assert.AreEqual('BLOCKER', CappedImpact(Findings, RULE_SECRET));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_OnlyHintFindings_RuleCappedToLow;
// Schwaecher als Warning: alle Funde sind Hint (uLeakDetector2 meldet den
// nicht freigegebenen Rueckgabewert so), die Regel traegt hoechstens LOW.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := MakeFinding(fkMemoryLeak, 'A.pas', 1);
    F.Severity := lsHint;
    Findings.Add(F);
    Assert.AreEqual('LOW', CappedImpact(Findings, 'SCA001'));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_TieringOff_CatalogUnchanged;
// [Rules] EvidenceTiering=0: nichts wird gedeckelt, auch nicht je Lauf -
// dieselben Funde wie in RunCap_OnlyUnprovenFindings_RuleCapped.
var
  Findings : TObjectList<TLeakFinding>;
begin
  uSCAConsts.LastScanEvidenceTiering := False;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(UnprovenFinding(fkComparisonPrecedence, 'A.pas', 1));
    Assert.AreEqual('HIGH', CappedImpact(Findings, RULE_PRECEDENCE));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_WarningRuleWithCatalogHigh_Unchanged;
// Haelt die Grenze des Deckels fest: SCA008 fuehrt Warning mit Katalog-HIGH,
// jeder Fund traegt fcMedium. Die Politik senkt ihn nicht unter die Katalog-
// Schwere, also bleibt der Impact (s. RunCappedMeta). Aendert sich das,
// aendern sich auch SCA124, SCA138, SCA162 und SCA196 - ein eigener Entscheid.
var
  Findings : TObjectList<TLeakFinding>;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkNilDeref, 'A.pas', 1));
    Assert.AreEqual('HIGH', CappedImpact(Findings, 'SCA008'));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_PathUpgrade_CountsAsFull;
// poaSeverityError hat das letzte Wort gegen die Politik. Ein so
// hochgestufter Fund ist im Lauf ein Error und traegt die Regel.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := UnprovenFinding(fkComparisonPrecedence, 'A.pas', 1);
    Findings.Add(F);
    TEvidenceTiering.ApplyToFindings(Findings);
    F.OverrideSeverity(lsError);
    Assert.AreEqual('HIGH', CappedImpact(Findings, RULE_PRECEDENCE));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_DowngradedFullFinding_FollowsExportSet;
// Die Regel richtet sich nach den Funden, die der Export wirklich traegt:
// ein voller Fund, den ein Nutzer herabgestuft hat, bleibt draussen und darf
// die Regel nicht tragen. Mit --sonar-keep-downgraded ist er wieder dabei.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(UnprovenFinding(fkComparisonPrecedence, 'A.pas', 1));
    F := MakeFinding(fkComparisonPrecedence, 'Gen.pas', 2);
    F.OverrideSeverity(lsHint);
    Findings.Add(F);
    Assert.AreEqual('MEDIUM', CappedImpact(Findings, RULE_PRECEDENCE));
    Assert.AreEqual('HIGH', CappedImpact(Findings, RULE_PRECEDENCE, True));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_CustomRule_FollowsItsFindings;
// Der Custom-Pfad baut seinen Impact selbst (CustomRuleMeta). Heute tragen
// Custom-Funde immer fcHigh, der Pfad muss dem Lauf aber genauso folgen -
// und eine Pfad-Hochstufung darf die YAML-Severity nicht uebersteigen.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
begin
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := CustomFinding('A.pas', 'MINI010', lsError);
    F.Confidence := fcMedium;
    Findings.Add(F);
    Assert.AreEqual('MEDIUM', CappedImpact(Findings, 'MINI010'));
    Findings.Add(CustomFinding('B.pas', 'MINI010', lsError));
    Assert.AreEqual('HIGH', CappedImpact(Findings, 'MINI010'));
    Findings.Clear;
    F := CustomFinding('C.pas', 'MINI011', lsHint);
    F.OverrideSeverity(lsError);
    Findings.Add(F);
    Assert.AreEqual('LOW', CappedImpact(Findings, 'MINI011'));
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.RunCap_RuleOrderStaysFirstOccurrence;
// rules[] bleibt in der Reihenfolge des ersten Auftretens und je Regel
// einmal - der Umbau in EmitRules darf daran nichts verschieben.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Rules    : TJSONArray;
begin
  Root := nil;
  uSCAConsts.LastScanEvidenceTiering := True;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkNilDeref, 'A.pas', 1));
    Findings.Add(UnprovenFinding(fkComparisonPrecedence, 'A.pas', 2));
    Findings.Add(MakeFinding(fkNilDeref, 'B.pas', 3));
    Root := Report(Findings);
    Rules := Root.GetValue<TJSONArray>('rules');
    Assert.AreEqual<Integer>(2, Rules.Count);
    Assert.AreEqual('SCA008',
      (Rules.Items[0] as TJSONObject).GetValue<string>('id'));
    Assert.AreEqual(RULE_PRECEDENCE,
      (Rules.Items[1] as TJSONObject).GetValue<string>('id'));
    Assert.AreEqual<Integer>(3, Root.GetValue<TJSONArray>(KEY_ISSUES).Count);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportSonarRoundtrip);

end.
