unit uTestDateFormatSettings;

// Tests fuer den TDateFormatSettingsDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDateFormatSettings = class
  public
    [Test] procedure StrToDateNoSettings_Reported;
    [Test] procedure DateToStrNoSettings_Reported;
    [Test] procedure StrToFloatNoSettings_Reported;
    [Test] procedure FormatFloatNoSettings_Reported;

    [Test] procedure StrToDateWithSettings_NoFinding;
    [Test] procedure StrToIntNoSettings_NoFinding;
    [Test] procedure UnrelatedCall_NoFinding;

    // FP-Regression (FmtSettings-Abkuerzung 2026-06-29): ein explizit
    // uebergebenes TFormatSettings-Argument namens 'FmtSettings'/'LFmtSettings'
    // zaehlt jetzt - wie 'FormatSettings' - als "Settings vorhanden".
    [Test] procedure StrToFloatWithFmtSettings_NoFinding;
    // Gegenprobe: ohne jegliches Settings-Argument bleibt es ein Treffer.
    [Test] procedure StrToFloatNoSettings_StillReported;

    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestDateFormatSettings.StrToDateNoSettings_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin LogIt(StrToDate(s)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDateFormatSettings));
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.DateToStrNoSettings_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(d: TDateTime);'#13#10 +
  'begin LogIt(DateToStr(d)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDateFormatSettings));
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.StrToFloatNoSettings_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin LogIt(StrToFloat(s)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDateFormatSettings));
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.FormatFloatNoSettings_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Double);'#13#10 +
  'begin LogIt(FormatFloat(''0.00'', x)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDateFormatSettings));
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.StrToDateWithSettings_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string; const FormatSettings: TFormatSettings);'#13#10 +
  'begin LogIt(StrToDate(s, FormatSettings)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDateFormatSettings));
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.StrToIntNoSettings_NoFinding;
// StrToInt ist locale-unabhaengig - Integer-Parsing nutzt nur '0'-'9' und '-'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin LogIt(StrToInt(s)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDateFormatSettings));
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.UnrelatedCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoSomething(42); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDateFormatSettings));
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin LogIt(StrToDate(s)); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDateFormatSettings then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkDateFormatSettings finding expected');
    Assert.AreEqual(fkDateFormatSettings, Hit.Kind);
    Assert.AreEqual(lsWarning,            Hit.Severity);
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.StrToFloatWithFmtSettings_NoFinding;
// FmtSettings-Abkuerzung (2026-06-29): 'FmtSettings' ist die gaengige Kurzform
// fuer ein explizit uebergebenes TFormatSettings. MentionsFormatSettings matched
// jetzt zusaetzlich das Teilwort 'fmtsettings' -> kein Locale-Bug, kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string; const FmtSettings: TFormatSettings);'#13#10 +
  'begin i := StrToFloat(s, FmtSettings); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDateFormatSettings),
        'StrToFloat mit FmtSettings-Argument darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestDateFormatSettings.StrToFloatNoSettings_StillReported;
// Gegenprobe: ohne Settings-Argument ist StrToFloat locale-abhaengig -> Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin i := StrToFloat(s); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDateFormatSettings) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDateFormatSettings);

end.
