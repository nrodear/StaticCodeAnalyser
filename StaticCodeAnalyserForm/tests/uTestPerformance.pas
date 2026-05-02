unit uTestPerformance;

// Performance-Tests für Lexer, Parser und Analyse-Pipeline.
//
// Jeder Test misst eine konkrete Phase und gibt das Ergebnis
// (Laufzeit, Durchsatz) als DUnitX-Log-Nachricht aus.
// Assertions prüfen nur, dass die Phase innerhalb großzügiger
// Obergrenzen bleibt – damit CI-Builds auf langsamen Maschinen
// nicht fälschlicherweise fehlschlagen.
//
// Messphasen:
//   Phase 1 – Lexer          : Tokenisierung (Tokens/ms)
//   Phase 2 – Parser         : AST-Aufbau   (Zeilen/ms)
//   Phase 3 – Voll-Analyse   : Lexer + Parser + alle 5 Detektoren
//   Phase 4 – Wiederholungen : Parser 100× auf denselben Text
//   Phase 5 – Sehr große Datei: synthetische 3 000-Zeilen-Datei

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Diagnostics, System.TimeSpan, System.Generics.Collections,
  uAstNode, uLexer, uParser2, uMethodd12, uSCAConsts,
  uLeakDetector2, uCodeSmells2, uSQLInjection,
  uHardcodedSecret, uFormatMismatch;

type
  [TestFixture]
  TTestPerformance = class
  private
    // Erzeugt N Methoden mit je 1 lokalen Variable (korrekt freigegeben)
    class function MakeSource(MethodCount: Integer): string; static;

    // Erzeugt eine realistische Methode mit typischen Mustern
    class function MakeMethod(Index: Integer): string; static;

    // Erzeugt Quelltext mit bewusst eingebauten Befunden
    class function MakeSourceWithFindings(MethodCount: Integer): string; static;

    // Führt alle 5 Detektoren auf dem Root-Knoten aus
    class procedure RunAllDetectors(Root: TAstNode;
      Results: TObjectList<TLeakFinding>); static;
  public
    [Test] procedure Perf_Lexer_ThroughputTokensPerMs;
    [Test] procedure Perf_Parser_ThroughputLinesPerMs;
    [Test] procedure Perf_FullPipeline_50Methods;
    [Test] procedure Perf_FullPipeline_500Methods;
    [Test] procedure Perf_Parser_Repeated100Times;
    [Test] procedure Perf_Lexer_LargeStringLiterals;
    [Test] procedure Perf_FindAll_DeepTree;
  end;

implementation

{ ---- Hilfsmethoden ---- }

class function TTestPerformance.MakeMethod(Index: Integer): string;
// Erzeugt eine typische Methode mit try/finally und mehreren Statements
const
  TMPL =
    'procedure TBench.Method%d;'#13#10+
    'var list%d: TStringList; i%d: Integer;'#13#10+
    'begin'#13#10+
    '  list%d := TStringList.Create;'#13#10+
    '  try'#13#10+
    '    for i%d := 0 to 99 do'#13#10+
    '    begin'#13#10+
    '      list%d.Add(IntToStr(i%d));'#13#10+
    '      if list%d.Count > 50 then list%d.Clear;'#13#10+
    '    end;'#13#10+
    '  finally'#13#10+
    '    FreeAndNil(list%d);'#13#10+
    '  end;'#13#10+
    'end;'#13#10;
var
  n: string;
begin
  n := IntToStr(Index);
  Result := Format(TMPL, [Index, Index, Index, Index, Index,
                           Index, Index, Index, Index, Index]);
end;

class function TTestPerformance.MakeSource(MethodCount: Integer): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit BenchUnit;');
    SB.AppendLine('implementation');
    for i := 1 to MethodCount do
      SB.Append(MakeMethod(i));
    SB.AppendLine('end.');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TTestPerformance.MakeSourceWithFindings(MethodCount: Integer): string;
// Jede zweite Methode hat ein absichtliches Speicherleck
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit BenchUnit;');
    SB.AppendLine('implementation');
    for i := 1 to MethodCount do
    begin
      if Odd(i) then
        SB.Append(MakeMethod(i))       // korrekt
      else
      begin
        // Leck: kein Free
        SB.AppendLine(Format('procedure TBench.LeakMethod%d;', [i]));
        SB.AppendLine(Format('var leak%d: TStringList;', [i]));
        SB.AppendLine('begin');
        SB.AppendLine(Format('  leak%d := TStringList.Create;', [i]));
        SB.AppendLine(Format('  leak%d.Add(''x'');', [i]));
        SB.AppendLine('end;');
      end;
    end;
    SB.AppendLine('end.');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class procedure TTestPerformance.RunAllDetectors(Root: TAstNode;
  Results: TObjectList<TLeakFinding>);
begin
  TLeakDetector2.AnalyzeUnit(Root, 'bench.pas', Results);
  TEmptyExceptDetector2.AnalyzeUnit(Root, 'bench.pas', Results);
  TSQLInjectionDetector.AnalyzeUnit(Root, 'bench.pas', Results);
  THardcodedSecretDetector.AnalyzeUnit(Root, 'bench.pas', Results);
  TFormatMismatchDetector.AnalyzeUnit(Root, 'bench.pas', Results);
end;

{ ---- Tests ---- }

procedure TTestPerformance.Perf_Lexer_ThroughputTokensPerMs;
// Tokenisiert einen 500-Methoden-Quelltext und misst Tokens/ms.
const
  METHOD_COUNT = 500;
var
  Src      : string;
  Lex      : TLexer;
  SW       : TStopwatch;
  Tokens   : Int64;
  Lines    : Integer;
  T        : TToken;
  ElapsedMs: Int64;
begin
  Src   := MakeSource(METHOD_COUNT);
  Lines := 0;
  for var Ch in Src do
    if Ch = #10 then Inc(Lines);

  SW := TStopwatch.StartNew;
  Lex := TLexer.Create(Src);
  Tokens := 0;
  try
    repeat
      T := Lex.Next;
      Inc(Tokens);
    until T.Kind = tkEof;
  finally
    Lex.Free;
  end;
  SW.Stop;

  ElapsedMs := SW.ElapsedMilliseconds;
  if ElapsedMs = 0 then ElapsedMs := 1; // Division durch 0 verhindern

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format(
    'Lexer | %d Methoden | %d Zeilen | %d Tokens | %d ms | %d Tokens/ms',
    [METHOD_COUNT, Lines, Tokens, ElapsedMs, Tokens div ElapsedMs]));

  Assert.IsTrue(ElapsedMs < 10000,
    Format('Lexer zu langsam: %d ms für %d Zeilen', [ElapsedMs, Lines]));
  Assert.IsTrue(Tokens > 0, 'Kein Token produziert');
end;

procedure TTestPerformance.Perf_Parser_ThroughputLinesPerMs;
// Parst einen 500-Methoden-Quelltext und misst Zeilen/ms.
const
  METHOD_COUNT = 500;
var
  Src      : string;
  Parser   : TParser2;
  Root     : TAstNode;
  SW       : TStopwatch;
  Lines    : Integer;
  ElapsedMs: Int64;
begin
  Src   := MakeSource(METHOD_COUNT);
  Lines := 0;
  for var Ch in Src do
    if Ch = #10 then Inc(Lines);

  Parser := TParser2.Create;
  try
    SW   := TStopwatch.StartNew;
    Root := Parser.ParseSource(Src);
    SW.Stop;
    Root.Free;
  finally
    Parser.Free;
  end;

  ElapsedMs := SW.ElapsedMilliseconds;
  if ElapsedMs = 0 then ElapsedMs := 1;

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format(
    'Parser | %d Methoden | %d Zeilen | %d ms | %d Zeilen/ms',
    [METHOD_COUNT, Lines, ElapsedMs, Lines div ElapsedMs]));

  Assert.IsTrue(ElapsedMs < 10000,
    Format('Parser zu langsam: %d ms für %d Zeilen', [ElapsedMs, Lines]));
end;

procedure TTestPerformance.Perf_FullPipeline_50Methods;
// Komplette Analyse: Lexer + Parser + 5 Detektoren auf 50 Methoden.
// Jede zweite Methode hat ein Leck – Korrektheit der Befundanzahl wird
// zusätzlich geprüft.
const
  METHOD_COUNT = 50;
var
  Src      : string;
  Parser   : TParser2;
  Root     : TAstNode;
  Results  : TObjectList<TLeakFinding>;
  SW       : TStopwatch;
  ElapsedMs: Int64;
  Leaks    : Integer;
begin
  Src    := MakeSourceWithFindings(METHOD_COUNT);
  Parser := TParser2.Create;
  try
    SW      := TStopwatch.StartNew;
    Root    := Parser.ParseSource(Src);
    Results := TObjectList<TLeakFinding>.Create(True);
    try
      RunAllDetectors(Root, Results);
      SW.Stop;
      Leaks := 0;
      for var F in Results do
        if F.Kind = fkMemoryLeak then Inc(Leaks);
    finally
      Results.Free;
    end;
    Root.Free;
  finally
    Parser.Free;
  end;

  ElapsedMs := SW.ElapsedMilliseconds;
  if ElapsedMs = 0 then ElapsedMs := 1;

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format(
    'Pipeline-50 | %d Methoden | %d Befunde | %d ms',
    [METHOD_COUNT, Leaks, ElapsedMs]));

  Assert.IsTrue(Leaks > 0, 'Mindestens 1 Leak-Befund erwartet');
  Assert.IsTrue(ElapsedMs < 5000,
    Format('Pipeline-50 zu langsam: %d ms', [ElapsedMs]));
end;

procedure TTestPerformance.Perf_FullPipeline_500Methods;
// Skalierungstest: 500 Methoden – misst ob Laufzeit linear skaliert.
const
  METHOD_COUNT = 500;
var
  Src      : string;
  Parser   : TParser2;
  Root     : TAstNode;
  Results  : TObjectList<TLeakFinding>;
  SW       : TStopwatch;
  ElapsedMs: Int64;
  Lines    : Integer;
begin
  Src   := MakeSourceWithFindings(METHOD_COUNT);
  Lines := 0;
  for var Ch in Src do
    if Ch = #10 then Inc(Lines);

  Parser := TParser2.Create;
  try
    SW      := TStopwatch.StartNew;
    Root    := Parser.ParseSource(Src);
    Results := TObjectList<TLeakFinding>.Create(True);
    try
      RunAllDetectors(Root, Results);
      SW.Stop;
    finally
      Results.Free;
    end;
    Root.Free;
  finally
    Parser.Free;
  end;

  ElapsedMs := SW.ElapsedMilliseconds;
  if ElapsedMs = 0 then ElapsedMs := 1;

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format(
    'Pipeline-500 | %d Methoden | %d Zeilen | %d ms | %.1f Zeilen/ms',
    [METHOD_COUNT, Lines, ElapsedMs, Lines / ElapsedMs]));

  Assert.IsTrue(ElapsedMs < 30000,
    Format('Pipeline-500 zu langsam: %d ms', [ElapsedMs]));
end;

procedure TTestPerformance.Perf_Parser_Repeated100Times;
// Parser 100× auf denselben 20-Methoden-Text – misst Overhead pro Lauf.
const
  REPEATS       = 100;
  METHOD_COUNT  = 20;
var
  Src      : string;
  Parser   : TParser2;
  Root     : TAstNode;
  SW       : TStopwatch;
  ElapsedMs: Int64;
  AvgUs    : Int64;
begin
  Src    := MakeSource(METHOD_COUNT);
  Parser := TParser2.Create;
  try
    SW := TStopwatch.StartNew;
    for var R := 1 to REPEATS do
    begin
      Root := Parser.ParseSource(Src);
      Root.Free;
    end;
    SW.Stop;
  finally
    Parser.Free;
  end;

  ElapsedMs := SW.ElapsedMilliseconds;
  if ElapsedMs = 0 then ElapsedMs := 1;
  AvgUs := (SW.Elapsed.Ticks * 1000) div (REPEATS * TTimeSpan.TicksPerMillisecond);

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format(
    'Parser ×%d | %d Methoden/Lauf | gesamt %d ms | ∅ %d µs/Lauf',
    [REPEATS, METHOD_COUNT, ElapsedMs, AvgUs]));

  Assert.IsTrue(ElapsedMs < 30000,
    Format('Parser-Repeated zu langsam: %d ms', [ElapsedMs]));
end;

procedure TTestPerformance.Perf_Lexer_LargeStringLiterals;
// Prüft, ob der Lexer bei vielen langen Stringliteralen nicht hängt.
// Frühere ReadString-Version würde hier leere Tokens liefern.
var
  SB       : TStringBuilder;
  Src      : string;
  Lex      : TLexer;
  SW       : TStopwatch;
  StrToks  : Integer;
  T        : TToken;
  ElapsedMs: Int64;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; implementation');
    SB.AppendLine('procedure TFoo.Bar;');
    SB.AppendLine('begin');
    for var i := 1 to 500 do
      SB.AppendLine(Format(
        '  ShowMessage(Format(''Zeile %d: %%s = %%d'', [Name, Value]));', [i]));
    SB.AppendLine('end;');
    SB.AppendLine('end.');
    Src := SB.ToString;
  finally
    SB.Free;
  end;

  StrToks := 0;
  SW := TStopwatch.StartNew;
  Lex := TLexer.Create(Src);
  try
    repeat
      T := Lex.Next;
      if T.Kind = tkStrLit then
      begin
        Inc(StrToks);
        // Sicherstellen dass der Inhalt nicht leer ist
        Assert.IsTrue(Length(T.Value) > 0,
          Format('Leeres Stringliteral bei Token %d', [StrToks]));
      end;
    until T.Kind = tkEof;
  finally
    Lex.Free;
  end;
  SW.Stop;

  ElapsedMs := SW.ElapsedMilliseconds;
  if ElapsedMs = 0 then ElapsedMs := 1;

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format(
    'Lexer-Strings | 500 Format-Aufrufe | %d Stringtokens | %d ms',
    [StrToks, ElapsedMs]));

  Assert.IsTrue(StrToks >= 500, 'Mindestens 500 Stringtokens erwartet');
  Assert.IsTrue(ElapsedMs < 5000,
    Format('Lexer-Strings zu langsam: %d ms', [ElapsedMs]));
end;

procedure TTestPerformance.Perf_FindAll_DeepTree;
// Prüft die Geschwindigkeit von TAstNode.FindAll auf einem tiefen Baum.
// 1 000 Methoden erzeugen ~20 000+ Knoten; FindAll(nkLocalVar) muss
// schnell durch den gesamten Baum traversieren.
const
  METHOD_COUNT = 1000;
var
  Src       : string;
  Parser    : TParser2;
  Root      : TAstNode;
  SW        : TStopwatch;
  Methods   : TList<TAstNode>;
  LocalVars : TList<TAstNode>;
  TotalVars : Integer;
  ElapsedMs : Int64;
begin
  Src    := MakeSource(METHOD_COUNT);
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(Src);
    try
      SW      := TStopwatch.StartNew;
      Methods := Root.FindAll(nkMethod);
      try
        TotalVars := 0;
        for var M in Methods do
        begin
          LocalVars := M.FindAll(nkLocalVar);
          try
            Inc(TotalVars, LocalVars.Count);
          finally
            LocalVars.Free;
          end;
        end;
      finally
        Methods.Free;
      end;
      SW.Stop;
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;

  ElapsedMs := SW.ElapsedMilliseconds;
  if ElapsedMs = 0 then ElapsedMs := 1;

  TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format(
    'FindAll | %d Methoden | %d LocalVars gesamt | %d ms',
    [METHOD_COUNT, TotalVars, ElapsedMs]));

  Assert.IsTrue(TotalVars > 0, 'FindAll muss LocalVar-Knoten finden');
  Assert.IsTrue(ElapsedMs < 30000,
    Format('FindAll zu langsam: %d ms', [ElapsedMs]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPerformance);

end.
