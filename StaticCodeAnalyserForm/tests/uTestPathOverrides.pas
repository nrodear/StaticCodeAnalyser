unit uTestPathOverrides;

// Audit 2026-07 Stufe 3: TPathOverrides.ApplyToFindings ist fester
// Pipeline-Schritt (nach Suppression, vor ConfidenceFilter), hatte aber
// NULL Testabdeckung - ein Glob-/Action-Regressions-Bug haette still die
// Produktions-Ausgabe veraendert. Isolations-Tests via AddRule/Clear.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uPathOverrides;

type
  [TestFixture]
  TTestPathOverrides = class
  private
    function MakeFinding(const AFile: string; AKind: TFindingKind;
      ASev: TLeakSeverity): TLeakFinding;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DropAll_RemovesOnlyMatchingPath;
    [Test] procedure DropKind_LeavesOtherKindsOnSamePath;
    [Test] procedure SeverityHint_DowngradesMatchingKind;
    [Test] procedure NoMatch_ListUnchanged;
    [Test] procedure Idempotent_SecondApplyChangesNothing;
    // ---- 2026-11-03: Beispiele der analyser.ini-Vorlage ----
    [Test] procedure TemplateExamples_HitAbsolutePaths;
  end;

implementation

uses
  System.Classes, System.IOUtils,
  uRepoSettings;   // TRepoSettings.DefaultTemplate - die Vorlage selbst

function TTestPathOverrides.MakeFinding(const AFile: string;
  AKind: TFindingKind; ASev: TLeakSeverity): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName   := AFile;
  Result.MethodName := '';
  Result.LineNumber := '1';
  Result.MissingVar := 'x';
  Result.SetKind(AKind);
  Result.Severity   := ASev;
end;

procedure TTestPathOverrides.Setup;
begin
  TPathOverrides.Clear;
end;

procedure TTestPathOverrides.TearDown;
// Regeln nie in andere Fixtures leaken (globaler Rule-State).
begin
  TPathOverrides.Clear;
end;

procedure TTestPathOverrides.DropAll_RemovesOnlyMatchingPath;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('tests/*.pas', poaDrop, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('tests\foo.pas', fkMagicNumber, lsHint));
    L.Add(MakeFinding('src\foo.pas',   fkMagicNumber, lsHint));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'nur der tests\-Fund faellt');
    Assert.AreEqual('src\foo.pas', L[0].FileName);
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.DropKind_LeavesOtherKindsOnSamePath;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('gen/*.pas', poaDrop, [fkMagicNumber], False);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('gen\a.pas', fkMagicNumber,   lsHint));
    L.Add(MakeFinding('gen\a.pas', fkTooLongLine,   lsHint));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'nur der gelistete Kind faellt');
    Assert.IsTrue(L[0].Kind = fkTooLongLine, 'anderer Kind bleibt');
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.SeverityHint_DowngradesMatchingKind;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('legacy/*.pas', poaSeverityHint, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('legacy\old.pas', fkMagicNumber, lsError));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'Downgrade droppt nicht');
    Assert.IsTrue(L[0].Severity = lsHint, 'Severity auf Hint gedrueckt');
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.NoMatch_ListUnchanged;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('tests/*.pas', poaDrop, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('src\main.pas', fkMagicNumber, lsWarning));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count);
    Assert.IsTrue(L[0].Severity = lsWarning, 'unveraendert ohne Match');
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.Idempotent_SecondApplyChangesNothing;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('tests/*.pas', poaDrop, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('tests\t.pas', fkMagicNumber, lsHint));
    L.Add(MakeFinding('src\s.pas',   fkMagicNumber, lsHint));
    TPathOverrides.ApplyToFindings(L);
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'zweiter Apply ist No-op');
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.TemplateExamples_HitAbsolutePaths;
// Die auskommentierten [PathOverrides]-Beispiele der Vorlage muessen
// funktionieren, wenn der Nutzer das ';' wegnimmt. Der Glob laeuft gegen
// F.FileName, und das ist im echten Lauf ein ABSOLUTER Pfad; MatchesMask
// verankert am Anfang. Bis 2026-11 stand dort 'tests\**.pas' - das trifft
// 'C:\repo\tests\uFoo.pas' nie (die Tests oben nehmen relative Namen und
// sahen das deshalb nicht). Die Beispiele kommen aus der Vorlage selbst,
// nicht aus einer Abschrift - sonst bliebe ein Rueckfall dort unbemerkt.
const
  // Ein absoluter Pfad je Beispielzweck; jedes Muster muss mindestens
  // einen davon treffen.
  ABS_PATHS: array[0..3] of string = (
    'C:\repo\tests\uFoo.pas',
    'C:\repo\src\test_Bar.pas',
    'C:\repo\demos\legacy\uOld.pas',
    'C:\repo\src\generated\uGen.pas');
var
  Tpl, Examples      : TStringList;
  i, EqPos           : Integer;
  Line, Glob, IniPath: string;
  AbsPath            : string;
  InSection          : Boolean;
  L                  : TObjectList<TLeakFinding>;
begin
  Tpl := TStringList.Create;
  Examples := TStringList.Create;
  try
    Tpl.Text := TRepoSettings.DefaultTemplate;
    InSection := False;
    for i := 0 to Tpl.Count - 1 do
    begin
      Line := Trim(Tpl[i]);
      if SameText(Line, '[PathOverrides]') then
      begin
        InSection := True;
        Continue;
      end;
      if not InSection then Continue;
      // Die Beispiele stehen als Block direkt unter der Kopfzeile.
      if (Line = '') or Line.StartsWith('[') then Break;
      if Line.StartsWith(';') and (Pos('=', Line) > 0) then
        Examples.Add(Trim(Copy(Line, 2, MaxInt)));
    end;
    Assert.IsTrue(Examples.Count > 0, 'Vorlage ohne [PathOverrides]-Beispiele');

    // 1. Jede Aktion ist gueltig: Load uebernimmt jede Zeile. Eine
    //    ungueltige ueberspringt Load still, dann fehlt sie hier.
    IniPath := TPath.Combine(TPath.GetTempPath,
      'sca_pathoverrides_' + TGUID.NewGuid.ToString + '.ini');
    try
      TFile.WriteAllText(IniPath, '[PathOverrides]'#13#10 + Examples.Text,
        TEncoding.UTF8);
      TPathOverrides.Load(IniPath);
      Assert.AreEqual<Integer>(Examples.Count, TPathOverrides.RuleCount,
        'jede Vorlagen-Aktion ist gueltig');
    finally
      if TFile.Exists(IniPath) then TFile.Delete(IniPath);
    end;

    // 2. Jedes Muster trifft einen absoluten Pfad.
    for i := 0 to Examples.Count - 1 do
    begin
      EqPos := Pos('=', Examples[i]);
      Glob  := Trim(Copy(Examples[i], 1, EqPos - 1));
      TPathOverrides.Clear;
      TPathOverrides.AddRule(Glob, poaDrop, [], True);
      L := TObjectList<TLeakFinding>.Create(True);
      try
        for AbsPath in ABS_PATHS do
          L.Add(MakeFinding(AbsPath, fkMagicNumber, lsHint));
        TPathOverrides.ApplyToFindings(L);
        Assert.IsTrue(L.Count < Length(ABS_PATHS), Format(
          'Vorlagen-Muster "%s" trifft keinen absoluten Pfad', [Glob]));
      finally
        L.Free;
      end;
    end;
  finally
    Examples.Free;
    Tpl.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPathOverrides);

end.
