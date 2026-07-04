unit uTestCommandInjection;

// Tests fuer TCommandInjectionDetector (SCA163).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommandInjection = class
  public
    // ---- Positive: Konkatenation in Shell-API ----------------------------
    [Test] procedure CmdInj_ShellExecuteConcat_Reported;
    [Test] procedure CmdInj_CreateProcessConcat_Reported;
    [Test] procedure CmdInj_WinExecConcat_Reported;
    [Test] procedure CmdInj_QualifiedShellExecute_Reported;

    // ---- Negative: pure Literale ohne '+' --------------------------------
    [Test] procedure CmdInj_ShellExecutePureLiteral_NoFinding;
    [Test] procedure CmdInj_CreateProcessNoConcat_NoFinding;

    // ---- Negative: Plus innerhalb Stringliteral schuetzt ----------------
    [Test] procedure CmdInj_PlusInsideStringLiteral_NoFinding;

    // ---- Negative: andere API -------------------------------------------
    [Test] procedure CmdInj_HarmlessCallWithConcat_NoFinding;

    // ---- Finding-Inhalt --------------------------------------------------
    [Test] procedure CmdInj_Finding_KindSeverityConfidence;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCommandInjection.CmdInj_ShellExecuteConcat_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var url: string;'#13#10 +
  'begin'#13#10 +
  '  ShellExecute(0, ''open'', PChar(''cmd /c '' + url), nil, nil, SW_SHOW);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCommandInjection),
      'genau 1 CommandInjection-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'ShellExecute(0'),
      TFindingHelper.FirstOf(F, fkCommandInjection).LineNumber,
      'Fund muss auf der Aufruf-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_CreateProcessConcat_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var cmd, arg: string;'#13#10 +
  'begin'#13#10 +
  '  CreateProcess(nil, PChar(cmd + '' '' + arg), nil, nil, False, 0, nil, nil, si, pi);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCommandInjection),
      'genau 1 CommandInjection-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'CreateProcess(nil'),
      TFindingHelper.FirstOf(F, fkCommandInjection).LineNumber,
      'Fund muss auf der Aufruf-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_WinExecConcat_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var arg: string;'#13#10 +
  'begin WinExec(PAnsiChar(AnsiString(''notepad '' + arg)), SW_SHOW); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCommandInjection),
      'genau 1 CommandInjection-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'WinExec('),
      TFindingHelper.FirstOf(F, fkCommandInjection).LineNumber,
      'Fund muss auf der Aufruf-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_QualifiedShellExecute_Reported;
// 'Winapi.ShellAPI.ShellExecute' - qualifizierter Aufruf, letztes Pfad-
// Segment ist 'shellexecute' -> Match.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var url: string;'#13#10 +
  'begin'#13#10 +
  '  Winapi.ShellAPI.ShellExecute(0, ''open'', PChar(url + ''.exe''), nil, nil, SW_SHOW);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCommandInjection),
      'genau 1 CommandInjection-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'Winapi.ShellAPI.ShellExecute'),
      TFindingHelper.FirstOf(F, fkCommandInjection).LineNumber,
      'Fund muss auf der Aufruf-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_ShellExecutePureLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  ShellExecute(0, ''open'', ''C:\Tools\notepad.exe'', nil, nil, SW_SHOW);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommandInjection));
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_CreateProcessNoConcat_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  CreateProcess(nil, ''C:\Tools\app.exe'', nil, nil, False, 0, nil, nil, si, pi);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommandInjection));
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_PlusInsideStringLiteral_NoFinding;
// Das '+' steht INNERHALB des Literals - kein Concat-Operator.
// Erwartung: kein Finding, denn der Heuristik-Walker erkennt das Apostroph-State.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  ShellExecute(0, ''open'', ''calc + plus.exe'', nil, nil, SW_SHOW);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommandInjection));
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_HarmlessCallWithConcat_NoFinding;
// Konkatenation in einem Call der NICHT auf die Shell-API-Liste matched.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b: string;'#13#10 +
  'begin WriteLn(a + b); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommandInjection));
  finally F.Free; end;
end;

procedure TTestCommandInjection.CmdInj_Finding_KindSeverityConfidence;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var url: string;'#13#10 +
  'begin'#13#10 +
  '  ShellExecute(0, ''open'', PChar(''cmd /c '' + url), nil, nil, SW_SHOW);'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkCommandInjection then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.AreEqual(fkCommandInjection, Hit.Kind);
    Assert.AreEqual(lsError, Hit.Severity);
    Assert.AreEqual(fcLow, Hit.Confidence,
      'CommandInjection ist heuristisch ohne Taint-Tracking -> Confidence=fcLow');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandInjection);

end.
