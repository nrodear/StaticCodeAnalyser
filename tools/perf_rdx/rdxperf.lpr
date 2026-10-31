program rdxperf;

// reDelphix-Zeitmessung ohne Delphi-Bau (FPC 3.2.2, i386-win32).
// Faehrt je Fundstelle (sites.tsv: Datei<TAB>Zeile<TAB>Regel<TAB>Meldung)
// die TEXT-Anteile von TRdxProvider.Provide nach, die JEDER Fund bezahlt,
// und den Planer der Regel, wenn er die Form TRdxMapPlanner hat:
//   lines  : Lines.Text := Text  (Provide; Modus file nur je Datei)
//   supp   : TRdxSuppress.LineMarker + FileMarker (davon FileMarker extra)
//   plan   : Map + Planer (wie uRdxFixRunner.MapFix)
//   ctx    : TRdxContextRunner.Run am Fund (Rechtsklick im Editor, Spalte 1)
//   disk   : nur SCA014/SCA069/SCA111/SCA112 - FileReason + IncludeReason
//            (was MagicCheck/LookupCheck/PlanDigitGrouping nach einem
//            Angebot fragen; Obergrenze: der Planer koennte vorher ablehnen)
// NICHT enthalten (AST/ToolsAPI, nur mit Delphi-Harness): TSourcePlaces.Open,
// Describe/Baum-Rezepte, Planer mit Places-Form (unmapped_rows.txt),
// Puffer lesen ueber ToolsAPI.
// Zaehler (gepatchte Kopien): Map-Aufbauten, Map-Zeilen, FileExists der
// Include-Suche, Verzeichnis-Scans (FindFirst), LoadFileSmart.
//
// MODUS (Umgebung RDX_MODE, Standard file). Mit -dRDX_SHARED - der Stand
// kennt TRdxMappedLines und TRdxDiskReasonCache (Charge P5), das Skript
// erkennt das selbst - gibt es drei Wege; ohne nur old:
//   file    : wie der Anbieter heute (TRdxProvider.SharedLines): EINE
//             TRdxMappedLines je Datei, alle Funde der Datei teilen Zeilen
//             und Map (gleicher Text -> dieselben Zeilen, wie aufeinander-
//             folgende Provide eines Menues); Plattenblick-Cache je Datei
//   provide : je Fund frische TRdxMappedLines (EINE Map je Provide), der
//             Plattenblick-Cache je Fund geleert
//   old     : der Weg vor P5 als Vergleich - frische TStringList je Fund,
//             TRdxCodeMap.Create je Planer, kein Plattenblick-Cache
// Ergebnisse je Fund (Marker, Planer, Kontext, Plattenblick) als Text nach
// <out.csv>.res - Identitaets-Vergleich der Modi (compare_res.py).
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
  uRdxSuppress, uRdxContextRunner, uRdxMagicFixes,
{$I planner_uses.inc}
  uRdxPaths;

type
  TRdxMapPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;

{$I planners.inc}

type
  TAgg = record
    N                             : Integer;
    Lines, Supp, Plan, Ctx, Disk  : Double;   // ms
    MaxTotal                      : Double;
    Maps, Fex, Dirs, Loads        : Int64;
    Enabled                       : Integer;
  end;
  TSite = record
    Total  : Double;
    Row    : string;
  end;

var
  Freq : Int64;

function AggSum(const A: TAgg): Double;
begin
  Result := A.Lines + A.Supp + A.Plan + A.Ctx + A.Disk;
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

function EditText(const AEdit: TRdxEdit): string;
begin
  Result := Format('%d:%d-%d:%d[%s]->[%s]', [AEdit.Span.StartLine,
    AEdit.Span.StartCol, AEdit.Span.EndLine, AEdit.Span.EndCol,
    AEdit.Expected, AEdit.NewText]);
end;

function OutText(AOk: Boolean; const AEdit: TRdxEdit; const AWhy: string): string;
begin
  if AOk then
    Result := 'ok ' + EditText(AEdit)
  else
    Result := 'no ' + AWhy;
end;

function CtxText(const AList: TArray<TRdxContextOutcome>): string;
var
  i, k : Integer;
begin
  Result := IntToStr(Length(AList));
  for i := 0 to High(AList) do
  begin
    Result := Result + Format('|%d %s %s %s %s', [Ord(AList[i].Kind),
      BoolToStr(AList[i].Enabled, True), AList[i].Name, AList[i].Hint,
      AList[i].Reason]);
    for k := 0 to High(AList[i].Edits) do
      Result := Result + ' ' + EditText(AList[i].Edits[k]);
  end;
end;

function Clean(const S: string): string;
begin
  Result := StringReplace(StringReplace(StringReplace(S, #13, '\r',
    [rfReplaceAll]), #10, '\n', [rfReplaceAll]), #9, '\t', [rfReplaceAll]);
end;

function DiskFeature(const ARule: string; out AFeature: TRdxLateFeature): Boolean;
begin
  Result := True;
  if ARule = 'SCA014' then AFeature := lfInlineConst
  else if ARule = 'SCA069' then AFeature := lfDigitSeparator
  else if (ARule = 'SCA111') or (ARule = 'SCA112') then AFeature := lfInlineVar
  else Result := False;
end;

var
  Sites, Cols, Lines, Work, OutCsv, Res : TStringList;
  Planners : TDictionary<string, TList<Integer>>;
  Names    : TArray<string>;
  Fns      : TArray<TRdxMapPlanner>;
  Rules    : TArray<string>;
  Agg      : TDictionary<string, TAgg>;
  All      : TList<TSite>;
  i, k, LineNo, Idx, TopN : Integer;
  Path, Rule, Msg, CurFile, Text, KName, Why, Mode, Line : string;
  A        : TAgg;
  T0, T1, T2, T3, T4, T5, TF0, TF1, TM0, TM1 : Int64;
  M0, F0, D0, L0 : Int64;
  E        : TRdxEdit;
  Map      : TRdxCodeMap;
  Ok, AnyOk : Boolean;
  Outs     : TArray<TRdxContextOutcome>;
  Total, PlanMs : Double;
  Site     : TSite;
  Keys     : TArray<string>;
  GrandLines, GrandSupp, GrandPlan, GrandCtx, GrandDisk : Double;
  GrandFR, GrandFMark : Double;
  FilesSeen : Integer;
  S        : string;
  Feature  : TRdxLateFeature;
{$IFDEF RDX_SHARED}
  Cache    : TRdxDiskReasonCache;
  FileWork : TRdxMappedLines;
{$ENDIF}
begin
  if ParamCount < 2 then
  begin
    Writeln('rdxperf <sites.tsv> <out.csv> [topN]   (Umgebung RDX_MODE: file|provide|old)');
    Halt(2);
  end;
  QueryPerformanceFrequency(Freq);
  SetRdxLanguageOverride('en');
  TopN := StrToIntDef(ParamStr(3), 25);
  Mode := LowerCase(GetEnvironmentVariable('RDX_MODE'));
  if Mode = '' then Mode := 'file';
  if (Mode <> 'file') and (Mode <> 'provide') and (Mode <> 'old') then
  begin
    Writeln('RDX_MODE unbekannt: ', Mode, ' (file, provide oder old)');
    Halt(2);
  end;
{$IFNDEF RDX_SHARED}
  if Mode <> 'old' then
    Writeln('Stand ohne TRdxMappedLines (vor Charge P5) - Modus ', Mode,
      ' gibt es nicht, gemessen wird old');
  Mode := 'old';
{$ELSE}
  Cache := TRdxDiskReasonCache.Create;
  FileWork := nil;
  if Mode <> 'old' then
    TRdxMagicFixes.UseDiskCache(Cache);
{$ENDIF}
  Sites := TStringList.Create;
  Cols := TStringList.Create;
  Cols.Delimiter := #9;
  Cols.StrictDelimiter := True;
  Lines := TStringList.Create;
  OutCsv := TStringList.Create;
  Res := TStringList.Create;
  Planners := TDictionary<string, TList<Integer>>.Create;
  Agg := TDictionary<string, TAgg>.Create;
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
  OutCsv.Add('file;line;rule;lines_ms;supp_ms;fmark_ms;plan_ms;ctx_ms;disk_ms;'
    + 'total_ms;maps;map_lines_hint;fileexists;dirscans;loads;enabled;planners');
  CurFile := '#';
  Text := '';
  FilesSeen := 0;
  GrandLines := 0; GrandSupp := 0; GrandPlan := 0; GrandCtx := 0; GrandDisk := 0;
  GrandFR := 0; GrandFMark := 0;
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
      if not LoadFileSmart(Path, Lines) then Lines.Clear;
      Text := Lines.Text;
      // Referenz: EIN Map-Aufbau je Datei (zaehlt in GRdxMapBuilds mit,
      // die Zusammenfassung zieht ihn wieder ab)
      Map := TRdxCodeMap.Create(Lines);
      Map.Free;
      Inc(FilesSeen);
{$IFDEF RDX_SHARED}
      // file: neue Datei = neue geteilte Zeilen, Plattenblick neu
      FreeAndNil(FileWork);
      Cache.Clear;
{$ENDIF}
    end;
    if (LineNo < 1) or (LineNo > Lines.Count) then Continue;
    KName := RuleKindName(Rule);
    M0 := GRdxMapBuilds; F0 := GRdxFileExists; D0 := GRdxDirScans;
    L0 := GRdxFileLoads;
    Line := Format('%s'#9'%d'#9'%s', [Path, LineNo, Rule]);
    T0 := NowTicks;
    // Provide: Lines.Text := Text (je Modus, s. Kopf)
{$IFDEF RDX_SHARED}
    if Mode = 'file' then
    begin
      if FileWork = nil then
      begin
        FileWork := TRdxMappedLines.Create;
        FileWork.Text := Text;
      end;
      Work := FileWork;
    end
    else if Mode = 'provide' then
    begin
      Cache.Clear;
      Work := TRdxMappedLines.Create;
      Work.Text := Text;
    end
    else
{$ENDIF}
    begin
      Work := TStringList.Create;
      Work.Text := Text;
    end;
    try
      T1 := NowTicks;
      TM0 := T1;
      TM1 := T1;
      try
        Ok := TRdxSuppress.LineMarker(Work, LineNo, KName, E, Why);
        Line := Line + #9'L ' + OutText(Ok, E, Why);
        TM0 := NowTicks;
        Ok := TRdxSuppress.FileMarker(Work, KName, E, Why);
        TM1 := NowTicks;
        Line := Line + #9'F ' + OutText(Ok, E, Why);
      except
        on Ex: Exception do Line := Line + #9'EXC ' + Ex.Message;
      end;
      T2 := NowTicks;
      AnyOk := False;
      S := '';
      if Planners.ContainsKey(Rule) then
        for Idx in Planners[Rule] do
        begin
          try
{$IFDEF RDX_SHARED}
            Map := TRdxCodeMap.Acquire(Work);
            try
              Ok := Fns[Idx](Map, LineNo, Msg, E, Why);
            finally
              TRdxCodeMap.Release(Map);
            end;
{$ELSE}
            Map := TRdxCodeMap.Create(Work);
            try
              Ok := Fns[Idx](Map, LineNo, Msg, E, Why);
            finally
              Map.Free;
            end;
{$ENDIF}
          except
            on Ex: Exception do
            begin
              Ok := False;
              Why := 'EXC ' + Ex.ClassName + ': ' + Ex.Message;
            end;
          end;
          AnyOk := AnyOk or Ok;
          S := S + Names[Idx] + ' ';
          Line := Line + #9'P ' + Names[Idx] + ' ' + OutText(Ok, E, Why);
        end;
      T3 := NowTicks;
      try
        Outs := TRdxContextRunner.Run(Work,
          TEditorContext.At(Path, LineNo, 1));
        Line := Line + #9'C ' + CtxText(Outs);
      except
        on Ex: Exception do Line := Line + #9'C EXC ' + Ex.Message;
      end;
      T4 := NowTicks;
      if DiskFeature(Rule, Feature) then
      begin
        TF0 := NowTicks;
        Line := Line + #9'D ' + TRdxMagicFixes.FileReason(Path, Feature);
        TF1 := NowTicks;
        GrandFR := GrandFR + Ms(TF0, TF1);
{$IFDEF RDX_SHARED}
        Map := TRdxCodeMap.Acquire(Work);
        try
          Line := Line + ' / ' + TRdxMagicFixes.IncludeReason(Path, Map, Feature);
        finally
          TRdxCodeMap.Release(Map);
        end;
{$ELSE}
        Map := TRdxCodeMap.Create(Work);
        try
          Line := Line + ' / ' + TRdxMagicFixes.IncludeReason(Path, Map, Feature);
        finally
          Map.Free;
        end;
{$ENDIF}
      end;
      T5 := NowTicks;
    finally
{$IFDEF RDX_SHARED}
      if Work <> FileWork then
{$ENDIF}
        Work.Free;
    end;
    Res.Add(Clean(Line));
    if not Agg.TryGetValue(Rule, A) then
      A := Default(TAgg);
    Inc(A.N);
    A.Lines := A.Lines + Ms(T0, T1);
    A.Supp := A.Supp + Ms(T1, T2);
    PlanMs := Ms(T2, T3);
    A.Plan := A.Plan + PlanMs;
    A.Ctx := A.Ctx + Ms(T3, T4);
    A.Disk := A.Disk + Ms(T4, T5);
    Total := Ms(T0, T5);
    if Total > A.MaxTotal then A.MaxTotal := Total;
    A.Maps := A.Maps + (GRdxMapBuilds - M0);
    A.Fex := A.Fex + (GRdxFileExists - F0);
    A.Dirs := A.Dirs + (GRdxDirScans - D0);
    A.Loads := A.Loads + (GRdxFileLoads - L0);
    if AnyOk then Inc(A.Enabled);
    Agg.AddOrSetValue(Rule, A);
    GrandLines := GrandLines + Ms(T0, T1);
    GrandSupp := GrandSupp + Ms(T1, T2);
    GrandFMark := GrandFMark + Ms(TM0, TM1);
    GrandPlan := GrandPlan + PlanMs;
    GrandCtx := GrandCtx + Ms(T3, T4);
    GrandDisk := GrandDisk + Ms(T4, T5);
    Site.Total := Total;
    Site.Row := Format('%s;%d;%s;%.3f;%.3f;%.3f;%.3f;%.3f;%.3f;%.3f;%d;%d;%d;%d;%d;%d;%s',
      [Csv(Path), LineNo, Rule, Ms(T0, T1), Ms(T1, T2), Ms(TM0, TM1), PlanMs,
       Ms(T3, T4), Ms(T4, T5), Total, GRdxMapBuilds - M0, Lines.Count,
       GRdxFileExists - F0, GRdxDirScans - D0, GRdxFileLoads - L0, Ord(AnyOk),
       Trim(S)]);
    OutCsv.Add(Site.Row);
    All.Add(Site);
  end;
{$IFDEF RDX_SHARED}
  FreeAndNil(FileWork);
  TRdxMagicFixes.UseDiskCache(nil);
  Cache.Free;
{$ENDIF}
  OutCsv.SaveToFile(ParamStr(2), TEncoding.UTF8);
  Res.SaveToFile(ParamStr(2) + '.res', TEncoding.UTF8);

  Writeln(Format('Modus %s; Fundstellen %d, Dateien %d, Planer (MapFix-Form) %d',
    [Mode, All.Count, FilesSeen, PlannerCount]));
  Writeln(Format('Summe ms: lines %.0f  supp %.0f  plan %.0f  ctx %.0f  disk %.0f  gesamt %.0f',
    [GrandLines, GrandSupp, GrandPlan, GrandCtx, GrandDisk,
     GrandLines + GrandSupp + GrandPlan + GrandCtx + GrandDisk]));
  Writeln(Format('davon supp FileMarker %.0f ms; disk FileReason %.0f ms, IncludeReason samt Map %.0f ms',
    [GrandFMark, GrandFR, GrandDisk - GrandFR]));
  Writeln(Format('Map-Aufbauten gesamt %d (davon %d Referenz je Datei; %.2f je Fund ohne Referenz), Map-Zeilen %d, '
    + 'FileExists %d, Verzeichnis-Scans %d, LoadFileSmart %d',
    [GRdxMapBuilds, FilesSeen, (GRdxMapBuilds - FilesSeen) / Max(All.Count, 1),
     GRdxMapLines, GRdxFileExists, GRdxDirScans, GRdxFileLoads]));
  Writeln;
  Writeln('Je Regel (ms gesamt / ms je Fund), absteigend nach Summe:');
  Writeln(Format('%-8s %6s %9s %9s %9s %9s %9s %8s %8s %6s %6s %6s %5s',
    ['Regel', 'N', 'lines', 'supp', 'plan', 'ctx', 'disk', 'je Fund', 'max',
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
    Writeln(Format('%-8s %6d %9.1f %9.1f %9.1f %9.1f %9.1f %8.3f %8.2f %6.2f %6d %6d %5d',
      [Keys[k], A.N, A.Lines, A.Supp, A.Plan, A.Ctx, A.Disk,
       AggSum(A) / A.N, A.MaxTotal,
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
