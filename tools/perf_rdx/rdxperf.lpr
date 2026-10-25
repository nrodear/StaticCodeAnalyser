program rdxperf;

// reDelphix-Zeitmessung ohne Delphi-Bau (FPC 3.2.2, i386-win32).
// Faehrt je Fundstelle (sites.tsv: Datei<TAB>Zeile<TAB>Regel<TAB>Meldung)
// die TEXT-Anteile von TRdxProvider.Provide nach, die JEDER Fund bezahlt,
// und den Planer der Regel, wenn er die Form TRdxMapPlanner hat:
//   lines  : Lines.Text := Text  (Provide tut das je Aufruf)
//   supp   : TRdxSuppress.LineMarker + FileMarker (je Fund, baut je Map)
//   plan   : TRdxCodeMap.Create + Planer (wie uRdxFixRunner.MapFix)
//   ctx    : TRdxContextRunner.Run am Fund (Rechtsklick im Editor, Spalte 1)
// NICHT enthalten (AST/ToolsAPI, nur mit Delphi-Harness): TSourcePlaces.Open,
// Describe/Baum-Rezepte, Planer mit Places-Form (unmapped_rows.txt),
// Puffer lesen ueber ToolsAPI.
// Zaehler (gepatchte Kopien): Map-Aufbauten, Map-Zeilen, FileExists der
// Include-Suche, Verzeichnis-Scans (FindFirst), LoadFileSmart.
//
//   rdxperf <sites.tsv> <out.csv> [topN]
//
// Nicht von Hand bauen: tools/perf_rdx/run_rdxperf.sh erzeugt planners.inc
// und planner_uses.inc (gen_harness.py), kopiert diese Datei in das
// Arbeitsverzeichnis RDXPERF_WORK und uebersetzt sie dort. Endung .lpr,
// damit der Delphi-Selbstscan (dlDelphi: nur .pas) das FPC-Programm ohne
// seine generierten Includes nicht mitliest.

{$mode delphiunicode}{$H+}

uses
  Windows, SysUtils, Classes, Math, Generics.Collections, Generics.Defaults,
  uFileTextCache, uFindingActions, uRdxText, uRdxBufferMath, uRdxCodeMap,
  uRdxSuppress, uRdxContextRunner,
{$I planner_uses.inc}
  uRdxPaths;

type
  TRdxMapPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;

{$I planners.inc}

type
  TAgg = record
    N                       : Integer;
    Lines, Supp, Plan, Ctx  : Double;   // ms
    MaxTotal                : Double;
    Maps, Fex, Dirs, Loads  : Int64;
    Enabled                 : Integer;
  end;
  TSite = record
    Total  : Double;
    Row    : string;
  end;

var
  Freq : Int64;

function AggSum(const A: TAgg): Double;
begin
  Result := A.Lines + A.Supp + A.Plan + A.Ctx;
end;

function NowTicks: Int64;
begin
  QueryPerformanceCounter(Result);
end;

function Ms(A, B: Int64): Double;
begin
  Result := (B - A) * 1000.0 / Freq;
end;

function Csv(const S: string): string;
begin
  Result := StringReplace(StringReplace(S, ';', ',', [rfReplaceAll]),
    #13#10, ' ', [rfReplaceAll]);
end;

var
  Sites, Cols, Lines, Work, OutCsv : TStringList;
  Planners : TDictionary<string, TList<Integer>>;
  Names    : TArray<string>;
  Fns      : TArray<TRdxMapPlanner>;
  Rules    : TArray<string>;
  Agg      : TDictionary<string, TAgg>;
  FileMap  : TDictionary<string, Double>;
  All      : TList<TSite>;
  i, k, LineNo, Idx, TopN : Integer;
  Path, Rule, Msg, CurFile, Text, KName, Why : string;
  A        : TAgg;
  T0, T1, T2, T3, T4 : Int64;
  M0, F0, D0, L0 : Int64;
  E        : TRdxEdit;
  Map      : TRdxCodeMap;
  Ok, AnyOk : Boolean;
  Outs     : TArray<TRdxContextOutcome>;
  LoadMs, MapMs, Total, PlanMs : Double;
  Site     : TSite;
  Keys     : TArray<string>;
  GrandLines, GrandSupp, GrandPlan, GrandCtx : Double;
  FilesSeen : Integer;
  S        : string;
begin
  if ParamCount < 2 then
  begin
    Writeln('rdxperf <sites.tsv> <out.csv> [topN]');
    Halt(2);
  end;
  QueryPerformanceFrequency(Freq);
  SetRdxLanguageOverride('en');
  TopN := StrToIntDef(ParamStr(3), 25);
  Sites := TStringList.Create;
  Cols := TStringList.Create;
  Cols.Delimiter := #9;
  Cols.StrictDelimiter := True;
  Lines := TStringList.Create;
  OutCsv := TStringList.Create;
  Planners := TDictionary<string, TList<Integer>>.Create;
  Agg := TDictionary<string, TAgg>.Create;
  FileMap := TDictionary<string, Double>.Create;
  All := TList<TSite>.Create;
  SetLength(Names, PlannerCount);
  SetLength(Fns, PlannerCount);
  SetLength(Rules, PlannerCount);
  for i := 0 to PlannerCount - 1 do
  begin
    PlannerAt(i, Rules[i], Names[i], Fns[i]);
    if not Planners.ContainsKey(Rules[i]) then
      Planners.Add(Rules[i], TList<Integer>.Create);
    Planners[Rules[i]].Add(i);
  end;
  Sites.LoadFromFile(ParamStr(1), TEncoding.UTF8);
  OutCsv.Add('file;line;rule;lines_ms;supp_ms;plan_ms;ctx_ms;total_ms;'
    + 'maps;map_lines_hint;fileexists;dirscans;loads;enabled;planners');
  CurFile := '#';
  Text := '';
  FilesSeen := 0;
  GrandLines := 0; GrandSupp := 0; GrandPlan := 0; GrandCtx := 0;
  for i := 0 to Sites.Count - 1 do
  begin
    Cols.DelimitedText := Sites[i];
    if Cols.Count < 3 then Continue;
    Path := Cols[0];
    LineNo := StrToIntDef(Cols[1], 0);
    Rule := Cols[2];
    if Cols.Count > 3 then Msg := Cols[3] else Msg := '';
    if Path <> CurFile then
    begin
      CurFile := Path;
      Lines.Clear;
      T0 := NowTicks;
      if not LoadFileSmart(Path, Lines) then Lines.Clear;
      T1 := NowTicks;
      Text := Lines.Text;
      LoadMs := Ms(T0, T1);
      // Kosten EINES Map-Aufbaus fuer diese Datei (Referenz je Datei)
      T0 := NowTicks;
      Map := TRdxCodeMap.Create(Lines);
      Map.Free;
      T1 := NowTicks;
      MapMs := Ms(T0, T1);
      FileMap.AddOrSetValue(Path, MapMs);
      Inc(FilesSeen);
    end;
    if (LineNo < 1) or (LineNo > Lines.Count) then Continue;
    KName := RuleKindName(Rule);
    M0 := GRdxMapBuilds; F0 := GRdxFileExists; D0 := GRdxDirScans;
    L0 := GRdxFileLoads;
    Work := TStringList.Create;
    try
      T0 := NowTicks;
      Work.Text := Text;                       // Provide: Lines.Text := Text
      T1 := NowTicks;
      try
        TRdxSuppress.LineMarker(Work, LineNo, KName, E, Why);
        TRdxSuppress.FileMarker(Work, KName, E, Why);
      except
        on Ex: Exception do ;
      end;
      T2 := NowTicks;
      AnyOk := False;
      S := '';
      if Planners.ContainsKey(Rule) then
        for Idx in Planners[Rule] do
        begin
          try
            Map := TRdxCodeMap.Create(Work);
            try
              Ok := Fns[Idx](Map, LineNo, Msg, E, Why);
            finally
              Map.Free;
            end;
          except
            on Ex: Exception do
            begin
              Ok := False;
              Why := 'EXC ' + Ex.ClassName + ': ' + Ex.Message;
            end;
          end;
          AnyOk := AnyOk or Ok;
          S := S + Names[Idx] + ' ';
        end;
      T3 := NowTicks;
      try
        Outs := TRdxContextRunner.Run(Work,
          TEditorContext.At(Path, LineNo, 1));
      except
        on Ex: Exception do ;
      end;
      T4 := NowTicks;
    finally
      Work.Free;
    end;
    if not Agg.TryGetValue(Rule, A) then
      A := Default(TAgg);
    Inc(A.N);
    A.Lines := A.Lines + Ms(T0, T1);
    A.Supp := A.Supp + Ms(T1, T2);
    PlanMs := Ms(T2, T3);
    A.Plan := A.Plan + PlanMs;
    A.Ctx := A.Ctx + Ms(T3, T4);
    Total := Ms(T0, T4);
    if Total > A.MaxTotal then A.MaxTotal := Total;
    A.Maps := A.Maps + (GRdxMapBuilds - M0);
    A.Fex := A.Fex + (GRdxFileExists - F0);
    A.Dirs := A.Dirs + (GRdxDirScans - D0);
    A.Loads := A.Loads + (GRdxFileLoads - L0);
    if AnyOk then Inc(A.Enabled);
    Agg.AddOrSetValue(Rule, A);
    GrandLines := GrandLines + Ms(T0, T1);
    GrandSupp := GrandSupp + Ms(T1, T2);
    GrandPlan := GrandPlan + PlanMs;
    GrandCtx := GrandCtx + Ms(T3, T4);
    Site.Total := Total;
    Site.Row := Format('%s;%d;%s;%.3f;%.3f;%.3f;%.3f;%.3f;%d;%d;%d;%d;%d;%d;%s',
      [Csv(Path), LineNo, Rule, Ms(T0, T1), Ms(T1, T2), PlanMs, Ms(T3, T4),
       Total, GRdxMapBuilds - M0, Lines.Count, GRdxFileExists - F0,
       GRdxDirScans - D0, GRdxFileLoads - L0, Ord(AnyOk), Trim(S)]);
    OutCsv.Add(Site.Row);
    All.Add(Site);
  end;
  OutCsv.SaveToFile(ParamStr(2), TEncoding.UTF8);

  Writeln(Format('Fundstellen %d, Dateien %d, Planer (MapFix-Form) %d',
    [All.Count, FilesSeen, PlannerCount]));
  Writeln(Format('Summe ms: lines %.0f  supp %.0f  plan %.0f  ctx %.0f',
    [GrandLines, GrandSupp, GrandPlan, GrandCtx]));
  Writeln(Format('Map-Aufbauten gesamt %d (%.1f je Fund), Map-Zeilen %d, '
    + 'FileExists %d, Verzeichnis-Scans %d, LoadFileSmart %d',
    [GRdxMapBuilds, GRdxMapBuilds / Max(All.Count, 1), GRdxMapLines,
     GRdxFileExists, GRdxDirScans, GRdxFileLoads]));
  Writeln;
  Writeln('Je Regel (ms gesamt / ms je Fund), absteigend nach Summe:');
  Writeln(Format('%-8s %6s %9s %9s %9s %9s %8s %8s %6s %6s %6s %5s',
    ['Regel', 'N', 'lines', 'supp', 'plan', 'ctx', 'je Fund', 'max',
     'maps/F', 'fex', 'dirs', 'ok']));
  Keys := Agg.Keys.ToArray;
  // FPC 3.2.2: keine anonymen Methoden - Auswahlsortierung
  for k := 0 to High(Keys) - 1 do
    for Idx := k + 1 to High(Keys) do
      if AggSum(Agg[Keys[Idx]]) > AggSum(Agg[Keys[k]]) then
      begin
        S := Keys[k]; Keys[k] := Keys[Idx]; Keys[Idx] := S;
      end;
  for k := 0 to High(Keys) do
  begin
    A := Agg[Keys[k]];
    Writeln(Format('%-8s %6d %9.1f %9.1f %9.1f %9.1f %8.3f %8.2f %6.1f %6d %6d %5d',
      [Keys[k], A.N, A.Lines, A.Supp, A.Plan, A.Ctx,
       (A.Lines + A.Supp + A.Plan + A.Ctx) / A.N, A.MaxTotal,
       A.Maps / A.N, A.Fex, A.Dirs, A.Enabled]));
  end;
  Writeln;
  Writeln(Format('Top %d langsamste Fundstellen (total ms):', [TopN]));
  for k := 0 to Min(TopN, All.Count) - 1 do
  begin
    LineNo := k;
    for Idx := k + 1 to All.Count - 1 do
      if All[Idx].Total > All[LineNo].Total then LineNo := Idx;
    Site := All[LineNo]; All[LineNo] := All[k]; All[k] := Site;
    Writeln('  ', All[k].Row);
  end;
end.