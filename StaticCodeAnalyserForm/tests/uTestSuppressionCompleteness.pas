unit uTestSuppressionCompleteness;

// Vollstaendigkeits-Test: jeder einzelne TFindingKind muss per
// `// noinspection <KindName>` unterdrueckt werden koennen.
//
// Hintergrund: TSuppression.KindFromName loest den im Kommentar genannten
// Namen ueber das KIND_META-Array auf. Wenn ein neuer Detektor ohne
// passenden KIND_META-Eintrag (oder mit Tippfehler) hinzukommt, fliegt
// die Suppression still durch und der Suppress-Marker wirkt nicht. Dieser
// Test deckt alle 161 Kinds in einem Rutsch ab und faengt Drift sofort.
//
// Drei Tests:
//   1. EveryKindNameResolvesViaKindFromName
//      KindFromName(KIND_META[K].Name) muss exakt K liefern.
//   2. EveryKindNameIsUnique
//      Keine zwei Kinds duerfen denselben KIND_META.Name haben (sonst
//      kollidiert die Suppression-Reverse-Aufloesung).
//   3. EveryKindCanBeSuppressedEndToEnd
//      Eine einzige Tmp-Datei mit allen 161 Suppress-Markern + je einer
//      Code-Zeile. Synthetische Findings (eines pro Kind) auf die
//      richtigen Code-Zeilen. ApplyToFindings muss alle 161 entfernen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSuppressionCompleteness = class
  public
    [Test] procedure EveryKindNameResolvesViaKindFromName;
    [Test] procedure EveryKindNameIsUnique;
    [Test] procedure EveryKindCanBeSuppressedEndToEnd;

    // ---- fkUnusedSuppression-EMISSION (Audit P4: war komplett ungetestet;
    //      Semantik empirisch validiert 2026-07-04 via CLI-Scan) ----------
    // Staler Marker wird gemeldet, wenn die Datei daneben einen
    // konsumierten Marker hat; Fundzeile = Marker-Zeile.
    [Test] procedure UnusedMarker_WithConsumedSiblingInFile_Reported;
    // Nur konsumierte Marker -> kein UnusedSuppression-Rauschen.
    [Test] procedure ConsumedMarkerOnly_NoUnusedFinding;
    // BEKANNTE LUECKE (Audit_CodeReview "UnusedSuppression", zurueckgestellt):
    // in Dateien OHNE konsumierten Marker wird FileMarkers nie gebaut ->
    // stale Marker dort werden NICHT gemeldet. Dieser Test schreibt den
    // Ist-Zustand fest - der kuenftige Fix MUSS ihn bewusst anfassen.
    [Test] procedure StaleMarkerOnly_KnownGap_NotReported;

    // ---- Audit #10b (2026-07-05): Lesefehler ist kein stilles fail-open --
    // Marker-Host existiert, ist aber nicht lesbar (exklusiver Lock):
    // Original-Finding bleibt UNGEFILTERT stehen UND es gibt genau ein
    // fkFileReadError-Diagnose-Finding mit MSG_SUPPRESSION_READ_ERROR.
    [Test] procedure UnreadableMarkerHost_EmitsDiagnosticFinding;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uSuppression,
  uTestFindingHelper;

procedure TTestSuppressionCompleteness.EveryKindNameResolvesViaKindFromName;
var
  K, Resolved : TFindingKind;
  Name        : string;
  Missing     : TStringList;
begin
  Missing := TStringList.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Name := KIND_META[K].Name;
      // Leerer Name = bewusste Lookup-Sperre - aktuell nirgends, aber
      // der Vollstaendigkeit halber tolerant.
      if Name = '' then
      begin
        Missing.Add(Format('Kind ord=%d hat leeren KIND_META.Name', [Ord(K)]));
        Continue;
      end;
      if not KindFromName(Name, Resolved) then
        Missing.Add(Format('KindFromName(%s) liefert false - Reverse-Lookup '
          + 'broken', [Name]))
      else if Resolved <> K then
        Missing.Add(Format(
          'KindFromName(%s) liefert ord=%d statt erwarteter ord=%d (%s)',
          [Name, Ord(Resolved), Ord(K), KIND_META[K].Name]));
    end;
    Assert.AreEqual<Integer>(0, Missing.Count,
      'Fehlende oder falsche KIND_META->Kind Lookups:'#13#10 + Missing.Text);
  finally
    Missing.Free;
  end;
end;

procedure TTestSuppressionCompleteness.EveryKindNameIsUnique;
var
  K, Other    : TFindingKind;
  Duplicates  : TStringList;
begin
  Duplicates := TStringList.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      if KIND_META[K].Name = '' then Continue;
      // Guard gegen Succ(High) - waere Range-Check-Error mit {$R+}.
      if K = High(TFindingKind) then Continue;
      for Other := Succ(K) to High(TFindingKind) do
      begin
        if KIND_META[Other].Name = '' then Continue;
        if SameText(KIND_META[K].Name, KIND_META[Other].Name) then
          Duplicates.Add(Format(
            'KIND_META.Name "%s" ist doppelt: ord=%d UND ord=%d',
            [KIND_META[K].Name, Ord(K), Ord(Other)]));
      end;
    end;
    Assert.AreEqual<Integer>(0, Duplicates.Count,
      'Doppelte KIND_META-Namen (Suppression waere mehrdeutig):'#13#10 +
      Duplicates.Text);
  finally
    Duplicates.Free;
  end;
end;

procedure TTestSuppressionCompleteness.EveryKindCanBeSuppressedEndToEnd;
// Eine einzige Tmp-Datei mit Doppel-Zeilen-Layout:
//   Zeile (2i+1): // noinspection <KIND_META[K_i].Name>
//   Zeile (2i+2): pseudo := True; // i-te Code-Zeile, wo das Finding sitzt
//
// Synthetische Findings (eines pro Kind) auf Zeile (2i+2). Wenn die
// Suppression-Pipeline alle 161 Kinds kennt, muss die Liste nach
// ApplyToFindings leer sein.
var
  K          : TFindingKind;
  KindList   : TList<TFindingKind>;
  Lines      : TStringList;
  TempPath   : string;
  Findings   : TObjectList<TLeakFinding>;
  F          : TLeakFinding;
  i          : Integer;
  RemainingNames : TStringList;
begin
  // Alle Kinds mit non-leerem Namen sammeln (deterministischer Iter-Order).
  // fkFileReadError ist per Design von der Suppression ausgenommen
  // (uSuppression.ApplyToFindings, Z. 211) - Parser/IO-Fehler sollen
  // nicht silent weg-suppressed werden.
  KindList := TList<TFindingKind>.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
      if (KIND_META[K].Name <> '') and (K <> fkFileReadError) then
        KindList.Add(K);

    // Tmp-Datei bauen: Suppression-Marker + Dummy-Code im Wechsel.
    Lines := TStringList.Create;
    try
      for i := 0 to KindList.Count - 1 do
      begin
        Lines.Add('// noinspection ' + KIND_META[KindList[i]].Name);
        Lines.Add('pseudo := True;');
      end;
      TempPath := TPath.Combine(TPath.GetTempPath,
        'sca_suppress_' + TGuid.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-','')
        + '.pas');
      Lines.SaveToFile(TempPath, TEncoding.UTF8);
    finally
      Lines.Free;
    end;

    try
      // Findings synthetisieren: jeweils auf die Code-Zeile (2i+2).
      Findings := TObjectList<TLeakFinding>.Create(True);
      try
        for i := 0 to KindList.Count - 1 do
        begin
          F := TLeakFinding.Create;
          F.FileName   := TempPath;
          F.MethodName := '';
          F.LineNumber := IntToStr((i * 2) + 2);
          F.MissingVar := 'completeness-test';
          F.SetKind(KindList[i]);
          Findings.Add(F);
        end;

        // Pre-Check: alle Findings sind da.
        Assert.AreEqual(KindList.Count, Findings.Count,
          'Setup-Fehler: erwartete Findings-Zahl mismatch');

        TSuppression.ApplyToFindings(Findings);

        // Post-Check: alle muessten weggefiltert sein.
        if Findings.Count > 0 then
        begin
          RemainingNames := TStringList.Create;
          try
            for F in Findings do
              RemainingNames.Add(Format('Kind %s (ord=%d) Line=%s',
                [KIND_META[F.Kind].Name, Ord(F.Kind), F.LineNumber]));
            Assert.Fail(Format(
              '%d von %d Suppress-Markern haben nicht gewirkt:'#13#10 + '%s',
              [Findings.Count, KindList.Count, RemainingNames.Text]));
          finally
            RemainingNames.Free;
          end;
        end;
      finally
        Findings.Free;
      end;
    finally
      if TFile.Exists(TempPath) then
        TFile.Delete(TempPath);
    end;
  finally
    KindList.Free;
  end;
end;

procedure TTestSuppressionCompleteness.UnusedMarker_WithConsumedSiblingInFile_Reported;
// Konsumierter EmptyMethod-Marker + staler GotoStatement-Marker (kein goto
// im File). Erwartung: EmptyMethod unterdrueckt, genau 1 fkUnusedSuppression
// auf der stalen Marker-Zeile. (Pipeline-Weg: Suppression laeuft nur dort.)
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection EmptyMethod'#13#10 +
  'procedure Leer;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  '// noinspection GotoStatement'#13#10 +
  'procedure Voll;'#13#10 +
  'begin'#13#10 +
  '  Writeln(1);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyMethod),
      'EmptyMethod-Marker muss konsumiert sein');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedSuppression),
      'genau 1 UnusedSuppression fuer den stalen GotoStatement-Marker');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'noinspection GotoStatement'),
      TFindingHelper.FirstOf(F, fkUnusedSuppression).LineNumber,
      'Fundzeile = Marker-Zeile');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.ConsumedMarkerOnly_NoUnusedFinding;
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection EmptyMethod'#13#10 +
  'procedure Leer;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyMethod),
      'Marker muss konsumiert sein');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedSuppression),
      'konsumierter Marker darf nicht als unused gemeldet werden');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.StaleMarkerOnly_KnownGap_NotReported;
// Datei hat Findings (Writeln etc.), aber KEIN Marker konsumiert etwas ->
// FileMarkers wird nie gebaut, der stale Marker bleibt unentdeckt.
// DOKUMENTIERTE LUECKE - siehe Fixture-Deklaration.
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection GotoStatement'#13#10 +
  'procedure Voll;'#13#10 +
  'begin'#13#10 +
  '  Writeln(1);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedSuppression),
      'Ist-Zustand (bekannte Luecke): ohne konsumierten Marker keine ' +
      'UnusedSuppression-Emission - Fix muss diesen Test bewusst drehen');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.UnreadableMarkerHost_EmitsDiagnosticFinding;
// Audit #10b: BuildMap/BuildMarkers liefen bei AcquireLines=nil still
// fail-open (leere Map, keine Spur). Jetzt: Original-Finding bleibt
// stehen + genau 1 fkFileReadError-Diagnose auf der Datei.
// Der Lesefehler wird ueber einen exklusiven Datei-Lock erzwungen
// (fmShareExclusive verhindert das Open von TStringList.LoadFromFile).
var
  TmpPath  : string;
  Lock     : TFileStream;
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  DiagCnt  : Integer;
  LeakCnt  : Integer;
begin
  TmpPath := TPath.Combine(TPath.GetTempPath,
    'sca_suppr_lock_' + TGUID.NewGuid.ToString + '.pas');
  TFile.WriteAllText(TmpPath,
    '// noinspection MemoryLeak'#13#10 +
    'x := TStringList.Create;'#13#10);
  try
    Lock := TFileStream.Create(TmpPath, fmOpenRead or fmShareExclusive);
    try
      Findings := TObjectList<TLeakFinding>.Create(True);
      try
        Findings.Add(TLeakFinding.New(TmpPath, 'M', 2, 'x', fkMemoryLeak));
        TSuppression.ApplyToFindings(Findings);

        DiagCnt := 0; LeakCnt := 0;
        for F in Findings do
        begin
          if F.Kind = fkFileReadError then
          begin
            Inc(DiagCnt);
            Assert.AreEqual(TmpPath, F.FileName,
              'Diagnose-Finding muss auf den Marker-Host zeigen');
            Assert.AreEqual(MSG_SUPPRESSION_READ_ERROR, F.MissingVar,
              'Diagnose-Message muss die Read-Error-Konstante sein');
          end;
          if F.Kind = fkMemoryLeak then Inc(LeakCnt);
        end;
        Assert.AreEqual<Integer>(1, DiagCnt,
          'genau 1 fkFileReadError-Diagnose fuer den unlesbaren Host');
        Assert.AreEqual<Integer>(1, LeakCnt,
          'Original-Finding bleibt ungefiltert stehen (fail-open, aber sichtbar)');
      finally
        Findings.Free;
      end;
    finally
      Lock.Free;
    end;
  finally
    TFile.Delete(TmpPath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSuppressionCompleteness);

end.
