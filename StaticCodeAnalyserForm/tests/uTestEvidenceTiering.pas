unit uTestEvidenceTiering;

// K2 Stufe 1+2 (Konzept_FpUnter5Prozent_2026-08-26): Evidenz-Politik.
// uEvidenceTiering ist fester Pipeline-Schritt (nach Suppression, VOR
// PathOverrides) - die Tests sichern die Deckel-Matrix, die Diagnose-
// Ausnahme, den Nutzer-Vorrang der PathOverrides und den Trust-Budget-
// Demote von SCA001 (Governance-Pin, s.u.).

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uEvidenceTiering, uPathOverrides;

type
  [TestFixture]
  TTestEvidenceTiering = class
  private
    function MakeFinding(AKind: TFindingKind; ASev: TLeakSeverity;
      AConf: TFindingConfidence): TLeakFinding;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure HighError_BleibtError;
    [Test] procedure MediumError_WirdWarning;
    [Test] procedure LowFunde_WerdenHint;
    [Test] procedure Deckel_HebtNieAn;
    [Test] procedure FileReadError_BleibtUnangetastet;
    [Test] procedure RueckgabeZaehltNurGedeckelte;
    [Test] procedure PathOverride_Hochstufung_GewinntGegenDenDeckel;
    [Test] procedure MemoryLeak_DefaultKonfidenz_IstMedium;
  end;

implementation

function TTestEvidenceTiering.MakeFinding(AKind: TFindingKind;
  ASev: TLeakSeverity; AConf: TFindingConfidence): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName   := 'src\probe.pas';
  Result.MethodName := '';
  Result.LineNumber := '1';
  Result.MissingVar := 'x';
  Result.SetKind(AKind);
  // NACH SetKind: SetKind setzt KindDefaultConfidence, der Test braucht
  // aber eine DEFINIERTE Konfidenz je Fall (genau das ist der Je-Fund-
  // Pfad, den Detektoren wie uUninitVar produktiv gehen).
  Result.Confidence := AConf;
  Result.Severity   := ASev;
end;

procedure TTestEvidenceTiering.Setup;
begin
  TPathOverrides.Clear;
end;

procedure TTestEvidenceTiering.TearDown;
// Regeln nie in andere Fixtures leaken (globaler Rule-State).
begin
  TPathOverrides.Clear;
end;

procedure TTestEvidenceTiering.HighError_BleibtError;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkMemoryLeak, lsError, fcHigh));
    Assert.AreEqual<Integer>(0, TEvidenceTiering.ApplyToFindings(L),
      'fcHigh wird nie gedeckelt');
    Assert.IsTrue(L[0].Severity = lsError, 'Error bleibt Error');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.MediumError_WirdWarning;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkSQLInjection, lsError, fcMedium));
    Assert.AreEqual<Integer>(1, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsWarning,
      'fcMedium traegt hoechstens Warning ("Error = bewiesen")');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.LowFunde_WerdenHint;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkUseAfterFree, lsError,   fcLow));
    L.Add(MakeFinding(fkUseAfterFree, lsWarning, fcLow));
    Assert.AreEqual<Integer>(2, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsHint, 'fcLow: Error -> Hint');
    Assert.IsTrue(L[1].Severity = lsHint, 'fcLow: Warning -> Hint');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.Deckel_HebtNieAn;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    // Ein fcHigh-Hint bleibt Hint - der Deckel ist KEINE Buehne nach
    // oben, sonst wuerde die Politik Katalog-Severities ueberschreiben.
    L.Add(MakeFinding(fkTodoComment, lsHint, fcHigh));
    L.Add(MakeFinding(fkNilDeref,    lsWarning, fcMedium));
    Assert.AreEqual<Integer>(0, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsHint,    'Hint bleibt Hint');
    Assert.IsTrue(L[1].Severity = lsWarning, 'Warning bleibt Warning');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.FileReadError_BleibtUnangetastet;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    // Diagnose-Befund: dieselbe Ausnahme wie in uConfidenceFilter/
    // uPathOverrides/uBaseline - ein Lesefehler darf nie leiser werden,
    // egal welche Konfidenz er traegt.
    L.Add(MakeFinding(fkFileReadError, lsError, fcLow));
    Assert.AreEqual<Integer>(0, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsError, 'Diagnose bleibt Error');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.RueckgabeZaehltNurGedeckelte;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkSQLInjection, lsError,   fcMedium)); // gedeckelt
    L.Add(MakeFinding(fkMemoryLeak,   lsError,   fcHigh));   // bleibt
    L.Add(MakeFinding(fkTodoComment,  lsHint,    fcMedium)); // schon drunter
    Assert.AreEqual<Integer>(1, TEvidenceTiering.ApplyToFindings(L),
      'nur der eine Error->Warning-Fall zaehlt');
    Assert.AreEqual<Integer>(3, L.Count, 'der Deckel entfernt NIE Befunde');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.PathOverride_Hochstufung_GewinntGegenDenDeckel;
var
  L: TObjectList<TLeakFinding>;
begin
  // Pipeline-Reihenfolge: Deckel VOR PathOverrides - die explizite
  // Nutzer-Hochstufung je Pfad (poaSeverityError) behaelt das letzte
  // Wort gegen die Politik (Gegenpruefung K2). Der Test faehrt beide
  // Schritte in Produktions-Reihenfolge.
  TPathOverrides.AddRule('src/*.pas', poaSeverityError, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkSQLInjection, lsError, fcMedium));
    TEvidenceTiering.ApplyToFindings(L);
    Assert.IsTrue(L[0].Severity = lsWarning, 'Vorbedingung: Deckel griff');
    TPathOverrides.ApplyToFindings(L);
    Assert.IsTrue(L[0].Severity = lsError,
      'poaSeverityError stuft NACH dem Deckel wieder hoch - Nutzer gewinnt');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.MemoryLeak_DefaultKonfidenz_IstMedium;
begin
  // GOVERNANCE-PIN (K2 Stufe 2): SCA001 steht wegen 62-78 % Korpus-FP
  // (Voll-Audit 2026-08-15) auf fcMedium. Wer diesen Test rot macht,
  // will SCA001 re-promoten - das ist NUR mit frischer Korpus-Messung
  // unter 5 % FP je Evidenzpfad zulaessig (Trust-Budget, Konzept
  // FpUnter5Prozent). Der Pin schuetzt vor versehentlichem Zuruecksetzen.
  Assert.IsTrue(KindDefaultConfidence(fkMemoryLeak) = fcMedium,
    'SCA001 Trust-Budget-Demote (62-78 % FP) darf nicht ohne Messung kippen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEvidenceTiering);

end.
