unit uDfmGodHandler;

// Detektor: Eine einzige Methode haengt an Events vieler verschiedener
// Komponenten. Klassischer Spaghetti-Indikator nach 'OnClick = same
// MainClick auf 12 Buttons'.
//
// Schwelle: DetectorMaxGodHandlerEvents (Default 5, konfigurierbar via
// analyser.ini -> [Detectors] GodHandlerMaxEvents=N).
//
// Quelle der Events: Binding.Events (vom FormBinder bereits extrahiert).
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFormBinder;

type
  TDfmGodHandlerDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

type
  // Pro Handler aggregierter Zustand. ClassRef/EventName kollabieren auf
  // '' sobald eine zweite Klasse/ein zweiter Event-Typ auftaucht - das
  // traegt das Homogenitaets-Gate (Haertung 2026-08-09, User-Entscheid;
  // Stichprobe nach dem Erwecken: 5/6 FP durch parametrisierte
  // Buendelung wie Tag-Farbmenue 26x / Klaviertasten 36x. Heterogene
  // Bindungen bleiben Fund - SynUniDesigner: TEdit.OnChange +
  // TCheckBox.OnClick mit 90-Zeilen-Kaskade war der einzige TP).
  THandlerStat = record
    Count     : Integer;
    Sample    : string;   // Original-Case des Handler-Namens
    FirstLine : Integer;
    ClassRef  : string;   // '' = gemischte Komponenten-Klassen
    EventName : string;   // '' = gemischte Event-Typen
  end;
  THandlerStats = TDictionary<string, THandlerStat>;

procedure CollectHandlerStats(Binding: TFormBinding; Stats: THandlerStats);
var
  Ev      : TBoundEvent;
  St      : THandlerStat;
  Key     : string;
  EvClass : string;
begin
  for Ev in Binding.Events do
  begin
      Key := LowerCase(Ev.HandlerName);
      if Ev.Component <> nil then EvClass := Ev.Component.ClassRef
      else EvClass := '?';
      if Stats.TryGetValue(Key, St) then
      begin
        Inc(St.Count);
        if not SameText(St.ClassRef, EvClass) then St.ClassRef := '';
        if not SameText(St.EventName, Ev.EventName) then St.EventName := '';
      end
      else
      begin
        St.Count     := 1;
        St.Sample    := Ev.HandlerName;
        St.FirstLine := Ev.Line;
        St.ClassRef  := EvClass;
        St.EventName := Ev.EventName;
      end;
    Stats.AddOrSetValue(Key, St);
  end;
end;

procedure ReportGodHandlers(Stats: THandlerStats; Threshold: Integer;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Pair : TPair<string, THandlerStat>;
  St   : THandlerStat;
  F    : TLeakFinding;
begin
  for Pair in Stats do
  begin
    St := Pair.Value;
    if St.Count < Threshold then Continue;
    // Homogen (eine Klasse + ein Event-Typ) = parametrisierte
    // Buendelung -> still.
    if (St.ClassRef <> '') and (St.EventName <> '') then Continue;

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(St.FirstLine);
    F.MissingVar := Format(
      '%s is wired to %d component events (>= %d) - consider splitting',
      [St.Sample, St.Count, Threshold]);
    F.SetKind(fkDfmGodHandler);
    Results.Add(F);
  end;
end;

class procedure TDfmGodHandlerDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Stats     : THandlerStats;
  Threshold : Integer;
begin
  if Binding = nil then Exit;

  Threshold := DetectorMaxGodHandlerEvents;
  if Threshold <= 1 then Threshold := 5;     // Sicherheitsnetz

  Stats := THandlerStats.Create;
  try
    CollectHandlerStats(Binding, Stats);
    ReportGodHandlers(Stats, Threshold, FileName, Results);
  finally
    Stats.Free;
  end;
end;

end.
